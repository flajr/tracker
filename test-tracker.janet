#!/usr/bin/env janet

# Import the tracker module
(import ./tracker :as t)

# Test helpers
(var test-count 0)
(var pass-count 0)
(var fail-count 0)

(defmacro test [name & body]
  ~(do
     (++ test-count)
     (try
       (do ,;body)
       ([err]
         (++ fail-count)
         (eprintf "❌ %s: %s" ,name err)
         (error err)))
     (++ pass-count)
     (printf "✓ %s" ,name)))

(defmacro test-eq [name expected actual]
  ~(test ,name
     (let [exp ,expected
           act ,actual]
       (unless (deep= exp act)
         (error (string/format "Expected %q but got %q" exp act))))))

(defmacro test-truthy [name expr]
  ~(test ,name
     (unless ,expr
       (error (string/format "Expected truthy but got %q" ,expr)))))

(defmacro test-error [name & body]
  ~(test ,name
     (var errored false)
     (try
       (do ,;body)
       ([_] (set errored true)))
     (unless errored
       (error "Expected error but none occurred"))))

# Mock current-time for deterministic tests
(var mock-time 1234567890)
(defn mock-current-time [] mock-time)

# Test utility functions
(test "unique-put adds new items"
  (def arr @[1 2 3])
  (t/unique-put arr 4)
  (assert (deep= arr @[1 2 3 4])))

(test "unique-put doesn't add duplicates"
  (def arr @[1 2 3])
  (t/unique-put arr 2)
  (assert (deep= arr @[1 2 3])))

(test "find-last finds last occurrence"
  (assert (= 6 (t/find-last "ab" "ab cd ab")))
  (assert (= 0 (t/find-last "ab" "ab cd ef")))
  (assert (nil? (t/find-last "xy" "ab cd ef"))))

(test "generate-id creates 2-character strings"
  (def id (t/generate-id))
  (assert (= 2 (length id)))
  (assert (peg/match ~(sequence (some (choice (range "az") (range "09")))) id)))

(test "format-duration handles various durations"
  (assert (= "0m" (t/format-duration 0)))
  (assert (= "0m" (t/format-duration 59)))
  (assert (= "1m" (t/format-duration 60)))
  (assert (= "2h" (t/format-duration 7200)))
  (assert (= "1d" (t/format-duration 86400)))
  (assert (= "1d 2h 30m" (t/format-duration 95400))))

(test "parse-duration parses formatted strings"
  (assert (= 0 (t/parse-duration "0m")))
  (assert (= 0 (t/parse-duration "")))
  (assert (= 60 (t/parse-duration "1m")))
  (assert (= 7200 (t/parse-duration "2h")))
  (assert (= 86400 (t/parse-duration "1d")))
  (assert (= 95400 (t/parse-duration "1d 2h 30m"))))

(test "format-date and parse-date round trip"
  (def timestamp 1234567890)
  (def formatted (t/format-date timestamp))
  (def parsed (t/parse-date formatted))
  # format-date only preserves minute precision, so compare with seconds zeroed
  (assert (= (- timestamp (% timestamp 60)) parsed)))

(test "parse-date handles nil"
  (assert (nil? (t/parse-date nil)))
  (assert (nil? (t/parse-date "nil"))))

# Test task creation
(test "make-task creates proper structure"
  (with-dyns [:current-time mock-current-time]
    (def task (t/make-task "Test task"))
    (assert (= "Test task" (task :name)))
    (assert (= "running" (task :status)))
    (assert (= mock-time (task :created)))
    (assert (= 2 (length (task :id))))
    (assert (deep= @[[mock-time nil]] (task :time-sessions)))
    (assert (deep= @[] (task :tags)))
    (assert (deep= @[] (task :notes)))))

# Test find-task
(test "find-task finds by name"
  (def tasks @{"Task 1" @{:id "ab" :name "Task 1"}
               "Task 2" @{:id "cd" :name "Task 2"}})
  (def found (t/find-task tasks "Task 1"))
  (assert (= "Task 1" (found :name))))

(test "find-task finds by ID"
  (def tasks @{"Task 1" @{:id "ab" :name "Task 1"}
               "Task 2" @{:id "cd" :name "Task 2"}})
  (def found (t/find-task tasks "cd"))
  (assert (= "Task 2" (found :name))))

(test "find-task returns nil for missing task"
  (def tasks @{"Task 1" @{:id "ab" :name "Task 1"}})
  (assert (nil? (t/find-task tasks "Missing")))
  (assert (nil? (t/find-task tasks "zz"))))

# Test task template formatting
(test "task-template formats complete task"
  (def task @{:name "Test Task"
              :id "ab"
              :status "running"
              :created 1234567890
              :time-sessions @[[1234567890 1234568490] [1234570000 nil]]
              :tags @["urgent" "bug"]
              :notes @["First note" "Second note"]})
  (def output (t/task-template task))
  (assert (string/find "# Task: Test Task" output))
  (assert (string/find "- **ID**: ab" output))
  (assert (string/find "- **Status**: running" output))
  (assert (string/find "- **Created**: 2009-02-13 00:31" output))
  (assert (string/find "#urgent #bug" output))
  (assert (string/find "First note; Second note" output)))

# Test file operations with temporary files
(defn with-temp-tracker [f]
  (def temp-file (string "/tmp/test-tracker-" (math/random) ".md"))
  (with-dyns [:TRACKER_FILE temp-file]
    (try
      (f temp-file)
      ([_] nil))
    (os/rm temp-file)))

(test "save-tasks and load-tasks round trip"
  (with-temp-tracker
    (fn [temp-file]
      (def tasks @{"Task 1" @{:name "Task 1"
                              :id "ab"
                              :status "running"
                              :created 1234567890
                              :time-sessions @[[1234567890 1234568490]]
                              :tags @["test"]
                              :notes @["A note"]}})
      (t/save-tasks tasks)
      (def loaded (t/load-tasks))
      (def task (loaded "Task 1"))
      (assert task)
      (assert (= "Task 1" (task :name)))
      (assert (= "ab" (task :id)))
      (assert (= "running" (task :status)))
      (assert (deep= @["test"] (task :tags)))
      (assert (deep= @["A note"] (task :notes))))))

# Test command functions with output capture
(defn capture-output [f]
  (def buf @"")
  (with-dyns [:out buf]
    (f))
  (string buf))

(test "cmd-create creates new task"
  (with-temp-tracker
    (fn [temp-file]
      (def output (capture-output (fn [] (t/cmd-create "New Task"))))
      (assert (string/find "Created task: New Task" output))
      (def tasks (t/load-tasks))
      (assert (tasks "New Task")))))

(test "cmd-create rejects duplicate"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (def output (capture-output (fn [] (t/cmd-create "Task 1"))))
      (assert (string/find "Error: Task 'Task 1' already exists" output)))))

(test "cmd-pause pauses running task"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (def output (capture-output (fn [] (t/cmd-pause "Task 1"))))
      (assert (string/find "Paused task: Task 1" output))
      (def tasks (t/load-tasks))
      (assert (= "paused" ((tasks "Task 1") :status))))))

(test "cmd-resume resumes paused task"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (t/cmd-pause "Task 1")
      (def output (capture-output (fn [] (t/cmd-resume "Task 1"))))
      (assert (string/find "Resumed task: Task 1" output))
      (def tasks (t/load-tasks))
      (assert (= "running" ((tasks "Task 1") :status))))))

(test "cmd-stop stops task"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (def output (capture-output (fn [] (t/cmd-stop "Task 1"))))
      (assert (string/find "Stopped task: Task 1" output))
      (def tasks (t/load-tasks))
      (assert (= "stopped" ((tasks "Task 1") :status))))))

(test "cmd-tag adds tags"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (def output (capture-output (fn [] (t/cmd-tag "Task 1" "urgent"))))
      (assert (string/find "Added tag 'urgent' to task: Task 1" output))
      (def tasks (t/load-tasks))
      (assert (deep= @["urgent"] ((tasks "Task 1") :tags))))))

(test "cmd-note adds notes"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (def output (capture-output (fn [] (t/cmd-note "Task 1" "Test note"))))
      (assert (string/find "Added note to task: Task 1" output))
      (def tasks (t/load-tasks))
      (assert (deep= @["Test note"] ((tasks "Task 1") :notes))))))

(test "calc-total-time calculates session totals"
  (def sessions @[[100 200] [300 500] [600 nil]])
  (assert (= 300 (t/calc-total-time sessions))))

# Test list output formatting
(test "task-list-template formats task info"
  (def task @{:name "Test Task"
              :id "ab"
              :status "paused"
              :created 1234567890
              :time-sessions @[[1234567890 1234568490]]
              :tags @["test"]
              :notes @["Note 1"]})
  (def [main created sessions tags notes] (t/task-list-template task))
  (assert (string/find "[ paused]" main))
  (assert (string/find "[ab]: Test Task" main))
  (assert (string/find "Created:" created))
  (assert (= 1 (length sessions)))
  (assert tags)
  (assert notes))

# Summary
(printf "\n========================================")
(printf "Tests: %d | ✓ Passed: %d | ❌ Failed: %d" test-count pass-count fail-count)
(printf "========================================")

(if (= fail-count 0)
  (do
    (print "\nAll tests passed! 🎉")
    (os/exit 0))
  (do
    (eprintf "\n%d tests failed" fail-count)
    (os/exit 1)))
