// release.arr — CI/CD release pipeline
export const meta = {
  name: 'release',
  description: 'release.arr — CI/CD release pipeline',
  phases: [{ title: 'Run' }],
}

const par1 = (await parallel([
  () => agent(`lint`, { label: 'lint' }),
  () => agent(`test`, { label: 'test' })
])).filter(Boolean)
const gate_2 = await agent(`gate

Parameters: require=[pass, pass]\n\nReturn a Code.\n\n## Input\n${JSON.stringify(par1)}`, { label: 'gate' })
const par3 = (await parallel([
  () => agent(`build_linux

Parameters: profile=static\n\n## Input\n${gate_2}`, { label: 'build_linux' }),
  () => agent(`build_macos

Parameters: profile=release\n\n## Input\n${gate_2}`, { label: 'build_macos' })
])).filter(Boolean)
const upload_release_4 = await agent(`upload_release

Parameters: tag=v0.1.0\n\nReturn a ().\n\n## Input\n${JSON.stringify(par3)}`, { label: 'upload_release' })
return upload_release_4
