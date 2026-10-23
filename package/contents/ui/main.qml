import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "ChannelResolver.js" as Resolver

PlasmoidItem {
    id: root

    property int unseen: 0
    property int visibleLimit: 50
    property int totalMatching: 0
    property int totalStoredVideos: 0
    property bool unreadOnly: false
    property bool showChannels: false
    property string infoMessage: ""
    property string formError: ""
    property string channelToRemove: ""
    property int storedChannels: 0
    property string selectedChannelId: ""
    property string selectedChannelName: ""

    Plasmoid.icon: "applications-multimedia"
    toolTipMainText: i18n("YouTube Upload Tracker")
    toolTipSubText: unseen === 0 ? i18n("No unseen uploads") : i18np("%1 unseen upload", "%1 unseen uploads", unseen)

    UploadStore { id: dataStore }
    UploadEngine {
        id: feedEngine
        store: dataStore
        refreshMinutes: Math.max(5, Plasmoid.configuration.refreshMinutes)
        onChanged: root.reload()
        // The outage message is derived from the live scheduler state. Once
        // recovery is confirmed, clear the stale HTTP error from the footer.
        onUpstreamOutageActiveChanged: {
            if (!feedEngine.upstreamOutageActive) root.infoMessage = ""
        }
        onProblem: function(message) { root.infoMessage = message; }
        onManualRefreshFinished: function(errorCount, deferredCount) {
            if (feedEngine.upstreamOutageActive) {
                root.infoMessage = i18n("YouTube feeds appear temporarily unavailable; automatic retry scheduled.")
            } else if (errorCount > 0 && deferredCount > 0) {
                root.infoMessage = i18n("Refresh: %1 error(s), %2 deferred by retry cooldown.", errorCount, deferredCount)
            } else if (errorCount > 0) {
                root.infoMessage = i18n("Refresh finished with %1 error(s). See Channels for details.", errorCount)
            } else if (deferredCount > 0) {
                root.infoMessage = i18n("Refresh complete; %1 channel(s) deferred by retry cooldown.", deferredCount)
            } else {
                root.infoMessage = ""
            }
        }
        onInputError: function(message) { root.formError = message; }
        onChannelAdded: function(title) {
            // Clear only after save succeeds. An asynchronous @handle lookup
            // can fail later; preserve the original input for easy correction.
            channelInput.clear()
            root.infoMessage = i18n("Channel added. Loading its recent videos…")
            root.showChannels = false
        }
    }

    function reload() {
        try {
            var selected = dataStore.videos(visibleLimit, unreadOnly, selectedChannelId);
            videoItems.clear();
            for (var i = 0; i < selected.length; ++i) {
                var v = selected[i];
                videoItems.append({
                    videoId: v.video_id,
                    videoTitle: v.title,
                    channelTitle: v.channel_title,
                    videoUrl: v.url,
                    thumbnailUrl: v.thumbnail_url,
                    publishedMs: Number(v.published_ms),
                    wasSeen: Number(v.seen) !== 0
                });
            }
            var channels = dataStore.allChannels();
            if (selectedChannelId.length > 0 && !channels.some(function(c) { return c.id === selectedChannelId; })) {
                selectedChannelId = "";
                selectedChannelName = "";
                selected = dataStore.videos(visibleLimit, unreadOnly, "");
                videoItems.clear();
                for (var r = 0; r < selected.length; ++r) {
                    var v2 = selected[r];
                    videoItems.append({videoId:v2.video_id, videoTitle:v2.title, channelTitle:v2.channel_title,
                        videoUrl:v2.url, thumbnailUrl:v2.thumbnail_url, publishedMs:Number(v2.published_ms), wasSeen:Number(v2.seen) !== 0});
                }
            }
            channelItems.clear();
            for (var j = 0; j < channels.length; ++j) {
                var c = channels[j];
                channelItems.append({
                    channelId: c.id,
                    channelTitle: c.title === c.id ? Resolver.displayLabel(c.source_url, c.id) : c.title,
                    channelError: c.last_error,
                    lastChecked: Number(c.last_checked_ms),
                    initialized: Number(c.initialized) !== 0,
                    feedEntries: Number(c.last_feed_entries),
                    feedRawEntries: Number(c.last_feed_raw_entries),
                    feedAdded: Number(c.last_feed_added),
                    storedCount: Number(c.stored_count),
                    newestStored: Number(c.newest_stored_ms)
                });
            }
            totalMatching = dataStore.videoTotal(unreadOnly, selectedChannelId);
            totalStoredVideos = dataStore.videoTotal(false);
            unseen = dataStore.unreadCount();
            storedChannels = channels.length;
        } catch(e) {
            infoMessage = i18n("Local storage failed: %1", String(e));
            console.error("YouTube Upload Tracker storage:", e);
        }
    }

    // Allow individual seen/unseen changes without resetting the entire ListView.
    // This preserves the user's scroll position when browsing a long feed.
    function viewChannelUploads(channelId, channelName) {
        selectedChannelId = channelId;
        selectedChannelName = channelName;
        visibleLimit = 50;
        unreadOnly = false; // show both seen and unseen for diagnosis
        showChannels = false;
        reload();
    }

    function setVideoSeenState(videoId, isSeen) {
        try {
            dataStore.setSeenState(videoId, isSeen);
            if (unreadOnly) {
                reload();  // the entry must leave or enter the filtered feed
            } else {
                for (var i = 0; i < videoItems.count; ++i) {
                    if (videoItems.get(i).videoId === videoId) {
                        videoItems.setProperty(i, "wasSeen", isSeen);
                        break;
                    }
                }
                unseen = dataStore.unreadCount();
            }
        } catch (e) {
            infoMessage = i18n("Could not update video status: %1", String(e));
        }
    }

    function openVideo(videoId, url) {
        setVideoSeenState(videoId, true);
        Qt.openUrlExternally(url);
    }

    function formatTime(ms) {
        if (!ms) return i18n("Unknown date");
        var delta = Date.now() - ms;
        if (delta >= 0 && delta < 60000) return i18n("Just now");
        if (delta >= 60000 && delta < 3600000) return i18n("%1m ago", Math.floor(delta / 60000));
        if (delta >= 3600000 && delta < 86400000) return i18n("%1h ago", Math.floor(delta / 3600000));
        if (delta >= 86400000 && delta < 604800000) return i18n("%1d ago", Math.floor(delta / 86400000));
        return new Date(ms).toLocaleDateString(Qt.locale());
    }

    ListModel { id: videoItems }
    ListModel { id: channelItems }

    Component.onCompleted: {
        dataStore.initialize();
        reload();
        feedEngine.tick();
    }

    compactRepresentation: Item {
        id: compact
        implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
        implicitHeight: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.75
            height: width
            source: "applications-multimedia"
        }
        Rectangle {
            visible: root.unseen > 0
            anchors.top: parent.top
            anchors.right: parent.right
            height: Math.max(15, Math.min(parent.height * 0.48, 22))
            width: Math.max(height, countLabel.implicitWidth + 8)
            radius: height / 2
            color: "#cc3333"
            Controls.Label {
                id: countLabel
                anchors.centerIn: parent
                text: root.unseen > 99 ? "99+" : String(root.unseen)
                color: "white"
                font.bold: true
                font.pixelSize: Math.max(9, parent.height * 0.64)
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: root.Plasmoid.expanded = !root.Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 370
        Layout.minimumHeight: 340
        Layout.preferredWidth: 515
        Layout.preferredHeight: 540

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "applications-multimedia"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                Controls.Label {
                    text: i18n("YouTube Uploads")
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.15
                    Layout.fillWidth: true
                }
                Controls.Label {
                    visible: root.unseen > 0
                    text: i18np("%1 new", "%1 new", root.unseen)
                    font.bold: true
                }
                Controls.ToolButton {
                    icon.name: "view-refresh"
                    text: i18n("Refresh")
                    display: Controls.AbstractButton.IconOnly
                    enabled: !feedEngine.manualRefreshActive
                    onClicked: {
                        root.infoMessage = ""
                        feedEngine.refreshAll()
                    }
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: text
                }
                Controls.ToolButton {
                    icon.name: "configure"
                    text: i18n("Configure")
                    display: Controls.AbstractButton.IconOnly
                    onClicked: plasmoid.action("configure").trigger()
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: text
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Controls.TabButton {
                    text: i18n("Uploads")
                    checked: !root.showChannels
                    onClicked: root.showChannels = false
                    Layout.fillWidth: true
                }
                Controls.TabButton {
                    text: i18n("Channels (%1)", root.storedChannels)
                    checked: root.showChannels
                    onClicked: root.showChannels = true
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                visible: !root.showChannels && root.selectedChannelId.length > 0
                Layout.fillWidth: true
                Controls.Label {
                    Layout.fillWidth: true
                    text: i18n("Channel: %1", root.selectedChannelName)
                    elide: Text.ElideRight
                }
                Controls.Button {
                    text: i18n("Show all channels")
                    onClicked: {
                        root.selectedChannelId = "";
                        root.selectedChannelName = "";
                        root.visibleLimit = 50;
                        root.reload();
                    }
                }
            }

            RowLayout {
                visible: !root.showChannels
                Layout.fillWidth: true
                Controls.CheckBox {
                    text: i18n("Unseen only")
                    checked: root.unreadOnly
                    onToggled: {
                        root.unreadOnly = checked
                        root.visibleLimit = 50
                        root.reload()
                    }
                }
                Item { Layout.fillWidth: true }
                Controls.Button {
                    text: i18n("Mark all seen")
                    enabled: root.unseen > 0
                    onClicked: {
                        dataStore.markAllSeen()
                        root.reload()
                    }
                }
                // A single hidden bulk action does not need a separate menu.
                // Keep both status actions directly accessible beside the filter.
                Controls.Button {
                    text: i18n("Mark all unseen")
                    enabled: root.totalStoredVideos > root.unseen
                    onClicked: {
                        dataStore.markAllUnseen()
                        root.reload()
                    }
                }
            }

            Item {
                visible: !root.showChannels
                Layout.fillWidth: true
                Layout.fillHeight: true
                ListView {
                    id: videoList
                    anchors.fill: parent
                    clip: true
                    spacing: 1
                    model: videoItems
                    boundsBehavior: Flickable.StopAtBounds
                    Controls.ScrollBar.vertical: Controls.ScrollBar { id: uploadScrollBar }
                    delegate: Item {
                        // Reserve room for the interactive scrollbar *and* a gutter;
                        // the Seen checkbox must never sit beneath the scroll track.
                        width: Math.max(0, videoList.width - uploadScrollBar.width - Kirigami.Units.smallSpacing * 3)
                        height: 87
                        RowLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing
                            // The open-video action and the status checkbox are
                            // separate sibling controls: changing status must NOT
                            // also open the browser.
                            Controls.ItemDelegate {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                onClicked: root.openVideo(model.videoId, model.videoUrl)
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing * 2
                                    Image {
                                        Layout.preferredWidth: 125
                                        Layout.preferredHeight: 70
                                        source: model.thumbnailUrl
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: 160
                                        sourceSize.height: 90
                                        asynchronous: true
                                        cache: true
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: model.videoTitle
                                            textFormat: Text.PlainText
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            font.bold: !model.wasSeen
                                        }
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: model.channelTitle
                                            elide: Text.ElideRight
                                            opacity: 0.75
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        }
                                        Controls.Label {
                                            text: root.formatTime(model.publishedMs)
                                            opacity: 0.65
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        }
                                    }
                                    Rectangle {
                                        visible: !model.wasSeen
                                        Layout.preferredWidth: 7
                                        Layout.preferredHeight: 7
                                        radius: 4
                                        color: Kirigami.Theme.highlightColor
                                    }
                                }
                            }
                            Controls.CheckBox {
                                Layout.alignment: Qt.AlignVCenter
                                text: i18n("Seen")
                                checked: model.wasSeen
                                onToggled: root.setVideoSeenState(model.videoId, checked)
                                Controls.ToolTip.visible: hovered
                                Controls.ToolTip.text: checked
                                    ? i18n("Mark as unseen") : i18n("Mark as seen")
                            }
                        }
                    }
                    onAtYEndChanged: {
                        if (atYEnd && videoItems.count < root.totalMatching && count > 0) {
                            root.visibleLimit += 50
                            root.reload()
                        }
                    }
                }
                Controls.Label {
                    visible: videoItems.count === 0
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                    text: root.storedChannels === 0
                        ? i18n("No channels followed yet. Open the Channels tab to add one.")
                        : (root.unreadOnly ? i18n("Nothing unseen.") : i18n("No uploads loaded yet. Feeds are checked automatically."))
                }

            }

            ColumnLayout {
                visible: root.showChannels
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Controls.Label {
                    text: i18n("Add a channel")
                    font.bold: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    Controls.TextField {
                        id: channelInput
                        Layout.fillWidth: true
                        placeholderText: i18n("YouTube @handle, channel URL, or UC… ID")
                        onAccepted: {
                            if (!feedEngine.resolvingChannel && text.trim().length > 0) {
                                root.formError = ""
                                feedEngine.add(text)
                            }
                        }
                    }
                    Controls.Button {
                        id: addButton
                        text: feedEngine.resolvingChannel ? i18n("Finding…") : i18n("Add")
                        enabled: !feedEngine.resolvingChannel && channelInput.text.trim().length > 0
                        onClicked: {
                            root.formError = ""
                            feedEngine.add(channelInput.text)
                        }
                    }
                }
                Controls.Label {
                    Layout.fillWidth: true
                    visible: root.formError.length > 0
                    color: Kirigami.Theme.negativeTextColor
                    text: root.formError
                    wrapMode: Text.WordWrap
                }
            }
            ListView {
                id: channelList
                visible: root.showChannels
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: channelItems
                Controls.ScrollBar.vertical: Controls.ScrollBar {}
                delegate: Controls.ItemDelegate {
                    width: channelList.width
                    height: 76
                    onClicked: root.viewChannelUploads(model.channelId, model.channelTitle)
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: i18n("Show uploads for %1", model.channelTitle)
                    contentItem: RowLayout {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                Layout.fillWidth: true
                                text: model.channelTitle
                                elide: Text.ElideRight
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: model.channelError ? i18n("Error: %1", model.channelError)
                                     : (!model.initialized ? i18n("Awaiting first check")
                                        : i18n("Last checked: %1", root.formatTime(model.lastChecked)))
                                opacity: 0.7
                                elide: Text.ElideRight
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: model.feedEntries < 0
                                      ? i18n("Feed details available after next check")
                                      : i18n("Feed: %1/%2 entries · %3 added · %4 stored", model.feedEntries, model.feedRawEntries, model.feedAdded, model.storedCount)
                                Controls.ToolTip.visible: hovered
                                Controls.ToolTip.text: text
                                opacity: 0.7
                                elide: Text.ElideRight
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }
                        Controls.ToolButton {
                            icon.name: "view-list-details"
                            text: i18n("Show uploads")
                            display: Controls.AbstractButton.IconOnly
                            onClicked: root.viewChannelUploads(model.channelId, model.channelTitle)
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.text: text
                        }
                        Controls.ToolButton {
                            icon.name: "edit-delete"
                            text: i18n("Remove")
                            display: Controls.AbstractButton.IconOnly
                            onClicked: {
                                root.channelToRemove = model.channelId
                                removeDialog.open()
                            }
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.text: text
                        }
                    }
                }
            }

            Controls.Label {
                Layout.fillWidth: true
                visible: feedEngine.manualRefreshActive || root.infoMessage.length > 0 || feedEngine.upstreamOutageActive
                text: feedEngine.manualRefreshActive
                    ? i18n("Refreshing channels: %1 remaining…", feedEngine.manualRefreshRemaining)
                    : feedEngine.upstreamOutageActive
                        ? i18n("YouTube feeds temporarily unavailable; retrying automatically.")
                        : root.infoMessage
                elide: Text.ElideRight
                opacity: 0.7
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
            Controls.Label {
                Layout.fillWidth: true
                text: root.storedChannels === 0 ? i18n("Follow channels to begin") :
                      feedEngine.inFlightCount > 0 ? i18n("Checking %1 feed(s)…", feedEngine.inFlightCount) :
                      i18n("%1 channel(s) followed", root.storedChannels)
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
        }

        Controls.Dialog {
            id: removeDialog
            title: i18n("Remove channel?")
            modal: true
            standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
            anchors.centerIn: parent
            Controls.Label {
                width: 275
                wrapMode: Text.WordWrap
                text: i18n("Remove this channel and its stored uploads from the widget?")
            }
            onAccepted: feedEngine.forgetChannel(root.channelToRemove)
        }
    }
}
