import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "shavanced.notification-center"

  // The bar passes its shell object to widgets. This is the existing first-
  // party service, not a second notification daemon.
  readonly property var notificationService: bar && bar.shell && bar.shell.firstPartyServiceFor
    ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property int liveCount: notificationService && notificationService.popupModel
    ? notificationService.popupModel.count : 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂚"
    active: root.liveCount > 0
    tooltipText: root.liveCount > 0 ? root.liveCount + " live notifications" : "Notification Center"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.notificationService)
        root.notificationService.clearPopups()
      else
        Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "shavanced.notification-center", "{}"])
    }
  }

  Text {
    visible: root.liveCount > 0
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.liveCount > 9 ? "9+" : String(root.liveCount)
    color: root.bar ? root.bar.background : Color.background
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
