#!/usr/bin/env node
// Unit tests for model/*.js, one tests/<module>.test.js per model file.
// Run: node tests/run.js            every module
//      node tests/run.js form keymap  only those modules

const fs = require("fs")
const { describe, report } = require("./harness")

const all = fs.readdirSync(__dirname).filter(f => f.endsWith(".test.js")).map(f => f.slice(0, -".test.js".length)).sort()
const wanted = process.argv.slice(2)
for (const name of wanted) {
  if (!all.includes(name)) {
    console.error("no tests/" + name + ".test.js (have: " + all.join(", ") + ")")
    process.exit(2)
  }
}
for (const name of wanted.length ? wanted : all) {
  describe(name)
  require("./" + name + ".test.js")
}
report()
