# encoding: utf-8
require "csv"

module LogStash module Filters module Dictionary
  class CsvFile < File

    protected

    def read_file_into_dictionary
      ::CSV.open(@dictionary_path, 'r:bom|utf-8') do |csv|
        csv.each { |row| k,v = row; @dictionary[k] = v }
      end
    end
  end
end end end
