# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/translate"
require "webmock/rspec"
require 'digest/sha1'
WebMock.disable_net_connect!(allow_localhost: true)

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
  end
  
  describe "webserver translation" do
      config <<-CONFIG
      filter {
          translate {
              field       => "status"
              destination => "translation"
              dictionary_url  => "http://dummyurl/"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
          hash = Digest::SHA1.hexdigest 'http://dummyurl/'
          config.before(:each) do
              FileUtils.rm_rf(hash+'.yml')
              stub_request(:get, "http://dummyurl/").
              with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
              to_return(:status => 200, :body => "\
                        '200': OK\n\
                        '300': Redirect\n\
                        '400': Client Error\n\
                        '500': Server Error", :headers => {})
          end
          config.after(:all) do
              FileUtils.rm_rf(hash+'.yml')
          end
      end
      
      sample("status" => "200") do
          insist { subject["translation"] } == "OK"
      end
  end
  
  describe "webserver translation existing YML" do
      config <<-CONFIG
      filter {
          translate {
              field       => "status"
              destination => "translation"
              dictionary_url  => "http://dummyurl/"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
        hash = Digest::SHA1.hexdigest 'http://dummyurl/'
          config.before(:each) do
              FileUtils.rm_rf(hash+'.yml')
              File.open(hash+'.yml', 'wb') { |f| f.write("\
                                                       '200': OKF\n\
                                                       '300': Redirect\n\
                                                       '400': Client Error\n\
                                                       '500': Server Error") }
              stub_request(:get, "http://dummyurl/").
              with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
              to_return(:status => 200, :body => "\
                        '200': OK\n\
                        '300': Redirect\n\
                        '400': Client Error\n\
                        '500': Server Error", :headers => {})
          end
          config.after(:all) do
              FileUtils.rm_rf(hash+'.yml')
          end
      end
      
      sample("status" => "200") do
          insist { subject["translation"] } == "OK"
      end
  end
  
  describe "webserver translation not valid" do
      config <<-CONFIG
      filter {
          translate {
              field       => "status"
              destination => "translation"
              dictionary_url  => "http://dummyurl/"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
        hash = Digest::SHA1.hexdigest 'http://dummyurl/'
          config.before(:each) do
              FileUtils.rm_rf(hash+'.yml')
              stub_request(:get, "http://dummyurl/").
              with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
              to_return(:status => 200, :body => "\
                        '200': OK\n\
                        '300': Redirect\n\
                        '400', Client Error\n\
                        '500': Server Error", :headers => {})
          end
          config.after(:all) do
              FileUtils.rm_rf(hash+'.yml')
          end
      end
      
      sample("status" => "200") do
          insist { subject["translation"] } == nil
      end
  end
  
  describe "webserver translation not valid existing YML" do
      config <<-CONFIG
      filter {
          translate {
              field       => "status"
              destination => "translation"
              dictionary_url  => "http://dummyurl/"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
        hash = Digest::SHA1.hexdigest 'http://dummyurl/'
          config.before(:each) do
              FileUtils.rm_rf(hash+'.yml')
              File.open(hash+'.yml', 'wb') { |f| f.write("\
                                                       '200': OKF\n\
                                                       '300': Redirect\n\
                                                       '400': Client Error\n\
                                                       '500': Server Error") }
              stub_request(:get, "http://dummyurl/").
              with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
              to_return(:status => 200, :body => "\
                        '200': OK\n\
                        '300': Redirect\n\
                        '400', Client Error\n\
                        '500': Server Error", :headers => {})
          end
          config.after(:all) do
              FileUtils.rm_rf(hash+'.yml')
          end
      end
      
      sample("status" => "200") do
          insist { subject["translation"] } == "OKF"
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
