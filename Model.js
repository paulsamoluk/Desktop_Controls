// Every knob the panel exposes.
//
// `hypr` is the option key hyprctl understands (also the key `hl.config()`
// nests, split on ":"). Opacity is kept as a whole percentage for the slider
// and converted to Hyprland's 0.0-1.0 at the edges, so the two ends agree.
//
// `default` is only a placeholder for the first paint, before the live read
// lands. `Reset to default` restores the values captured on first run, stored
// as base<Key> in this widget's shell.json entry — not these.
var OPTIONS = [
  { key: "focusedOpacity", label: "Focused windows", hypr: "decoration:active_opacity", group: "opacity", kind: "percent", min: 20, max: 100, step: 1, unit: "%", default: 100 },
  { key: "unfocusedOpacity", label: "Unfocused windows", hypr: "decoration:inactive_opacity", group: "opacity", kind: "percent", min: 20, max: 100, step: 1, unit: "%", default: 100 },
  { key: "rounding", label: "Corner rounding", hypr: "decoration:rounding", group: "shape", kind: "int", min: 0, max: 40, step: 1, unit: " px", default: 0 },
  { key: "gapsIn", label: "Inner gaps", hypr: "general:gaps_in", group: "shape", kind: "int", min: 0, max: 60, step: 1, unit: " px", default: 5 },
  { key: "gapsOut", label: "Outer gaps", hypr: "general:gaps_out", group: "shape", kind: "int", min: 0, max: 80, step: 1, unit: " px", default: 10 },
  { key: "borderWidth", label: "Border width", hypr: "general:border_size", group: "shape", kind: "int", min: 0, max: 10, step: 1, unit: " px", default: 2 },
  { key: "blur", label: "Background blur", hypr: "decoration:blur:enabled", group: "effects", kind: "bool", default: false },
  { key: "shadows", label: "Window shadows", hypr: "decoration:shadow:enabled", group: "effects", kind: "bool", default: false },
  { key: "animations", label: "Animations", hypr: "animations:enabled", group: "effects", kind: "bool", default: true }
]

var KEYS = OPTIONS.map(function(o) { return o.key })

function optionFor(key) {
  for (var i = 0; i < OPTIONS.length; i++) if (OPTIONS[i].key === key) return OPTIONS[i]
  return null
}

function optionForHypr(hypr) {
  for (var i = 0; i < OPTIONS.length; i++) if (OPTIONS[i].hypr === hypr) return OPTIONS[i]
  return null
}

function byGroup(group) {
  return OPTIONS.filter(function(o) { return o.group === group })
}

function isToggle(o) { return o.kind === "bool" }

function hasValues(values) {
  if (!values) return false
  for (var i = 0; i < OPTIONS.length; i++) {
    if (values[OPTIONS[i].key] !== undefined && values[OPTIONS[i].key] !== null) return true
  }
  return false
}

function defaults() {
  var out = {}
  for (var i = 0; i < OPTIONS.length; i++) out[OPTIONS[i].key] = OPTIONS[i].default
  return out
}

// The shell.json field that holds the value captured on first run, for Reset.
function baseKey(key) {
  return "base" + key.charAt(0).toUpperCase() + key.slice(1)
}

// Has a live read drifted away from a saved value? An option the read did not
// answer is not a difference — only a real disagreement counts.
function differs(key, live, saved) {
  if (live === undefined || live === null) return false
  var option = optionFor(key)
  if (option && option.kind === "bool") return (live === true) !== (saved === true)
  return Math.round(Number(live)) !== Math.round(Number(saved))
}

// ---------------------------------------------------------------------------
// Reading: one process for the whole table. `hyprctl getoption` answers with
// {"option": "...", "int"|"float"|"bool"|"css": ...}, so we ask for JSON and
// print "key<TAB>json" per line.
// ---------------------------------------------------------------------------

function readCommand() {
  var keys = OPTIONS.map(function(o) { return o.hypr }).join(" ")
  var script = 'for k in ' + keys + '; do printf "%s\\t" "$k"; hyprctl -j getoption "$k" | tr -d "\\n"; printf "\\n"; done'
  return ["sh", "-c", script]
}

function numberFrom(parsed) {
  if (!parsed) return 0
  if (parsed.int !== undefined) return Number(parsed.int)
  if (parsed.float !== undefined) return Number(parsed.float)
  if (typeof parsed.css === "string") return Number(String(parsed.css).split(" ")[0])
  return 0
}

function valueFrom(option, parsed) {
  if (option.kind === "bool") return parsed && parsed.bool === true
  if (option.kind === "percent") return Math.round(numberFrom(parsed) * 100)
  return Math.round(numberFrom(parsed))
}

function parseRead(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var tab = line.indexOf("\t")
    if (tab < 0) continue
    var option = optionForHypr(line.substring(0, tab))
    if (!option) continue
    try {
      out[option.key] = valueFrom(option, JSON.parse(line.substring(tab + 1)))
    } catch (e) {
      // A malformed line leaves that one knob untouched.
    }
  }
  return out
}

// ---------------------------------------------------------------------------
// Writing: `hyprctl keyword` is dead on the Lua config parser, so every change
// goes through `hyprctl eval 'hl.config({ ... })'`. Only the keys we were given
// are touched, so callers can apply a single slider without disturbing the rest.
// ---------------------------------------------------------------------------

function luaBool(value) { return value === true || value === "true" ? "true" : "false" }

function luaFor(values) {
  if (!hasValues(values)) return ""

  var decoration = []
  var general = []
  var animations = []

  if (values.focusedOpacity !== undefined && values.focusedOpacity !== null)
    decoration.push("active_opacity = " + (Math.round(Number(values.focusedOpacity)) / 100).toFixed(2))
  if (values.unfocusedOpacity !== undefined && values.unfocusedOpacity !== null)
    decoration.push("inactive_opacity = " + (Math.round(Number(values.unfocusedOpacity)) / 100).toFixed(2))
  if (values.rounding !== undefined && values.rounding !== null)
    decoration.push("rounding = " + Math.round(Number(values.rounding)))
  if (values.blur !== undefined && values.blur !== null)
    decoration.push("blur = { enabled = " + luaBool(values.blur) + " }")
  if (values.shadows !== undefined && values.shadows !== null)
    decoration.push("shadow = { enabled = " + luaBool(values.shadows) + " }")

  if (values.gapsIn !== undefined && values.gapsIn !== null)
    general.push("gaps_in = " + Math.round(Number(values.gapsIn)))
  if (values.gapsOut !== undefined && values.gapsOut !== null)
    general.push("gaps_out = " + Math.round(Number(values.gapsOut)))
  if (values.borderWidth !== undefined && values.borderWidth !== null)
    general.push("border_size = " + Math.round(Number(values.borderWidth)))

  if (values.animations !== undefined && values.animations !== null)
    animations.push("enabled = " + luaBool(values.animations))

  var parts = []
  if (decoration.length) parts.push("decoration = { " + decoration.join(", ") + " }")
  if (general.length) parts.push("general = { " + general.join(", ") + " }")
  if (animations.length) parts.push("animations = { " + animations.join(", ") + " }")
  if (!parts.length) return ""

  return "hl.config({ " + parts.join(", ") + " })"
}

function evalCommand(values) {
  var lua = luaFor(values)
  if (lua === "") return []
  return ["hyprctl", "eval", lua]
}

function display(option, value) {
  if (option.kind === "bool") return value === true ? "On" : "Off"
  return String(Math.round(Number(value))) + option.unit
}
