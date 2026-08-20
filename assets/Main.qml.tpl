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
  property bool audioEnabled: {{audioEnabled}}
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

  // password container - positionable via anchor
  Item {
    id: passWrap
    width: 420
    height: 120
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

    Column {
      anchors.centerIn: parent
      spacing: 18

      Image {
        id: logo
        source: "logo.png"
        width: Math.min(sourceSize.width, root.width * 0.7)
        height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: 0.95
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12

        Image {
          source: root.loginFailed ? "lock-failed.png" : "lock.png"
          width: 28
          height: 32
          fillMode: Image.PreserveAspectFit
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: 260
          height: 44

          Image {
            id: entry
            source: root.loginFailed ? "entry-failed.png" : "entry.png"
            anchors.centerIn: parent
            width: 260
            height: 44
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
  }

  Component.onCompleted: password.forceActiveFocus()
}
