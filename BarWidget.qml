import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "qml"
import "Model.js" as Model

// A note on the bar, always. It is dimmed while nothing plays or the player
// is paused, and carries the track title while something plays.
BarWidget {
  id: root
  moduleName: "io.github.sette7blo.omacrate"

  readonly property string pluginDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/io.github.sette7blo.omacrate"

  // Service.qml instance, provided by Omarchy's plugin host.
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  readonly property var options: service ? service.options : Model.settings(settings)
  readonly property bool linked: service ? service.linked === true : false
  readonly property bool playing: service ? service.playing === true : false
  readonly property bool paused: service ? service.paused === true : false

  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  // Dim while nothing plays or the player is paused, like a locked wallet.
  readonly property color iconColor: playing && !paused ? foreground : dim

  // No server text in the tooltip: the bar draws it as rich text.
  readonly property string statusTooltip: !linked ? "Omacrate: not linked to Plex"
    : (!playing ? "Omacrate" : (paused ? "Omacrate: paused" : "Omacrate: playing"))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("service" in target) target.service = root.service
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onServiceChanged: injectPanel()

  // Panel contract for the bar's popout coordinator.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }
  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
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

  TextMetrics {
    id: titleMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: button.labelText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.iconColor
    iconComponent: Component {
      NoteIcon {
        size: Style.bar.iconCanvas
        iconColor: root.iconColor
        strokeWidth: 2.4

        Behavior on iconColor {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: Style.duration(160) }
        }
      }
    }
    // The slot is sized for a lone icon; widen it while the title shows.
    fixedWidth: vertical ? -1
      : slotSize + (labelText !== "" ? Math.ceil(titleMetrics.width) + Style.space(4) : 0)
    labelText: root.playing && root.options.showTitle && !root.vertical && root.service
      ? Model.barLabel(root.service.current) : ""
    tooltipText: root.statusTooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.togglePanel()
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.service) root.service.togglePause()
      } else if (buttonCode === Qt.RightButton) {
        if (root.service) root.service.next()
      }
    }
  }
}
