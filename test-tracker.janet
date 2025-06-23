#!/usr/bin/env janet

# Import the tracker module
(import ./tracker :as t)

# Test helpers
(var test-count 0)
(var pass-count 0)
(var fail-count 0)

(defn distinct [arr]
  "Return array with unique elements"
  (def seen @{})
  (def result @[])
  (each item arr
    (unless (seen item)
      (put seen item true)
      (array/push result item)))
  result)

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
  (def tasks @{})
  (def id (t/generate-id tasks))
  (assert (= 2 (length id)))
  (assert (peg/match ~(sequence (some (choice (range "az") (range "09")))) id)))

(test "generate-id creates unique IDs"
  (def tasks @{"Task 1" @{:id "ab"} "Task 2" @{:id "cd"}})
  (var ids @[])
  (for i 0 10
    (def id (t/generate-id tasks))
    (assert (not (find |(= $ id) ["ab" "cd"])))
    (array/push ids id)
    # Add small delay to ensure different timestamps
    (os/sleep 0.001))
  # Check we got different IDs (with seeding, should be different)
  (assert (>= (length (distinct ids)) 2)))

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

(test "parse-date handles nil"
  (assert (nil? (t/parse-date nil)))
  (assert (nil? (t/parse-date "nil"))))

# Test task creation
(test "make-task creates proper structure"
  (with-dyns [:current-time mock-current-time]
    (def tasks @{})
    (def task (t/make-task "Test task" tasks))
    (assert (= "Test task" (task :name)))
    (assert (= "running" (task :status)))
    (assert (= mock-time (task :created)))
    (assert (= 2 (length (task :id))))
    (assert (deep= @[[mock-time nil]] (task :time-sessions)))
    (assert (deep= @[] (task :tags)))
    (assert (deep= @[] (task :notes)))))

(test "make-task with tags and notes"
  (with-dyns [:current-time mock-current-time]
    (def tasks @{})
    (def task (t/make-task "Test task" tasks @["urgent"] @["Note 1"]))
    (assert (deep= @["urgent"] (task :tags)))
    (assert (deep= @["Note 1"] (task :notes)))))

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

# Test calc-total-time
(test "calc-total-time calculates completed sessions"
  (with-dyns [:current-time mock-current-time]
    (def task @{:status "stopped"
                :time-sessions @[[100 200] [300 500]]})
    (assert (= 300 (t/calc-total-time task)))))

(test "calc-total-time includes running session"
  (with-dyns [:current-time (fn [] 700)]
    (def task @{:status "running"
                :time-sessions @[[100 200] [300 500] [600 nil]]})
    (assert (= 400 (t/calc-total-time task)))))

(test "calc-total-time ignores nil sessions for stopped tasks"
  (with-dyns [:current-time (fn [] 700)]
    (def task @{:status "stopped"
                :time-sessions @[[100 200] [300 500] [600 nil]]})
    (assert (= 300 (t/calc-total-time task)))))

# Test calc-session-duration
(test "calc-session-duration calculates duration"
  (assert (= 100 (t/calc-session-duration 100 200 300)))
  (assert (= 200 (t/calc-session-duration 100 nil 300)))
  (assert (nil? (t/calc-session-duration nil 200 300))))

# Test format-task-list-line
(test "format-task-list-line formats task"
  (with-dyns [:current-time (fn [] 700)]
    (def task @{:name "Test Task"
                :id "ab"
                :status "running"
                :time-sessions @[[100 200] [300 500] [600 nil]]})
    (def line (t/format-task-list-line task))
    (assert (string/find "[running]" line))
    (assert (string/find "[ab]" line))
    (assert (string/find "Test Task" line))))

# Test task-template formatting
(test "task-template formats complete task"
  (with-dyns [:current-time (fn [] 1234570600)]
    (def task @{:name "Test Task"
                :id "ab"
                :status "running"
                :created 1234567890
                :time-sessions @[[1234567890 1234568490] [1234570000 nil]]
                :tags @["urgent" "bug"]
                :notes @["First note" "Second note"]})
    (def output (t/task-template task))
    (assert (string/find "Task: Test Task" output))
    (assert (string/find "ID: ab" output))
    (assert (string/find "Status: running" output))
    (assert (string/find "Created: 2009-02-13" output))
    (assert (string/find "Total Time:" output))
    (assert (string/find "#urgent #bug" output))
    (assert (string/find "First note; Second note" output))))

# Test file operations with temporary files
(defn with-temp-tracker [f]
  (def temp-file (string "/tmp/test-tracker-" (os/cryptorand 8) ".toml"))
  (with-dyns [:tracker-file temp-file]
    (try
      (f temp-file)
      ([_] nil))
    (try (os/rm temp-file) ([_] nil))))

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

(test "save and load handles multiple time sessions"
  (with-temp-tracker
    (fn [temp-file]
      (def tasks @{"Task 1" @{:name "Task 1"
                              :id "ab"
                              :status "paused"
                              :created 1234567890
                              :time-sessions @[[1234567890 1234568490]
                                               [1234570000 1234571000]
                                               [1234572000 nil]]
                              :tags @[]
                              :notes @[]}})
      (t/save-tasks tasks)
      (def loaded (t/load-tasks))
      (def task (loaded "Task 1"))
      (assert (= 3 (length (task :time-sessions))))
      (assert (= 1234567890 (get-in task [:time-sessions 0 0])))
      (assert (= 1234568490 (get-in task [:time-sessions 0 1])))
      (assert (nil? (get-in task [:time-sessions 2 1]))))))

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

(test "cmd-tag prevents duplicate tags"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (t/cmd-tag "Task 1" "urgent")
      (t/cmd-tag "Task 1" "urgent")
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



(test "cmd-list lists all tasks"
  (with-temp-tracker
    (fn [temp-file]
      (t/cmd-create "Task 1")
      (t/cmd-create "Task 2")
      (def output (capture-output (fn [] (t/cmd-list))))
      (assert (string/find "Tasks from" output))
      (assert (string/find "Task 1" output))
      (assert (string/find "Task 2" output)))))

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
