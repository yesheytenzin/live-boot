# Live Boot

Live video wallpaper for the **SDDM boot screen** with a seamless `video → password` transition. Pick a video like a wallpaper and position the login box.

Fork of the `live-wallpaper` pattern, but for boot only (`live-boot` id, not `tenzin.live-boot`).

## Quick start

1. Copy an MP4/MKV/WebM/MOV/M4V into the current theme:

   ```text
   ~/.config/omarchy/backgrounds/<theme-name>/
   ```

2. Open **Style → Boot Background** (or run `~/.config/omarchy/plugins/live-boot/live-boot.sh`).
3. Pick a video, drag/choose the password position, **Apply to Boot**.

Next reboot shows looping muted video behind the password field. Video is revealed only after first frame (no black flash); password fades/slides in.

## Features

- Boot-only: patches `/usr/share/sddm/themes/omarchy/Main.qml` via `pkexec`/`sudo` (template `assets/Main.qml.tpl`)
- Supports MP4, MKV, WebM, MOV, M4V
- Generates thumbnails with existing `ffmpeg`
- 9-grid + custom drag positioning for password box (`center`, `top`, `bottom`, etc. + `offsetX/Y`)
- Live preview in overlay: `video → password` transition WYSIWYG
- Keeps `background.jpg` poster as fallback if `QtMultimedia` missing in SDDM greeter
- Restores stock SDDM on `--uninstall` or `--clear`

## Install

```bash
omarchy plugin add https://github.com/yesheytenzin/live-boot.git --enable
```

Then pick a video:

```bash
~/.config/omarchy/plugins/live-boot/live-boot.sh
# or via menu Style → Boot Background
```

No extra packages required (uses Qt runtime + `ffmpeg`). SDDM video needs `qt6-multimedia` + `gstreamer` for best results; otherwise poster shows.

## Update

```bash
omarchy plugin update live-boot
```

## Remove

```bash
~/.config/omarchy/plugins/live-boot/live-boot.sh --uninstall
omarchy plugin remove live-boot
```

State lives in `~/.local/state/omarchy/live-boot/config.json`, cache in `~/.cache/omarchy/live-boot/`.

## Development

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/live-boot"
omarchy plugin validate "$PLUGIN_DIR"
bash -n "$PLUGIN_DIR/live-boot.sh"
# qmllint needs shell path
/usr/lib/qt6/bin/qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$PLUGIN_DIR/Service.qml" "$PLUGIN_DIR/Overlay.qml"
```

Files:

- `manifest.json` — `service` + `overlay` (`keepLoaded:true`)
- `Service.qml` — watches config, IPC `live-boot`, syncs to SDDM
- `Overlay.qml` — grid + preview + 9-grid/custom position UI
- `live-boot.sh` — discovery, thumbs, `pkexec cp` to `/usr/share/sddm/themes/omarchy/`, menu wiring
- `assets/Main.qml.tpl` — SDDM template with `{{anchor}}` `{{offsetX}}` `{{offsetY}}`

## SDDM notes

SDDM runs as user `sddm`, so videos are copied to `/usr/share/sddm/themes/omarchy/background.mp4` (`644`). Position is baked into `Main.qml` at sync time. Test without reboot:

```bash
sddm --test-mode --theme /usr/share/sddm/themes/omarchy
# or
sddm-greeter --test-mode --theme /usr/share/sddm/themes/omarchy
```

## License

MIT — see [LICENSE](LICENSE)
