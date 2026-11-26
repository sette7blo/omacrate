# Roadmap

## Where we are

v0.4.0 released 2026-11-26: DJ dock (v0.3.0) and the "Look up and play without asking"
switch. The marketplace listing (#15215, approved 2026-11-24) is still at v0.2.7. The CLI
is covered by tests against a stand-in server, and the plugin is used daily against a real
Plex server with Lidarr and the DJ.

## Next, in order

1. Run the marketplace security baseline on v0.4.0, then send one [Verify] update for
   v0.3.0 and v0.4.0.
2. Try the DJ with the other supported agents (claude, codex, copilot).
3. Translations: move the panel strings into `i18n/en.json`.

## Ideas, not scheduled

- Small cover art in the now-playing line, off by default.
- Remember the queue across a stop, so play can resume it.
- Report plays back to Plex (play counts, "continue listening").

## Standing constraints

- Nothing runs while idle: no polling, no helper process. The DJ dock has no timer either:
  it watches the DJ's view file only while docked.
- No visualiser, waveform, equaliser, album-derived colours or radio.
- The DJ, the only AI feature, is off until the user turns it on in the settings, and the
  agent skills are never linked without a separate button press.
- The Plex token is account-wide. It stays in the mode-600 state file and never reaches a
  process listing, a URL, a log, the bar config or an agent.
- Anything that changes the server (saving a playlist, adding an artist, a library scan)
  is a CLI command; the agent skills ask before running one.
- The DJ uses Lidarr only after its own opt-in, and never sees download activity
  (queue, history, release names, indexers, download clients).
