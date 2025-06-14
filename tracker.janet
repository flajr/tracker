#!/usr/bin/env janet

# Dynamic variable for time (can be mocked in tests)
(defn current-time [] (dyn :current-time os/time))

# Uniq array
(defn unique-put [arr item]
  (when (not (find (fn [x] (= x item)) arr))
    (array/push arr item))
  arr)

# Find last occurrence of a substring in a string
(defn find-last [substr str]
  (var last-pos nil)
  (var pos 0)
  (while (< pos (length str))
    (let [found (string/find substr str pos)]
      (if found
        (do
          (set last-pos found)
          (set pos (+ found 1)))
        (break))))
  last-pos)

# Generate random 4-character ID
(defn generate-id []
  (let [chars "abcdefghijklmnopqrstuvwxyz0123456789"
        seed (+ ((current-time)) (math/floor (* 1000000 (% (os/clock) 1))))
        rng (math/rng seed)]
    (string/join (map (fn [_]
                        (let [idx (math/rng-int rng (length chars))]
                          (string/slice chars idx (+ idx 1))))
                      (range 2)))))

# Format duration in seconds to readable string (displays in minutes/hours/days)
(defn format-duration [seconds]
  (if (< seconds 60) "0m"
    (let [days (math/floor (/ seconds 86400))
          remaining (% seconds 86400)
          hours (math/floor (/ remaining 3600))
          remaining (% remaining 3600)
          minutes (math/round (/ remaining 60))]
      (string/join (filter (fn [x] (not (empty? x)))
                          [(if (> days 0) (string days "d") "")
                           (if (> hours 0) (string hours "h") "")
                           (if (> minutes 0) (string minutes "m") "")]) " "))))

# Parse duration string back to seconds (from minutes/hours/days)
(defn parse-duration [duration-str]
  (if (or (nil? duration-str) (empty? duration-str) (= duration-str "0m"))
    0
    (let [parts (string/split " " duration-str)]
      (var result 0)
      (loop [part :in parts]
        (cond
          (string/has-suffix? "d" part)
          (let [num (scan-number (string/slice part 0 (- (length part) 1)))]
            (when num (set result (+ result (* num 86400)))))
          (string/has-suffix? "h" part)
          (let [num (scan-number (string/slice part 0 (- (length part) 1)))]
            (when num (set result (+ result (* num 3600)))))
          (string/has-suffix? "m" part)
          (let [num (scan-number (string/slice part 0 (- (length part) 1)))]
            (when num (set result (+ result (* num 60)))))))
      result)))

# Create new task
(defn make-task [name]
  @{:id (generate-id)
   :name name
   :status "running"
   :created ((current-time))
   :time-sessions @[[((current-time)) nil]]
   :tags @[]
   :notes @[]})

# Find task by name or ID in given tasks table
(defn find-task [tasks name-or-id]
  (or (tasks name-or-id)
      (let [pair (first (filter (fn [[_ task]] (= (task :id) name-or-id)) (pairs tasks)))]
        (when pair (get pair 1)))))


# String constants for parsing
(def prefix-id "- **ID**: ")
(def prefix-status "- **Status**: ")
(def prefix-created "- **Created**: ")
(def prefix-task-time "- **Task Time**: ")
(def prefix-tags "- **Tags**: ")
(def prefix-notes "- **Notes**: ")

# Get tracker file path from environment or use default
(defn get-tracker-path []
  (or (dyn :TRACKER_FILE)
      (os/getenv "TRACKER_FILE")
      (string (os/getenv "HOME") "/.tracker.md")))

# Format unix timestamp to readable date string
(defn format-date [timestamp]
  (let [date (os/date timestamp "UTC")]
    (string/format "%04d-%02d-%02d %02d:%02d"
                   (date :year)
                   (+ (date :month) 1)
                   (date :month-day)
                   (date :hours)
                   (date :minutes))))

# Parse formatted date string back to unix timestamp
(defn parse-date [date-str]
  (if (or (nil? date-str) (= date-str "nil"))
    nil
    (let [parts (peg/match ~{:main (sequence :year "-" :month "-" :day " " :hour ":" :minute)
                            :year (capture (repeat 4 (range "09")))
                            :month (capture (repeat 2 (range "09")))
                            :day (capture (repeat 2 (range "09")))
                            :hour (capture (repeat 2 (range "09")))
                            :minute (capture (repeat 2 (range "09")))}
                          date-str)]
      (when (and parts (= (length parts) 5))
        (let [year (scan-number (parts 0))
              month (scan-number (parts 1))
              day (scan-number (parts 2))
              hour (scan-number (parts 3))
              minute (scan-number (parts 4))]
          (os/mktime {:year year
                      :month (- month 1)
                      :month-day day
                      :hours hour
                      :minutes minute
                      :seconds 0}
                      "UTC"))))))

# Load tasks from markdown file
(defn load-tasks []
  (def tasks @{})
  (def filename (get-tracker-path))
  (when (os/stat filename)
    (def content (slurp filename))
    (def sections (string/split "\n# Task: " content))
    (loop [section :in (slice sections 1)]
      (def lines (string/split "\n" section))
      (when (> (length lines) 0)
        (def task-name (string/trim (first lines)))
        (def task @{:name task-name :tags @[] :notes @[] :time-sessions @[]})
        (loop [line :in lines]
          (cond
            (string/has-prefix? prefix-id line)
            (put task :id (string/trim (string/slice line (length prefix-id))))
            (string/has-prefix? prefix-status line)
            (put task :status (string/trim (string/slice line (length prefix-status))))
            (string/has-prefix? prefix-created line)
            (put task :created (parse-date (string/trim (string/slice line (length prefix-created)))))
            (string/has-prefix? prefix-task-time line)
            (let [sessions-str (string/trim (string/slice line (length prefix-task-time)))]
              (when (not (empty? sessions-str))
                (let [session-parts (string/split "; " sessions-str)]
                  (loop [session :in session-parts]
                    # Format is: YYYY-MM-DD HH:MM-YYYY-MM-DD HH:MM or YYYY-MM-DD HH:MM-nil
                    (cond
                      # Handle sessions ending with -nil
                      (string/has-suffix? "-nil" session)
                      (let [start-str (string/slice session 0 (- (length session) 4))
                            start (parse-date start-str)]
                        (when start
                          (array/push (task :time-sessions) @[start nil])))
                      # Handle sessions with two timestamps
                      # Look for pattern "YYYY-MM-DD HH:MM" which is 16 characters
                      (>= (length session) 33)  # Min length for two timestamps with dash
                      (let [# First timestamp is first 16 characters
                            start-str (string/slice session 0 16)
                            # Skip the dash at position 16
                            # Second timestamp starts at position 17
                            stop-str (string/slice session 17)
                            start (parse-date start-str)
                            stop (parse-date stop-str)]
                        (when (and start stop)
                          (array/push (task :time-sessions) @[start stop]))))))))
            (string/has-prefix? prefix-tags line)
            (let [tags-str (string/trim (string/slice line (length prefix-tags)))]
              (when (not (empty? tags-str))
                # Split on spaces and remove # characters
                (let [tag-parts (string/split " " tags-str)]
                  (loop [tag :in tag-parts]
                    (let [trimmed-tag (string/trim tag)]
                      (when (and (not (empty? trimmed-tag)) (string/has-prefix? "#" trimmed-tag))
                        (let [clean-tag (string/slice trimmed-tag 1)]
                          (when (not (empty? clean-tag))
                            (array/push (task :tags) clean-tag)))))))))
            (string/has-prefix? prefix-notes line)
            (let [notes-str (string/trim (string/slice line (length prefix-notes)))]
              (when (not (empty? notes-str))
                (let [note-parts (string/split "; " notes-str)]
                  (loop [note :in note-parts]
                    (let [clean-note (string/trim note)]
                      (when (not (empty? clean-note))
                        (array/push (task :notes) clean-note)))))))))
        (put tasks task-name task))))
  tasks)

# Template for task markdown format using string/format
(defn task-template [task]
  (def tags-str (if (> (length (task :tags)) 0)
                   (string "#" (string/join (task :tags) " #"))
                   ""))
  (def notes-str (if (> (length (task :notes)) 0)
                    (string/join (task :notes) "; ")
                    ""))
  (def sessions-str
    (string/join
      (map (fn [session]
             (let [start (session 0)
                   stop (session 1)]
               (if stop
                 (string/format "%s-%s" (format-date start) (format-date stop))
                 (string/format "%s-nil" (format-date start)))))
           (task :time-sessions))
      "; "))

  # Format sessions string separately to handle empty sessions
  (def sessions-str-display
    (if (= sessions-str "")
      ""
      sessions-str))
  (string/format `# Task: %s
- **ID**: %s
- **Status**: %s
- **Created**: %s
- **Task Time**: %s
- **Tags**: %s
- **Notes**: %s

`
                 (task :name)
                 (task :id)
                 (task :status)
                 (format-date (task :created))
                 sessions-str-display
                 tags-str
                 notes-str))

# Save tasks to markdown file
(defn save-tasks [tasks]
  (def content @["# Time Tracker\n\n"])
  (loop [[name task] :pairs tasks]
    (array/push content (task-template task)))
  (spit (get-tracker-path) (string/join content)))

# Message templates for better consistency
(def msg-templates
  {:task-exists "Error: Task '%s' already exists"
   :task-created "Created task: %s (ID: %s)"
   :task-not-found "Error: Task '%s' does not exist"
   :task-paused "Paused task: %s"
   :task-resumed "Resumed task: %s"
   :task-stopped "Stopped task: %s"
   :task-already-paused "Task '%s' is already paused"
   :task-not-paused "Task '%s' is not paused"
   :tag-added "Added tag '%s' to task: %s"
   :note-added "Added note to task: %s"})

# Create new task
(defn cmd-create [name]
  (def tasks (load-tasks))
  (if (find-task tasks name)
    (printf (msg-templates :task-exists) name)
    (do
      (put tasks name (make-task name))
      (save-tasks tasks)
      (printf (msg-templates :task-created) name ((tasks name) :id)))))

# Pause running task
(defn cmd-pause [name-or-id]
  (def tasks (load-tasks))
  (if-let [task (find-task tasks name-or-id)]
    (if (= (task :status) "running")
      (do
        # Find the last session and set its stop time
        (when (> (length (task :time-sessions)) 0)
          (let [last-session (array/peek (task :time-sessions))]
            (when (nil? (last-session 1))
              (put last-session 1 ((current-time))))))
        (put task :status "paused")
        (save-tasks tasks)
        (printf (msg-templates :task-paused) (task :name)))
      (printf (msg-templates :task-already-paused) (task :name)))
    (printf (msg-templates :task-not-found) name-or-id)))

# Resume paused task
(defn cmd-resume [name-or-id]
  (def tasks (load-tasks))
  (if-let [task (find-task tasks name-or-id)]
    (if (= (task :status) "paused")
      (do
        (put task :status "running")
        # Add a new session
        (array/push (task :time-sessions) @[((current-time)) nil])
        (save-tasks tasks)
        (printf (msg-templates :task-resumed) (task :name)))
      (printf (msg-templates :task-not-paused) (task :name)))
    (printf (msg-templates :task-not-found) name-or-id)))

# Stop task
(defn cmd-stop [name-or-id]
  (def tasks (load-tasks))
  (if-let [task (find-task tasks name-or-id)]
    (do
      (when (= (task :status) "running")
        # Find the last session and set its stop time
        (when (> (length (task :time-sessions)) 0)
          (let [last-session (array/peek (task :time-sessions))]
            (when (nil? (last-session 1))
              (put last-session 1 ((current-time)))))))
      (put task :status "stopped")
      (save-tasks tasks)
      (printf (msg-templates :task-stopped) (task :name)))
    (printf (msg-templates :task-not-found) name-or-id)))

# Calculate total time from sessions
(defn calc-total-time [sessions]
  (var total 0)
  (loop [session :in sessions]
    (let [start (session 0)
          stop (session 1)]
      (when stop
        (set total (+ total (- stop start))))))
  total)

# Template for task list display format using string/format
(defn task-list-template [task]
  # Calculate current total time including active session
  (var total-time (calc-total-time (task :time-sessions)))
  (var active-session nil)
  (when (and (= (task :status) "running") (> (length (task :time-sessions)) 0))
    (let [last-session (array/peek (task :time-sessions))]
      (when (nil? (last-session 1))
        (set active-session last-session)
        (set total-time (+ total-time (- ((current-time)) (last-session 0)))))))

  (def main-line (string/format " [%7s] [%15s] [%s]: %s"
                                (task :status)
                                (format-duration total-time)
                                (task :id)
                                (task :name)))
  (def created-line (string/format "    Created: %19s" (format-date (task :created))))
  (def session-lines @[])
  (loop [i :range [0 (length (task :time-sessions))]]
    (let [session ((task :time-sessions) i)
          start (session 0)
          stop (session 1)
          duration (if stop (- stop start) (- ((current-time)) start))]
      (array/push session-lines
        (string/format "    Session %2d: %16s - %16s [%15s]"
                       (+ i 1)
                       (format-date start)
                       (if stop (format-date stop) "running")
                       (format-duration duration)))))
  (def tags-line (if (> (length (task :tags)) 0)
                    (string/format "    Tags: #%s" (string/join (task :tags) " #"))
                    nil))
  (def notes-line (if (> (length (task :notes)) 0)
                     (string/format "    Notes: %s" (string/join (task :notes) "; "))
                     nil))
  [main-line created-line session-lines tags-line notes-line])

# List all tasks
(defn cmd-list []
  (def tasks (load-tasks))
  (if (empty? tasks)
    (printf "No tasks found in %s" (get-tracker-path))
    (do
      (printf "Tasks from %s:" (get-tracker-path))
      (loop [[name task] :pairs tasks]
        (def [main-line created-line session-lines tags-line notes-line] (task-list-template task))
        (print main-line)
        (print created-line)
        (loop [session-line :in session-lines]
          (print session-line))
        (when tags-line (print tags-line))
        (when notes-line (print notes-line))
        (print)))))

# Add tag to task
(defn cmd-tag [name-or-id tag]
  (def tasks (load-tasks))
  (if-let [task (find-task tasks name-or-id)]
    (do
      (unique-put (task :tags) tag)
      (save-tasks tasks)
      (printf (msg-templates :tag-added) tag (task :name)))
    (printf (msg-templates :task-not-found) name-or-id)))

# Add note to task
(defn cmd-note [name-or-id note]
  (def tasks (load-tasks))
  (if-let [task (find-task tasks name-or-id)]
    (do
      (unique-put (task :notes) note)
      (save-tasks tasks)
      (printf (msg-templates :note-added) (task :name)))
    (printf (msg-templates :task-not-found) name-or-id)))

# Help template
(def help-text (string "Time Tracker - A simple task time tracking tool\n\n"
                       "VERSION: 0.2.0\n"
                       "USAGE:\n"
                       "    janet tracker.janet <command> [args...]\n\n"
                       "COMMANDS:\n"
                       "    create <task-name>           Create a new task\n"
                       "    pause  <task-name-or-id>     Pause a running task\n"
                       "    resume <task-name-or-id>     Resume a paused task\n"
                       "    stop   <task-name-or-id>     Stop a task completely\n"
                       "    list                         List all tasks with their status\n"
                       "    tag    <task-name-or-id> <tag>     Add a tag to a task\n"
                       "    note   <task-name-or-id> <note>    Add a note to a task\n\n"
                       "ENVIRONMENT:\n"
                       "    TRACKER_FILE    Path to tracker file (default: ~/.tracker.md)\n\n"
                       "EXAMPLES:\n"
                       "    janet tracker.janet create \"Fix database bug\"\n"
                       "    janet tracker.janet pause \"Fix database bug\"\n"
                       "    janet tracker.janet tag abc1 urgent\n"
                       "    janet tracker.janet note abc1 \"Found the root cause\"\n"
                       "    janet tracker.janet list\n"
                       "    TRACKER_FILE=/tmp/work.md janet tracker.janet list\n"))

(defn show-help []
  (print help-text))

(defn show-command-help [command]
  (case command
    "create" (print "Usage: janet tracker.janet create <task-name>")
    "pause"  (print "Usage: janet tracker.janet pause <task-name-or-id>")
    "resume" (print "Usage: janet tracker.janet resume <task-name-or-id>")
    "stop"   (print "Usage: janet tracker.janet stop <task-name-or-id>")
    "tag"    (print "Usage: janet tracker.janet tag <task-name-or-id> <tag>")
    "note"   (print "Usage: janet tracker.janet note <task-name-or-id> <note>")
    (show-help)))

# Main function
(defn main [& args]
  # Skip script name
  (def real-args (slice args 1))

  (if (< (length real-args) 1)
    (show-help)
    (let [cmd (first real-args)]
      (cond
        (= cmd "create")
        (if (>= (length real-args) 2)
          (cmd-create (real-args 1))
          (show-command-help "create"))

        (= cmd "pause")
        (if (>= (length real-args) 2)
          (cmd-pause (real-args 1))
          (show-command-help "pause"))

        (= cmd "resume")
        (if (>= (length real-args) 2)
          (cmd-resume (real-args 1))
          (show-command-help "resume"))

        (= cmd "stop")
        (if (>= (length real-args) 2)
          (cmd-stop (real-args 1))
          (show-command-help "stop"))

        (= cmd "list")
        (cmd-list)

        (= cmd "tag")
        (if (>= (length real-args) 3)
          (cmd-tag (real-args 1) (real-args 2))
          (show-command-help "tag"))

        (= cmd "note")
        (if (>= (length real-args) 3)
          (cmd-note (real-args 1) (real-args 2))
          (show-command-help "note"))

        (do
          (print "Unknown command: " cmd)
          (show-help))))))
