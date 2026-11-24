import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "qml"
import "Model.js" as Model

// One panel: a header, four tabs over one list, a search box, and what is
// playing. A tab is filled by one omacrate command the first time it is
// shown; opening an artist, an album or a playlist stacks another list on
// top of it. Nothing is fetched ahead.
Panel {
  id: root
  moduleName: "io.github.sette7blo.omacrate"
  ipcTarget: "io.github.sette7blo.omacrate"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string cli: service ? service.cli : ""
  readonly property bool linked: service ? service.linked === true : false
  readonly property bool playing: service ? service.playing === true : false
  readonly property var current: service ? service.current : null
  readonly property string loginState: service ? service.loginState : ""
  readonly property string user: service ? service.link.user : ""
  // The Plex server and user the shown lists were read from.
  readonly property string connection: service ? service.link.connection : ""
  // Another account, user or server: everything shown came from the old one,
  // so it is dropped, with any action waiting on it, and read again.
  onConnectionChanged: {
    root.pendingRequest = null
    root.forget()
    if (root.linked) root.ensureTab()
  }
  readonly property bool home: service ? service.link.home === true : false
  readonly property bool djOn: service ? service.options.dj === true && service.agentReady === true : false

  property bool showSettings: false
  readonly property bool showLists: linked && !showSettings

  // --- Views ---------------------------------------------------------------
  // What the list shows is the top of `stack`, or else the search results
  // while there is a search, or else the tab.
  property string tab: "recent"
  property var tabViews: ({})
  property var searchView: null
  property string query: ""
  property var stack: []
  property int cursor: 0
  property bool loading: false
  property string message: ""
  property var pendingRequest: null

  readonly property int staleSeconds: 300
  readonly property var queueView: ({ title: "Queue", within: "queue", key: "", rows: [], cursor: 0 })
  readonly property var baseView: query !== "" ? searchView : (tab === "queue" ? queueView : (tabViews[tab] || null))
  readonly property var view: stack.length ? stack[stack.length - 1] : baseView
  readonly property bool inList: stack.length > 0 || query !== ""
  readonly property var rows: {
    if (!linked || !service || !view) return []
    if (view.within === "queue") return Model.queueRows(service.queue, service.position)
    return view.rows
  }

  readonly property string heroMeta: {
    if (!service) return ""
    if (showSettings) return "Settings"
    if (!linked) return loginState === "waiting" ? "Waiting for the code" : "Not linked"
    return Model.linkSummary(service.link)
  }

  readonly property string emptyText: {
    if (loading) return "Loading."
    if (!view) return ""
    if (view.within === "search") return "Nothing matches."
    if (view.within === "queue") return "Nothing is queued. Play something from the other lists."
    if (view.within === "playlists") return "This user has no playlists."
    return "Nothing here."
  }

  function showStacked(next) {
    if (root.view) root.view.cursor = root.cursor
    root.stack = root.stack.concat([next])
    root.cursor = 0
  }

  function back() {
    root.message = ""
    if (root.stack.length) {
      var rest = root.stack.slice(0, root.stack.length - 1)
      root.stack = rest
      var below = rest.length ? rest[rest.length - 1] : root.baseView
      root.cursor = below ? (below.cursor || 0) : 0
    } else if (searchField.text !== "") {
      searchField.text = ""
    }
  }

  function selectTab(name) {
    root.message = ""
    root.stack = []
    root.tab = name
    root.cursor = name === "queue" && root.service ? Math.max(0, root.service.position) : 0
    if (searchField.text !== "") searchField.text = ""
    root.query = ""
    ensureTab()
  }

  function ensureTab() {
    if (!root.opened || !root.linked || root.query !== "") return
    var request = Model.tabRequest(root.tab)
    if (!request) return
    var have = root.tabViews[root.tab]
    if (have && Date.now() - have.at < root.staleSeconds * 1000) return
    request.target = "tab:" + root.tab
    load(request)
  }

  function forget() {
    root.tabViews = ({})
    root.searchView = null
    root.stack = []
    root.cursor = 0
    root.message = ""
    root.query = ""
    if (searchField.text !== "") searchField.text = ""
  }

  function move(delta) {
    if (!root.rows.length) return
    root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + delta))
  }

  onCursorChanged: list.positionViewAtIndex(root.cursor, ListView.Contain)
  onRowsChanged: if (root.cursor >= root.rows.length) root.cursor = Math.max(0, root.rows.length - 1)

  // --- Reading from the server ---------------------------------------------
  // One request at a time. A newer one waits for the running one to end and
  // replaces whatever was waiting, so fast typing costs one search, not ten.
  function load(request) {
    if (!root.cli) return
    request.connection = root.connection
    root.message = ""
    root.loading = true
    if (listProc.running) {
      // The same request on the same connection is already on its way.
      var running = listProc.request
      if (running && running.target === request.target && running.connection === request.connection
          && JSON.stringify(running.args) === JSON.stringify(request.args)) {
        root.pendingRequest = null
        return
      }
      root.pendingRequest = request
      return
    }
    launch(request)
  }

  // Each request carries the connection it was asked on; the CLI refuses it
  // on any other, and an answer that arrives after a change is dropped.
  function launch(request) {
    if (!request.connection) request.connection = root.connection
    listProc.request = request
    listProc.command = [root.cli, "--json", "--connection", request.connection].concat(request.args)
    listProc.running = true
  }

  function search() {
    debounce.stop()
    var term = searchField.text.replace(/^\s+|\s+$/g, "")
    if (term.length < 2) {
      if (root.query === "") return
      root.query = ""
      root.searchView = null
      root.stack = []
      root.cursor = 0
      root.pendingRequest = null
      ensureTab()
      return
    }
    root.query = term
    root.stack = []
    load({ args: ["search", term], within: "search", title: "Search results", key: "", target: "search" })
  }

  function showUsers() {
    var request = Model.usersRequest()
    request.target = "stack"
    load(request)
  }

  function reload() {
    var views = ({})
    for (var k in root.tabViews) if (k !== root.tab) views[k] = root.tabViews[k]
    root.tabViews = views
    root.stack = []
    root.ensureTab()
  }

  Timer {
    id: debounce
    interval: 280
    onTriggered: root.search()
  }

  Process {
    id: listProc
    property var request: null
    running: false
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: function(code) {
      var request = listProc.request
      listProc.request = null
      if (root.pendingRequest) {
        var next = root.pendingRequest
        root.pendingRequest = null
        Qt.callLater(root.launch, next)
        return
      }
      root.loading = false
      if (!request) return
      if (request.connection !== root.connection) return
      if (code !== 0) {
        root.message = Model.errorText(listErr.text) || "The Plex server did not answer."
        return
      }
      var made = {
        title: request.title, within: request.within, key: request.key, cursor: 0, at: Date.now(),
        connection: request.connection,
        rows: request.within === "users" ? Model.userRows(listOut.text)
          : Model.rows(Model.items(listOut.text), request.within)
      }
      if (request.target === "search") {
        // The box was cleared while this search ran.
        if (root.query === "") return
        root.searchView = made
        root.stack = []
        root.cursor = 0
      } else if (request.target.indexOf("tab:") === 0) {
        var name = request.target.slice(4)
        var views = ({})
        for (var k in root.tabViews) views[k] = root.tabViews[k]
        views[name] = made
        root.tabViews = views
        if (!root.inList && root.tab === name) root.cursor = 0
      } else {
        root.showStacked(made)
      }
    }
  }

  // --- Playing -------------------------------------------------------------
  // done and failed are optional; without failed, an error shows in the panel.
  function act(args, done, failed) {
    if (!args || !root.cli || actProc.running) return
    root.message = ""
    actProc.done = done || null
    actProc.failed = failed || null
    actProc.command = [root.cli].concat(args)
    actProc.running = true
  }

  Process {
    id: actProc
    property var done: null
    property var failed: null
    running: false
    stderr: StdioCollector { id: actErr; waitForEnd: true }
    onExited: function(code) {
      var done = actProc.done
      var failed = actProc.failed
      actProc.done = null
      actProc.failed = null
      if (code === 0) {
        if (done) done()
        return
      }
      var error = Model.errorText(actErr.text) || "That did not work."
      if (failed) failed(error)
      else root.message = error
    }
  }

  function activate(index, drillOnly) {
    var row = root.rows[index]
    if (!row || !root.service) return
    root.cursor = index
    var request = Model.listRequest(row)
    if (request) {
      request.target = "stack"
      load(request)
      return
    }
    if (drillOnly) return
    if (row.kind === "user") {
      if (row.locked) root.message = "This user has a PIN. Run omacrate user in a terminal to switch."
      else act(Model.userArgs(row))
    } else if (row.kind === "queued") {
      root.service.jump(index)
    } else {
      act(Model.playArgs(row, index, root.view, false))
    }
  }

  function playSelected(shuffle) {
    act(Model.playArgs(root.rows[root.cursor], root.cursor, null, shuffle))
  }

  function addSelected() {
    act(Model.addArgs(root.rows[root.cursor]))
  }

  function askDj() {
    if (!root.cli) return
    if (root.service && root.service.options.djDock) root.service.startDj()
    else Util.execArgv([root.cli, "dj"])
    close()
  }

  function openLinkPage() {
    Util.execArgv(["xdg-open", "https://plex.tv/link"])
  }

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  Connections {
    target: root
    function onOpenedChanged() {
      if (root.service) root.service.panelOpen = root.opened
      if (!root.opened) {
        root.showSettings = false
        return
      }
      root.ensureTab()
      Qt.callLater(function() {
        if (root.linked) root.focusSearch()
        else keys.forceActiveFocus()
      })
    }
  }

  // Another user has other playlists, and a new link is another library.
  onUserChanged: {
    root.forget()
    root.ensureTab()
  }

  onLinkedChanged: {
    root.forget()
    root.ensureTab()
    if (root.opened && root.linked) Qt.callLater(root.focusSearch)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.linked ? searchField : keys
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(720))

    // Keys for the list. The search box has its own below; this item holds
    // the focus whenever the box does not.
    Item {
      id: keys
      focus: true
      Keys.onPressed: function(event) {
        var key = event.key
        var letter = event.text
        var svc = root.service
        if (key === Qt.Key_Escape) {
          // Out of the settings or a list first, out of the panel after that.
          if (root.showSettings) root.showSettings = false
          else if (root.linked && root.inList) root.back()
          else root.close()
        } else if (root.showSettings) {
          return
        } else if (!root.linked) {
          if (key !== Qt.Key_Return && key !== Qt.Key_Enter) return
          if (root.loginState === "waiting") root.openLinkPage()
          else if (svc) svc.startLogin()
        } else if (key === Qt.Key_Tab) {
          root.selectTab(Model.nextTab(root.tab, 1))
        } else if (key === Qt.Key_Backtab) {
          root.selectTab(Model.nextTab(root.tab, -1))
        } else if (key === Qt.Key_Down || letter === "j") {
          root.move(1)
        } else if (key === Qt.Key_Up || letter === "k") {
          if (root.cursor === 0) root.focusSearch()
          else root.move(-1)
        } else if (key === Qt.Key_PageDown) {
          root.move(10)
        } else if (key === Qt.Key_PageUp) {
          root.move(-10)
        } else if (key === Qt.Key_Home || letter === "g") {
          root.cursor = 0
        } else if (key === Qt.Key_End || letter === "G") {
          root.cursor = Math.max(0, root.rows.length - 1)
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
          root.activate(root.cursor, false)
        } else if (key === Qt.Key_Right || letter === "l") {
          root.activate(root.cursor, true)
        } else if (key === Qt.Key_Backspace || key === Qt.Key_Left || letter === "h") {
          root.back()
        } else if (key === Qt.Key_Space) {
          if (svc) svc.togglePause()
        } else if (letter === "p") {
          root.playSelected(false)
        } else if (letter === "s") {
          root.playSelected(true)
        } else if (letter === "a") {
          root.addSelected()
        } else if (letter === "n") {
          if (svc) svc.next()
        } else if (letter === "b") {
          if (svc) svc.previous()
        } else if (letter === ",") {
          if (svc && svc.playing) svc.seek(svc.time - 10)
        } else if (letter === ".") {
          if (svc && svc.playing) svc.seek(svc.time + 10)
        } else if (letter === "-") {
          if (svc && svc.playing) svc.nudgeVolume(-5)
        } else if (letter === "=" || letter === "+") {
          if (svc && svc.playing) svc.nudgeVolume(5)
        } else if (letter === "m") {
          if (svc && svc.playing) svc.toggleMute()
        } else if (letter === "d") {
          if (root.djOn) root.askDj()
        } else if (letter === "u") {
          if (root.home) root.showUsers()
        } else if (letter === "/") {
          root.focusSearch()
        } else {
          return
        }
        event.accepted = true
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.spacing.xxl

      PanelHero {
        id: hero
        title: "Omacrate"
        meta: root.heroMeta
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
          Row {
            spacing: Style.spacing.md

            PanelActionButton {
              visible: root.showLists
              iconText: "\u{f0450}"
              tooltipText: "Reload this list"
              opacity: root.loading ? 0.45 : 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.reload()
            }
            PanelActionButton {
              iconText: root.showSettings ? "\u{f0156}" : "\u{f0493}"
              tooltipText: root.showSettings ? "Close settings" : "Settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                keys.forceActiveFocus()
                root.showSettings = !root.showSettings
              }
            }
          }
        }
      }

      PanelSeparator {
        id: heroSeparator
        foreground: root.foreground
      }

      // ---- Settings ----
      // They scroll inside whatever height the panel has left below the
      // header, so the DJ switches at the bottom stay reachable.
      Flickable {
        id: settingsScroller
        width: parent.width
        readonly property real panelCap: Math.min(Style.space(720),
          panel.availableCardHeight > 0 ? panel.availableCardHeight - panel.verticalContentInset : Style.space(720))
        height: Math.max(0, Math.min(contentHeight,
          panelCap - hero.height - heroSeparator.height - body.spacing * 2))
        visible: root.showSettings
        contentWidth: width
        contentHeight: settingsLoader.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
          id: settingsScroll
          policy: ScrollBar.AsNeeded
        }

        Loader {
          id: settingsLoader
          width: settingsScroller.width - (settingsScroller.interactive ? settingsScroll.width + Style.space(6) : 0)
          active: root.showSettings
          sourceComponent: Component {
            SettingsView {
              width: settingsLoader.width
              service: root.service
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onSwitchUser: {
                root.showSettings = false
                root.showUsers()
              }
              onLinkAccount: {
                root.showSettings = false
                if (root.service) root.service.startLogin()
              }
            }
          }
        }
      }

      // ---- Not linked ----
      Column {
        width: parent.width
        spacing: Style.spacing.lg
        visible: !root.linked && !root.showSettings

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.loginState === "waiting"
            ? "Enter this code at plex.tv/link. This panel links itself once you have."
            : "Link Omacrate to your Plex account to play your music library."
          color: root.foreground
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          visible: root.loginState === "waiting"
          text: root.service ? root.service.loginCode : ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.letterSpacing: Style.space(6)
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.loginState === "failed"
          text: root.service ? root.service.loginError : ""
          color: Commons.Color.urgent
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Row {
          spacing: Style.spacing.lg

          Button {
            visible: root.loginState !== "waiting"
            text: root.loginState === "starting" ? "Getting a code" : "Link Plex"
            enabled: root.loginState !== "starting"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.startLogin()
          }
          Button {
            visible: root.loginState === "waiting"
            text: "Open plex.tv/link"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.openLinkPage()
          }
          Button {
            visible: root.loginState === "waiting"
            text: "Cancel"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.cancelLogin()
          }
        }
      }

      // ---- Tabs ----
      ButtonGroup {
        visible: root.showLists
        options: Model.tabs(root.playing && root.service ? root.service.queue.length : 0)
        value: root.inList ? "" : root.tab
        fontSize: Style.font.bodySmall
        focusable: false
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onChanged: function(value) {
          keys.forceActiveFocus()
          root.selectTab(value)
        }
      }

      // ---- Search ----
      TextField {
        id: searchField
        width: parent.width
        visible: root.showLists
        placeholderText: "Search artists, albums and tracks"
        foreground: root.foreground
        accent: root.accent
        onTextChanged: debounce.restart()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (searchField.text !== "") searchField.text = ""
            else if (root.inList) root.back()
            else root.close()
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            keys.forceActiveFocus()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (debounce.running) root.search()
            keys.forceActiveFocus()
          } else {
            return
          }
          event.accepted = true
        }
      }

      // ---- List, under a heading once it is not the tab itself ----
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.showLists

        RowLayout {
          width: parent.width
          spacing: Style.spacing.md
          visible: root.inList

          PanelActionButton {
            iconText: "\u{f0141}"
            tooltipText: "Back"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              keys.forceActiveFocus()
              root.back()
            }
          }
          PanelSectionHeader {
            Layout.fillWidth: true
            text: root.view ? root.view.title : (root.loading ? "Loading" : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          Text {
            textFormat: Text.PlainText
            visible: root.rows.length > 0
            text: root.rows.length === 1 ? "1 item" : root.rows.length + " items"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(330))
          visible: count > 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.rows
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: RowItem {
            required property var modelData
            required property int index
            width: list.width
            entry: modelData
            selected: keys.activeFocus && index === root.cursor
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: {
              keys.forceActiveFocus()
              root.activate(index, false)
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: list.count === 0 && text !== ""
          text: root.emptyText
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
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

      // ---- Now playing ----
      PanelSeparator {
        foreground: root.foreground
        visible: nowPlaying.visible
      }

      Column {
        id: nowPlaying
        width: parent.width
        spacing: Style.spacing.md
        visible: root.showLists && root.playing && root.current !== null

        PanelSectionHeader {
          text: root.service && root.service.paused ? "Paused" : "Now playing"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.spacing.xxs

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.current ? root.current.title : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            text: Model.nowLine(root.current)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.lg

          Text {
            textFormat: Text.PlainText
            text: root.service ? Model.clock(root.service.time) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            Layout.fillWidth: true
            bar: root.bar
            minimum: 0
            maximum: root.service ? Math.max(1, root.service.duration) : 1
            value: root.service ? Math.min(root.service.time, maximum) : 0
            integer: true
            step: 5
            onReleased: function(value) { if (root.service) root.service.seek(value) }
          }
          Text {
            textFormat: Text.PlainText
            text: root.service ? Model.clock(root.service.duration) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xxl

          PanelActionButton {
            iconText: "\u{f04ae}"
            tooltipText: "Previous"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.previous()
          }
          PanelActionButton {
            iconText: root.service && root.service.paused ? "\u{f040a}" : "\u{f03e4}"
            tooltipText: root.service && root.service.paused ? "Play" : "Pause"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.togglePause()
          }
          PanelActionButton {
            iconText: "\u{f04ad}"
            tooltipText: "Next"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.next()
          }
          PanelActionButton {
            iconText: "\u{f04db}"
            tooltipText: "Stop"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.stop()
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.lg

          PanelActionButton {
            iconText: root.service ? Model.volumeGlyph(root.service.volume, root.service.muted) : ""
            tooltipText: root.service && root.service.muted ? "Unmute" : "Mute"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.toggleMute()
          }
          PanelSlider {
            Layout.fillWidth: true
            bar: root.bar
            minimum: 0
            maximum: 100
            value: root.service ? (root.service.muted ? 0 : root.service.volume) : 0
            integer: true
            step: 5
            onMoved: function(value) { if (root.service) root.service.setVolume(value) }
            onReleased: function(value) { if (root.service) root.service.setVolume(value) }
            onRightClicked: if (root.service) root.service.toggleMute()
          }
          Text {
            textFormat: Text.PlainText
            Layout.minimumWidth: Style.space(30)
            horizontalAlignment: Text.AlignRight
            text: root.service ? (root.service.muted ? "muted" : root.service.volume + "%") : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator {
        foreground: root.foreground
        visible: root.showLists
      }

      // ---- Actions ----
      Button {
        width: parent.width
        visible: root.showLists && root.djOn
        text: "Ask DJ"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.askDj()
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.showLists
        text: Model.hints(keys.activeFocus ? root.rows[root.cursor] : null, root.playing, root.inList)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }
}
