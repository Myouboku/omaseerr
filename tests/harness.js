// Loads model/*.js the way the QML engine does. `.pragma library` and
// `.import "x.js" as X` are QML directives, not JavaScript: they are stripped,
// each `.import` is loaded first (once, shared, like a library) and bound to
// its alias, and the file runs in its own function scope, so its top-level
// names stay its own and only reach other files through their alias.
// The code runs in this realm, so its arrays and objects compare with
// assert.deepStrictEqual like ours.

const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const root = path.join(__dirname, "..")
const loaded = new Map()

function load(file) {
  const full = path.resolve(root, file)
  if (loaded.has(full)) {
    const done = loaded.get(full)
    if (!done) throw new Error("circular .import of " + path.relative(root, full))
    return done
  }
  loaded.set(full, null)
  const source = fs.readFileSync(full, "utf8")
  const aliases = []
  const deps = []
  const importLine = /^\s*\.import\s+"([^"]+\.js)"\s+as\s+([A-Za-z_$][\w$]*)\s*$/
  for (const line of source.split("\n")) {
    if (!/^\s*\.import\b/.test(line)) continue
    const m = line.match(importLine)
    if (!m) throw new Error(path.relative(root, full) + ": unsupported " + line.trim())
    aliases.push(m[2])
    deps.push(load(path.relative(root, path.join(path.dirname(full), m[1]))))
  }
  // Top-level declarations start their line; nested ones are indented.
  const names = [...new Set([...source.matchAll(/^(?:var|let|const|function)\s+([A-Za-z_$][\w$]*)/gm)].map(m => m[1]))]
  const body = source
    .replace(/^[ \t]*\.pragma[ \t]+library[ \t]*$/m, "")
    .replace(/^[ \t]*\.import[ \t].*$/gm, "")
  const wrapped = "(function(" + aliases.join(", ") + ") {\n" + body +
    "\nreturn {" + names.map(n => JSON.stringify(n) + ": " + n).join(", ") + "}\n})"
  const namespace = vm.runInThisContext(wrapped, { filename: full, lineOffset: -1 })(...deps)
  loaded.set(full, namespace)
  return namespace
}

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
}

let passed = 0
const failures = []
let suite = ""

function describe(name) {
  suite = name
}

function test(name, fn) {
  const full = suite ? suite + ": " + name : name
  try {
    fn()
    passed += 1
  } catch (error) {
    failures.push({ name: full, error })
  }
}

function eq(actual, expected) {
  assert.deepStrictEqual(actual, expected)
}

function report() {
  for (const f of failures) {
    console.error("FAIL " + f.name)
    console.error("  " + String(f.error && f.error.message || f.error).split("\n").join("\n  "))
  }
  console.log(passed + " passed, " + failures.length + " failed")
  process.exit(failures.length ? 1 : 0)
}

module.exports = { load, fixture, describe, test, eq, report }
