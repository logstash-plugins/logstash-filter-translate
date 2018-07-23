# encoding: utf-8
module LogStash module Filters module Dictionary
  class Memory

    attr_reader :dictionary, :fetch_strategy

    def initialize(hash, exact, regex)
      if exact
        if regex
          @fetch_strategy = FetchStrategy::MemoryExactRegex.new(hash)
        else
          @fetch_strategy = FetchStrategy::MemoryExact.new(hash)
        end
      else
        @fetch_strategy = FetchStrategy::MemoryRegexUnion.new(hash)
      end
    end

    private

    def needs_refresh?
      false
    end

    def load_dictionary(raise_exception=false)
      # noop
    end

    def stop_scheduler
      # noop
    end
  end
end end end
