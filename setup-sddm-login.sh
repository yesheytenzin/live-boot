#!/bin/bash
set -euo pipefail

readonly config_dir="/etc/sddm.conf.d"
readonly state_dir="/var/lib/live-boot"
readonly autologin_conf="$config_dir/autologin.conf"
readonly backup_conf="$state_dir/sddm-autologin.conf"
readonly legacy_backup_conf="$config_dir/autologin.conf.live-boot-disabled"
readonly older_backup_conf="$config_dir/autologin.conf.disabled"
readonly script_path="$(readlink -f "$0")"

action="${1:---disable}"

status() {
  if [[ -f $autologin_conf ]]; then
    echo "enabled: $autologin_conf"
  elif [[ -f $legacy_backup_conf || -f $older_backup_conf ]]; then
    echo "enabled: legacy backup is still inside $config_dir"
  elif [[ -f $backup_conf ]]; then
    echo "disabled by live-boot: $backup_conf"
  elif [[ -d $state_dir ]]; then
    echo "disabled by live-boot: $state_dir"
  else
    echo "disabled: no autologin configuration"
  fi
}

if [[ $action == "--status" ]]; then
  status
  exit 0
fi

if [[ $action != "--disable" && $action != "--restore" ]]; then
  echo "usage: $0 [--disable|--restore|--status]" >&2
  exit 2
fi

if [[ $EUID -ne 0 ]]; then
  if [[ $action == "--disable" && ! -f $autologin_conf && ! -f $legacy_backup_conf && ! -f $older_backup_conf ]]; then
    status
    exit 0
  fi
  if [[ $action == "--restore" && -f $autologin_conf ]]; then
    status
    exit 0
  fi
  if [[ -t 0 && -t 1 ]]; then exec sudo "$script_path" "$action"; fi
  exec pkexec "$script_path" "$action"
fi

case "$action" in
  --disable)
    mkdir -p "$state_dir"
    chmod 711 "$state_dir"
    if [[ -f $autologin_conf ]]; then
      [[ ! -e $backup_conf ]] || { echo "live-boot: refusing to overwrite $backup_conf" >&2; exit 1; }
      mv "$autologin_conf" "$backup_conf"
    fi
    for legacy in "$legacy_backup_conf" "$older_backup_conf"; do
      [[ -f $legacy ]] || continue
      if [[ -e $backup_conf ]]; then rm -f "$legacy"; else mv "$legacy" "$backup_conf"; fi
    done
    ;;
  --restore)
    [[ ! -e $autologin_conf ]] || { status; exit 0; }
    if [[ -f $backup_conf ]]; then
      mv "$backup_conf" "$autologin_conf"
    elif [[ -f $legacy_backup_conf ]]; then
      mv "$legacy_backup_conf" "$autologin_conf"
    elif [[ -f $older_backup_conf ]]; then
      mv "$older_backup_conf" "$autologin_conf"
    else
      status
      exit 0
    fi
    rmdir "$state_dir" 2>/dev/null || true
    ;;
esac

status
