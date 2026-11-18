---
name: omacrate-add-artist
description: Add an artist the user does not have yet to Lidarr through omacrate, so the albums get downloaded into the Plex music library. Trigger on "add the artist X", "get me some X", "I want X in my library", "download X".
---

# Omacrate: add an artist with Lidarr

Adding an artist starts downloads. Always say what will be added and get a
yes first.

This only works when the user has given omacrate their Lidarr address and
key. Check before anything else:

```sh
omacrate lidarr status
```

If that says Lidarr is not available to the DJ, tell the user they can
allow it in the omacrate settings (the gear, AI DJ section), and stop. If it
says Lidarr is not set up, tell the user to fill in the Lidarr
address and API key in the omacrate settings (the gear in the panel), or to
run `omacrate lidarr set http://<address>:8686` themselves (it asks for the
API key), and stop. Never ask for the key or put one on a command line.

## Steps

1. Make sure the artist is missing:

   ```sh
   omacrate --json search "altin gun"
   ```

2. Look the artist up. The first column is the id the add command takes:

   ```sh
   omacrate lidarr lookup "altin gun"
   ```

   "in Lidarr" in the last column means it is already there: say so and
   stop. If several artists share the name, list them and ask which one.

3. Check where it would go:

   ```sh
   omacrate lidarr profiles
   ```

   With one root folder, the defaults are right and no options are needed.
   With several, ask, then pass `--root <path>` (and `--quality <id>`,
   `--metadata <id>` when the user wants other profiles).

4. Confirm in one line, for example
   `Add Altin Gun to Lidarr in /data/music and search for all albums?`

5. Add:

   ```sh
   omacrate lidarr add 11111111-2222-3333-4444-555555555555
   ```

6. Downloads take a while, and Lidarr usually tells Plex itself once
   they are imported. If the user says the new albums still do not show
   up, offer a rescan (ask first, it makes the server work):

   ```sh
   omacrate scan
   ```

## Rules

- One artist per confirmation.
- Never remove or unmonitor anything.
