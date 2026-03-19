-- explore_context : () → (SourceCode, (History, Docs))
-- summarize       : (SourceCode, (History, Docs)) → Context
-- ask_questions   : Context → Requirements
-- propose         : Requirements → Design

(read_files(glob: "lib/**/*.ml") *** git_log(n: "20") *** read_docs(path: "CLAUDE.md"))
  >>> summarize
  >>> ask_questions(style: one_at_a_time)
  >>> propose(count: "3")
  >>> present_design
  >>> write_spec
