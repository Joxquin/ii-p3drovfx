pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.services.ai
import qs.modules.common

/**
 * The assistant behind every ✦ button in System Health.
 *
 * One per window: only one sheet, crash stage or hero is open at a time, so one run is
 * enough, and a tab switch or a closing sheet simply resets it. Nothing of the AI graph
 * exists until the first send — the text task sits in a Loader that turns on then and
 * off again on reset, the budget the Modes agent keeps too.
 *
 * The answer is shown in place, under the prompt pill, rather than in the chat. The run
 * is a one-off text task narrowed to the read-only `health` tools; what it sends about
 * the subject is redacted first when `health.assistant.redact` is on (the default). A
 * crash dump never reaches it: the tools return the journal's stack-trace text only.
 */
Item {
    id: root

    visible: false

    /// Whether the ✦ buttons show at all: the app's switch and the shell-wide AI policy.
    readonly property bool allowed: (Config.options?.health?.assistant?.enable ?? true) && SearchPanelRegistry.aiPolicyEnabled

    /// Which surface the assistant is open on ("finding:<id>", "crash:<exe>", "overview").
    property string subjectKey: ""
    /// Called at send time for the facts about the subject, so they are current.
    property var subjectProvider: null
    property bool expanded: false
    /// "idle" | "running" | "error"
    property string phase: "idle"
    property string errorText: ""
    property string answer: ""
    property string question: ""
    /// The one fix the model proposed, as a button: { findingId, verb, label, args }.
    property var proposal: null

    function isOpenOn(key): bool {
        return root.expanded && root.subjectKey === key;
    }

    function hasAnswerFor(key): bool {
        return root.subjectKey === key && (root.answer.length > 0 || root.phase !== "idle");
    }

    function toggle(key, provider): void {
        if (root.subjectKey === key && root.expanded) {
            if (root.phase === "running")
                return;
            root.dismiss();
            return;
        }
        if (root.subjectKey !== key)
            root.reset();
        root.subjectKey = key;
        root.subjectProvider = provider;
        root.expanded = true;
    }

    function dismiss(): void {
        if (root.phase === "running")
            root.stop();
        root.expanded = false;
        root.phase = "idle";
        root.errorText = "";
    }

    function reset(): void {
        if (root.phase === "running")
            root.stop();
        root.expanded = false;
        root.phase = "idle";
        root.errorText = "";
        root.answer = "";
        root.question = "";
        root.proposal = null;
        root.subjectKey = "";
        root.subjectProvider = null;
        taskLoader.active = false;
    }

    function stop(): void {
        if (taskLoader.item)
            taskLoader.item.cancel();
        root.phase = "idle";
    }

    readonly property string systemPrompt: [
        "You are the System Health assistant inside a Linux desktop shell (Quickshell on Hyprland).",
        "The user pressed \"Explain\" on one problem the shell detected. Explain what happened and how to fix it.",
        "Answer in plain words, in the user's language: at most 6 short sentences or a short list. No preamble.",
        "Use the health_* tools when the facts given are not enough: unit logs, the crash's stack trace, journal lines, the owning package.",
        "Never claim you ran or changed anything; you cannot. If one action the app offers would fix it, call health_propose_fix once with that action; the user decides.",
        "Commands the user should run themselves go in a fenced code block. Prefer the distribution's tools (pacman, systemctl, journalctl).",
        "Identifying data is redacted: <user>, <host>, <ip>, <mac>, and ~ for the home directory. Do not ask for it."
    ].join("\n")

    function submit(text): void {
        const subject = root.subjectProvider ? root.subjectProvider() : null;
        const q = String(text ?? "").trim();
        root.question = q.length > 0 ? q : Translation.tr("What happened, and how do I fix it?");
        root.answer = "";
        root.proposal = null;
        root.errorText = "";
        root.phase = "running";
        let facts = JSON.stringify(subject ?? {}, null, 1);
        if (HealthService.redact)
            facts = HealthService.redactText(facts);
        const body = `${root.question}\n\nWhat System Health knows about it:\n\`\`\`json\n${facts}\n\`\`\``;
        taskLoader.active = true;
        const task = taskLoader.item;
        if (!task) {
            root.phase = "error";
            root.errorText = Translation.tr("The assistant could not start.");
            return;
        }
        // A model without tool support still gets the facts; it just cannot dig further.
        task.toolMode = task.model?.tools === true ? "functions" : "none";
        Ai.healthIntegration.activeKey = root.subjectKey;
        task.start(root.systemPrompt, body);
    }

    Connections {
        target: Ai.healthIntegration
        enabled: root.phase === "running"
        function onProposed(proposal) {
            root.proposal = proposal;
        }
    }

    /// Runs the proposed fix. Only ever called from the user's click on its button.
    function runProposal(): void {
        const p = root.proposal;
        if (!p)
            return;
        Ai.healthIntegration.runProposal(p);
        root.proposal = null;
    }

    Loader {
        id: taskLoader
        active: false
        sourceComponent: AiTextTask {
            taskName: "health_explain"
            scriptName: "health_explain"
            toolDomains: ["health"]
            temperature: 0.2

            // Deltas: the answer grows under the pill as it streams.
            onChunk: text => root.answer += String(text ?? "")
            onFinished: result => {
                root.answer = String(result ?? "").trim();
                root.phase = "idle";
                Ai.healthIntegration.activeKey = "";
            }
            onFailed: error => {
                root.phase = "error";
                root.errorText = String(error ?? "");
                Ai.healthIntegration.activeKey = "";
            }
            onStatusChanged: {
                if (status === "aborted") {
                    root.phase = "idle";
                    Ai.healthIntegration.activeKey = "";
                }
            }
        }
    }
}
