# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/translate"

describe LogStash::Filters::Translate do

  let(:config) { Hash.new }
  subject { described_class.new(config) }

  describe "exact translation" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "translation",
        "dictionary"  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                           "500", "Server Error" ],
                           "exact"       => true,
                           "regex"       => false
      }
    end

    let(:event) { LogStash::Event.new("status" => 200) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event.get("translation")).to eq("OK")
    end
  end


  describe "multi translation" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "translation",
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

  describe "regex translation" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "translation",
        "dictionary"  => [ "^2[0-9][0-9]$", "OK",
                           "^3[0-9][0-9]$", "Redirect",
                           "^4[0-9][0-9]$", "Client Error",
                           "^5[0-9][0-9]$", "Server Error" ],
        "exact"       => true,
        "regex"       => true
      }
    end

    let(:event) { LogStash::Event.new("status" => "200") }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event.get("translation")).to eq("OK")
    end
  end

  describe "fallback value" do

    context "static configuration" do
      let(:config) do
        {
          "field"       => "status",
          "destination" => "translation",
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
          "field"       => "status",
          "destination" => "translation",
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

    let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict-wrong.yml") }

    let(:config) do
      {
        "field"       => "status",
        "destination" => "translation",
        "dictionary_path"  => dictionary_path,
        "exact"       => true,
        "regex"       => false
      }
    end

    it "raises exception when loading" do
      error = "(#{dictionary_path}): mapping values are not allowed here at line 1 column 45 when loading dictionary file at #{dictionary_path}"
      expect { subject.register }.to raise_error("#{described_class}: #{error}")
    end

    context "when using a yml file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.yml") }
      let(:event) { LogStash::Event.new("status" => "a") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq(1)
      end
    end

    context "when using a json file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.json") }
      let(:event) { LogStash::Event.new("status" => "b") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq(20)
      end
    end

    context "when using a csv file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.csv") }
      let(:event) { LogStash::Event.new("status" => "c") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event.get("translation")).to eq("300")
      end
    end

    context "when using an uknown file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.other") }

      it "return the exact translation" do
        expect { subject.register }.to raise_error(RuntimeError, /Dictionary #{dictionary_path} have a non valid format/)
      end
    end
  end

  describe "general configuration" do
    let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.yml") }
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

  describe "refresh_behaviour" do
    let(:dictionary_content) { "a : 1\nb : 2\nc : 3" }
    let(:modified_content) { "a : 1\nb : 4" }
    let(:dictionary_path)  { "#{Stud::Temporary.pathname}.yml" }
    let(:refresh_behaviour) { "merge" }
    let(:config) do
      {
        "field" => "status",
        "destination" => "translation",
        "dictionary_path" => dictionary_path,
        "refresh_interval" => 10000, # we're controlling this manually
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
        subject.send(:load_dictionary)
        subject.filter(after_mod)
        expect(before_mod.get("translation")).to eq(2)
        expect(after_mod.get("translation")).to eq(4)
      end
      it "keeps leftover entries" do
        subject.filter(before_del)
        IO.write(dictionary_path, modified_content)
        subject.send(:load_dictionary)
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
        subject.send(:load_dictionary)
        subject.filter(after_mod)
        expect(before_mod.get("translation")).to eq(2)
        expect(after_mod.get("translation")).to eq(4)
      end
      it "removes leftover entries" do
        subject.filter(before_del)
        IO.write(dictionary_path, modified_content)
        subject.send(:load_dictionary)
        subject.filter(after_del)
        expect(before_del.get("translation")).to eq(3)
        expect(after_del.get("translation")).to eq("no match")
      end
    end
  end
end
