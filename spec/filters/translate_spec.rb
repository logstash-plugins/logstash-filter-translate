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
      expect(event["translation"]).to eq("OK")
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
      expect(event["translation"]).to eq("OK & Server Error")
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
      expect(event["translation"]).to eq("OK")
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
        expect(event["translation"]).to eq("no match")
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
        expect(event["translation"]).to eq("missing no match")
      end
    end

    context "static json configuration with a json dictionary lookup file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.json") }

      let(:config) do
        {
          "field"       => "ip",
          "destination" => "geo",
          "dictionary_path"  => dictionary_path,
          "exact"       => true,
          "regex"       => false,
          "fallback" => %Q[{"ip":"lookup failed","lat":-1.234,"lng":12.345,"loc":[12.345,-1.234],"name":"unknown server"}]
        }
      end

      let(:event) { LogStash::Event.new("ip" => "10.2.10.9") }

      it "returns the fallback translation" do
        subject.register
        subject.filter(event)
        translated = event["geo"]
        expect(translated).to be_a(Hash)
        expect(translated["ip"]).to eq("lookup failed")
        expect(translated["lat"]).to eq(-1.234)
        expect(translated["lng"]).to eq(12.345)
        expect(translated["loc"]).to eq([12.345, -1.234])
        expect(translated["name"]).to eq("unknown server")
        expect(event["[geo][name]"]).to eq("unknown server")
      end
    end

    context "static yaml configuration with a yaml dictionary lookup file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.yml") }

      let(:config) do
        {
          "field"       => "ip",
          "destination" => "geo",
          "dictionary_path"  => dictionary_path,
          "exact"       => true,
          "regex"       => false,
          "fallback" => %Q[---\n  ip: "lookup failed"\n  lat: -1.234\n  lng: 12.345\n  loc: \n    - 12.345\n    - -1.234\n  name: "unknown server"\n]
        }
      end

      let(:event) { LogStash::Event.new("ip" => "10.2.10.9") }

      it "returns the fallback translation" do
        subject.register
        subject.filter(event)
        translated = event["geo"]
        expect(translated).to be_a(Hash)
        expect(translated["ip"]).to eq("lookup failed")
        expect(translated["lat"]).to eq(-1.234)
        expect(translated["lng"]).to eq(12.345)
        expect(translated["loc"]).to eq([12.345, -1.234])
        expect(translated["name"]).to eq("unknown server")
        expect(event["[geo][name]"]).to eq("unknown server")
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
        expect(event["translation"]).to eq(1)
      end
    end

    context "when using a json file" do
      let(:config) do
        {
          "field"       => "ip",
          "destination" => "geo",
          "dictionary_path"  => dictionary_path,
          "exact"       => true,
          "regex"       => false
        }
      end
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.json") }
      let(:event) { LogStash::Event.new("ip" => "10.2.10.3") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        translated = event["geo"]
        expect(translated).to be_a(Hash)
        expect(translated["ip"]).to eq("10.2.10.3")
        expect(translated["lat"]).to eq(-1.234)
        expect(translated["lng"]).to eq(12.345)
        expect(translated["loc"]).to eq([12.345, -1.234])
        expect(translated["name"]).to eq("app-svr-103")
        expect(event["[geo][name]"]).to eq("app-svr-103")
      end
    end

    context "when using a csv file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.csv") }
      let(:event) { LogStash::Event.new("status" => "c") }

      it "return the exact translation" do
        subject.register
        subject.filter(event)
        expect(event["translation"]).to eq("300")
      end
    end

    context "when using an uknown file" do
      let(:dictionary_path)  { File.join(File.dirname(__FILE__), "..", "fixtures", "dict.other") }

      it "return the exact translation" do
        expect { subject.register }.to raise_error(RuntimeError, /Dictionary #{dictionary_path} have a non valid format/)
      end
    end
  end
end
