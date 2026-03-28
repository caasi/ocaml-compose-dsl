-- tdd-loop.arr — test-driven development cycle

write_test(for: feature) :: Feature -> Code
  >>> loop(
    implement :: Code -> Code
      >>> run_tests :: Code -> TestResult
      >>> evaluate(criteria: all_pass) :: TestResult -> Code
  )
  >>> commit :: Code -> ()
