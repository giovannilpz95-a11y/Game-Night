// Runs the Luau unit tests in tests/*.spec.luau outside Roblox, using luau-web (real Luau
// compiled to WebAssembly). It also compile-checks every file under src/.
//
// Only pure modules (game rules, PartyRegistry, Match, RateLimiter) can be tested this way:
// the runner fakes `game`, `script`, `require` and `Random`, nothing else from Roblox.

import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { LuauState } from 'luau-web'

const root = new URL('..', import.meta.url).pathname
const project = JSON.parse(readFileSync(join(root, 'default.project.json'), 'utf8'))

// Map each Rojo $path to its place in the DataModel, e.g. src/shared -> ReplicatedStorage/Shared
const mounts = []
function walkTree(node, path) {
  for (const [key, value] of Object.entries(node)) {
    if (key.startsWith('$') || typeof value !== 'object') continue
    const here = [...path, key]
    if (value.$path) mounts.push({ dir: value.$path, path: here })
    walkTree(value, here)
  }
}
walkTree(project.tree, [])
mounts.push({ dir: 'tests', path: ['Tests'] })

function listLuau(dir) {
  const out = []
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (statSync(full).isDirectory()) out.push(...listLuau(full))
    else if (name.endsWith('.luau') || name.endsWith('.lua')) out.push(full)
  }
  return out
}

const modules = [] // { file, path: [..segments], source }
for (const mount of mounts) {
  const base = join(root, mount.dir)
  for (const file of listLuau(base)) {
    const parts = relative(base, file).split(sep)
    let last = parts.pop().replace(/\.(server|client)?\.?luau?$/, '').replace(/\.luau?$/, '')
    const segments = [...mount.path, ...parts]
    if (last !== 'init') segments.push(last)
    modules.push({ file: relative(root, file), path: segments, source: readFileSync(file, 'utf8') })
  }
}

const state = await LuauState.createAsync({})

// 1. Compile-check every file.
let compileErrors = 0
for (const m of modules) {
  const result = state.loadstring(m.source, m.file, false)
  if (typeof result === 'string') {
    compileErrors++
    console.error(`COMPILE ERROR ${result}`)
  }
}
if (compileErrors > 0) {
  console.error(`\n${compileErrors} file(s) failed to compile`)
  process.exit(1)
}
console.log(`Compiled ${modules.length} files OK`)

// 2. Bundle modules into one chunk and run the specs.
// `export type` is only legal at a chunk's top level, so strip `export` inside the bundle.
const lua = (s) => '[==========[' + s + ']==========]'
let bundle = readFileSync(join(root, 'tools', 'test-prelude.luau'), 'utf8')
for (const m of modules) {
  const body = m.source.replace(/^export type /gm, 'type ')
  bundle += `\n__define({${m.path.map((x) => JSON.stringify(x)).join(', ')}}, ${lua(m.file)}, function(script)\n${body}\nend)\n`
}
bundle += '\nreturn __runSpecs()\n'

const run = state.loadstring(bundle, 'bundle', false)
if (typeof run === 'string') {
  console.error(run)
  process.exit(1)
}
try {
  // luau-web returns a chunk's results as an array.
  const [failed] = await run()
  process.exit(failed === 0 ? 0 : 1)
} catch (err) {
  console.error(err)
  process.exit(1)
}
