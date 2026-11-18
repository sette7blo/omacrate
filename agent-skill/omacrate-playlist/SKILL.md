---
name: omacrate-playlist
description: Build a playlist from the user's own Plex music library and save it to Plex, give a playlist cover artwork, or delete a playlist. Trigger on "make me a playlist", "build a playlist for X", "something for a long drive", "suggest music from my library", "make a cover for my playlist", "delete the playlist X", "DJ".
---

# Omacrate: build and save a playlist

Read `omacrate-library` first; it lists the commands used to look through
the library. This skill is about choosing tracks and saving them.

## Steps

1. Find out what the user wants if they have not said: a mood, an occasion,
   a length, artists to lean on or to avoid.

2. Learn the library before choosing:

   ```sh
   omacrate --json artists
   ```

   Pick artists that fit, then read their albums and tracks:

   ```sh
   omacrate --json albums <artist key>
   omacrate --json tracks <album key>
   ```

   `seconds` on each track lets you hit a requested length.

3. Offer to play it before saving. Playing changes nothing on the server:

   ```sh
   omacrate play <track key> <track key> ...
   ```

4. Show the list (artist, title, total length) and ask before saving.
   Saving writes to the user's Plex server, so it needs a yes.

5. Save, in the order you want the tracks:

   ```sh
   omacrate playlist create "Late Drive" 300 301 310
   ```

   The answer names the new playlist key (`playlist:901`). To add to an
   existing playlist:

   ```sh
   omacrate playlist add playlist:901 302
   ```

## Cover artwork

Ask before setting artwork; it replaces the picture in Plex. The command
takes a JPEG, a PNG or an SVG file:

```sh
omacrate playlist art playlist:901 /tmp/late-drive-cover.svg
```

If you can generate images, save a square PNG or JPEG (10 MB at most) and
pass that. Otherwise draw the cover as an SVG yourself:

- square `viewBox` (for example `0 0 1000 1000`), shapes, gradients and text
  only, one self-contained file
- no `<image>`, no external fonts, no links to other files or addresses:
  omacrate draws the SVG on its own, so anything outside the file is missing
- write it to a new file under `/tmp`, not over one of the user's files

omacrate turns an SVG into a 1000x1000 PNG before uploading it. Tell the
user the cover is set; they see it in Plex and Plexamp, not in omacrate.

## Deleting a playlist

Deleting cannot be undone. Name the playlist and its track count, get a
clear yes for that one playlist, then:

```sh
omacrate playlist delete playlist:901
```

The tracks stay in the library; only the list goes. Never delete a playlist
the user did not name, and never several at once.

## Rules

- Every track must come from a `tracks` or `search` result in this
  session. Never invent a key and never pad the list with tracks the
  library does not have.
- Passing an album or artist key adds all of its tracks. Use track keys
  when you want to choose.
- One playlist per confirmation. There is no command to rename a
  playlist; tell the user to do that in Plex.
- When the user wants music by an artist they do not have, say so. Only
  if you were given the `omacrate-add-artist` skill, offer to add them.
