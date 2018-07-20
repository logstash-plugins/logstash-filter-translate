# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"

require "logstash/filters/translate"
require "benchmark/ips"

module BenchmarkingFileBuilder
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
end

describe LogStash::Filters::Translate do
  let(:directory) { Pathname.new(Stud::Temporary.directory) }
  let(:dictionary_name) { "dict-h.csv" }
  let(:dictionary_path) { directory.join(dictionary_name) }
  let(:dictionary_size) { 100000 }
  let(:config) do
    {
      "field"       => "[status]",
      "destination" => "[translation]",
      "dictionary_path"  => dictionary_path.to_path,
      "exact"       => true,
      "regex"       => false,
      "refresh_interval" => 0,
      "override" => true,
      "refresh_behaviour" => "merge"
    }
  end
  before do
    directory
    BenchmarkingFileBuilder.create_huge_csv_dictionary(directory, dictionary_name, dictionary_size)
  end

  it 'dude, do you even bench?' do
    plugin = described_class.new(config)
    plugin.register
    event = LogStash::Event.new("status" => "baz", "translation" => "foo")

    report = Benchmark.ips do |x|
      x.config(:time => 20, :warmup => 120)
      x.report("filter(event)") { plugin.filter(event) }
    end
    expect(report).not_to be_nil
  end
end
