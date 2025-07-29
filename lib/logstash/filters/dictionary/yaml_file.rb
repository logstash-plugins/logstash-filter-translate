# encoding: utf-8

require_relative "yaml_visitor"
require_relative "streaming_yaml_parser"

module LogStash module Filters module Dictionary
  class YamlFile < File

    protected

    def initialize_for_file_type(**file_type_args)
      @yaml_code_point_limit = file_type_args[:yaml_code_point_limit]
    end

    def read_file_into_dictionary
      if ENV['YAML_PARSER'] == 'psych'
        visitor = YamlVisitor.create
        parser = Psych::Parser.new(Psych::TreeBuilder.new)
        parser.code_point_limit = @yaml_code_point_limit
        # low level YAML read that tries to create as
        # few intermediate objects as possible
        # this overwrites the value at key
        yaml_string = IO.read(@dictionary_path, :mode => 'r:bom|utf-8')
        parser.parse(yaml_string, @dictionary_path)
        visitor.accept_with_dictionary(@dictionary, parser.handler.root)
        sleep 100
      else
        parser = StreamingYamlDictParser.new(@dictionary_path)

        parser.each_pair do |key, value|
          @dictionary[key] = value
        end
        sleep 100
      end
    end
  end
end end end
