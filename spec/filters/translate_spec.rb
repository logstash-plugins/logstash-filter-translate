# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require 'logstash/plugin_mixins/ecs_compatibility_support/spec_helper'
require "logstash/filters/translate"

module TranslateUtil
  def self.build_fixture_path(filename)
    File.join(File.dirname(__FILE__), "..", "fixtures", filename)
  end
end

describe LogStash::Filters::Translate do

  let(:config) { Hash.new }
  subject { described_class.new(config) }

  let(:logger) { double('Logger').as_null_object }
  let(:deprecation_logger) { double('DeprecationLogger').as_null_object }

  before(:each) do
    allow_any_instance_of(described_class).to receive(:logger).and_return(logger)
    allow_any_instance_of(described_class).to receive(:deprecation_logger).and_return(deprecation_logger)
  end

  describe "exact translation" do

    let(:config) do
      {
        "source"      => "status",
        "target"      => "translation",
        "dictionary"  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                           "500", "Server Error" ],
        "exact"       => true,
        "regex"       => false
      }
    end

    let(:event) { LogStash::Event.new("status" => 200) }

    it "coerces field to a string then returns the exact translation" do
      subject.register
      subject.filter(event)
      expect(event.get("translation")).to eq("OK")
    end
  end

  describe "translation fails when regex setting is false but keys are regex based" do

    let(:config) do
      {
        "source"      => "status",
        "target"      => "translation",
        "dictionary"  => [ "^2\\d\\d", "OK",
                           "^3\\d\\d", "Redirect",
                           "^4\\d\\d", "Client Error",
                           "^5\\d\\d", "Server Error" ],
        "exact"       => true,
        "regex"       => false
      }
    end

    let(:event) { LogStash::Event.new("status" => 200) }

    it "does not return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event.get("translation")).to be_nil
    end
  end

  describe "multi translation" do
    context "when using an inline dictionary" do
      let(:config) do
        {
          "source"      => "status",
          "target"      => "translation",
          "dictionary"  => [ "200", "OK",
                             "300", "Redirect",
                             "400", "Client Error",
                             "500", "Server Error" ],
          "exact"       => false,
          "regex"       => false
        }
      end

      let(:event) { LogStash::Event.new("status" => "200 & 500") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("OK & Server Error")
      end
    end

    context "when using a file based dictionary" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("regex_union_dict.csv") }
      let(:config) do
        {
          "source"      => "status",
          "target"      => "translation",
          "dictionary_path" => dictionary_path,
          "refresh_interval" => 0,
          "exact"       => false,
          "regex"       => false
        }
      end

      let(:event) { LogStash::Event.new("status" => "200 & 500") }

      it "return the exact regex translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("OK & Server Error")
      end
    end
  end

  describe "regex translation" do
    context "when using an inline dictionary" do
      let(:config) do
        {
          "source"      => "status",
          "target"      => "translation",
          "dictionary"  => [ "^2[0-9][0-9]$", "OK",
                             "^3[0-9][0-9]$", "Redirect",
                             "^4[0-9][0-9]$", "Client Error",
                             "^5[0-9][0-9]$", "Server Error" ],
          "exact"       => true,
          "regex"       => true
        }
      end

      let(:event) { LogStash::Event.new("status" => "200") }

      it "return the exact regex translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("OK")
      end
    end

    context "when using a file based dictionary" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("regex_dict.csv") }
      let(:config) do
        {
          "source"      => "status",
          "target"      => "translation",
          "dictionary_path" => dictionary_path,
          "refresh_interval" => 0,
          "exact"       => true,
          "regex"       => true
        }
      end

      let(:event) { LogStash::Event.new("status" => "200") }

      it "return the exact regex translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("OK")
      end
    end
  end

  describe "fallback value", :ecs_compatibility_support do
    ecs_compatibility_matrix(:disabled, :v1) do
      before(:each) do
        allow_any_instance_of(described_class).to receive(:ecs_compatibility).and_return(ecs_compatibility)
      end

      context "static configuration" do
        let(:config) do
          {
              "source"   => "status",
              "target"   => "translation",
              "fallback" => "no match"
          }
        end

        let(:event) { LogStash::Event.new("status" => "200") }

        it "return the exact translation" do
          subject.register
          subject.filter(event)
          expect(event.get("translation")).to eq("no match")
        end
      end

      context "allow sprintf" do
        let(:config) do
          {
              "source"   => "status",
              "target"   => "translation",
              "fallback" => "%{missing_translation}"
          }
        end

        let(:event) { LogStash::Event.new("status" => "200", "missing_translation" => "missing no match") }

        it "return the exact translation" do
          subject.register
          subject.filter(event)
          expect(event.get("translation")).to eq("missing no match")
        end
      end

    end
  end

  describe "loading a dictionary" do

    let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict-wrong.yml") }

    let(:config) do
      {
        "source"      => "status",
        "target"      => "translation",
        "dictionary_path"  => dictionary_path,
        "refresh_interval" => -1,
        "exact"       => true,
        "regex"       => false
      }
    end

    it "raises exception when loading" do
      error = /mapping values are not allowed here at line 1 column 45 when loading dictionary file/
      expect { subject.register }.to raise_error(error)
    end

    context "when using a yml file" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.yml") }
      let(:event) { LogStash::Event.new("status" => "a") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq(1)
      end

      describe "yaml_load_strategy" do
        let(:one_shot_parse_filter) { subject }
        let(:streaming_parse_filter) { described_class.new(config.merge("yaml_load_strategy" => 'streaming')) }

        before(:each) do
          subject.register
          streaming_parse_filter.register
        end
        let(:one_shot_dictionary) { one_shot_parse_filter.lookup.dictionary }
        let(:streaming_dictionary) { streaming_parse_filter.lookup.dictionary }
        it "produces an equivalent dictionary for both strategies" do
          puts one_shot_dictionary.inspect
          puts streaming_dictionary.inspect
          expect(one_shot_dictionary).to eq(streaming_dictionary)
        end
      end
    end

    describe "when using a yml dictionary with code point limit" do
      let(:config) do
        {
          "source"      => "status",
          "target"      => "translation",
          "dictionary_path"  => dictionary_path,
          "yaml_dictionary_code_point_limit" => codepoint_limit
        }
      end
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.yml") }
      let(:dictionary_size) { IO.read(dictionary_path).size }
      let(:event) { LogStash::Event.new("status" => "a") }
      let(:codepoint_limit) { dictionary_size }

      context "codepoint limit under dictionary size" do
        let(:codepoint_limit) { dictionary_size / 2 }

        it "raises exception" do
          expect { subject.register }.to raise_error(/The incoming YAML document exceeds/)
        end
      end

      context "dictionary is within limit" do
        it "returns the exact translation" do
          subject.register
          subject.filter(event)
          expect(event.get("translation")).to eq(1)
        end
      end

      context "limit set to zero" do
        let(:dictionary_size) { 0 }

        it "raises configuration exception" do
          expect { subject.register }.to raise_error(LogStash::ConfigurationError, /Please set a positive number/)
        end
      end

      context "limit is unset" do
        let(:config) do
          {
            "source"      => "status",
            "target"      => "translation",
            "dictionary_path"  => dictionary_path,
          }
        end

        it "sets the limit to 128MB" do
          subject.register
          expect(subject.instance_variable_get(:@yaml_dictionary_code_point_limit)).to eq(134_217_728)
        end
      end

      context "dictionary is json and limit is set" do
        let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.json") }
        let(:dictionary_size) { 100 }

        it "raises configuration exception" do
          expect { subject.register }.to raise_error(LogStash::ConfigurationError, /Please remove `yaml_dictionary_code_point_limit` for dictionary file in JSON or CSV format/)
        end
      end

      context "dictionary is json and limit is unset" do
        let(:config) do
          {
            "source"      => "status",
            "target"      => "translation",
            "dictionary_path"  => TranslateUtil.build_fixture_path("dict.json"),
          }
        end

        it "returns the exact translation" do
          subject.register
          subject.filter(event)
          expect(event.get("translation")).to eq(10)
        end
      end
    end

    context "when using a map tagged yml file" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("tag-map-dict.yml") }
      let(:event) { LogStash::Event.new("status" => "six") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("val-6-1|val-6-2")
      end
    end

    context "when using a omap tagged yml file" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("tag-omap-dict.yml") }
      let(:event) { LogStash::Event.new("status" => "nine") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("val-9-1|val-9-2")
      end
    end

    context "when using a json file" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.json") }
      let(:event) { LogStash::Event.new("status" => "b") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq(20)
      end
    end

    context "when using a csv file" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.csv") }
      let(:event) { LogStash::Event.new("status" => "c") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("300")
      end
    end

    context "when using an unknown file" do
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.other") }

      it "raises error" do
        expect { subject.register }.to raise_error(RuntimeError, /Dictionary #{dictionary_path} has a non valid format/)
      end
    end
  end

  describe "iterate_on functionality" do
    let(:config) do
      {
        "iterate_on"       => "foo",
        "source"           => iterate_on_field,
        "target"           => "baz",
        "fallback"         => "nooo",
        "dictionary_path"  => dictionary_path,
        # "override"         => true,
        "refresh_interval" => 0
      }
    end
    let(:dictionary_path)  { TranslateUtil.build_fixture_path("tag-map-dict.yml") }

    describe "when iterate_on is the same as field, AKA array of values" do
      let(:iterate_on_field) { "foo" }
      let(:event) { LogStash::Event.new("foo" => ["nine","eight", "seven"]) }
      it "adds a translation to target array for each value in field array" do
        subject.register
        subject.filter(event)
        expect(event.get("baz")).to eq(["val-9-1|val-9-2", "val-8-1|val-8-2", "val-7-1|val-7-2"])
      end
    end

    describe "when iterate_on is the same as field, AKA array of values, coerces integer elements to strings" do
      let(:iterate_on_field) { "foo" }
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("regex_union_dict.csv") }
      let(:event) { LogStash::Event.new("foo" => [200, 300, 400]) }
      it "adds a translation to target array for each value in field array" do
        subject.register
        subject.filter(event)
        expect(event.get("baz")).to eq(["OK","Redirect","Client Error"])
      end
    end

    describe "when iterate_on is not the same as field, AKA array of objects" do
      let(:iterate_on_field) { "bar" }
      let(:event) { LogStash::Event.new("foo" => [{"bar"=>"two"},{"bar"=>"one"}, {"bar"=>"six"}]) }
      it "adds a translation to each map" do
        subject.register
        subject.filter(event)
        expect(event.get("[foo][0][baz]")).to eq("val-2-1|val-2-2")
        expect(event.get("[foo][1][baz]")).to eq("val-1-1|val-1-2")
        expect(event.get("[foo][2][baz]")).to eq("val-6-1|val-6-2")
      end
    end

    describe "when iterate_on is not the same as field, AKA array of objects, coerces integer values to strings" do
      let(:iterate_on_field) { "bar" }
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("regex_union_dict.csv") }
      let(:event) { LogStash::Event.new("foo" => [{"bar"=>200},{"bar"=>300}, {"bar"=>400}]) }
      it "adds a translation to each map" do
        subject.register
        subject.filter(event)
        expect(event.get("[foo][0][baz]")).to eq("OK")
        expect(event.get("[foo][1][baz]")).to eq("Redirect")
        expect(event.get("[foo][2][baz]")).to eq("Client Error")
      end
    end
  end

  describe "field and destination are the same (explicit override)" do
    let(:dictionary_path)  { TranslateUtil.build_fixture_path("tag-map-dict.yml") }
    let(:config) do
      {
        "field"            => "foo",
        "destination"      => "foo",
        "dictionary_path"  => dictionary_path,
        "override"         => true,
        "refresh_interval" => -1,
        "ecs_compatibility" => 'disabled'
      }
    end

    let(:event) { LogStash::Event.new("foo" => "nine") }

    it "overwrites existing value" do
      subject.register
      subject.filter(event)
      expect(event.get("foo")).to eq("val-9-1|val-9-2")
    end
  end

  context "invalid dictionary configuration" do
    let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict.yml") }
    let(:config) do
      {
        "source"           => "random field",
        "dictionary"       => { "a" => "b" },
        "dictionary_path"  => dictionary_path,
      }
    end

    it "raises an exception if both 'dictionary' and 'dictionary_path' are set" do
      expect { subject.register }.to raise_error(LogStash::ConfigurationError)
    end
  end

  context "invalid target+destination configuration" do
    let(:config) do
      {
          "source"      => "message",
          "target"      => 'foo',
          "destination" => 'bar',
      }
    end

    it "raises an exception if both 'target' and 'destination' are set" do
      expect { subject.register }.to raise_error(LogStash::ConfigurationError, /remove .*?destination => /)
    end
  end

  context "invalid source+field configuration" do
    let(:config) do
      {
        "source"      => "message",
        "field"       => 'foo'
      }
    end

    it "raises an exception if both 'source' and 'field' are set" do
      expect { subject.register }.to raise_error(LogStash::ConfigurationError, /remove .*?field => /)
    end
  end

  context "destination option" do
    let(:config) do
      {
          "source" => "message", "destination" => 'bar', "ecs_compatibility" => 'v1'
      }
    end

    it "sets the target" do
      subject.register
      expect( subject.target ).to eql 'bar'

      expect(logger).to have_received(:debug).with(a_string_including "intercepting `destination`")
      expect(deprecation_logger).to have_received(:deprecated).with(a_string_including "`destination` option is deprecated; use `target` instead.")
    end
  end

  context "field option" do
    let(:config) do
      {
          "field" => "message", "target" => 'bar'
      }
    end

    it "sets the source" do
      subject.register # does not raise
      expect( subject.source ).to eql 'message'

      expect(logger).to have_received(:debug).with(a_string_including "intercepting `field`")
      expect(deprecation_logger).to have_received(:deprecated).with(a_string_including "`field` option is deprecated; use `source` instead.")
    end
  end

  context "source option" do
    let(:config) do
      {
          "target" => 'bar'
      }
    end

    it "is required to be set" do
      expect { subject.register }.to raise_error(LogStash::ConfigurationError, /provide .*?source => /)
    end
  end

  describe "refresh_behaviour" do
    let(:dictionary_content) { "a : 1\nb : 2\nc : 3" }
    let(:modified_content) { "a : 1\nb : 4" }
    let(:dictionary_path)  { "#{Stud::Temporary.pathname}.yml" }
    let(:refresh_behaviour) { "merge" }
    let(:config) do
      {
        "source" => "status",
        "target" => "translation",
        "dictionary_path" => dictionary_path,
        "refresh_interval" => -1, # we're controlling this manually
        "exact" => true,
        "regex" => false,
        "fallback" => "no match",
        "refresh_behaviour" => refresh_behaviour
      }
    end

    before :each do
      IO.write(dictionary_path, dictionary_content)
      subject.register
    end

    let(:before_mod) { LogStash::Event.new("status" => "b") }
    let(:after_mod) { LogStash::Event.new("status" => "b") }
    let(:before_del) { LogStash::Event.new("status" => "c") }
    let(:after_del) { LogStash::Event.new("status" => "c") }

    context "when 'merge'" do
      let(:refresh_behaviour) { 'merge' }
      it "overwrites existing entries" do
        subject.filter(before_mod)
        IO.write(dictionary_path, modified_content)
        subject.lookup.load_dictionary
        subject.filter(after_mod)
        expect(before_mod.get("translation")).to eq(2)
        expect(after_mod.get("translation")).to eq(4)
      end
      it "keeps leftover entries" do
        subject.filter(before_del)
        IO.write(dictionary_path, modified_content)
        subject.lookup.load_dictionary
        subject.filter(after_del)
        expect(before_del.get("translation")).to eq(3)
        expect(after_del.get("translation")).to eq(3)
      end
    end

    context "when 'replace'" do
      let(:refresh_behaviour) { 'replace' }
      it "overwrites existing entries" do
        subject.filter(before_mod)
        IO.write(dictionary_path, modified_content)
        subject.lookup.load_dictionary
        subject.filter(after_mod)
        expect(before_mod.get("translation")).to eq(2)
        expect(after_mod.get("translation")).to eq(4)
      end
      it "removes leftover entries" do
        subject.filter(before_del)
        IO.write(dictionary_path, modified_content)
        subject.lookup.load_dictionary
        subject.filter(after_del)
        expect(before_del.get("translation")).to eq(3)
        expect(after_del.get("translation")).to eq("no match")
      end
    end
  end

  describe "loading an empty dictionary" do
    let(:directory) { Pathname.new(Stud::Temporary.directory) }

    let(:config) do
      {
        "source"      => "status",
        "target"      => "translation",
        "dictionary_path"  => dictionary_path.to_path,
        "refresh_interval" => -1,
        "fallback" => "no match",
        "exact"       => true,
        "regex"       => false
      }
    end

    before do
      dictionary_path.open("wb") do |file|
        file.write("")
      end
    end

    context "when using a yml file" do
      let(:dictionary_path) { directory.join("dict-e.yml") }
      let(:event) { LogStash::Event.new("status" => "a") }

      it "return the exact translation" do

        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("no match")
      end
    end

    context "when using a json file" do
      let(:dictionary_path) { directory.join("dict-e.json") }
      let(:event) { LogStash::Event.new("status" => "b") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("no match")
      end
    end

    context "when using a csv file" do
      let(:dictionary_path) { directory.join("dict-e.csv") }
      let(:event) { LogStash::Event.new("status" => "c") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("no match")
      end
    end
  end

  describe "default target" do

    let(:config) do
      {
          "source" => "message",
          "dictionary" => { "foo" => "bar" }
      }
    end

    let(:event) { LogStash::Event.new("message" => "foo") }

    before { subject.register }

    context "legacy mode" do

      let(:config) { super().merge('ecs_compatibility' => 'disabled') }

      it "uses the translation target" do
        subject.filter(event)
        expect(event.get("translation")).to eq("bar")
        expect(event.get("message")).to eq("foo")
      end

    end

    context "ECS mode" do

      let(:config) { super().merge('ecs_compatibility' => 'v1') }

      it "does in place translation" do
        subject.filter(event)
        expect(event.include?("translation")).to be false
        expect(event.get("message")).to eq("bar")
      end

    end

  end


  describe "error handling" do

    let(:config) do
      {
          "source" => "message",
          "dictionary" => { "foo" => "bar" }
      }
    end

    let(:event) { LogStash::Event.new("message" => "foo") }

    before { subject.register }

    it "handles unexpected error within filter" do
      expect(subject.updater).to receive(:update).and_raise RuntimeError.new('TEST')

      expect { subject.filter(event) }.to_not raise_error
    end

    it "propagates Java errors" do
      expect(subject.updater).to receive(:update).and_raise java.lang.OutOfMemoryError.new('FAKE-OUT!')

      expect { subject.filter(event) }.to raise_error(java.lang.OutOfMemoryError)
    end

  end

end
