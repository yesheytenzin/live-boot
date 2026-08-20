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
  property var pos: ({ anchor: "custom", offsetX: 0, offsetY: 114 })
  property bool audioEnabled: false
  property bool showLogo: true
  property var logoPos: ({ offsetX: 0, offsetY: -44 })
  property var logoSize: ({ width: 800, height: 188 })
  property var previewRes: ({ width: 1920, height: 1080 })
  property var fieldSize: ({ width: 335, height: 48 })
  property bool sizesCustomized: false
  property bool positionsCustomized: false
  property string revealMode: "first-frame"
  property int transitionDuration: 700
  property int passwordDelay: 250
  property bool linkPasswordToLogo: true
  property int passwordGap: 40

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
      if (cfg.logoPos && typeof cfg.logoPos === "object") logoPos = { offsetX: parseInt(cfg.logoPos.offsetX)||0, offsetY: parseInt(cfg.logoPos.offsetY)||0 }
      else logoPos = { offsetX: 0, offsetY: -44 }
      if (cfg.logoSize && typeof cfg.logoSize === "object") logoSize = { width: Math.max(80, Math.min(1200, parseInt(cfg.logoSize.width)||800)), height: Math.max(20, Math.min(400, parseInt(cfg.logoSize.height)||188)) }
      if (cfg.previewRes && typeof cfg.previewRes === "object") previewRes = { width: parseInt(cfg.previewRes.width)||1920, height: parseInt(cfg.previewRes.height)||1080 }
      if (cfg.revealMode === "video-end" || cfg.revealMode === "first-frame") revealMode = cfg.revealMode
      if (cfg.transitionDuration !== undefined) transitionDuration = Math.max(100, Math.min(3000, parseInt(cfg.transitionDuration)||700))
      if (cfg.passwordDelay !== undefined) passwordDelay = Math.max(0, Math.min(3000, parseInt(cfg.passwordDelay)||0))
      linkPasswordToLogo = cfg.linkPasswordToLogo !== false
      if (cfg.passwordGap !== undefined) passwordGap = Math.max(0, Math.min(300, parseInt(cfg.passwordGap)||0))
      if (cfg.fieldSize && typeof cfg.fieldSize === "object") fieldSize = { width: Math.max(200, Math.min(1600, parseInt(cfg.fieldSize.width)||335)), height: Math.max(40, Math.min(320, parseInt(cfg.fieldSize.height)||48)) }
      else if (cfg.size && typeof cfg.size === "object") fieldSize = { width: Math.max(200, Math.min(1600, parseInt(cfg.size.width)||335)), height: Math.max(40, Math.min(320, parseInt(cfg.size.height)||48)) }
      sizesCustomized = cfg.sizesCustomized === true
      positionsCustomized = cfg.positionsCustomized === true
    } catch (e) {
      console.warn("live-boot config parse failed", e)
    }
  }

  function saveConfig() {
    var payload = { video: videoPath, poster: posterPath, pos: pos, audioEnabled: audioEnabled, fieldSize: fieldSize, showLogo: showLogo, logoPos: logoPos, logoSize: logoSize, sizesCustomized: sizesCustomized, positionsCustomized: positionsCustomized, previewRes: previewRes, revealMode: revealMode, transitionDuration: transitionDuration, passwordDelay: passwordDelay, linkPasswordToLogo: linkPasswordToLogo, passwordGap: passwordGap }
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
    onExited: function(exitCode, exitStatus) {
      var message = exitCode === 0 ? "Live Boot applied to SDDM" : "Live Boot was not applied; authorization was cancelled or failed"
      Quickshell.execDetached(["omarchy-notification-send", message, "-t", "4000"])
    }
  }

  Process {
    id: wireMenuProc
    command: [root.script, "--wire-menu"]
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
    function applySettings(payloadJson: string): void {
      var cfg
      try { cfg = JSON.parse(payloadJson) } catch (e) { console.warn("live-boot apply payload invalid", e); return }
      cfg.pos = cfg.pos || {}
      cfg.fieldSize = cfg.fieldSize || {}
      cfg.logoPos = cfg.logoPos || {}
      cfg.logoSize = cfg.logoSize || {}
      cfg.previewRes = cfg.previewRes || {}
      root.videoPath = String(cfg.video || "").trim()
      root.posterPath = String(cfg.poster || "").trim()
      root.audioEnabled = cfg.audioEnabled === true
      root.pos = { anchor: String(cfg.pos.anchor || "center"), offsetX: parseInt(cfg.pos.offsetX,10)||0, offsetY: parseInt(cfg.pos.offsetY,10)||0 }
      root.fieldSize = { width: Math.max(200, Math.min(1600, parseInt(cfg.fieldSize.width,10)||335)), height: Math.max(40, Math.min(320, parseInt(cfg.fieldSize.height,10)||48)) }
      root.showLogo = cfg.showLogo === true
      root.logoPos = { offsetX: parseInt(cfg.logoPos.offsetX,10)||0, offsetY: parseInt(cfg.logoPos.offsetY,10)||0 }
      root.logoSize = { width: Math.max(80, Math.min(1200, parseInt(cfg.logoSize.width,10)||800)), height: Math.max(20, Math.min(400, parseInt(cfg.logoSize.height,10)||188)) }
      root.sizesCustomized = cfg.sizesCustomized === true
      root.positionsCustomized = cfg.positionsCustomized === true
      root.previewRes = { width: Math.max(640, Math.min(7680, parseInt(cfg.previewRes.width,10)||1920)), height: Math.max(480, Math.min(4320, parseInt(cfg.previewRes.height,10)||1080)) }
      root.revealMode = cfg.revealMode === "video-end" ? "video-end" : "first-frame"
      root.transitionDuration = Math.max(100, Math.min(3000, parseInt(cfg.transitionDuration,10)||700))
      root.passwordDelay = Math.max(0, Math.min(3000, parseInt(cfg.passwordDelay,10)||0))
      root.linkPasswordToLogo = cfg.linkPasswordToLogo !== false
      root.passwordGap = Math.max(0, Math.min(300, parseInt(cfg.passwordGap,10)||0))
      root.saveConfig()
      root.syncSddm()
    }
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
      root.positionsCustomized = true
      root.saveConfig()
      root.syncSddm()
    }
    function setFieldSize(width: string, height: string): void {
      var w = Math.max(200, Math.min(1600, parseInt(width,10)||335))
      var h = Math.max(40, Math.min(320, parseInt(height,10)||48))
      root.fieldSize = { width: w, height: h }
      root.saveConfig()
      root.syncSddm()
    }
    function setShowLogo(enabled: string): void {
      root.showLogo = String(enabled) === "true" || String(enabled) === "1"
      root.saveConfig()
      root.syncSddm()
    }
    function setLogoPosition(offsetX: string, offsetY: string): void {
      root.logoPos = { offsetX: parseInt(offsetX,10)||0, offsetY: parseInt(offsetY,10)||0 }
      root.positionsCustomized = true
      root.saveConfig()
      root.syncSddm()
    }
    function setLogoSize(width: string, height: string): void {
      root.logoSize = { width: Math.max(80, Math.min(1200, parseInt(width,10)||800)), height: Math.max(20, Math.min(400, parseInt(height,10)||188)) }
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
    function setTransition(mode: string, duration: string, delay: string): void {
      root.revealMode = String(mode) === "video-end" ? "video-end" : "first-frame"
      root.transitionDuration = Math.max(100, Math.min(3000, parseInt(duration,10)||700))
      root.passwordDelay = Math.max(0, Math.min(3000, parseInt(delay,10)||0))
      root.saveConfig()
      root.syncSddm()
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
      return JSON.stringify({ video: root.videoPath, poster: root.posterPath, pos: root.pos, audioEnabled: root.audioEnabled, fieldSize: root.fieldSize, showLogo: root.showLogo, logoPos: root.logoPos, logoSize: root.logoSize, sizesCustomized: root.sizesCustomized, positionsCustomized: root.positionsCustomized, previewRes: root.previewRes, revealMode: root.revealMode, transitionDuration: root.transitionDuration, passwordDelay: root.passwordDelay, linkPasswordToLogo: root.linkPasswordToLogo, passwordGap: root.passwordGap })
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

  Component.onCompleted: wireMenuProc.running = true

  Component.onDestruction: Quickshell.execDetached([root.script, "--unwire-menu"])
}
