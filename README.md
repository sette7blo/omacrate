# omacrate

Omarchy plugin that plays your [Plex](https://plex.tv) music library. One
search box, one list, one headless `mpv`.

![The omacrate panel open on the desktop: tabs, search box, the artist list and Ask DJ](preview.png)

It is deliberately small. There is no visualiser, no waveform, no equaliser,
no colours pulled from album art and no local copy of your library. While
nothing plays, nothing runs: no polling and no helper process, just a
dimmed note on the bar.

Omacrate is not made by or affiliated with Plex.

## Requirements

- Omarchy **Quattro** (v4.5+) with the plugin runtime
- A Plex Media Server with a music library, and a Plex account that can
  reach it
- `mpv`, `socat`, `curl` and `jq`, all in the Arch repositories. The plugin
  never installs packages itself; if one is missing, `install.sh` names it.
- Optional: `mpv-mpris`, so the media keys and Omarchy's own media controls
  work with it

## Install

```sh
omarchy plugin add https://github.com/sette7blo/omacrate.git --enable
```

The first time the plugin loads, it links the `omacrate` command and a
launcher entry. Then link your Plex account: click the note on the bar and
press **Link Plex**, or run `omacrate login`. Either shows a four-character
code to enter at [plex.tv/link](https://plex.tv/link).

To update: `omarchy plugin update io.github.sette7blo.omacrate`.

From a clone instead, `./install.sh` does the same. `--no-enable` links
everything but leaves the bar widget for you to enable, and `--skills` also
links the [agent skills](#dj).

## What gets installed

| Location | What |
|---|---|
| `~/.config/omarchy/plugins/io.github.sette7blo.omacrate` | Plugin dir |
| `~/.local/bin/omacrate` | Command line tool (symlink) |
| `~/.local/share/applications/omacrate.desktop` | Launcher entry, opens the panel |
| `~/.local/state/omarchy/omacrate/credentials.json` | Plex token, the token of the Home user in use and, if you set it, the Lidarr key (mode 600) |
| `~/.local/state/omarchy/omacrate/queue.json` | The current queue (titles only) |
| `~/.local/state/omarchy/omacrate/volume` | The player volume, kept for the next start |
| `~/.local/state/omarchy/omacrate/mpv.conf` | The header mpv sends to your server (mode 600) |
| `$XDG_RUNTIME_DIR/omacrate/mpv.sock` | mpv's control socket, while it runs |
| `~/.agents/skills/omacrate-*`, `~/.claude/skills/omacrate-*`, etc. | Agent skills, only with `install.sh --skills` |

## Bar

A note, always on the bar. It is dimmed while nothing plays or the player
is paused, and shows the title of the track while something plays.

- **Left-click** opens the panel, **middle-click** pauses or resumes,
  **right-click** skips to the next track.

The panel also opens from the launcher (**Omacrate**), or bind a key to
`omacrate panel`, for example in
`~/.config/hypr/bindings.lua` (pick a key that is free on your setup):

```lua
o.bind("SUPER + ALT + M", "Omacrate", "omacrate panel")
```

The title can be turned off in the [settings](#settings).

## Panel

A header with the server and user, four tabs over one list, a search box,
and what is playing at the bottom: the track, a seek bar, previous, pause,
next and stop, and a volume slider. The volume is the player's own (0 to
100), not the system mixer, and it is kept for the next time music starts.
Click the speaker, or right-click the slider, to mute; the mouse wheel over
the slider moves it in steps of five.

- **Queue**: what is playing and what comes next. Press a track to jump to it.
- **Recent**: the albums added most recently.
- **Artists**: every artist, then their albums, then the tracks.
- **Playlists**: the playlists of the user in use.

The panel opens with the cursor in the search box. Typing searches artists,
albums and tracks across the library; clearing the box returns to the tab.
Opening an artist, an album or a playlist shows its contents with a back
arrow above the list.

| Key | Does |
|---|---|
| `Down` or `Enter` in the search box | Move to the list |
| `Tab`, `Shift+Tab` | Next and previous tab |
| `j` `k`, arrows, `PgUp` `PgDn`, `g` `G` | Move in the list |
| `Enter` | Open an artist, album or playlist; play a track |
| `l` or `Right` | Open, never play |
| `h`, `Left`, `Backspace` or `Esc` | Back one list |
| `p` | Play the selected artist, album, playlist or track now |
| `s` | The same, shuffled |
| `a` | Add it to the end of the queue |
| `Space` | Pause or resume |
| `n` `b` | Next and previous track |
| `,` `.` | Back and forward ten seconds |
| `-` `+` | Volume down and up |
| `m` | Mute or unmute |
| `/` | Back to the search box |
| `i` | Set artwork for the selected or open playlist (opens a file chooser) |
| `x` | Delete the selected or open playlist, after a yes |
| `u` | Switch user (Plex Home) |
| `d` | Ask the DJ |
| `Esc` | Back, then close |

### Settings

The gear in the header opens the settings:

- **Plex account**: which server and user are linked, **Link Plex**,
  **Switch user** and **Log out**. Logging out stops the player and forgets
  the token on this computer.
- **Lidarr**: address and API key, so you can add artists you do not have
  yet. See [Lidarr](#lidarr-optional).
- **Bar**: show or hide the track title next to the note.
- **AI DJ**: off by default, and Lidarr is a second, separate yes for it.
  See [DJ](#dj).

### Plex Home users

Playlists belong to a Plex user. If your account is a Plex Home, the
settings have a **Switch user** button (or press `u` in the panel): pick a
user to see and play their playlists.
A user with a PIN can only be switched to from a terminal, with
`omacrate user <name>`, which asks for the PIN. Switching stops the player
and empties the queue.

`Enter` on a track inside an album or a playlist plays the album or
playlist from that track on. On a search result it plays that track alone.

## Command line

```sh
omacrate login                     # link with a code at plex.tv/link
omacrate status                    # what is linked and what is playing
omacrate user                      # the users of your Plex Home
omacrate user "Kid"                # switch to one (their playlists)
omacrate search "khruangbin"       # artists, albums and tracks
omacrate albums 100                # albums of the artist with key 100
omacrate play 200                  # play an album, artist, track or playlist
omacrate play --shuffle 100
omacrate add 201                   # append to the queue
omacrate toggle | next | prev | stop
omacrate volume 60                 # or +5, -5; no number prints it
omacrate playlist create "Late Drive" 300 301 310
omacrate playlist art playlist:901 cover.png   # JPEG, PNG or SVG
omacrate playlist delete playlist:901
omacrate panel                     # open or close the panel
```

`omacrate --help` lists everything. `--json` right after `omacrate` prints
machine-readable output. With several servers on the account, `omacrate
server` lists them and `omacrate server <name>` switches.

## DJ

The DJ is the only part of omacrate that involves an AI agent, and it is
**off until you turn it on**: open the settings (the gear) and switch on
**Enable the DJ**. While it is off there is no DJ button, the `d` key does
nothing, and the plugin never looks for an agent.

Once on, **Ask DJ** in the panel (or `d`) opens your default Omarchy agent
(claude, codex, cursor-agent or copilot) in a terminal and asks it to act as a DJ working from your own library: it
can look through your artists, suggest and play music, and build a playlist
and save it to Plex, make a cover for a playlist, or delete one. Ask it
for a cover ("make a cover for Late Drive") and it generates a picture, or
draws one as an SVG that omacrate turns into a PNG, and sets it as the
playlist's artwork in Plex. The button shows only when a default agent is set
(`omarchy default agent <name>`). `omacrate dj` in a terminal does the same
and needs no setting, since typing it is asking for it.

```sh
omacrate dj
omacrate dj "an hour of mellow funk for cooking"
```

The agent opens with its normal permission prompts, so it asks before it
runs a command, unless you have allowed that command in the agent's own
settings. Omarchy's agent launcher switches those prompts off; the DJ does
not use it, because the agent reads text other people can write (tags in
downloaded files, MusicBrainz data through Lidarr), and such text could
carry instructions. The DJ is also told to treat all of it as data.

There is no AI and no API key in the plugin. The agent is the one you
already use, and it works through the `omacrate` command, so it never needs
your Plex token (it could still read it, see
[The DJ and Lidarr](#the-dj-and-lidarr)). It looks things up and plays
without asking, and asks before anything that changes your server.

The agent is pointed at three skill files in `agent-skill/` by path, so
nothing has to be installed for the DJ. Linking the skills into your agents'
own skill folders is a second, separate choice, never made for you: press
**Install agent skills** in the settings (shown once the DJ is on), or run:

```sh
~/.config/omarchy/plugins/io.github.sette7blo.omacrate/install.sh --skills
```

- **omacrate-library**: look through the library and play from it
- **omacrate-playlist**: build a playlist and save it, after confirmation
- **omacrate-add-artist**: add an artist through Lidarr, after confirmation;
  only for the DJ when you allow it (see below)

**Remove agent skills** in the settings, or `uninstall.sh --skills`, removes
the links again.

### The DJ and Lidarr

What the agent runs, and what it prints, goes to the agent's provider. Your
library is what the DJ is for; what you download is not. So the DJ cannot
use Lidarr until you switch on **Let the DJ use Lidarr** (in the AI DJ
section, shown once Lidarr is set up), or run `omacrate lidarr dj on`.
While it is off:

- the DJ is not handed the add-artist skill, and its instructions do not
  mention Lidarr, so the provider is not told Lidarr is there;
- every `omacrate lidarr` command run by the DJ fails with "not available
  to the DJ" and prints no address; `omacrate status` leaves the Lidarr
  line out.

Even when it is on, the DJ only sees artist names, whether they are already
in Lidarr, and your root folders and profiles: never release names,
indexers, download clients or history. It can never change the Lidarr
settings or this switch. The DJ gets this through `OMACRATE_DJ=1` in its
environment. That is a guard rail, not a wall: the switch decides what the
DJ is told and what `omacrate` will do for it, but it does not hide anything.
The agent runs as you, and the Plex token and the Lidarr key are in
`~/.local/state/omarchy/omacrate/credentials.json` (mode 600, readable by
every program you run), whether the switch is on or off. No plugin can hide a
file from a program running as the same user. The DJ keeps the agent's
permission prompts, but what they cover depends on the agent: some read files
without asking. If that is not enough for you, leave the DJ off, or leave
Lidarr unset. Skills you link into your agents' own folders are not covered;
an agent you start yourself uses them as you ask.

## Lidarr (optional)

To add artists you do not have yet, open the settings
(the gear), fill in the Lidarr address and API key (Lidarr, Settings,
General) and press **Save**; it checks the connection right away. Or from a
terminal:

```sh
omacrate lidarr set https://lidarr.home.lan   # asks for the API key
omacrate lidarr lookup "altin gun"
omacrate lidarr add <id from lookup>
omacrate scan                            # ask Plex to rescan afterwards
omacrate lidarr dj on                    # let the DJ use it too
```

An `https://` address is used as it is, and so is plain `http://` to this
same computer. Plain `http://` to another computer sends the key, and every
request, unencrypted across your network, so omacrate asks first: turn on
**Send the key over plain http** under the address (it is asked again on
every save), or pass `--allow-http`:

```sh
omacrate lidarr set --allow-http http://192.168.1.10:8686
```

A plain http address saved by an earlier version is paused until you save it
again this way.

Set Lidarr's own Plex connection (Lidarr, Settings, Connect, Plex Media
Server, Update Library) and new albums show up in Plex once imported,
without a rescan.

The key is read from the prompt or from stdin, never from the command line.

## Privacy and network

- The login token Plex hands out covers your whole account, not just music.
  Omacrate only ever asks your server for music libraries, but the token
  itself is not limited. To limit it for real, sign in as a Plex Home
  managed user that is shared the music library alone.
- The plugin talks to `plex.tv` (login and finding your server), to your
  server, and to Lidarr if you set it up. Nothing else.
- Tokens travel in headers, never in an address, and reach `curl` through
  stdin and `mpv` through its private control socket, so they do not show in
  a process listing.
- Your server is reached over https only (Plex's own `plex.direct`
  addresses); plain http is used only for a server on this same computer.
  If Secure connections is disabled in the Plex server settings, omacrate
  cannot connect.
- mpv only opens stream paths of Plex's own form (`/library/parts/...`) on
  the linked server, checks the server's certificate (mpv does not by
  default), refuses redirects instead of following them with the token, and
  never hands a stream address to yt-dlp. mpv holds no token of its own:
  each queued track carries the token of the server it was queued from, so
  a track never sends one server's token to another. Switching server, Plex
  Home user or account stops the player and empties the queue.
- Every request to Plex and Lidarr ignores your curl configuration
  (`~/.curlrc`), refuses redirects and checks certificates, so the token and
  the Lidarr key stay with the address they were meant for.
- Each request to Plex or Lidarr uses one read of the saved connection: the
  address, and the token or key that belongs to it. Every login, Plex Home
  user switch and switch to another server starts a new session; a server
  lookup saves its result only in the session it started in, so a logout or
  switch made meanwhile always wins. The panel's lists, and a playlist delete
  or artwork change, belong to the session, server and user they were read
  on: anything else is refused, and a change of any of them clears the lists.
- A picked picture is opened once; it must be a regular file, and that one
  open is what is checked, copied and sent.
- The Lidarr API key goes only to the address you enter, without following
  redirects. Plain http to another computer needs your explicit yes first;
  prefer an https address if Lidarr has one.
- Text from the server is shown as plain text and never becomes part of a
  shell command.
- The Plex token and the Lidarr key are stored in
  `~/.local/state/omarchy/omacrate/credentials.json` (mode 600). Any program
  you run can read it, an AI agent included; the DJ settings do not change
  that.

## Tests

```sh
node --test tests/
```

`cli.test.js` runs the command against a local stand-in for plex.tv, a Plex
server and Lidarr, and plays silent audio through a real `mpv`.

## Uninstall

```sh
~/.config/omarchy/plugins/io.github.sette7blo.omacrate/uninstall.sh
omarchy plugin remove io.github.sette7blo.omacrate
```

The first stops the player and removes the links, the token and the Lidarr
settings; the second removes the plugin. Neither touches Plex or Lidarr. To
also revoke the token, remove the "Omacrate" device under **Authorized
Devices** in your Plex account settings.

## Repository layout

```
manifest.json              Plugin manifest (kinds: service, bar-widget)
Service.qml                Link state, mpv socket, login
BarWidget.qml              The note and track title on the bar
Panel.qml                  The panel: search, list, now playing
RowItem.qml                One row of the list
SettingsView.qml           Plex account, bar and DJ settings
qml/NoteIcon.qml           The icon
Model.js                   Parsing and row building (no QML)
bin/omacrate               Command line tool: Plex, player, Lidarr, DJ
omacrate.desktop.in        Launcher template (install.sh fills in the CLI path)
agent-skill/               Three SKILL.md files for the DJ
tests/                     Node tests for Model.js and the CLI
install.sh / uninstall.sh  Setup the plugin runs on load, clean uninstall
```

## License

MIT. See `LICENSE`.
