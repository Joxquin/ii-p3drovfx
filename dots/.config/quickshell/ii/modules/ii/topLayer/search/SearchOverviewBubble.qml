pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * The connect-mode overview, pulled out of the search drop as a second drop.
 *
 * The island's AuxiliaryBubbleSurface turned downwards. One linear clock drives
 * everything through damped responses: a small pill hidden in the search's lower edge
 * travels out with a liquid neck still joining it to the search, the neck pinches off
 * as it reaches its place, and only then does it spread into the overview's card. Every
 * value is a pure function of the clock, so calling it back half way retraces the same
 * path, and the resting pose is exact.
 *
 * Nothing here fades. The topLayer is blurred by the compositor with an `ignore_alpha`
 * threshold, and a fade sweeps every pixel's alpha across it: the blur behind the grid
 * switched on in one frame somewhere in the middle of the old entrance. The field and
 * the content mask both have hard edges, so a pixel is either the overview or nothing
 * and the blur moves with the edge.
 *
 * The overview is drawn hosted (no panel, shadow or margin of its own); this item paints
 * its panel colour and radius instead, so at rest it looks as it did. Children are the
 * overview's content, laid out at the overview's resting size.
 *
 * Geometry comes in the host's coordinates; `away` is +1 when the search grows down
 * from a top bar and -1 for a bottom bar.
 */
Item {
    id: root

    default property alias contents: contentHost.data

    /** Out and settled beside the search, or tucked back into it. */
    property bool open: false
    /** A gesture owns the clock: it follows the search's while the fingers hold it. */
    property bool held: false
    property real heldProgress: 0
    property bool animationsEnabled: true
    property int openDuration: 700
    property int closeDuration: 340

    // The search drop: the body the overview hangs from.
    property real barEdgeY: 0
    property real away: 1
    property real searchCenterX: 0
    property real searchBodyWidth: 0
    property real searchHeight: 0
    property real searchRadius: 0
    /** Where the search will rest; the overview's place is measured from it. */
    property real searchRestHeight: 0
    property color searchColor: "black"

    // The overview at rest.
    property real overviewCenterX: 0
    property real overviewWidth: 0
    property real overviewHeight: 0
    property real overviewRadius: 0
    property real gap: 10
    property color panelColor: "black"

    // ── The clock ────────────────────────────────────────────────────────────
    property real clock: 0
    readonly property bool active: root.open || root.clock > 0.001
    readonly property bool atRest: !root.held && !clockAnim.running && (root.clock <= 0 || root.clock >= 1)

    /**
     * The earliest clock at which the drop looks settled: the neck has let go, the
     * travel is within a pixel and the card has spread. A recall starts from here, not
     * from 1, so there is no dead time before it moves.
     */
    readonly property real settledClock: 0.86

    onOpenChanged: root._restart()
    onHeldChanged: {
        if (root.held)
            clockAnim.stop();
        else
            root._restart();
    }

    function _restart() {
        if (root.held)
            return;
        clockAnim.stop();
        if (!root.animationsEnabled) {
            root.clock = root.open ? 1 : 0;
            return;
        }
        if (!root.open)
            root.clock = Math.min(root.clock, root.settledClock);
        const target = root.open ? 1 : 0;
        const span = Math.abs(target - root.clock);
        if (span <= 0.0001) {
            root.clock = target;
            return;
        }
        clockAnim.to = target;
        clockAnim.duration = Math.max(1, Math.round((root.open ? root.openDuration : root.closeDuration * (1 / root.settledClock)) * span));
        clockAnim.start();
    }

    NumberAnimation {
        id: clockAnim
        target: root
        property: "clock"
        easing.type: Easing.Linear
    }

    Binding {
        target: root
        property: "clock"
        value: Math.max(0, Math.min(1, root.heldProgress))
        when: root.held
        restoreMode: Binding.RestoreNone
    }

    // ── The motion ───────────────────────────────────────────────────────────
    function smoothstep(value) {
        const t = Math.max(0, Math.min(1, value));
        return t * t * (3 - 2 * t);
    }
    function stage(start, end) {
        return root.smoothstep((root.clock - start) / (end - start));
    }
    function mix(from, to, amount) {
        return from + (to - from) * amount;
    }
    // A damped response normalised at the end point (see AuxiliaryBubbleSurface).
    // overshoot = exp(-pi * decay / frequency).
    function response(delay, decay, frequency) {
        const phase = decay / frequency;
        const time = Math.max(0, Math.min(1, root.clock) - delay);
        const end = 1 - delay;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency * time));
        const terminal = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency * end));
        return value / terminal;
    }

    /** The pill it leaves the search as: a drop of the search's own width class. */
    readonly property real seedHeight: Math.min(root.overviewHeight, 40)
    readonly property real seedWidth: Math.min(root.overviewWidth, Math.max(140, root.searchBodyWidth * 0.5))

    /** Grows out of nothing inside the search before it shows, so it never pops. */
    readonly property real appear: root.stage(0, 0.14)
    /** Out of the search to its place, about 2% past it. */
    readonly property real travel: root.response(0.02, 6.6, 5.6)
    /** The neck lets go as the drop arrives; the card spreads once it is free. */
    readonly property real release: root.stage(0.3, 0.5)
    readonly property real spread: root.response(0.3, 6.8, 5.8)

    /** Distance from the bar's edge to the drop's near edge. */
    readonly property real restTop: root.searchRestHeight + root.gap
    readonly property real startTop: root.searchHeight - root.seedHeight * 0.85
    readonly property real liveTop: root.mix(root.startTop, root.restTop, root.travel)
    readonly property real liveCenterX: root.mix(root.searchCenterX, root.overviewCenterX, root.travel)
    readonly property real liveWidth: Math.max(0, root.mix(root.seedWidth, root.overviewWidth, root.spread) * root.appear)
    readonly property real liveHeight: Math.max(0, root.mix(root.seedHeight, root.overviewHeight, root.spread) * root.appear)
    readonly property real liveRadius: Math.min(root.mix(root.seedHeight / 2, root.overviewRadius, root.spread),
        root.liveHeight / 2, root.liveWidth / 2)

    /**
     * The contents open from the drop's middle as it spreads: a slice of the grid in
     * a travelling pill read as a clipped window, not as a drop. An inset, not a fade.
     */
    readonly property real contentReveal: root.stage(0.26, 0.62)
    readonly property real contentInset: (1 - root.contentReveal) * Math.max(root.liveWidth, root.liveHeight) / 2

    readonly property real neckBlend: {
        // Never thicker than the ends it joins: the largest blend whose joint stays
        // within the smaller end's radius (see AuxiliaryBubbleSurface.neckBlend).
        const bodyCap = Math.min(root.searchRadius, root.searchHeight / 2);
        const dropCap = Math.min(root.liveRadius, root.liveHeight / 2);
        const distance = Math.abs((root.liveTop + dropCap) - (root.searchHeight - bodyCap));
        const radius = Math.max(0, Math.min(bodyCap, dropCap));
        const flush = 4 * (Math.sqrt(radius * radius + distance * distance / 4) - radius);
        return Math.min(flush, root.seedHeight * 0.8) * (1 - root.release);
    }

    visible: root.clock > 0.001 && root.liveHeight > 0.25

    // ── The surface ──────────────────────────────────────────────────────────
    /** Room for the neck and the overshoot around both shapes. */
    readonly property real bleed: 32

    function premultiplied(color) {
        return Qt.vector4d(color.r * color.a, color.g * color.a, color.b * color.a, color.a);
    }

    ShaderEffect {
        id: field
        // A frame whose y grows away from the bar; flipped for a bottom bar.
        readonly property real spanLeft: Math.min(root.searchCenterX - root.searchBodyWidth / 2,
            root.overviewCenterX - root.overviewWidth / 2) - root.bleed
        readonly property real spanRight: Math.max(root.searchCenterX + root.searchBodyWidth / 2,
            root.overviewCenterX + root.overviewWidth / 2) + root.bleed
        x: Math.floor(spanLeft)
        width: Math.ceil(spanRight - x)
        height: Math.ceil(Math.max(root.restTop + root.overviewHeight * 1.05,
            root.liveTop + root.liveHeight) + root.bleed)
        y: root.away > 0 ? root.barEdgeY : root.barEdgeY - height
        transform: Scale {
            yScale: root.away > 0 ? 1 : -1
            origin.y: field.height / 2
        }

        property vector2d resolution: Qt.vector2d(width, height)
        property vector4d bodyColor: root.premultiplied(root.searchColor)
        property vector4d bubbleColor: root.premultiplied(root.panelColor)
        // The search reaches above the bar's edge, so only its lower corners count.
        readonly property real bodyReach: root.searchRadius * 2 + 4
        property vector4d bodyShape: Qt.vector4d(root.searchCenterX - x,
            (root.searchHeight - bodyReach) / 2, root.searchBodyWidth, root.searchHeight + bodyReach)
        property vector4d bubbleShape: Qt.vector4d(root.liveCenterX - x,
            root.liveTop + root.liveHeight / 2, root.liveWidth, root.liveHeight)
        property real bodyRadius: root.searchRadius
        property real bubbleRadius: root.liveRadius
        property real blend: root.neckBlend

        fragmentShader: Qt.resolvedUrl("shaders/overviewBubbleField.frag.qsb")
    }

    // ── The contents ─────────────────────────────────────────────────────────
    /**
     * Laid out at the resting size and carried by the drop's near edge, so the grid
     * arrives with it instead of being uncovered in place. The mask is a layer only
     * while the drop is moving; at rest the contents draw straight to the window.
     */
    Item {
        id: contentHost
        x: root.overviewCenterX - root.overviewWidth / 2
        y: root.away > 0 ? root.barEdgeY + root.liveTop : root.barEdgeY - root.liveTop - root.overviewHeight
        width: root.overviewWidth
        height: root.overviewHeight

        visible: root.contentReveal > 0
        layer.enabled: !root.atRest
        layer.effect: ShaderEffect {
            property vector2d resolution: Qt.vector2d(contentHost.width, contentHost.height)
            property vector4d box: Qt.vector4d(root.liveCenterX - contentHost.x,
                root.away > 0 ? root.liveHeight / 2 : root.overviewHeight - root.liveHeight / 2,
                Math.max(0, root.liveWidth - root.contentInset * 2), Math.max(0, root.liveHeight - root.contentInset * 2))
            property real radius: Math.max(0, root.liveRadius - root.contentInset * 0.5)
            fragmentShader: Qt.resolvedUrl("shaders/roundedRevealMask.frag.qsb")
        }
    }
}
