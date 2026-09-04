# encoding: utf-8
# frozen_string_literal: true
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
        "source"      => "[status]",
        "target"      => "[translation]",
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
      allow(subject.lookup).to receive(:logger).and_return(double("LookupLogger").as_null_object)
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
            try(5) do
              subject.filter(event)
              wait(0.5).for{event.get("[translation]")}.to eq("12"), "field [translation] did not eq '12'"
            end
          end
          .then("stop") do
            subject.close
          end
      end

      it "updates the event after scheduled reload" do
        actions.activate_quietly
        actions.assert_no_errors
      end

      it 'uses the replacement dictionary after reload' do
        actions = RSpec::Sequencing
          .run("translate") do
            event_a = LogStash::Event.new("status" => "a" )
            event_b = LogStash::Event.new("status" => "b" )
            event_c = LogStash::Event.new("status" => "c" )
            event_d = LogStash::Event.new("status" => "d" )

            subject.multi_filter([event_a, event_b, event_c, event_d])

            expect(event_a.get("translation")).to eq('1')
            expect(event_b.get("translation")).to eq('2')
            expect(event_c.get("translation")).to eq('3')
            expect(event_d.get("translation")).to be_nil
          end
          .then("modify file with new CSV") do
            dictionary_path.open("w") do |file|
              file.puts("a,11\nb,12\nd,14\n") # changes a+b, removes c, adds d
            end
          end
          .then_after(2, "translate again, ensuring we use the replacement dictionary") do

            event_a = LogStash::Event.new("status" => "a" )
            event_b = LogStash::Event.new("status" => "b" )
            event_c = LogStash::Event.new("status" => "c" )
            event_d = LogStash::Event.new("status" => "d" )

            subject.multi_filter([event_a, event_b, event_c, event_d])

            expect(event_a.get("translation")).to eq('11')
            expect(event_b.get("translation")).to eq('12')
            expect(event_c.get("translation")).to be_nil # not present in updated dict
            expect(event_d.get("translation")).to eq('14')
          end
          .then("stop") do
            subject.close
          end

        actions.activate_quietly
        actions.assert_no_errors
      end

      context "when replacement file is corrupt" do

        it "logs a warning with the parse error but keeps processing with existing definitions" do
          actions = RSpec::Sequencing
            .run("translate") do
              event_a = LogStash::Event.new("status" => "a" )
              event_b = LogStash::Event.new("status" => "b" )
              event_c = LogStash::Event.new("status" => "c" )
              event_d = LogStash::Event.new("status" => "d" )

              subject.multi_filter([event_a, event_b, event_c, event_d])

              expect(event_a.get("translation")).to eq('1')
              expect(event_b.get("translation")).to eq('2')
              expect(event_c.get("translation")).to eq('3')
              expect(event_d.get("translation")).to be_nil
            end
            .then("modify file with invalid CSV") do
              dictionary_path.open("w") do |file|
                file.puts("a,11\nb,12\n\"\xFF".dup.force_encoding("UTF-8")) # intentional broken utf-8
              end
            end
            .then_after(2, "wait for dictionary reload attempt and ensure logs were emitted") do
              wait_for { subject.lookup.logger }.to have_received(:warn).with(/continuing with old dictionary/, anything)
            end
            .then("translate again, ensuring we still use the old dictionary") do

              event_a = LogStash::Event.new("status" => "a" )
              event_b = LogStash::Event.new("status" => "b" )
              event_c = LogStash::Event.new("status" => "c" )
              event_d = LogStash::Event.new("status" => "d" )

              subject.multi_filter([event_a, event_b, event_c, event_d])

              expect(event_a.get("translation")).to eq('1')
              expect(event_b.get("translation")).to eq('2')
              expect(event_c.get("translation")).to eq('3')
              expect(event_d.get("translation")).to be_nil
            end
            .then("stop") do
              subject.close
            end
          actions.activate_quietly
          actions.assert_no_errors
        end
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
            try(5) do
              subject.filter(event)
              wait(0.5).for{event.get("[translation]")}.to eq("22"), "field [translation] did not eq '22'"
            end
          end
          .then("stop") do
            subject.close
          end
      end

      it "updates the event after scheduled reload" do
        actions.activate_quietly
        actions.assert_no_errors
      end

      it 'uses the merged dictionary after reload' do
        actions = RSpec::Sequencing
          .run("translate") do
            event_a = LogStash::Event.new("status" => "a" )
            event_b = LogStash::Event.new("status" => "b" )
            event_c = LogStash::Event.new("status" => "c" )
            event_d = LogStash::Event.new("status" => "d" )

            subject.multi_filter([event_a, event_b, event_c, event_d])

            expect(event_a.get("translation")).to eq('1')
            expect(event_b.get("translation")).to eq('2')
            expect(event_c.get("translation")).to eq('3')
            expect(event_d.get("translation")).to be_nil
          end
          .then("modify file with new CSV") do
            dictionary_path.open("w") do |file|
              file.puts("a,11\nb,12\nd,14\n") # changes a+b, removes c, adds d
            end
          end
          .then_after(1.2, "wait the scheduler load the new definition") do
            try(5) do                         # ← retries up to 5 times
              flag_event = LogStash::Event.new("status" => "a" )
              subject.filter(flag_event)
              wait(0.5).for { flag_event.get("translation") }.to eq("11")
            end
          end
          .then_after(2, "translate again, ensuring we use the merged dictionary") do
            event_a = LogStash::Event.new("status" => "a" )
            event_b = LogStash::Event.new("status" => "b" )
            event_c = LogStash::Event.new("status" => "c" )
            event_d = LogStash::Event.new("status" => "d" )

            subject.multi_filter([event_a, event_b, event_c, event_d])

            expect(event_a.get("translation")).to eq('11')
            expect(event_b.get("translation")).to eq('12')
            expect(event_c.get("translation")).to eq('3') # deleted in update, uses old value after merge
            expect(event_d.get("translation")).to eq('14')
          end
          .then("stop") do
            subject.close
          end
        actions.activate_quietly
        actions.assert_no_errors
      end

      context "when replacement file is corrupt" do

        it "logs a warning with the parse error but keeps processing with existing definitions" do
          actions = RSpec::Sequencing
            .run("translate") do
              event_a = LogStash::Event.new("status" => "a" )
              event_b = LogStash::Event.new("status" => "b" )
              event_c = LogStash::Event.new("status" => "c" )
              event_d = LogStash::Event.new("status" => "d" )

              subject.multi_filter([event_a, event_b, event_c, event_d])

              expect(event_a.get("translation")).to eq('1')
              expect(event_b.get("translation")).to eq('2')
              expect(event_c.get("translation")).to eq('3')
              expect(event_d.get("translation")).to be_nil
            end
            .then("modify file with invalid CSV") do
              dictionary_path.open("w") do |file|
                file.puts("a,11\nb,12\n\"\xFF".dup.force_encoding("UTF-8")) # intentional broken utf-8
              end
            end
            .then_after(2, "wait for dictionary reload attempt and ensure logs were emitted") do
              wait_for { subject.lookup.logger }.to have_received(:warn).with(/continuing with old dictionary/, anything)
            end
            .then("translate again, ensuring we still use the old dictionary") do
              event_a = LogStash::Event.new("status" => "a" )
              event_b = LogStash::Event.new("status" => "b" )
              event_c = LogStash::Event.new("status" => "c" )
              event_d = LogStash::Event.new("status" => "d" )

              subject.multi_filter([event_a, event_b, event_c, event_d])

              expect(event_a.get("translation")).to eq('1')
              expect(event_b.get("translation")).to eq('2')
              expect(event_c.get("translation")).to eq('3')
              expect(event_d.get("translation")).to be_nil
            end
            .then("stop") do
              subject.close
            end
          actions.activate_quietly
          actions.assert_no_errors
        end
      end
    end
  end

  describe "huge json file merge" do
    let(:dictionary_path) { directory.join("dict-h.json") }
    let(:dictionary_size) { 100000 }
    let(:config) do
      {
        "source"      => "[status]",
        "target"      => "[translation]",
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
      allow(subject).to receive(:logger).and_return(double("Logger").as_null_object)
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
        "source"      => "[status]",
        "target"      => "[translation]",
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
      allow(subject).to receive(:logger).and_return(double("Logger").as_null_object)
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
