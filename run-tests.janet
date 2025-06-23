#!/usr/bin/env janet

# Test runner for time tracker

(print "🧪 Running Time Tracker Tests\n")

# Run basic tests
(print "═══════════════════════════════════════")
(print "Running basic tests...")
(print "═══════════════════════════════════════")
(def basic-result (os/execute ["janet" "test-tracker.janet"] :p))

# Summary
(print "\n═══════════════════════════════════════")
(print "Test Summary")
(print "═══════════════════════════════════════")
(printf "Basic tests: %s" (if (= 0 basic-result) "✓ PASSED" "❌ FAILED"))
(def exit-code (if (= 0 basic-result) 0 1))
(if (= 0 exit-code)
  (print "\n✅ All test suites passed!")
  (print "\n❌ Some tests failed!"))

(os/exit exit-code)
