import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The settings behind the gear: the Plex account, the bar, and the DJ. The DJ
// is the only part of the plugin that involves an AI agent, and it stays off
// until it is switched on here.
Column {
  id: root

  property var service: null
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool linked: service ? service.linked === true : false
  readonly property var options: service ? service.options : Model.settings(null)
  readonly property string skillsState: service ? service.skillsState : ""

  signal switchUser()
  signal linkAccount()

  spacing: Style.spacing.xxl

  readonly property string lidarrAddress: service ? service.lidarrAddress : ""
  property bool editLidarr: false

  Component.onCompleted: {
    if (!root.service) return
    root.service.checkLidarr()
    if (root.options.dj) root.service.checkSkills()
  }

  // ---- Plex account ----
  Column {
    width: parent.width
    spacing: Style.spacing.lg

    PanelSectionHeader {
      text: "Plex account"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: {
        if (!root.service || !root.linked) return "Not linked. Linking shows a code to enter at plex.tv/link."
        var link = root.service.link
        var line = "Linked to " + link.server
        if (link.home && link.user) line += " as " + link.user
        return line + "."
      }
      color: root.foreground
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Row {
      spacing: Style.spacing.lg

      Button {
        visible: !root.linked
        text: "Link Plex"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.linkAccount()
      }
      Button {
        visible: root.linked && root.service && root.service.link.home === true
        text: "Switch user"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.switchUser()
      }
      Button {
        visible: root.linked
        text: "Log out"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: if (root.service) root.service.logout()
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: root.linked
      text: "Logging out stops the player and forgets the Plex token on this computer."
      color: root.dim
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: root.foreground }

  // ---- Lidarr ----
  // Optional. Used only when you ask for an artist you do not have yet, with
  // omacrate lidarr add, or by the DJ if it is allowed in the DJ section. The key goes to the command on stdin
  // and is never shown again.
  Column {
    id: lidarrSection
    width: parent.width
    spacing: Style.spacing.lg

    readonly property bool showForm: root.lidarrAddress === "" || root.editLidarr

    PanelSectionHeader {
      text: "Lidarr"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.lidarrAddress !== ""
        ? "Connected to " + root.lidarrAddress + "."
        : "Optional. With Lidarr set up, you can add artists you do not have yet."
      color: root.foreground
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    TextField {
      id: lidarrAddressField
      width: parent.width
      visible: lidarrSection.showForm
      placeholderText: "Address, e.g. http://192.168.1.10:8686"
      text: root.lidarrAddress
      foreground: root.foreground
      accent: root.accent
      Keys.onReturnPressed: lidarrKeyField.forceActiveFocus()
    }
    TextField {
      id: lidarrKeyField
      width: parent.width
      visible: lidarrSection.showForm
      password: true
      placeholderText: "API key (Lidarr, Settings, General)"
      foreground: root.foreground
      accent: root.accent
      Keys.onReturnPressed: lidarrSave.clicked()
    }
    Row {
      spacing: Style.spacing.lg

      Button {
        id: lidarrSave
        visible: lidarrSection.showForm
        text: root.service && root.service.lidarrBusy ? "Checking" : "Save"
        enabled: !(root.service && root.service.lidarrBusy)
          && /^https?:\/\/\S+$/.test(lidarrAddressField.text.trim())
          && lidarrKeyField.text.trim().length >= 20
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: {
          if (!enabled || !root.service) return
          root.service.saveLidarr(lidarrAddressField.text, lidarrKeyField.text)
          lidarrKeyField.text = ""
          root.editLidarr = false
        }
      }
      Button {
        visible: root.editLidarr
        text: "Cancel"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: {
          lidarrKeyField.text = ""
          root.editLidarr = false
        }
      }
      Button {
        visible: root.lidarrAddress !== "" && !root.editLidarr
        text: "Change"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: {
          lidarrAddressField.text = root.lidarrAddress
          root.editLidarr = true
        }
      }
      Button {
        visible: root.lidarrAddress !== "" && !root.editLidarr
        text: "Remove"
        enabled: !(root.service && root.service.lidarrBusy)
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: if (root.service) root.service.removeLidarr()
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: text !== ""
      text: root.service ? root.service.lidarrMessage : ""
      color: root.service && root.service.lidarrFailed ? Commons.Color.urgent : root.dim
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: root.foreground }

  // ---- Bar ----
  Column {
    width: parent.width
    spacing: Style.spacing.lg

    PanelSectionHeader {
      text: "Bar"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Toggle {
      width: parent.width
      label: "Show the track title"
      description: "Next to the note, while something plays."
      checked: root.options.showTitle
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onClicked: if (root.service) root.service.persistSettings({ showTitle: !root.options.showTitle })
    }
  }

  PanelSeparator { foreground: root.foreground }

  // ---- DJ ----
  Column {
    width: parent.width
    spacing: Style.spacing.lg

    PanelSectionHeader {
      text: "AI DJ"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Toggle {
      width: parent.width
      label: "Enable the DJ"
      description: "Off unless you turn it on."
      checked: root.options.dj
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onClicked: {
        if (!root.service) return
        var on = !root.options.dj
        root.service.persistSettings({ dj: on })
        if (on) root.service.checkSkills()
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "The DJ adds an Ask DJ button that opens your own default Omarchy agent (claude, codex, cursor-agent or copilot) in a terminal and points it at your music library. It opens with the agent's normal permission prompts, so it asks before running commands. Omacrate has no AI of its own and no API key, and sends nothing anywhere itself. What the agent sends to its provider is between you and that agent."
      color: root.dim
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // A second yes, so the agent's provider does not learn what you download
    // or that Lidarr is there unless you want it to.
    Toggle {
      width: parent.width
      visible: root.options.dj && root.lidarrAddress !== ""
      label: "Let the DJ use Lidarr"
      description: "Off: the DJ cannot look up or add artists, and is not told that Lidarr is there."
      checked: root.service ? root.service.lidarrDj : false
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onClicked: if (root.service) root.service.setLidarrDj(!root.service.lidarrDj)
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: root.options.dj && root.service && !root.service.agentReady && root.service.agentNote !== ""
      text: root.service ? root.service.agentNote : ""
      color: Commons.Color.urgent
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // The skills are a second, separate choice: links in your agents' own
    // folders, so they also work outside the DJ.
    Column {
      width: parent.width
      spacing: Style.spacing.lg
      visible: root.options.dj && root.skillsState !== "" && root.skillsState !== "unavailable"

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.skillsState === "installed"
          ? "The omacrate skills are linked into your agents' skill folders."
          : "Optional: link the omacrate skills into your agents' skill folders, so they know the omacrate command outside the DJ too. The DJ works without this."
        color: root.dim
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Button {
        text: root.skillsState === "installed" ? "Remove agent skills" : "Install agent skills"
        enabled: !(root.service && root.service.skillsBusy)
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: if (root.service) root.service.setSkills(root.skillsState !== "installed")
      }
    }
  }
}
