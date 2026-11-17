#!/usr/bin/env bash
# Reverses install.sh: stops the player, removes the symlinks, the saved Plex
# token and the Lidarr settings. Never touches Plex or Lidarr themselves.
# With --skills it removes the agent skill links and nothing else.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ID="io.github.sette7blo.omacrate"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PLUGIN_LINK="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/omacrate"
DESKTOP_LINK="$DATA_HOME/applications/omacrate.desktop"
STATE_DIR="$STATE_HOME/omarchy/omacrate"

log() { printf '[omacrate] %s\n' "$*"; }

remove_link() {
  local path="$1"
  if [[ -L "$path" ]]; then
    unlink "$path"
    log "removed $path"
  fi
}

# Only links that point into this plugin are removed, so a skill of the same
# name from somewhere else stays.
remove_skills() {
  local agent_home skill_src link
  for agent_home in "$HOME/.claude" "$HOME/.codex" "$HOME/.agents" "$HOME/.copilot"; do
    [[ -d "$agent_home/skills" ]] || continue
    for skill_src in "$PROJECT_DIR"/agent-skill/*/; do
      [[ -d "$skill_src" ]] || continue
      link="$agent_home/skills/$(basename "$skill_src")"
      if [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$skill_src")" ]]; then
        remove_link "$link"
      fi
    done
  done
}

SKILLS_ONLY=false
case "${1:-}" in
  "") ;;
  --skills) SKILLS_ONLY=true ;;
  *) echo "Usage: $0 [--skills]" >&2; exit 2 ;;
esac

if $SKILLS_ONLY; then
  remove_skills
  log "removed the agent skill links"
  exit 0
fi

"$PROJECT_DIR/bin/omacrate" stop >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi

# A plugin added with omarchy plugin add is a folder, not a link; omarchy
# plugin remove takes that away.
remove_link "$PLUGIN_LINK"
remove_link "$CLI_LINK"
remove_link "$DESKTOP_LINK"
remove_skills

if [[ -d "$STATE_DIR" ]]; then
  rm -rf "$STATE_DIR"
  log "removed $STATE_DIR"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

log "uninstalled $PLUGIN_ID"
