import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Desktop Controls — bar button, panel host, and the part that keeps Hyprland's
// runtime values honest.
//
// Hyprland forgets runtime `hl.config()` changes whenever it reloads its config
// (a theme switch, editing a .lua file, `omarchy restart hyprctl`), so the saved
// values are re-stated when the shell starts and the compositor is checked
// cheaply every few seconds for having drifted back.
BarWidget {
  id: root
  moduleName: "psamoluk.desktop-controls"

  readonly property string icon: "\uF1DE" // nf-fa-sliders
  readonly property string label: "Desktop Controls"

  property var live: ({})
  property double lastApplyAt: 0

  // ---------------------------------------------------------------------------
  // This widget's inline shell.json entry
  // ---------------------------------------------------------------------------
  function entryFields() {
    var out = { id: moduleName }
    if (settings) for (var k in settings) if (k !== "id") out[k] = settings[k]
    return out
  }

  function persist(fields) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = entryFields()
    for (var f in fields) entry[f] = fields[f]
    bar.shell.updateEntryInline(moduleName, entry)
  }

  function savedValues() {
    var out = {}
    for (var i = 0; i < Model.KEYS.length; i++) {
      var key = Model.KEYS[i]
      if (settings && settings[key] !== undefined && settings[key] !== null) out[key] = settings[key]
    }
    return out
  }

  function baseValues() {
    var out = {}
    for (var i = 0; i < Model.KEYS.length; i++) {
      var key = Model.KEYS[i]
      var base = settings ? settings[Model.baseKey(key)] : undefined
      if (base !== undefined && base !== null) out[key] = base
    }
    return out
  }

  // On first run, remember the desktop as it was before this plugin touched it,
  // so the panel's Reset has something honest to go back to.
  function captureBase(live) {
    if (!Model.hasValues(live)) return
    if (settings && settings.baseCaptured === true) return
    var fields = { baseCaptured: true }
    for (var key in live) fields[Model.baseKey(key)] = live[key]
    persist(fields)
  }

  // ---------------------------------------------------------------------------
  // Applying
  // ---------------------------------------------------------------------------
  function apply(values) {
    var command = Model.evalCommand(values)
    if (!command.length) return
    applyProc.command = command
    applyProc.running = true
    lastApplyAt = Date.now()
  }

  function applySaved() { apply(savedValues()) }

  // A config reload puts the compositor back on whatever the .lua files say.
  // If what it reports no longer matches what the panel saved, restate it.
  function checkDrift(live) {
    var saved = savedValues()
    if (!Model.hasValues(saved)) return
    if (Date.now() - lastApplyAt < 5000) return

    var drifted = false
    for (var key in saved) {
      if (Model.differs(key, live[key], saved[key])) {
        drifted = true
        break
      }
    }
    if (drifted) apply(saved)
  }

  // ---------------------------------------------------------------------------
  // Panel wiring (the contract the bar's popout coordinator expects)
  // ---------------------------------------------------------------------------
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: {
    readProc.command = Model.readCommand()
    Qt.callLater(function() {
      root.applySaved()
      driftTimer.start()
    })
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // One read answers both questions: what did the base look like, and has the
  // compositor drifted since the last apply.
  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = Model.parseRead(text)
        if (!Model.hasValues(values)) return
        root.live = values
        root.captureBase(values)
        root.checkDrift(values)
      }
    }
  }

  Timer {
    id: driftTimer
    interval: 8000
    repeat: true
    running: false
    onTriggered: if (!readProc.running && !applyProc.running) readProc.running = true
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    slotSize: Style.bar.statusSlot
    tooltipText: root.label
    onPressed: function(b) { root.togglePanel() }
  }
}
