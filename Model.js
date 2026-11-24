// Pure-JS helpers shared by Service.qml, BarWidget.qml and Panel.qml: the
// link state, what the omacrate command prints, what mpv says on its socket,
// and the rows the panel draws. No QML types in here, so the whole file runs
// under Node for tests.

var PLUGIN_ID = "io.github.sette7blo.omacrate"

// Bounds. Anything past these is dropped before it reaches the UI.
var MAX_TEXT = 200
var MAX_ROWS = 5000
var MAX_QUEUE = 2000
var MAX_LABEL = 32

var TYPES = ["artist", "album", "track", "playlist"]

function text(value, max) {
  if (value === null || value === undefined) return ""
  var s = String(value).replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/^\s+|\s+$/g, "")
  var limit = max || MAX_TEXT
  return s.length > limit ? s.slice(0, limit) : s
}

function count(value) {
  var n = Number(value)
  return isFinite(n) && n > 0 ? Math.floor(n) : 0
}

function parseJson(raw) {
  try {
    return JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
}

function clock(seconds) {
  var s = count(seconds)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var tail = (r < 10 ? "0" : "") + r
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + tail
  return m + ":" + tail
}

// ----- Settings (bar layout entry) -----

function settings(raw) {
  var data = raw && typeof raw === "object" ? raw : {}
  // The DJ is the one feature that involves an AI agent. It is off until the
  // user turns it on.
  return { showTitle: data.showTitle !== false, dj: data.dj === true }
}

// The widget's own entry in shell.json holds its settings.
function pluginSettings(config) {
  if (!config || typeof config !== "object") return settings(null)
  var layout = config.bar && config.bar.layout ? config.bar.layout : {}
  var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
  for (var s = 0; s < sections.length; s++) {
    var entries = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && typeof entries[i] === "object" && String(entries[i].id || "") === PLUGIN_ID) return settings(entries[i])
    }
  }
  return settings(null)
}

function settingsPayload(raw) {
  var data = settings(raw)
  return { id: PLUGIN_ID, showTitle: data.showTitle, dj: data.dj }
}

// The panel's volume slider works in steps of five, from 0 to 100.
function volumeStep(volume, delta) {
  var v = Math.round((count(volume) + Number(delta || 0)) / 5) * 5
  return Math.max(0, Math.min(100, v))
}

function volumeGlyph(volume, muted) {
  if (muted || volume <= 0) return "\u{f075f}"
  if (volume < 34) return "\u{f057f}"
  if (volume < 67) return "\u{f0580}"
  return "\u{f057e}"
}

// ----- Link state -----

// Only what the UI needs leaves this function; the tokens in the file are
// read past and dropped.
function linkInfo(raw) {
  var data = parseJson(raw)
  var plex = data && data.plex && typeof data.plex === "object" ? data.plex : {}
  var lidarr = data && data.lidarr && typeof data.lidarr === "object" ? data.lidarr : {}
  var libraries = []
  var sections = Array.isArray(plex.sections) ? plex.sections : []
  for (var i = 0; i < sections.length && i < 20; i++) {
    var title = text(sections[i] && sections[i].title, 60)
    if (title) libraries.push(title)
  }
  // The session, server and Plex Home user, as the CLI names them for
  // --connection. The session changes with every login, user switch and
  // switch to another server, so it tells two accounts apart.
  var id = /^[A-Za-z0-9._-]{1,80}$/
  var session = typeof plex.session === "string" && id.test(plex.session) ? plex.session : "none"
  var machine = typeof plex.machineId === "string" && id.test(plex.machineId) ? plex.machineId : "none"
  var who = typeof plex.userUuid === "string" && id.test(plex.userUuid) ? plex.userUuid : "account"
  return {
    linked: !!plex.serverUri && !!plex.serverToken,
    connection: session + "/" + machine + "/" + who,
    server: text(plex.serverName, 60),
    user: text(plex.user, 60),
    home: plex.home === true,
    libraries: libraries,
    lidarr: !!lidarr.baseUrl && !!lidarr.apiKey
  }
}

function sameLink(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

function linkSummary(info) {
  if (!info || !info.linked) return "Not linked"
  if (!info.libraries.length) return info.server + ": no music library"
  return info.home && info.user ? join([info.server, info.user]) : info.server
}

// ----- Items from the omacrate command -----

function isKey(value) {
  return /^(playlist:)?[0-9]{1,12}$/.test(String(value || ""))
}

// Plain http to another computer sends the Lidarr key unencrypted; the same
// rule as lidarr_cleartext in bin/omacrate.
function lidarrCleartext(address) {
  var s = String(address || "").trim()
  if (!/^http:\/\//.test(s)) return false
  return !/^http:\/\/(localhost|127\.[0-9]+\.[0-9]+\.[0-9]+|\[::1\])(:[0-9]+)?(\/.*)?$/.test(s)
}

function item(raw) {
  if (!raw || typeof raw !== "object") return null
  var type = String(raw.type || "")
  if (TYPES.indexOf(type) === -1) return null
  var key = String(raw.key || "")
  if (!isKey(key)) return null
  var year = count(raw.year)
  return {
    key: key,
    type: type,
    title: text(raw.title) || "Untitled",
    artist: text(raw.artist),
    album: text(raw.album),
    year: year >= 1000 && year <= 9999 ? year : 0,
    seconds: count(raw.seconds),
    count: count(raw.count),
    genres: genres(raw.genres)
  }
}

function genres(raw) {
  var out = []
  if (!Array.isArray(raw)) return out
  for (var i = 0; i < raw.length && out.length < 3; i++) {
    var one = text(raw[i], 30)
    if (one) out.push(one)
  }
  return out
}

function items(raw, max) {
  var data = typeof raw === "string" ? parseJson(raw) : raw
  var list = []
  if (!Array.isArray(data)) return list
  var limit = max || MAX_ROWS
  for (var i = 0; i < data.length && list.length < limit; i++) {
    var one = item(data[i])
    if (one) list.push(one)
  }
  return list
}

function parseQueue(raw) {
  var list = items(raw, MAX_QUEUE)
  var tracks = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].type === "track") tracks.push(list[i])
  }
  return tracks
}

function join(parts) {
  var kept = []
  for (var i = 0; i < parts.length; i++) {
    if (parts[i]) kept.push(parts[i])
  }
  return kept.join("  ·  ")
}

function plural(n, one, many) {
  return n === 1 ? "1 " + one : (n > 1 ? n + " " + many : "")
}

var TYPE_LABELS = { artist: "Artist", album: "Album", track: "Track", playlist: "Playlist" }

// A row is a title with a note on its right, and a dim second line with a
// small label on its right. `within` says which list the row is in: "search",
// "artist", "album", "playlist", "artists", "playlists", "recent" or "queue".
// What the list already says is left out of its rows: an album's tracks do
// not repeat the album, an artist's albums do not repeat the artist.
function row(it, within) {
  var subtitle = ""
  var right = ""
  if (it.type === "track") {
    subtitle = within === "album" ? it.artist : join([it.artist, it.album])
    right = it.seconds > 0 ? clock(it.seconds) : ""
  } else if (it.type === "album") {
    subtitle = within === "artist" ? plural(it.count, "track", "tracks") : it.artist
    right = it.year ? String(it.year) : ""
  } else if (it.type === "artist") {
    subtitle = it.genres.join(", ")
    right = plural(it.count, "album", "albums")
  } else {
    subtitle = it.seconds > 0 ? clock(it.seconds) : ""
    right = plural(it.count, "track", "tracks")
  }
  return {
    kind: it.type, key: it.key, title: it.title, subtitle: subtitle, right: right,
    label: within === "search" ? TYPE_LABELS[it.type] : "", current: false, locked: false
  }
}

function rows(list, within) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push(row(list[i], within))
  return out
}

function queueRows(queue, position) {
  var out = []
  var list = Array.isArray(queue) ? queue : []
  for (var i = 0; i < list.length; i++) {
    var one = row(list[i], "queue")
    one.kind = "queued"
    one.current = i === position
    out.push(one)
  }
  return out
}

// The users of a Plex Home, from `omacrate --json user`.
function userRows(raw) {
  var data = typeof raw === "string" ? parseJson(raw) : raw
  var out = []
  if (!Array.isArray(data)) return out
  for (var i = 0; i < data.length && out.length < 50; i++) {
    var one = data[i]
    if (!one || typeof one !== "object" || !/^[0-9a-f]{8,40}$/.test(String(one.uuid || ""))) continue
    out.push({
      kind: "user", key: String(one.uuid), title: text(one.title, 60) || "Unnamed",
      subtitle: join([one.admin === true ? "Account owner" : "Home user", one.protected === true ? "has a PIN" : ""]),
      right: one.current === true ? "In use" : "", label: "",
      current: one.current === true, locked: one.protected === true && one.admin !== true
    })
  }
  return out
}

// ----- Tabs -----

var TABS = ["queue", "recent", "artists", "playlists"]

function tabs(queued) {
  return [
    { value: "queue", label: queued > 0 ? "Queue " + queued : "Queue" },
    { value: "recent", label: "Recent" },
    { value: "artists", label: "Artists" },
    { value: "playlists", label: "Playlists" }
  ]
}

function nextTab(tab, direction) {
  var i = TABS.indexOf(tab)
  if (i === -1) return TABS[0]
  return TABS[(i + (direction < 0 ? TABS.length - 1 : 1)) % TABS.length]
}

// The command behind a tab. The queue has none: it is read from the player.
function tabRequest(tab) {
  if (tab === "recent") return { args: ["recent", "50"], within: "recent", title: "Recently added", key: "" }
  if (tab === "artists") return { args: ["artists"], within: "artists", title: "Artists", key: "" }
  if (tab === "playlists") return { args: ["playlists"], within: "playlists", title: "Playlists", key: "" }
  return null
}

function usersRequest() {
  return { args: ["user"], within: "users", title: "Switch user", key: "" }
}

// The command behind a row that opens a list, and what that list is.
function listRequest(row) {
  if (!row || row.kind === "user" || !isKey(row.key)) return null
  if (row.kind === "artist") return { args: ["albums", row.key], within: "artist", title: row.title, key: row.key }
  if (row.kind === "album") return { args: ["tracks", row.key], within: "album", title: row.title, key: row.key }
  if (row.kind === "playlist") return { args: ["tracks", row.key], within: "playlist", title: row.title, key: row.key }
  return null
}

// What Enter plays on a track row: the whole album or playlist from that
// track on, or the one track when it came out of a search.
function playArgs(row, index, view, shuffle) {
  if (!row || !isKey(row.key) || row.kind === "queued" || row.kind === "user") return null
  var args = ["play"]
  if (shuffle) args.push("--shuffle")
  var inList = view && (view.within === "album" || view.within === "playlist") && isKey(view.key)
  if (row.kind === "track" && inList && !shuffle) return args.concat(["--at", String(count(index)), view.key])
  return args.concat([row.key])
}

function addArgs(row) {
  if (!row || !isKey(row.key) || row.kind === "queued" || row.kind === "user") return null
  return ["add", row.key]
}

// Switching to a user with a PIN needs a terminal, so the panel only offers
// the others.
function userArgs(row) {
  if (!row || row.kind !== "user" || row.current || row.locked) return null
  if (!/^[0-9a-f]{8,40}$/.test(String(row.key || ""))) return null
  return ["user", row.key]
}

function hints(row, playing, inList) {
  var parts = []
  if (inList) parts.push("esc back")
  if (row) {
    if (row.kind === "track") parts.push("enter play", "a queue")
    else if (row.kind === "queued") parts.push("enter jump")
    else if (row.kind === "user") parts.push("enter switch")
    else parts.push("enter open", "p play", "s shuffle", "a queue")
  }
  if (playing) parts.push("space pause", "n b skip", "- + volume")
  parts.push("tab next list", "/ search")
  return parts.join("   ")
}

// ----- mpv -----

function mpvLine(argv, requestId) {
  var message = { command: argv }
  if (requestId) message.request_id = requestId
  return JSON.stringify(message) + "\n"
}

var OBSERVED = ["playlist-pos", "pause", "duration", "idle-active", "volume", "mute"]

function mpvSubscribe() {
  var out = ""
  for (var i = 0; i < OBSERVED.length; i++) out += mpvLine(["observe_property", i + 1, OBSERVED[i]])
  return out
}

var TIME_REQUEST = 100

// One line from the socket becomes {name, value} or null. Numbers are the
// only values taken from mpv; titles come from the saved queue.
function mpvEvent(line) {
  var data = parseJson(line)
  if (!data || typeof data !== "object") return null
  if (data.event === "property-change" && OBSERVED.indexOf(data.name) !== -1) {
    if (data.name === "pause" || data.name === "idle-active" || data.name === "mute") return { name: data.name, value: data.data === true }
    if (data.name === "playlist-pos") {
      var pos = Number(data.data)
      return { name: "position", value: isFinite(pos) && pos >= 0 ? Math.floor(pos) : -1 }
    }
    return { name: data.name, value: count(data.data) }
  }
  if (data.request_id === TIME_REQUEST && data.error === "success") return { name: "time", value: count(data.data) }
  if (data.event === "seek" || data.event === "playback-restart") return { name: "moved", value: true }
  return null
}

// ----- Bar -----

function barLabel(track, max) {
  if (!track) return ""
  var limit = max || MAX_LABEL
  var title = text(track.title)
  return title.length > limit ? title.slice(0, limit - 1).replace(/\s+$/, "") + "…" : title
}

function nowLine(track) {
  if (!track) return ""
  return join([track.artist, track.album])
}

// ----- Login -----

function pin(raw) {
  var data = parseJson(raw)
  if (!data || typeof data !== "object") return null
  var id = String(data.id || "")
  var code = String(data.code || "")
  if (!/^[0-9]{1,20}$/.test(id) || !/^[A-Za-z0-9]{4,8}$/.test(code)) return null
  return { id: id, code: code.toUpperCase() }
}

function errorText(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = text(lines[i].replace(/^omacrate:\s*/, ""), 160)
    if (line) return line
  }
  return ""
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID, MAX_TEXT: MAX_TEXT, MAX_ROWS: MAX_ROWS, MAX_QUEUE: MAX_QUEUE,
    TIME_REQUEST: TIME_REQUEST,
    text: text, clock: clock, settings: settings, pluginSettings: pluginSettings,
    settingsPayload: settingsPayload, linkInfo: linkInfo, sameLink: sameLink,
    linkSummary: linkSummary, isKey: isKey, lidarrCleartext: lidarrCleartext, item: item, items: items, parseQueue: parseQueue,
    rows: rows, queueRows: queueRows, tabs: tabs, nextTab: nextTab, tabRequest: tabRequest,
    usersRequest: usersRequest, listRequest: listRequest,
    playArgs: playArgs, addArgs: addArgs, userRows: userRows, userArgs: userArgs, hints: hints, mpvLine: mpvLine,
    mpvSubscribe: mpvSubscribe, mpvEvent: mpvEvent, volumeStep: volumeStep, volumeGlyph: volumeGlyph, barLabel: barLabel, nowLine: nowLine,
    pin: pin, errorText: errorText
  }
}
