# encoding: utf-8
require 'rspec/wait'
require "logstash/devutils/rspec/spec_helper"
require "support/rspec_wait_handler_helper"
require "support/build_huge_dictionaries"

require "rspec_sequencing"

require "logstash/filters/translate"

describe LogStash::Filters::Translate do
  let(:directory) { Pathname.new(Stud::Temporary.directory) }
  describe "scheduled reloading" do
    subject { described_class.new(config) }

    let(:config) do
      {
        "field"       => "[status]",
        "destination" => "[translation]",
        "dictionary_path"  => dictionary_path.to_path,
        "exact"       => true,
        "regex"       => false,
        "refresh_interval" => 1,
        "override" => true,
        "refresh_behaviour" => refresh_behaviour
      }
    end

    let(:event) { LogStash::Event.new("status" => "b") }

    before do
      directory
      wait(1.0).for{Dir.exist?(directory)}.to eq(true)
      dictionary_path.open("wb") do |file|
        file.puts("a,1\nb,2\nc,3\n")
      end
      subject.register
    end

    after do
      FileUtils.rm_rf(directory)
      wait(1.0).for{Dir.exist?(directory)}.to eq(false)
    end

    context "replace" do
      let(:dictionary_path) { directory.join("dict-r.csv") }
      let(:refresh_behaviour) { "replace" }
      let(:actions) do
        RSpec::Sequencing
          .run("translate") do
            subject.filter(event)
            wait(0.1).for{event.get("[translation]")}.to eq("2"), "field [translation] did not eq '2'"
          end
          .then_after(1,"modify file") do
            dictionary_path.open("w") do |file|
              file.puts("a,11\nb,12\nc,13\n")
            end
          end
          .then_after(1.2, "wait then translate again") do
            subject.filter(event)
            wait(0.1).for{event.get("[translation]")}.to eq("12"), "field [translation] did not eq '12'"
          end
          .then("stop") do
            subject.close
          end
      end

      it "updates the event after scheduled reload" do
        actions.activate_quietly
        actions.assert_no_errors
      end
    end

    context "merge" do
      let(:dictionary_path) { directory.join("dict-m.csv") }
      let(:refresh_behaviour) { "merge" }
      let(:actions) do
        RSpec::Sequencing
          .run("translate") do
            subject.filter(event)
            wait(0.1).for{event.get("[translation]")}.to eq("2"), "field [translation] did not eq '2'"
          end
          .then_after(1,"modify file") do
            dictionary_path.open("w") do |file|
              file.puts("a,21\nb,22\nc,23\n")
            end
          end
          .then_after(1.2, "wait then translate again") do
            subject.filter(event)
            wait(0.1).for{event.get("[translation]")}.to eq("22"), "field [translation] did not eq '22'"
          end
          .then("stop") do
            subject.close
          end
      end

      it "updates the event after scheduled reload" do
        actions.activate_quietly
        actions.assert_no_errors
      end
    end
  end

  describe "huge json file merge" do
    let(:dictionary_path) { directory.join("dict-h.json") }
    let(:dictionary_size) { 100000 }
    let(:config) do
      {
        "field"       => "[status]",
        "destination" => "[translation]",
        "dictionary_path"  => dictionary_path.to_path,
        "exact"       => true,
        "regex"       => false,
        "refresh_interval" => 1,
        "override" => true,
        "refresh_behaviour" => "merge"
      }
    end
    let(:event) { LogStash::Event.new("status" => "baz", "translation" => "foo") }
    subject { described_class.new(config) }

    before do
      directory
      wait(1.0).for{Dir.exist?(directory)}.to eq(true)
      LogStash::Filters::Dictionary.create_huge_json_dictionary(directory, "dict-h.json", dictionary_size)
      subject.register
    end

    let(:actions) do
      RSpec::Sequencing
        .run("translate") do
          subject.filter(event)
          wait(0.1).for{event.get("[translation]")}.not_to eq("foo"), "field [translation] should not be 'foo'"
        end
        .then_after(0.1,"modify file") do
          LogStash::Filters::Dictionary.create_huge_json_dictionary(directory, "dict-h.json", dictionary_size)
        end
        .then_after(1.8, "wait then translate again") do
          subject.filter(event)
          wait(0.1).for{event.get("[translation]")}.not_to eq("foo"), "field [translation] should not be 'foo'"
        end
        .then("stop") do
          subject.close
        end
    end

    it "updates the event after scheduled reload" do
      actions.activate_quietly
      actions.assert_no_errors
    end
  end

  describe "huge csv file merge" do
    let(:dictionary_path) { directory.join("dict-h.csv") }
    let(:dictionary_size) { 100000 }
    let(:config) do
      {
        "field"       => "[status]",
        "destination" => "[translation]",
        "dictionary_path"  => dictionary_path.to_path,
        "exact"       => true,
        "regex"       => false,
        "refresh_interval" => 1,
        "override" => true,
        "refresh_behaviour" => "merge"
      }
    end
    let(:event) { LogStash::Event.new("status" => "bar", "translation" => "foo") }
    subject { described_class.new(config) }

    before do
      directory
      wait(1.0).for{Dir.exist?(directory)}.to eq(true)
      LogStash::Filters::Dictionary.create_huge_csv_dictionary(directory, "dict-h.csv", dictionary_size)
      subject.register
    end

    let(:actions) do
      RSpec::Sequencing
        .run("translate") do
          subject.filter(event)
          wait(0.1).for{event.get("[translation]")}.not_to eq("foo"), "field [translation] should not be 'foo'"
        end
        .then_after(0.1,"modify file") do
          LogStash::Filters::Dictionary.create_huge_csv_dictionary(directory, "dict-h.csv", dictionary_size)
        end
        .then_after(1.8, "wait then translate again") do
          subject.filter(event)
          wait(0.1).for{event.get("[translation]")}.not_to eq("foo"), "field [translation] should not be 'foo'"
        end
        .then("stop") do
          subject.close
        end
    end

    it "updates the event after scheduled reload" do
      actions.activate_quietly
      actions.assert_no_errors
    end
  end
end
