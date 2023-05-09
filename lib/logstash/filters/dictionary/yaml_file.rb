# encoding: utf-8

require_relative "yaml_visitor"

module LogStash module Filters module Dictionary
  class YamlFile < File

    protected

    def initialize_for_file_type(file_max_bytes)
      @visitor = YamlVisitor.create

      @parser = Psych::Parser.new(Psych::TreeBuilder.new)
      @parser.code_point_limit = file_max_bytes
    end

    def read_file_into_dictionary
      # low level YAML read that tries to create as
      # few intermediate objects as possible
      # this overwrites the value at key
      yaml_string = IO.read(@dictionary_path, :mode => 'r:bom|utf-8')
      @parser.parse(yaml_string, @dictionary_path)
      @visitor.accept_with_dictionary(@dictionary, @parser.handler.root)
    end
  end
end end end
