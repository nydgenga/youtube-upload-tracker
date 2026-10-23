import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page
    property alias cfg_refreshMinutes: minutes.value

    Kirigami.FormLayout {
      Controls.SpinBox {
        id: minutes
        Kirigami.FormData.label: i18n("Check every (minutes):")
        from: 5
        to: 120
        stepSize: 5
        editable: true
    }
      Controls.Label {
        text: i18n("Public channel feeds are checked without signing in. Channels can be added or removed from the widget popup.")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    }
}
