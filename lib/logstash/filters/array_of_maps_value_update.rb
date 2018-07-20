# encoding: utf-8

module LogStash module Filters
  class ArrayOfMapsValueUpdate
    def initialize(foreach, field, destination, fallback, lookup)
      @foreach = ensure_reference_format(foreach)
      @field = ensure_reference_format(field)
      @destination = ensure_reference_format(destination)
      @fallback = fallback
      @use_fallback = !fallback.nil?
      @lookup = lookup
    end

    def test_for_inclusion(event, override)
      # Skip translation in case event does not have @event field.
      return true if event.include?(@foreach)
      false
    end

    def update(event)
      val = event.get(@foreach) # should be an array of hashes
      source = Array(val)
      matches = Array.new(source.size)
      source.size.times do |index|
        nested_field = "#{@foreach}[#{index}]#{@field}"
        nested_destination = "#{@foreach}[#{index}]#{@destination}"
        inner = event.get(nested_field)
        @lookup.fetch(inner) do |value|
          event.set(nested_destination, value)
          matches[index] = true
        end
        if @use_fallback && !matches[index]
          event.set(nested_destination, event.sprintf(@fallback))
          matches[index] = true
        end
      end
      return matches.any?
    end

    def ensure_reference_format(field)
      field.start_with?("[") && field.end_with?("]") ? field : "[#{field}]"
    end
  end
end end
