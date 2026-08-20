# Live Boot

Live video wallpaper for the **SDDM boot screen** with a seamless `video → password` transition. Pick a video like a wallpaper and position the login box. **Audio plays at boot if the video has an audio track** (toggleable).

Fork of the `live-wallpaper` pattern, but for boot only (`live-boot` id).

## Quick start

1. Copy an MP4/MKV/WebM/MOV/M4V into the current theme:

   ```text
   ~/.config/omarchy/backgrounds/<theme-name>/
   ```

2. Open **Style → Boot Background** (or run `~/.config/omarchy/plugins/live-boot/live-boot.sh`).
3. Pick a video, choose the preview resolution, drag the logo and password independently, resize the password field, then **Apply to Boot**.

Next reboot either loops video behind the login or plays it once before revealing the logo and password, depending on the selected reveal mode. If sound is enabled, audio plays at SDDM when the greeter has a PipeWire/Pulse session.

## Features

- Boot-only: patches `/usr/share/sddm/themes/omarchy/Main.qml` via `pkexec`/`sudo` (template `assets/Main.qml.tpl` with `{{anchor}}` `{{offsetX}}` `{{offsetY}}` `{{audioEnabled}}`)
- Supports MP4, MKV, WebM, MOV, M4V
- Limits boot playback to 10 seconds; longer sources are cached as trimmed boot-safe MP4 files
- Generates thumbnails with existing `ffmpeg`, detects audio with `ffprobe`
- **Audio toggle**: auto-enables when video has an audio stream; shows “No audio track” otherwise. Preview respects toggle via `AudioOutput { muted: !audioEnabled }`
- Independent logo/password dragging and resizing (password up to 1600×320, logo up to 1200×400)
- WYSIWYG preview automatically detects the monitor hosting the picker
- Default size/position actions reproduce Omarchy's stock responsive logo and fixed 335×48 password row
- Automatic defaults migrate legacy sizes once; later manual logo/password size edits are preserved
- Optional after-video reveal transition with live replay/end-frame alignment preview, fade timing, and password delay controls
- End-frame alignment mode matches the official logo over moving baked text and links the password 40px below
- Live preview in overlay: `video → password` transition WYSIWYG
- Keeps `background.jpg` poster as fallback if `QtMultimedia` missing
- Restores stock SDDM on `--uninstall` or `--clear`

## Install

```bash
omarchy plugin add https://github.com/yesheytenzin/live-boot.git --enable
```

Then pick a video:

```bash
~/.config/omarchy/plugins/live-boot/live-boot.sh
```

Requires `ffmpeg`/`ffprobe` (already in Omarchy) and `qt6-multimedia` for SDDM video. For boot audio, greeter needs audio stack — test with `sddm --test-mode`.

## Update

```bash
omarchy plugin update live-boot
```

## Remove

```bash
~/.config/omarchy/plugins/live-boot/live-boot.sh --uninstall
omarchy plugin remove live-boot
```

State in `~/.local/state/omarchy/live-boot/config.json` (`video`, `poster`, `pos`, `logoPos`, `fieldSize`, `showLogo`, `previewRes`, `audioEnabled`), cache in `~/.cache/omarchy/live-boot/`.

## Development

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/live-boot"
omarchy plugin validate "$PLUGIN_DIR"
bash -n "$PLUGIN_DIR/live-boot.sh"
```

Files:

- `manifest.json` — `service` + `overlay` (`keepLoaded:true`)
- `Service.qml` — watches config, IPC `live-boot` (`setVideoWithAudio`/`setAudio`/`setPosition`)
- `Overlay.qml` — grid + preview + 9-grid/custom position + audio toggle (auto-detect via `ffprobe`)
- `live-boot.sh` — discovery, thumbs, `has_audio_track()`, `pkexec cp` to `/usr/share/sddm/themes/omarchy/`
- `assets/Main.qml.tpl` — SDDM template with `MediaPlayer + AudioOutput { muted: !audioEnabled }`

## SDDM notes

SDDM runs as user `sddm`, so videos are copied to `/usr/share/sddm/themes/omarchy/background.mp4` (`644`). Position + audio are baked into `Main.qml` at sync. Test without reboot:

```bash
sddm --test-mode --theme /usr/share/sddm/themes/omarchy
```

If audio doesn't play at boot, check `qt6-multimedia-gstreamer` and `gst-plugin-pipewire`.

## License

MIT — see [LICENSE](LICENSE)
