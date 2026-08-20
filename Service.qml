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

  function loadConfig() {
    if (!configFile.text()) return
    try {
      var cfg = JSON.parse(configFile.text())
      if (cfg.video) videoPath = String(cfg.video)
      if (cfg.poster) posterPath = String(cfg.poster)
      if (cfg.pos && typeof cfg.pos === "object") pos = cfg.pos
    } catch (e) {
      console.warn("live-boot config parse failed", e)
    }
  }

  function saveConfig() {
    var payload = { video: videoPath, poster: posterPath, pos: pos }
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
    function status(): string {
      return JSON.stringify({ video: root.videoPath, poster: root.posterPath, pos: root.pos })
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
