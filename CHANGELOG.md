## 2.1.0
 - Added other formats, a part from YAML, to be used when loading
   dictionaries from files in this plugin. Current supported formats are
   YAML, JSON and CSV.

## 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully, 
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0

# 0.1.10
  - fix failing test due to a missing encoding: utf8 magic header
