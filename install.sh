#!/usr/bin/env bash
# Idempotent installer for the omacrate Omarchy plugin.
# Links the CLI and the launcher and enables the bar widget. The plugin runs
# it with --if-needed on every load, so after `omarchy plugin add` there is
# nothing else to run. The agent skills are linked only on request, with
# --skills; a run without it never creates or checks them.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ID="io.github.sette7blo.omacrate"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN_LINK="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/omacrate"
DESKTOP_LINK="$DATA_HOME/applications/omacrate.desktop"
AGENT_HOMES=("$HOME/.claude" "$HOME/.codex" "$HOME/.agents" "$HOME/.copilot")

ENABLE=true
IF_NEEDED=false
SKILLS=false
SKILLS_STATUS=false

usage() {
  cat <<USAGE
Usage: $0 [--skills] [--no-enable] [--if-needed]
       $0 --skills-status

--skills    also links the agent skills into the agent homes that exist
            (~/.agents, ~/.claude, ~/.codex, ~/.copilot). Never done without
            this option. uninstall.sh --skills removes them again. The DJ
            works without them: it is handed the skill files by path.
--skills-status prints installed, none, or unavailable (no agent home found)
            and changes nothing.
--no-enable links everything but leaves the bar widget for you to enable.
--if-needed does nothing when everything is already in place. The plugin's
            service runs the installer this way each time it loads.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills)
      SKILLS=true; shift ;;
    --skills-status)
      SKILLS_STATUS=true; shift ;;
    --no-enable)
      ENABLE=false; shift ;;
    --if-needed)
      IF_NEEDED=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage >&2; exit 2 ;;
  esac
done

log() { printf '[omacrate] %s\n' "$*"; }

# Never replaces or moves anything: when the path is already taken by something
# that is not this plugin's link, it is left as it is. The plugin calls its own
# bin/ directly, so it works without the link.
link_path() {
  local source_path="$1"
  local target_path="$2"
  mkdir -p "$(dirname "$target_path")"
  if [[ -L "$target_path" && "$(readlink -f "$target_path")" == "$(readlink -f "$source_path")" ]]; then
    return 0
  fi
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    log "left $target_path as it is: something else is already there"
    return 0
  fi
  ln -s "$source_path" "$target_path"
  log "linked $target_path"
}

# Ours, or taken by something we leave alone: either way nothing to do.
in_place() {
  [[ -e "$1" || -L "$1" ]]
}

linked_to() {
  [[ -L "$1" && "$(readlink -f "$1")" == "$(readlink -f "$2")" ]]
}

setup_complete() {
  local skill_src agent_home
  in_place "$CLI_LINK" || return 1
  [[ -e "$PROJECT_DIR/omacrate.desktop" ]] && in_place "$DESKTOP_LINK" || return 1
  $SKILLS || return 0
  for skill_src in "$PROJECT_DIR"/agent-skill/*/; do
    [[ -d "$skill_src" ]] || continue
    for agent_home in "${AGENT_HOMES[@]}"; do
      [[ -d "$agent_home" ]] || continue
      in_place "$agent_home/skills/$(basename "$skill_src")" || return 1
    done
  done
  return 0
}

skills_status() {
  local skill_src agent_home homes=0 linked=0
  for agent_home in "${AGENT_HOMES[@]}"; do
    [[ -d "$agent_home" ]] || continue
    homes=$((homes + 1))
    for skill_src in "$PROJECT_DIR"/agent-skill/*/; do
      [[ -d "$skill_src" ]] || continue
      if linked_to "$agent_home/skills/$(basename "$skill_src")" "$skill_src"; then
        linked=$((linked + 1))
      fi
    done
  done
  if (( homes == 0 )); then echo unavailable
  elif (( linked == 0 )); then echo none
  else echo installed
  fi
}

install_plugin_link() {
  # omarchy plugin add already cloned this folder into the plugin directory.
  # Linking it onto itself would move the checkout aside.
  if [[ -e "$PLUGIN_LINK" || -L "$PLUGIN_LINK" ]] \
    && [[ "$(readlink -f "$PLUGIN_LINK")" == "$PROJECT_DIR" ]]; then
    return
  fi
  link_path "$PROJECT_DIR" "$PLUGIN_LINK"
}

install_cli() {
  chmod +x "$PROJECT_DIR/bin/omacrate"
  link_path "$PROJECT_DIR/bin/omacrate" "$CLI_LINK"
}

install_desktop() {
  local rendered="$PROJECT_DIR/omacrate.desktop"
  sed "s|@@OMACRATE_CLI@@|$CLI_LINK|g" "$PROJECT_DIR/omacrate.desktop.in" > "$rendered"
  link_path "$rendered" "$DESKTOP_LINK"
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
}

install_skills() {
  local skill_src skill_name agent_home
  for skill_src in "$PROJECT_DIR"/agent-skill/*/; do
    [[ -d "$skill_src" ]] || continue
    skill_name="$(basename "$skill_src")"
    for agent_home in "${AGENT_HOMES[@]}"; do
      if [[ -d "$agent_home" ]]; then
        link_path "${skill_src%/}" "$agent_home/skills/$skill_name"
      fi
    done
  done
}

already_enabled() {
  command -v omarchy >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  omarchy plugin list --json 2>/dev/null \
    | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null 2>&1
}

register_omarchy() {
  if ! command -v omarchy >/dev/null 2>&1; then
    log "omarchy not found on PATH; skipping validate/enable"
    return
  fi
  # Rescanning from inside the running service would reload this installer.
  if ! $IF_NEEDED; then
    omarchy plugin validate "$PROJECT_DIR"
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  if $ENABLE && ! already_enabled; then
    omarchy plugin enable "$PLUGIN_ID" right >/dev/null 2>&1 || true
  fi
}

check_tools() {
  local tool missing=()
  for tool in mpv socat curl jq; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] || log "missing: ${missing[*]}. They are in the Arch repositories; install them, then click the note again"
}

main() {
  if $SKILLS_STATUS; then
    skills_status
    exit 0
  fi
  if $IF_NEEDED && setup_complete; then
    exit 0
  fi
  log "plugin dir: $PROJECT_DIR"
  install_plugin_link
  install_cli
  install_desktop
  if $SKILLS; then install_skills; fi
  register_omarchy
  check_tools
  log "done. Run: omacrate login   (or click the note on the bar)"
}

main "$@"
