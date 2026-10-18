import QtQuick
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects as GE
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * An extended app group: a 2x2 block of spots. The first three members sit
 * in the first three as full-size icons, opened directly by a click; the
 * last spot is the small group (a mosaic of the next four members) that
 * opens the same popup a small group does.
 *
 * It only draws. The tile owns the gesture and asks `spotAt()` which spot a
 * click landed on, so dragging, selection and the context menu stay the
 * tile's, exactly as for every other icon.
 */
Item {
    id: root
    // The layer, for its icon metrics and label style.
    required property var host
    required property var entry
    required property string shape
    required property color fill
    // The text colour that reads on `fill`.
    required property color onFill
    // Where the pointer is, in this item's coordinates, and whether it is.
    property point hoverPoint: Qt.point(0, 0)
    property bool hovering: false

    readonly property var apps: root.entry.apps ?? []
    readonly property real cw: root.width / 2
    readonly property real ch: root.height / 2

    // 0..3, row by row.
    function spotAt(x, y) {
        return (y >= root.ch ? 2 : 0) + (x >= root.cw ? 1 : 0);
    }
    readonly property int hoveredSpot: root.hovering ? root.spotAt(root.hoverPoint.x, root.hoverPoint.y) : -1

    // The plate: a rounded block, or a circle's worth of rounding. The
    // cookie shapes are for the one-cell face; a block this size would
    // clip its own spots.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 6
        radius: root.shape === "circle" ? Math.min(width, height) * 0.32
            : root.shape === "squircle" ? Math.min(width, height) * 0.22 : Appearance.rounding.large
        color: root.fill
    }
    // The hovered spot's own plate.
    Rectangle {
        readonly property int spot: Math.max(0, root.hoveredSpot)
        x: (spot % 2) * root.cw + 10
        y: Math.floor(spot / 2) * root.ch + 10
        width: root.cw - 20
        height: root.ch - 20
        radius: Appearance.rounding.normal
        color: Qt.alpha(root.onFill, 0.12)
        opacity: root.hoveredSpot >= 0 ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    component Spot: Item {
        id: spot
        property string label: ""
        default property alias face: faceHost.data
        width: root.cw
        height: root.ch
        Column {
            anchors.centerIn: parent
            width: parent.width - 12
            spacing: root.host.labelGap
            Item {
                id: faceHost
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.host.iconSize
                height: root.host.iconSize
            }
            StyledText {
                width: parent.width
                visible: (root.host.options.labels ?? "always") !== "never"
                text: spot.label
                font.family: Appearance.font.family.main
                font.variableAxes: root.host.labelAxes
                font.pixelSize: root.host.labelSize
                color: root.onFill
                elide: Text.ElideRight
                maximumLineCount: 1
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Repeater {
        model: 3
        delegate: Spot {
            id: appSpot
            required property int index
            readonly property var app: root.apps[index] ?? null
            x: (index % 2) * root.cw
            y: Math.floor(index / 2) * root.ch
            label: app ? (app.name || app.id) : ""
            IconImage {
                anchors.fill: parent
                visible: appSpot.app !== null
                mipmap: true
                source: appSpot.app ? DesktopShortcuts.iconSource(appSpot.app.icon, "image-missing") : ""
            }
            // An empty spot is a faint dashed-feeling hole, not nothing.
            Rectangle {
                anchors.fill: parent
                visible: appSpot.app === null
                radius: width * 0.25
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(root.onFill, 0.2)
            }
        }
    }
    Spot {
        x: root.cw
        y: root.ch
        label: root.entry.name || root.entry.id || ""
        DesktopGroupFace {
            anchors.fill: parent
            apps: root.apps.slice(3, 7)
            shape: root.shape === "circle" || root.shape === "cookie" || root.shape === "clover" ? root.shape : "rounded"
            fill: Qt.alpha(root.onFill, 0.1)
        }
    }
}
