// Self-contained bar widget: the popup lives right here, anchored to the
// icon button via PopupCard, exactly like the original widget (this is what
// made the old widget position/size itself correctly — PopupCard anchors to
// anchorItem automatically, no manual screen-edge math needed).
//
// Data layer is rewired to the service surface confirmed working in the
// newer plugin (popupModel for live notifications, historyDir for on-disk
// history) instead of the old pendingModel/pastModel calls, which is why
// notifications weren't showing.
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

  // Locally-dismissed history entries, hidden until they drop out of the
  // on-disk history on their own (see dismiss()).
  property var hiddenHistoryKeys: ({})
  function historyKey(row) {
    if (row.id !== undefined && row.id !== null && row.id !== 0) return "id:" + row.id
    return "k:" + row.app + "|" + row.summary + "|" + row.timestamp
  }

  // Look up the long-running notifications service through the shell host.
  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var notificationService: hostShell && hostShell.firstPartyServiceFor
    ? hostShell.firstPartyServiceFor("omarchy.notifications") : null

  readonly property int liveCount: notificationService && notificationService.popupModel
    ? notificationService.popupModel.count : 0
  readonly property string historyDir: notificationService && notificationService.historyDir
    ? String(notificationService.historyDir) : ""

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
  readonly property color colForeground: Color.foreground
  readonly property color colDim: Qt.darker(Color.foreground, 1.4)
  readonly property color colBorder: Style.normalBorderFor(Color.foreground, Color.accent)
  readonly property color colSurface: Style.normalFillFor(Color.foreground, Color.accent)
  readonly property color colAccent: Color.accent
  readonly property int cardRadius: notificationService && notificationService.cornerRadius
    ? notificationService.cornerRadius : Style.cornerRadius

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
    for (var h = 0; h < root.historyRows.length; ++h) {
      var history = root.historyRows[h]
      if (root.hiddenHistoryKeys[root.historyKey(history)]) continue
      if (!rowMatches(history)) continue
      rows.push({
        sourceIndex: -1,
        isLive: false,
        id: history.id,
        app: history.app,
        appIcon: history.appIcon,
        summary: history.summary,
        body: history.body,
        glyph: history.glyph,
        urgency: history.urgency,
        timestamp: history.timestamp
      })
    }
    var model = root.notificationService ? root.notificationService.popupModel : null
    if (!model) { root.filteredRows = rows; return }
    for (var i = 0; i < model.count; ++i) {
      var row = model.get(i)
      if (!row || !rowMatches(row)) continue
      rows.push({
        sourceIndex: i,
        isLive: true,
        id: row.id !== undefined ? row.id : null,
        app: String(row.appName || row.app || "Unknown application"),
        appIcon: String(row.appIcon || ""),
        summary: String(row.summary || "Notification"),
        body: String(row.body || ""),
        glyph: String(row.glyph || NotificationLogic.glyphFromHints(row.hints)),
        urgency: Number(row.urgency || 1),
        timestamp: Number(row.timestamp || 0)
      })
    }
    rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
    root.filteredRows = rows
  }

  function dismiss(row) {
    if (!row) return
    if (row.isLive) {
      if (root.notificationService && typeof root.notificationService.dismissPopup === "function")
        root.notificationService.dismissPopup(row.sourceIndex)
    } else {
      var key = root.historyKey(row)
      var next = Object.assign({}, root.hiddenHistoryKeys)
      next[key] = true
      root.hiddenHistoryKeys = next
      if (root.notificationService && typeof root.notificationService.removeHistoryEntry === "function")
        root.notificationService.removeHistoryEntry(row.id)
    }
    rebuildRows()
  }

  // ---- Focus / launch the app that sent a notification.
  // Uses omarchy-launch-or-focus when available (exact word-boundary match on
  // window class/title).  Falls back to a direct hyprctl lookup so the feature
  // works even on minimal installs.
  property string focusTarget: ""

  function focusApp(appName) {
    var name = String(appName || "").trim()
    if (name === "" || name === "notify-send" || name === "omarchy-action") return
    root.focusTarget = name
    focusLookup.command = ["hyprctl", "clients", "-j"]
    focusLookup.running = true
  }

  function resolveFocusFromClients(json) {
    var target = root.focusTarget
    if (!target) return
    try {
      var clients = JSON.parse(json)
      var needle = target.toLowerCase()
      var best = null
      for (var i = 0; i < clients.length; i++) {
        var c = clients[i]
        if (!c) continue
        var cls = String(c["class"] || "").toLowerCase()
        var title = String(c["title"] || "").toLowerCase()
        if (cls === needle || title === needle ||
            cls.indexOf(needle) >= 0 || title.indexOf(needle) >= 0 ||
            needle.indexOf(cls) >= 0) {
          best = c
          break
        }
      }
      if (best && best.address) {
        focusDispatch.command = ["hyprctl", "dispatch", "focuswindow", "address:" + best.address]
        focusDispatch.running = true
        root.close()
        return
      }
    } catch (e) { /* ignore parse errors */ }

    // No matching window found — try to launch via omarchy-launch-or-focus.
    focusLaunch.command = ["omarchy-launch-or-focus", target]
    focusLaunch.running = true
    root.close()
  }

  function clearSearch() {
    root.query = ""
    searchField.text = ""
  }

  function clearAll() {
    if (!root.notificationService) return
    if (typeof root.notificationService.clearPopups === "function") root.notificationService.clearPopups()
    if (typeof root.notificationService.clearHistory === "function") root.notificationService.clearHistory()
    root.historyRows = []
    root.hiddenHistoryKeys = ({})
    rebuildRows()
  }

  function parseHistory(raw) {
    var parsed = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
      var line = lines[i].trim()
      if (!line) continue
      try {
        var value = JSON.parse(line)
        if (!value || typeof value !== "object") continue
        parsed.push({
          id: value.id !== undefined ? value.id : (value.originalId !== undefined ? value.originalId : null),
          app: String(value.app || "Unknown application"),
          appIcon: String(value.appIcon || ""),
          summary: String(value.summary || "Notification"),
          body: String(value.body || ""),
          glyph: String(value.glyph || ""),
          urgency: Number(value.urgency === undefined ? 1 : value.urgency),
          timestamp: Number(value.timestamp || 0)
        })
      } catch (e) {
        // A torn write is ignored, matching the first-party parser.
      }
    }
    parsed.sort(function(a, b) { return b.timestamp - a.timestamp })
    root.historyRows = parsed.slice(0, root.notificationService && root.notificationService.historyLimit
      ? Number(root.notificationService.historyLimit) : 10)
    rebuildRows()
  }

  function refreshHistory() {
    if (!root.historyDir || historyReader.running) return
    historyReader.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", root.historyDir]
    historyReader.running = true
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      clearSearch()
      refreshHistory()
      rebuildRows()
      // Explicitly grab keyboard focus for the search field. Without this,
      // a wlr-layer-shell popup can render and accept mouse clicks while
      // still not reliably routing keystrokes to a child TextField, which
      // is what made typing feel inconsistent.
      Qt.callLater(function() { if (root.popupOpen) searchField.forceActiveFocus() })
    }
  }
  onQueryChanged: rebuildRows()

  Timer {
    interval: 500
    repeat: true
    running: root.popupOpen
    onTriggered: root.refreshHistory()
  }

  Process {
    id: historyReader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseHistory(text)
    }
  }

  Process {
    id: focusLookup
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.resolveFocusFromClients(text)
    }
  }

  Process {
    id: focusDispatch
    running: false
  }

  Process {
    id: focusLaunch
    running: false
  }

  Connections {
    target: root.notificationService ? root.notificationService.popupModel : null
    function onCountChanged() { root.rebuildRows() }
    function onDataChanged() { root.rebuildRows() }
    function onRowsInserted() { root.rebuildRows() }
    function onRowsRemoved() { root.rebuildRows() }
    function onModelReset() { root.rebuildRows() }
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

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
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
              color: root.dndOn ? Color.background : root.colDim
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: dndLabel
              text: root.dndOn ? "DND on" : "DND off"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.dndOn ? Color.background : root.colDim
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

          // Left-click opens/focuses the sending application.
          // Hover reveals a dedicated close (x) button for dismissal.
          MouseArea {
            id: rowHoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusApp(rowCard.modelData.app)
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
              color: rowCard.modelData.urgency === 2 ? Color.urgent : Color.accent
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
        text: "Click to open app · Hover ✕ to dismiss · Esc closes"
        font.family: root.bar ? root.bar.fontFamily : ""
        color: Qt.darker(root.colForeground, 1.55)
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
