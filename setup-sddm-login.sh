#!/bin/bash
set -euo pipefail

readonly config_dir="/etc/sddm.conf.d"
readonly autologin_conf="$config_dir/autologin.conf"
readonly backup_conf="$config_dir/autologin.conf.live-boot-disabled"
readonly legacy_backup_conf="$config_dir/autologin.conf.disabled"
readonly script_path="$(readlink -f "$0")"

action="${1:---disable}"

status() {
  if [[ -f $autologin_conf ]]; then
    echo "enabled: $autologin_conf"
  elif [[ -f $backup_conf ]]; then
    echo "disabled by live-boot: $backup_conf"
  elif [[ -f $legacy_backup_conf ]]; then
    echo "disabled by live-boot: $legacy_backup_conf"
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
  if [[ $action == "--disable" && ! -f $autologin_conf ]]; then
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
    [[ -f $autologin_conf ]] || { status; exit 0; }
    if [[ -e $backup_conf || -e $legacy_backup_conf ]]; then
      echo "live-boot: refusing to overwrite an existing autologin backup" >&2
      exit 1
    fi
    mv "$autologin_conf" "$backup_conf"
    ;;
  --restore)
    [[ ! -e $autologin_conf ]] || { status; exit 0; }
    if [[ -f $backup_conf ]]; then
      mv "$backup_conf" "$autologin_conf"
    elif [[ -f $legacy_backup_conf ]]; then
      mv "$legacy_backup_conf" "$autologin_conf"
    else
      status
      exit 0
    fi
    ;;
esac

status
