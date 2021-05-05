# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/translate"

module TranslateUtil
  def self.build_fixture_path(filename)
    File.join(File.dirname(__FILE__), "..", "fixtures", filename)
  end
end

describe LogStash::Filters::Translate do

  let(:config) { Hash.new }
  subject { described_class.new(config) }

  describe "exact translation" do

    let(:config) do
      {
        "field"       => "status",
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
        "field"       => "status",
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
          "field"       => "status",
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
          "field"       => "status",
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
          "field"       => "status",
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
          "field"       => "status",
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

  describe "fallback value" do

    context "static configuration" do
      let(:config) do
        {
          "field"    => "status",
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
          "field"    => "status",
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

  describe "loading a dictionary" do

    let(:dictionary_path)  { TranslateUtil.build_fixture_path("dict-wrong.yml") }

    let(:config) do
      {
        "field"       => "status",
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
        "field"            => iterate_on_field,
        "destination"      => "baz",
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
      it "adds a translation to destination array for each value in field array" do
        subject.register
        subject.filter(event)
        expect(event.get("baz")).to eq(["val-9-1|val-9-2", "val-8-1|val-8-2", "val-7-1|val-7-2"])
      end
    end

    describe "when iterate_on is the same as field, AKA array of values, coerces integer elements to strings" do
      let(:iterate_on_field) { "foo" }
      let(:dictionary_path)  { TranslateUtil.build_fixture_path("regex_union_dict.csv") }
      let(:event) { LogStash::Event.new("foo" => [200, 300, 400]) }
      it "adds a translation to destination array for each value in field array" do
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

  describe "field and destination are the same (needs override)" do
    let(:dictionary_path)  { TranslateUtil.build_fixture_path("tag-map-dict.yml") }
    let(:config) do
      {
        "field"            => "foo",
        "destination"      => "foo",
        "dictionary_path"  => dictionary_path,
        "override"         => true,
        "refresh_interval" => -1
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
        "field"            => "random field",
        "dictionary"       => { "a" => "b" },
        "dictionary_path"  => dictionary_path,
      }
    end

    it "raises an exception if both 'dictionary' and 'dictionary_path' are set" do
      expect { subject.register }.to raise_error(LogStash::ConfigurationError)
    end
  end

  context "invalid target+dictionary configuration" do
    let(:config) do
      {
          "field"       => "message",
          "target"      => 'foo',
          "destination" => 'bar',
      }
    end

    it "raises an exception if both 'target' and 'destination' are set" do
      expect { subject.register }.to raise_error(LogStash::ConfigurationError)
    end
  end

  describe "refresh_behaviour" do
    let(:dictionary_content) { "a : 1\nb : 2\nc : 3" }
    let(:modified_content) { "a : 1\nb : 4" }
    let(:dictionary_path)  { "#{Stud::Temporary.pathname}.yml" }
    let(:refresh_behaviour) { "merge" }
    let(:config) do
      {
        "field" => "status",
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
        "field"       => "status",
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
end
