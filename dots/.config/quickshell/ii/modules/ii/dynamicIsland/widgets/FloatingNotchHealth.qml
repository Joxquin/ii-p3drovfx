pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * "zeron.service failed" and why, with the fix as the button. A click elsewhere on the
 * strip opens System Health on that finding.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.health : null;
    }
    readonly property var payload: root.source ? root.source.payload : null
    readonly property var finding: root.payload?.finding ?? null
    readonly property int more: Number(root.payload?.more ?? 0)
    readonly property var fix: HealthService.primaryFix(root.finding)
    property bool working: false

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const id = root.finding?.id ?? "";
            root.source?.dismiss();
            HealthService.openFinding(id);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            shape: root.finding?.kind === "crash" ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie9Sided
            text: root.finding?.kind === "crash" ? "heart_broken" : "error"
            iconSize: 18
            padding: 7
            color: Appearance.colors.colErrorContainer
            colSymbol: Appearance.colors.colOnErrorContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.finding ? (root.more > 0 ? Translation.tr("%1 and %2 more").arg(HealthText.title(root.finding)).arg(root.more) : HealthText.title(root.finding)) : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: root.finding ? HealthText.detail(root.finding, Date.now()) : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            visible: root.fix !== null
            implicitHeight: 34
            implicitWidth: fixLabel.implicitWidth + 24
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colErrorContainer
            colBackgroundHover: Appearance.colors.colErrorContainerHover
            colRipple: Appearance.colors.colErrorContainerActive
            enabled: !root.working
            onClicked: {
                root.working = true;
                const id = root.finding.id;
                HealthService.runPrimaryFix(id, () => {
                    root.working = false;
                    root.source?.dismiss();
                });
                // A verb with no reply (reboot) or a dismissed polkit prompt must not
                // leave the strip stuck in "working".
                if (root.fix?.verb === "reboot")
                    root.source?.dismiss();
            }

            contentItem: StyledText {
                id: fixLabel
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.working ? Translation.tr("Working…") : (root.fix?.label ?? "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }
}
