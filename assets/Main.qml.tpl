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
  property string revealMode: "{{revealMode}}"
  property int transitionDuration: {{transitionDuration}}
  property int passwordDelay: {{passwordDelay}}
  property bool revealStarted: false
  property bool logoRevealed: false
  property bool passwordRevealed: false
  focus: true

  function revealLogin() {
    if (revealStarted) {
      if (!passwordRevealed) { passwordRevealTimer.stop(); showPassword() }
      return
    }
    revealStarted = true
    fallbackTimer.stop()
    endSafety.stop()
    if (revealMode === "video-end" && player.playbackState === MediaPlayer.PlayingState) player.pause()
    logoRevealed = true
    if (passwordDelay <= 0) showPassword()
    else passwordRevealTimer.restart()
  }

  function showPassword() {
    passwordRevealed = true
    Qt.callLater(function() { password.forceActiveFocus() })
  }

  Keys.onPressed: function(event) {
    if (!passwordRevealed && (event.key === Qt.Key_Escape || event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      revealLogin()
      event.accepted = true
    }
  }

  Timer { id: passwordRevealTimer; interval: root.passwordDelay; onTriggered: root.showPassword() }
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
        muted: !root.audioEnabled || (root.revealMode === "video-end" && root.revealStarted)
        volume: 0.8
      }
      loops: root.revealMode === "video-end" ? 1 : MediaPlayer.Infinite
      onDurationChanged: {
        if (root.revealMode === "video-end" && duration > 0) {
          endSafety.interval = duration + 3000
          endSafety.restart()
        }
      }
      onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) root.revealLogin()
      onErrorOccurred: function(es, s) { console.warn("live-boot SDDM player error", es, s); root.revealLogin() }
    }

    VideoOutput {
      id: videoOut
      anchors.fill: parent
      fillMode: VideoOutput.PreserveAspectCrop
      visible: root.videoReady
    }

    Connections {
      target: videoOut.videoSink
      function onVideoFrameChanged() {
        if (!root.videoReady) {
          root.videoReady = true
          if (root.revealMode === "first-frame") root.revealLogin()
        }
      }
    }

    // if video file missing or no decoder, stay on poster
    Timer { interval: 1500; running: true; onTriggered: if (!root.videoReady) console.log("live-boot: staying on poster (video not ready)") }

    Component.onCompleted: {
      // try to play; if QtMultimedia missing, poster stays
      try { player.play() } catch (e) { console.warn("live-boot player.play failed", e) }
      // fallback timer to show content even if video never fires frameReady
      fallbackTimer.restart()
    }
    Timer { id: fallbackTimer; interval: 5000; onTriggered: if (!root.videoReady) root.revealLogin() }
    Timer { id: endSafety; interval: 15000; running: root.revealMode === "video-end"; onTriggered: root.revealLogin() }
  }

  // dark scrim for legibility
  Rectangle {
    anchors.fill: parent
    color: "#0e0e14"
    opacity: root.logoRevealed ? 0.18 : 0.0
    Behavior on opacity { NumberAnimation { duration: root.transitionDuration } }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.revealMode === "video-end" && !root.passwordRevealed
    onClicked: root.revealLogin()
  }

  // Logo is independent from the password field.
  Item {
    id: logoWrap
    width: {{logoWidth}}
    height: {{logoHeight}}
    x: root.width/2 - width/2 + root.logoOffsetX
    y: root.height/2 - height/2 + root.logoOffsetY
    visible: root.showLogo
    opacity: root.logoRevealed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic } }
    Behavior on x { NumberAnimation { duration: root.transitionDuration } }
    Behavior on y { NumberAnimation { duration: root.transitionDuration } }

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
    // Omarchy's natural password row is 335x48. No scale cap.
    readonly property real s: Math.min(width / 335.0, height / 48.0)
    anchors.centerIn: root.anchor === "center" ? parent : undefined
    anchors.horizontalCenter: root.anchor !== "center" && root.anchor !== "custom" ? parent.horizontalCenter : undefined
    anchors.top: root.anchor.indexOf("top") !== -1 ? parent.top : undefined
    anchors.bottom: root.anchor.indexOf("bottom") !== -1 ? parent.bottom : undefined
    anchors.topMargin: root.anchor.indexOf("top") !== -1 ? 40 + root.offsetY : 0
    anchors.bottomMargin: root.anchor.indexOf("bottom") !== -1 ? 40 - root.offsetY : 0
    x: root.anchor === "custom" ? parent.width/2 - width/2 + root.offsetX : x
    y: root.anchor === "custom" ? parent.height/2 - height/2 + root.offsetY : y
    opacity: root.passwordRevealed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic } }
    Behavior on x { NumberAnimation { duration: 300 } }
    Behavior on y { NumberAnimation { duration: 300 } }

    Row {
      anchors.centerIn: parent
      scale: passWrap.s
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: 286
        height: 48

          Image {
            id: entry
            source: root.loginFailed ? "entry-failed.png" : "entry.png"
            anchors.centerIn: parent
            width: parent.width
            height: 48
            fillMode: Image.PreserveAspectCrop
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Repeater {
              model: Math.min(password.text.length, 21)
              Image { source: "bullet.png"; width: 7; height: 7 }
            }
          }

          TextInput {
            id: password
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 24
            font.letterSpacing: 5
            passwordCharacter: "\u2022"
            color: "transparent"
            selectionColor: "transparent"
            selectedTextColor: "transparent"
            cursorDelegate: Item {}
            enabled: root.passwordRevealed
            focus: root.passwordRevealed
            onTextChanged: root.loginFailed = false
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                sddm.login(root.currentUser, password.text, root.sessionIndex)
                event.accepted = true
              }
            }
          }
      }
    }
  }

  Component.onCompleted: root.forceActiveFocus()
}
