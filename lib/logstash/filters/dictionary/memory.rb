# encoding: utf-8
require "logstash/filters/fetch_strategy/memory"

module LogStash module Filters module Dictionary
  class Memory

    attr_reader :dictionary, :fetch_strategy

    def initialize(hash, exact, regex)
      if exact
        @fetch_strategy = regex ? FetchStrategy::Memory::ExactRegex.new(hash) : FetchStrategy::Memory::Exact.new(hash)
      else
        @fetch_strategy = FetchStrategy::Memory::RegexUnion.new(hash)
      end
    end

    def stop_scheduler
      # noop
    end

    private

    def needs_refresh?
      false
    end

    def load_dictionary(raise_exception=false)
      # noop
    end
  end
end end end
