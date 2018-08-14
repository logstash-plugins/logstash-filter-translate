# encoding: utf-8

module LogStash module Filters
  class SingleValueUpdate
    def initialize(field, destination, fallback, lookup)
      @field = field
      @destination = destination
      @fallback = fallback
      @use_fallback = !fallback.nil? # fallback is not nil, the user set a value in the config
      @lookup = lookup
    end

    def test_for_inclusion(event, override)
      # Skip translation in case @destination field already exists and @override is disabled.
      return false if event.include?(@destination) && !override
      event.include?(@field)
    end

    def update(event)
      # If source field is array use first value and make sure source value is string
      source = Array(event.get(@field)).first.to_s
      matched = [true, nil]
      @lookup.fetch_strategy.fetch(source, matched)
      if matched.first
        event.set(@destination, matched.last)
      elsif @use_fallback
        event.set(@destination, event.sprintf(@fallback))
        matched[0] = true
      end
      return matched.first
    end
  end
end end
