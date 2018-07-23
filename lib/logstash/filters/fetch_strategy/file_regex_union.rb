# encoding: utf-8

module LogStash module Filters module FetchStrategy
  class FileRegexUnion
    def initialize(dictionary, rw_lock)
      @dictionary = dictionary
      @read_lock = rw_lock.readLock
    end

    def dictionary_updated
      @union_regex_keys = Regexp.union(@dictionary.keys)
    end

    def fetch(source)
      @read_lock.lock
      begin
        value = source.gsub(@union_regex_keys, @dictionary)
        yield LogStash::Util.deep_clone(value) if source != value
      ensure
        @read_lock.unlock
      end
    end
  end
end end end
