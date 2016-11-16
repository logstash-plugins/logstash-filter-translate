# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "csv"

java_import 'java.util.concurrent.locks.ReentrantReadWriteLock'


# A general search and replace tool that uses a configured hash
# and/or a file to determine replacement values. Currently supported are 
# YAML, JSON, and CSV files.
#
# The dictionary entries can be specified in one of two ways: First,
# the `dictionary` configuration item may contain a hash representing
# the mapping. Second, an external file (readable by logstash) may be specified
# in the `dictionary_path` configuration item. These two methods may not be used
# in conjunction; it will produce an error.
#
# Operationally, if the event field specified in the `field` configuration
# matches the EXACT contents of a dictionary entry key (or matches a regex if
# `regex` configuration item has been enabled), the field's value will be substituted
# with the matched key's value from the dictionary.
#
# By default, the translate filter will replace the contents of the 
# maching event field (in-place). However, by using the `destination`
# configuration item, you may also specify a target event field to
# populate with the new translated value.
# 
# Alternatively, for simple string search and replacements for just a few values
# you might consider using the gsub function of the mutate filter.

class LogStash::Filters::Translate < LogStash::Filters::Base
  config_name "translate"

  # The name of the logstash event field containing the value to be compared for a
  # match by the translate filter (e.g. `message`, `host`, `response_code`). 
  # 
  # If this field is an array, only the first value will be used.
  config :field, :validate => :string, :required => true

  # If the destination (or target) field already exists, this configuration item specifies
  # whether the filter should skip translation (default) or overwrite the target field
  # value with the new translation value.
  config :override, :validate => :boolean, :default => false

  # The dictionary to use for translation, when specified in the logstash filter
  # configuration item (i.e. do not use the `@dictionary_path` file).
  #
  # Example:
  # [source,ruby]
  #     filter {
  #       %PLUGIN% {
  #         dictionary => [ "100", "Continue",
  #                         "101", "Switching Protocols",
  #                         "merci", "thank you",
  #                         "old version", "new version" ]
  #       }
  #     }
  #
  # NOTE: It is an error to specify both `dictionary` and `dictionary_path`.
  config :dictionary, :validate => :hash,  :default => {}

  # The full path of the external dictionary file. The format of the table
  # should be a standard YAML, JSON, or CSV. Make sure you specify any integer-based keys
  # in quotes. For example, the YAML file should look something like this:
  # [source,ruby]
  #     "100": Continue
  #     "101": Switching Protocols
  #     merci: gracias
  #     old version: new version
  #
  # NOTE: it is an error to specify both `dictionary` and `dictionary_path`.
  #
  # The currently supported formats are YAML, JSON, and CSV. Format selection is
  # based on the file extension: `json` for JSON, `yaml` or `yml` for YAML, and
  # `csv` for CSV. The JSON format only supports simple key/value, unnested
  # objects. The CSV format expects exactly two columns, with the first serving
  # as the original text, and the second column as the replacement.
  config :dictionary_path, :validate => :path

  # When using a dictionary file, this setting will indicate how frequently
  # (in seconds) logstash will check the dictionary file for updates.
  config :refresh_interval, :validate => :number, :default => 300

  # The destination field you wish to populate with the translated code. The default
  # is a field named `translation`. Set this to the same value as source if you want
  # to do a substitution, in this case filter will allways succeed. This will clobber
  # the old value of the source field! 
  config :destination, :validate => :string, :default => "translation"

  # When `exact => true`, the translate filter will populate the destination field
  # with the exact contents of the dictionary value. When `exact => false`, the
  # filter will populate the destination field with the result of any existing
  # destination field's data, with the translated value substituted in-place.
  #
  # For example, consider this simple translation.yml, configured to check the `data` field:
  # [source,ruby]
  #     foo: bar
  #
  # If logstash receives an event with the `data` field set to `foo`, and `exact => true`,
  # the destination field will be populated with the string `bar`.

  # If `exact => false`, and logstash receives the same event, the destination field
  # will be also set to `bar`. However, if logstash receives an event with the `data` field
  # set to `foofing`, the destination field will be set to `barfing`.
  #
  # Set both `exact => true` AND `regex => `true` if you would like to match using dictionary
  # keys as regular expressions. A large dictionary could be expensive to match in this case. 
  config :exact, :validate => :boolean, :default => true

  # If you'd like to treat dictionary keys as regular expressions, set `exact => true`.
  # Note: this is activated only when `exact => true`.
  config :regex, :validate => :boolean, :default => false

  # In case no translation occurs in the event (no matches), this will add a default
  # translation string, which will always populate `field`, if the match failed.
  #
  # For example, if we have configured `fallback => "no match"`, using this dictionary:
  # [source,ruby]
  #     foo: bar
  #
  # Then, if logstash received an event with the field `foo` set to `bar`, the destination
  # field would be set to `bar`. However, if logstash received an event with `foo` set to `nope`,
  # then the destination field would still be populated, but with the value of `no match`.
  # This configuration can be dynamic and include parts of the event using the `%{field}` syntax.
  config :fallback, :validate => :string

  def register
    rw_lock = java.util.concurrent.locks.ReentrantReadWriteLock.new
    @read_lock = rw_lock.readLock
    @write_lock = rw_lock.writeLock
    
    if @dictionary_path && !@dictionary.empty?
      raise LogStash::ConfigurationError, I18n.t(
        "logstash.agent.configuration.invalid_plugin_register",
        :plugin => "filter",
        :type => "translate",
        :error => "The configuration options 'dictionary' and 'dictionary_path' are mutually exclusive"
      )
    end

    if @dictionary_path
      @next_refresh = Time.now + @refresh_interval
      raise_exception = true
      lock_for_write { load_dictionary(raise_exception) }
    end

    @logger.debug? and @logger.debug("#{self.class.name}: Dictionary - ", :dictionary => @dictionary)
    if @exact
      @logger.debug? and @logger.debug("#{self.class.name}: Dictionary translation method - Exact")
    else
      @logger.debug? and @logger.debug("#{self.class.name}: Dictionary translation method - Fuzzy")
    end
  end # def register

  def lock_for_read
    @read_lock.lock
    begin
      yield
    ensure
      @read_lock.unlock
    end
  end

  def lock_for_write
    @write_lock.lock
    begin
      yield
    ensure
      @write_lock.unlock
    end
  end

  def filter(event)
    if @dictionary_path
      if needs_refresh?
        lock_for_write do
          if needs_refresh?
            load_dictionary
            @next_refresh = Time.now + @refresh_interval
            @logger.info("refreshing dictionary file")
          end
        end
      end
    end

    return unless event.include?(@field) # Skip translation in case event does not have @event field.
    return if event.include?(@destination) and not @override # Skip translation in case @destination field already exists and @override is disabled.

    begin
      #If source field is array use first value and make sure source value is string
      source = event.get(@field).is_a?(Array) ? event.get(@field).first.to_s : event.get(@field).to_s
      matched = false
      if @exact
        if @regex
          key = @dictionary.keys.detect{|k| source.match(Regexp.new(k))}
          if key
            event.set(@destination, lock_for_read { @dictionary[key] })
            matched = true
          end
        elsif @dictionary.include?(source)
          event.set(@destination, lock_for_read { @dictionary[source] })
          matched = true
        end
      else
        translation = lock_for_read { source.gsub(Regexp.union(@dictionary.keys), @dictionary) }
        
        if source != translation
          event.set(@destination, translation.force_encoding(Encoding::UTF_8))
          matched = true
        end
      end

      if not matched and @fallback
        event.set(@destination, event.sprintf(@fallback))
        matched = true
      end
      filter_matched(event) if matched or @field == @destination
    rescue Exception => e
      @logger.error("Something went wrong when attempting to translate from dictionary", :exception => e, :field => @field, :event => event)
    end
  end # def filter

  private

  def load_dictionary(raise_exception=false)
    if /.y[a]?ml$/.match(@dictionary_path)
      load_yaml(raise_exception)
    elsif @dictionary_path.end_with?(".json")
      load_json(raise_exception)
    elsif @dictionary_path.end_with?(".csv")
      load_csv(raise_exception)
    else
      raise "#{self.class.name}: Dictionary #{@dictionary_path} have a non valid format"
    end
  rescue => e
    loading_exception(e, raise_exception)
  end

  def load_yaml(raise_exception=false)
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
    merge_dictionary!(YAML.load_file(@dictionary_path), raise_exception)
  end

  def load_json(raise_exception=false)
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
    merge_dictionary!(JSON.parse(File.read(@dictionary_path)), raise_exception)
  end

  def load_csv(raise_exception=false)
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
    data = CSV.read(@dictionary_path).inject(Hash.new) do |acc, v|
      acc[v[0]] = v[1]
      acc
    end
    merge_dictionary!(data, raise_exception)
  end

  def merge_dictionary!(data, raise_exception=false)
    @dictionary.merge!(data)
  end

  def loading_exception(e, raise_exception=false)
    msg = "#{self.class.name}: #{e.message} when loading dictionary file at #{@dictionary_path}"
    if raise_exception
      raise RuntimeError.new(msg)
    else
      @logger.warn("#{msg}, continuing with old dictionary", :dictionary_path => @dictionary_path)
    end
  end

  def needs_refresh?
    @next_refresh < Time.now
  end
end # class LogStash::Filters::Translate
