# encoding: utf-8
require "csv"

module LogStash module Filters module Dictionary
  class CsvFile < File

    protected

    def read_dictionary
      ::CSV.open(@dictionary_path, 'r:bom|utf-8') do |csv|
        csv.each_with_object({}) { |(k,v), dictionary| dictionary[k] = v }
      end
    end
  end
end end end
