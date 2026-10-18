import QtQuick
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

/**
 * The face of an app group: a plate in the group's shape and colour with a
 * 2x2 mosaic of its members. One face is the whole tile of a small group and
 * the mini-group spot of an extended one.
 *
 * `shape` is one of rounded | squircle | circle | cookie | clover; the last
 * two are MaterialShapes and keep their mosaic inside the shape's body.
 */
Item {
    id: root
    property var apps: []
    property string shape: "rounded"
    property color fill: Appearance.m3colors.m3surfaceContainerHigh

    readonly property bool material: root.shape === "cookie" || root.shape === "clover"
    readonly property real mosaicIcon: root.width * (root.material || root.shape === "circle" ? 0.31 : 0.38)

    Rectangle {
        anchors.fill: parent
        visible: !root.material
        radius: root.shape === "circle" ? width / 2
            : root.shape === "squircle" ? width * 0.3 : Appearance.rounding.normal
        color: root.fill
    }
    Loader {
        anchors.fill: parent
        active: root.material
        sourceComponent: MaterialShape {
            shape: root.shape === "clover" ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie9Sided
            color: root.fill
        }
    }
    Grid {
        anchors.centerIn: parent
        columns: 2
        spacing: root.width * 0.07
        Repeater {
            model: root.apps.slice(0, 4)
            delegate: IconImage {
                required property var modelData
                implicitSize: root.mosaicIcon
                mipmap: true
                source: DesktopShortcuts.iconSource(modelData.icon, "image-missing")
            }
        }
    }
}
