pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell
  property var manifest
  property string home: Quickshell.env("HOME")

  property bool opened: false
  property var rows: [] // [{filePath, thumbnailPath}]
  property string selectedPath: ""
  property int selectedIndex: 0
  property string filterText: ""
  property bool videoReady: false
  property var pos: ({ anchor: "custom", offsetX: 0, offsetY: 114 })
  property var fieldSize: ({ width: 335, height: 48 })
  property bool audioEnabled: false
  property bool showLogo: true
  property var logoPos: ({ offsetX: 0, offsetY: -44 })
  property var logoSize: ({ width: 800, height: 188 })
  property bool sizesCustomized: false
  property var previewRes: ({ width: 1920, height: 1080 })
  property var detectedRes: ({ width: 0, height: 0 })
  property string themeDir: "/usr/share/sddm/themes/omarchy"
  property string revealMode: "first-frame"
  property int transitionDuration: 700
  property int passwordDelay: 250
  property bool previewRevealStarted: false
  property bool previewLogoRevealed: false
  property bool previewPasswordRevealed: false
  property bool previewHasAudio: false
  property string previewVideo: ""
  property string previewPoster: ""
  property bool dragging: false
  property bool logoDragging: false
  property bool logoResizing: false
  property bool resizing: false
  property bool linkPasswordToLogo: true
  property int passwordGap: 40
  property bool endAlignMode: false
  readonly property int maxVideoDuration: 10000

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/live-boot"
  readonly property string configPath: stateDir + "/config.json"

  function fileUrl(path) {
    if (!path) return ""
    var enc = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + enc
  }

  function open(payloadJson) {
    var args = {}
    try { args = JSON.parse(payloadJson || "{}") } catch (e) { args = {} }
    if (args.rowsB64) {
      try {
        var decoded = Qt.atob(String(args.rowsB64))
        var lines = decoded.split("\n")
        var out = []
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          var parts = line.split("\t")
          if (parts.length >= 2) out.push({ filePath: parts[0], thumbnailPath: parts[1] })
        }
        rows = out
      } catch (e) { console.warn("live-boot decode failed", e) }
    } else if (Array.isArray(args.rows)) {
      rows = args.rows
    }
    selectedPath = String(args.selected || args.selectedPath || "")
    if (selectedPath) {
      for (var k = 0; k < rows.length; k++) if (rows[k].filePath === selectedPath) { selectedIndex = k; break }
      previewVideo = selectedPath
      previewPoster = rows[selectedIndex] ? rows[selectedIndex].thumbnailPath : ""
    } else if (rows.length > 0) {
      selectedIndex = 0
      previewVideo = rows[0].filePath
      previewPoster = rows[0].thumbnailPath
    }
    // load pos/size/audio/logo/res from args or file
    if (args.pos && typeof args.pos === "object") pos = args.pos
    if (args.fieldSize && typeof args.fieldSize === "object") fieldSize = { width: Math.max(200,Math.min(1600, args.fieldSize.width||335)), height: Math.max(40,Math.min(320, args.fieldSize.height||48)) }
    else if (args.size && typeof args.size === "object") fieldSize = { width: Math.max(200,Math.min(1600, args.size.width||335)), height: Math.max(40,Math.min(320, args.size.height||48)) }
    else if (!args.pos) loadPos() // loadPos also loads fieldSize
    else if (typeof args.audioEnabled !== "boolean") loadPos()
    if (typeof args.audioEnabled === "boolean") audioEnabled = args.audioEnabled
    else if (typeof args.audio === "boolean") audioEnabled = args.audio
    if (typeof args.showLogo === "boolean") showLogo = args.showLogo
    if (args.logoPos && typeof args.logoPos === "object") logoPos = { offsetX: parseInt(args.logoPos.offsetX)||0, offsetY: parseInt(args.logoPos.offsetY)||0 }
    if (args.logoSize && typeof args.logoSize === "object") logoSize = { width: Math.max(80,Math.min(1200,args.logoSize.width||800)), height: Math.max(20,Math.min(400,args.logoSize.height||188)) }
    sizesCustomized = args.sizesCustomized === true
    if (args.previewRes && typeof args.previewRes === "object") previewRes = { width: parseInt(args.previewRes.width)||1920, height: parseInt(args.previewRes.height)||1080 }
    if (args.detectedRes && typeof args.detectedRes === "object") detectedRes = { width: parseInt(args.detectedRes.width)||0, height: parseInt(args.detectedRes.height)||0 }
    if (typeof args.themeDir === "string" && args.themeDir) themeDir = String(args.themeDir)
    if (args.revealMode === "video-end" || args.revealMode === "first-frame") revealMode = args.revealMode
    if (args.transitionDuration !== undefined) transitionDuration = Math.max(100, Math.min(3000, parseInt(args.transitionDuration)||700))
    if (args.passwordDelay !== undefined) passwordDelay = Math.max(0, Math.min(3000, parseInt(args.passwordDelay)||0))
    linkPasswordToLogo = args.linkPasswordToLogo !== false
    if (args.passwordGap !== undefined) passwordGap = Math.max(0, Math.min(300, parseInt(args.passwordGap)||0))
    opened = true
    detectScreenTimer.restart()
    videoReady = false
    previewHasAudio = false
    if (previewVideo) { replayTransition(); audioProbeProc.running = true }
  }

  function close() {
    opened = false
    previewPlayer.stop()
  }

  function loadPos() {
    // best-effort read via Process cat
    loadPosProc.running = true
  }

  Process {
    id: loadPosProc
    command: ["bash", "-c", "cat " + String(root.configPath).replace(/'/g, "'\\''") + " 2>/dev/null | head -c 8192"]
    stdout: StdioCollector { id: loadPosOut; waitForEnd: true }
    onExited: {
      try {
        var cfg = JSON.parse(String(loadPosOut.text || "{}"))
        if (cfg.pos) root.pos = cfg.pos
        if (cfg.fieldSize && typeof cfg.fieldSize === "object") root.fieldSize = { width: Math.max(200,Math.min(1600, cfg.fieldSize.width||335)), height: Math.max(40,Math.min(320, cfg.fieldSize.height||48)) }
        else if (cfg.size && typeof cfg.size === "object") root.fieldSize = { width: Math.max(200,Math.min(1600, cfg.size.width||335)), height: Math.max(40,Math.min(320, cfg.size.height||48)) }
        if (typeof cfg.audioEnabled === "boolean") root.audioEnabled = cfg.audioEnabled
        if (typeof cfg.showLogo === "boolean") root.showLogo = cfg.showLogo
        if (cfg.logoPos && typeof cfg.logoPos === "object") root.logoPos = { offsetX: parseInt(cfg.logoPos.offsetX)||0, offsetY: parseInt(cfg.logoPos.offsetY)||0 }
        if (cfg.logoSize && typeof cfg.logoSize === "object") root.logoSize = { width: Math.max(80,Math.min(1200,cfg.logoSize.width||800)), height: Math.max(20,Math.min(400,cfg.logoSize.height||188)) }
        root.sizesCustomized = cfg.sizesCustomized === true
        if (cfg.previewRes && typeof cfg.previewRes === "object") {
          root.previewRes = { width: parseInt(cfg.previewRes.width)||1920, height: parseInt(cfg.previewRes.height)||1080 }
        }
        if (cfg.revealMode === "video-end" || cfg.revealMode === "first-frame") root.revealMode = cfg.revealMode
        if (cfg.transitionDuration !== undefined) root.transitionDuration = Math.max(100, Math.min(3000, parseInt(cfg.transitionDuration)||700))
        if (cfg.passwordDelay !== undefined) root.passwordDelay = Math.max(0, Math.min(3000, parseInt(cfg.passwordDelay)||0))
        root.linkPasswordToLogo = cfg.linkPasswordToLogo !== false
        if (cfg.passwordGap !== undefined) root.passwordGap = Math.max(0, Math.min(300, parseInt(cfg.passwordGap)||0))
        if (cfg.video && !root.previewVideo) {
          root.previewVideo = String(cfg.video)
          root.previewPoster = String(cfg.poster || "")
          audioProbeProc.running = true
        }
      } catch (e) {}
    }
  }

  // detect if previewVideo has an audio stream
  Process {
    id: audioProbeProc
    command: ["bash", "-c", "ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 " + Util.shellQuote(root.previewVideo) + " 2>/dev/null | head -n 1"]
    stdout: StdioCollector { id: audioProbeOut; waitForEnd: true }
    onExited: {
      var has = String(audioProbeOut.text || "").trim().length > 0
      root.previewHasAudio = has
      // auto-enable audio if video has audio (user wants sound when available)
      if (has && !root.audioEnabled) {
        root.audioEnabled = true
      } else if (!has && root.audioEnabled) {
        root.audioEnabled = false
      }
    }
  }

  function selectIndex(idx) {
    if (idx < 0 || idx >= rows.length) return
    selectedIndex = idx
    selectedPath = rows[idx].filePath
    previewVideo = rows[idx].filePath
    previewPoster = rows[idx].thumbnailPath
    previewHasAudio = false
    replayTransition()
    audioProbeProc.running = true
  }

  function revealPreview() {
    if (previewRevealStarted) {
      if (!previewPasswordRevealed) { previewPasswordTimer.stop(); previewPasswordRevealed = true }
      return
    }
    previewRevealStarted = true
    previewFallbackTimer.stop()
    previewEndSafety.stop()
    if (revealMode === "video-end" && previewPlayer.playbackState === MediaPlayer.PlayingState) previewPlayer.pause()
    previewLogoRevealed = true
    if (passwordDelay <= 0) previewPasswordRevealed = true
    else previewPasswordTimer.restart()
  }

  function replayTransition() {
    endAlignMode = false
    previewRevealStarted = false
    previewLogoRevealed = false
    previewPasswordRevealed = false
    videoReady = false
    previewPasswordTimer.stop()
    previewFallbackTimer.stop()
    previewEndSafety.stop()
    previewEndSafety.interval = 15000
    previewPlayer.stop()
    previewPlayer.source = fileUrl(previewVideo)
    previewPlayer.play()
    previewFallbackTimer.restart()
    if (revealMode === "video-end") previewEndSafety.restart()
  }

  function applySelected() {
    if (!selectedPath) return
    var payload = JSON.stringify({ video: selectedPath, poster: previewPoster, audioEnabled: audioEnabled, pos: pos, fieldSize: fieldSize, showLogo: showLogo, logoPos: logoPos, logoSize: logoSize, sizesCustomized: sizesCustomized, previewRes: previewRes, revealMode: revealMode, transitionDuration: transitionDuration, passwordDelay: passwordDelay, linkPasswordToLogo: linkPasswordToLogo, passwordGap: passwordGap })
    Quickshell.execDetached(["bash", "-c", "omarchy-shell -q live-boot applySettings " + Util.shellQuote(payload) + " >/dev/null 2>&1 &"])
    close()
  }

  function updatePos(anchor, ox, oy) {
    linkPasswordToLogo = false
    pos = { anchor: anchor, offsetX: ox, offsetY: oy }
  }
  function updateFieldSize(w, h) {
    fieldSize = { width: Math.max(200, Math.min(1600, w)), height: Math.max(40, Math.min(320, h)) }
    sizesCustomized = true
    syncLinkedPassword()
  }
  function updateShowLogo(v) { showLogo = !!v }
  function updateLogoPos(ox, oy) { logoPos = { offsetX: ox, offsetY: oy }; syncLinkedPassword() }
  function updateLogoSize(w, h) { logoSize = { width: Math.max(80, Math.min(1200, w)), height: Math.max(20, Math.min(400, h)) }; sizesCustomized = true; syncLinkedPassword() }
  function syncLinkedPassword() {
    if (!linkPasswordToLogo) return
    pos = { anchor: "custom", offsetX: Math.round(logoPos.offsetX), offsetY: Math.round(logoPos.offsetY + logoSize.height/2 + passwordGap + fieldSize.height/2) }
  }
  function setPasswordLink(enabled) { linkPasswordToLogo = !!enabled; syncLinkedPassword() }
  function updatePasswordGap(value) { passwordGap = Math.max(0, Math.min(300, value)); linkPasswordToLogo = true; syncLinkedPassword() }
  function logoWidthFor(screenWidth) { return Math.round(Math.min(800, screenWidth * 0.8)) }
  function logoHeightFor(screenWidth) { return Math.round(logoWidthFor(screenWidth) * 188 / 800) }
  function defaultLogoWidth() { return logoWidthFor(previewRes.width) }
  function defaultLogoHeight() { return logoHeightFor(previewRes.width) }
  function defaultPasswordY() { return Math.round(defaultLogoHeight() / 2 + 20) }
  function resetDefaultPositions() {
    logoPos = { offsetX: 0, offsetY: -44 }
    linkPasswordToLogo = true
    passwordGap = 40
    syncLinkedPassword()
  }
  function resetDefaultSizes() {
    updateLogoSize(defaultLogoWidth(), defaultLogoHeight())
    updateFieldSize(335, 48)
    sizesCustomized = false
    syncLinkedPassword()
  }

  Timer { id: previewPasswordTimer; interval: root.passwordDelay; onTriggered: root.previewPasswordRevealed = true }
  Timer { id: previewFallbackTimer; interval: 5000; onTriggered: if (!root.videoReady) root.revealPreview() }
  Timer { id: previewEndSafety; interval: 15000; onTriggered: root.revealPreview() }
  Timer { id: endAlignTimer; interval: 80; onTriggered: { previewPlayer.pause(); root.previewRevealStarted = true; root.previewLogoRevealed = true; root.previewPasswordRevealed = true; root.syncLinkedPassword() } }
  Timer { id: detectScreenTimer; interval: 0; onTriggered: root.detectScreen() }
  function alignEndFrame() {
    revealMode = "video-end"
    endAlignMode = true
    setPasswordLink(true)
    previewPasswordTimer.stop()
    previewFallbackTimer.stop()
    previewEndSafety.stop()
    previewPlayer.setPosition(Math.max(0, Math.min(previewPlayer.duration || maxVideoDuration, maxVideoDuration) - 50))
    endAlignTimer.restart()
  }
  function detectScreen() {
    var w = detectedRes.width > 0 ? detectedRes.width : Math.round(win.Screen.width)
    var h = detectedRes.height > 0 ? detectedRes.height : Math.round(win.Screen.height)
    if (w < 1 || h < 1) return

    previewRes = { width: w, height: h }
    if (!sizesCustomized) resetDefaultSizes()
    syncLinkedPassword()
  }

  // position helpers for preview
  function posToAnchors() {
    // returns placement for password box in preview
    var a = pos.anchor || "center"
    if (a === "center") return { center: true }
    return { anchor: a }
  }

  PanelWindow {
    id: win
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "live-boot-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.imagePicker.scrim
      opacity: 0.92
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // main card - responsive
    Rectangle {
      id: card
      width: Math.min(parent.width - 40, 990)
      height: Math.min(parent.height - 40, 738)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      border.color: Color.imagePicker.selectedBorder
      border.width: 1
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.panelGap

        // Left: grid
        ColumnLayout {
          Layout.preferredWidth: 300
          Layout.fillHeight: true
          spacing: Style.spacing.rowGap

          Text {
            text: "Boot Video"
            color: Color.foreground
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }
          Text {
            text: "Pick a video from the theme backgrounds. Preview on the right shows the SDDM transition."
            color: Color.background
            // use muted via alpha
            opacity: 0.7
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // search
          Rectangle {
            Layout.fillWidth: true
            height: Style.spacing.controlHeight
            radius: Style.cornerRadius
            color: Color.imagePicker.background || Color.background
            border.color: filterInput.activeFocus ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
            border.width: 1
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              TextInput {
                id: filterInput
                Layout.fillWidth: true
                color: Color.foreground
                selectionColor: Color.accent
                font.pixelSize: Style.font.body
                clip: true
                onTextChanged: root.filterText = text
                Keys.onPressed: function(e) {
                  if (e.key === Qt.Key_Escape) { if (text) text = ""; else root.close(); e.accepted = true }
                  else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.applySelected(); e.accepted = true }
                }
              }
              Text { visible: !filterInput.text; text: "Filter…"; color: Color.foreground; opacity: 0.4; font.pixelSize: Style.font.bodySmall }
            }
          }

          // grid
          GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 145
            cellHeight: 96
            model: {
              var out = []
              var f = String(root.filterText || "").toLowerCase()
              for (var i = 0; i < root.rows.length; i++) {
                var r = root.rows[i]
                if (f && r.filePath.toLowerCase().indexOf(f) === -1) continue
                out.push({ idx: i, data: r })
              }
              return out
            }
            delegate: Item {
              required property var modelData
              width: grid.cellWidth
              height: grid.cellHeight
              Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: Style.cornerRadius
                color: "transparent"
                border.color: modelData.idx === root.selectedIndex ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
                border.width: modelData.idx === root.selectedIndex ? 2 : 1
                clip: true
                Image {
                  anchors.fill: parent
                  source: root.fileUrl(modelData.data.thumbnailPath)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                }
                Rectangle {
                  anchors.fill: parent
                  color: Util.alpha(Color.background, modelData.idx === root.selectedIndex ? 0 : 0.25)
                }
                // play badge
                Rectangle {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: 6
                  width: 22; height: 14; radius: 3
                  color: Util.alpha(Color.background, 0.7)
                  Text { anchors.centerIn: parent; text: "▶"; color: Color.foreground; font.pixelSize: 8 }
                }
                Text {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: 4
                  text: String(modelData.data.filePath).split("/").pop()
                  color: Color.foreground
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                  style: Text.Outline
                  styleColor: Util.alpha(Color.background, 0.8)
                }
                MouseArea { anchors.fill: parent; onClicked: root.selectIndex(modelData.idx); onDoubleClicked: root.applySelected() }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Rectangle {
              width: 90; height: Style.spacing.controlHeight
              radius: Style.cornerRadius
              color: Color.background
              border.color: Color.imagePicker.unselectedBorder
              border.width: 1
              Text { anchors.centerIn: parent; text: "Cancel"; color: Color.foreground; font.pixelSize: Style.font.body }
              MouseArea { anchors.fill: parent; onClicked: root.close() }
            }
            Rectangle {
              width: 110; height: Style.spacing.controlHeight
              radius: Style.cornerRadius
              color: Color.accent
              Text { anchors.centerIn: parent; text: "Apply to Boot"; color: Color.background; font.pixelSize: Style.font.body; font.weight: Font.DemiBold }
              MouseArea { anchors.fill: parent; onClicked: root.applySelected() }
            }
          }
        }

        // Right: preview + position
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.rowGap

          RowLayout {
            Layout.fillWidth: true
            Text { text: "Preview — video → password"; color: Color.foreground; font.pixelSize: Style.font.subtitle; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            Rectangle {
              width: 112; height: 26; radius: 7
              color: Util.alpha(Color.background,0.55)
              border.color: Color.imagePicker.unselectedBorder
              border.width: 1
              Text { anchors.centerIn: parent; text: "Default positions"; color: Color.foreground; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.resetDefaultPositions() }
            }
          }

          // Aspect-correct screen simulation. All SDDM pixels are converted
          // through preview.displayScale, including drag and resize values.
          Item {
            id: previewFrame
            Layout.fillWidth: true
            Layout.minimumHeight: 270
            Layout.preferredHeight: 270
            Layout.maximumHeight: 270

            Rectangle {
              id: preview
              readonly property real aspect: root.previewRes.width / root.previewRes.height
              readonly property real displayScale: width / root.previewRes.width
              width: Math.min(parent.width, parent.height * aspect)
              height: width / aspect
              anchors.centerIn: parent
              radius: Style.cornerRadius
              color: "#0e0e14"
              clip: true
              border.color: Color.imagePicker.unselectedBorder
              border.width: 1

            // video
            MediaPlayer {
              id: previewPlayer
              videoOutput: previewOut
              audioOutput: AudioOutput { id: previewAudio; muted: !root.audioEnabled || (root.revealMode === "video-end" && root.previewRevealStarted); volume: 0.85 }
              loops: root.revealMode === "video-end" ? 1 : MediaPlayer.Infinite
              onDurationChanged: {
                if (root.revealMode === "video-end" && duration > 0) {
                  previewEndSafety.interval = Math.min(duration, root.maxVideoDuration) + 3000
                  previewEndSafety.restart()
                }
              }
              onPositionChanged: {
                if (position < root.maxVideoDuration) return
                if (root.revealMode === "video-end") root.revealPreview()
                else setPosition(0)
              }
              onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) root.revealPreview()
              onErrorOccurred: { console.warn("preview error", errorString); root.revealPreview() }
            }
            VideoOutput {
              id: previewOut
              anchors.fill: parent
              fillMode: VideoOutput.PreserveAspectCrop
              visible: root.videoReady
            }
            Image {
              id: poster
              anchors.fill: parent
              source: root.fileUrl(root.previewPoster)
              fillMode: Image.PreserveAspectCrop
              visible: !root.videoReady
              asynchronous: true
            }
            Connections {
              target: previewOut.videoSink
              function onVideoFrameChanged() {
                if (root.previewVideo && !root.videoReady) {
                  root.videoReady = true
                  if (root.revealMode === "first-frame") root.revealPreview()
                }
              }
            }
            // scrim for legibility - mirrors SDDM Main.qml
            Rectangle { anchors.fill: parent; color: "#0e0e14"; opacity: root.previewLogoRevealed ? 0.18 : 0.0; Behavior on opacity { NumberAnimation{duration:root.transitionDuration}} }
            MouseArea {
              anchors.fill: parent
              enabled: root.revealMode === "video-end" && !root.previewPasswordRevealed
              onClicked: root.revealPreview()
            }

            // Logo has its own position and drag target.
            Item {
              id: logoWrap
              width: root.logoSize.width * preview.displayScale
              height: root.logoSize.height * preview.displayScale
              x: preview.width/2 - width/2 + root.logoPos.offsetX * preview.displayScale
              y: preview.height/2 - height/2 + root.logoPos.offsetY * preview.displayScale
              visible: root.showLogo
              opacity: root.previewLogoRevealed ? (root.endAlignMode ? 0.55 : 1) : 0
              Behavior on opacity { NumberAnimation { duration: root.revealMode === "video-end" ? 80 : root.transitionDuration; easing.type: Easing.OutCubic } }
              Behavior on x { enabled: !root.logoDragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
              Behavior on y { enabled: !root.logoDragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
              Behavior on width { enabled: !root.logoResizing; NumberAnimation { duration: 120 } }
              Behavior on height { enabled: !root.logoResizing; NumberAnimation { duration: 120 } }

              Image {
                anchors.fill: parent
                source: root.fileUrl(root.themeDir + "/logo.png")
                fillMode: Image.PreserveAspectFit
                opacity: 0.95
                asynchronous: true
              }
              MouseArea {
                anchors.fill: parent
                anchors.rightMargin: 14
                anchors.bottomMargin: 14
                enabled: root.previewLogoRevealed
                drag.target: logoWrap
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 4
                drag.maximumX: preview.width - logoWrap.width - 4
                drag.minimumY: 4
                drag.maximumY: preview.height - logoWrap.height - 4
                drag.smoothed: false
                cursorShape: Qt.SizeAllCursor
                onPressed: root.logoDragging = true
                onReleased: {
                  root.logoDragging = false
                  root.updateLogoPos(Math.round((logoWrap.x + logoWrap.width/2 - preview.width/2) / preview.displayScale), Math.round((logoWrap.y + logoWrap.height/2 - preview.height/2) / preview.displayScale))
                }
              }
              Rectangle {
                width: 16; height: 16; radius: 4
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Util.alpha(Color.accent, root.logoResizing ? 0.95 : 0.75)
                border.color: Color.background
                border.width: 1
                Text { anchors.centerIn: parent; text: "⤡"; color: Color.background; font.pixelSize: 9 }
                MouseArea {
                  anchors.fill: parent
                  enabled: root.previewLogoRevealed
                  cursorShape: Qt.SizeFDiagCursor
                  onPressed: root.logoResizing = true
                  onReleased: root.logoResizing = false
                  onPositionChanged: function(mouse) {
                    if (!root.logoResizing) return
                    root.updateLogoSize(root.logoSize.width + (mouse.x - width/2) / preview.displayScale, root.logoSize.height + (mouse.y - height/2) / preview.displayScale)
                  }
                }
              }
            }

            // password overlay - positionable + resizable
            Item {
              id: passWrap
              width: root.fieldSize.width * preview.displayScale
              height: root.fieldSize.height * preview.displayScale
              // Omarchy's natural password row is 335x48.
              readonly property real s: Math.min(root.fieldSize.width / 335.0, root.fieldSize.height / 48.0) * preview.displayScale
              // anchor logic — custom uses free x/y, others use anchors (x/y ignored)
              anchors.centerIn: root.pos.anchor === "center" ? parent : undefined
              anchors.horizontalCenter: root.pos.anchor !== "center" && root.pos.anchor !== "custom" ? parent.horizontalCenter : undefined
              anchors.top: root.pos.anchor.indexOf("top") !== -1 ? parent.top : undefined
              anchors.bottom: root.pos.anchor.indexOf("bottom") !== -1 ? parent.bottom : undefined
              anchors.topMargin: root.pos.anchor.indexOf("top") !== -1 ? (40 + root.pos.offsetY) * preview.displayScale : 0
              anchors.bottomMargin: root.pos.anchor.indexOf("bottom") !== -1 ? (40 - root.pos.offsetY) * preview.displayScale : 0
              x: root.pos.anchor === "custom" ? parent.width/2 - width/2 + root.pos.offsetX * preview.displayScale : 0
              y: root.pos.anchor === "custom" ? parent.height/2 - height/2 + root.pos.offsetY * preview.displayScale : 0
              opacity: root.previewPasswordRevealed ? 1 : 0
              Behavior on opacity { NumberAnimation{duration:root.transitionDuration; easing.type:Easing.OutCubic} }
              Behavior on x { enabled: !root.dragging && !root.resizing; NumberAnimation{duration:120; easing.type: Easing.OutCubic} }
              Behavior on y { enabled: !root.dragging && !root.resizing; NumberAnimation{duration:120; easing.type: Easing.OutCubic} }
              Behavior on width { enabled: !root.resizing; NumberAnimation{duration:140} }
              Behavior on height { enabled: !root.resizing; NumberAnimation{duration:140} }

              // WYSIWYG password row - independent from the logo.
              Row {
                anchors.centerIn: parent
                scale: passWrap.s
                spacing: 15
                Image {
                  source: root.fileUrl(root.themeDir + "/lock.png")
                  width: 34; height: 38; fillMode: Image.PreserveAspectFit
                  asynchronous: true
                }
                Item {
                  width: 286
                  height: 48
                  Image {
                    source: root.fileUrl(root.themeDir + "/entry.png")
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                  }
                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Repeater {
                      model: 8
                      delegate: Image {
                        source: root.fileUrl(root.themeDir + "/bullet.png")
                        width: 7; height: 7
                        asynchronous: true
                      }
                    }
                  }
                }
              }
              MouseArea {
                id: dragArea
                anchors.fill: parent
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                drag.target: root.pos.anchor === "custom" ? passWrap : undefined
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 4
                drag.maximumX: preview.width - passWrap.width - 4
                drag.minimumY: 4
                drag.maximumY: preview.height - passWrap.height - 4
                drag.smoothed: false
                cursorShape: root.pos.anchor==="custom" ? Qt.SizeAllCursor : Qt.ArrowCursor
                enabled: root.pos.anchor==="custom" && root.previewPasswordRevealed
                onPressed: root.dragging = true
                onReleased: {
                  root.dragging = false
                  if (root.pos.anchor === "custom") {
                    var cx = preview.width/2
                    var cy = preview.height/2
                    root.updatePos("custom", Math.round((passWrap.x + passWrap.width/2 - cx) / preview.displayScale), Math.round((passWrap.y + passWrap.height/2 - cy) / preview.displayScale))
                  }
                }
                // no live pos updates — avoids stutter; only final pos on release
              }

              // resize handle (bottom-right corner)
              Rectangle {
                id: resizeHandle
                width: 18; height: 18
                radius: 4
                color: Util.alpha(Color.accent, root.resizing ? 0.95 : 0.75)
                border.color: Color.background
                border.width: 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 2
                anchors.bottomMargin: 2
                visible: true
                Text { anchors.centerIn: parent; text: "⤡"; color: Color.background; font.pixelSize: 10; rotation: 0 }
                MouseArea {
                  anchors.fill: parent
                  enabled: root.previewPasswordRevealed
                  cursorShape: Qt.SizeFDiagCursor
                  onPressed: root.resizing = true
                  onReleased: root.resizing = false
                  onPositionChanged: function(mouse) {
                    if (!root.resizing) return
                    var newW = Math.max(200, Math.min(1600, root.fieldSize.width + (mouse.x - width/2) / preview.displayScale))
                    var newH = Math.max(40, Math.min(320, root.fieldSize.height + (mouse.y - height/2) / preview.displayScale))
                    root.updateFieldSize(Math.round(newW), Math.round(newH))
                  }
                  // also support drag
                  drag.target: resizeHandle
                  drag.axis: Drag.XAndYAxis
                }
              }
            }

            Text {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.margins: 8
              text: root.videoReady ? "● LIVE" : "poster"
              color: root.videoReady ? "#ff5a5a" : Color.foreground
              opacity: 0.8
              font.pixelSize: Style.font.caption
              style: Text.Outline
              styleColor: Util.alpha(Color.background, 0.8)
            }

            // guides + click-to-place surface (behind password, in front of video)
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              // subtle center guides when near center/custom
              Rectangle { width: 1; height: parent.height; x: parent.width/2; color: Util.alpha(Color.accent, root.pos.anchor==="center" || (root.pos.anchor==="custom" && Math.abs(root.pos.offsetX)<8 && Math.abs(root.pos.offsetY)<8) ? 0.18 : 0); visible: root.pos.anchor==="center" || root.pos.anchor==="custom" }
              Rectangle { height: 1; width: parent.width; y: parent.height/2; color: Util.alpha(Color.accent, root.pos.anchor==="center" || (root.pos.anchor==="custom" && Math.abs(root.pos.offsetX)<8 && Math.abs(root.pos.offsetY)<8) ? 0.18 : 0); visible: root.pos.anchor==="center" || root.pos.anchor==="custom" }
            }

            // hint when custom - drag only
            Rectangle {
              visible: root.pos.anchor==="custom"
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottomMargin: 8
              width: hintText.width + 16; height: 20; radius: 10
              color: Util.alpha(Color.background,0.72)
              border.color: Util.alpha(Color.accent,0.45)
              border.width: 1
              Text { id: hintText; anchors.centerIn: parent; text: "Drag the password box to place"; color: Color.foreground; font.pixelSize: 10; opacity: 0.85 }
            }
          }
          }

          // Transition controls mirror the SDDM state machine.
          Rectangle {
            Layout.fillWidth: true
            Layout.minimumHeight: 64
            Layout.preferredHeight: 64
            Layout.maximumHeight: 64
            radius: 9
            color: Util.alpha(Color.background, 0.32)
            border.color: Util.alpha(Color.imagePicker.unselectedBorder, 0.7)
            border.width: 1
            ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 4
            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              Text { text: "TRANSITION"; color: Color.foreground; font.pixelSize: 9; font.weight: Font.DemiBold; opacity: 0.5 }
              Repeater {
                model: [{label:"Immediate", mode:"first-frame"}, {label:"After video", mode:"video-end"}]
                delegate: Rectangle {
                  required property var modelData
                  width: 92; height: 26; radius: 7
                  color: root.revealMode === modelData.mode ? Color.accent : Util.alpha(Color.background,0.5)
                  border.color: root.revealMode === modelData.mode ? Color.accent : Color.imagePicker.unselectedBorder
                  border.width: 1
                  Text { anchors.centerIn: parent; text: modelData.label; color: root.revealMode === modelData.mode ? Color.background : Color.foreground; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
                  MouseArea { anchors.fill: parent; onClicked: { root.revealMode = modelData.mode; root.replayTransition() } }
                }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: previewPlayer.duration > root.maxVideoDuration ? "10s cap" : (previewPlayer.duration > 0 ? Math.round(previewPlayer.duration/100)/10 + "s" : "")
                color: previewPlayer.duration > root.maxVideoDuration ? Color.accent : Color.foreground
                opacity: 0.65
                font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: 58; height: 26; radius: 7
                color: Util.alpha(Color.background,0.5); border.color: Color.imagePicker.unselectedBorder; border.width: 1
                Text { anchors.centerIn: parent; text: "Replay"; color: Color.foreground; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; onClicked: root.replayTransition() }
              }
              Rectangle {
                width: 66; height: 26; radius: 7
                color: root.endAlignMode ? Color.accent : Util.alpha(Color.background,0.5); border.color: root.endAlignMode ? Color.accent : Color.imagePicker.unselectedBorder; border.width: 1
                Text { anchors.centerIn: parent; text: "End align"; color: root.endAlignMode ? Color.background : Color.foreground; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; onClicked: root.alignEndFrame() }
              }
            }
            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              Text { text: "Fade"; color: Color.foreground; opacity: 0.55; font.pixelSize: Style.font.caption }
              Rectangle {
                width: 86; height: 24; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                RowLayout { anchors.fill: parent; spacing: 0
                  Rectangle { width: 20; height: 24; color: "transparent"; Text { anchors.centerIn: parent; text: "−"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.transitionDuration=Math.max(100,root.transitionDuration-100) } }
                  Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.transitionDuration + "ms"; color: Color.foreground; font.pixelSize: 10 }
                  Rectangle { width: 20; height: 24; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.transitionDuration=Math.min(3000,root.transitionDuration+100) } }
                }
              }
              Text { text: "Password delay"; color: Color.foreground; opacity: 0.55; font.pixelSize: Style.font.caption }
              Rectangle {
                width: 86; height: 24; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                RowLayout { anchors.fill: parent; spacing: 0
                  Rectangle { width: 20; height: 24; color: "transparent"; Text { anchors.centerIn: parent; text: "−"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.passwordDelay=Math.max(0,root.passwordDelay-50) } }
                  Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.passwordDelay + "ms"; color: Color.foreground; font.pixelSize: 10 }
                  Rectangle { width: 20; height: 24; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.passwordDelay=Math.min(3000,root.passwordDelay+50) } }
                }
              }
              Item { Layout.fillWidth: true }
              Text { text: root.endAlignMode ? "55% overlay: match the final text edges" : (root.revealMode === "video-end" ? "Click preview to reveal" : "Reveal on first frame"); color: Color.foreground; opacity: 0.4; font.pixelSize: 9 }
            }
            }
          }

          // Compact, paired control cards keep related settings together.
          RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 250
            Layout.preferredHeight: 250
            Layout.maximumHeight: 250
            spacing: 8

            Rectangle {
              Layout.fillWidth: true; Layout.fillHeight: true; radius: 9
              color: Util.alpha(Color.background,0.32); border.color: Util.alpha(Color.imagePicker.unselectedBorder,0.7); border.width: 1
              ColumnLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 7
                RowLayout {
                  Layout.fillWidth: true
                  Text { text: "LOGO"; color: Color.foreground; font.pixelSize: 9; font.weight: Font.DemiBold; opacity: 0.5 }
                  Item { Layout.fillWidth: true }
                  Text { text: root.showLogo ? "VISIBLE" : "HIDDEN"; color: Color.foreground; font.pixelSize: 9; opacity: 0.45 }
                  Rectangle {
                    Layout.preferredWidth: 42; Layout.preferredHeight: 22; radius: 11
                    color: root.showLogo ? Color.accent : Util.alpha(Color.background,0.65); border.color: Color.imagePicker.unselectedBorder; border.width: 1
                    Rectangle { width: 14; height: 14; radius: 7; color: Color.background; anchors.verticalCenter: parent.verticalCenter; x: root.showLogo ? parent.width-width-4 : 4; Behavior on x { NumberAnimation { duration: 140 } } }
                    MouseArea { anchors.fill: parent; onClicked: root.updateShowLogo(!root.showLogo) }
                  }
                }
                RowLayout {
                  Layout.fillWidth: true
                  Text { text: root.previewRes.width + "×" + root.previewRes.height; color: Color.foreground; font.pixelSize: Style.font.caption; opacity: 0.55 }
                  Item { Layout.fillWidth: true }
                  Rectangle {
                    Layout.preferredWidth: 82; Layout.preferredHeight: 24; radius: 6
                    color: Util.alpha(Color.background,0.55); border.color: Color.imagePicker.unselectedBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "All defaults"; color: Color.foreground; font.pixelSize: Style.font.caption }
                    MouseArea { anchors.fill: parent; onClicked: { root.resetDefaultSizes(); root.updateLogoPos(0,-44) } }
                  }
                }
                Text { text: "SIZE"; color: Color.foreground; font.pixelSize: 9; opacity: 0.4 }
                RowLayout {
                  Layout.fillWidth: true; spacing: 6
                  Text { text: "W"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                  Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                    RowLayout { anchors.fill: parent; spacing: 0
                      Rectangle { Layout.preferredWidth: 22; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "−"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateLogoSize(root.logoSize.width-20,root.logoSize.height) } }
                      Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Math.round(root.logoSize.width); color: Color.foreground; font.pixelSize: 10 }
                      Rectangle { Layout.preferredWidth: 22; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateLogoSize(root.logoSize.width+20,root.logoSize.height) } }
                    }
                  }
                  Text { text: "H"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                  Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                    RowLayout { anchors.fill: parent; spacing: 0
                      Rectangle { Layout.preferredWidth: 22; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "−"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateLogoSize(root.logoSize.width,root.logoSize.height-5) } }
                      Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Math.round(root.logoSize.height); color: Color.foreground; font.pixelSize: 10 }
                      Rectangle { Layout.preferredWidth: 22; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateLogoSize(root.logoSize.width,root.logoSize.height+5) } }
                    }
                  }
                }
                RowLayout {
                  Layout.fillWidth: true
                  Text { text: "POSITION"; color: Color.foreground; font.pixelSize: 9; opacity: 0.4 }
                  Item { Layout.fillWidth: true }
                  Text { text: root.logoPos.offsetX + ", " + root.logoPos.offsetY; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                  Rectangle { Layout.preferredWidth: 48; Layout.preferredHeight: 22; radius: 6; color: Util.alpha(Color.background,0.55); border.color: Color.imagePicker.unselectedBorder; border.width: 1; Text { anchors.centerIn: parent; text: "Reset"; color: Color.foreground; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.updateLogoPos(0,-44) } }
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true; Layout.fillHeight: true; radius: 9
              color: Util.alpha(Color.background,0.32); border.color: Util.alpha(Color.imagePicker.unselectedBorder,0.7); border.width: 1
              RowLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 9
                ColumnLayout {
                  Layout.fillWidth: true; spacing: 7
                  RowLayout {
                    Layout.fillWidth: true
                    Text { text: "PASSWORD"; color: Color.foreground; font.pixelSize: 9; font.weight: Font.DemiBold; opacity: 0.5 }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                      Layout.preferredWidth: 58; Layout.preferredHeight: 20; radius: 5
                      color: root.linkPasswordToLogo ? Util.alpha(Color.accent,0.22) : "transparent"; border.color: root.linkPasswordToLogo ? Color.accent : Color.imagePicker.unselectedBorder; border.width: 1
                      Text { anchors.centerIn: parent; text: root.linkPasswordToLogo ? "LINKED" : (root.pos.anchor === "custom" ? "FREE" : root.pos.anchor.toUpperCase()); color: Color.foreground; font.pixelSize: 8; opacity: 0.8 }
                      MouseArea { anchors.fill: parent; onClicked: root.setPasswordLink(!root.linkPasswordToLogo) }
                    }
                  }
                  Text { text: "SIZE"; color: Color.foreground; font.pixelSize: 9; opacity: 0.4 }
                  RowLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "W"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                    Rectangle {
                      Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                      RowLayout { anchors.fill: parent; spacing: 0
                        Rectangle { Layout.preferredWidth: 20; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "−"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateFieldSize(root.fieldSize.width-50,root.fieldSize.height) } }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.fieldSize.width; color: Color.foreground; font.pixelSize: 10 }
                        Rectangle { Layout.preferredWidth: 20; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateFieldSize(root.fieldSize.width+50,root.fieldSize.height) } }
                      }
                    }
                    Text { text: "H"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                    Rectangle {
                      Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                      RowLayout { anchors.fill: parent; spacing: 0
                        Rectangle { Layout.preferredWidth: 20; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "−"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateFieldSize(root.fieldSize.width,root.fieldSize.height-10) } }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.fieldSize.height; color: Color.foreground; font.pixelSize: 10 }
                        Rectangle { Layout.preferredWidth: 20; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground } MouseArea { anchors.fill: parent; onClicked: root.updateFieldSize(root.fieldSize.width,root.fieldSize.height+10) } }
                      }
                    }
                  }
                  RowLayout {
                    Layout.fillWidth: true
                    Text { text: "OFFSET"; color: Color.foreground; font.pixelSize: 9; opacity: 0.4 }
                    Item { Layout.fillWidth: true }
                    Text { text: "GAP"; color: Color.foreground; font.pixelSize: 8; opacity: 0.4 }
                    Rectangle { Layout.preferredWidth: 56; Layout.preferredHeight: 20; radius: 5; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
                      RowLayout { anchors.fill: parent; spacing: 0
                        Rectangle { Layout.preferredWidth: 17; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "-"; color: Color.foreground; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.updatePasswordGap(root.passwordGap-5) } }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.passwordGap; color: Color.foreground; font.pixelSize: 9 }
                        Rectangle { Layout.preferredWidth: 17; Layout.fillHeight: true; color: "transparent"; Text { anchors.centerIn: parent; text: "+"; color: Color.foreground; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.updatePasswordGap(root.passwordGap+5) } }
                      }
                    }
                  }
                  RowLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "X"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1; TextInput { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; text: String(root.pos.offsetX); color: Color.foreground; font.pixelSize: 10; onAccepted: root.updatePos(root.pos.anchor,parseInt(text)||0,root.pos.offsetY) } }
                    Text { text: "Y"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6; color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1; TextInput { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; text: String(root.pos.offsetY); color: Color.foreground; font.pixelSize: 10; onAccepted: root.updatePos(root.pos.anchor,root.pos.offsetX,parseInt(text)||0) } }
                  }
                  Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 25; radius: 6
                    color: root.pos.anchor === "custom" ? Color.accent : Util.alpha(Color.background,0.55); border.color: root.pos.anchor === "custom" ? Color.accent : Color.imagePicker.unselectedBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: root.pos.anchor === "custom" ? "Drag enabled" : "Enable free drag"; color: root.pos.anchor === "custom" ? Color.background : Color.foreground; font.pixelSize: 10; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: root.updatePos("custom",root.pos.offsetX,root.pos.offsetY) }
                  }
                }
                Rectangle {
                  Layout.preferredWidth: 74; Layout.preferredHeight: 126; radius: 8
                  color: Util.alpha(Color.background,0.45); border.color: Color.imagePicker.unselectedBorder; border.width: 1
                  GridLayout {
                    anchors.fill: parent; anchors.margins: 5; columns: 3; rows: 3; columnSpacing: 3; rowSpacing: 3
                    Repeater {
                      model: ["topLeft","top","topRight","centerLeft","center","centerRight","bottomLeft","bottom","bottomRight"]
                      delegate: Rectangle {
                        required property string modelData
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                        color: root.pos.anchor === modelData ? Color.accent : Util.alpha(Color.background,0.65)
                        border.color: root.pos.anchor === modelData ? Color.accent : Util.alpha(Color.foreground,0.12); border.width: 1
                        Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: root.pos.anchor === modelData ? Color.background : Util.alpha(Color.foreground,0.5) }
                        MouseArea { anchors.fill: parent; onClicked: root.updatePos(modelData,0,0) }
                      }
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true; Layout.minimumHeight: 38; Layout.preferredHeight: 38; Layout.maximumHeight: 38; radius: 9
            color: Util.alpha(Color.background,0.32); border.color: Util.alpha(Color.imagePicker.unselectedBorder,0.7); border.width: 1
            RowLayout {
              anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
              Text { text: "AUDIO"; color: Color.foreground; font.pixelSize: 9; font.weight: Font.DemiBold; opacity: 0.5 }
              Text { text: root.previewHasAudio ? "Video audio is available" : "No audio track in this video"; color: Color.foreground; font.pixelSize: Style.font.caption; opacity: 0.45 }
              Item { Layout.fillWidth: true }
              Text { text: root.previewHasAudio ? (root.audioEnabled ? "ON" : "OFF") : "UNAVAILABLE"; color: Color.foreground; font.pixelSize: 9; opacity: 0.5 }
              Rectangle {
                Layout.preferredWidth: 42; Layout.preferredHeight: 22; radius: 11
                color: root.audioEnabled && root.previewHasAudio ? Color.accent : Util.alpha(Color.background,0.65); border.color: Color.imagePicker.unselectedBorder; border.width: 1; opacity: root.previewHasAudio ? 1 : 0.4
                Rectangle { width: 14; height: 14; radius: 7; color: Color.background; anchors.verticalCenter: parent.verticalCenter; x: root.audioEnabled ? parent.width-width-4 : 4; Behavior on x { NumberAnimation { duration: 140 } } }
                MouseArea { anchors.fill: parent; enabled: root.previewHasAudio; onClicked: root.audioEnabled = !root.audioEnabled }
              }
            }
          }
        }
      }
    }
  }
}
