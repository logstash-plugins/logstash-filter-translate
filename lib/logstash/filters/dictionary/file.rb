# encoding: utf-8
require "logstash/util/loggable"
require "logstash/filters/fetch_strategy/file"

module LogStash module Filters module Dictionary
  class DictionaryFileError < StandardError; end

  class File

    include LogStash::Util::Loggable

    def self.create(path, refresh_interval, refresh_behaviour, exact, regex, params)
      if /\.y[a]?ml$/.match(path)
        instance = YamlFile.new(path, refresh_interval, exact, regex, params["dictionary_file_max_bytes"])
      elsif path.end_with?(".json")
        instance = JsonFile.new(path, refresh_interval, exact, regex)
      elsif path.end_with?(".csv")
        instance = CsvFile.new(path, refresh_interval, exact, regex)
      else
        raise "Translate: Dictionary #{path} has a non valid format"
      end
      if refresh_behaviour == 'merge'
        instance.set_update_strategy(:merge_dictionary)
      elsif refresh_behaviour == 'replace'
        instance.set_update_strategy(:replace_dictionary)
      else
        # we really should never get here
        raise(LogStash::ConfigurationError, "Unknown value for refresh_behaviour=#{refresh_behaviour.to_s}")
      end
    end

    attr_reader :dictionary, :fetch_strategy

    def initialize(path, refresh_interval, exact, regex, file_max_bytes = nil)
      @dictionary_path = path
      @refresh_interval = refresh_interval
      @short_refresh = @refresh_interval <= 300
      rw_lock = java.util.concurrent.locks.ReentrantReadWriteLock.new
      @write_lock = rw_lock.writeLock
      @dictionary = Hash.new
      @update_method = method(:merge_dictionary)
      initialize_for_file_type(file_max_bytes)
      args = [@dictionary, rw_lock]
      klass = case
              when exact && regex then FetchStrategy::File::ExactRegex
              when exact          then FetchStrategy::File::Exact
              else                     FetchStrategy::File::RegexUnion
              end
      @fetch_strategy = klass.new(*args)
      load_dictionary(raise_exception = true)
    end

    def load_dictionary(raise_exception=false)
      begin
        @dictionary_mtime = ::File.mtime(@dictionary_path).to_f
        @update_method.call
      rescue Errno::ENOENT
        @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      rescue => e
        loading_exception(e, raise_exception)
      end
    end

    def set_update_strategy(method_sym)
      @update_method = method(method_sym)
      self
    end

    protected

    def initialize_for_file_type(file_max_bytes)
      # sub class specific initializer
    end

    def read_file_into_dictionary
      # defined in csv_file, yaml_file and json_file
    end

    private

    def merge_dictionary
      @write_lock.lock
      begin
        read_file_into_dictionary
        @fetch_strategy.dictionary_updated
      ensure
        @write_lock.unlock
      end
    end

    def replace_dictionary
      @write_lock.lock
      begin
        @dictionary.clear
        read_file_into_dictionary
        @fetch_strategy.dictionary_updated
      ensure
        @write_lock.unlock
      end
    end

    # scheduler executes this method, periodically
    def reload_dictionary
      if @short_refresh
        load_dictionary if needs_refresh?
      else
        load_dictionary
      end
    end
    public :reload_dictionary

    def needs_refresh?
      @dictionary_mtime != ::File.mtime(@dictionary_path).to_f
    end

    def loading_exception(e, raise_exception)
      msg = "Translate: #{e.message} when loading dictionary file at #{@dictionary_path}"
      if raise_exception
        dfe = DictionaryFileError.new(msg)
        dfe.set_backtrace(e.backtrace)
        raise dfe
      else
        @logger.warn("#{msg}, continuing with old dictionary", :dictionary_path => @dictionary_path)
      end
    end
  end
end end end
