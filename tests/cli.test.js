// Run with: node --test tests/
// Drives bin/omacrate against tests/fake-server.js in throwaway XDG folders.
// The player tests need mpv and socat and play to a null audio device.
const test = require("node:test")
const assert = require("node:assert/strict")
const { spawn, spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const CLI = path.join(__dirname, "..", "bin", "omacrate")
const have = function(cmd) { return spawnSync("sh", ["-c", "command -v " + cmd]).status === 0 }
const canPlay = have("mpv") && have("socat")

let server, base, tmp, env

function run(args, input) {
  const out = spawnSync(CLI, args, { env: env, input: input || "", encoding: "utf8", timeout: 60000 })
  return { code: out.status, out: out.stdout.trim(), err: out.stderr.trim() }
}
function ok(args, input) {
  const r = run(args, input)
  assert.equal(r.code, 0, args.join(" ") + ": " + r.err)
  return r.out
}
function json(args) { return JSON.parse(ok(["--json"].concat(args))) }
async function requests() { return (await fetch(base + "/__log")).json() }
const sleep = function(ms) { return new Promise(function(done) { setTimeout(done, ms) }) }

test.before(async function() {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "omacrate-test-"))
  server = spawn(process.execPath, [path.join(__dirname, "fake-server.js")], { stdio: ["ignore", "pipe", "inherit"] })
  const port = await new Promise(function(done) { server.stdout.once("data", function(d) { done(String(d).trim()) }) })
  base = "http://127.0.0.1:" + port
  env = Object.assign({}, process.env, {
    XDG_STATE_HOME: path.join(tmp, "state"), XDG_RUNTIME_DIR: path.join(tmp, "run"),
    OMACRATE_PLEX_TV: base + "/api/v2", OMACRATE_MPV_ARGS: "--ao=null"
  })
  fs.mkdirSync(env.XDG_RUNTIME_DIR, { mode: 0o700 })
})

test.after(function() {
  run(["stop"])
  server.kill()
  fs.rmSync(tmp, { recursive: true, force: true })
})

const credPath = function() { return path.join(env.XDG_STATE_HOME, "omarchy", "omacrate", "credentials.json") }

test("commands that need Plex say so before login", function() {
  const r = run(["search", "air"])
  assert.notEqual(r.code, 0)
  assert.match(r.err, /omacrate login/)
})

test("login with a code saves a private token and picks the answering address", function() {
  const pin = json(["login", "--start"])
  assert.deepEqual(pin, { id: "77", code: "ABCD" })
  assert.equal(ok(["login", "--wait", pin.id]), "linked")
  const cred = JSON.parse(fs.readFileSync(credPath(), "utf8"))
  assert.equal(cred.plex.serverName, "Crate")
  assert.equal(cred.plex.serverUri, base)
  assert.equal(cred.plex.machineId, "machine-1")
  assert.deepEqual(cred.plex.sections, [{ id: "3", title: "Music" }])
  assert.equal(fs.statSync(credPath()).mode & 0o777, 0o600)
  assert.equal(fs.statSync(path.dirname(credPath())).mode & 0o777, 0o700)
})

test("search returns artists, albums and tracks from the music library only", function() {
  const hits = json(["search", "mordechai"])
  assert.deepEqual(hits.map(function(h) { return h.type + ":" + h.key }), ["album:200"])
  assert.equal(hits[0].artist, "Khruangbin")
  assert.equal(json(["search", "a"]).some(function(h) { return h.type === "movie" }), false)
  assert.equal(hits[0].part, undefined)
})

test("browsing walks artist, album, tracks", function() {
  const artists = json(["artists"])
  assert.deepEqual(artists.map(function(a) { return a.title }), ["Khruangbin", "Air"])
  assert.deepEqual(artists[0].genres, ["Funk", "Psychedelic"])
  assert.deepEqual(json(["albums", "100"]).map(function(a) { return a.key }), ["200"])
  assert.deepEqual(json(["tracks", "200"]).map(function(t) { return t.key }), ["300", "301", "302"])
  assert.deepEqual(json(["tracks", "100", "playlist:900"]).map(function(t) { return t.key }),
    ["300", "301", "302", "300", "310"])
  assert.match(ok(["tracks", "201"]), /track\s+310\s+La femme d'argent\s+Air\s+Moon Safari/)
  assert.notEqual(run(["albums", "x; rm -rf /"]).code, 0)
})

test("a playlist is saved with the server's machine id and the track keys", async function() {
  const made = json(["playlist", "create", "Late Drive", "200", "310"])
  assert.deepEqual(made, { key: "playlist:901", title: "Late Drive", count: 4 })
  const post = (await requests()).filter(function(r) { return r.method === "POST" && r.path === "/playlists" })[0]
  const q = new URLSearchParams(post.query)
  assert.equal(q.get("title"), "Late Drive")
  assert.equal(q.get("uri"), "server://machine-1/com.plexapp.plugins.library/library/metadata/300,301,302,310")
})

test("a playlist gets artwork from a JPEG or PNG, and can be deleted", async function() {
  const png = path.join(tmp, "cover.png")
  fs.writeFileSync(png, Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"), Buffer.alloc(200)]))
  const fake = path.join(tmp, "cover.jpg")
  fs.writeFileSync(fake, "<html>not a picture</html>")
  assert.deepEqual(json(["playlist", "art", "playlist:901", png]), { key: "playlist:901", artwork: true })
  const up = (await requests()).filter(function(r) { return r.path === "/library/metadata/901/posters" })
  assert.equal(up.length, 1)
  assert.equal(up[0].method, "POST")
  assert.equal(up[0].contentType, "image/png")
  assert.equal(up[0].length, 208)
  assert.match(run(["playlist", "art", "playlist:901", fake]).err, /JPEG, PNG or SVG/)
  if (have("rsvg-convert")) {
    // A picture next to the SVG must not end up inside the upload.
    const svg = path.join(tmp, "cover.svg")
    fs.writeFileSync(svg, '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10"><rect width="10" height="10" fill="#c33"/><image href="cover.png" width="10" height="10"/></svg>')
    assert.deepEqual(json(["playlist", "art", "playlist:901", svg]), { key: "playlist:901", artwork: true })
    const last = (await requests()).filter(function(r) { return r.path === "/library/metadata/901/posters" }).pop()
    assert.equal(last.contentType, "image/png")
    assert.ok(last.length > 1000)
    assert.equal(fs.readdirSync(os.tmpdir()).filter(function(n) { return /^tmp\./.test(n) && fs.existsSync(path.join(os.tmpdir(), n, "cover.svg")) }).length, 0)
  }
  assert.notEqual(run(["playlist", "art", "playlist:901", path.join(tmp, "missing.png")]).code, 0)
  assert.notEqual(run(["playlist", "art", "901", png]).code, 0)

  assert.notEqual(run(["playlist", "delete", "901"]).code, 0)
  assert.deepEqual(json(["playlist", "delete", "playlist:901"]), { key: "playlist:901", deleted: true })
  assert.equal(json(["playlists"]).some(function(p) { return p.key === "playlist:901" }), false)
  assert.notEqual(run(["playlist", "delete", "playlist:901"]).code, 0)
})

test("tokens travel in headers, never in an address", async function() {
  const log = await requests()
  assert.ok(log.length > 5)
  for (const r of log) {
    assert.doesNotMatch(r.query, /token/i)
    assert.doesNotMatch(r.query, /srv-token-1|acct-token-1|kid-token-1/)
  }
})

test("plex home: list the users, switch to one, and back", async function() {
  const cred = function() { return JSON.parse(fs.readFileSync(credPath(), "utf8")).plex }
  assert.equal(cred().home, true)
  assert.equal(cred().user, "Papa")
  const users = json(["user"])
  assert.deepEqual(users.map(function(u) { return u.title + (u.current ? "*" : "") }), ["Papa*", "Kid", "Teen", "Guest"])
  assert.match(ok(["user", "kid"]), /Now using Kid/)
  assert.equal(cred().userToken, "kid-token-1")
  assert.equal(cred().token, "acct-token-1")
  assert.equal(cred().user, "Kid")
  assert.deepEqual(json(["user"]).filter(function(u) { return u.current }).map(function(u) { return u.title }), ["Kid"])
  assert.match(ok(["status"]), /Crate, Music \(as Kid\)/)
  assert.equal(json(["artists"]).length, 2)

  // A PIN is asked for, and a wrong one changes nothing.
  assert.notEqual(run(["user", "teen"], "\n").code, 0)
  assert.notEqual(run(["user", "teen"], "1111\n").code, 0)
  assert.equal(cred().user, "Kid")
  assert.match(ok(["user", "cccccccccccccccc"], "4321\n"), /Now using Teen/)
  const sw = (await requests()).filter(function(r) { return /cccccccccccccccc\/switch$/.test(r.path) })
  assert.equal(sw[sw.length - 1].query, "?pin=4321")
  const ps = spawnSync("ps", ["-eo", "args"], { encoding: "utf8" }).stdout
  assert.doesNotMatch(ps, /pin=4321/)

  // A user who was never shared the server leaves things as they were.
  const guest = run(["user", "guest"])
  assert.notEqual(guest.code, 0)
  assert.match(guest.err, /no access/)
  assert.equal(cred().user, "Teen")
  assert.equal(cred().serverUri, base)

  assert.notEqual(run(["user", "nobody"]).code, 0)
  assert.match(ok(["user", "Papa"]), /Now using Papa/)
  assert.equal(cred().userToken, undefined)
  assert.equal(cred().userUuid, undefined)
  assert.match(ok(["user", "Papa"]), /Already using Papa/)
})

test("lidarr: the key comes from stdin, lookup and add go through", async function() {
  assert.notEqual(run(["lidarr", "lookup", "air"]).code, 0)
  assert.notEqual(run(["lidarr", "set", base], "short\n").code, 0)
  assert.deepEqual(json(["lidarr", "address"]), { address: "", dj: false, allowHttp: false })
  assert.match(ok(["lidarr", "set", base + "/"], "abcdef0123456789abcdef0123456789\n"), /Connected to Lidarr 3\.1\.6/)
  assert.deepEqual(json(["lidarr", "address"]), { address: base, dj: false, allowHttp: false })
  assert.doesNotMatch(ok(["--json", "lidarr", "address"]), /abcdef/)
  assert.match(ok(["lidarr", "lookup", "altin"]), /11111111-2222-3333-4444-555555555555\s+Altin Gun\s+not added/)
  assert.match(ok(["lidarr", "add", "11111111-2222-3333-4444-555555555555"]), /Added Altin Gun to Lidarr/)
  const post = (await requests()).filter(function(r) { return r.method === "POST" && r.path === "/api/v1/artist" })[0]
  const body = JSON.parse(post.body)
  assert.equal(body.rootFolderPath, "/data/music")
  assert.equal(body.qualityProfileId, 2)
  assert.equal(body.metadataProfileId, 3)
  assert.deepEqual(body.addOptions, { monitor: "all", searchForMissingAlbums: true })
  const again = run(["lidarr", "add", "99999999-2222-3333-4444-555555555555"])
  assert.notEqual(again.code, 0)
  assert.match(again.err, /already in Lidarr/)
  assert.notEqual(run(["lidarr", "queue"]).code, 0)
})

test("the Lidarr key goes over plain http to another computer only with an explicit yes", function() {
  const saved = fs.readFileSync(credPath(), "utf8")
  const key = "abcdef0123456789abcdef0123456789\n"
  // 192.0.2.0/24 is reserved for documentation: nothing answers there.
  const refused = run(["lidarr", "set", "http://192.0.2.1:8686"], key)
  assert.notEqual(refused.code, 0)
  assert.match(refused.err, /plain http.*--allow-http/)
  assert.equal(fs.readFileSync(credPath(), "utf8"), saved)
  // An address saved before the switch existed is paused, not used.
  const cred = JSON.parse(saved)
  cred.lidarr.baseUrl = "http://192.0.2.1:8686"
  fs.writeFileSync(credPath(), JSON.stringify(cred), { mode: 0o600 })
  const paused = run(["lidarr", "status"])
  assert.notEqual(paused.code, 0)
  assert.match(paused.err, /plain http/)
  fs.writeFileSync(credPath(), saved, { mode: 0o600 })
  assert.match(ok(["lidarr", "status"]), /ok/)
})

test("a curl config cannot send the token or key on through a redirect", async function() {
  const home = path.join(tmp, "curl-home")
  fs.mkdirSync(home, { recursive: true })
  fs.writeFileSync(path.join(home, ".curlrc"), "location\n")
  const saved = fs.readFileSync(credPath(), "utf8")
  const cred = JSON.parse(saved)
  cred.plex.serverUri = base + "/hop"
  cred.lidarr.baseUrl = base + "/hop"
  fs.writeFileSync(credPath(), JSON.stringify(cred), { mode: 0o600 })
  const plain = env
  env = Object.assign({}, env, { CURL_HOME: home })
  try {
    assert.notEqual(run(["artists"]).code, 0)
    assert.notEqual(run(["lidarr", "status"]).code, 0)
  } finally {
    env = plain
    fs.writeFileSync(credPath(), saved, { mode: 0o600 })
  }
  const hops = (await requests()).filter(function(r) { return r.path.indexOf("/hop/") === 0 })
  assert.ok(hops.length >= 2)
  assert.deepEqual((await requests()).filter(function(r) { return r.path.indexOf("/landed/") === 0 }), [])
})

test("the DJ reaches Lidarr only after the user allows it, and never changes its settings", function() {
  const asDj = function(args, input) {
    const out = spawnSync(CLI, args, { env: Object.assign({}, env, { OMACRATE_DJ: "1" }), input: input || "", encoding: "utf8" })
    return { code: out.status, out: out.stdout.trim(), err: out.stderr.trim() }
  }
  assert.equal(ok(["lidarr", "dj"]), "off")
  for (const args of [["lidarr", "lookup", "altin"], ["lidarr", "status"], ["lidarr", "profiles"], ["lidarr", "address"]]) {
    const r = asDj(args)
    assert.notEqual(r.code, 0, args.join(" "))
    assert.match(r.err, /not available to the DJ/)
    assert.doesNotMatch(r.out, /127\.0\.0\.1|http/)
  }
  assert.doesNotMatch(asDj(["status"]).out, /Lidarr/)
  assert.match(ok(["status"]), /Lidarr:/)

  assert.match(asDj(["lidarr", "dj", "on"]).err, /cannot change the Lidarr settings/)
  assert.equal(ok(["lidarr", "dj"]), "off")
  ok(["lidarr", "dj", "on"])
  assert.deepEqual(json(["lidarr", "address"]), { address: base, dj: true, allowHttp: false })
  assert.match(asDj(["lidarr", "lookup", "altin"]).out, /Altin Gun/)
  assert.match(asDj(["lidarr", "set", base], "abcdef0123456789abcdef0123456789\n").err, /cannot change/)
  assert.match(asDj(["lidarr", "unset"]).err, /cannot change/)
  assert.match(asDj(["lidarr", "dj", "off"]).err, /cannot change/)
  ok(["lidarr", "dj", "off"])
  assert.equal(ok(["lidarr", "dj"]), "off")
})

test("play, queue, skip and stop through mpv", { skip: !canPlay && "mpv or socat missing" }, async function() {
  assert.deepEqual(json(["now"]), { playing: false })
  ok(["play", "--at", "1", "200"])
  await sleep(700)
  let now = json(["now"])
  assert.equal(now.playing, true)
  assert.equal(now.title, "Time (You and I)")
  assert.equal(now.position, 1)
  assert.equal(now.queued, 3)
  assert.equal(now.length, 30)

  ok(["next"])
  await sleep(500)
  assert.equal(json(["now"]).key, "302")

  ok(["add", "310"])
  assert.equal(json(["queue"]).length, 4)

  // Replacing the queue while a track plays must not leave the old one in it.
  ok(["play", "201"])
  await sleep(700)
  now = json(["now"])
  assert.equal(now.key, "310")
  assert.equal(now.position, 0)
  assert.equal(now.queued, 1)

  ok(["pause"])
  assert.equal(json(["now"]).paused, true)
  assert.equal(ok(["volume", "60"]), "60")
  assert.equal(ok(["volume", "-15"]), "45")
  assert.equal(ok(["volume", "+200"]), "100")
  ok(["volume", "45"])
  assert.deepEqual(json(["volume"]), { volume: 45 })
  assert.notEqual(run(["volume", "loud"]).code, 0)
  ok(["seek", "20"])
  await sleep(300)
  assert.ok(json(["now"]).time >= 19)

  const parts = (await requests()).filter(function(r) { return r.path.indexOf("/library/parts/") === 0 })
  assert.ok(parts.length > 0)
  for (const r of parts) assert.equal(r.plexToken, "srv-token-1")
  const ps = spawnSync("ps", ["-eo", "args"], { encoding: "utf8" }).stdout
  assert.doesNotMatch(ps, /srv-token-1/)
  // The token stays on the linked server: checked certificates, no redirects, no yt-dlp.
  const conf = fs.readFileSync(path.join(path.dirname(credPath()), "mpv.conf"), "utf8")
  assert.doesNotMatch(conf, /srv-token|X-Plex-Token/)
  assert.match(conf, /^tls-verify=yes$/m)
  assert.match(conf, /^stream-lavf-o=max_redirects=0$/m)
  assert.match(conf, /^ytdl=no$/m)

  ok(["stop"])
  await sleep(400)
  assert.deepEqual(json(["now"]), { playing: false })
  // The level outlives the player and is handed to the next one.
  assert.deepEqual(json(["volume"]), { volume: 45 })
  assert.notEqual(run(["next"]).code, 0)
})

test("each queued track sends only the token of the server it was queued from", { skip: !canPlay && "mpv or socat missing" }, async function() {
  const saved = fs.readFileSync(credPath(), "utf8")
  const port = new URL(base).port
  const partsFrom = async function(host) {
    return (await requests()).filter(function(r) { return r.path.indexOf("/library/parts/") === 0 && r.host === host })
  }
  try {
    ok(["play", "201"])
    await sleep(700)
    // Another address and another token are saved while the queue plays,
    // as an address lookup or a switch made elsewhere would leave them.
    const cred = JSON.parse(saved)
    cred.plex.serverUri = "http://localhost:" + port
    cred.plex.serverToken = "srv-token-2"
    fs.writeFileSync(credPath(), JSON.stringify(cred), { mode: 0o600 })
    ok(["add", "300"])
    ok(["next"])
    await sleep(700)
    assert.equal(json(["now"]).key, "300")
    const added = await partsFrom("localhost:" + port)
    assert.ok(added.length > 0)
    for (const r of added) assert.equal(r.plexToken, "srv-token-2")
    // Back to the track queued before the change: it keeps its own server and token.
    ok(["prev"])
    await sleep(700)
    assert.equal(json(["now"]).key, "310")
    const first = await partsFrom("127.0.0.1:" + port)
    assert.ok(first.length > 0)
    for (const r of first) assert.equal(r.plexToken, "srv-token-1")
  } finally {
    fs.writeFileSync(credPath(), saved, { mode: 0o600 })
  }
  // Switching the server stops the player and empties the queue.
  const cred = JSON.parse(saved)
  cred.plex.serverToken = "srv-token-2"
  fs.writeFileSync(credPath(), JSON.stringify(cred), { mode: 0o600 })
  ok(["server", "Crate"])
  assert.deepEqual(json(["now"]), { playing: false })
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(path.dirname(credPath()), "queue.json"), "utf8")), [])
  assert.equal(JSON.parse(fs.readFileSync(credPath(), "utf8")).plex.serverToken, "srv-token-1")
})

test("the player quits by itself when the queue ends", { skip: !canPlay && "mpv or socat missing" }, async function() {
  ok(["play", "310"])
  await sleep(500)
  ok(["seek", "29"])
  let playing = true
  for (let i = 0; i < 40 && playing; i++) {
    await sleep(250)
    playing = json(["now"]).playing
  }
  assert.equal(playing, false)
})

test("logout forgets Plex and keeps Lidarr", function() {
  ok(["logout"])
  const cred = JSON.parse(fs.readFileSync(credPath(), "utf8"))
  assert.equal(cred.plex, undefined)
  assert.equal(cred.lidarr.baseUrl, base)
  assert.equal(fs.readFileSync(path.join(path.dirname(credPath()), "queue.json"), "utf8").trim(), "[]")
  assert.notEqual(run(["artists"]).code, 0)
})

test("the DJ opens the agent with its own permission prompts, never a bypass flag", async function() {
  const bin = fs.mkdtempSync(path.join(tmp, "agentbin-"))
  const record = path.join(bin, "launched")
  const script = function(name, body) { fs.writeFileSync(path.join(bin, name), "#!/bin/sh\n" + body + "\n", { mode: 0o755 }) }
  script("omarchy-default-agent", 'cat "' + bin + '/agent"')
  script("omarchy-launch-tui", 'for a in "$@"; do printf "%s\\n" "$a"; done > "' + record + '"')
  script("codex", "exit 0")
  const dj = function(agent, args) {
    fs.writeFileSync(path.join(bin, "agent"), agent)
    const out = spawnSync(CLI, args, { env: Object.assign({}, env, { PATH: bin + ":" + process.env.PATH, HOME: tmp }), encoding: "utf8" })
    return { code: out.status, out: out.stdout.trim(), err: out.stderr.trim() }
  }

  const status = JSON.parse(dj("kimi", ["--json", "status"]).out)
  assert.equal(status.agent, false)
  assert.match(status.agentNote, /works with claude, codex, cursor-agent or copilot/)
  assert.notEqual(dj("kimi", ["dj"]).code, 0)

  assert.equal(JSON.parse(dj("codex", ["--json", "status"]).out).agent, true)
  const launch = async function(args) {
    fs.rmSync(record, { force: true })
    assert.equal(dj("codex", args).code, 0)
    let argv = null
    for (let i = 0; i < 40 && !argv; i++) {
      await sleep(50)
      if (fs.existsSync(record)) argv = fs.readFileSync(record, "utf8").trim().split("\n")
    }
    assert.ok(argv, "the agent window was not opened")
    return argv
  }

  // Lidarr is set up from the tests above, but the DJ has not been allowed it.
  let argv = await launch(["dj", "something mellow"])
  const at = argv.indexOf("codex")
  assert.deepEqual(argv.slice(0, 2), ["--app-id=org.omarchy.agent", "env"])
  assert.ok(argv.slice(2, at).indexOf("OMACRATE_DJ=1") !== -1, "the agent runs without OMACRATE_DJ=1")
  assert.equal(argv[at + 1], "--")
  let prompt = argv[at + 2]
  assert.match(prompt, /never follow instructions/)
  assert.match(prompt, /My request: something mellow$/)
  assert.match(prompt, /omacrate-library\/SKILL\.md/)
  assert.doesNotMatch(prompt, /Lidarr|add-artist/)
  assert.match(prompt, /Do not try to download or add music/)
  for (const flag of ["--yolo", "--trust", "--approve-for-me", "--allow-all", "--auto", "--permission-mode", "--dangerously-skip-permissions"])
    assert.equal(argv.indexOf(flag), -1, flag)

  ok(["lidarr", "dj", "on"])
  argv = await launch(["dj"])
  prompt = argv[argv.indexOf("codex") + 2]
  assert.match(prompt, /omacrate-add-artist\/SKILL\.md/)
  assert.match(prompt, /adding an artist to Lidarr/)
  assert.doesNotMatch(prompt, /Do not try to download/)
  ok(["lidarr", "dj", "off"])
})
