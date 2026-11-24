import QtQuick
import qs.Commons

// A plain list of rows for the DJ dock. A click is passed up with the row and
// its place in the list; the dock decides whether it opens or plays.
Column {
  id: root

  property var list: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal activated(var row, int index)

  Repeater {
    model: root.list
    delegate: RowItem {
      required property var modelData
      required property int index
      width: root.width
      entry: modelData
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onActivated: root.activated(modelData, index)
    }
  }
}
