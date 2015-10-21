# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/translate"

describe LogStash::Filters::Translate do

  let(:config) { Hash.new }
  subject { described_class.new(config) }


  describe "exact translation string" do

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


  describe "exact translation array" do

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

    let(:event) { LogStash::Event.new("status" => [200]) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event["translation"]).to eq(["OK"])
    end
  end


  describe "multi translation string" do

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


  describe "multi translation array" do

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

    let(:event) { LogStash::Event.new("status" => ["200", "500 & 300"]) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event["translation"]).to eq(["OK", "Server Error & Redirect"])
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


  describe "regex translation array" do

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

    let(:event) { LogStash::Event.new("status" => [200]) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event["translation"]).to eq(["OK"])
    end
  end


  describe "fallback value" do

    context "static configuration string" do
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
  end


  describe "multi translation string default destination" do

    let(:config) do
      {
        "field"       => "status",
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
      expect(event["status_translation"]).to eq("OK & Server Error")
    end
  end


  describe "multi translation array default destination" do

    let(:config) do
      {
        "field"       => "status",
        "dictionary"  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                           "500", "Server Error" ],
        "exact"       => false,
        "regex"       => false
      }
    end

    let(:event) { LogStash::Event.new("status" => ["200", "500 & 300"]) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event["status_translation"]).to eq(["OK", "Server Error & Redirect"])
    end
  end


  describe "multi translation string overwrite field" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "status",
        "override" => true,
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
      expect(event["status"]).to eq("OK & Server Error")
    end
  end


  describe "multi translation array overwrite field overwrite field" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "status",
        "override" => true,
        "dictionary"  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                           "500", "Server Error" ],
        "exact"       => false,
        "regex"       => false
      }
    end

    let(:event) { LogStash::Event.new("status" => ["200", "500 & 300"]) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event["status"]).to eq(["OK", "Server Error & Redirect"])
    end
  end


  describe "multi translation string overwrite field disallowed" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "status",
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
      expect(event["status"]).to eq("200 & 500")
    end
  end


  describe "multi translation array overwrite field disallowed" do

    let(:config) do
      {
        "field"       => "status",
        "destination" => "status",
        "dictionary"  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                           "500", "Server Error" ],
        "exact"       => false,
        "regex"       => false
      }
    end

    let(:event) { LogStash::Event.new("status" => ["200", "500 & 300"]) }

    it "return the exact translation" do
      subject.register
      subject.filter(event)
      expect(event["status"]).to eq(["200", "500 & 300"])
    end
  end


end
