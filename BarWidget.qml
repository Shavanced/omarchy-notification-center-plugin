// Self-contained bar widget: the popup lives right here, anchored to the
// icon button via PopupCard, exactly like the original widget (this is what
// made the old widget position/size itself correctly — PopupCard anchors to
// anchorItem automatically, no manual screen-edge math needed).
//
// Data layer reads the notification service's state files (live.json and
// history.json), since third-party plugins only see DND on the service.
//
// UI: no more Pending/Recently tabs — a search field, a
// "Recent and live notifications" label with a Clear all button, then a
// single merged, newest-first list below (live + history combined).
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NotificationLogic.js" as NotificationLogic

BarWidget {
  id: root
  moduleName: "shavanced.notification-center"

  property bool popupOpen: false
  function close() { popupOpen = false }

  property string query: ""
  property var filteredRows: []
  property var historyRows: []
  property var liveRows: []

  // Third-party plugins only get a narrow proxy of omarchy.notifications
  // (doNotDisturb + setDoNotDisturb), so the rows are read from the state
  // files the service writes: live.json (on screen) and history.json.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/notifications"

  // Entries dismissed or cleared here. The service offers no way for a
  // plugin to remove them, so they are hidden locally and persisted.
  property var hiddenKeys: ({})
  property double clearedBefore: 0
  readonly property string hiddenPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/shavanced.notification-center/hidden.json"

  function isHidden(row) {
    return !!root.hiddenKeys[row.key] || (row.timestamp > 0 && row.timestamp <= root.clearedBefore)
  }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var notificationService: hostShell && hostShell.firstPartyServiceFor
    ? hostShell.firstPartyServiceFor("omarchy.notifications") : null

  readonly property int liveCount: {
    var n = 0
    for (var i = 0; i < root.liveRows.length; ++i) if (!root.isHidden(root.liveRows[i])) n++
    return n
  }

  // ---- DND (guarded: lives on Omarchy's first-party service, not here).
  readonly property bool dndSupported: !!notificationService
    && typeof notificationService.doNotDisturb === "boolean"
    && typeof notificationService.setDoNotDisturb === "function"
  readonly property bool dndOn: dndSupported && notificationService.doNotDisturb
  function toggleDnd() {
    if (dndSupported) notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  readonly property string icon: {
    if (root.dndOn) return "󰂛"
    if (root.liveCount > 0) return "󱅫"
    return "󰂚"
  }

  // Theme palette (mirrors the old widget's tokens).
  readonly property color colForeground: Commons.Color.foreground
  readonly property color colDim: Qt.darker(Commons.Color.foreground, 1.4)
  readonly property color colBorder: Style.normalBorderFor(Commons.Color.foreground, Commons.Color.accent)
  readonly property color colSurface: Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent)
  readonly property color colAccent: Commons.Color.accent
  readonly property int cardRadius: Style.cornerRadius

  function notificationIconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function formatTimestamp(ms) {
    var date = new Date(Number(ms) || Date.now())
    var now = new Date()
    var sameDay = date.getFullYear() === now.getFullYear()
      && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
    var time = date.toLocaleTimeString(Qt.locale(), "hh:mm")
    return sameDay ? time : date.toLocaleDateString(Qt.locale(), "MMM d") + " · " + time
  }

  function rowMatches(row) {
    var needle = root.query.trim().toLowerCase()
    if (needle === "") return true
    var haystack = [row.app, row.summary, row.body].join(" ").toLowerCase()
    return haystack.indexOf(needle) >= 0
  }

  function rebuildRows() {
    var rows = []
    var seen = ({})
    var sources = [root.liveRows, root.historyRows]
    for (var s = 0; s < sources.length; ++s) {
      for (var i = 0; i < sources[s].length; ++i) {
        var row = sources[s][i]
        if (seen[row.key] || root.isHidden(row) || !rowMatches(row)) continue
        seen[row.key] = true
        rows.push(row)
      }
    }
    rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
    root.filteredRows = rows
  }

  function saveHidden() {
    // Forget keys that have aged out of both state files.
    var present = ({})
    var all = root.liveRows.concat(root.historyRows)
    for (var i = 0; i < all.length; ++i) present[all[i].key] = true
    var keys = []
    for (var key in root.hiddenKeys) if (present[key]) keys.push(key)
    hiddenFile.setText(JSON.stringify({ clearedBefore: root.clearedBefore, keys: keys }) + "\n")
  }

  function dismiss(row) {
    if (!row) return
    var next = Object.assign({}, root.hiddenKeys)
    next[row.key] = true
    root.hiddenKeys = next
    saveHidden()
    rebuildRows()
  }

  function clearSearch() {
    root.query = ""
    searchField.text = ""
  }

  function clearAll() {
    var newest = 0
    var all = root.liveRows.concat(root.historyRows)
    for (var i = 0; i < all.length; ++i) newest = Math.max(newest, all[i].timestamp || 0)
    root.clearedBefore = Math.max(Date.now(), newest)
    root.hiddenKeys = ({})
    saveHidden()
    rebuildRows()
  }

  function parseRows(raw, isLive) {
    var parsed = []
    var list = []
    try { list = JSON.parse(String(raw || "[]")) } catch (e) { list = [] }
    if (!Array.isArray(list)) return parsed
    for (var i = 0; i < list.length; ++i) {
      var value = list[i]
      if (!value || typeof value !== "object") continue
      var ts = Number(value.ts || 0)
      parsed.push({
        key: String(value.key || ((value.app || "") + "|" + (value.summary || "") + "|" + ts)),
        isLive: isLive,
        id: value.originalId !== undefined ? value.originalId : null,
        app: String(value.app || "Unknown application"),
        appIcon: String(value.appIcon || ""),
        summary: String(value.summary || "Notification"),
        body: String(value.body || ""),
        glyph: String(value.glyph || ""),
        urgency: Number(value.urgency === undefined ? 1 : value.urgency),
        // The service stores seconds; the UI works in milliseconds.
        timestamp: ts > 0 && ts < 1e11 ? ts * 1000 : ts
      })
    }
    return parsed
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      clearSearch()
      rebuildRows()
    }
  }
  onQueryChanged: rebuildRows()

  FileView {
    path: root.stateDir + "/live.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.liveRows = root.parseRows(text(), true); root.rebuildRows() }
    onLoadFailed: { root.liveRows = []; root.rebuildRows() }
  }

  FileView {
    path: root.stateDir + "/history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.historyRows = root.parseRows(text(), false); root.rebuildRows() }
    onLoadFailed: { root.historyRows = []; root.rebuildRows() }
  }

  FileView {
    id: hiddenFile
    path: root.hiddenPath
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var state = JSON.parse(text())
        var keys = ({})
        for (var i = 0; i < (state.keys || []).length; ++i) keys[String(state.keys[i])] = true
        root.hiddenKeys = keys
        root.clearedBefore = Number(state.clearedBefore || 0)
      } catch (e) {
      }
      root.rebuildRows()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.liveCount > 0 && !root.dndOn
    tooltipText: root.dndOn ? "DND on — right-click to turn off"
      : (root.liveCount > 0 ? root.liveCount + " live notifications" : "Notification Center")

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.toggleDnd()
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: searchField
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.cappedContentHeight(Style.space(540))

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      // ----------------------------------------- header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "Notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colForeground
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          text: root.liveCount === 1 ? "1 notification" : root.liveCount + " notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colDim
          font.pixelSize: Style.font.caption
        }

        Item { Layout.fillWidth: true }

        BorderSurface {
          id: dndPill
          visible: root.dndSupported
          Layout.preferredHeight: Math.max(Style.space(24), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
          Layout.preferredWidth: dndLabel.implicitWidth + dndGlyph.implicitWidth + Style.space(18)
          radius: Math.min(Style.space(12), root.cardRadius + Style.space(6))
          color: root.dndOn ? root.colAccent : root.colSurface
          borderSpec: Border.flat(root.dndOn ? root.colAccent : root.colBorder, Style.normalBorderWidth)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              id: dndGlyph
              text: root.dndOn ? "󰂛" : "󰂚"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.dndOn ? Commons.Color.background : root.colDim
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: dndLabel
              text: root.dndOn ? "DND on" : "DND off"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.dndOn ? Commons.Color.background : root.colDim
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleDnd()
          }
        }

        BorderSurface {
          Layout.preferredWidth: Style.space(22)
          Layout.preferredHeight: Style.space(22)
          radius: Math.min(Style.space(6), root.cardRadius)
          color: closeHeaderArea.containsMouse ? root.colBorder : "transparent"
          borderSpec: Border.flat(root.colBorder, Style.normalBorderWidth)

          Text {
            anchors.centerIn: parent
            text: "󰅖"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: closeHeaderArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
          }
        }
      }

      // ----------------------------------------- search
      TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search notifications"
        activeFocusOnPress: true
        onTextEdited: root.query = text
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.query.length > 0) {
              root.clearSearch()
            } else {
              root.close()
            }
            event.accepted = true
          }
        }
      }

      // ----------------------------------------- label + clear all
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          text: root.query.trim() === "" ? "Recent and live notifications" : root.filteredRows.length + " matching notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colDim
          font.pixelSize: Style.font.caption
        }

        BorderSurface {
          Layout.preferredWidth: clearLabel.implicitWidth + Style.space(16)
          Layout.preferredHeight: Math.max(Style.space(22), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
          radius: Math.min(Style.space(6), root.cardRadius)
          color: clearArea.containsMouse ? root.colBorder : "transparent"
          borderSpec: Border.flat(root.colBorder, Style.normalBorderWidth)

          Text {
            id: clearLabel
            anchors.centerIn: parent
            text: "Clear all"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: clearArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearAll()
          }
        }
      }

      // ----------------------------------------- list
      ListView {
        id: listView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.space(8)
        model: root.filteredRows
        visible: count > 0

        delegate: BorderSurface {
          id: rowCard
          required property var modelData

          readonly property string smallIconSource: root.notificationIconSource(modelData.appIcon)
          readonly property bool hasIcon: modelData.glyph === "" && smallIconSource.length > 0
          readonly property string sanitizedBody: NotificationLogic.sanitizeBody(modelData.body, modelData.app, modelData.appIcon)

          width: listView.width
          implicitHeight: rowContent.implicitHeight + Style.spacing.panelGap
          radius: root.cardRadius
          color: "transparent"
          borderSpec: Border.flat(root.colBorder, Style.normalBorderWidth)

          // Left click dismisses. Hover reveals a dedicated close (x)
          // button as an alternate, more discoverable way to dismiss.
          MouseArea {
            id: rowHoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismiss(rowCard.modelData)
          }

          RowLayout {
            id: rowContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: rowCard.borderLeft + Style.space(12)
            anchors.rightMargin: rowCard.borderRight + Style.space(12)
            spacing: Style.space(10)

            Text {
              Layout.alignment: Qt.AlignTop
              visible: rowCard.modelData.glyph !== ""
              text: rowCard.modelData.glyph
              color: rowCard.modelData.urgency === 2 ? Commons.Color.urgent : Commons.Color.accent
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.icon
            }

            Item {
              Layout.preferredWidth: Style.space(32)
              Layout.preferredHeight: Style.space(32)
              Layout.alignment: Qt.AlignVCenter
              visible: rowCard.hasIcon && rowIconImage.status !== Image.Error

              Image {
                id: rowIconImage
                anchors.fill: parent
                source: rowCard.smallIconSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                asynchronous: true
                smooth: true
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              RowLayout {
                Layout.fillWidth: true
                Text {
                  Layout.fillWidth: true
                  text: rowCard.modelData.app
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colDim
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  text: root.formatTimestamp(rowCard.modelData.timestamp)
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colDim
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                Layout.fillWidth: true
                visible: rowCard.modelData.summary.length > 0
                text: rowCard.modelData.summary
                font.family: root.bar ? root.bar.fontFamily : ""
                color: root.colForeground
                font.pixelSize: Style.font.subtitle
                font.bold: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
              }

              Text {
                Layout.fillWidth: true
                visible: rowCard.sanitizedBody.length > 0
                text: rowCard.sanitizedBody
                textFormat: Text.PlainText
                font.family: root.bar ? root.bar.fontFamily : ""
                color: root.colDim
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 3
              }
            }

            // Close (x): visible ONLY while hovering this row.
            Rectangle {
              Layout.preferredWidth: Style.space(20)
              Layout.preferredHeight: Style.space(20)
              Layout.alignment: Qt.AlignVCenter
              visible: rowHoverArea.containsMouse
              radius: Math.min(4, root.cardRadius)
              color: closeArea.containsMouse ? root.colBorder : "transparent"

              Text {
                anchors.centerIn: parent
                text: "✕"
                font.family: root.bar ? root.bar.fontFamily : ""
                color: root.colDim
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  mouse.accepted = true
                  root.dismiss(rowCard.modelData)
                }
              }
            }
          }
        }
      }

      // ----------------------------------------- empty state
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: listView.count === 0

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰂚"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colBorder
            font.pixelSize: Style.font.displayLarge
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.query.trim() === "" ? "No notifications" : "No matching notifications"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colDim
            font.pixelSize: Style.font.body
          }
        }
      }

      // ----------------------------------------- footer legend
      Text {
        Layout.fillWidth: true
        text: "Left-click or hover the ✕ to dismiss · Esc closes"
        font.family: root.bar ? root.bar.fontFamily : ""
        color: Qt.darker(root.colForeground, 1.55)
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
