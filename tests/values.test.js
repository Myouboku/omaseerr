// Tests for model/values.js.

const { load, test, eq } = require("./harness")
const Values = load("model/values.js")

test("strings are bounded and stripped of controls", () => {
  const long = "a".repeat(5000)
  eq(Values.str(long, 10).length, 10)
  eq(Values.str("a\u0000b\u001bc"), "abc")
  eq(Values.str({ toString() { return "x" } }), "")
})

test("parseJson refuses huge or broken bodies", () => {
  eq(Values.parseJson("{").ok, false)
  eq(Values.parseJson("x".repeat(Values.MAX_RESPONSE + 1)).error, "tooLarge")
  eq(Values.parseJson("").value, null)
})
