-- lint      : Code → LintReport
-- test      : Code → TestReport
-- gate      : (LintReport, TestReport) → (Code, Code)
-- build_*   : Code → Binary
-- upload    : (Binary, Binary) → Release

(lint &&& test)
  >>> gate(require: [pass, pass])
  >>> (build_linux(profile: static) *** build_macos(profile: release))
  >>> upload_release(tag: "v0.1.0")
