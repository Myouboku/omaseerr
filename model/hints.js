// The shortcut hints under each page: reading "key label · key label …" (the
// translations' format) and laying the pairs out in centred, balanced lines.
// ui/KeyHints.qml measures the pairs and places them where this says.
.pragma library

// [{ keys, label }]: a pair's keys run to its first space (so keys never
// contain one), the label is the rest.
function parseHints(text) {
  return String(text).split(" · ").map(function(part) {
    var cut = part.indexOf(" ")
    return cut < 0 ? { keys: part, label: "" } : { keys: part.slice(0, cut), label: part.slice(cut + 1) }
  })
}

// Greedy wrap of `widths` at `limit`, `gap` apart: the indices on each line.
function wrapLines(widths, limit, gap) {
  var lines = [], line = [], used = 0
  for (var i = 0; i < widths.length; i++) {
    var w = widths[i]
    if (line.length && used + gap + w > limit) { lines.push(line); line = []; used = 0 }
    used += (line.length ? gap : 0) + w
    line.push(i)
  }
  if (line.length) lines.push(line)
  return lines
}

// As few lines as fit in `width`, with widths as even as possible: the
// greedy wrap at the narrowest limit that needs no more lines.
function balancedLines(widths, width, gap) {
  var count = wrapLines(widths, width, gap).length
  var lo = 0, hi = width
  for (var i = 0; i < widths.length; i++) lo = Math.max(lo, widths[i])
  while (hi - lo > 1) {
    var mid = (lo + hi) / 2
    if (wrapLines(widths, mid, gap).length <= count) hi = mid; else lo = mid
  }
  return wrapLines(widths, Math.min(hi, width), gap)
}

// Positions for items of `sizes` ([{ width, height }]): balanced lines,
// each centred in `width`, items vertically centred on their line, lines
// `vGap` apart. { positions: [{ x, y }] (rounded), height }; nothing to place
// (no items, no width) gives no positions and height 0.
function layoutHints(sizes, width, hGap, vGap) {
  if (!sizes.length || width <= 0) return { positions: [], height: 0 }
  var widths = sizes.map(function(s) { return s.width })
  var lines = balancedLines(widths, width, hGap)
  var positions = [], y = 0
  for (var l = 0; l < lines.length; l++) {
    var row = lines[l], total = 0, tall = 0
    for (var j = 0; j < row.length; j++) { total += sizes[row[j]].width; tall = Math.max(tall, sizes[row[j]].height) }
    total += hGap * (row.length - 1)
    var x = Math.max(0, (width - total) / 2)
    for (var k = 0; k < row.length; k++) {
      var s = sizes[row[k]]
      positions[row[k]] = { x: Math.round(x), y: Math.round(y + (tall - s.height) / 2) }
      x += s.width + hGap
    }
    y += tall + (l < lines.length - 1 ? vGap : 0)
  }
  return { positions: positions, height: y }
}
