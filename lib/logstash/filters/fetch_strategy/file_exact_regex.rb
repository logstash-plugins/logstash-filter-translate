# encoding: utf-8

module LogStash module Filters module FetchStrategy
  class FileExactRegex
    def initialize(dictionary, rw_lock)
      @keys_regex = Hash.new()
      @dictionary = dictionary
      @read_lock = rw_lock.readLock
    end

    def dictionary_updated
      @keys_regex.clear
      # rebuilding the regex map is time expensive
      # 100 000 keys takes 0.5 seconds on a high spec Macbook Pro
      # at least we are not doing it for every event like before
      @dictionary.keys.each{|k| @keys_regex[k] = Regexp.new(k)}
    end

    def fetch(source)
      @read_lock.lock
      begin
        key = @dictionary.keys.detect{|k| source.match(@keys_regex[k])}
        yield LogStash::Util.deep_clone(@dictionary[key]) if key
      ensure
        @read_lock.unlock
      end
    end
  end
end end end
