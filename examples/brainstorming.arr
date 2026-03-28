-- brainstorming.arr — structured exploration before implementation

(read_files(glob: "lib/**/*.ml")
  *** git_log(n: "20")
  *** read_docs(path: "CLAUDE.md")) :: () -> Sources
  >>> summarize :: Sources -> Context
  >>> ask_questions(style: one_at_a_time) :: Context -> Requirements
  >>> propose(count: "3") :: Requirements -> Design
  >>> present_design :: Design -> Feedback
  >>> write_spec :: Feedback -> ()
