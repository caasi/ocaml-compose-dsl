-- release.arr — CI/CD release pipeline

(lint &&& test) :: Code -> Reports
  >>> gate(require: [pass, pass]) :: Reports -> Code
  >>> (build_linux(profile: static) *** build_macos(profile: release)) :: Code -> Binaries
  >>> upload_release(tag: "v0.1.0") :: Binaries -> ()
