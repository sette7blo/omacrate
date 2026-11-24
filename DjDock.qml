import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "qml"
import "Model.js" as Model

// omacrate docked on the left edge while the DJ runs in a terminal. The
// exclusive zone reserves the strip the way the bar does, so Hyprland tiles
// the terminal into the rest of the screen. It only shows what is playing,
// the queue and the playlist changed last; acting on them is the DJ's job, or
// the panel's. Every Text holds server data, so every Text is plain.
PanelWindow {
  id: root

  required property var service

  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family
  // Hyprland keeps windows a full gaps_out from the edges; Style.gapsOut is half.
  readonly property real edgeGap: Style.gapsOut * 2
  readonly property real cardWidth: Style.space(340)

  readonly property var current: service.current
  readonly property var queueRows: Model.queueRows(service.queue, service.position)
  readonly property var playlist: service.djPlaylist
  readonly property var playlistRows: Model.rows(service.djPlaylistTracks, "playlist")

  screen: service.djScreen
  visible: service.djDockShown
  color: "transparent"

  WlrLayershell.namespace: "omacrate-dj-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: implicitWidth

  anchors {
    top: true
    bottom: true
    left: true
  }
  implicitWidth: edgeGap + cardWidth

  BorderSurface {
    id: card
    x: root.edgeGap
    y: root.edgeGap
    width: root.cardWidth
    height: parent.height - root.edgeGap * 2
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius
    clip: true

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      contentWidth: width
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar {
        id: scroll
        policy: ScrollBar.AsNeeded
      }

      Column {
        id: body
        width: flick.width - (flick.interactive ? scroll.width + Style.space(6) : 0)
        spacing: Style.spacing.xxl

        PanelHero {
          width: parent.width
          title: "Omacrate"
          meta: "DJ"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            NoteIcon {
              size: Style.font.display
              iconColor: root.foreground
              strokeWidth: 1.75
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "\u{f0156}"
              tooltipText: "Close DJ"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.closeDj()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- Now playing ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm

          PanelSectionHeader {
            width: parent.width
            text: root.service.paused ? "Paused" : "Now playing"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.current ? root.current.title : "Nothing is playing."
            color: root.current ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: root.current ? Style.font.body : Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            text: Model.nowLine(root.current)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        // ---- Queue ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.queueRows.length > 0

          PanelSectionHeader {
            width: parent.width
            text: "Queue"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: root.queueRows
            delegate: RowItem {
              required property var modelData
              width: parent.width
              enabled: false
              entry: modelData
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- Latest playlist ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm

          PanelSectionHeader {
            width: parent.width
            text: root.playlist ? "Latest playlist: " + root.playlist.title : "Latest playlist"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            text: !root.service.djPlaylistLoaded ? "Loading playlists."
              : (!root.playlist ? "No playlists yet. Ask the DJ to make one."
              : (root.playlistRows.length ? "" : "This playlist is empty."))
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Repeater {
            model: root.playlistRows
            delegate: RowItem {
              required property var modelData
              width: parent.width
              enabled: false
              entry: modelData
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
            }
          }
        }
      }
    }
  }
}
