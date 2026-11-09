// Seerr's API through curl: the command line, the config it reads on stdin,
// and turning curl's exit code and output into an API answer.
.pragma library
.import "values.js" as Values
.import "api.js" as Api

// API calls go through curl rather than QML's XMLHttpRequest, which follows
// redirects on its own and re-sends every header, X-Api-Key included, to
// wherever the server points. curl follows none (no -L), so the key only ever
// reaches the URL it was bound to. Everything secret travels in a config file
// on stdin (-K -), never in argv where /proc would show it. -q, which must
// come first, keeps a ~/.curlrc (and its possible -L) out of it.
var CURL_MARK = "\n@@omaseerr-curl@@ "

function curlArgv(timeoutSec) {
  var t = String(Values.clampInt(timeoutSec, 15, 1, 120))
  return ["curl", "-q", "--silent", "--globoff", "--proto", "=http,https",
    "--connect-timeout", "10", "--max-time", t, "--max-filesize", String(Values.MAX_RESPONSE),
    "--compressed", "--config", "-"]
}

// A curl config string: quoted, with the escapes curl's config parser knows.
function curlQuote(value) {
  return "\"" + String(value)
    .replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
    .replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + "\""
}

function curlConfig(method, url, key, body) {
  var lines = [
    "url = " + curlQuote(url),
    "request = " + curlQuote(method),
    "header = " + curlQuote("X-Api-Key: " + key),
    "header = " + curlQuote("Accept: application/json"),
    // The status and any redirect target, after the body.
    "write-out = " + curlQuote(CURL_MARK + "%{http_code} %{redirect_url}")
  ]
  if (body !== null && body !== undefined) {
    lines.push("header = " + curlQuote("Content-Type: application/json"))
    // data-raw, unlike data, never reads a file for a leading "@".
    lines.push("data-raw = " + curlQuote(JSON.stringify(body)))
  }
  return lines.join("\n") + "\n"
}

// curl exit codes worth telling apart; anything else is "network".
var CURL_TLS_CODES = [35, 51, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91, 98]

// The { ok, status, data, error, message, location } an API callback gets,
// from curl's exit code and output.
function parseCurlResult(exitCode, output) {
  var code = typeof exitCode === "number" ? exitCode : -1
  if (code === 28) return { ok: false, status: 0, error: "timeout" }
  if (code === 63) return { ok: false, status: 0, error: "tooLarge" }
  if (CURL_TLS_CODES.indexOf(code) !== -1) return { ok: false, status: 0, error: "tls" }
  var out = typeof output === "string" ? output : ""
  var at = out.lastIndexOf(CURL_MARK)
  if (code !== 0 || at === -1) return { ok: false, status: 0, error: "network" }
  var tail = out.slice(at + CURL_MARK.length).replace(/\s+$/, "")
  var m = tail.match(/^(\d{3})(?: ([^\n]*))?$/)
  var status = m ? parseInt(m[1], 10) : 0
  if (status === 0) return { ok: false, status: 0, error: "network" }
  if (status >= 300 && status < 400) {
    // Shown as the address to use instead, so without the API path.
    var location = Values.str(m[2] || "", 300)
    var api = location.indexOf(Api.API_PREFIX + "/")
    if (api > 0) location = location.slice(0, api)
    return { ok: false, status: status, error: "redirect", location: location }
  }
  var parsed = Values.parseJson(out.slice(0, at))
  if (status >= 200 && status < 300)
    return parsed.ok ? { ok: true, status: status, data: parsed.value } : { ok: false, status: status, error: parsed.error }
  return { ok: false, status: status, error: "http", message: parsed.ok ? Api.errorMessage(parsed.value) : "" }
}
