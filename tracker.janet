# Import tomlin for TOML parsing
(import ./deps/tomlin :as tomlin)

# Utility functions
(defn unique-put [arr item]
  "Add item to array if not already present"
  (unless (find |(= $ item) arr)
    (array/push arr item)))

(defn find-last [needle haystack]
  "Find last occurrence of substring"
  (var last-pos nil)
  (var pos 0)
  (while (string/find needle haystack pos)
    (set last-pos (string/find needle haystack pos))
    (set pos (+ last-pos 1)))
  last-pos)

(defn generate-id [tasks]
  "Generate a unique random 2-character task ID"
  (def chars "abcdefghijklmnopqrstuvwxyz0123456789")
  (def existing-ids (map |($ :id) (values tasks)))
  (var id nil)
  (var attempts 0)
  (while (or (nil? id) (find |(= $ id) existing-ids))
    # Use os/cryptorand for better randomness
    (def rand-bytes (os/cryptorand 2))
    (def char1 (string/from-bytes (chars (% (rand-bytes 0) 36))))
    (def char2 (string/from-bytes (chars (% (rand-bytes 1) 36))))
    (set id (string char1 char2))
    (++ attempts)
    (when (> attempts 100)
      (error "Unable to generate unique ID")))
  id)

(defn format-duration [seconds]
  "Format duration in seconds to human readable format"
  (if (= seconds 0)
    "0m"
    (let [days (math/floor (/ seconds 86400))
          hours (math/floor (/ (% seconds 86400) 3600))
          minutes (math/floor (/ (% seconds 3600) 60))
          parts @[]]
      (when (> days 0) (array/push parts (string days "d")))
      (when (> hours 0) (array/push parts (string hours "h")))
      (when (> minutes 0) (array/push parts (string minutes "m")))
      (if (empty? parts) "0m" (string/join parts " ")))))

(defn parse-duration [duration-str]
  "Parse duration string back to seconds"
  (if (or (nil? duration-str) (= duration-str ""))
    0
    (let [parts (string/split " " duration-str)]
      (var total 0)
      (each part parts
        (cond
          (string/has-suffix? "d" part)
          (when-let [num (scan-number (string/slice part 0 (- (length part) 1)))]
            (+= total (* num 86400)))
          (string/has-suffix? "h" part)
          (when-let [num (scan-number (string/slice part 0 (- (length part) 1)))]
            (+= total (* num 3600)))
          (string/has-suffix? "m" part)
          (when-let [num (scan-number (string/slice part 0 (- (length part) 1)))]
            (+= total (* num 60)))))
      total)))

(defn format-date [timestamp]
  "Format timestamp to YYYY-MM-DD HH:MM"
  (let [time (os/date timestamp)]
    (string/format "%04d-%02d-%02d %02d:%02d"
                   (time :year) (+ 1 (time :month)) (time :month-day)
                   (time :hours) (time :minutes))))

(defn parse-date [date-str]
  "Parse date string to timestamp"
  (if (or (nil? date-str) (= date-str "nil"))
    nil
    (let [parts (string/split " " date-str)
          date-part (parts 0)
          time-part (parts 1)
          date-nums (map scan-number (string/split "-" date-part))
          time-nums (map scan-number (string/split ":" time-part))]
      (os/mktime {:year (date-nums 0)
                  :month (- (date-nums 1) 1)
                  :month-day (date-nums 2)
                  :hours (time-nums 0)
                  :minutes (time-nums 1)
                  :seconds 0}))))

(defn current-timestamp []
  "Get current timestamp in YYYY-MM-DD HH:MM format"
  (format-date ((dyn :current-time os/time))))

# Task management functions
(defn make-task [name tasks &opt tags notes]
  "Create a new task structure"
  (def timestamp ((dyn :current-time os/time)))
  @{:name name
    :id (generate-id tasks)
    :status "running"
    :created timestamp
    :time-sessions @[[timestamp nil]]
    :tags (or tags @[])
    :notes (or notes @[])})

(defn find-task [tasks identifier]
  "Find task by name or ID"
  (or (tasks identifier)
      (find |(= ($ :id) identifier) (values tasks))))

(defn get-tracker-file []
  "Get tracker file path from environment or default"
  (or (os/getenv "TRACKER_FILE")
      (string (os/getenv "HOME") "/.tracker.toml")))

(defn load-tasks []
  "Load tasks from TOML file and convert to internal format"
  (def content (try (slurp (dyn :tracker-file (get-tracker-file))) ([_] "")))
  (def data (if (= content "") @{} (tomlin/toml->janet content)))
  (def tasks @{})
  (def toml-tasks (get data :tasks @{}))

  (eachp [id task-data] toml-tasks
    (def time-sessions @[])
    (each time-entry (get task-data :task_time @[])
      (if (string/find " to " time-entry)
        (let [parts (string/split " to " time-entry)
              start-time (parse-date (parts 0))
              end-time (if (= (parts 1) "nil") nil (parse-date (parts 1)))]
          (array/push time-sessions [start-time end-time]))
        (array/push time-sessions [nil nil])))

    (def task @{:name (get task-data :name "")
                :id (string id)
                :status (get task-data :status "stopped")
                :created (parse-date (get task-data :created ""))
                :time-sessions time-sessions
                :tags (array ;(get task-data :tags @[]))
                :notes (array ;(get task-data :notes @[]))})

    (put tasks (task :name) task))

  tasks)

(defn save-tasks [tasks]
  "Save tasks to TOML file"
  (def buf @"")

  (eachp [name task] tasks
    (def time-entries @[])
    (each [start end] (task :time-sessions)
      (def start-str (if start (format-date start) ""))
      (def end-str (if end (format-date end) "nil"))
      (array/push time-entries (string start-str " to " end-str)))

    # Write section header
    (buffer/push buf "[tasks." (task :id) "]\n")

    # Write fields
    (buffer/push buf "name = \"" (task :name) "\"\n")
    (buffer/push buf "status = \"" (task :status) "\"\n")
    (buffer/push buf "created = \"" (format-date (task :created)) "\"\n")

    # Write arrays
    (buffer/push buf "task_time = [")
    (if (empty? time-entries)
      (buffer/push buf "]")
      (if (= (length time-entries) 1)
        (buffer/push buf "\"" (time-entries 0) "\"]")
        (do
          (buffer/push buf "\n")
          (var i 0)
          (each entry time-entries
            (buffer/push buf "    \"" entry "\"")
            (when (< i (- (length time-entries) 1))
              (buffer/push buf ","))
            (buffer/push buf "\n")
            (++ i))
          (buffer/push buf "]"))))
    (buffer/push buf "\n")

    (buffer/push buf "tags = [")
    (if (empty? (task :tags))
      (buffer/push buf "]")
      (buffer/push buf (string/join (map |(string "\"" $ "\"") (task :tags)) ", ") "]"))
    (buffer/push buf "\n")

    (buffer/push buf "notes = [")
    (if (empty? (task :notes))
      (buffer/push buf "]")
      (buffer/push buf (string/join (map |(string "\"" $ "\"") (task :notes)) ", ") "]"))
    (buffer/push buf "\n\n"))

  (spit (dyn :tracker-file (get-tracker-file)) (string buf)))

(defn calc-total-time [task]
  "Calculate total time from time sessions"
  (var total 0)
  (def current-time ((dyn :current-time os/time)))
  (def time-sessions (task :time-sessions))
  (each [start end] time-sessions
    (when start
      (if end
        (+= total (- end start))
        (when (= (task :status) "running")
          (+= total (- current-time start))))))
  total)

(defn task-template [task]
  "Format task for detailed display"
  (def total-time (calc-total-time task))
  (string
    "Task: " (task :name) "\n"
    "ID: " (task :id) "\n"
    "Status: " (task :status) "\n"
    "Created: " (format-date (task :created)) "\n"
    "Total Time: " (format-duration total-time) "\n"
    "Tags: " (if (empty? (task :tags)) "none"
               (string "#" (string/join (task :tags) " #"))) "\n"
    "Notes: " (if (empty? (task :notes)) "none"
                (string/join (task :notes) "; ")) "\n"))

(defn calc-session-duration [start end current-time]
  "Calculate duration of a single session"
  (when start
    (- (or end current-time) start)))

(defn format-task-list-line [task]
  "Format task for list display"
  (def total-time (calc-total-time task))
  (def time-str (string/format "%15s" (format-duration total-time)))
  (string " [" (task :status) "] [" time-str "] [" (task :id) "]: " (task :name)))

# Command functions
(defn cmd-create [name &opt tags notes]
  "Create a new task"
  (def tasks (load-tasks))
  (if (tasks name)
    (print "Error: Task '" name "' already exists")
    (do
      (def task (make-task name tasks tags notes))
      (put tasks name task)
      (save-tasks tasks)
      (print "Created task: " name " (ID: " (task :id) ")"))))

(defn cmd-pause [identifier]
  "Pause a task"
  (def tasks (load-tasks))
  (when-let [task (find-task tasks identifier)]
    (put task :status "paused")
    (def time-sessions (task :time-sessions))
    (when (and (not (empty? time-sessions))
               (nil? (last (last time-sessions))))
      (def last-idx (- (length time-sessions) 1))
      (def last-session (time-sessions last-idx))
      (put time-sessions last-idx [(first last-session) ((dyn :current-time os/time))]))
    (save-tasks tasks)
    (print "Paused task: " (task :name))))

(defn cmd-resume [identifier]
  "Resume a paused task"
  (def tasks (load-tasks))
  (when-let [task (find-task tasks identifier)]
    (when (= (task :status) "paused")
      (put task :status "running")
      (array/push (task :time-sessions) [((dyn :current-time os/time)) nil])
      (save-tasks tasks)
      (print "Resumed task: " (task :name)))))



(defn cmd-stop [identifier]
  "Stop a task"
  (def tasks (load-tasks))
  (when-let [task (find-task tasks identifier)]
    (put task :status "stopped")
    (def time-sessions (task :time-sessions))
    (when (and (not (empty? time-sessions))
               (nil? (last (last time-sessions))))
      (def last-idx (- (length time-sessions) 1))
      (def last-session (time-sessions last-idx))
      (put time-sessions last-idx [(first last-session) ((dyn :current-time os/time))]))
    (save-tasks tasks)
    (print "Stopped task: " (task :name))))

(defn cmd-tag [identifier tag]
  "Add tag to task"
  (def tasks (load-tasks))
  (if-let [task (find-task tasks identifier)]
    (do
      (unique-put (task :tags) tag)
      (save-tasks tasks)
      (print "Added tag '" tag "' to task: " (task :name)))
    (print "Error: Task not found: " identifier)))

(defn cmd-note [identifier note]
  "Add note to task"
  (def tasks (load-tasks))
  (if-let [task (find-task tasks identifier)]
    (do
      (array/push (task :notes) note)
      (save-tasks tasks)
      (print "Added note to task: " (task :name)))
    (print "Error: Task not found: " identifier)))

(defn cmd-list []
  "List all tasks"
  (def tasks (load-tasks))
  (print "Tasks from " (dyn :tracker-file (get-tracker-file)) ":")
  (def current-time ((dyn :current-time os/time)))

  (eachp [name task] tasks
    (print (format-task-list-line task))
    (print (string "    Created:    " (format-date (task :created))))

    # Print sessions with duration
    (var session-num 1)
    (each [start end] (task :time-sessions)
      (when start
        (def duration (calc-session-duration start end current-time))
        (def end-str (if end (format-date end) "         running"))
        (def duration-str (format-duration duration))
        (print (string/format "    Session %2d: %s - %s [%15s]"
                             session-num (format-date start) end-str duration-str))
        (++ session-num)))

    # Print tags
    (when (not (empty? (task :tags)))
      (print (string "    Tags: #" (string/join (task :tags) " #"))))

    # Print notes
    (when (not (empty? (task :notes)))
      (print (string "    Notes: " (string/join (task :notes) "; "))))

    (print)))  # Empty line between tasks



# Help functions
(defn show-help []
  (print "Usage: janet tracker.janet [create|pause|resume|stop|tag|note|list] [args...]")
  (print "")
  (print "Tasks are stored in ~/.tracker.toml by default.")
  (print "Set TRACKER_FILE environment variable to use a different location."))

(defn show-command-help [cmd]
  (case cmd
    "create" (print "Usage: janet tracker.janet create <task-name>")
    "pause" (print "Usage: janet tracker.janet pause <task-id-or-name>")
    "resume" (print "Usage: janet tracker.janet resume <task-id-or-name>")
    "stop" (print "Usage: janet tracker.janet stop <task-id-or-name>")
    "tag" (print "Usage: janet tracker.janet tag <task-id-or-name> <tag>")
    "note" (print "Usage: janet tracker.janet note <task-id-or-name> <note>")
    "list" (print "Usage: janet tracker.janet list")
    (show-help)))

# CLI interface
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
