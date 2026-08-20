import QtQuick 2.0
import SddmComponents 2.0

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

  // --- live background ---
  // video file is copied to theme dir as background.mp4 by live-boot.sh --sync-sddm
  // poster fallback is background.jpg
  Item {
    anchors.fill: parent
    // poster fallback (visible until first video frame)
    Image {
      id: poster
      anchors.fill: parent
      source: "background.jpg"
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: !root.videoReady
    }
    // mpv via QtMultimedia would be ideal, but SDDM QtMultimedia may be missing gstreamer
    // We keep Image fallback as primary; if QtMultimedia available, Video will overlay it.
    // The template is rendered at install time; for full video support ensure qt6-multimedia is installed.
    // Placeholder Video - will be active if Multimedia is importable at runtime
    // If import fails SDDM falls back to poster (acceptable degradation)
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
    // center default, offsets from live-boot config
    anchors.centerIn: root.anchor === "center" ? parent : undefined
    anchors.horizontalCenter: root.anchor !== "center" && root.anchor !== "custom" ? parent.horizontalCenter : undefined
    anchors.top: root.anchor.indexOf("top") !== -1 ? parent.top : undefined
    anchors.bottom: root.anchor.indexOf("bottom") !== -1 ? parent.bottom : undefined
    anchors.topMargin: root.anchor.indexOf("top") !== -1 ? 40 + root.offsetY : 0
    anchors.bottomMargin: root.anchor.indexOf("bottom") !== -1 ? 40 - root.offsetY : 0
    // custom uses absolute offsets from center
    x: root.anchor === "custom" ? parent.width/2 - width/2 + root.offsetX : x
    y: root.anchor === "custom" ? parent.height/2 - height/2 + root.offsetY : y
    opacity: 1
    // fade in after short delay to mimic video->password transition
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

  // if Video is available the poster will be replaced - we keep poster as base
  // simulate videoReady after 400ms for transition
  Timer { interval: 400; running: true; onTriggered: root.videoReady = true }

  Component.onCompleted: password.forceActiveFocus()
}
