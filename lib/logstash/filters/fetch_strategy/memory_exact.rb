# encoding: utf-8

module LogStash module Filters module FetchStrategy
  class MemoryExact
    def initialize(dictionary)
      @dictionary = dictionary
    end

    def fetch(source)
      yield LogStash::Util.deep_clone(@dictionary[source]) if @dictionary.include?(source)
    end
  end
end end end
