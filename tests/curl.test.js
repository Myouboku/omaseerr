// Tests for model/curl.js.

const { load, test, eq } = require("./harness")
const Curl = load("model/curl.js")

test("curlArgv never follows redirects and reads its config from stdin", () => {
  const argv = Curl.curlArgv(15)
  eq(argv[0], "curl")
  eq(argv[1], "-q") // must be first to skip ~/.curlrc
  eq(argv.some(a => /^(-L|--location|--location-trusted)$/.test(a)), false)
  eq(argv.slice(-2), ["--config", "-"])
  eq(argv[argv.indexOf("--proto") + 1], "=http,https")
  eq(argv[argv.indexOf("--max-time") + 1], "15")
  eq(argv.join(" ").includes("devkey"), false)
})

test("curlConfig quotes values and keeps the body raw", () => {
  const c = Curl.curlConfig("PUT", "https://s.example/api/v1/request/4", "devkey1234567890", { rootFolder: "/a \"b\"\\c\nd", tags: [1] })
  const lines = c.trim().split("\n")
  eq(lines[0], 'url = "https://s.example/api/v1/request/4"')
  eq(lines[1], 'request = "PUT"')
  eq(lines[2], 'header = "X-Api-Key: devkey1234567890"')
  eq(lines.includes('header = "Content-Type: application/json"'), true)
  const data = lines.find(l => l.startsWith("data-raw = "))
  // Undo curl's config escapes: the body must come back byte for byte.
  const unq = JSON.parse(data.slice("data-raw = ".length))
  eq(JSON.parse(unq), { rootFolder: "/a \"b\"\\c\nd", tags: [1] })
  // Every value stays on its own line.
  eq(lines.every(l => /^[a-z-]+ = ".*"$/.test(l)), true)
  eq(Curl.curlConfig("GET", "https://s.example/x", "k", null).includes("data-raw"), false)
})

test("parseCurlResult", () => {
  const M = Curl.CURL_MARK
  eq(Curl.parseCurlResult(0, '{"a":1}' + M + "200 "), { ok: true, status: 200, data: { a: 1 } })
  eq(Curl.parseCurlResult(0, '{"message":"Nope"}' + M + "403 "), { ok: false, status: 403, error: "http", message: "Nope" })
  eq(Curl.parseCurlResult(0, "" + M + "302 https://auth.example/login?rd=x"),
    { ok: false, status: 302, error: "redirect", location: "https://auth.example/login?rd=x" })
  eq(Curl.parseCurlResult(0, "<html>" + M + "307 "), { ok: false, status: 307, error: "redirect", location: "" })
  eq(Curl.parseCurlResult(0, M + "301 https://seerr.example.com/api/v1/request?take=20").location, "https://seerr.example.com")
  eq(Curl.parseCurlResult(0, "not json" + M + "200 ").error, "badJson")
  eq(Curl.parseCurlResult(0, M + "000 ").error, "network")
  eq(Curl.parseCurlResult(7, "").error, "network")
  eq(Curl.parseCurlResult(28, M + "000 ").error, "timeout")
  eq(Curl.parseCurlResult(63, "").error, "tooLarge")
  eq(Curl.parseCurlResult(60, "").error, "tls")
  eq(Curl.parseCurlResult(0, '{"a":1}').error, "network") // no status line
  // A body that itself contains the marker: the last one wins.
  eq(Curl.parseCurlResult(0, '"x' + M.trim() + '"' + M + "200 ").ok, true)
})
