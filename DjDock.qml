import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "qml"
import "Model.js" as Model

// omacrate docked on the left edge while the DJ runs in a terminal. The
// exclusive zone reserves the strip the way the bar does, so Hyprland tiles
// the terminal into the rest of the screen. Four tabs: what the DJ looked at
// last, the playlists, the library and the queue. Rows open and play as in
// the panel; the keyboard stays with the terminal. Every Text can hold server
// data, so every Text is plain.
PanelWindow {
  id: root

  required property var service

  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family
  // Hyprland keeps windows a full gaps_out from the edges; Style.gapsOut is half.
  readonly property real edgeGap: Style.gapsOut * 2
  readonly property real cardWidth: Style.space(360)
  readonly property string cli: service.cli

  property string tab: "dj"
  // Lists opened from a row, newest last; Back drops one.
  property var stack: []
  property bool loading: false
  property string message: ""
  property var recentRows: []
  property var artistRows: []
  property bool libraryLoaded: false

  readonly property var current: service.current
  readonly property var djView: service.djView
  readonly property var top: stack.length ? stack[stack.length - 1] : null
  // The list a track row plays from: an open album or playlist, or the
  // playlist the DJ just showed.
  readonly property var playView: {
    if (top) return top
    if (tab === "dj" && djView && djView.within === "playlist" && djView.changed)
      return { within: "playlist", key: djView.changed }
    return null
  }
  readonly property var rows: {
    if (top) return top.rows
    if (tab === "dj") return djView ? Model.rows(djView.items, djView.within) : []
    if (tab === "playlists") return Model.playlistRows(service.djPlaylists, service.djChanged)
    if (tab === "queue") return Model.queueRows(service.queue, service.position)
    return []
  }
  readonly property string emptyText: {
    if (loading) return "Loading."
    if (top) return "Nothing here."
    if (tab === "dj") return "When the DJ looks something up or changes a playlist, it shows here."
    if (tab === "playlists") return service.djPlaylistsLoaded ? "No playlists yet. Ask the DJ to make one." : "Loading playlists."
    if (tab === "queue") return "Nothing is queued."
    return ""
  }

  onTabChanged: {
    root.stack = []
    root.message = ""
    if (root.tab === "library") root.loadLibrary()
  }

  // A new DJ result brings the DJ tab forward, unless you are inside a list.
  Connections {
    target: root.service
    function onDjViewChanged() {
      if (root.service.djView && root.stack.length === 0) root.tab = "dj"
    }
  }

  function open(row) {
    var request = Model.listRequest(row)
    if (!request || listProc.running) return
    root.message = ""
    root.loading = true
    listProc.request = request
    listProc.command = [root.cli, "--json"].concat(request.args)
    listProc.running = true
  }

  function back() {
    root.message = ""
    if (root.stack.length) root.stack = root.stack.slice(0, root.stack.length - 1)
  }

  function activate(row, index) {
    if (!row) return
    if (Model.listRequest(row)) {
      root.open(row)
    } else if (row.kind === "queued") {
      root.service.jump(index)
    } else {
      root.act(Model.playArgs(row, index, root.playView, false))
    }
  }

  function act(args) {
    if (!args || actProc.running) return
    root.message = ""
    actProc.command = [root.cli].concat(args)
    actProc.running = true
  }

  function loadLibrary() {
    if (root.libraryLoaded || recentProc.running || artistsProc.running) return
    recentProc.command = [root.cli, "--json", "recent", "12"]
    recentProc.running = true
    artistsProc.command = [root.cli, "--json", "artists"]
    artistsProc.running = true
  }

  Process {
    id: listProc
    property var request: null
    running: false
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      var request = listProc.request
      listProc.request = null
      if (!request) return
      if (code !== 0) {
        root.message = Model.errorText(listErr.text) || "That list did not load."
        return
      }
      root.stack = root.stack.concat([{
        title: request.title, within: request.within, key: request.key,
        rows: Model.rows(Model.items(String(listOut.text || "")), request.within)
      }])
    }
  }

  Process {
    id: actProc
    running: false
    stderr: StdioCollector { id: actErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.message = Model.errorText(actErr.text) || "That did not work."
    }
  }

  Process {
    id: recentProc
    running: false
    stdout: StdioCollector { id: recentOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.recentRows = Model.rows(Model.items(String(recentOut.text || "")), "recent")
      root.libraryLoaded = !artistsProc.running
    }
  }

  Process {
    id: artistsProc
    running: false
    stdout: StdioCollector { id: artistsOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.artistRows = Model.rows(Model.items(String(artistsOut.text || "")), "artists")
      root.libraryLoaded = !recentProc.running
    }
  }

  screen: service.djScreen
  visible: service.djDockShown
  color: "transparent"

  WlrLayershell.namespace: "omacrate-dj-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: implicitWidth

  anchors {
    top: true
    bottom: true
    left: true
  }
  implicitWidth: edgeGap + cardWidth

  BorderSurface {
    id: card
    x: root.edgeGap
    y: root.edgeGap
    width: root.cardWidth
    height: parent.height - root.edgeGap * 2
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius
    clip: true

    Item {
      id: inner
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset

      // ---- Header: title, tabs, and the open list's own bar ----
      Column {
        id: header
        width: parent.width
        spacing: Style.spacing.lg

        PanelHero {
          width: parent.width
          title: "Omacrate"
          meta: "DJ"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            NoteIcon {
              size: Style.font.display
              iconColor: root.foreground
              strokeWidth: 1.75
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "\u{f0156}"
              tooltipText: "Close DJ"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.closeDj()
            }
          }
        }

        ButtonGroup {
          options: Model.dockTabs(root.service.queue.length)
          value: root.tab
          fontSize: Style.font.bodySmall
          focusable: false
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(value) { root.tab = value }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.md
          visible: root.top !== null || (root.tab === "dj" && root.djView !== null)

          PanelActionButton {
            visible: root.top !== null
            iconText: "\u{f0141}"
            tooltipText: "Back"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.back()
          }
          PanelSectionHeader {
            width: parent.width - x - (playButtons.visible ? playButtons.width + Style.spacing.md : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: root.top ? root.top.title : (root.djView ? root.djView.title : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          Row {
            id: playButtons
            spacing: Style.spacing.sm
            visible: root.playView !== null && Model.isKey(root.playView.key)

            PanelActionButton {
              iconText: "\u{f040a}"
              tooltipText: "Play"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.act(["play", root.playView.key])
            }
            PanelActionButton {
              iconText: "\u{f049d}"
              tooltipText: "Shuffle"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.act(["play", "--shuffle", root.playView.key])
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: text !== ""
          text: root.message
          color: Commons.Color.urgent
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // ---- The list ----
      Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.lg
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.spacing.lg
        width: parent.width
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
          id: scroll
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: body
          width: flick.width - (flick.interactive ? scroll.width + Style.space(6) : 0)
          spacing: Style.spacing.lg

          DockRows {
            width: parent.width
            visible: root.top !== null || root.tab !== "library"
            list: root.rows
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: function(row, index) { root.activate(row, index) }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: (root.top !== null || root.tab !== "library") && root.rows.length === 0 && text !== ""
            text: root.emptyText
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---- Library: recently added, then every artist ----
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.top === null && root.tab === "library"

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: !root.libraryLoaded
              text: "Loading the library."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            PanelSectionHeader {
              width: parent.width
              visible: root.recentRows.length > 0
              text: "Recently added"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            DockRows {
              width: parent.width
              list: root.recentRows
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onActivated: function(row, index) { root.activate(row, index) }
            }
            PanelSectionHeader {
              width: parent.width
              visible: root.artistRows.length > 0
              text: root.artistRows.length + " artists"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            DockRows {
              width: parent.width
              list: root.artistRows
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onActivated: function(row, index) { root.activate(row, index) }
            }
          }
        }
      }

      // ---- Now playing, one line with the controls ----
      Column {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        spacing: Style.spacing.md

        PanelSeparator { foreground: root.foreground }

        Row {
          width: parent.width
          spacing: Style.spacing.md

          Column {
            width: parent.width - controls.width - Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.current ? root.current.title : "Nothing is playing."
              color: root.current ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: text !== ""
              text: Model.nowLine(root.current)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Row {
            id: controls
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm
            visible: root.service.playing

            PanelActionButton {
              iconText: "\u{f04ae}"
              tooltipText: "Previous"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.previous()
            }
            PanelActionButton {
              iconText: root.service.paused ? "\u{f040a}" : "\u{f03e4}"
              tooltipText: root.service.paused ? "Resume" : "Pause"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.togglePause()
            }
            PanelActionButton {
              iconText: "\u{f04ad}"
              tooltipText: "Next"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.next()
            }
          }
        }
      }
    }
  }
}
