# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- DJ dock, off by default: with **Dock the DJ panel** on, Ask DJ opens the DJ on the first
  empty workspace with a panel docked beside it showing what is playing, the queue and the
  playlist changed most recently. It follows only the DJ's own terminal and closes with it.
- `omacrate --json playlists` gives each playlist an `updated` time (its last change).

### Changed
- The DJ terminal opens with its own app-id, `org.omarchy.agent.omacrate`, instead of
  `org.omarchy.agent`.

### Removed
- The panel's playlist artwork and delete buttons, and their `i` and `x` keys. Both stay
  available to the DJ and on the command line (`omacrate playlist art`,
  `omacrate playlist delete`); in Plex's own apps you can do both too.

## [v0.2.7] - 2026-11-19

### Security
- A login saved before sessions existed is given a session, under the lock, before any
  server lookup starts, and a lookup never saves when it has no session to check against.
  A lookup that began on such a login can no longer write the old server back after a
  logout. The panel's lists keep working through this one-time change.
- An automatic retry after the saved address stops answering, and a Plex Home user switch,
  look the server up by its machine id instead of its name, and save only if the session
  and the server are both unchanged, so they never move to another server that has the
  same name.
- Playlist artwork is read by `lib/read_picture.py`. It walks the picked file's real path
  without following links, and refuses a file in a folder another account can change
  (unless the folder is sticky, like `/tmp`, and the file is yours or root's), or a file
  another account can change, since the path could name a different picture by then. The
  regular-file check and the bounded read are made on that one open file.

## [v0.2.6] - 2026-11-19

### Security
- Every login, Plex Home user switch and switch to another server starts a new session in
  the credentials file; logout removes it. A server lookup (also the automatic one when
  the saved address stops answering) saves its result only if the session is still the
  one it started in, checked under the lock, so a lookup overtaken by a logout, login or
  user switch saves nothing, and the request that started it is not retried in another
  session.
- The panel's connection id is now session, server and user, so two accounts on the same
  shared server never share it. Every list the panel reads carries it (`--connection`,
  now a global option before the command), an answer that arrives after a change is
  dropped, a delete or artwork change uses the connection of the list it was picked from,
  and any change of session, server or user clears the cached lists and pending actions.
- Playlist artwork is opened once: the regular-file check and the bounded read happen on
  that one open file, in one process with a time limit, so a file or link swapped in
  between is never read.

## [v0.2.5] - 2026-11-18

### Security
- Every Plex request reads the server address and its token in one read of the saved
  connection, so a server change made at the same moment can never pair one server's
  address with the other server's token. Choosing a server (`omacrate server`, a login, an
  automatic address lookup, switching Plex Home user) checks each candidate address with
  that server's own token and saves server, token, address and libraries in one write;
  nothing is saved if no address answers. Changes to the saved credentials are made one
  at a time.
- Lidarr requests read the address, the key and the consent to plain http together, so
  the key and the consent always belong to the address the request goes to.
- A playlist delete waiting for confirmation, or an artwork change waiting for the file
  picker, is tied to the Plex server and user it was asked for on: the panel passes them
  as `--connection`, and the CLI refuses the action if either changed. A switch also
  drops a pending delete.
- The panel takes the picked file's path whole and refuses a name that contains a
  newline. The CLI reads the picture once, at most just over 10 MB, into a private
  folder, and checks and uploads that copy, so a file replaced after the check is never
  sent.

## [v0.2.4] - 2026-11-18

### Security
- mpv no longer holds one Plex token for everything it plays. Each queued track carries
  the token of the server it was queued from, so after the saved server address or token
  changes, new tracks are sent with the new token and earlier tracks keep theirs; one
  server's token never goes to another. Switching server with `omacrate server` or
  logging in again now stops the player and empties the queue, as switching Plex Home
  user already did.

## [v0.2.3] - 2026-11-18

### Security
- Requests to plex.tv, the Plex server and Lidarr no longer read your curl configuration
  (`~/.curlrc`), so a setting there cannot make them follow a redirect with the
  `X-Plex-Token` or `X-Api-Key` header, or skip the certificate check. A redirect is now
  an error rather than an empty answer.

## [v0.2.2] - 2026-11-18

### Security
- Playback checks the Plex server's TLS certificate. mpv does not by default, so a
  machine in the middle could have read the token.
- mpv no longer follows a redirect: FFmpeg would have sent the `X-Plex-Token` header on
  to the new host. A redirected stream now fails to play instead. mpv's yt-dlp hook is
  off, so a stream address is never handed to yt-dlp.
- The Lidarr API key is sent over plain http to another computer only after an explicit
  yes: **Send the key over plain http** in the settings (asked on every save) or
  `omacrate lidarr set --allow-http`. https addresses, and http to this same computer,
  work as before. A plain http address saved by an earlier version is paused until it is
  saved again with that yes. The settings example address is now https.

## [v0.2.1] - 2026-11-18

### Fixed
- The launcher (`omacrate.desktop`) runs the plugin's own `bin/omacrate` instead of
  `~/.local/bin/omacrate`, which may belong to another program when the installer left
  it alone. Launchers written by earlier versions are rewritten on the next load. If
  the plugin folder's path holds characters a launcher cannot carry safely, no launcher
  is made.
- The DJ is given the full path of `bin/omacrate` and told to run it by that path, for
  the same reason.

### Changed
- The **Let the DJ use Lidarr** setting, the README and the privacy notes now say plainly
  that the setting is not a lock: an agent runs as you and can read the saved Plex token
  and Lidarr key whatever the setting.

## [v0.2.0] - 2026-11-18

### Changed
- The DJ cannot use Lidarr until you allow it with **Let the DJ use Lidarr** in the
  settings or `omacrate lidarr dj on`. While it is off, the DJ is not given the
  add-artist skill or told that Lidarr exists, and `omacrate lidarr` refuses it. The DJ
  can never change the Lidarr settings.

### Removed
- `omacrate lidarr queue`. It showed what is downloading, which nothing needs: Lidarr
  can tell Plex itself when albums are imported.

## [v0.1.1] - 2026-11-18

### Fixed
- The installer no longer moves an existing `~/.local/bin/omacrate` or `omacrate.desktop` aside
  to put its own link there. A path that is already taken is left as it is, and the
  plugin works without the link. The uninstaller removes only links that point into the
  plugin. Backups made by earlier versions (`*.bak.<date>`) are not touched.

## [v0.1.0] - 2026-11-17

### Added
- Plays a Plex music library through one headless `mpv`, started on the first play and
  gone when the queue ends.
- Login with a four-character code entered at plex.tv/link, from the panel or with
  `omacrate login`.
- One keyboard-first panel: a search box, one list for artists, albums, tracks, playlists
  and the queue, and a now-playing line with a seek bar.
- Plex Home: switch between the users of the home, from the panel or with
  `omacrate user`, to reach each user's own playlists.
- Bar widget with the title of the playing track, dimmed while nothing plays.
- `omacrate` command line tool for everything the panel does, plus saving playlists,
  a library scan and adding artists through Lidarr.
- Settings behind a gear in the panel: Plex account (link, switch user, log out), the
  Lidarr address and API key, the track title on the bar, and the DJ.
- Delete a playlist (with a confirmation) and set playlist artwork, from the panel (`x`,
  `i`, or the buttons on an open playlist), the command line (`omacrate playlist delete`,
  `omacrate playlist art`, JPEG, PNG or SVG) and the DJ, which can draw a cover for a
  playlist and set it.
- Volume slider and mute in the panel, `-` `+` `m` keys and `omacrate volume`. The level is
  the player's own and is kept for the next start.
- An optional AI DJ, off by default. Switched on in the settings, it adds an Ask DJ button
  that opens your default Omarchy agent working from your own library. The plugin has no
  AI and no API key of its own. Three agent skills come with it; they are linked into your
  agents' folders only when you press the button for it.

### Security
- The Plex server is reached over https only (plain http only on this computer), so the
  token never travels in clear.
- Stream paths from the server are checked before mpv opens them, and tokens are checked
  before they are written into curl's and mpv's configuration.
- The DJ opens the agent with its normal permission prompts instead of through Omarchy's
  launcher, which switches them off, and tells it that library and Lidarr text is data,
  never instructions. Supported agents: claude, codex, cursor-agent, copilot.

[Unreleased]: https://github.com/sette7blo/omacrate/compare/v0.2.7...HEAD
[v0.2.7]: https://github.com/sette7blo/omacrate/compare/v0.2.6...v0.2.7
[v0.2.6]: https://github.com/sette7blo/omacrate/compare/v0.2.5...v0.2.6
[v0.2.5]: https://github.com/sette7blo/omacrate/compare/v0.2.4...v0.2.5
[v0.2.4]: https://github.com/sette7blo/omacrate/compare/v0.2.3...v0.2.4
[v0.2.3]: https://github.com/sette7blo/omacrate/compare/v0.2.2...v0.2.3
[v0.2.2]: https://github.com/sette7blo/omacrate/compare/v0.2.1...v0.2.2
[v0.2.1]: https://github.com/sette7blo/omacrate/compare/v0.2.0...v0.2.1
[v0.2.0]: https://github.com/sette7blo/omacrate/compare/v0.1.1...v0.2.0
[v0.1.1]: https://github.com/sette7blo/omacrate/compare/v0.1.0...v0.1.1
[v0.1.0]: https://github.com/sette7blo/omacrate/releases/tag/v0.1.0
