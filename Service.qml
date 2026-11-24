import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// Background service. It never polls: it watches two small files the omacrate
// command writes, and while music plays it listens on mpv's own socket, which
// tells it when the track or the pause state changes. With nothing playing
// there is no process, no timer and no connection.
Item {
  id: root

  property var shell: null
  property bool panelOpen: false

  // --- Filesystem layout (same rules as bin/omacrate) ----------------------
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/omacrate"
  readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || stateDir) + "/omacrate"
  readonly property string pluginDir: home + "/.config/omarchy/plugins/" + Model.PLUGIN_ID
  readonly property string cli: pluginDir + "/bin/omacrate"

  // --- Settings (the widget's entry in shell.json) --------------------------
  property var options: Model.settings(null)

  function loadSettings() {
    var sh = root.shell
    var cfg = sh ? (sh.shellConfig || (sh.barConfig ? { bar: sh.barConfig } : null)) : null
    var next = Model.pluginSettings(cfg)
    if (JSON.stringify(next) !== JSON.stringify(root.options)) root.options = next
  }

  function persistSettings(patch) {
    var current = Model.settings(root.options)
    var extra = patch && typeof patch === "object" ? patch : {}
    for (var k in extra) current[k] = extra[k]
    current = Model.settings(current)
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(Model.PLUGIN_ID, Model.settingsPayload(current))
    root.options = current
  }

  onShellChanged: root.loadSettings()

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onBarConfigChanged() { root.loadSettings() }
    function onShellConfigChanged() { root.loadSettings() }
  }

  // --- Link state ----------------------------------------------------------
  property var link: Model.linkInfo("")
  readonly property bool linked: link.linked

  // --- Player state --------------------------------------------------------
  property var queue: []
  property bool connected: false
  property int position: -1
  property bool paused: false
  property bool idle: true
  property int duration: 0
  property int time: 0
  // mpv's own volume (0-100), not the system mixer. Kept across player
  // restarts by bin/omacrate, so the last value is shown until mpv reports.
  property int volume: 100
  property bool muted: false

  readonly property bool playing: connected && !idle && position >= 0
  readonly property var current: playing && position < queue.length ? queue[position] : null

  // --- Login with a code ---------------------------------------------------
  // "" when nothing is going on, then starting, waiting or failed.
  property string loginState: ""
  property string loginCode: ""
  property string loginError: ""

  // Whether Omarchy has a default agent the DJ can open. Looked at only when
  // the DJ is switched on in the settings, and then only as the panel opens.
  property bool agentReady: false
  // Why the DJ cannot open an agent, shown in the settings.
  property string agentNote: ""

  function checkAgent() {
    if (!root.options.dj) {
      root.agentReady = false
      return
    }
    if (!root.panelOpen || statusProc.running) return
    statusProc.command = [root.cli, "--json", "status"]
    statusProc.running = true
  }

  onOptionsChanged: {
    root.checkAgent()
    // Switching the DJ or the dock off takes the dock down; the terminal stays.
    if (root.djDocked && (!root.options.dj || !root.options.djDock)) root.closeDjDock()
  }

  // --- Agent skills --------------------------------------------------------
  // "" until checked, then installed, none or unavailable. Linked only when
  // the user presses the button in the settings.
  property string skillsState: ""
  property bool skillsBusy: false

  function checkSkills() {
    if (skillsProc.running) return
    skillsProc.statusRun = true
    skillsProc.command = [root.pluginDir + "/install.sh", "--skills-status"]
    skillsProc.running = true
  }

  function setSkills(install) {
    if (skillsProc.running) return
    root.skillsBusy = true
    skillsProc.statusRun = false
    skillsProc.command = install
      ? [root.pluginDir + "/install.sh", "--if-needed", "--skills"]
      : [root.pluginDir + "/uninstall.sh", "--skills"]
    skillsProc.running = true
  }

  Process {
    id: skillsProc
    property bool statusRun: false
    running: false
    stdout: StdioCollector { id: skillsOut; waitForEnd: true }
    onExited: function(code) {
      if (skillsProc.statusRun) {
        var word = String(skillsOut.text || "").trim()
        if (word === "installed" || word === "none" || word === "unavailable") root.skillsState = word
        return
      }
      root.skillsBusy = false
      Qt.callLater(root.checkSkills)
    }
  }

  // --- Lidarr --------------------------------------------------------------
  // Only the address is read back; the key goes into the command on stdin
  // and is never shown again.
  property string lidarrAddress: ""
  property bool lidarrDj: false
  property bool lidarrAllowHttp: false
  property bool lidarrBusy: false
  property string lidarrMessage: ""
  property bool lidarrFailed: false
  property string pendingLidarrKey: ""

  function checkLidarr() {
    if (lidarrProc.running) return
    lidarrProc.mode = "address"
    lidarrProc.command = [root.cli, "--json", "lidarr", "address"]
    lidarrProc.running = true
  }

  function saveLidarr(address, key, allowHttp) {
    if (lidarrProc.running) return
    root.lidarrBusy = true
    root.lidarrMessage = ""
    root.lidarrFailed = false
    root.pendingLidarrKey = String(key || "").replace(/\s+/g, "")
    lidarrProc.mode = "set"
    lidarrProc.command = allowHttp
      ? [root.cli, "lidarr", "set", "--allow-http", String(address || "").trim()]
      : [root.cli, "lidarr", "set", String(address || "").trim()]
    lidarrProc.running = true
  }

  // Whether the DJ may use Lidarr; kept by the CLI next to the key.
  function setLidarrDj(on) {
    if (lidarrProc.running) return
    root.lidarrDj = on
    lidarrProc.mode = "dj"
    lidarrProc.command = [root.cli, "lidarr", "dj", on ? "on" : "off"]
    lidarrProc.running = true
  }

  function removeLidarr() {
    if (lidarrProc.running) return
    root.lidarrBusy = true
    root.lidarrMessage = ""
    root.lidarrFailed = false
    lidarrProc.mode = "unset"
    lidarrProc.command = [root.cli, "lidarr", "unset"]
    lidarrProc.running = true
  }

  Process {
    id: lidarrProc
    property string mode: ""
    running: false
    stdinEnabled: true
    stdout: StdioCollector { id: lidarrOut; waitForEnd: true }
    stderr: StdioCollector { id: lidarrErr; waitForEnd: true }
    onRunningChanged: {
      if (running && lidarrProc.mode === "set") {
        lidarrProc.write(root.pendingLidarrKey + "\n")
        root.pendingLidarrKey = ""
      }
    }
    onExited: function(code) {
      var mode = lidarrProc.mode
      lidarrProc.mode = ""
      if (mode === "address") {
        var data = null
        try { data = JSON.parse(String(lidarrOut.text || "")) } catch (e) { data = null }
        root.lidarrAddress = data && typeof data.address === "string" ? data.address : ""
        root.lidarrDj = !!(data && data.dj === true)
        root.lidarrAllowHttp = !!(data && data.allowHttp === true)
        return
      }
      if (mode === "dj") {
        Qt.callLater(root.checkLidarr)
        return
      }
      root.lidarrBusy = false
      if (code === 0) {
        root.lidarrFailed = false
        root.lidarrMessage = mode === "set" ? (String(lidarrOut.text || "").trim() || "Saved.") : "Removed."
      } else {
        root.lidarrFailed = true
        root.lidarrMessage = Model.errorText(lidarrErr.text) || "Lidarr did not answer."
      }
      Qt.callLater(root.checkLidarr)
    }
  }

  // --- Logout --------------------------------------------------------------
  function logout() {
    if (logoutProc.running) return
    logoutProc.command = [root.cli, "logout"]
    logoutProc.running = true
  }

  Process {
    id: logoutProc
    running: false
    onExited: function(code) { credentials.reload() }
  }

  // --- Player commands -----------------------------------------------------
  function send(argv) {
    if (!root.connected) return
    mpv.write(Model.mpvLine(argv, 0))
    mpv.flush()
  }

  function askTime() {
    if (!root.connected) return
    mpv.write(Model.mpvLine(["get_property", "time-pos"], Model.TIME_REQUEST))
    mpv.flush()
  }

  function togglePause() { send(["cycle", "pause"]) }
  function next() { send(["playlist-next", "weak"]) }
  function previous() { send(["playlist-prev", "weak"]) }
  function stop() { send(["quit"]) }

  function seek(seconds) {
    var target = Math.max(0, Math.floor(Number(seconds) || 0))
    root.time = target
    send(["seek", target, "absolute"])
  }

  // Sent to mpv at once while the slider moves; saved through the command a
  // moment after the last change, so dragging does not start one process per
  // step.
  function setVolume(value) {
    var v = Math.max(0, Math.min(100, Math.round(Number(value) || 0)))
    root.volume = v
    send(["set_property", "volume", v])
    if (root.muted && v > 0) send(["set_property", "mute", false])
    volumeSave.restart()
  }

  function nudgeVolume(delta) { root.setVolume(Model.volumeStep(root.volume, delta)) }
  function toggleMute() { send(["cycle", "mute"]) }

  Timer {
    id: volumeSave
    interval: 500
    onTriggered: {
      if (volumeProc.running) {
        volumeSave.restart()
        return
      }
      volumeProc.command = [root.cli, "volume", String(root.volume)]
      volumeProc.running = true
    }
  }

  Process {
    id: volumeProc
    running: false
  }

  function jump(index) {
    var i = Math.floor(Number(index))
    if (!(i >= 0 && i < root.queue.length)) return
    send(["playlist-play-index", i])
    send(["set_property", "pause", false])
  }

  // The command starts mpv, then saves the queue; that save is what brings
  // the service to the socket.
  function reachPlayer() {
    if (!mpv.connected) mpv.connected = true
  }

  function playerGone() {
    root.connected = false
    root.position = -1
    root.paused = false
    root.idle = true
    root.duration = 0
    root.time = 0
  }

  function handleLine(line) {
    var event = Model.mpvEvent(line)
    if (!event) return
    if (event.name === "position") {
      root.position = event.value
      root.time = 0
      if (root.panelOpen) root.askTime()
    } else if (event.name === "pause") {
      root.paused = event.value
    } else if (event.name === "idle-active") {
      root.idle = event.value
    } else if (event.name === "volume") {
      // While the slider is being saved, mpv echoes the value just sent.
      if (!volumeSave.running) root.volume = Math.min(100, event.value)
    } else if (event.name === "mute") {
      root.muted = event.value
    } else if (event.name === "duration") {
      root.duration = event.value
    } else if (event.name === "time") {
      root.time = event.value
    } else if (event.name === "moved") {
      if (root.panelOpen) root.askTime()
    }
  }

  Socket {
    id: mpv
    path: root.runDir + "/mpv.sock"
    parser: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    onConnectedChanged: {
      if (mpv.connected) {
        root.connected = true
        mpv.write(Model.mpvSubscribe())
        mpv.flush()
        root.askTime()
      } else {
        root.playerGone()
      }
    }
  }

  // The seek bar is the only thing that needs the clock, so it is asked for
  // only while the panel is open and a track is running.
  Timer {
    interval: 1000
    repeat: true
    running: root.panelOpen && root.playing && !root.paused
    onTriggered: root.askTime()
  }

  // --- Login ---------------------------------------------------------------
  function startLogin() {
    if (loginProc.running) return
    root.loginState = "starting"
    root.loginCode = ""
    root.loginError = ""
    loginProc.waiting = false
    loginProc.command = [root.cli, "--json", "login", "--start"]
    loginProc.running = true
  }

  function cancelLogin() {
    loginProc.cancelled = true
    loginProc.running = false
    root.loginState = ""
    root.loginCode = ""
  }

  function waitForCode(id) {
    loginProc.waiting = true
    loginProc.command = [root.cli, "login", "--wait", id]
    loginProc.running = true
  }

  Process {
    id: loginProc
    property bool waiting: false
    property bool cancelled: false
    running: false
    stdout: StdioCollector { id: loginOut; waitForEnd: true }
    stderr: StdioCollector { id: loginErr; waitForEnd: true }
    onExited: function(code) {
      if (loginProc.cancelled) {
        loginProc.cancelled = false
        return
      }
      if (code !== 0) {
        root.loginState = "failed"
        root.loginCode = ""
        root.loginError = Model.errorText(loginErr.text) || "Could not reach plex.tv."
        return
      }
      if (loginProc.waiting) {
        root.loginState = ""
        root.loginCode = ""
        credentials.reload()
        return
      }
      var pin = Model.pin(loginOut.text)
      if (!pin) {
        root.loginState = "failed"
        root.loginError = "plex.tv did not give a code."
        return
      }
      root.loginCode = pin.code
      root.loginState = "waiting"
      Qt.callLater(root.waitForCode, pin.id)
    }
  }

  // --- Files ---------------------------------------------------------------
  FileView {
    id: credentials
    path: root.stateDir + "/credentials.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = Model.linkInfo(text())
      if (!Model.sameLink(next, root.link)) root.link = next
    }
    onLoadFailed: root.link = Model.linkInfo("")
    onFileChanged: reload()
  }

  FileView {
    id: queueFile
    path: root.stateDir + "/queue.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.queue = Model.parseQueue(text())
      // An empty queue means nothing was started, so there is no socket.
      if (root.queue.length) root.reachPlayer()
    }
    onLoadFailed: root.queue = []
    onFileChanged: reload()
  }

  // --- Lifecycle -----------------------------------------------------------
  // install.sh --if-needed finishes what omarchy plugin add does not (the
  // command and the launcher) and exits at once when that is already done.
  // It never links the agent skills; that takes install.sh --skills by hand.
  Process {
    id: installProc
    running: false
  }

  // Creates the private state folder and the two files, so the watchers
  // above have something to watch before the first login.
  Process {
    id: prepareProc
    running: false
    onExited: function(code) {
      credentials.reload()
      queueFile.reload()
    }
  }

  Process {
    id: statusProc
    running: false
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(code) {
      var data = null
      try { data = JSON.parse(String(statusOut.text || "")) } catch (e) { data = null }
      root.agentReady = code === 0 && !!data && data.agent === true
      root.agentNote = !root.agentReady && data && typeof data.agentNote === "string" ? Model.text(data.agentNote, 200) : ""
    }
  }

  onPanelOpenChanged: {
    if (!root.panelOpen) return
    root.askTime()
    root.checkAgent()
  }

  Component.onCompleted: {
    prepareProc.command = [root.cli, "prepare"]
    prepareProc.running = true
    installProc.command = [root.pluginDir + "/install.sh", "--if-needed"]
    installProc.running = true
  }

  // --- DJ dock --------------------------------------------------------------
  // With the dock switched on, Ask DJ docks a panel on the left edge and opens
  // the DJ terminal, which Hyprland tiles into the space left over. The
  // terminal is detached, so it is followed by its window: `omacrate dj`
  // launches it with the app-id below, used by no other agent window, and the
  // DJ's is the first one with it that was not open before the launch. Nothing
  // here runs unless the DJ and the dock are both on and Ask DJ was pressed.
  readonly property string djAppId: "org.omarchy.agent.omacrate"
  property bool djDocked: false
  property string djMonitorName: ""
  property string djAddress: ""
  property var djKnownAddresses: []
  // Set when the dock is closed before its terminal has appeared, so the
  // terminal is closed as soon as it does.
  property bool djClosePending: false
  // What the DJ looked at last (from the file `omacrate` writes while it runs
  // under the DJ), and the playlists, read while docked.
  property var djView: null
  property int djSince: 0
  property string djChanged: ""
  property var djPlaylists: []
  property bool djPlaylistsLoaded: false

  // Followed only while docked or waiting to close a late terminal, so
  // window changes cost nothing the rest of the time.
  readonly property var djWindows: root.djDocked || root.djClosePending ? root.djWindowList() : []

  function djWindowList() {
    var out = []
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var w = list[i].wayland
      if (w && w.appId === root.djAppId) out.push(list[i])
    }
    return out
  }
  readonly property var djWindow: {
    for (var i = 0; i < djWindows.length; i++) {
      if (djWindows[i].address === root.djAddress) return djWindows[i]
    }
    return null
  }
  readonly property var djWorkspace: djWindow ? djWindow.workspace : null
  readonly property var djMonitor: djWorkspace && djWorkspace.monitor
    ? djWorkspace.monitor : root.monitorNamed(root.djMonitorName)
  readonly property var djScreen: root.screenNamed(djMonitor ? djMonitor.name : root.djMonitorName)
  // Before the terminal maps, the dock is up so the terminal tiles beside it.
  // After that it follows the DJ's workspace, and stays up when Hyprland has
  // not reported where that is.
  readonly property bool djDockShown: {
    if (!djDocked || !djScreen) return false
    if (!djWindow || !djWorkspace || !djWorkspace.monitor) return true
    var active = djWorkspace.monitor.activeWorkspace
    return !active || active.id === djWorkspace.id
  }

  function screenNamed(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return null
  }

  function monitorNamed(name) {
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name === name) return monitors[i]
    }
    return null
  }

  // Hyprland wants 0x-prefixed addresses; Quickshell reports them without.
  function hyprAddress(address) {
    var a = String(address || "")
    if (a.indexOf("0x") !== 0) a = "0x" + a
    return /^0x[0-9a-f]+$/i.test(a) ? a : ""
  }

  // The DJ and its dock are one unit: it opens on the first empty workspace
  // of the focused monitor (Omarchy gives each monitor slots 1-10), and a
  // second Ask DJ goes back to the one already open. With every slot taken it
  // opens where you are.
  function startDj() {
    if (!root.options.dj || !root.options.djDock) return
    if (root.djDocked && root.djWindow) {
      var open = root.hyprAddress(root.djWindow.address)
      if (open) Hyprland.dispatch('hl.dsp.focus({window = hl.get_window("address:' + open + '")})')
      return
    }
    if (root.djDocked) return
    Hyprland.dispatch("function() local m = hl.get_active_monitor() if not m then return end "
      + "for s = 1, 10 do local ws = hl.get_workspace(o.workspaces.workspace_id(m, s)) "
      + "if not ws or (ws.windows or 0) == 0 then o.workspaces.focus(s)() return end end end")
    // A DJ terminal already open (from `omacrate dj` in a terminal, say) is
    // never taken for the new one.
    var focused = Hyprland.focusedMonitor
    var known = []
    var existing = root.djWindowList()
    for (var i = 0; i < existing.length; i++) known.push(existing[i].address)
    root.djKnownAddresses = known
    root.djAddress = ""
    root.djMonitorName = focused ? focused.name : (Quickshell.screens.length ? Quickshell.screens[0].name : "")
    // Give the dock a moment to reserve its edge before the terminal maps.
    djLaunchTimer.restart()
    djWaitTimer.restart()
    root.djClosePending = false
    root.djView = null
    root.djChanged = ""
    root.djSince = Math.floor(Date.now() / 1000) - 2
    root.djDocked = true
    root.refreshDjPlaylists()
  }

  function closeDjDock() {
    djLaunchTimer.stop()
    djWaitTimer.stop()
    root.djDocked = false
    root.djAddress = ""
    root.djView = null
    root.djChanged = ""
    root.djPlaylists = []
    root.djPlaylistsLoaded = false
    if (!root.djClosePending) root.djKnownAddresses = []
  }

  // Closing the dock closes the DJ's terminal too. If the terminal is still
  // on its way, it is closed when it appears.
  function closeDj() {
    var address = root.djWindow ? root.hyprAddress(root.djWindow.address) : ""
    if (address) {
      Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
    } else if (root.djDocked && !djLaunchTimer.running) {
      root.djClosePending = true
      djPendingTimer.restart()
    }
    root.closeDjDock()
  }

  onDjWindowsChanged: {
    if (root.djClosePending) {
      for (var j = 0; j < root.djWindows.length; j++) {
        var late = root.djWindows[j].address
        if (root.djKnownAddresses.indexOf(late) >= 0) continue
        var hex = root.hyprAddress(late)
        if (hex) Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + hex + '" })')
        root.djClosePending = false
        djPendingTimer.stop()
        root.djKnownAddresses = []
        return
      }
    }
    if (!root.djDocked || djLaunchTimer.running) return
    if (!root.djAddress) {
      for (var i = 0; i < root.djWindows.length; i++) {
        var address = root.djWindows[i].address
        if (root.djKnownAddresses.indexOf(address) < 0) {
          root.djAddress = address
          djWaitTimer.stop()
          return
        }
      }
    } else if (!root.djWindow) {
      root.closeDjDock()
    }
  }

  Timer {
    id: djLaunchTimer
    interval: 200
    onTriggered: {
      // A login shell, so the agent sees the same PATH it would from a terminal.
      djProc.command = ["bash", "-lc", 'exec "$@"', "bash", root.cli, "dj"]
      djProc.running = true
    }
  }

  // `omacrate dj` reports its own errors; either way, a dock with no terminal
  // beside it goes away.
  Timer {
    id: djWaitTimer
    interval: 20000
    onTriggered: if (!root.djAddress) root.closeDjDock()
  }

  // A terminal that never appears does not keep a close waiting forever.
  Timer {
    id: djPendingTimer
    interval: 20000
    onTriggered: {
      root.djClosePending = false
      root.djKnownAddresses = []
    }
  }

  Process {
    id: djProc
    running: false
    onExited: function(code) { if (code !== 0) root.closeDjDock() }
  }

  // The DJ view is a file `omacrate` replaces after each lookup it runs under
  // the DJ, so the dock follows the conversation without a timer. It is
  // watched only while docked. When the DJ saved or changed a playlist, the
  // playlist list is read again.
  FileView {
    id: djViewFile
    path: root.djDocked ? root.runDir + "/dj-view.json" : ""
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = Model.djView(text(), root.djSince)
      if (!next) return
      root.djView = next
      if (next.changed) {
        root.djChanged = next.changed
        root.refreshDjPlaylists()
      }
    }
    onFileChanged: reload()
  }

  function refreshDjPlaylists() {
    if (!root.djDocked || !root.linked) return
    if (djPlaylistsProc.running) {
      djPlaylistsProc.again = true
      return
    }
    djPlaylistsProc.command = [root.cli, "--json", "playlists"]
    djPlaylistsProc.running = true
  }

  Process {
    id: djPlaylistsProc
    property bool again: false
    running: false
    stdout: StdioCollector { id: djPlaylistsOut; waitForEnd: true }
    onExited: function(code) {
      if (!root.djDocked) return
      if (code === 0) root.djPlaylists = Model.items(String(djPlaylistsOut.text || ""))
      root.djPlaylistsLoaded = true
      if (djPlaylistsProc.again) {
        djPlaylistsProc.again = false
        Qt.callLater(root.refreshDjPlaylists)
      }
    }
  }

  LazyLoader {
    active: root.djDocked
    DjDock {
      service: root
    }
  }
}
