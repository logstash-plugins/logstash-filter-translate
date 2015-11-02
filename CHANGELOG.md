# 3.0.0
 - Added support to handle full arrays instead of only first element
 - Changed default destination field to [source field]_translation in order to fix bug
 - Added tests for new functionality
 - Changed some functions to private

# 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully, 
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0

# 0.1.10
  - fix failing test due to a missing encoding: utf8 magic header
