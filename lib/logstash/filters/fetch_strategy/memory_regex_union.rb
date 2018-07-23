# encoding: utf-8

module LogStash module Filters module FetchStrategy
  class MemoryRegexUnion
    def initialize(dictionary)
      @dictionary = dictionary
      @union_regex_keys = Regexp.union(@dictionary.keys)
    end

    def fetch(source)
      value = source.gsub(@union_regex_keys, @dictionary)
      yield LogStash::Util.deep_clone(value) if source != value
    end
  end
end end end
