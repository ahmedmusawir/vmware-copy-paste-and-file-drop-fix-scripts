#!/usr/bin/env bash
# ============================================================================
# fix-vmware-clipboard.sh
# ----------------------------------------------------------------------------
# Restores copy/paste (and drag-and-drop) between a VMware guest and host
# without rebooting the VM. Targets the user-level vmtoolsd (-n vmusr) which
# is almost always the stale piece when clipboard dies.
#
# Usage:   ./fix-vmware-clipboard.sh           # normal run
#          ./fix-vmware-clipboard.sh --hard    # also restart system daemon
#          ./fix-vmware-clipboard.sh --status  # just show what's running
#
# Author: Jarvis (for Moose @ Stark Industries)
# ============================================================================

set -u

# ---- pretty output ---------------------------------------------------------
c_reset="\033[0m"; c_red="\033[31m"; c_grn="\033[32m"
c_ylw="\033[33m"; c_cyn="\033[36m"; c_bld="\033[1m"

say()  { printf "${c_cyn}==>${c_reset} %s\n" "$*"; }
ok()   { printf "${c_grn}✓${c_reset}  %s\n" "$*"; }
warn() { printf "${c_ylw}!${c_reset}  %s\n" "$*"; }
err()  { printf "${c_red}✗${c_reset}  %s\n" "$*" >&2; }
hr()   { printf '%s\n' "----------------------------------------"; }

# ---- helpers ---------------------------------------------------------------
show_status() {
  hr
  printf "${c_bld}Current vmtoolsd processes:${c_reset}\n"
  if ps aux | grep -E '[v]mtoolsd' >/dev/null; then
    ps aux | grep -E '[v]mtoolsd'
  else
    warn "No vmtoolsd processes running."
  fi
  hr
}

get_vmusr_pids() {
  # PIDs of user-level vmtoolsd belonging to the invoking user
  pgrep -u "$USER" -f 'vmtoolsd -n vmusr' 2>/dev/null || true
}

# ---- mode switches ---------------------------------------------------------
MODE="normal"
case "${1:-}" in
  --status) MODE="status" ;;
  --hard)   MODE="hard"   ;;
  -h|--help)
    sed -n '2,18p' "$0"; exit 0 ;;
  "" ) : ;;
  * ) err "Unknown flag: $1"; exit 2 ;;
esac

# ---- preflight -------------------------------------------------------------
if ! command -v vmtoolsd >/dev/null 2>&1; then
  err "vmtoolsd not found. Is open-vm-tools installed?"
  echo "    Try: sudo apt install --reinstall open-vm-tools open-vm-tools-desktop"
  exit 1
fi

if [[ "$MODE" == "status" ]]; then
  show_status
  exit 0
fi

# ---- 1. kill stale user-level vmtoolsd ------------------------------------
say "Hunting for stale vmusr processes..."
mapfile -t pids < <(get_vmusr_pids)

if (( ${#pids[@]} == 0 )); then
  warn "No existing user-level vmtoolsd. Will start a fresh one."
else
  for pid in "${pids[@]}"; do
    say "Killing PID $pid"
    kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
  done
  sleep 1
  # make sure they're really gone
  mapfile -t still < <(get_vmusr_pids)
  if (( ${#still[@]} > 0 )); then
    warn "Some processes hanging on, forcing..."
    for pid in "${still[@]}"; do kill -9 "$pid" 2>/dev/null || true; done
    sleep 1
  fi
  ok "Stale vmusr processes cleared."
fi

# ---- 2. optional: bounce the system daemon --------------------------------
if [[ "$MODE" == "hard" ]]; then
  say "Hard mode: restarting open-vm-tools system service..."
  if sudo systemctl restart open-vm-tools; then
    ok "open-vm-tools restarted."
  else
    err "Failed to restart open-vm-tools (continuing anyway)."
  fi
fi

# ---- 3. relaunch user-level vmtoolsd --------------------------------------
say "Starting fresh vmtoolsd -n vmusr..."
# detach properly so it survives this shell
nohup /usr/bin/vmtoolsd -n vmusr >/dev/null 2>&1 &
disown 2>/dev/null || true
sleep 1

# ---- 4. verify -------------------------------------------------------------
mapfile -t new_pids < <(get_vmusr_pids)
if (( ${#new_pids[@]} == 0 )); then
  err "vmusr did not come up. Try: $0 --hard"
  show_status
  exit 1
fi

ok "vmusr is running (PID ${new_pids[*]})"
show_status

printf "\n${c_grn}${c_bld}Clipboard should be back.${c_reset} Try copying between host and guest now.\n"
printf "If it's still dead, in VMware: ${c_bld}VM → Settings → Options → Guest Isolation${c_reset}\n"
printf "→ toggle 'Enable copy and paste' off, Apply, on, Apply. Re-handshakes the channel.\n"
