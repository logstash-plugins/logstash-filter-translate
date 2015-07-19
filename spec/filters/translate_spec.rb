require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/translate"
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

describe LogStash::Filters::Translate do
  

  describe "exact translation" do
    config <<-CONFIG
      filter {
        translate {
          field       => "status"
          destination => "translation"
          dictionary  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                           "500", "Server Error" ]
          exact       => true
          regex       => false
        }
      }
    CONFIG

    sample("status" => 200) do
      insist { subject["translation"] } == "OK"
    end
  end

  describe "multi translation" do
    config <<-CONFIG
      filter {
        translate {
          field       => "status"
          destination => "translation"
          dictionary  => [ "200", "OK",
                           "300", "Redirect",
                           "400", "Client Error",
                          "500", "Server Error" ]
          exact       => false
          regex       => false
        }
      }
    CONFIG

    sample("status" => "200 & 500") do
      insist { subject["translation"] } == "OK & Server Error"
    end
  end

  describe "regex translation" do
    config <<-CONFIG
      filter {
        translate {
          field       => "status"
          destination => "translation"
          dictionary  => [ "^2[0-9][0-9]$", "OK",
                           "^3[0-9][0-9]$", "Redirect",
                           "^4[0-9][0-9]$", "Client Error",
                           "^5[0-9][0-9]$", "Server Error" ]
          exact       => true
          regex       => true
        }
      }
    CONFIG

    sample("status" => "200") do
      insist { subject["translation"] } == "OK"
    end
  end

  describe "fallback value - static configuration" do
    config <<-CONFIG
      filter {
        translate {
          field       => "status"
          destination => "translation"
          fallback => "no match"
        }
      }
    CONFIG

    sample("status" => "200") do
      insist { subject["translation"] } == "no match"
    end
  end
  
  describe "webserver translation" do
      config <<-CONFIG
      filter {
          translate {
              field       => "status"
              destination => "translation"
              dictionary_url  => "http://dummyurl/"
              file_to_download => "foo"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
          config.before(:each) do
              FileUtils.rm_rf('foo.yml')
              stub_request(:get, "http://dummyurl/").
              with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
              to_return(:status => 200, :body => "\
                        '200': OK\n\
                        '300': Redirect\n\
                        '400': Client Error\n\
                        '500': Server Error", :headers => {})
          end
          config.after(:all) do
              FileUtils.rm_rf('foo.yml')
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
              file_to_download => "foo"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
          config.before(:each) do
              FileUtils.rm_rf('foo.yml')
              File.open('foo.yml', 'wb') { |f| f.write("\
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
              FileUtils.rm_rf('foo.yml')
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
              file_to_download => "foo"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
          config.before(:each) do
              FileUtils.rm_rf('foo.yml')
              stub_request(:get, "http://dummyurl/").
              with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
              to_return(:status => 200, :body => "\
                        '200': OK\n\
                        '300': Redirect\n\
                        '400', Client Error\n\
                        '500': Server Error", :headers => {})
          end
          config.after(:all) do
              FileUtils.rm_rf('foo.yml')
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
              file_to_download => "foo"
          }
      }
      CONFIG
      
      RSpec.configure do |config|
          config.before(:each) do
              FileUtils.rm_rf('foo.yml')
              File.open('foo.yml', 'wb') { |f| f.write("\
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
              FileUtils.rm_rf('foo.yml')
          end
      end
      
      sample("status" => "200") do
          insist { subject["translation"] } == "OKF"
      end
  end

  describe "fallback value - allow sprintf" do
    config <<-CONFIG
      filter {
        translate {
          field       => "status"
          destination => "translation"
          fallback => "%{missing_translation}"
        }
      }
    CONFIG

    sample("status" => "200", "missing_translation" => "no match") do
      insist { subject["translation"] } == "no match"
    end
  end

end
