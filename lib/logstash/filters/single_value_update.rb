# encoding: utf-8

module LogStash module Filters
  class SingleValueUpdate
    def initialize(field, destination, fallback, lookup)
      @field = field
      @destination = destination
      @fallback = fallback
      @use_fallback = !fallback.nil?
      @lookup = lookup
    end

    def test_for_inclusion(event, override)
      # Skip translation in case event does not have @event field.
      return true if event.include?(@field)
      # Skip translation in case @destination field already exists and @override is disabled.
      return true if event.include?(@destination) && override
      false
    end

    def update(event)
      val = event.get(@field)
      source = val.is_a?(Array) ? val.first.to_s : val.to_s
      matched = false
      @lookup.fetch(source) do |value|
        event.set(@destination, value)
        matched = true
      end

      if @use_fallback && !matched
        event.set(@destination, event.sprintf(@fallback))
        matched = true
      end
      return matched
    end
  end
end end
