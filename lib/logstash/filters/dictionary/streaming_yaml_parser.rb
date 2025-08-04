module LogStash module Filters module Dictionary
  class StreamingYamlDictParser
    def snakeYamlEngineV2
      Java::org.snakeyaml.engine.v2
    end

    def snakeYamlEngineV2Events
      snakeYamlEngineV2.events
    end

    def initialize(filename, yaml_code_point_limit)
      settings = snakeYamlEngineV2.api.LoadSettings.builder
        .set_code_point_limit(yaml_code_point_limit)
        .build

      stream = Java::java.io.FileInputStream.new(filename)
      reader = Java::java.io.InputStreamReader.new(stream, Java::java.nio.charset.StandardCharsets::UTF_8)
      stream_reader = snakeYamlEngineV2.scanner.StreamReader.new(reader, settings)

      @parser = snakeYamlEngineV2.parser.ParserImpl.new(stream_reader, settings)

      skip_until(snakeYamlEngineV2Events.MappingStartEvent)
    end


    def each_pair
      while peek_event && !peek_event.is_a?(snakeYamlEngineV2Events.MappingEndEvent)
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
      when snakeYamlEngineV2Events.ScalarEvent
        parse_scalar(event)
      when snakeYamlEngineV2Events.MappingStartEvent
        parse_mapping
      when snakeYamlEngineV2Events.SequenceStartEvent
        parse_sequence
      else
        raise "Unexpected event: #{event.class}"
      end
    end

    def parse_mapping
      hash = {}
      while peek_event && !peek_event.is_a?(snakeYamlEngineV2Events.MappingEndEvent)
        key = parse_node
        value = parse_node
        hash[key] = value
      end
      next_event
      hash
    end

    def parse_sequence
      array = []
      while peek_event && !peek_event.is_a?(snakeYamlEngineV2Events.SequenceEndEvent)
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
