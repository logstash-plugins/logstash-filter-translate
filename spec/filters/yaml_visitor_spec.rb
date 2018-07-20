require "logstash/devutils/rspec/spec_helper"

require "logstash/filters/dictionary/yaml_visitor"

describe LogStash::Filters::Dictionary::YamlVisitor do
  it 'works' do
    yaml_string = "---\na: \n x: 3\nb: \n x: 4\n"
    dictionary = {"c" => {"x" => 5}}
    described_class.create.accept_with_dictionary(dictionary, Psych.parse_stream(yaml_string)).first
    expect(dictionary.keys.sort).to eq(["a", "b", "c"])
    values = dictionary.values
    expect(values[0]).to eq({"x" => 5})
    expect(values[1]).to eq({"x" => 3})
    expect(values[2]).to eq({"x" => 4})
  end
end
