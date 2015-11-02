# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# A general search and replace tool which uses a configured hash
# and/or a YAML file to determine replacement values.
#
# The dictionary entries can be specified in one of two ways: First,
# the `dictionary` configuration item may contain a hash representing
# the mapping. Second, an external YAML file (readable by logstash) may be specified
# in the `dictionary_path` configuration item. These two methods may not be used
# in conjunction; it will produce an error.
#
# Operationally, if the event field specified in the `field` configuration
# matches the EXACT contents of a dictionary entry key (or matches a regex if
# `regex` configuration item has been enabled), the field's value will be substituted
# with the matched key's value from the dictionary.
#
# By default, the translate filter will put the translated value in
# [source field]_translated. However, by using the `destination`
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
  # If this field is an array then the plugin will iterate over the full array and
  # store the translated values in the same position in the destination field.
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
  # NOTE: it is an error to specify both `dictionary` and `dictionary_path`
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
  # NOTE: it is an error to specify both `dictionary` and `dictionary_path`
  config :dictionary_path, :validate => :path

  # When using a dictionary file, this setting will indicate how frequently
  # (in seconds) logstash will check the YAML file for updates.
  config :refresh_interval, :validate => :number, :default => 300
  
  # The destination field you wish to populate with the translated code. If not set
  # [source field]_translation will the destination field. Set this to the same value
  # as source and set override to true if you want to do a substitution, in this case
  # filter will allways succeed. This will clobber the old value of the source field!
  config :destination, :validate => :string

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
    if @dictionary_path
      @next_refresh = Time.now + @refresh_interval
      registering = true
      load_yaml(registering)
    end
    
    @logger.debug? and @logger.debug("#{self.class.name}: Dictionary - ", :dictionary => @dictionary)
    if @exact
      @logger.debug? and @logger.debug("#{self.class.name}: Dictionary translation method - Exact")
    else
      @logger.debug? and @logger.debug("#{self.class.name}: Dictionary translation method - Fuzzy")
    end
  end # def register

  private
  def load_yaml(registering=false)
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end

    begin
      @dictionary.merge!(YAML.load_file(@dictionary_path))
    rescue Exception => e
      if registering
        raise "#{self.class.name}: Bad Syntax in dictionary file #{@dictionary_path}"
      else
        @logger.warn("#{self.class.name}: Bad Syntax in dictionary file, continuing with old dictionary", :dictionary_path => @dictionary_path)
      end
    end
  end

  private
  def match_event(source, event)
    event_item = ''

    if @exact
      if @regex
        key = @dictionary.keys.detect{|k| source.match(Regexp.new(k))}
        if key
          event_item = @dictionary[key]
          matched = true
        end
      elsif @dictionary.include?(source)
        event_item = @dictionary[source]
        matched = true
      end
    else
      translation = source.gsub(Regexp.union(@dictionary.keys), @dictionary)
      if source != translation
        event_item = translation
        matched = true
      end
    end
    if  !matched && @fallback
      event_item = event.sprintf(@fallback)
      matched = true
    end
    return event_item, matched
  end

  private
  def determine_field_type(event)
    #Check if field is an array
    if event[@field].is_a?(Array)
      #Field is an array, walk it
      event[@field].each_with_index do |source, index|
        event[@destination] ||= []
        event_item,matched = match_event(source.to_s, event)
        event[@destination][index] = event_item if matched
      end

    else
      #Field is not an array
      event_item,matched = match_event(event[@field].to_s, event)
      event[@destination] = event_item.force_encoding(Encoding::UTF_8) if matched
    end

    filter_matched(event) if matched or @field == @destination
  end

  public
  def filter(event)
    

    if @dictionary_path
      if @next_refresh < Time.now
        load_yaml
        @next_refresh = Time.now + @refresh_interval
        @logger.info("refreshing dictionary file")
      end
    end

    #if destination is not set default to #{@field}_translation
    @destination ||= "#{@field}_translation"
    
    return unless event.include?(@field) # Skip translation in case event does not have @event field.
    return if event.include?(@destination) &&  !@override # Skip translation in case @destination field already exists and @override is disabled.

    begin
      determine_field_type(event)

    rescue => e
      @logger.error("Something went wrong when attempting to translate from dictionary", :exception => e, :field => @field, :event => event)
    end
  end # def filter
end # class LogStash::Filters::Translate
