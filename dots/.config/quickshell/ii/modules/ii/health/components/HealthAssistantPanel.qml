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

    visible: (root.mine && root.assistant.expanded) || root.showAnswer
    spacing: ClockStyle.gapSmall

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
        radius: ClockStyle.radiusLarge
        color: root.colCard

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
