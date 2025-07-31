java_import 'org.snakeyaml.engine.v2.api.LoadSettings'
java_import 'org.snakeyaml.engine.v2.parser.ParserImpl'
java_import 'org.snakeyaml.engine.v2.scanner.StreamReader'
java_import 'java.io.FileInputStream'
java_import 'java.io.InputStreamReader'
java_import 'java.nio.charset.StandardCharsets'
java_import 'org.snakeyaml.engine.v2.events.MappingStartEvent'
java_import 'org.snakeyaml.engine.v2.events.MappingEndEvent'
java_import 'org.snakeyaml.engine.v2.events.SequenceStartEvent'
java_import 'org.snakeyaml.engine.v2.events.SequenceEndEvent'
java_import 'org.snakeyaml.engine.v2.events.ScalarEvent'

module LogStash module Filters module Dictionary
  class StreamingYamlDictParser
    def initialize(filename, yaml_code_point_limit)
      settings = LoadSettings.builder
        .set_code_point_limit(yaml_code_point_limit)
        .build

      stream = FileInputStream.new(filename)
      reader = InputStreamReader.new(stream, StandardCharsets::UTF_8)
      stream_reader = StreamReader.new(reader, settings)

      @parser = ParserImpl.new(stream_reader, settings)

      skip_until(MappingStartEvent)
    end


    def each_pair
      while peek_event && !peek_event.is_a?(MappingEndEvent)
        key = parse_node
        value = parse_node
        yield(key, value)
      end
    end

    private

    def next_event
      @parser.next
    ensure
      nil
    end

    def peek_event
      @parser.peek_event
    end

    def skip_until(event_class)
      while @parser.has_next
        evt = @parser.next
        return if event_class === evt
      end
    end

    def parse_node
      event = next_event

      case event
      when ScalarEvent
        parse_scalar(event)
      when MappingStartEvent
        parse_mapping
      when SequenceStartEvent
        parse_sequence
      else
        raise "Unexpected event: #{event.class}"
      end
    end

    def parse_mapping
      hash = {}
      while peek_event && !peek_event.is_a?(MappingEndEvent)
        key = parse_node
        value = parse_node
        hash[key] = value
      end
      next_event
      hash
    end

    def parse_sequence
      array = []
      while peek_event && !peek_event.is_a?(SequenceEndEvent)
        array << parse_node
      end
      next_event
      array
    end
    def parse_scalar(scalar)
      value = scalar.value
      # return quoted scalars as they are
      # e.g. don't convert "true" to true
      return value unless scalar.is_plain

      # otherwise let's do some checking and conversions
      case value
      when 'null', '', '~' then nil
      when 'true' then true
      when 'false' then false
      else
        # Try to convert to integer or float
        if value.match?(/\A-?\d+\z/)
          value.to_i
        elsif value.match?(/\A-?\d+\.\d+\z/)
          value.to_f
        else
          value
        end
      end
    end
  end
end end end
