# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/sette7blo/omacrate/compare/v0.1.1...HEAD
[v0.1.1]: https://github.com/sette7blo/omacrate/compare/v0.1.0...v0.1.1
[v0.1.0]: https://github.com/sette7blo/omacrate/releases/tag/v0.1.0
