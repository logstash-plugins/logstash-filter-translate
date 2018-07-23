# encoding: utf-8

module LogStash module Filters module FetchStrategy
  class MemoryExactRegex
    def initialize(dictionary)
      @keys_regex = Hash.new()
      @dictionary = dictionary
      @dictionary.keys.each{|k| @keys_regex[k] = Regexp.new(k)}
    end

    def fetch(source)
      key = @dictionary.keys.detect{|k| source.match(@keys_regex[k])}
      yield LogStash::Util.deep_clone(@dictionary[key]) if key
    end
  end
end end end
