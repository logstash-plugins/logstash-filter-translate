# encoding: utf-8

module LogStash module Filters module Dictionary
  class Memory
    attr_reader :dictionary

    def initialize(hash, exact, regex)
      @dictionary = hash
      @exact = exact
      @regex = regex
      if @exact
        using_regex_map if @regex
      else
        using_regex_union
      end
    end

    def fetch(source)
      if @exact
        if @regex
          key = @dictionary.keys.detect{|k| source.match(@keys_regex[k])}
          yield deep_clone(@dictionary[key]) if key
        else
          yield deep_clone(@dictionary[source]) if @dictionary.include?(source)
        end
      else
        value = source.gsub(@union_regex_keys, @dictionary)
        yield deep_clone(value) if source != value
      end
    end

    private

    def using_regex_map
      @keys_regex = Hash.new
      @dictionary.keys.each{|k| @keys_regex[k] = Regexp.new(k)}
    end

    def using_regex_union
      @union_regex_keys = Regexp.union(@dictionary.keys)
    end

    def needs_refresh?
      false
    end

    def load_dictionary(raise_exception=false)
      # noop
    end

    def stop_scheduler
      # noop
    end

    def deep_clone(value)
      # prevent other filters from mutating the dictionary value itself
      LogStash::Util.deep_clone(value)
    end
  end
end end end
