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
    attr_reader :dictionary

    def initialize(path, refresh_interval, exact, regex)
      @exact = exact
      @regex = regex
      @use_regex_hash = false
      @use_regex_union = false
      @dictionary_path = path
      @refresh_interval = refresh_interval
      @short_refresh = @refresh_interval < 300.001
      rw_lock = java.util.concurrent.locks.ReentrantReadWriteLock.new
      @read_lock = rw_lock.readLock
      @write_lock = rw_lock.writeLock
      @dictionary = Hash.new
      @keys_regex = Hash.new
      @update_method = method(:merge_dictionary)
      initialize_for_file_type
      raise_exception = true
      load_dictionary(raise_exception)
      if @exact
        using_regex_map if @regex
      else
        using_regex_union
      end
      stop_scheduler
      start_scheduler unless @refresh_interval <= 0 # disabled, a scheduler interval of zero makes no sense
    end

    def initialize_for_file_type
      # sub class specific initializer
    end

    def using_regex_map
      @use_regex_hash = true
      build_regex_map
    end

    def using_regex_union
      @use_regex_union = true
      build_union_regex
    end

    def fetch(source)
      if @exact
        if @regex
          @read_lock.lock
          lock_for_read do
            key = @dictionary.keys.detect{|k| source.match(@keys_regex[k])}
            yield deep_clone(@dictionary[key]) if key
          end
        else
          lock_for_read do
            yield deep_clone(@dictionary[source]) if @dictionary.include?(source)
          end
        end
      else
        lock_for_read do
          value = source.gsub(@union_regex_keys, @dictionary)
          yield deep_clone(value) if source != value
        end
      end
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

    def deep_clone(value)
      LogStash::Util.deep_clone(value)
    end

    def start_scheduler
      @scheduler = Rufus::Scheduler.new
      @scheduler.interval("#{@refresh_interval}s", :overlap => false) do
        reload_dictionary
      end
    end

    def lock_for_read
      @read_lock.lock
      begin
        yield
      ensure
        @read_lock.unlock
      end
    end

    def lock_for_write
      @write_lock.lock
      begin
        yield
      ensure
        @write_lock.unlock
      end
    end

    def read_file_into_dictionary
      # defined in csv_file, yaml_file and json_file
    end

    def merge_dictionary
      lock_for_write do
        read_file_into_dictionary
        # rebuilding the regex map is time expensive
        build_regex_map if @use_regex_hash
        build_union_regex if @use_regex_union
      end
    end

    def replace_dictionary
      lock_for_write do
        @dictionary.clear
        read_file_into_dictionary
        # rebuilding the regex map is time expensive
        build_regex_map if @use_regex_hash
        build_union_regex if @use_regex_union
      end
    end

    def build_regex_map
      @keys_regex.clear
      # rebuilding the regex map is time expensive
      # 100 000 keys takes 0.5 seconds on a high spec Macbook Pro
      # at least we are not doing it for every event like before
      @dictionary.keys.each{|k| @keys_regex[k] = Regexp.new(k)}
    end

    def build_union_regex
      @union_regex_keys = Regexp.union(@dictionary.keys)
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
