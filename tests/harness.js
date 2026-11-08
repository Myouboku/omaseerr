// Loads model/*.js the way the QML engine does: `.pragma library` and `.import`
// are QML directives, not JavaScript, so they are stripped and the rest runs in
// this realm, where its top-level declarations become globals we collect.

const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

function load(file) {
  const full = path.join(__dirname, "..", file)
  const source = fs.readFileSync(full, "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")
    .replace(/^\s*\.import\s+.*$/gm, "")
  const before = new Set(Object.getOwnPropertyNames(globalThis))
  vm.runInThisContext(source, { filename: file })
  const namespace = {}
  for (const name of Object.getOwnPropertyNames(globalThis)) {
    if (!before.has(name)) namespace[name] = globalThis[name]
  }
  return namespace
}

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
}

let passed = 0
const failures = []

function test(name, fn) {
  try {
    fn()
    passed += 1
  } catch (error) {
    failures.push({ name, error })
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

module.exports = { load, fixture, test, eq, report }
