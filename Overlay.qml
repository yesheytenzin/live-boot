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
  property var pos: ({ anchor: "center", offsetX: 0, offsetY: 0 })
  property bool audioEnabled: false
  property bool previewHasAudio: false
  property string previewVideo: ""
  property string previewPoster: ""
  property bool dragging: false

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
    // load pos/audio from args or file
    if (args.pos && typeof args.pos === "object") pos = args.pos
    else loadPos()
    if (typeof args.audioEnabled === "boolean") audioEnabled = args.audioEnabled
    else if (typeof args.audio === "boolean") audioEnabled = args.audio
    opened = true
    videoReady = false
    previewHasAudio = false
    if (previewVideo) {
      previewPlayer.play()
      audioProbeProc.running = true
    }
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
        if (typeof cfg.audioEnabled === "boolean") root.audioEnabled = cfg.audioEnabled
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
    videoReady = false
    previewHasAudio = false
    previewPlayer.stop()
    previewPlayer.source = fileUrl(previewVideo)
    previewPlayer.play()
    audioProbeProc.running = true
  }

  function applySelected() {
    if (!selectedPath) return
    // poster is thumbnail for now; script will regenerate best frame
    var poster = previewPoster
    var audio = audioEnabled ? "true" : "false"
    // call service IPC via shell - include audio flag
    Quickshell.execDetached(["bash", "-c", "omarchy-shell -q live-boot setVideoWithAudio " + Util.shellQuote(selectedPath) + " " + Util.shellQuote(poster) + " " + Util.shellQuote(audio) + " >/dev/null 2>&1 &"])
    // also persist pos immediately (pos IPC also syncs, but setVideoWithAudio already syncs)
    Quickshell.execDetached(["bash", "-c", "omarchy-shell -q live-boot setPosition " + Util.shellQuote(pos.anchor) + " " + Util.shellQuote(String(pos.offsetX)) + " " + Util.shellQuote(String(pos.offsetY)) + " >/dev/null 2>&1; omarchy-shell -q live-boot setAudio " + Util.shellQuote(audio) + " >/dev/null 2>&1 &"])
    close()
  }

  function updatePos(anchor, ox, oy) {
    pos = { anchor: anchor, offsetX: ox, offsetY: oy }
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
      width: Math.min(parent.width - 40, 1100)
      height: Math.min(parent.height - 40, 680)
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
          Layout.preferredWidth: 360
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
            cellWidth: 170
            cellHeight: 110
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

          Text { text: "Preview — video → password"; color: Color.foreground; font.pixelSize: Style.font.subtitle; font.weight: Font.DemiBold }

          // preview area - simulates SDDM
          Rectangle {
            id: preview
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.cornerRadius
            color: "#0e0e14"
            clip: true
            border.color: Color.imagePicker.unselectedBorder
            border.width: 1

            // video
            MediaPlayer {
              id: previewPlayer
              videoOutput: previewOut
              audioOutput: AudioOutput { id: previewAudio; muted: !root.audioEnabled; volume: 0.85 }
              loops: MediaPlayer.Infinite
              onErrorOccurred: console.warn("preview error", errorString)
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
              function onVideoFrameChanged() { if (root.previewVideo) root.videoReady = true }
            }
            // dim while loading
            Rectangle { anchors.fill: parent; color: "#1a1b26"; opacity: root.videoReady ? 0 : 1; Behavior on opacity { NumberAnimation{duration:400}} }

            // password overlay - positionable
            Item {
              id: passWrap
              width: 340
              height: 56
              // anchor logic
              anchors.centerIn: root.pos.anchor === "center" ? parent : undefined
              anchors.horizontalCenter: root.pos.anchor !== "center" ? parent.horizontalCenter : undefined
              anchors.top: root.pos.anchor.indexOf("top") !== -1 ? parent.top : undefined
              anchors.bottom: root.pos.anchor.indexOf("bottom") !== -1 ? parent.bottom : undefined
              anchors.topMargin: root.pos.anchor.indexOf("top") !== -1 ? 24 + root.pos.offsetY : 0
              anchors.bottomMargin: root.pos.anchor.indexOf("bottom") !== -1 ? 24 - root.pos.offsetY : 0
              x: root.pos.anchor === "custom" ? parent.width/2 - width/2 + root.pos.offsetX : x
              y: root.pos.anchor === "custom" ? parent.height/2 - height/2 + root.pos.offsetY : y
              opacity: root.videoReady ? 1 : 0
              Behavior on opacity { NumberAnimation{duration:600}}
              Behavior on x { NumberAnimation{duration:200}}
              Behavior on y { NumberAnimation{duration:200}}

              // entry bg
              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: Util.alpha(Color.background, 0.88)
                border.color: Color.accent
                border.width: 1.5
              }
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                Text { text: ""; color: Color.foreground; font.pixelSize: 18; font.family: Style.font.family }
                Row {
                  Layout.fillWidth: true
                  spacing: 5
                  Repeater { model: Math.min(8, 8); delegate: Rectangle { width: 7; height: 7; radius: 3.5; color: Color.foreground } }
                }
                Text { text: "• • •"; color: Color.foreground; opacity: 0.5; font.pixelSize: Style.font.bodySmall }
              }

              MouseArea {
                anchors.fill: parent
                drag.target: root.pos.anchor === "custom" ? passWrap : undefined
                drag.axis: Drag.XAndYAxis
                onPressed: root.dragging = true
                onReleased: {
                  root.dragging = false
                  if (root.pos.anchor === "custom") {
                    var cx = parent.width/2
                    var cy = parent.height/2
                    root.updatePos("custom", Math.round(passWrap.x + passWrap.width/2 - cx), Math.round(passWrap.y + passWrap.height/2 - cy))
                  }
                }
                onPositionChanged: if (root.dragging && root.pos.anchor==="custom") root.updatePos("custom", Math.round(passWrap.x + passWrap.width/2 - parent.width/2), Math.round(passWrap.y + passWrap.height/2 - parent.height/2))
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
          }

          // position controls
          Text { text: "Password position"; color: Color.foreground; font.pixelSize: Style.font.bodySmall; opacity: 0.7 }

          GridLayout {
            columns: 3
            rowSpacing: 4
            columnSpacing: 4
            Layout.fillWidth: true

            Repeater {
              model: [
                {label:"↖", a:"topLeft"}, {label:"↑", a:"top"}, {label:"↗", a:"topRight"},
                {label:"←", a:"centerLeft"}, {label:"◉", a:"center"}, {label:"→", a:"centerRight"},
                {label:"↙", a:"bottomLeft"}, {label:"↓", a:"bottom"}, {label:"↘", a:"bottomRight"}
              ]
              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                height: 30
                radius: Style.cornerRadius
                color: root.pos.anchor === modelData.a ? Color.accent : Util.alpha(Color.background, 0.6)
                border.color: Color.imagePicker.unselectedBorder
                border.width: 1
                Text { anchors.centerIn: parent; text: modelData.label; color: root.pos.anchor === modelData.a ? Color.background : Color.foreground; font.pixelSize: Style.font.bodySmall; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; onClicked: root.updatePos(modelData.a, 0, 0) }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "Custom drag:"; color: Color.foreground; font.pixelSize: Style.font.caption; opacity: 0.6 }
            Rectangle {
              Layout.fillWidth: true; height: 28; radius: Style.cornerRadius
              color: root.pos.anchor==="custom" ? Util.alpha(Color.accent,0.15) : Util.alpha(Color.background,0.4)
              border.color: root.pos.anchor==="custom" ? Color.accent : Color.imagePicker.unselectedBorder
              border.width: 1
              Text { anchors.centerIn: parent; text: root.pos.anchor==="custom" ? "drag password box in preview" : "click to enable custom"; color: Color.foreground; opacity: 0.7; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.updatePos("custom", root.pos.offsetX, root.pos.offsetY) }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: "Offset X"; color: Color.foreground; font.pixelSize: Style.font.caption }
            Rectangle {
              Layout.fillWidth: true; height: 28; radius: Style.cornerRadius
              color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
              TextInput { id: ox; anchors.fill: parent; anchors.margins: 6; text: String(root.pos.offsetX); color: Color.foreground; font.pixelSize: Style.font.bodySmall; onAccepted: root.updatePos(root.pos.anchor, parseInt(text)||0, root.pos.offsetY) }
            }
            Text { text: "Y"; color: Color.foreground; font.pixelSize: Style.font.caption }
            Rectangle {
              Layout.fillWidth: true; height: 28; radius: Style.cornerRadius
              color: Color.background; border.color: Color.imagePicker.unselectedBorder; border.width: 1
              TextInput { id: oy; anchors.fill: parent; anchors.margins: 6; text: String(root.pos.offsetY); color: Color.foreground; font.pixelSize: Style.font.bodySmall; onAccepted: root.updatePos(root.pos.anchor, root.pos.offsetX, parseInt(text)||0) }
            }
            Rectangle {
              width: 56; height: 28; radius: Style.cornerRadius; color: Util.alpha(Color.background,0.5); border.color: Color.imagePicker.unselectedBorder; border.width: 1
              Text { anchors.centerIn: parent; text: "↺"; color: Color.foreground }
              MouseArea { anchors.fill: parent; onClicked: root.updatePos(root.pos.anchor, 0, 0) }
            }
          }

          // audio toggle
          RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "Boot sound"; color: Color.foreground; font.pixelSize: Style.font.bodySmall; opacity: 0.7 }
            Item { Layout.fillWidth: true }
            Text {
              text: root.previewHasAudio ? (root.audioEnabled ? "On" : "Off") : "No audio track"
              color: root.previewHasAudio ? Color.foreground : Color.foreground
              opacity: root.previewHasAudio ? 0.9 : 0.4
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              width: 52; height: 26; radius: 13
              color: root.audioEnabled && root.previewHasAudio ? Color.accent : Util.alpha(Color.background,0.6)
              border.color: Color.imagePicker.unselectedBorder
              border.width: 1
              opacity: root.previewHasAudio ? 1 : 0.45
              Rectangle {
                width: 18; height: 18; radius: 9
                color: Color.background
                border.color: Color.imagePicker.unselectedBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                x: root.audioEnabled ? parent.width - width - 4 : 4
                Behavior on x { NumberAnimation{duration:150}}
              }
              MouseArea {
                anchors.fill: parent
                enabled: root.previewHasAudio
                onClicked: root.audioEnabled = !root.audioEnabled
              }
            }
            Text {
              text: "🔊"
              color: Color.foreground
              opacity: root.audioEnabled && root.previewHasAudio ? 0.9 : 0.3
              font.pixelSize: Style.font.body
            }
          }
          Text {
            visible: !root.previewHasAudio && root.previewVideo !== ""
            text: "This video has no audio track — sound will stay silent at boot even if enabled."
            color: Color.foreground
            opacity: 0.5
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }
}
