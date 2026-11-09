// Tests for model/hints.js.

const { load, test, eq } = require("./harness")
const Hints = load("model/hints.js")
const en = require("../i18n/en.json")
const fr = require("../i18n/fr.json")

test("parseHints splits pairs and keys from labels", () => {
  eq(Hints.parseHints("↑↓ navigate · Enter details · a/A approve"),
    [{ keys: "↑↓", label: "navigate" }, { keys: "Enter", label: "details" }, { keys: "a/A", label: "approve" }])
  // The label keeps its own spaces; a lone key has no label.
  eq(Hints.parseHints("Esc go back · Tab"), [{ keys: "Esc", label: "go back" }, { keys: "Tab", label: "" }])
  eq(Hints.parseHints(""), [{ keys: "", label: "" }])
  // A middle dot without its spaces is part of a label.
  eq(Hints.parseHints("x a·b"), [{ keys: "x", label: "a·b" }])
})

test("every translated hint line parses to keys without spaces and a label", () => {
  for (const [lang, strings] of [["en", en], ["fr", fr]]) {
    const flat = {}
    const walk = (o, p) => { for (const k in o) typeof o[k] === "object" ? walk(o[k], p + k + ".") : flat[p + k] = o[k] }
    walk(strings, "")
    const keys = Object.keys(flat).filter(k => /(^|\.)keys[A-Za-z]*$/.test(k))
    eq([lang, keys.length > 0], [lang, true])
    for (const k of keys) for (const e of Hints.parseHints(flat[k])) eq([lang, k, e.keys !== "" && e.label !== ""], [lang, k, true])
  }
})

test("wrapLines wraps greedily between items", () => {
  eq(Hints.wrapLines([10, 10, 10], 100, 5), [[0, 1, 2]])
  eq(Hints.wrapLines([10, 10, 10], 25, 5), [[0, 1], [2]])
  eq(Hints.wrapLines([10, 10, 10], 24, 5), [[0], [1], [2]])
  // An item wider than the limit still gets a line of its own.
  eq(Hints.wrapLines([50, 10], 20, 5), [[0], [1]])
  eq(Hints.wrapLines([], 20, 5), [])
})

test("balancedLines keeps the line count and evens the lines out", () => {
  // Greedy at 100 gives 4 + 1; balanced gives 3 + 2.
  eq(Hints.wrapLines([20, 20, 20, 20, 20], 100, 5), [[0, 1, 2, 3], [4]])
  eq(Hints.balancedLines([20, 20, 20, 20, 20], 100, 5), [[0, 1, 2], [3, 4]])
  // Everything fits on one line: still one line.
  eq(Hints.balancedLines([10, 10, 10], 200, 5), [[0, 1, 2]])
  // Never narrower than the widest item.
  eq(Hints.balancedLines([60, 10, 10], 70, 5), [[0], [1, 2]])
  eq(Hints.balancedLines([30], 10, 5), [[0]])
})

test("layoutHints centres lines and items on their line", () => {
  const sizes = [{ width: 20, height: 10 }, { width: 20, height: 14 }, { width: 20, height: 10 }, { width: 20, height: 10 }, { width: 20, height: 10 }]
  const out = Hints.layoutHints(sizes, 100, 5, 4)
  // 3 + 2: line 1 is 70 wide, line 2 is 45 wide, both centred in 100.
  eq(out.positions, [
    { x: 15, y: 2 }, { x: 40, y: 0 }, { x: 65, y: 2 },
    { x: 28, y: 18 }, { x: 53, y: 18 }
  ])
  eq(out.height, 14 + 4 + 10)
  eq(Hints.layoutHints([{ width: 30, height: 12 }], 100, 5, 4), { positions: [{ x: 35, y: 0 }], height: 12 })
  // Too narrow: lines start at the left edge, not before it.
  eq(Hints.layoutHints([{ width: 130, height: 12 }], 100, 5, 4).positions, [{ x: 0, y: 0 }])
})

test("layoutHints with nothing to place", () => {
  eq(Hints.layoutHints([], 100, 5, 4), { positions: [], height: 0 })
  eq(Hints.layoutHints([{ width: 10, height: 10 }], 0, 5, 4), { positions: [], height: 0 })
  eq(Hints.layoutHints([{ width: 10, height: 10 }], -5, 5, 4), { positions: [], height: 0 })
})
