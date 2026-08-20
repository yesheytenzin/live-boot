#!/bin/bash
set -u

readonly plugin_id="live-boot"
readonly state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/live-boot"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/live-boot"
readonly video_state="$state_dir/video"
readonly poster_state="$state_dir/poster"
readonly config_path="$state_dir/config.json"
readonly expected_state="$state_dir/expected"
readonly sddm_theme_dir="/usr/share/sddm/themes/omarchy"
readonly sddm_video="$sddm_theme_dir/background.mp4"
readonly sddm_poster="$sddm_theme_dir/background.jpg"
readonly sddm_main="$sddm_theme_dir/Main.qml"
readonly sddm_main_backup="$sddm_theme_dir/Main.qml.live-boot.bak"

mkdir -p "$state_dir" "$cache_dir"

is_video() {
  local ext="${1##*.}"
  ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
  case ",$ext," in ,mp4,|,mkv,|,webm,|,mov,|,m4v,) return 0 ;; esac
  return 1
}

thumbnail_for() {
  local media="$1" sig hash thumb tmp
  sig=$(stat -Lc '%s:%Y' "$media" 2>/dev/null) || return 1
  hash=$(printf 'ffmpeg-v1:%s:%s' "$media" "$sig" | md5sum | cut -d ' ' -f 1)
  thumb="$cache_dir/$hash.jpg"
  if [[ ! -f $thumb ]]; then
    tmp="$thumb.$$.jpg"
    if ! ffmpeg -nostdin -hide_banner -loglevel error -ss 1 -i "$media" -an -frames:v 1 -vf "scale=768:-2:force_original_aspect_ratio=decrease" -q:v 3 -y "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      ffmpeg -nostdin -hide_banner -loglevel error -i "$media" -an -frames:v 1 -vf "scale=768:-2:force_original_aspect_ratio=decrease" -q:v 3 -y "$tmp" || return 1
    fi
    mv -f "$tmp" "$thumb"
  fi
  printf '%s' "$thumb"
}

has_audio_track() {
  ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$1" 2>/dev/null | grep -q audio
}

boot_video_for() {
  local media="$1" duration sig hash output tmp
  duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$media" 2>/dev/null) || return 1
  if ! awk -v duration="$duration" 'BEGIN { exit !(duration > 10) }'; then
    printf '%s' "$media"
    return 0
  fi

  sig=$(stat -Lc '%s:%Y' "$media" 2>/dev/null) || return 1
  hash=$(printf 'boot-video-10s-v1:%s:%s' "$media" "$sig" | md5sum | cut -d ' ' -f 1)
  output="$cache_dir/$hash.mp4"
  if [[ ! -f $output ]]; then
    tmp="$output.$$.mp4"
    ffmpeg -nostdin -hide_banner -loglevel error -i "$media" -t 10 \
      -map 0:v:0 -map "0:a:0?" -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' \
      -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
      -c:a aac -b:a 192k -movflags +faststart -y "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$output"
  fi
  printf '%s' "$output"
}

ensure_config() {
  if [[ ! -f $config_path ]]; then
    printf '{"video":"","poster":"","pos":{"anchor":"custom","offsetX":0,"offsetY":114},"audioEnabled":false,"fieldSize":{"width":335,"height":48},"showLogo":true,"logoPos":{"offsetX":0,"offsetY":-44},"logoSize":{"width":800,"height":188},"sizesCustomized":false,"previewRes":{"width":1920,"height":1080},"revealMode":"first-frame","transitionDuration":700,"passwordDelay":250,"linkPasswordToLogo":true,"passwordGap":40}\n' >"$config_path"
  fi
  # migrate legacy video/poster files into json if json empty
  local vid="" post=""
  [[ -s $video_state ]] && vid=$(<"$video_state")
  [[ -s $poster_state ]] && post=$(<"$poster_state")
  local has_vid
  has_vid=$(python3 -c "import json,sys; d=json.load(open('$config_path')); print(d.get('video',''))" 2>/dev/null || echo "")
  if [[ -z $has_vid && -n $vid ]]; then
    local pos_json audio_json
    pos_json=$(python3 -c "import json; d=json.load(open('$config_path')); import json as j; print(j.dumps(d.get('pos',{'anchor':'center','offsetX':0,'offsetY':0})))" 2>/dev/null || echo '{"anchor":"center","offsetX":0,"offsetY":0}')
    audio_json=$(python3 -c "import json; d=json.load(open('$config_path')); print('true' if d.get('audioEnabled') or d.get('audio') else 'false')" 2>/dev/null || echo "false")
    # auto-enable audio if legacy video has audio and no explicit setting
    if [[ $audio_json == "false" && -n $vid ]] && has_audio_track "$vid"; then
      audio_json="true"
    fi
    printf '{"video":%s,"poster":%s,"pos":%s,"audioEnabled":%s}\n' "$(printf '%s' "$vid" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" "$(printf '%s' "$post" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" "$pos_json" "$audio_json" >"$config_path"
  fi
  # ensure keys exist
  python3 -c "import json,pathlib; p=pathlib.Path('$config_path'); d=json.load(open(p)); d.setdefault('audioEnabled', False); res=d.setdefault('previewRes', {'width':1920,'height':1080}); lw=min(800, int(res.get('width',1920))*0.8); lh=round(lw*188/800); d.setdefault('pos', {'anchor':'custom','offsetX':0,'offsetY':round(lh/2+20)}); d.setdefault('fieldSize', {'width':335,'height':48}); d.setdefault('showLogo', True); d.setdefault('logoPos', {'offsetX':0,'offsetY':-44}); d.setdefault('logoSize', {'width':round(lw),'height':lh}); d.setdefault('sizesCustomized',False); d.setdefault('revealMode','first-frame'); d.setdefault('transitionDuration',700); d.setdefault('passwordDelay',250); d.setdefault('linkPasswordToLogo',True); d.setdefault('passwordGap',40); open(p,'w').write(json.dumps(d, indent=2)+'\n')" 2>/dev/null || true
}

load_pos() {
  ensure_config
  python3 -c "import json; d=json.load(open('$config_path')); p=d.get('pos',{'anchor':'center','offsetX':0,'offsetY':0}); print(p.get('anchor','center') + '\t' + str(p.get('offsetX',0)) + '\t' + str(p.get('offsetY',0)))" 2>/dev/null || echo -e "center\t0\t0"
}

sync_sddm() {
  ensure_config
  local video poster anchor ox oy audioEnabled audioMuted fieldW fieldH showLogo logoX logoY logoW logoH revealMode transitionDuration passwordDelay
  video=$(python3 -c "import json; print(json.load(open('$config_path')).get('video',''))" 2>/dev/null || echo "")
  poster=$(python3 -c "import json; print(json.load(open('$config_path')).get('poster',''))" 2>/dev/null || echo "")
  audioEnabled=$(python3 -c "import json; print('true' if json.load(open('$config_path')).get('audioEnabled') else 'false')" 2>/dev/null || echo "false")
  if [[ $audioEnabled == "true" ]]; then audioMuted="false"; else audioMuted="true"; fi
  showLogo=$(python3 -c "import json; print('true' if json.load(open('$config_path')).get('showLogo', True) else 'false')" 2>/dev/null || echo "true")
  logoX=$(python3 -c "import json; print(json.load(open('$config_path')).get('logoPos',{}).get('offsetX',0))" 2>/dev/null || echo "0")
  logoY=$(python3 -c "import json; print(json.load(open('$config_path')).get('logoPos',{}).get('offsetY',-44))" 2>/dev/null || echo "-44")
  logoW=$(python3 -c "import json; print(json.load(open('$config_path')).get('logoSize',{}).get('width',800))" 2>/dev/null || echo "800")
  logoH=$(python3 -c "import json; print(json.load(open('$config_path')).get('logoSize',{}).get('height',188))" 2>/dev/null || echo "188")
  fieldW=$(python3 -c "import json; d=json.load(open('$config_path')); print(d.get('fieldSize',{}).get('width',335))" 2>/dev/null || echo "335")
  fieldH=$(python3 -c "import json; d=json.load(open('$config_path')); print(d.get('fieldSize',{}).get('height',48))" 2>/dev/null || echo "48")
  revealMode=$(python3 -c "import json; print(json.load(open('$config_path')).get('revealMode','first-frame'))" 2>/dev/null || echo "first-frame")
  transitionDuration=$(python3 -c "import json; print(json.load(open('$config_path')).get('transitionDuration',700))" 2>/dev/null || echo "700")
  passwordDelay=$(python3 -c "import json; print(json.load(open('$config_path')).get('passwordDelay',250))" 2>/dev/null || echo "250")
  read -r anchor ox oy <<<"$(load_pos)"

  if [[ -z $video || ! -f $video ]]; then
    # clear SDDM video -> restore theme
    if [[ -f $sddm_main_backup ]]; then
      pkexec bash -c "rm -f '$sddm_video' '$sddm_poster'; cp '$sddm_main_backup' '$sddm_main'" 2>/dev/null || sudo bash -c "rm -f '$sddm_video' '$sddm_poster'; cp '$sddm_main_backup' '$sddm_main'" 2>/dev/null || true
    fi
    return 0
  fi

  if [[ -z $poster || ! -f $poster ]]; then
    poster=$(thumbnail_for "$video") || { echo "cannot thumb $video" >&2; return 1; }
    # update config poster
    python3 -c "import json,pathlib; p=pathlib.Path('$config_path'); d=json.load(open(p)); d['poster']=r'$poster'; open(p,'w').write(json.dumps(d,indent=2)+'\n')" 2>/dev/null || true
  fi

  local boot_video
  boot_video=$(boot_video_for "$video") || { echo "cannot prepare 10-second boot video" >&2; return 1; }

  local tpl="$HOME/.config/omarchy/plugins/$plugin_id/assets/Main.qml.tpl"
  local tmp_main
  tmp_main=$(mktemp)
  local tmp_poster_dest
  tmp_poster_dest=$(mktemp --suffix=.jpg)
  local tmp_video_dest
  tmp_video_dest=$(mktemp --suffix=.mp4)

  cp -f "$poster" "$tmp_poster_dest"
  cp -f "$boot_video" "$tmp_video_dest"

  # render template if exists, else use sddm Main.qml with injected pos/size via sed
  if [[ -f $tpl ]]; then
    sed -e "s/{{anchor}}/$anchor/g" -e "s/{{offsetX}}/$ox/g" -e "s/{{offsetY}}/$oy/g" -e "s/{{audioMuted}}/$audioMuted/g" -e "s/{{audioEnabled}}/$audioEnabled/g" -e "s/{{showLogo}}/$showLogo/g" -e "s/{{logoOffsetX}}/$logoX/g" -e "s/{{logoOffsetY}}/$logoY/g" -e "s/{{logoWidth}}/$logoW/g" -e "s/{{logoHeight}}/$logoH/g" -e "s/{{fieldWidth}}/$fieldW/g" -e "s/{{fieldHeight}}/$fieldH/g" -e "s/{{revealMode}}/$revealMode/g" -e "s/{{transitionDuration}}/$transitionDuration/g" -e "s/{{passwordDelay}}/$passwordDelay/g" "$tpl" >"$tmp_main"
  else
    cp -f "$OMARCHY_PATH/default/sddm/omarchy/Main.qml" "$tmp_main" 2>/dev/null || cp -f "/usr/share/omarchy/default/sddm/omarchy/Main.qml" "$tmp_main" 2>/dev/null || cp -f "$sddm_main" "$tmp_main"
  fi

  # backup once
  if [[ ! -f $sddm_main_backup && -f $sddm_main ]]; then
    pkexec bash -c "cp '$sddm_main' '$sddm_main_backup'" 2>/dev/null || sudo bash -c "cp '$sddm_main' '$sddm_main_backup'" 2>/dev/null || cp "$sddm_main" "$sddm_main_backup" 2>/dev/null || true
  fi

  pkexec bash -c "cp '$tmp_video_dest' '$sddm_video'; cp '$tmp_poster_dest' '$sddm_poster'; cp '$tmp_main' '$sddm_main'; chmod 644 '$sddm_video' '$sddm_poster' '$sddm_main'" 2>/dev/null \
    || sudo bash -c "cp '$tmp_video_dest' '$sddm_video'; cp '$tmp_poster_dest' '$sddm_poster'; cp '$tmp_main' '$sddm_main'; chmod 644 '$sddm_video' '$sddm_poster' '$sddm_main'" 2>/dev/null \
    || { cp "$tmp_video_dest" "$sddm_video" 2>/dev/null; cp "$tmp_poster_dest" "$sddm_poster" 2>/dev/null; cp "$tmp_main" "$sddm_main" 2>/dev/null; }

  rm -f "$tmp_main" "$tmp_poster_dest" "$tmp_video_dest"
  printf '%s\n' "$poster" >"$expected_state"
}

resume_live_boot() {
  ensure_config
  local video
  video=$(python3 -c "import json; print(json.load(open('$config_path')).get('video',''))" 2>/dev/null || echo "")
  [[ -n $video && -f $video ]] || return 0
  sync_sddm
}

clear_boot() {
  printf '{"video":"","poster":"","pos":{"anchor":"custom","offsetX":0,"offsetY":114},"audioEnabled":false,"fieldSize":{"width":335,"height":48},"showLogo":true,"logoPos":{"offsetX":0,"offsetY":-44},"logoSize":{"width":800,"height":188},"sizesCustomized":false,"previewRes":{"width":1920,"height":1080},"revealMode":"first-frame","transitionDuration":700,"passwordDelay":250,"linkPasswordToLogo":true,"passwordGap":40}\n' >"$config_path"
  rm -f "$video_state" "$poster_state" "$expected_state"
  sync_sddm
}

ensure_menu_override() {
  local file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  local action="~/.config/omarchy/plugins/$plugin_id/live-boot.sh"
  local entry="{\"icon\":\"\",\"label\":\"Boot Background\",\"aliases\":[\"boot background\",\"boot video\",\"sddm\"],\"action\":\"$action\"}"
  mkdir -p "$(dirname "$file")"
  if [[ ! -f $file ]]; then
    printf '{\n  "style.bootBackground": %s\n}\n' "$entry" >"$file"
  elif grep -qE '^[[:space:]]*"style\.bootBackground"[[:space:]]*:' "$file"; then
    sed -i -E "s|^([[:space:]]*\"style\.bootBackground\"[[:space:]]*:[[:space:]]*).*$|\1$entry,|" "$file"
  else
    sed -i "0,/^[[:space:]]*{/a\  \"style.bootBackground\": $entry," "$file"
  fi
  omarchy menu refresh >/dev/null 2>&1 || true
}

unwire_menu_override() {
  local file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  [[ -f $file ]] || return 0
  sed -i -E '\|^[[:space:]]*"style\.bootBackground".*live-boot/live-boot\.sh.*$|d' "$file"
  omarchy menu refresh >/dev/null 2>&1 || true
}

uninstall_plugin_state() {
  unwire_menu_override
  clear_boot
  # restore SDDM if backup exists
  if [[ -f $sddm_main_backup ]]; then
    pkexec bash -c "cp '$sddm_main_backup' '$sddm_main'; rm -f '$sddm_video' '$sddm_poster' '$sddm_main_backup'" 2>/dev/null || sudo bash -c "cp '$sddm_main_backup' '$sddm_main'; rm -f '$sddm_video' '$sddm_poster' '$sddm_main_backup'" 2>/dev/null || true
  fi
  rm -rf "$state_dir" "$cache_dir"
}

check_config() {
  # placeholder for Service timer poll - ensure sync if config changed externally
  :
}

case "${1:-}" in
  --sync-sddm) sync_sddm; exit $? ;;
  --resume) resume_live_boot; exit $? ;;
  --clear) clear_boot; exit 0 ;;
  --wire-menu) ensure_menu_override; exit 0 ;;
  --unwire-menu) unwire_menu_override; exit 0 ;;
  --uninstall) uninstall_plugin_state; exit 0 ;;
  --check-config) check_config; exit 0 ;;
esac

# --- picker flow: summon overlay with rows ---
ensure_config
theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo "tokyo-night")
theme_dir="$HOME/.local/state/omarchy/current/theme/backgrounds"
user_dir="$HOME/.config/omarchy/backgrounds/$theme_name"
current_video=$(python3 -c "import json; print(json.load(open('$config_path')).get('video',''))" 2>/dev/null || echo "")
current_pos_json=$(python3 -c "import json; d=json.load(open('$config_path')); import json as j; print(j.dumps(d.get('pos',{'anchor':'custom','offsetX':0,'offsetY':114})))" 2>/dev/null || echo '{"anchor":"custom","offsetX":0,"offsetY":114}')
current_size_json=$(python3 -c "import json; d=json.load(open('$config_path')); import json as j; print(j.dumps(d.get('fieldSize',{'width':335,'height':48})))" 2>/dev/null || echo '{"width":335,"height":48}')
current_show_logo=$(python3 -c "import json; print('true' if json.load(open('$config_path')).get('showLogo', True) else 'false')" 2>/dev/null || echo "true")
current_logo_pos_json=$(python3 -c "import json; d=json.load(open('$config_path')); import json as j; print(j.dumps(d.get('logoPos',{'offsetX':0,'offsetY':-44})))" 2>/dev/null || echo '{"offsetX":0,"offsetY":-44}')
current_logo_size_json=$(python3 -c "import json; d=json.load(open('$config_path')); import json as j; print(j.dumps(d.get('logoSize',{'width':800,'height':188})))" 2>/dev/null || echo '{"width":800,"height":188}')
current_sizes_customized=$(python3 -c "import json; print('true' if json.load(open('$config_path')).get('sizesCustomized') else 'false')" 2>/dev/null || echo "false")
current_res_json=$(python3 -c "import json; d=json.load(open('$config_path')); import json as j; print(j.dumps(d.get('previewRes',{'width':1920,'height':1080})))" 2>/dev/null || echo '{"width":1920,"height":1080}')
detected_res_json=$(hyprctl monitors -j 2>/dev/null | jq -c 'map(select(.focused))[0] // .[0] | {width, height}' 2>/dev/null || true)
[[ $detected_res_json == \{* ]] || detected_res_json=$current_res_json
current_reveal_mode=$(python3 -c "import json; print(json.load(open('$config_path')).get('revealMode','first-frame'))" 2>/dev/null || echo "first-frame")
current_transition_duration=$(python3 -c "import json; print(json.load(open('$config_path')).get('transitionDuration',700))" 2>/dev/null || echo "700")
current_password_delay=$(python3 -c "import json; print(json.load(open('$config_path')).get('passwordDelay',250))" 2>/dev/null || echo "250")
current_link_password=$(python3 -c "import json; print('true' if json.load(open('$config_path')).get('linkPasswordToLogo',True) else 'false')" 2>/dev/null || echo "true")
current_password_gap=$(python3 -c "import json; print(json.load(open('$config_path')).get('passwordGap',40))" 2>/dev/null || echo "40")
current_audio=$(python3 -c "import json; print('true' if json.load(open('$config_path')).get('audioEnabled') else 'false')" 2>/dev/null || echo "false")

rows_file=$(mktemp)
trap 'rm -f "$rows_file"' EXIT

media_args=()
while IFS= read -r ext; do
  (( ${#media_args[@]} > 0 )) && media_args+=(-o)
  media_args+=(-iname "*.$ext")
done <<'EOF_EXTS'
mp4
mkv
webm
mov
m4v
EOF_EXTS

found_any=false
if [[ -d $theme_dir || -d $user_dir ]]; then
  find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \( "${media_args[@]}" \) -print0 2>/dev/null | sort -z | while IFS= read -r -d '' media; do
    thumb=$(thumbnail_for "$media") || continue
    printf '%s\t%s\n' "$media" "$thumb"
    found_any=true
  done >"$rows_file"
fi

if [[ ! -s $rows_file ]]; then
  omarchy-notification-send "No boot videos found — drop an MP4 into ~/.config/omarchy/backgrounds/$theme_name/" -t 3000
  exit 0
fi

rows_b64=$(base64 -w 0 <"$rows_file")
payload=$(printf '{"rowsB64":"%s","selected":%s,"pos":%s,"fieldSize":%s,"showLogo":%s,"logoPos":%s,"logoSize":%s,"sizesCustomized":%s,"previewRes":%s,"detectedRes":%s,"themeDir":"%s","audioEnabled":%s,"revealMode":"%s","transitionDuration":%s,"passwordDelay":%s,"linkPasswordToLogo":%s,"passwordGap":%s}' "$rows_b64" "$(printf '%s' "$current_video" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" "$current_pos_json" "$current_size_json" "$current_show_logo" "$current_logo_pos_json" "$current_logo_size_json" "$current_sizes_customized" "$current_res_json" "$detected_res_json" "$sddm_theme_dir" "$current_audio" "$current_reveal_mode" "$current_transition_duration" "$current_password_delay" "$current_link_password" "$current_password_gap")

# summon overlay; keepLoaded overlay stays mounted
if ! omarchy-shell shell summon live-boot "$payload" >/dev/null 2>&1; then
  # fallback: try summon via plugin id as overlay
  omarchy-shell -q live-boot open "$payload" >/dev/null 2>&1 || true
  # last resort: directly summon shell overlay id
  omarchy-shell shell summon live-boot "$payload" >/dev/null 2>&1 || {
    omarchy-notification-send "Live Boot: could not open picker (shell not running?)" -t 2000
    exit 1
  }
fi
