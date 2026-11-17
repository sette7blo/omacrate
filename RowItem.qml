import QtQuick
import QtQuick.Layouts
import qs.Commons

// One row of the list: a title with a note on its right, and a dim second
// line with a small label on its right. The text comes from the Plex server,
// so every Text is plain.
Item {
  id: root

  property var entry: ({})
  property bool selected: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool current: !!entry && entry.current === true
  readonly property bool twoLines: !!entry && (entry.subtitle !== "" || entry.label !== "")

  signal activated()

  implicitHeight: content.implicitHeight + Style.spacing.md * 2

  Rectangle {
    anchors.fill: parent
    visible: root.selected || mouse.containsMouse
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.selected ? 0.12 : 0.07)
    radius: Style.cornerRadius
  }

  // A bar on the leading edge marks the track that is playing.
  Rectangle {
    visible: root.current
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(2)
    height: parent.height - Style.spacing.md * 2
    radius: width / 2
    color: root.accent
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.md + (root.current ? Style.space(6) : 0)
    anchors.rightMargin: Style.spacing.md
    spacing: Style.spacing.xxs

    RowLayout {
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.entry ? root.entry.title : ""
        color: root.current ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        maximumLineCount: 1
      }
      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: root.entry ? root.entry.right : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        maximumLineCount: 1
      }
    }

    RowLayout {
      width: parent.width
      spacing: Style.spacing.lg
      visible: root.twoLines

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.entry ? root.entry.subtitle : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        maximumLineCount: 1
      }
      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: root.entry ? root.entry.label : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        maximumLineCount: 1
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
