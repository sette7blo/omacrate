# Roadmap

## Where we are

First working version, built 2026-11-17, not yet on GitHub and not released. The CLI
(login by code, search, browse, play through a headless mpv, playlists, Lidarr, DJ) is
covered by tests against a stand-in server. Linked to a real server since 2026-11-17;
the panel (tabs, settings, Plex Home user switch) has had only a first look.

## Next, in order

1. Use it against the real server and fix what the stand-in got wrong (search hubs, large
   artist lists, relay addresses, tracks without a direct-play part).
2. Check that the DJ skills work with `cursor-agent`: (a) does it find user-level skills on
   its own, (b) does it follow a SKILL.md handed over by path. Also try the DJ's own
   launch (`cursor-agent agent -- <prompt>`, no `--yolo`) and the other three agents.
3. Push to github.com/sette7blo/omacrate, release v0.1.0.
4. Translations: move the panel strings into `i18n/en.json`.

## Ideas, not scheduled

- Small cover art in the now-playing line, off by default.
- Remember the queue across a stop, so play can resume it.
- Report plays back to Plex (play counts, "continue listening").

## Standing constraints

- Nothing runs while idle: no polling, no helper process.
- No visualiser, waveform, equaliser, album-derived colours or radio.
- The DJ, the only AI feature, is off until the user turns it on in the settings, and the
  agent skills are never linked without a separate button press.
- The Plex token is account-wide. It stays in the mode-600 state file and never reaches a
  process listing, a URL, a log, the bar config or an agent.
- Anything that changes the server (saving a playlist, adding an artist, a library scan)
  is a CLI command; the agent skills ask before running one.
