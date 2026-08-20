pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string home: Quickshell.env("HOME")
  readonly property string script: home + "/.config/omarchy/plugins/live-boot/live-boot.sh"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/live-boot"
  readonly property string configPath: stateDir + "/config.json"

  property string videoPath: ""
  property string posterPath: ""
  property var pos: ({ anchor: "center", offsetX: 0, offsetY: 0 })
  property bool audioEnabled: false
  property bool showLogo: true
  property var previewRes: ({ width: 1920, height: 1080 })
  property var fieldSize: ({ width: 340, height: 56 })

  function loadConfig() {
    if (!configFile.text()) return
    try {
      var cfg = JSON.parse(configFile.text())
      if (cfg.video) videoPath = String(cfg.video)
      if (cfg.poster) posterPath = String(cfg.poster)
      if (cfg.pos && typeof cfg.pos === "object") pos = cfg.pos
      if (typeof cfg.audioEnabled === "boolean") audioEnabled = cfg.audioEnabled
      else if (typeof cfg.audio === "boolean") audioEnabled = cfg.audio
      if (typeof cfg.showLogo === "boolean") showLogo = cfg.showLogo
      if (cfg.previewRes && typeof cfg.previewRes === "object") previewRes = { width: parseInt(cfg.previewRes.width)||1920, height: parseInt(cfg.previewRes.height)||1080 }
      if (cfg.fieldSize && typeof cfg.fieldSize === "object") fieldSize = { width: Math.max(200, Math.min(600, parseInt(cfg.fieldSize.width)||340)), height: Math.max(40, Math.min(120, parseInt(cfg.fieldSize.height)||56)) }
      else if (cfg.size && typeof cfg.size === "object") fieldSize = { width: Math.max(200, Math.min(600, parseInt(cfg.size.width)||340)), height: Math.max(40, Math.min(120, parseInt(cfg.size.height)||56)) }
    } catch (e) {
      console.warn("live-boot config parse failed", e)
    }
  }

  function saveConfig() {
    var payload = { video: videoPath, poster: posterPath, pos: pos, audioEnabled: audioEnabled, fieldSize: fieldSize, showLogo: showLogo, previewRes: previewRes }
    configFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function openSelector() {
    if (!pickerProc.running) pickerProc.running = true
  }

  function syncSddm() {
    if (!syncProc.running) syncProc.running = true
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig()
    onLoadFailed: {}
    onFileChanged: reload()
  }

  Process {
    id: pickerProc
    command: [root.script]
  }

  Process {
    id: syncProc
    command: [root.script, "--sync-sddm"]
  }

  Process {
    id: wireMenuProc
    command: [root.script, "--wire-menu"]
  }

  Process {
    id: resumeProc
    command: [root.script, "--resume"]
  }

  Timer {
    id: changeCheck
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      if (!changeCheckProc.running) changeCheckProc.running = true
    }
  }

  Process {
    id: changeCheckProc
    command: [root.script, "--check-config"]
  }

  IpcHandler {
    target: "live-boot"
    function openSelector(): void { root.openSelector() }
    function sync(): void { root.syncSddm() }
    function setVideo(path: string, poster: string): void {
      root.videoPath = String(path || "").trim()
      root.posterPath = String(poster || "").trim()
      root.saveConfig()
      root.syncSddm()
    }
    function setPosition(anchor: string, offsetX: string, offsetY: string): void {
      var a = String(anchor || "center")
      var x = parseInt(offsetX, 10) || 0
      var y = parseInt(offsetY, 10) || 0
      root.pos = { anchor: a, offsetX: x, offsetY: y }
      root.saveConfig()
      root.syncSddm()
    }
    function setFieldSize(width: string, height: string): void {
      var w = Math.max(200, Math.min(600, parseInt(width,10)||340))
      var h = Math.max(40, Math.min(120, parseInt(height,10)||56))
      root.fieldSize = { width: w, height: h }
      root.saveConfig()
      root.syncSddm()
    }
    function setShowLogo(enabled: string): void {
      root.showLogo = String(enabled) === "true" || String(enabled) === "1"
      root.saveConfig()
      root.syncSddm()
    }
    function setPreviewRes(width: string, height: string): void {
      var w = parseInt(width,10) || 1920
      var h = parseInt(height,10) || 1080
      // 640x480 is SDDM's test-mode coordinate space.
      w = Math.max(640, Math.min(7680, w))
      h = Math.max(480, Math.min(4320, h))
      root.previewRes = { width: w, height: h }
      root.saveConfig()
    }
    function setAudio(enabled: string): void {
      root.audioEnabled = String(enabled) === "true" || String(enabled) === "1"
      root.saveConfig()
      root.syncSddm()
    }
    function setVideoWithAudio(path: string, poster: string, audio: string): void {
      root.videoPath = String(path || "").trim()
      root.posterPath = String(poster || "").trim()
      if (audio !== undefined) root.audioEnabled = String(audio) === "true" || String(audio) === "1"
      root.saveConfig()
      root.syncSddm()
    }
    function status(): string {
      return JSON.stringify({ video: root.videoPath, poster: root.posterPath, pos: root.pos, audioEnabled: root.audioEnabled, fieldSize: root.fieldSize, showLogo: root.showLogo, previewRes: root.previewRes })
    }
    function stop(): void {
      root.videoPath = ""
      root.posterPath = ""
      root.saveConfig()
      if (!clearProc.running) clearProc.running = true
    }
  }

  Process {
    id: clearProc
    command: [root.script, "--clear"]
  }

  Component.onCompleted: {
    wireMenuProc.running = true
    // resume after a tick so shell is ready
    Qt.callLater(function() { resumeProc.running = true })
  }

  Component.onDestruction: Quickshell.execDetached([root.script, "--unwire-menu"])
}
