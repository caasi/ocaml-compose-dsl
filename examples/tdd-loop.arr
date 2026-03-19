-- write_test : Feature → (Code, TestSuite)
-- implement  : (Code, ErrorContext) → (Code, ErrorContext)
-- run_tests  : Code → Either PassResult FailResult
-- evaluate   : Either PassResult FailResult → (Result, ErrorContext)

write_test(for: feature)
  >>> loop(
    implement
      >>> run_tests
      >>> evaluate(criteria: all_pass)
  )
  >>> commit
