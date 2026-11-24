# Roadmap

## Where we are

v0.2.7 released 2026-11-19 and listed on the Omarchy plugin marketplace (#15215, approved
2026-11-24). The CLI is covered by tests against a stand-in server, and the plugin is used
daily against a real Plex server with Lidarr and the DJ. On `main` since v0.2.7: the panel
no longer has playlist artwork and delete buttons (the DJ and the CLI keep both).

## Next, in order

1. DJ dock beside the DJ terminal (#11), then release and send a marketplace [Verify]
   update after running the marketplace security baseline on the files.
2. Try the DJ with the other supported agents (claude, codex, copilot).
3. Translations: move the panel strings into `i18n/en.json`.

## Ideas, not scheduled

- Small cover art in the now-playing line, off by default.
- Remember the queue across a stop, so play can resume it.
- Report plays back to Plex (play counts, "continue listening").

## Standing constraints

- Nothing runs while idle: no polling, no helper process. The DJ dock reads the playlist
  list every 15 s only while it is on screen.
- No visualiser, waveform, equaliser, album-derived colours or radio.
- The DJ, the only AI feature, is off until the user turns it on in the settings, and the
  agent skills are never linked without a separate button press.
- The Plex token is account-wide. It stays in the mode-600 state file and never reaches a
  process listing, a URL, a log, the bar config or an agent.
- Anything that changes the server (saving a playlist, adding an artist, a library scan)
  is a CLI command; the agent skills ask before running one.
- The DJ uses Lidarr only after its own opt-in, and never sees download activity
  (queue, history, release names, indexers, download clients).
