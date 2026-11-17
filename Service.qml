import QtQuick
import Quickshell
import Quickshell.Io
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

  onOptionsChanged: root.checkAgent()

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

  function saveLidarr(address, key) {
    if (lidarrProc.running) return
    root.lidarrBusy = true
    root.lidarrMessage = ""
    root.lidarrFailed = false
    root.pendingLidarrKey = String(key || "").replace(/\s+/g, "")
    lidarrProc.mode = "set"
    lidarrProc.command = [root.cli, "lidarr", "set", String(address || "").trim()]
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
}
