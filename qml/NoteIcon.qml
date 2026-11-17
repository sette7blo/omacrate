// Lucide `music` — https://lucide.dev/icons/music (ISC license).
// Drawn as paths so the icon stays recolorable at runtime.
import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property real size: 14
  property color iconColor: "white"
  property real strokeWidth: 2

  implicitWidth: size
  implicitHeight: size

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    transformOrigin: Item.TopLeft
    scale: root.size / 24

    ShapePath {
      strokeWidth: root.strokeWidth
      strokeColor: root.iconColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M9 18 V5 l12 -2 v13" }
    }
    ShapePath {
      strokeWidth: root.strokeWidth
      strokeColor: root.iconColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M9 18 a3 3 0 1 1 -6 0 a3 3 0 1 1 6 0 z" }
    }
    ShapePath {
      strokeWidth: root.strokeWidth
      strokeColor: root.iconColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M21 16 a3 3 0 1 1 -6 0 a3 3 0 1 1 6 0 z" }
    }
  }
}
