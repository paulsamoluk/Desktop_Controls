import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Desktop Controls — Hyprland window appearance, tuned from the bar.
//
// Everything is applied live through `hyprctl eval 'hl.config({ ... })'`
// (`hyprctl keyword` is refused by the Lua config parser) and read back with
// `hyprctl -j getoption`, so the sliders always show what the compositor is
// actually doing rather than what we last sent.
Panel {
  id: root
  moduleName: "psamoluk.desktop-controls"
  ipcTarget: "psamoluk.desktop-controls"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color barForeground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var opacityRows: Model.byGroup("opacity")
  readonly property var shapeRows: Model.byGroup("shape")
  readonly property var effectRows: Model.byGroup("effects")

  // Seeded with the shipped defaults so the first paint has numbers; the live
  // read replaces them as soon as it lands.
  property var values: Model.defaults()
  property var pending: ({})
  property double lastApplyAt: 0

  function valueFor(key) {
    var value = values[key]
    return value === undefined || value === null ? 0 : value
  }

  // ---------------------------------------------------------------------------
  // Persist one field into this widget's inline shell.json entry, preserving
  // every other field — the same approach the first-party panels use.
  // ---------------------------------------------------------------------------
  function persistKey(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    if (root.settings) for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---------------------------------------------------------------------------
  // Applying: only the keys handed in are touched, so one slider never
  // disturbs the rest of the desktop.
  // ---------------------------------------------------------------------------
  function applyChanges(changes, persist) {
    var next = {}
    for (var existing in values) next[existing] = values[existing]
    for (var key in changes) {
      next[key] = changes[key]
      if (persist === true) persistKey(key, changes[key])
    }
    values = next

    var lua = Model.luaFor(changes)
    if (lua === "") return
    writeProc.command = ["hyprctl", "eval", lua]
    writeProc.running = true
    lastApplyAt = Date.now()
  }

  // Dragging a slider fires on every step; hold the latest value and write it at
  // most once per frame-ish instead of once per event.
  function queueChange(key, value) {
    var next = {}
    for (var existing in pending) next[existing] = pending[existing]
    next[key] = value
    pending = next
    applyTimer.restart()
  }

  function flushPending(persist) {
    applyTimer.stop()
    if (!Model.hasValues(pending)) return
    var changes = pending
    pending = ({})
    applyChanges(changes, persist === true)
  }

  // Back to how the desktop looked before this plugin first changed anything.
  // Without a capture (fresh install, nothing saved yet) the shipped defaults
  // are the honest answer.
  function resetToCaptured() {
    var captured = {}
    for (var i = 0; i < Model.KEYS.length; i++) {
      var key = Model.KEYS[i]
      var value = root.settings ? root.settings[Model.baseKey(key)] : undefined
      if (value !== undefined && value !== null) captured[key] = value
    }
    if (!Model.hasValues(captured)) captured = Model.defaults()
    applyChanges(captured, true)
  }

  function refresh() {
    if (readProc.running) return
    readProc.command = Model.readCommand()
    readProc.running = true
  }

  onOpenedChanged: if (opened) refresh()
  Component.onCompleted: refresh()

  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A read that raced an apply (or a drag in progress) would only fight
        // the user; ignore it and wait for the next one.
        if (Date.now() - root.lastApplyAt < 1200) return
        var live = Model.parseRead(text)
        if (Model.hasValues(live)) root.values = live
      }
    }
  }

  Process {
    id: writeProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: applyTimer
    interval: 60
    onTriggered: root.flushPending(false)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          iconComponent: heroGlyph
          title: "Desktop Controls"
          meta: "WINDOW APPEARANCE"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        // ------------------------------ opacity ------------------------------
        Column {
          id: opacitySection
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "WINDOW OPACITY"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.opacityRows
            delegate: Column {
              required property var modelData
              width: opacitySection.width
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: Math.max(opacityLabel.implicitHeight, opacityValue.implicitHeight)

                Text {
                  id: opacityLabel
                  text: modelData.label
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: opacityValue
                  textFormat: Text.PlainText
                  text: Model.display(modelData, opacitySlider.dragging ? opacitySlider.liveValue : root.valueFor(modelData.key))
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: opacitySlider
                width: parent.width
                bar: root.bar
                minimum: modelData.min
                maximum: modelData.max
                step: modelData.step
                integer: true
                value: root.valueFor(modelData.key)
                onMoved: function(v) { root.queueChange(modelData.key, Math.round(v)) }
                onReleased: function(v) {
                  root.queueChange(modelData.key, Math.round(v))
                  root.flushPending(true)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // --------------------------- shape & spacing -------------------------
        Column {
          id: shapeSection
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "SHAPE & SPACING"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.shapeRows
            delegate: Column {
              required property var modelData
              width: shapeSection.width
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: Math.max(shapeLabel.implicitHeight, shapeValue.implicitHeight)

                Text {
                  id: shapeLabel
                  text: modelData.label
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: shapeValue
                  textFormat: Text.PlainText
                  text: Model.display(modelData, shapeSlider.dragging ? shapeSlider.liveValue : root.valueFor(modelData.key))
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: shapeSlider
                width: parent.width
                bar: root.bar
                minimum: modelData.min
                maximum: modelData.max
                step: modelData.step
                integer: true
                value: root.valueFor(modelData.key)
                onMoved: function(v) { root.queueChange(modelData.key, Math.round(v)) }
                onReleased: function(v) {
                  root.queueChange(modelData.key, Math.round(v))
                  root.flushPending(true)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ------------------------------- effects -----------------------------
        Column {
          id: effectsSection
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.effectRows
            delegate: Item {
              required property var modelData
              width: effectsSection.width
              implicitHeight: Math.max(effectLabel.implicitHeight, effectSwitch.implicitHeight)

              Text {
                id: effectLabel
                text: modelData.label
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                id: effectSwitch
                checked: root.values[modelData.key] === true
                foreground: root.barForeground
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onToggled: {
                  var changes = {}
                  changes[modelData.key] = !(root.values[modelData.key] === true)
                  root.applyChanges(changes, true)
                }
              }
            }
          }
        }

        Button {
          text: "Reset to default"
          fontSize: Style.font.bodySmall
          foreground: Qt.darker(root.barForeground, 1.3)
          anchors.right: parent.right
          onClicked: root.resetToCaptured()
        }
      }
    }
  }

  Component {
    id: heroGlyph

    OpticalGlyph {
      text: "\uF1DE"
      fontFamily: root.fontFamily
      fontSize: Style.font.display
      color: root.barForeground
    }
  }
}
