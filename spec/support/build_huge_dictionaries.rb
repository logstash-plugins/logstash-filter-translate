# encoding: utf-8
# frozen_string_literal: true

require "securerandom"

module LogStash module Filters module Dictionary
  def self.create_huge_csv_dictionary(directory, name, size)
    tmppath = directory.join("temp_big.csv")
    tmppath.open("w") do |file|
      file.puts("foo,#{SecureRandom.hex(4)}")
      file.puts("bar,#{SecureRandom.hex(4)}")
      size.times do |i|
        file.puts("#{SecureRandom.hex(12)},#{1000000 + i}")
      end
      file.puts("baz,quux")
    end
    tmppath.rename(directory.join(name))
  end

  def self.create_huge_json_dictionary(directory, name, size)
    tmppath = directory.join("temp_big.json")
    tmppath.open("w") do |file|
      file.puts("{")
      file.puts(%Q(  "foo":"#{SecureRandom.hex(4)}",))
      file.puts(%Q(  "bar":"#{SecureRandom.hex(4)}",))
      size.times do |i|
        file.puts(%Q(  "#{SecureRandom.hex(12)}":"#{1000000 + i}",))
      end
      file.puts('  "baz":"quux"')
      file.puts("}")
    end
    tmppath.rename(directory.join(name))
  end
end end end
