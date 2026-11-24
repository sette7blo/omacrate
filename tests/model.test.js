// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const M = require("../Model.js")

const TRACK = { key: "300", type: "track", title: "First Class", artist: "Khruangbin", album: "Mordechai", year: 2020, seconds: 207, count: null }
const ALBUM = { key: "200", type: "album", title: "Mordechai", artist: "Khruangbin", album: "", year: 2020, seconds: 0, count: 10 }
const ARTIST = { key: "100", type: "artist", title: "Khruangbin", artist: "", album: "", year: null, seconds: 0, count: 4 }
const PLAYLIST = { key: "playlist:900", type: "playlist", title: "Sunday", seconds: 60, count: 1 }

test("clock formats seconds", function() {
  assert.equal(M.clock(0), "0:00")
  assert.equal(M.clock(65), "1:05")
  assert.equal(M.clock(3725), "1:02:05")
  assert.equal(M.clock(-4), "0:00")
  assert.equal(M.clock("x"), "0:00")
})

test("the link state never carries a token", function() {
  const raw = JSON.stringify({
    clientId: "c", plex: { token: "acct-secret", serverToken: "srv-secret", serverUri: "http://10.0.0.2:32400",
      serverName: "Crate", sections: [{ id: "3", title: "Music" }] },
    lidarr: { baseUrl: "http://x", apiKey: "abcdef0123456789abcdef0123456789" }
  })
  const info = M.linkInfo(raw)
  assert.deepEqual(info, { linked: true, connection: "none/none/account", server: "Crate", user: "", home: false, libraries: ["Music"], lidarr: true })
  assert.doesNotMatch(JSON.stringify(info), /secret|abcdef|10\.0\.0\.2/)
  assert.equal(M.linkSummary(info), "Crate")
})

test("the connection names the session, server and Plex Home user, never anything else", function() {
  const raw = function(plex) { return JSON.stringify({ plex: Object.assign({ serverUri: "https://a", serverToken: "t" }, plex) }) }
  assert.equal(M.linkInfo(raw({ machineId: "machine-1" })).connection, "none/machine-1/account")
  assert.equal(M.linkInfo(raw({ machineId: "machine-1", userUuid: "bbbbbbbbbbbbbbbb" })).connection, "none/machine-1/bbbbbbbbbbbbbbbb")
  assert.equal(M.linkInfo(raw({ session: "0a1b2c3d4e5f6071", machineId: "machine-1" })).connection, "0a1b2c3d4e5f6071/machine-1/account")
  assert.equal(M.linkInfo(raw({ session: "x/y", machineId: "a/b", userUuid: "x y" })).connection, "none/none/account")
  assert.equal(M.linkInfo(raw({ session: "s1" })).connection, "s1/none/account", "never the token or the address")
})

test("a missing or broken credentials file reads as not linked", function() {
  for (const raw of ["", "{}", "not json", "[]", "null", JSON.stringify({ plex: { serverUri: "http://x" } })]) {
    assert.equal(M.linkInfo(raw).linked, false)
  }
  assert.equal(M.linkSummary(M.linkInfo("")), "Not linked")
  assert.equal(M.linkSummary({ linked: true, server: "Crate", libraries: [] }), "Crate: no music library")
})

test("items keep known types with well-formed keys and bound their text", function() {
  const list = M.items(JSON.stringify([
    TRACK, ALBUM, ARTIST, PLAYLIST,
    { key: "1", type: "movie", title: "Not music" },
    { key: "5; rm -rf /", type: "track", title: "Bad key" },
    { key: "", type: "album", title: "No key" },
    null, "text", 4,
    { key: "301", type: "track", title: "x".repeat(900), artist: "a\nb\u0000c" }
  ]))
  assert.deepEqual(list.map(function(i) { return i.key }), ["300", "200", "100", "playlist:900", "301"])
  assert.equal(list[4].title.length, M.MAX_TEXT)
  assert.equal(list[4].artist, "a b c")
  assert.deepEqual(M.items("not json"), [])
  assert.deepEqual(M.items('{"a":1}'), [])
  assert.equal(M.items(JSON.stringify(new Array(50).fill(TRACK)), 10).length, 10)
})

test("markup in a title stays text", function() {
  const list = M.items([{ key: "302", type: "track", title: "<img src=x> Pelota", artist: "<b>K</b>" }])
  const row = M.rows(list, "search")[0]
  assert.equal(row.title, "<img src=x> Pelota")
  assert.equal(M.barLabel(list[0]), "<img src=x> Pelota")
  // The panel and the bar must draw these as plain text.
  for (const file of ["Panel.qml", "RowItem.qml", "SettingsView.qml", "DjDock.qml"]) {
    assert.doesNotMatch(fs.readFileSync(path.join(__dirname, "..", file), "utf8"), /Text\.(RichText|StyledText|MarkdownText|AutoText)/)
    const qml = fs.readFileSync(path.join(__dirname, "..", file), "utf8")
    const texts = qml.split(/\n\s*Text \{/).slice(1)
    assert.ok(texts.length > 0)
    for (const block of texts) assert.match(block.split("\n").slice(0, 3).join("\n"), /textFormat: Text\.PlainText/, file)
  }
})

test("the queue keeps tracks only", function() {
  const queue = M.parseQueue(JSON.stringify([TRACK, ALBUM, TRACK]))
  assert.equal(queue.length, 2)
  assert.deepEqual(M.parseQueue(""), [])
})

test("rows leave out what their list already says", function() {
  const items = M.items([TRACK, ALBUM, Object.assign({}, ARTIST, { genres: ["Funk", "Soul", "Dub", "Rock"] }), PLAYLIST])
  const found = M.rows(items, "search")
  assert.deepEqual(found.map(function(r) { return [r.subtitle, r.right, r.label] }), [
    ["Khruangbin  \u00b7  Mordechai", "3:27", "Track"], ["Khruangbin", "2020", "Album"],
    ["Funk, Soul, Dub", "4 albums", "Artist"], ["1:00", "1 track", "Playlist"]
  ])
  assert.equal(M.rows([items[0]], "album")[0].subtitle, "Khruangbin")
  assert.equal(M.rows([items[0]], "album")[0].label, "")
  assert.equal(M.rows([items[0]], "playlist")[0].subtitle, "Khruangbin  \u00b7  Mordechai")
  assert.equal(M.rows([items[1]], "artist")[0].subtitle, "10 tracks")
  assert.equal(M.rows([items[1]], "recent")[0].subtitle, "Khruangbin")
})

test("the queue view marks the playing track", function() {
  const queue = M.parseQueue([TRACK, Object.assign({}, TRACK, { key: "301", title: "Time" })])
  const rows = M.queueRows(queue, 1)
  assert.deepEqual(rows.map(function(r) { return r.current }), [false, true])
  assert.equal(rows[0].kind, "queued")
  assert.deepEqual(M.queueRows(null, 0), [])
})

test("tabs: the queue shows its length, and tab walks round", function() {
  assert.deepEqual(M.tabs(0).map(function(t) { return t.label }), ["Queue", "Recent", "Artists", "Playlists"])
  assert.equal(M.tabs(12)[0].label, "Queue 12")
  assert.equal(M.nextTab("queue", 1), "recent")
  assert.equal(M.nextTab("playlists", 1), "queue")
  assert.equal(M.nextTab("queue", -1), "playlists")
  assert.equal(M.nextTab("nope", 1), "queue")
  assert.equal(M.tabRequest("queue"), null)
  assert.deepEqual(M.tabRequest("recent").args, ["recent", "50"])
  assert.deepEqual(M.tabRequest("artists").args, ["artists"])
  assert.equal(M.tabRequest("playlists").within, "playlists")
})

test("plex home users: only those without a PIN can be switched to from the panel", function() {
  const link = { linked: true, server: "Crate", user: "Kid", home: true, libraries: ["Music"] }
  assert.equal(M.linkSummary(link), "Crate  \u00b7  Kid")
  assert.deepEqual(M.usersRequest().args, ["user"])
  const rows = M.userRows(JSON.stringify([
    { uuid: "aaaaaaaaaaaaaaaa", title: "Papa", admin: true, protected: true, current: false },
    { uuid: "bbbbbbbbbbbbbbbb", title: "<b>Kid</b>", admin: false, protected: false, current: true },
    { uuid: "cccccccccccccccc", title: "Teen", admin: false, protected: true, current: false },
    { uuid: "dddddddddddddddd", title: "Guest", admin: false, protected: false, current: false },
    { uuid: "--json", title: "Bad" }, null
  ]))
  assert.deepEqual(rows.map(function(r) { return r.title }), ["Papa", "<b>Kid</b>", "Teen", "Guest"])
  assert.equal(rows[1].right, "In use")
  assert.equal(rows[2].subtitle, "Home user  \u00b7  has a PIN")
  assert.deepEqual(M.userArgs(rows[0]), ["user", "aaaaaaaaaaaaaaaa"])
  assert.equal(M.userArgs(rows[1]), null)
  assert.equal(M.userArgs(rows[2]), null)
  assert.deepEqual(M.userArgs(rows[3]), ["user", "dddddddddddddddd"])
  assert.equal(M.playArgs(rows[3], 0, null, false), null)
  assert.equal(M.addArgs(rows[3]), null)
  assert.equal(M.listRequest(rows[3]), null)
  assert.deepEqual(M.userRows("nope"), [])
})

test("opening a row asks for the right list", function() {
  const rows = M.rows(M.items([TRACK, ALBUM, ARTIST, PLAYLIST]), "search")
  assert.equal(M.listRequest(rows[0]), null)
  assert.deepEqual(M.listRequest(rows[1]).args, ["tracks", "200"])
  assert.deepEqual(M.listRequest(rows[2]).args, ["albums", "100"])
  assert.equal(M.listRequest(rows[2]).within, "artist")
  assert.deepEqual(M.listRequest(rows[3]).args, ["tracks", "playlist:900"])
  assert.equal(M.listRequest({ kind: "album", key: "--shuffle", title: "x" }), null)
})

test("enter on a track plays its album from there, or the track alone from a search", function() {
  const track = M.rows(M.items([TRACK]), "album")[0]
  assert.deepEqual(M.playArgs(track, 4, { within: "album", key: "200" }, false), ["play", "--at", "4", "200"])
  assert.deepEqual(M.playArgs(track, 2, { within: "playlist", key: "playlist:900" }, false), ["play", "--at", "2", "playlist:900"])
  assert.deepEqual(M.playArgs(track, 4, { within: "search", key: "" }, false), ["play", "300"])
  assert.deepEqual(M.playArgs(track, 4, null, false), ["play", "300"])
  assert.deepEqual(M.playArgs(track, 4, { within: "album", key: "200" }, true), ["play", "--shuffle", "300"])
  assert.equal(M.playArgs({ kind: "track", key: "--at" }, 0, null, false), null)
  assert.deepEqual(M.addArgs(track), ["add", "300"])
  assert.equal(M.addArgs({ kind: "queued", key: "300" }), null)
})

test("mpv lines are parsed into numbers and flags only", function() {
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":1,"name":"playlist-pos","data":3}'), { name: "position", value: 3 })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":1,"name":"playlist-pos","data":-1}'), { name: "position", value: -1 })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":1,"name":"playlist-pos"}'), { name: "position", value: -1 })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":2,"name":"pause","data":true}'), { name: "pause", value: true })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":3,"name":"duration","data":207.4}'), { name: "duration", value: 207 })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":4,"name":"idle-active","data":false}'), { name: "idle-active", value: false })
  assert.deepEqual(M.mpvEvent('{"data":12.9,"request_id":' + M.TIME_REQUEST + ',"error":"success"}'), { name: "time", value: 12 })
  assert.deepEqual(M.mpvEvent('{"event":"seek"}'), { name: "moved", value: true })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":5,"name":"volume","data":62.5}'), { name: "volume", value: 62 })
  assert.deepEqual(M.mpvEvent('{"event":"property-change","id":6,"name":"mute","data":true}'), { name: "mute", value: true })
  assert.equal(M.mpvEvent('{"event":"property-change","name":"media-title","data":"<b>x</b>"}'), null)
  assert.equal(M.mpvEvent('{"request_id":0,"error":"success"}'), null)
  assert.equal(M.mpvEvent("garbage"), null)
  assert.equal(M.mpvEvent(""), null)
})

test("mpv commands are one JSON line each", function() {
  assert.equal(M.mpvLine(["cycle", "pause"], 0), '{"command":["cycle","pause"]}\n')
  assert.equal(M.mpvLine(["get_property", "time-pos"], 100), '{"command":["get_property","time-pos"],"request_id":100}\n')
  const lines = M.mpvSubscribe().trim().split("\n")
  assert.equal(lines.length, 6)
  for (const line of lines) assert.equal(JSON.parse(line).command[0], "observe_property")
})

test("the bar label is cut to length", function() {
  assert.equal(M.barLabel(null), "")
  assert.equal(M.barLabel({ title: "Short" }), "Short")
  const long = M.barLabel({ title: "A very long track title that would push the clock around" })
  assert.equal(long.length <= 32, true)
  assert.match(long, /…$/)
  assert.equal(M.nowLine({ artist: "Air", album: "Moon Safari" }), "Air  ·  Moon Safari")
  assert.equal(M.nowLine({ artist: "", album: "Moon Safari" }), "Moon Safari")
})

test("a login code is checked before it is shown", function() {
  assert.deepEqual(M.pin('{"id":"77","code":"abcd"}'), { id: "77", code: "ABCD" })
  assert.equal(M.pin('{"id":"77","code":"<b>"}'), null)
  assert.equal(M.pin('{"id":"x","code":"ABCD"}'), null)
  assert.equal(M.pin("nope"), null)
})

test("the last line of an error is what the panel shows", function() {
  assert.equal(M.errorText("curl noise\nomacrate: the Plex server does not answer\n"), "the Plex server does not answer")
  assert.equal(M.errorText(""), "")
  assert.equal(M.errorText("x".repeat(500)).length, 160)
})

test("settings default to showing the title", function() {
  assert.deepEqual(M.settings(null), { showTitle: true, dj: false, djDock: false })
  assert.deepEqual(M.settings({ showTitle: false }), { showTitle: false, dj: false, djDock: false })
  assert.deepEqual(M.settings({ showTitle: "no" }), { showTitle: true, dj: false, djDock: false })
})

test("the DJ is off unless the bar entry turns it on", function() {
  assert.equal(M.settings({ dj: "yes" }).dj, false)
  assert.equal(M.settings({ dj: 1 }).dj, false)
  assert.equal(M.settings({ dj: true }).dj, true)
  assert.equal(M.settings({ djDock: "yes" }).djDock, false)
  assert.equal(M.settings({ djDock: true }).djDock, true)
  assert.equal(M.settingsPayload({ dj: true, djDock: true }).djDock, true)
  const config = { bar: { layout: { left: [{ id: "omarchy.menu" }], centerEnd: [{ id: M.PLUGIN_ID, dj: true, showTitle: false }] } } }
  assert.deepEqual(M.pluginSettings(config), { showTitle: false, dj: true, djDock: false })
  assert.deepEqual(M.pluginSettings({ bar: { layout: { right: [{ id: M.PLUGIN_ID }] } } }), { showTitle: true, dj: false, djDock: false })
  assert.deepEqual(M.pluginSettings(null), { showTitle: true, dj: false, djDock: false })
  assert.deepEqual(M.pluginSettings({ bar: { layout: { right: "x" } } }), { showTitle: true, dj: false, djDock: false })
  assert.deepEqual(M.settingsPayload({ dj: true }), { id: M.PLUGIN_ID, showTitle: true, dj: true, djDock: false })
  // The service must not look for an agent while the DJ is off.
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  assert.match(service, /function checkAgent\(\) \{\s+if \(!root\.options\.dj\)/)
  assert.equal(service.split('"--json", "status"').length, 2)
})

test("hints follow the selected row", function() {
  assert.match(M.hints({ kind: "track" }, false), /enter play/)
  assert.match(M.hints({ kind: "album" }, true), /enter open.*p play.*space pause/)
  assert.equal(M.hints(null, false), "tab next list   / search")
  assert.match(M.hints({ kind: "track" }, false, true), /^esc back   enter play/)
  assert.doesNotMatch(M.hints({ kind: "playlist" }, false), /artwork|delete/)
})

test("volume moves in steps of five within 0 to 100", function() {
  assert.equal(M.volumeStep(50, 5), 55)
  assert.equal(M.volumeStep(52, -5), 45)
  assert.equal(M.volumeStep(98, 5), 100)
  assert.equal(M.volumeStep(3, -5), 0)
  assert.equal(M.volumeStep("x", 5), 5)
  assert.equal(M.volumeGlyph(80, true), M.volumeGlyph(0, false))
  assert.notEqual(M.volumeGlyph(80, false), M.volumeGlyph(20, false))
})

test("plain http needs a yes only when it leaves this computer", function() {
  assert.equal(M.lidarrCleartext("http://192.168.1.10:8686"), true)
  assert.equal(M.lidarrCleartext("http://media:8686/"), true)
  assert.equal(M.lidarrCleartext("http://localhost.example:8686"), true)
  assert.equal(M.lidarrCleartext("https://lidarr.home.lan"), false)
  assert.equal(M.lidarrCleartext("http://localhost:8686"), false)
  assert.equal(M.lidarrCleartext("http://127.0.0.1:8686/lidarr"), false)
  assert.equal(M.lidarrCleartext("http://[::1]:8686"), false)
  assert.equal(M.lidarrCleartext(""), false)
})

test("the DJ dock shows the playlist changed last", function() {
  const list = M.items([
    Object.assign({}, PLAYLIST, { key: "playlist:900", updated: 100 }),
    Object.assign({}, PLAYLIST, { key: "playlist:901", title: "Late Drive", updated: 300 }),
    Object.assign({}, PLAYLIST, { key: "playlist:902", updated: 200 }),
    ALBUM
  ])
  assert.equal(M.latestPlaylist(list).key, "playlist:901")
  assert.equal(M.latestPlaylist([ALBUM]), null)
  assert.equal(M.latestPlaylist("no"), null)
  assert.equal(M.items([Object.assign({}, PLAYLIST, { updated: "soon" })])[0].updated, 0)
})
