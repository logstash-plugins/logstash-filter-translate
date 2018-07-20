# encoding: utf-8

module LogStash module Filters
  class ArrayOfValuesUpdate
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
      source = Array(val)

      target = Array.new(source.size)
      if @use_fallback
        target.fill(event.sprintf(@fallback))
      end
      source.each_with_index do |inner, index|
        @lookup.fetch(inner) do |value|
          target[index] = value
        end
      end
      event.set(@destination, target)
      return target.any?
    end
  end
end end
