import QtQuick 2.0
import SddmComponents 2.0
import QtMultimedia

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#0e0e14"

  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property bool videoReady: false
  property string anchor: "{{anchor}}"
  property int offsetX: {{offsetX}}
  property int offsetY: {{offsetY}}
  property int logoOffsetX: {{logoOffsetX}}
  property int logoOffsetY: {{logoOffsetY}}
  property bool audioEnabled: {{audioEnabled}}
  property bool showLogo: {{showLogo}}
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1) return i
    }
    return sessionModel.lastIndex
  }

  Connections {
    target: sddm
    function onLoginFailed() { root.loginFailed = true; password.text = ""; password.focus = true }
    function onLoginSucceeded() { root.loginFailed = false }
  }

  // --- live background: video + poster fallback ---
  Item {
    anchors.fill: parent

    // poster fallback while video loads
    Image {
      id: poster
      anchors.fill: parent
      source: "background.jpg"
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: !root.videoReady
    }

    MediaPlayer {
      id: player
      source: "background.mp4"
      videoOutput: videoOut
      audioOutput: AudioOutput {
        id: sddmAudio
        muted: !root.audioEnabled
        volume: 0.8
      }
      loops: MediaPlayer.Infinite
      onErrorOccurred: function(es, s) { console.warn("live-boot SDDM player error", es, s) }
    }

    VideoOutput {
      id: videoOut
      anchors.fill: parent
      fillMode: VideoOutput.PreserveAspectCrop
      visible: root.videoReady
    }

    Connections {
      target: videoOut.videoSink
      function onVideoFrameChanged() { if (!root.videoReady) root.videoReady = true }
    }

    // if video file missing or no decoder, stay on poster
    Timer { interval: 1500; running: true; onTriggered: if (!root.videoReady) console.log("live-boot: staying on poster (video not ready)") }

    Component.onCompleted: {
      // try to play; if QtMultimedia missing, poster stays
      try { player.play() } catch (e) { console.warn("live-boot player.play failed", e) }
      // fallback timer to show content even if video never fires frameReady
      fallbackTimer.restart()
    }
    Timer { id: fallbackTimer; interval: 2500; onTriggered: root.videoReady = true }
  }

  // dark scrim for legibility
  Rectangle {
    anchors.fill: parent
    color: "#0e0e14"
    opacity: root.videoReady ? 0.18 : 0.0
    Behavior on opacity { NumberAnimation { duration: 600 } }
  }

  // Logo is independent from the password field.
  Item {
    id: logoWrap
    width: 260
    height: Math.round(width * 188 / 800)
    x: root.width/2 - width/2 + root.logoOffsetX
    y: root.height/2 - height/2 + root.logoOffsetY
    visible: root.showLogo
    opacity: passWrap.opacity
    Behavior on x { NumberAnimation { duration: 300 } }
    Behavior on y { NumberAnimation { duration: 300 } }

    Image {
      anchors.fill: parent
      source: "logo.png"
      fillMode: Image.PreserveAspectFit
      opacity: 0.95
    }
  }

  // Password container - independently positionable and resizable.
  Item {
    id: passWrap
    width: {{fieldWidth}}
    height: {{fieldHeight}}
    // Natural password row is 340x56. No scale cap: larger sizes enlarge it.
    readonly property real s: Math.min(width / 340.0, height / 56.0)
    anchors.centerIn: root.anchor === "center" ? parent : undefined
    anchors.horizontalCenter: root.anchor !== "center" && root.anchor !== "custom" ? parent.horizontalCenter : undefined
    anchors.top: root.anchor.indexOf("top") !== -1 ? parent.top : undefined
    anchors.bottom: root.anchor.indexOf("bottom") !== -1 ? parent.bottom : undefined
    anchors.topMargin: root.anchor.indexOf("top") !== -1 ? 40 + root.offsetY : 0
    anchors.bottomMargin: root.anchor.indexOf("bottom") !== -1 ? 40 - root.offsetY : 0
    x: root.anchor === "custom" ? parent.width/2 - width/2 + root.offsetX : x
    y: root.anchor === "custom" ? parent.height/2 - height/2 + root.offsetY : y
    opacity: 1
    Component.onCompleted: { passWrap.opacity = 0; fadeIn.restart() }
    Timer { id: fadeIn; interval: 700; onTriggered: passWrap.opacity = 1 }
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    Behavior on x { NumberAnimation { duration: 300 } }
    Behavior on y { NumberAnimation { duration: 300 } }

    Row {
      anchors.centerIn: parent
      scale: passWrap.s
      spacing: 12

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 28
        height: 32
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: 300
        height: 44

          Image {
            id: entry
            source: root.loginFailed ? "entry-failed.png" : "entry.png"
            anchors.centerIn: parent
            width: parent.width
            height: 44
            fillMode: Image.PreserveAspectCrop
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
              model: Math.min(password.text.length, 21)
              Image { source: "bullet.png"; width: 7; height: 7 }
            }
          }

          TextInput {
            id: password
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 20
            font.letterSpacing: 4
            passwordCharacter: "\u2022"
            color: "transparent"
            selectionColor: "transparent"
            selectedTextColor: "transparent"
            cursorDelegate: Item {}
            focus: true
            onTextChanged: root.loginFailed = false
            Keys.onPressed: {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                sddm.login(root.currentUser, password.text, root.sessionIndex)
                event.accepted = true
              }
            }
          }
      }
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
