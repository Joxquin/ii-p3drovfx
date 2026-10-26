import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: indicatorContainer
    // enableShapeMask used to hide this indicator with nothing drawing running
    // state in its place, so a running app and an idle one looked identical.
    // The parent fork shows it either way.
    visible: root.appIsRunning

    readonly property int totalCount: root.appToplevel ? root.appToplevel.toplevels.length : 0
    readonly property string indicatorStyle: Config.options.dock.runningIndicatorStyle
    readonly property int maxVisible: Config.options.dock.runningIndicatorMaxVisible
    readonly property int visibleCount: Math.min(totalCount, maxVisible)

    readonly property bool appIsActive: (root.appToplevel?.toplevels ?? [])
        .some(toplevel => toplevel.activated === true)

    readonly property real indicatorWidth: Config.options.dock.runningIndicatorWidth
    readonly property real indicatorHeight: Config.options.dock.runningIndicatorHeight
    // A dot is always as wide as it is tall; a pill only stays wide while the
    // windows fit, and collapses to circles past that.
    readonly property real baseDotW: (indicatorStyle === "pill" && totalCount <= maxVisible)
        ? indicatorWidth
        : indicatorHeight
    readonly property real baseDotH: indicatorHeight

    readonly property real dotSpacing: 3
    readonly property real pitchX: root.isVertical ? 0 : (baseDotW + dotSpacing)
    readonly property real pitchY: root.isVertical ? (baseDotH + dotSpacing) : 0
    readonly property real indicatorMargin: Math.max(1, (root.dockContent?.dotMarginV ?? 1) * 0.35)

    width: root.isVertical ? baseDotW : (visibleCount * baseDotW + Math.max(0, visibleCount - 1) * dotSpacing)
    height: root.isVertical ? (visibleCount * baseDotH + Math.max(0, visibleCount - 1) * dotSpacing) : baseDotH

    // Keep the indicator on the screen-edge side of the icon in every orientation.
    // Same class of bug as the dock tray: conditional anchors are evaluated
    // one by one, so an orientation flip overlaps opposite edges, over-
    // constrains the group and permanently removes the width/height bindings.
    // AnchorChanges swaps the whole group atomically.
    state: root.dockPos
    states: [
        State {
            name: "top"
            AnchorChanges { target: indicatorContainer; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter }
        },
        State {
            name: "bottom"
            AnchorChanges { target: indicatorContainer; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }
        },
        State {
            name: "left"
            AnchorChanges { target: indicatorContainer; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
        },
        State {
            name: "right"
            AnchorChanges { target: indicatorContainer; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
        }
    ]

    anchors.bottomMargin: indicatorMargin
    anchors.topMargin: indicatorMargin
    anchors.leftMargin: indicatorMargin
    anchors.rightMargin: indicatorMargin

    Repeater {
        model: indicatorContainer.visibleCount
        delegate: Rectangle {
            width: indicatorContainer.baseDotW
            height: indicatorContainer.baseDotH
            radius: Appearance.rounding.full

            x: root.isVertical ? (indicatorContainer.baseDotW - width) / 2 : (index * indicatorContainer.pitchX)
            y: root.isVertical ? (index * indicatorContainer.pitchY) : 0

            color: indicatorContainer.appIsActive
                ? Appearance.colors.colPrimary
                : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
