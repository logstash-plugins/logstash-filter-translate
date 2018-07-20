# encoding: utf-8

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
    end
    tmppath.rename(directory.join(name))
  end

  def self.create_huge_json_dictionary(directory, name, size)
    tmppath = directory.join("temp_big.json")
    tmppath.open("w") do |file|
      file.puts("{")
      file.puts('  "foo":"'.concat(SecureRandom.hex(4)).concat('",'))
      file.puts('  "bar":"'.concat(SecureRandom.hex(4)).concat('",'))
      size.times do |i|
        file.puts('  "'.concat(SecureRandom.hex(12)).concat('":"').concat("#{1000000 + i}").concat('",'))
      end
      file.puts('  "baz":"'.concat(SecureRandom.hex(4)).concat('"'))
      file.puts("}")
    end
    tmppath.rename(directory.join(name))
  end
end end end
