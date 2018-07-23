# encoding: utf-8

module LogStash module Filters module FetchStrategy
  class FileExact
    def initialize(dictionary, rw_lock)
      @dictionary = dictionary
      @read_lock = rw_lock.readLock
    end

    def dictionary_updated
    end

    def fetch(source)
      @read_lock.lock
      begin
        yield LogStash::Util.deep_clone(@dictionary[source]) if @dictionary.include?(source)
      ensure
        @read_lock.unlock
      end
    end
  end
end end end
