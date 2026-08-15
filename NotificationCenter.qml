// Native Omarchy notification center. It only consumes the first-party
// omarchy.notifications service; it never starts or configures a daemon.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by shell.qml when the panel Loader creates this item.
  property var shell: null
  property bool opened: false
  property string query: ""
  property var filteredRows: []
  property var historyRows: []
  readonly property var notifications: shell && shell.firstPartyServiceFor
    ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property int liveCount: notifications && notifications.popupModel
    ? notifications.popupModel.count : 0
  // Service.qml's persistent history is one JSON file per archived popup in
  // this directory. Reading it never touches popupModel and therefore never
  // replays a notification or creates a normal Omarchy popup.
  readonly property string historyDir: notifications && notifications.historyDir
    ? String(notifications.historyDir) : ""

  function formatTimestamp(ms) {
    var date = new Date(Number(ms) || Date.now())
    var now = new Date()
    var sameDay = date.getFullYear() === now.getFullYear()
      && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
    var time = date.toLocaleTimeString(Qt.locale(), "hh:mm")
    return sameDay ? time : date.toLocaleDateString(Qt.locale(), "MMM d") + " · " + time
  }

  function rowMatches(row) {
    var needle = query.trim().toLowerCase()
    if (needle === "") return true
    var haystack = [row.app, row.summary, row.body].join(" ").toLowerCase()
    return haystack.indexOf(needle) >= 0
  }

  function rebuildRows() {
    var rows = []
    for (var h = 0; h < historyRows.length; ++h) {
      var history = historyRows[h]
      if (!rowMatches(history)) continue
      rows.push({
        sourceIndex: -1,
        isLive: false,
        app: history.app,
        summary: history.summary,
        body: history.body,
        glyph: history.glyph,
        urgency: history.urgency,
        timestamp: history.timestamp
      })
    }
    var model = notifications ? notifications.popupModel : null
    if (!model) { filteredRows = rows; return }
    // Live rows are appended after history so the current popup state is
    // visible without replacing or mutating the service's model.
    for (var i = 0; i < model.count; ++i) {
      var row = model.get(i)
      if (!row || !rowMatches(row)) continue
      // Copy only public snapshot data; Notification QObjects themselves
      // deliberately never leave Omarchy's first-party service.
      rows.push({
        sourceIndex: i,
        isLive: true,
        app: String(row.app || "Unknown application"),
        summary: String(row.summary || "Notification"),
        body: String(row.body || ""),
        glyph: String(row.glyph || ""),
        urgency: Number(row.urgency || 1),
        timestamp: Number(row.timestamp || 0)
      })
    }
    filteredRows = rows
  }

  function open(payloadJson) {
    opened = true
    query = ""
    refreshHistory()
    rebuildRows()
    Qt.callLater(function() { if (opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    query = ""
  }

  function dismiss(row) {
    if (row && row.isLive && notifications && typeof notifications.dismissPopup === "function")
      notifications.dismissPopup(row.sourceIndex)
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
          app: String(value.app || "Unknown application"),
          summary: String(value.summary || "Notification"),
          body: String(value.body || ""),
          glyph: String(value.glyph || ""),
          urgency: Number(value.urgency === undefined ? 1 : value.urgency),
          timestamp: Number(value.timestamp || 0)
        })
      } catch (error) {
        // A torn write is ignored, matching the first-party parser.
      }
    }
    parsed.sort(function(a, b) { return b.timestamp - a.timestamp })
    historyRows = parsed.slice(0, notifications && notifications.historyLimit
      ? Number(notifications.historyLimit) : 10)
    rebuildRows()
  }

  function refreshHistory() {
    if (!historyDir || historyReader.running) return
    historyReader.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", historyDir]
    historyReader.running = true
  }

  function clearAll() {
    if (!notifications) return
    if (typeof notifications.clearPopups === "function") notifications.clearPopups()
    if (typeof notifications.clearHistory === "function") notifications.clearHistory()
    historyRows = []
    rebuildRows()
  }

  onQueryChanged: rebuildRows()

  Timer {
    interval: 500
    repeat: true
    running: root.opened
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

  Connections {
    target: root.notifications ? root.notifications.popupModel : null
    function onCountChanged() { root.rebuildRows() }
    function onDataChanged() { root.rebuildRows() }
    function onRowsInserted() { root.rebuildRows() }
    function onRowsRemoved() { root.rebuildRows() }
    function onModelReset() { root.rebuildRows() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shavanced.notification-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Input-only outside-click surface. No opaque fullscreen overlay is
    // painted; only the compact notification card is visible.
    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(500), Math.max(300, panel.width - Style.gapsOut * 2))
      height: Math.min(Style.space(680), Math.max(180, panel.height - Style.gapsOut * 2))
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.gapsOut
      anchors.topMargin: Style.gapsOut
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      clip: true

      // Prevent clicks inside the card from reaching the outside-dismiss
      // surface behind it.
      MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            searchField.forceActiveFocus()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
            root.query = ""
            event.accepted = true
          } else if (event.key === Qt.Key_Delete && list.currentIndex >= 0) {
            root.dismiss(root.filteredRows[list.currentIndex])
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            list.currentIndex = Math.min(root.filteredRows.length - 1, list.currentIndex + 1)
            list.positionViewAtIndex(list.currentIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            list.currentIndex = Math.max(0, list.currentIndex - 1)
            list.positionViewAtIndex(list.currentIndex, ListView.Contain)
            event.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: "Notifications"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.liveCount === 1 ? "1 notification" : root.liveCount + " notifications"
              color: Qt.darker(Color.foreground, 1.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Button {
              iconText: "󰅖"
              tooltipText: "Close (Esc)"
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(4)
              focusable: true
              onClicked: root.close()
            }
          }

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search notifications (Ctrl+F)"
            text: root.query
            onTextEdited: root.query = text
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: root.query.trim() === "" ? "Recent and live notifications" : root.filteredRows.length + " matching notifications"
              color: Qt.darker(Color.foreground, 1.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Button {
              text: "Clear all"
              iconText: "󰆴"
              tooltipText: "Dismiss live notifications and clear saved history"
              focusable: true
              onClicked: root.clearAll()
            }
          }

          ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(8)
            model: root.filteredRows
            currentIndex: count > 0 ? Math.min(currentIndex < 0 ? 0 : currentIndex, count - 1) : -1
            ScrollBar.vertical: ScrollBar { }

            delegate: BorderSurface {
              id: notificationRow
              required property var modelData
              width: list.width - (list.ScrollBar.vertical.visible ? list.ScrollBar.vertical.width + Style.space(4) : 0)
              implicitHeight: rowLayout.implicitHeight + Style.space(18)
              radius: Style.cornerRadius
              color: ListView.isCurrentItem
                ? Style.selectedFillFor(Color.foreground, Color.accent)
                : Color.notifications.background
              borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(1)))

              MouseArea {
                anchors.fill: parent
                onClicked: list.currentIndex = index
              }

              RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.margins: Style.space(9)
                spacing: Style.space(9)

                Text {
                  Layout.alignment: Qt.AlignTop
                  visible: notificationRow.modelData.glyph !== ""
                  text: notificationRow.modelData.glyph
                  color: notificationRow.modelData.urgency === 2 ? Color.urgent : Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)
                  RowLayout {
                    Layout.fillWidth: true
                    Text {
                      Layout.fillWidth: true
                      text: notificationRow.modelData.app
                      color: Qt.darker(Color.foreground, 1.35)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                    Text {
                      text: root.formatTimestamp(notificationRow.modelData.timestamp)
                      color: Qt.darker(Color.foreground, 1.5)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Text {
                    Layout.fillWidth: true
                    text: notificationRow.modelData.summary
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }
                  Text {
                    Layout.fillWidth: true
                    visible: notificationRow.modelData.body !== ""
                    text: notificationRow.modelData.body
                    textFormat: Text.PlainText
                    color: Qt.darker(Color.foreground, 1.2)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }
                }
                Button {
                  Layout.alignment: Qt.AlignTop
                  iconText: "󰅖"
                  tooltipText: "Dismiss notification"
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(3)
              visible: notificationRow.modelData.isLive
              onClicked: root.dismiss(notificationRow.modelData)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: list.count === 0
              text: root.query.trim() === "" ? "No notifications" : "No matching notifications"
              color: Qt.darker(Color.foreground, 1.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Esc closes · Ctrl+F searches · ↑/↓ selects · Delete dismisses"
            color: Qt.darker(Color.foreground, 1.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
