# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"
require "open-uri"
require 'digest/sha1'

# A general search and replace tool which uses a configured hash
# and/or a YAML file or a Web service with a YAML response to determine replacement values.
#
# The dictionary entries can be specified in one of three ways: First,
# the `dictionary` configuration item may contain a hash representing
# the mapping. Second, an external YAML file (readable by logstash) may be specified
# in the `dictionary_path` configuration item. These two methods may not be used
# in conjunction; it will produce an error.
# Third, a Web service who your request produces a YML response. This may not be 
# used in conjunction with the first and second method; it will produce an error.
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
  # configuration item (i.e. do not use the `@dictionary_path` YAML file)
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
  # NOTE: it is an error to specify both `dictionary` and `dictionary_path` or `dictionary_url`
  config :dictionary, :validate => :hash,  :default => {}

  # The full path of the external YAML dictionary file. The format of the table
  # should be a standard YAML file. Make sure you specify any integer-based keys
  # in quotes. The YAML file should look something like this:
  # [source,ruby]
  #     "100": Continue
  #     "101": Switching Protocols
  #     merci: gracias
  #     old version: new version
  #     
  # NOTE: it is an error to specify both `dictionary` and `dictionary_path` or `dictionary_url`
  config :dictionary_path, :validate => :path

  # The full URI path of a Web service who generates an yml format response. 
  # The response generated needs to be equals than needed for @dictionary_path
  #
  # NOTE: it is an error to specify both `dictionary` and `dictionary_path` or `dictionary_url`
  config :dictionary_url, :validate => :string

  # When using a dictionary file or url, this setting will indicate how frequently
  # (in seconds) logstash will check the YAML file or url for updates.
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

  public
  def register
    registering = true
    if @dictionary_path
      @next_refresh = Time.now + @refresh_interval
      load_yaml(registering)
    elsif @dictionary_url
      @next_refresh = Time.now + @refresh_interval
      download_yaml(@dictionary_url, registering)
    end
    
    @logger.debug? and @logger.debug("#{self.class.name}: Dictionary - ", :dictionary => @dictionary)
    if @exact
      @logger.debug? and @logger.debug("#{self.class.name}: Dictionary translation method - Exact")
    else
      @logger.debug? and @logger.debug("#{self.class.name}: Dictionary translation method - Fuzzy")
    end
  end # def register

  private
  def load_file(registering, file_name, yaml_data=nil)
    if !File.exists?(file_name)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => file_name)
      return
    end

    begin
      if yaml_data==nil
        yaml_data = YAML.load_file(file_name)
      end
      @dictionary.merge!(yaml_data)
    rescue Exception => e
      if registering
        raise "#{self.class.name}: Bad Syntax in dictionary file #{file_name}"
      else
        @logger.warn("#{self.class.name}: Bad Syntax in dictionary file, continuing with old dictionary", :dictionary_path => file_name)
      end
    end
  end # def load_file

  public
  def load_yaml(registering=false)
    load_file(registering, @dictionary_path)
  end # def load_yaml

  public
  def download_yaml(path, registering=false)
    file_name = Digest::SHA1.hexdigest path;
    File.open(file_name+"_temp.yml", "wb") do |saved_file|
      open(path, "rb") do |read_file|
        saved_file.write(read_file.read)
      end
    end
    begin
      yaml_data = YAML.load_file(file_name+"_temp.yml")
      FileUtils.mv(file_name+"_temp.yml", file_name+".yml")
    rescue Exception => e
      FileUtils.rm_f(file_name+"_temp.yml")
    end
    load_file(registering, file_name+".yml", yaml_data)
  end
  # def download_yaml

  public
  def filter(event)
    

    if @dictionary_path
      if @next_refresh < Time.now
        load_yaml
        @next_refresh = Time.now + @refresh_interval
        @logger.info("refreshing dictionary file")
      end
    elsif @dictionary_url
      if @next_refresh < Time.now
        download_yaml(@dictionary_url)
        @next_refresh = Time.now + @refresh_interval
        @logger.info("downloading and refreshing dictionary file")
      end
    end
    
    return unless event.include?(@field) # Skip translation in case event does not have @event field.
    return if event.include?(@destination) and not @override # Skip translation in case @destination field already exists and @override is disabled.

    begin
      #If source field is array use first value and make sure source value is string
      source = event[@field].is_a?(Array) ? event[@field].first.to_s : event[@field].to_s
      matched = false
      if @exact
        if @regex
          key = @dictionary.keys.detect{|k| source.match(Regexp.new(k))}
          if key
            event[@destination] = @dictionary[key]
            matched = true
          end
        elsif @dictionary.include?(source)
          event[@destination] = @dictionary[source]
          matched = true
        end
      else 
        translation = source.gsub(Regexp.union(@dictionary.keys), @dictionary)
        if source != translation
          event[@destination] = translation.force_encoding(Encoding::UTF_8)
          matched = true
        end
      end

      if not matched and @fallback
        event[@destination] = event.sprintf(@fallback)
        matched = true
      end
      filter_matched(event) if matched or @field == @destination
    rescue Exception => e
      @logger.error("Something went wrong when attempting to translate from dictionary", :exception => e, :field => @field, :event => event)
    end
  end # def filter
end # class LogStash::Filters::Translate
