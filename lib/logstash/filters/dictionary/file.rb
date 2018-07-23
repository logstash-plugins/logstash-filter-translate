# encoding: utf-8
require 'rufus-scheduler'
require "logstash/util/loggable"

java_import 'java.util.concurrent.locks.ReentrantReadWriteLock'

module LogStash module Filters module Dictionary
  class File
    def self.create(path, refresh_interval, refresh_behaviour, exact, regex)
      if /\.y[a]?ml$/.match(path)
        instance = YamlFile.new(path, refresh_interval, exact, regex)
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

    include LogStash::Util::Loggable
    attr_reader :dictionary, :fetch_strategy

    def initialize(path, refresh_interval, exact, regex)
      @dictionary_path = path
      @refresh_interval = refresh_interval
      @short_refresh = @refresh_interval < 300.001
      rw_lock = java.util.concurrent.locks.ReentrantReadWriteLock.new
      @write_lock = rw_lock.writeLock
      @dictionary = Hash.new()
      @update_method = method(:merge_dictionary)
      initialize_for_file_type
      raise_exception = true
      if exact
        if regex
          @fetch_strategy = FetchStrategy::FileExactRegex.new(@dictionary, rw_lock)
        else
          @fetch_strategy = FetchStrategy::FileExact.new(@dictionary, rw_lock)
        end
      else
        @fetch_strategy = FetchStrategy::FileRegexUnion.new(@dictionary, rw_lock)
      end
      load_dictionary(raise_exception)
      stop_scheduler
      start_scheduler unless @refresh_interval <= 0 # disabled, a scheduler interval of zero makes no sense
    end

    def initialize_for_file_type
      # sub class specific initializer
    end

    def stop_scheduler
      @scheduler.shutdown(:wait) if @scheduler
    end

    def load_dictionary(raise_exception=false)
      begin
        @dictionary_mtime = ::File.mtime(@dictionary_path)
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

    private

    def start_scheduler
      @scheduler = Rufus::Scheduler.new
      @scheduler.interval("#{@refresh_interval}s", :overlap => false) do
        reload_dictionary
      end
    end

    def read_file_into_dictionary
      # defined in csv_file, yaml_file and json_file
    end

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

    def reload_dictionary
      if @short_refresh
        load_dictionary if needs_refresh?
      else
        load_dictionary
      end
    end

    def needs_refresh?
      ::File.mtime(@dictionary_path) != @dictionary_mtime
    end

    def loading_exception(e, raise_exception)
      msg = "Translate: #{e.message} when loading dictionary file at #{@dictionary_path}"
      if raise_exception
        raise RuntimeError.new(msg)
      else
        @logger.warn("#{msg}, continuing with old dictionary", :dictionary_path => @dictionary_path)
      end
    end
  end
end end end
