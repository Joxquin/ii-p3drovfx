import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The compact style's row of icon buttons on top of a menu: the entries the
 * user placed in the bar (ContextMenus.arrange's `bar`), each one square,
 * named by a tooltip. The buttons share the card's width; the bar's natural
 * width is what it needs at the minimum size, so the card can fit it.
 */
Item {
    id: root

    property var entries: []
    property real hostRadius: Appearance.rounding.windowRounding
    property real hostPadding: 6
    signal activated(var entry, Item button)

    readonly property real buttonSize: 36
    readonly property real spacing: 4
    readonly property real radius: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostPadding)

    visible: root.entries.length > 0
    implicitHeight: root.visible ? root.buttonSize : 0
    implicitWidth: root.entries.length * root.buttonSize + Math.max(0, root.entries.length - 1) * root.spacing

    RowLayout {
        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            model: root.entries

            delegate: Rectangle {
                id: button
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: root.buttonSize
                radius: mouse.pressed ? Math.max(Appearance.rounding.verysmall, root.radius - 4) : root.radius
                color: mouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                    : mouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
                    : Appearance.colors.colSurfaceContainerHigh

                Behavior on color {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on radius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: button.modelData.symbol ?? ""
                    iconSize: 19
                    fill: mouse.containsMouse ? 1 : 0
                    color: button.modelData.destructive ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activated(button.modelData, button)
                }

                StyledToolTip {
                    requireOverlay: false
                    extraVisibleCondition: mouse.containsMouse
                    text: button.modelData.title ?? ""
                }
            }
        }
    }
}
