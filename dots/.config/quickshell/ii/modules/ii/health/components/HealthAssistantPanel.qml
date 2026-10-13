pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The assistant's prompt pill and its answer, for one subject.
 *
 * The pill is Modes' bar (AssistantPromptBar) with two differences: an empty send asks
 * the default question, and the answer is printed here instead of in the chat. A fix
 * the model proposed is a button under the answer; it runs only when clicked.
 */
ColumnLayout {
    id: root

    required property HealthAssistant assistant
    required property string key
    property string placeholder: Translation.tr("Ask about this — “how do I fix it?”")
    /// The answer card's colours; a surface already on primary container passes another pair.
    property color colCard: ClockStyle.colPrimaryContainer
    property color colOnCard: ClockStyle.colOnPrimaryContainer

    readonly property bool mine: root.assistant.subjectKey === root.key
    readonly property bool showAnswer: root.mine && (root.assistant.answer.length > 0 || root.assistant.phase === "running")

    /// The card is folding away; the answer is cleared only once it is gone, so its text
    /// does not vanish first and leave a header-sized card to snap out.
    property bool closing: false

    readonly property bool wanted: (root.mine && root.assistant.expanded) || root.showAnswer || root.closing

    /// 1 open, 0 gone. Hiding on `wanted` alone cut the pill's own fold off on its first
    /// frame, and the owner's spacing above the panel snapped shut with it; the panel
    /// stays until this has folded that gap away, in step with the pill's height.
    property real openness: root.wanted ? 1 : 0

    Behavior on openness {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation {
            id: opennessAnim
            duration: ClockStyle.motionDefault.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }

    visible: root.wanted || opennessAnim.running
    Layout.topMargin: -(root.parent?.spacing ?? 0) * (1 - root.openness)
    spacing: ClockStyle.gapSmall

    function closeAnswer(): void {
        if (root.closing)
            return;
        if (root.assistant.phase === "running")
            root.assistant.stop();
        if (ClockStyle.reducedMotion) {
            root.assistant.clearAnswer();
            return;
        }
        card.foldHeight = card.height;
        root.closing = true;
        closeAnim.restart();
    }

    function endClose(clear): void {
        closeAnim.stop();
        if (clear && root.mine)
            root.assistant.clearAnswer();
        card.foldHeight = -1;
        card.foldMargin = 0;
        card.opacity = 1;
        root.closing = false;
    }

    // A question sent or a subject switched mid-fold must not be wiped when the fold ends.
    Connections {
        target: root.assistant
        enabled: root.closing
        function onSubjectKeyChanged() {
            root.endClose(false);
        }
    }

    Component.onDestruction: {
        if (root.closing && root.mine)
            root.assistant.clearAnswer();
    }

    SequentialAnimation {
        id: closeAnim

        ParallelAnimation {
            NumberAnimation {
                target: card
                property: "opacity"
                to: 0
                duration: ClockStyle.motionExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionExit.bezierCurve
            }
            // Height and the gap above fold together, so nothing below jumps at the end.
            // Emphasized, not the spatial spring: an overshoot would drive the height negative.
            NumberAnimation {
                target: card
                property: "foldHeight"
                to: 0
                duration: ClockStyle.motionEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasized
            }
            NumberAnimation {
                target: card
                property: "foldMargin"
                to: -root.spacing
                duration: ClockStyle.motionEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasized
            }
        }

        ScriptAction {
            script: root.endClose(true)
        }
    }

    AssistantPromptBar {
        id: bar
        Layout.fillWidth: true
        expanded: root.mine && root.assistant.expanded
        phase: root.mine ? (root.assistant.phase === "running" ? "running" : root.assistant.phase === "error" ? "error" : "idle") : "idle"
        errorText: root.assistant.errorText
        placeholder: root.placeholder
        allowEmpty: true
        showChatHop: false
        onSubmitted: text => {
            if (root.closing)
                root.endClose(false);
            root.assistant.submit(text);
            bar.clear();
        }
        onStopRequested: root.assistant.stop()
        onDismissed: root.assistant.dismiss()
    }

    Rectangle {
        id: card
        Layout.fillWidth: true
        visible: root.showAnswer
        implicitHeight: answerColumn.implicitHeight + ClockStyle.gapLarge * 2
        Layout.preferredHeight: foldHeight
        Layout.topMargin: foldMargin
        clip: root.closing
        radius: ClockStyle.radiusLarge
        color: root.colCard

        /// -1 lets the layout use implicitHeight; the close animation drives both.
        property real foldHeight: -1
        property real foldMargin: 0

        StaggeredEntrance {
            index: 0
        }

        ColumnLayout {
            id: answerColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: "auto_awesome"
                    iconSize: ClockStyle.iconSmall
                    fill: 1
                    color: root.colOnCard
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.assistant.question
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                    color: root.colOnCard
                    opacity: 0.8
                }

                ClockIconButton {
                    visible: root.assistant.answer.length > 0 && root.assistant.phase !== "running"
                    symbol: "content_copy"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    tooltip: Translation.tr("Copy the answer")
                    onClicked: Quickshell.clipboardText = root.assistant.answer
                }

                ClockIconButton {
                    symbol: "close"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    enabled: !root.closing
                    tooltip: root.assistant.phase === "running" ? Translation.tr("Stop and close the answer") : Translation.tr("Close the answer")
                    onClicked: root.closeAnswer()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.assistant.answer.length > 0
                text: root.assistant.answer
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textNormal
                color: root.colOnCard
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            ClockButton {
                visible: root.assistant.proposal !== null && root.assistant.phase !== "running"
                Layout.topMargin: ClockStyle.gapTiny
                variant: "filled"
                symbol: "touch_app"
                label: root.assistant.proposal?.label ?? ""
                onClicked: root.assistant.runProposal()
            }

            StyledText {
                Layout.fillWidth: true
                visible: HealthService.redact
                text: Translation.tr("Sent with your user, host and home path redacted. Crash dumps are never sent.")
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textSmall
                color: root.colOnCard
                opacity: 0.7
            }
        }
    }
}
