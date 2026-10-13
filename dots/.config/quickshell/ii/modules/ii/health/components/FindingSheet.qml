pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One finding, opened from a row: what it is in plain words, the facts under it, the
 * raw log where there is one, and the fixes as the footer. The assistant's ✦ button sits
 * in the header beside the close button, and its pill opens at the top of the body.
 *
 * The finding is read live by id, so a unit that recovers while the sheet is open turns
 * the sheet into "resolved" instead of leaving stale facts on screen.
 */
ClockSheet {
    id: root

    property string findingId: ""
    property HealthAssistant assistant: null
    /// Opens the cleanup sheet; set by the Storage page, which owns it.
    property var onFreeSpace: null

    readonly property var finding: HealthService.findingsById[root.findingId] ?? null
    property var lastFinding: null
    onFindingChanged: {
        if (root.finding)
            root.lastFinding = root.finding;
    }
    readonly property var f: root.finding ?? root.lastFinding
    readonly property var d: root.f?.data ?? ({})
    readonly property string kind: String(root.f?.kind ?? "")
    readonly property bool resolved: root.finding === null && root.lastFinding !== null
    readonly property bool isUnit: ["unit", "appLaunch", "restartLoop"].includes(root.kind)
    readonly property string assistantKey: `finding:${root.findingId}`

    property var logLines: []
    property bool logLoading: false
    property string busyVerb: ""
    property string actionError: ""

    title: root.f ? HealthText.title(root.f) : ""
    subtitle: root.resolved ? Translation.tr("Resolved") : (root.f ? HealthText.severityLabel(root.f.sev) : "")

    Component.onCompleted: {
        root.lastFinding = root.finding;
        root.loadLog();
    }

    function loadLog(): void {
        if (root.isUnit && root.d.unit) {
            root.logLoading = true;
            HealthService.query("unitLog", { scope: root.d.scope, unit: root.d.unit, lines: 40 }, (ok, data) => {
                root.logLoading = false;
                root.logLines = ok ? Array.from(data?.lines ?? []) : [];
            });
        } else if (root.kind === "journal" && root.f?.fp) {
            root.logLoading = true;
            HealthService.query("journalGroup", { fp: root.f.fp, lines: 20 }, (ok, data) => {
                root.logLoading = false;
                root.logLines = ok ? Array.from(data?.lines ?? []) : [];
            });
        }
    }

    function run(verb): void {
        root.busyVerb = verb;
        root.actionError = "";
        HealthService.act(verb, { scope: root.d.scope, unit: root.d.unit, drive: root.d.path }, (ok, data, error) => {
            root.busyVerb = "";
            if (!ok)
                root.actionError = error === "auth" || error === "denied"
                    ? Translation.tr("The password prompt was dismissed.")
                    : Translation.tr("It did not work: %1").arg(error || "?");
            else
                Qt.callLater(root.loadLog);
        });
    }

    function provider(): var {
        const out = { finding: root.f, title: HealthText.title(root.f), detail: HealthText.detail(root.f, Date.now()) };
        if (root.logLines.length > 0)
            out.recentLog = root.logLines.slice(-25);
        return out;
    }

    // The rows, one list per kind: [symbol, shape, caption, value].
    readonly property var rows: {
        const d = root.d;
        const S = MaterialShape.Shape;
        const now = Date.now();
        switch (root.kind) {
        case "unit":
        case "appLaunch":
            return [
                ["help", S.Cookie7Sided, Translation.tr("Why"), HealthText.unitWhy(d)],
                ["tag", S.Clover4Leaf, Translation.tr("Status"), HealthText.unitStatus(d) || Translation.tr("No exit status")],
                ["terminal", S.Cookie9Sided, Translation.tr("Program"), d.execPath ? (d.execExists === false ? Translation.tr("%1 (missing)").arg(d.execPath) : d.execPath) : Translation.tr("Unknown")],
                ["schedule", S.Sunny, Translation.tr("Failed"), Translation.tr("%1 ago").arg(HealthText.age(root.f?.since, now))],
                ["autorenew", S.Cookie12Sided, Translation.tr("Restarts"), String(d.nRestarts ?? 0)],
                ["deployed_code", S.SoftBurst, Translation.tr("Kind"), d.scope === "user" ? Translation.tr("User service") : Translation.tr("System service")]
            ];
        case "restartLoop":
            return [
                ["autorenew", S.Cookie12Sided, Translation.tr("Restarts"), Translation.tr("%1 in 10 minutes").arg(d.nRestarts ?? root.f?.count ?? 0)],
                ["description", S.Cookie7Sided, Translation.tr("Service"), d.description ?? d.unit ?? ""]
            ];
        case "journal":
            return [
                ["source", S.Cookie7Sided, Translation.tr("From"), HealthText.sourceLabel(d.source)],
                ["schedule", S.Sunny, Translation.tr("First seen"), Translation.tr("%1 ago").arg(HealthText.age(root.f?.since, now))],
                ["numbers", S.Clover4Leaf, Translation.tr("This boot"), Translation.tr("%1 lines").arg(d.countBoot ?? root.f?.count ?? 0)]
            ];
        case "disk":
            return [
                ["folder", S.Cookie7Sided, Translation.tr("Mounted at"), d.mount ?? ""],
                ["hard_drive", S.Cookie9Sided, Translation.tr("Free"), Translation.tr("%1 of %2").arg(HealthText.bytes(d.avail)).arg(HealthText.bytes(d.total))],
                ["data_usage", S.Sunny, Translation.tr("Inodes used"), `${Math.round(Number(d.inodesPct ?? 0))} %`],
                ["trending_up", S.Clover4Leaf, Translation.tr("Full in"), d.etaDays !== null && d.etaDays !== undefined ? Translation.tr("about %1 days").arg(Math.max(1, Math.round(d.etaDays))) : Translation.tr("not filling up")]
            ];
        case "drive":
            return [
                ["warning", S.Cookie7Sided, Translation.tr("Problem"), HealthText.driveProblems(d).join(", ")],
                ["device_thermostat", S.Sunny, Translation.tr("Temperature"), d.tempC !== null && d.tempC !== undefined ? `${Math.round(d.tempC)} °C` : "—"],
                ["battery_horiz_050", S.Cookie9Sided, Translation.tr("Rated life used"), d.percentUsed !== null && d.percentUsed !== undefined ? `${d.percentUsed} %` : "—"]
            ];
        case "firmware":
            return [
                ["memory", S.Cookie9Sided, Translation.tr("Device"), d.name ?? d.device ?? ""],
                ["upgrade", S.Sunny, Translation.tr("Version"), Translation.tr("%1 → %2").arg(d.version ?? "?").arg(d.newVersion ?? "?")],
                ["info", S.Cookie7Sided, Translation.tr("About"), d.summary ?? ""]
            ];
        case "security":
            return Array.from(d.attrs ?? []).filter(a => a.success === false).slice(0, 8).map(a =>
                ["shield", S.Clover4Leaf, a.name ?? a.id ?? "", String(a.result ?? "")]);
        case "reboot":
            return [
                ["memory", S.Cookie9Sided, Translation.tr("Running"), d.running ?? ""],
                ["deployed_code", S.Sunny, Translation.tr("Installed"), Array.from(d.installed ?? []).join(", ")]
            ];
        case "deletedLibs":
            return Array.from(d.processes ?? []).slice(0, 10).map(p =>
                ["apps", S.Cookie7Sided, `${p.comm} (${p.pid})`, Array.from(p.libs ?? []).map(l => String(l).split("/").pop()).join(", ")]);
        case "pacnew":
            return Array.from(d.files ?? []).slice(0, 12).map(file => ["description", S.Cookie7Sided, Translation.tr("File"), file]);
        case "pressure":
            return Array.from(d.top ?? []).map(p => ["memory", S.Cookie9Sided, p.comm, HealthText.bytes(p.rssBytes)]);
        case "thermal":
            return [
                ["device_thermostat", S.Sunny, Translation.tr("Temperature"), d.tempC ? `${Math.round(d.tempC)} °C` : "—"],
                ["speed", S.Cookie7Sided, Translation.tr("Slowdowns"), Translation.tr("%1 in 5 minutes").arg(d.events5min ?? 0)]
            ];
        case "timesync":
            return [
                ["schedule", S.Sunny, Translation.tr("Network time"), d.ntp ? Translation.tr("On, not synchronised yet") : Translation.tr("Off")]
            ];
        default:
            return [];
        }
    }

    headerActions: [
        HealthAssistantButton {
            assistant: root.assistant ?? placeholderAssistant
            key: root.assistantKey
            visible: root.assistant !== null && root.assistant.allowed && !root.resolved
            provider: () => root.provider()
        },
        ClockIconButton {
            visible: root.isUnit && !root.resolved && root.kind !== "restartLoop"
            symbol: "done_all"
            size: 38
            tooltip: Translation.tr("Clear the failure")
            onClicked: root.run("resetFailed")
        },
        ClockIconButton {
            visible: root.kind === "journal" && !root.resolved
            symbol: "notifications_off"
            size: 38
            tooltip: Translation.tr("Mute this message")
            onClicked: {
                HealthService.mute(root.f.fp);
                root.close();
            }
        },
        ClockIconButton {
            visible: root.kind === "appLaunch" && !root.resolved
            symbol: "visibility_off"
            size: 38
            tooltip: Translation.tr("Hide until it happens again")
            onClicked: {
                HealthService.dismiss(root.findingId);
                root.close();
            }
        }
    ]

    HealthAssistantPanel {
        Layout.fillWidth: true
        visible: root.assistant !== null && (root.assistant.isOpenOn(root.assistantKey) || root.assistant.hasAnswerFor(root.assistantKey))
        assistant: root.assistant ?? placeholderAssistant
        key: root.assistantKey
    }

    // A sheet can be built without an assistant (the island's Details on a window that
    // is still loading); the panel needs an object to bind to.
    HealthAssistant {
        id: placeholderAssistant
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.resolved
        text: Translation.tr("This was fixed while the sheet was open.")
        wrapMode: Text.Wrap
        font.pixelSize: ClockStyle.textNormal
        color: ClockStyle.colPrimary
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.kind === "journal"
        text: String(root.d.sample ?? "")
        wrapMode: Text.WrapAnywhere
        font.family: Appearance.font.family.monospace
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colOnSurface
    }

    Repeater {
        model: root.rows

        ClockFormPicker {
            required property var modelData
            Layout.fillWidth: true
            symbol: modelData[0]
            shapeKind: modelData[1]
            caption: modelData[2]
            value: modelData[3]
            showChevron: false
        }
    }

    HealthLogBox {
        visible: root.isUnit || root.kind === "journal"
        lines: root.logLines
        loading: root.logLoading
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.actionError.length > 0
        text: root.actionError
        wrapMode: Text.Wrap
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colError
    }

    actions: [
        ClockSheetAction {
            visible: root.isUnit && !root.resolved
            label: Translation.tr("Show in terminal")
            symbol: "terminal"
            onClicked: HealthService.runInTerminal(root.d.scope === "user"
                ? ["journalctl", "--user", "-u", root.d.unit, "-e", "--no-pager", "-n", "200"]
                : ["journalctl", "-u", root.d.unit, "-e", "--no-pager", "-n", "200"])
        },
        ClockSheetAction {
            readonly property var fix: HealthService.primaryFix(root.f)
            visible: root.isUnit && !root.resolved && fix !== null
            primary: true
            danger: fix?.verb === "disable"
            enabled: root.busyVerb.length === 0
            label: root.busyVerb.length > 0 ? Translation.tr("Working…") : (fix?.label ?? "")
            symbol: fix?.verb === "disable" ? "block" : fix?.verb === "stop" ? "stop" : "restart_alt"
            onClicked: root.run(fix.verb)
        },
        ClockSheetAction {
            // A missing program's fix is Disable; Restart stays one tap away.
            visible: root.kind === "unit" && !root.resolved && HealthService.primaryFix(root.f)?.verb === "disable"
            label: Translation.tr("Restart anyway")
            symbol: "restart_alt"
            onClicked: root.run("restart")
        },
        ClockSheetAction {
            visible: root.kind === "journal" && !root.resolved
            primary: true
            label: Translation.tr("Mark as known")
            symbol: "done"
            onClicked: {
                HealthService.markKnown(root.f.fp);
                root.close();
            }
        },
        ClockSheetAction {
            visible: root.kind === "disk" && typeof root.onFreeSpace === "function"
            primary: true
            label: Translation.tr("Free up space")
            symbol: "cleaning_services"
            onClicked: root.onFreeSpace()
        },
        ClockSheetAction {
            visible: root.kind === "drive" && !root.resolved
            primary: true
            enabled: root.busyVerb.length === 0
            label: Translation.tr("Run a self-test")
            symbol: "fact_check"
            onClicked: root.run("selftest")
        },
        ClockSheetAction {
            visible: root.kind === "firmware" || root.kind === "security"
            primary: root.kind === "firmware"
            label: root.kind === "firmware" ? Translation.tr("Update in a terminal") : Translation.tr("Open the fwupd report")
            symbol: "terminal"
            onClicked: HealthService.runInTerminal(root.kind === "firmware" ? ["fwupdmgr", "update"] : ["fwupdmgr", "security"])
        },
        ClockSheetAction {
            visible: root.kind === "reboot"
            primary: true
            label: Translation.tr("Restart now")
            symbol: "restart_alt"
            onClicked: GlobalStates.sessionOpen = true
        },
        ClockSheetAction {
            visible: root.kind === "pacnew"
            primary: true
            label: Translation.tr("Merge in a terminal")
            symbol: "merge"
            onClicked: HealthService.runInTerminal(["sudo", "pacdiff"])
        },
        ClockSheetAction {
            visible: root.kind === "timesync"
            primary: true
            label: Translation.tr("Turn on network time")
            symbol: "schedule"
            onClicked: Quickshell.execDetached(["timedatectl", "set-ntp", "true"])
        },
        ClockSheetAction {
            visible: root.kind === "pressure"
            primary: true
            label: Translation.tr("Open the task manager")
            symbol: "monitoring"
            onClicked: Quickshell.execDetached(["sh", "-c", Config.options?.apps?.taskManager ?? "plasma-systemmonitor"])
        }
    ]
}
