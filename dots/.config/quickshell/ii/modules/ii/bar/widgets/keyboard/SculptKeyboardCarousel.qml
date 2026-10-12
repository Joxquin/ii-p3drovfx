pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `carousel` variant of the Sculpt keyboard layout — an M3 Expressive carousel.
 *
 * The current layout is the large item; the one a click switches to waits
 * beside it as the small item, cropped by its far edge. Switching moves the
 * carousel: the old code slides out of the large item, the new one slides in
 * from the side the small item sits on, and the small item takes the layout
 * after that. With one layout there is no small item.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property var codes: []
    property int currentIndex: 0

    readonly property bool hasMore: root.codes.length > 1
    readonly property string currentCode: root.codes[root.currentIndex] ?? ""
    readonly property string nextCode: root.hasMore ? root.codes[(root.currentIndex + 1) % root.codes.length] : ""

    readonly property real gap: 3
    readonly property real heroLength: root.vertical
        ? Math.round(root.thickness * 0.92)
        : Math.max(Math.round(root.thickness * 1.25), Math.ceil(codeMetrics.implicitWidth) + 16)
    readonly property real peekLength: root.hasMore ? Math.round(root.thickness * (root.vertical ? 0.6 : 0.55)) : 0
    readonly property real itemRadius: Appearance.rounding.scale === 0 ? 0 : Math.round(root.thickness * 0.3)

    implicitWidth: root.vertical ? root.thickness : root.heroLength + (root.hasMore ? root.gap + root.peekLength : 0)
    implicitHeight: root.vertical ? root.heroLength + (root.hasMore ? root.gap + root.peekLength : 0) : root.thickness

    // `shownCode` trails the input by one change so the outgoing code is still
    // there to slide away; `travel` runs 1 → 0 on every switch.
    property string shownCode: root.currentCode
    property string outgoingCode: ""
    property real travel: 0

    onCurrentCodeChanged: {
        if (root.currentCode === root.shownCode)
            return;
        root.outgoingCode = root.shownCode;
        root.shownCode = root.currentCode;
        if (Appearance.reducedMotion || root.outgoingCode === "") {
            root.travel = 0;
            return;
        }
        slide.restart();
    }

    NumberAnimation {
        id: slide
        target: root
        property: "travel"
        from: 1
        to: 0
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    StyledText {
        id: codeMetrics
        visible: false
        text: root.shownCode
        font.family: Appearance.font.family.main
        font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.5 : 0.56))
        font.variableAxes: ({
            "wght": 800,
            "wdth": 60,
            "ROND": 100
        })
    }

    Rectangle {
        id: hero
        width: root.vertical ? root.thickness : root.heroLength
        height: root.vertical ? root.heroLength : root.thickness
        radius: Math.min(root.itemRadius, Math.min(width, height) / 2)
        color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
        clip: true

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(hero)
        }
        Behavior on width {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.barResize.numberAnimation.createObject(hero)
        }

        readonly property real span: root.vertical ? hero.height : hero.width

        StyledText {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.vertical ? 0 : hero.span * (root.travel - 1)
            anchors.verticalCenterOffset: root.vertical ? hero.span * (root.travel - 1) : 0
            visible: root.travel > 0
            text: root.outgoingCode
            font: codeMetrics.font
            color: root.tones.colOnBackground
        }

        StyledText {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.vertical ? 0 : hero.span * root.travel
            anchors.verticalCenterOffset: root.vertical ? hero.span * root.travel : 0
            text: root.shownCode
            font: codeMetrics.font
            color: root.tones.colOnBackground
        }
    }

    Rectangle {
        id: peek
        visible: root.hasMore
        x: root.vertical ? 0 : hero.width + root.gap
        y: root.vertical ? hero.height + root.gap : 0
        width: root.vertical ? root.thickness : root.peekLength
        height: root.vertical ? root.peekLength : root.thickness
        radius: Math.min(root.itemRadius, Math.min(width, height) / 2)
        color: root.tones.colBackgroundVariant
        clip: true

        // Set at the large item's size and pinned to the edge that faces it,
        // so the code is cut by the far edge rather than shrunk to fit.
        StyledText {
            x: root.vertical ? Math.round((peek.width - width) / 2) : Math.round(peek.width * 0.28)
            y: root.vertical ? Math.round(peek.height * 0.12) : Math.round((peek.height - height) / 2)
            text: root.nextCode
            font: codeMetrics.font
            color: root.tones.colOnBackgroundVariant
            opacity: 0.85
        }
    }
}
