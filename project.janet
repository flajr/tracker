(declare-project
  :name "tracker"
  :description "A simple task time tracking tool"
  :version "0.2.0"
  :dependencies ["https://github.com/pyrmont/tomlin"])

(declare-executable
  :name "tracker"
  :entry "tracker.janet"
  :cflags ["-static" "-Os" "-fomit-frame-pointer"]
  :lflags ["-static"]
  :install true)

(task "test" []
  (os/execute ["janet" "test-tracker.janet"] :p))
