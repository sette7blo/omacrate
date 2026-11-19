// Stand-in for plex.tv, a Plex Media Server and Lidarr on one local port, for
// tests/cli.test.js. Prints its port, records every request, and serves a
// silent WAV as every track.
const http = require("node:http")

const ACCOUNT_TOKEN = "acct-token-1"
const SERVER_TOKEN = "srv-token-1"
// A second server token, for a switch to another server while a queue plays.
const OTHER_SERVER_TOKEN = "srv-token-2"
const KID_TOKEN = "kid-token-1"
const homeUsers = [
  { id: 1, uuid: "aaaaaaaaaaaaaaaa", title: "Papa", admin: true, restricted: false, protected: false },
  { id: 2, uuid: "bbbbbbbbbbbbbbbb", title: "Kid", admin: false, restricted: true, protected: false },
  { id: 3, uuid: "cccccccccccccccc", title: "Teen", admin: false, restricted: true, protected: true },
  { id: 4, uuid: "dddddddddddddddd", title: "Guest", admin: false, restricted: true, protected: false }
]
const LIDARR_KEY = "abcdef0123456789abcdef0123456789"

const artists = [
  { ratingKey: "100", type: "artist", title: "Khruangbin", childCount: 1, Genre: [{ tag: "Funk" }, { tag: "Psychedelic" }] },
  { ratingKey: "101", type: "artist", title: "Air", childCount: 1, Genre: [{ tag: "Electronic" }] }
]
const albums = [
  { ratingKey: "200", type: "album", title: "Mordechai", parentTitle: "Khruangbin", parentRatingKey: "100", year: 2020, leafCount: 3 },
  { ratingKey: "201", type: "album", title: "Moon Safari", parentTitle: "Air", parentRatingKey: "101", year: 1998, leafCount: 1 }
]
function track(id, title, album, artist, albumKey, artistKey) {
  return {
    ratingKey: String(id), type: "track", title: title, parentTitle: album, grandparentTitle: artist,
    parentRatingKey: albumKey, grandparentRatingKey: artistKey, duration: 30000,
    Media: [{ Part: [{ key: "/library/parts/" + id + "/file.wav" }] }]
  }
}
const tracks = [
  track(300, "First Class", "Mordechai", "Khruangbin", "200", "100"),
  track(301, "Time (You and I)", "Mordechai", "Khruangbin", "200", "100"),
  track(302, "<img src=x> Pelota", "Mordechai", "Khruangbin", "200", "100"),
  track(310, "La femme d'argent", "Moon Safari", "Air", "201", "101")
]
const playlists = [{ ratingKey: "900", type: "playlist", title: "Sunday", leafCount: 2, duration: 60000, items: ["300", "310"] }]
const lidarrArtists = [
  { artistName: "Altin Gun", foreignArtistId: "11111111-2222-3333-4444-555555555555", id: 0 },
  { artistName: "Air", foreignArtistId: "99999999-2222-3333-4444-555555555555", id: 7 }
]

const log = []
let identityDown = false
let identityDelay = 0
let pinPolls = 0

function wav(seconds) {
  const rate = 8000
  const data = Buffer.alloc(rate * seconds, 128)
  const head = Buffer.alloc(44)
  head.write("RIFF", 0); head.writeUInt32LE(36 + data.length, 4); head.write("WAVEfmt ", 8)
  head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22)
  head.writeUInt32LE(rate, 24); head.writeUInt32LE(rate, 28); head.writeUInt16LE(1, 32)
  head.writeUInt16LE(8, 34); head.write("data", 36); head.writeUInt32LE(data.length, 40)
  return Buffer.concat([head, data])
}
const audio = wav(30)

function container(list) { return { MediaContainer: { size: list.length, Metadata: list } } }
function byKey(list, key) { return list.filter(function(x) { return x.ratingKey === key }) }

function route(req, url, body) {
  const p = url.pathname
  const q = url.searchParams
  let m

  // Anything below /hop is sent on to another host name for the same server.
  if (p.indexOf("/hop/") === 0) return { redirect: "http://localhost:" + server.address().port + "/landed" + p.slice(4) }

  if (p === "/api/v2/pins" && req.method === "POST") return { id: 77, code: "ABCD" }
  if (p === "/api/v2/pins/77") { pinPolls += 1; return { id: 77, code: "ABCD", authToken: pinPolls > 1 ? ACCOUNT_TOKEN : null } }
  if (p === "/api/v2/home/users") {
    return req.headers["x-plex-token"] === ACCOUNT_TOKEN ? { id: 9, name: "Home", users: homeUsers } : 401
  }
  if ((m = /^\/api\/v2\/home\/users\/([0-9a-f]+)\/switch$/.exec(p)) && req.method === "POST") {
    if (req.headers["x-plex-token"] !== ACCOUNT_TOKEN) return 401
    if (m[1] === "bbbbbbbbbbbbbbbb") return { title: "Kid", authToken: KID_TOKEN }
    if (m[1] === "cccccccccccccccc") return q.get("pin") === "4321" ? { title: "Teen", authToken: KID_TOKEN } : 403
    if (m[1] === "dddddddddddddddd") return { title: "Guest", authToken: "guest-token-1" }
    return 404
  }
  if (p === "/api/v2/resources") {
    // The guest is in the home but was never shared the server.
    if (req.headers["x-plex-token"] === "guest-token-1") return []
    if (req.headers["x-plex-token"] !== ACCOUNT_TOKEN && req.headers["x-plex-token"] !== KID_TOKEN) return 401
    const self = "http://127.0.0.1:" + server.address().port
    return [
      { name: "Phone", provides: "client,player", connections: [] },
      { name: "Crate", provides: "server", owned: true, accessToken: SERVER_TOKEN, clientIdentifier: "machine-1",
        connections: [
          { uri: self, local: false, relay: true },
          { uri: "http://127.0.0.1:1", local: true, relay: false },
          // Plain http off this computer is never tried: the token would travel in clear.
          { uri: "http://192.0.2.1:1", local: true, relay: false },
          { uri: self, local: false, relay: false }
        ] }
    ]
  }

  if (p.indexOf("/api/v1/") === 0) {
    if (req.headers["x-api-key"] !== LIDARR_KEY) return 401
    if (p === "/api/v1/system/status") return { appName: "Lidarr", version: "3.1.6" }
    if (p === "/api/v1/artist/lookup") {
      const term = (q.get("term") || "").toLowerCase()
      return lidarrArtists.filter(function(a) {
        return term.indexOf("lidarr:") === 0 ? a.foreignArtistId === term.slice(7) : a.artistName.toLowerCase().indexOf(term) !== -1
      })
    }
    if (p === "/api/v1/rootfolder") return [{ path: "/data/music", defaultQualityProfileId: 2, defaultMetadataProfileId: 3 }]
    if (p === "/api/v1/qualityprofile") return [{ id: 2, name: "Lossless" }]
    if (p === "/api/v1/metadataprofile") return [{ id: 3, name: "Standard" }]
    if (p === "/api/v1/artist" && req.method === "POST") return Object.assign({}, JSON.parse(body), { id: 12, path: "/data/music/Altin Gun" })
    return 404
  }

  if (req.headers["x-plex-token"] !== SERVER_TOKEN && req.headers["x-plex-token"] !== OTHER_SERVER_TOKEN) return 401
  if (p === "/identity") return identityDown ? 500 : { MediaContainer: { machineIdentifier: "machine-1" } }
  if (p === "/library/sections") {
    return { MediaContainer: { Directory: [{ key: "1", type: "movie", title: "Films" }, { key: "3", type: "artist", title: "Music" }] } }
  }
  if (p === "/library/sections/3/refresh") return {}
  if (p === "/library/sections/3/all") return container(q.get("type") === "9" ? albums : artists)
  if (p === "/hubs/search") {
    const term = (q.get("query") || "").toLowerCase()
    const hit = function(x) { return x.title.toLowerCase().indexOf(term) !== -1 }
    return { MediaContainer: { Hub: [
      { type: "artist", Metadata: artists.filter(hit) },
      { type: "album", Metadata: albums.filter(hit) },
      { type: "track", Metadata: tracks.filter(hit) },
      { type: "movie", Metadata: [{ ratingKey: "1", type: "movie", title: "Not music" }] }
    ] } }
  }
  if ((m = /^\/library\/metadata\/(\d+)$/.exec(p))) {
    const found = byKey(artists, m[1]).concat(byKey(albums, m[1]), byKey(tracks, m[1]))
    return found.length ? container(found) : 404
  }
  if ((m = /^\/library\/metadata\/(\d+)\/children$/.exec(p))) {
    return container(albums.filter(function(a) { return a.parentRatingKey === m[1] })
      .concat(tracks.filter(function(t) { return t.parentRatingKey === m[1] })))
  }
  if ((m = /^\/library\/metadata\/(\d+)\/allLeaves$/.exec(p))) {
    return container(tracks.filter(function(t) { return t.grandparentRatingKey === m[1] }))
  }
  if (p === "/playlists" && req.method === "GET") return container(playlists)
  if (p === "/playlists" && req.method === "POST") {
    const made = { ratingKey: "901", type: "playlist", title: q.get("title"), items: [] }
    playlists.push(made)
    return container([made])
  }
  if ((m = /^\/playlists\/(\d+)$/.exec(p)) && req.method === "DELETE") {
    const i = playlists.findIndex(function(x) { return x.ratingKey === m[1] })
    if (i < 0) return 404
    playlists.splice(i, 1)
    return {}
  }
  if ((m = /^\/library\/metadata\/(\d+)\/posters$/.exec(p)) && req.method === "POST") {
    return byKey(playlists, m[1]).length ? {} : 404
  }
  if ((m = /^\/playlists\/(\d+)\/items$/.exec(p))) {
    const list = byKey(playlists, m[1])[0]
    if (!list) return 404
    if (req.method === "PUT") return container([list])
    return container(list.items.map(function(k) { return byKey(tracks, k)[0] }))
  }
  if (/^\/library\/parts\/\d+\/file\.wav$/.test(p)) return audio
  return 404
}

const server = http.createServer(function(req, res) {
  const url = new URL(req.url, "http://localhost")
  let body = ""
  req.on("data", function(chunk) { body += chunk })
  req.on("end", function() {
    if (url.pathname === "/__log") {
      res.setHeader("Content-Type", "application/json")
      return res.end(JSON.stringify(log))
    }
    // POST /__identity with "down" makes every server address fail its check.
    if (url.pathname === "/__identity") {
      identityDown = body.trim() === "down"
      return res.end("ok")
    }
    // POST /__identity-delay with milliseconds slows every address check.
    if (url.pathname === "/__identity-delay") {
      identityDelay = Number(body.trim()) || 0
      return res.end("ok")
    }
    if (url.pathname === "/identity" && identityDelay > 0 && !req.delayed) {
      req.delayed = true
      return setTimeout(function() { req.emit("end") }, identityDelay)
    }
    log.push({
      method: req.method, host: req.headers.host || "", path: url.pathname, query: url.search, body: body,
      plexToken: req.headers["x-plex-token"] || "", apiKey: req.headers["x-api-key"] || "",
      agent: req.headers["user-agent"] || "", contentType: req.headers["content-type"] || "", length: Number(req.headers["content-length"] || 0)
    })
    const out = route(req, url, body)
    if (typeof out === "number") { res.statusCode = out; return res.end() }
    if (out && out.redirect) { res.statusCode = 302; res.setHeader("Location", out.redirect); return res.end() }
    if (Buffer.isBuffer(out)) { res.setHeader("Content-Type", "audio/wav"); return res.end(out) }
    res.setHeader("Content-Type", "application/json")
    res.end(JSON.stringify(out))
  })
})

server.listen(0, "127.0.0.1", function() { console.log(server.address().port) })
