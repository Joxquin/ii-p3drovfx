pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.dynamicIsland.core

/**
 * System Health: runs the `health_watch` helper and holds what it reports.
 *
 * The helper owns every measurement — systemd on both buses, the journal, UDisks2,
 * fwupd, the package log, pressure and thermals — and speaks the line protocol in
 * scripts/health/PROTOCOL.md. This side keeps the latest state of each message, turns
 * live critical findings into alerts (rate-limited, held while you are fullscreen or in
 * Do Not Disturb), and forwards the user's actions back. It is headless: the app, the
 * island strip and the assistant all read it, none of them talk to the helper.
 *
 * Nothing is spawned while `health.enable` is off, and nothing is built in QML until the
 * app opens: the window lives in a RetainedLoader like the clock's.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.health ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? true)

    readonly property string helperDir: `${Directories.scriptPath}/health`
    readonly property string binaryPath: `${root.helperDir}/health_watch`
    readonly property string accessScript: `${root.helperDir}/crash-access.sh`
    readonly property string stateDir: FileUtils.trimFileProtocol(`${Directories.state}/user/health`)

    // ── Helper lifecycle ────────────────────────────────────────────────
    /// Assumed present until the probe says otherwise, so the app never flashes its
    /// setup page on a start where the binary is there.
    property bool binaryPresent: true
    property bool probed: false
    /// True once the helper announced itself.
    property bool running: false
    /// True once the helper finished its first full scan; findings before it are the
    /// starting state, after it they are live.
    property bool synced: false
    property bool _restarting: false

    readonly property RustHelperBuild helperBuild: RustHelperBuild {
        label: "SystemHealth"
        sourceDir: `${root.helperDir}/health_watch_src`
        crateName: "health_watch"
        onFinished: ok => {
            root.checkBinary();
            if (ok) {
                root.restart();
                root.builtInApp = true;
            }
        }
    }

    /// The helper was just built from the app: the Overview offers crash-dump access
    /// once, the way the setup script does after its own build.
    property bool builtInApp: false
    readonly property bool offerDumpAccess: root.builtInApp && root.dumpAccess === "denied"
        && !(Persistent.states?.healthApp?.dumpAccessAsked ?? false)

    function answerDumpOffer(grant): void {
        if (Persistent.states?.healthApp)
            Persistent.states.healthApp.dumpAccessAsked = true;
        root.builtInApp = false;
        if (grant)
            root.setDumpAccess(true);
    }

    // ── What the helper reported ────────────────────────────────────────
    property var sources: ({})
    property string journalAccess: ""
    property string packageManager: ""
    /// "granted" | "denied" | "" (not known yet). Read from the ACL, never stored.
    property string dumpAccess: ""
    property string user: ""

    /// id → Finding, replaced as a whole on every change so bindings notice.
    property var findingsById: ({})
    /// Muted findings are still sent by the helper (the Journal and Crashes pages list
    /// them); everything that counts or alerts leaves them out.
    readonly property var findings: {
        const order = { critical: 0, warning: 1, info: 2 };
        return Object.values(root.findingsById).filter(f => f.muted !== true).sort((a, b) => (order[a.sev] ?? 3) - (order[b.sev] ?? 3) || Number(b.since ?? 0) - Number(a.since ?? 0));
    }
    /// What the hero counts: critical and warning findings, app launches excluded.
    readonly property var attention: root.findings.filter(f => f.kind !== "appLaunch" && (f.sev === "critical" || f.sev === "warning"))
    readonly property int attentionCount: root.attention.length

    property var crashGroups: []
    property var updateTransactions: []
    property var journal: ({ access: "", groups: [], noise: { knownGroups: 0, knownLines: 0, mutedGroups: 0 } })
    property var drives: []
    property var vitals: null
    property var system: null
    property var history: []
    property double lastMessageAt: 0

    function findingsOfKind(kinds): var {
        const set = Array.isArray(kinds) ? kinds : [kinds];
        return root.findings.filter(f => set.includes(f.kind));
    }

    function finding(id): var {
        return root.findingsById[String(id)] ?? null;
    }

    // ── Talking to the helper ───────────────────────────────────────────
    property int _req: 0
    property var _callbacks: ({})

    function send(obj): void {
        if (!helper.running)
            return;
        helper.write(JSON.stringify(obj) + "\n");
    }

    /// Asks the helper something; `callback(ok, data, error)` runs with its reply.
    function query(what, args, callback): void {
        root._request(Object.assign({ t: "query", what: what }, args ?? {}), callback);
    }

    /// Runs a unit or drive action (restart, stop, start, resetFailed, disable, enable,
    /// selftest). System units go through polkit, so the shell's agent asks.
    function act(verb, args, callback): void {
        root._request(Object.assign({ t: "act", verb: verb }, args ?? {}), callback);
    }

    function _request(obj, callback): void {
        if (!helper.running) {
            if (callback)
                callback(false, null, "not-running");
            return;
        }
        const req = ++root._req;
        if (callback) {
            const next = Object.assign({}, root._callbacks);
            next[req] = callback;
            root._callbacks = next;
        }
        obj.req = req;
        root.send(obj);
    }

    function mute(fp): void { root.send({ t: "mute", fp: String(fp) }); }
    function unmute(fp): void { root.send({ t: "unmute", fp: String(fp) }); }
    function markKnown(fp): void { root.send({ t: "markKnown", fp: String(fp) }); }
    function muteProgram(exe): void { root.send({ t: "muteProgram", exe: String(exe) }); }
    function unmuteProgram(exe): void { root.send({ t: "unmuteProgram", exe: String(exe) }); }
    function dismiss(id): void { root.send({ t: "dismiss", id: String(id) }); }
    function resetNoise(): void { root.send({ t: "resetNoise" }); }

    function rescan(): void {
        root.synced = false;
        root.send({ t: "rescan" });
        root.refreshDumpAccess();
    }

    /// The app tells the helper when it is on screen, for 2 s vitals instead of 15 s.
    property bool appVisible: false
    onAppVisibleChanged: root.send({ t: "visible", app: root.appVisible })

    function handleLine(line): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.warn("[Health] unreadable line from helper:", line);
            return;
        }
        root.lastMessageAt = Date.now();
        switch (msg.t) {
        case "ready":
            root.running = true;
            root.synced = false;
            root.sources = msg.sources ?? {};
            root.journalAccess = String(msg.sources?.journal ?? "");
            root.packageManager = String(msg.sources?.packages ?? "");
            root.dumpAccess = String(msg.dumpAccess ?? "");
            root.user = String(msg.user ?? "");
            root.findingsById = {};
            if (root.appVisible)
                root.send({ t: "visible", app: true });
            break;
        case "synced":
            root.synced = true;
            break;
        case "access":
            root.dumpAccess = String(msg.dumpAccess ?? root.dumpAccess);
            break;
        case "finding":
            root.applyFinding(msg);
            break;
        case "crashes":
            root.crashGroups = Array.from(msg.groups ?? []);
            break;
        case "updates":
            root.updateTransactions = Array.from(msg.transactions ?? []);
            break;
        case "journal":
            root.journal = {
                access: String(msg.access ?? ""),
                groups: Array.from(msg.groups ?? []),
                noise: msg.noise ?? { knownGroups: 0, knownLines: 0, mutedGroups: 0 }
            };
            break;
        case "drives":
            root.drives = Array.from(msg.drives ?? []);
            break;
        case "vitals":
            root.vitals = msg;
            break;
        case "system":
            root.system = msg;
            break;
        case "history":
            root.history = Array.from(msg.days ?? []);
            break;
        case "reply": {
            const cb = root._callbacks[msg.req];
            if (cb) {
                const next = Object.assign({}, root._callbacks);
                delete next[msg.req];
                root._callbacks = next;
                try {
                    cb(msg.ok === true, msg.data ?? null, String(msg.error ?? ""));
                } catch (e) {
                    console.warn("[Health] reply handler failed:", e);
                }
            }
            break;
        }
        case "log":
            console.warn(`[Health] helper: ${msg.msg ?? ""}`);
            break;
        }
    }

    function applyFinding(msg): void {
        const next = Object.assign({}, root.findingsById);
        if (msg.op === "resolve") {
            if (!(msg.id in next))
                return;
            delete next[msg.id];
            root.findingsById = next;
            root.dropHeld(String(msg.id));
            return;
        }
        const f = msg.f;
        if (!f || !f.id)
            return;
        next[f.id] = f;
        root.findingsById = next;
        if (f.alert === true && f.muted !== true && root.synced)
            root.raiseAlert(f);
    }

    // ── Alerts ──────────────────────────────────────────────────────────
    /// The island shows the strip; its source listens here.
    signal islandAlert(var finding)

    readonly property var alertOpts: root.opts?.alerts ?? null
    readonly property bool islandOwnsAlerts: IslandPolicy.enabled && IslandPolicy.widgetEnabled("health") && (root.alertOpts?.island ?? true)
    /// Fullscreen, Do Not Disturb or a locked screen: alerts wait and arrive as one.
    readonly property bool quiet: GlobalStates.screenLocked
        || ((root.alertOpts?.holdInFullscreen ?? true) && ((ToplevelManager.activeToplevel?.fullscreen ?? false) || Notifications.effectiveSilent))
    property var _held: []
    property var _recentAlerts: []

    onQuietChanged: {
        if (!root.quiet && root._held.length > 0)
            releaseHeld.restart();
    }

    // Leaving fullscreen often lands in another fullscreen window a moment later
    // (a game's launcher, a video); a short beat avoids alerting in between.
    Timer {
        id: releaseHeld
        interval: 2500
        onTriggered: {
            if (root.quiet || root._held.length === 0)
                return;
            const held = root._held.filter(f => root.findingsById[f.id] !== undefined);
            root._held = [];
            if (held.length === 1)
                root.deliverAlert(held[0], 0);
            else if (held.length > 1)
                root.deliverAlert(held[0], held.length - 1);
        }
    }

    function dropHeld(id): void {
        if (root._held.some(f => f.id === id))
            root._held = root._held.filter(f => f.id !== id);
    }

    function raiseAlert(f): void {
        if (root.quiet) {
            if (!root._held.some(h => h.id === f.id))
                root._held = [...root._held, f];
            return;
        }
        const now = Date.now();
        const recent = root._recentAlerts.filter(t => now - t < 600000);
        const max = root.alertOpts?.maxPer10Min ?? 3;
        if (recent.length >= max) {
            // Over the budget: keep it for one summary once the window frees up.
            root._recentAlerts = recent;
            if (!root._held.some(h => h.id === f.id))
                root._held = [...root._held, f];
            budgetTimer.interval = Math.max(1000, 600000 - (now - recent[0]));
            budgetTimer.restart();
            return;
        }
        root._recentAlerts = [...recent, now];
        root.deliverAlert(f, 0);
    }

    Timer {
        id: budgetTimer
        onTriggered: releaseHeld.restart()
    }

    function deliverAlert(f, more): void {
        const payload = { finding: f, more: more };
        if (root.islandOwnsAlerts) {
            root.islandAlert(payload);
            return;
        }
        root.notifyAlert(payload);
    }

    /// The fallback when the island is off or refused the strip (its quiet window).
    function notifyAlert(payload): void {
        if (!(root.alertOpts?.notifyFallback ?? true))
            return;
        const f = payload.finding;
        const more = Number(payload.more ?? 0);
        const actions = [{ identifier: "__qs_health_open", text: Translation.tr("Details") }];
        const fix = root.primaryFix(f);
        if (fix)
            actions.unshift({ identifier: "__qs_health_fix", text: fix.label });
        Notifications.publishInternalNotification({
            appName: Translation.tr("System Health"),
            appIcon: "health_metrics",
            summary: more > 0 ? Translation.tr("%1 and %2 more").arg(HealthText.title(f)).arg(more) : HealthText.title(f),
            body: HealthText.detail(f, Date.now()),
            urgency: f.sev === "critical" ? "critical" : "normal",
            actions: actions,
            actionPayload: { id: f.id }
        });
    }

    Connections {
        target: Notifications
        function onInternalActionInvoked(identifier, notificationId, payload) {
            const id = String(payload?.id ?? "");
            if (identifier === "__qs_health_open")
                root.openFinding(id);
            else if (identifier === "__qs_health_fix")
                root.runPrimaryFix(id);
        }
    }

    // ── Fixes ───────────────────────────────────────────────────────────
    /// The one action an alert offers as its button, or null.
    function primaryFix(f): var {
        if (!f)
            return null;
        const d = f.data ?? {};
        switch (f.kind) {
        case "unit":
            // A missing program is not fixed by restarting it; stopping the retries is.
            if (d.why === "exec-missing" || d.why === "user")
                return { label: Translation.tr("Disable"), verb: "disable" };
            return { label: Translation.tr("Restart"), verb: "restart" };
        case "restartLoop":
            return { label: Translation.tr("Stop"), verb: "stop" };
        case "crash":
            return { label: Translation.tr("Copy report"), verb: "copyReport" };
        case "reboot":
            return { label: Translation.tr("Restart"), verb: "reboot" };
        default:
            return null;
        }
    }

    function runPrimaryFix(id, callback): void {
        const f = root.finding(id);
        const fix = root.primaryFix(f);
        if (!fix)
            return;
        const d = f.data ?? {};
        if (fix.verb === "copyReport") {
            root.copyCrashReport(String(d.exe ?? ""));
            if (callback)
                callback(true, null, "");
        } else if (fix.verb === "reboot") {
            GlobalStates.sessionOpen = true;
        } else {
            root.act(fix.verb, { scope: d.scope, unit: d.unit }, callback);
        }
    }

    function openFinding(id): void {
        const f = root.finding(id);
        const tab = !f ? "overview"
            : ["unit", "appLaunch", "restartLoop"].includes(f.kind) ? "services"
            : f.kind === "crash" ? "crashes"
            : f.kind === "journal" ? "journal"
            : ["disk", "drive"].includes(f.kind) ? "storage"
            : ["firmware", "security", "reboot", "deletedLibs", "pacnew", "timesync"].includes(f.kind) ? "system"
            : "overview";
        GlobalStates.openHealthApp(tab, String(id ?? ""));
    }

    // ── Crash reports ───────────────────────────────────────────────────
    readonly property bool redact: root.opts?.assistant?.redact ?? true

    /// Replaces what identifies this machine or this person in text that may leave it.
    function redactText(text): string {
        let s = String(text ?? "");
        const home = String(Quickshell.env("HOME") ?? "");
        const userName = root.user || String(Quickshell.env("USER") ?? "");
        const host = hostnameFile.text().trim();
        if (home.length > 1)
            s = s.split(home).join("~");
        if (userName.length > 1)
            s = s.replace(new RegExp(`\\b${userName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "g"), "<user>");
        if (host.length > 1)
            s = s.replace(new RegExp(host.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"), "<host>");
        s = s.replace(/\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b/g, "<mac>");
        s = s.replace(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, "<ip>");
        s = s.replace(/\b(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}\b/g, "<ip>");
        return s;
    }

    FileView {
        id: hostnameFile
        path: "/proc/sys/kernel/hostname"
        printErrors: false
    }

    function crashGroup(exe): var {
        return root.crashGroups.find(g => g.exe === exe) ?? null;
    }

    /// A Markdown bug report for the newest crash of `exe`, copied to the clipboard.
    /// Built from the journal's stack trace, never from the dump itself.
    function copyCrashReport(exe, callback): void {
        const g = root.crashGroup(exe);
        root.query("crashInfo", { exe: exe }, (ok, data) => {
            const lines = [];
            lines.push(`## ${g?.name ?? exe} crashed (${HealthText.signalName(g?.signal, g?.signalName)})`);
            lines.push("");
            lines.push(`- Program: \`${exe}\``);
            if (g?.package)
                lines.push(`- Package: ${g.package} ${g.version ?? ""}`);
            lines.push(`- Crashes in 7 days: ${g?.count ?? 1}`);
            if (g?.afterUpdate)
                lines.push(`- First crash after updating ${g.afterUpdate.name} ${g.afterUpdate.from ?? ""} → ${g.afterUpdate.to ?? ""}`);
            lines.push(`- Kernel: ${root.system?.kernel?.running ?? ""}`);
            lines.push("");
            lines.push("```");
            const message = ok ? String(data?.message ?? "") : (g?.trace ?? []).map((fr, i) => `#${i} ${fr.fn} (${fr.module})`).join("\n");
            lines.push(message.trim());
            lines.push("```");
            const text = lines.join("\n");
            Quickshell.clipboardText = root.redact ? root.redactText(text) : text;
            if (callback)
                callback(true);
        });
    }

    // ── Crash-dump access ───────────────────────────────────────────────
    property bool accessBusy: false
    property string accessError: ""

    function refreshDumpAccess(): void {
        accessStatus.running = false;
        accessStatus.running = true;
    }

    /// Grants or revokes this account's read access to system crash dumps. pkexec asks
    /// for the password; the result is read back from the ACL, not assumed.
    function setDumpAccess(grant): void {
        if (root.accessBusy)
            return;
        root.accessBusy = true;
        root.accessError = "";
        accessChange.command = ["pkexec", root.accessScript, grant ? "grant" : "revoke", root.user || String(Quickshell.env("USER") ?? "")];
        accessChange.running = true;
    }

    Process {
        id: accessStatus
        command: [root.accessScript, "status", root.user || String(Quickshell.env("USER") ?? "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                if (s === "granted" || s === "denied")
                    root.dumpAccess = s;
            }
        }
    }

    Process {
        id: accessChange
        stderr: StdioCollector {
            id: accessChangeErr
        }
        onExited: (code, status) => {
            root.accessBusy = false;
            // 126/127: the password prompt was dismissed or pkexec is missing.
            if (code !== 0)
                root.accessError = code === 126 || code === 127 ? "cancelled" : (accessChangeErr.text.trim() || `exit ${code}`);
            root.refreshDumpAccess();
        }
    }

    // ── Cleanup ─────────────────────────────────────────────────────────
    property string cleaning: ""
    signal cleanupFinished(string what, bool ok)

    /// Frees space: "journal" (archives older than 4 weeks), "pacmanCache" (keep 2
    /// versions), "trash". The privileged ones go through pkexec.
    function cleanup(what): void {
        if (root.cleaning.length > 0)
            return;
        let cmd = null;
        if (what === "journal")
            cmd = ["pkexec", "journalctl", "--vacuum-time=4weeks"];
        else if (what === "pacmanCache")
            cmd = ["pkexec", "paccache", "-rk2"];
        else if (what === "trash")
            cmd = ["gio", "trash", "--empty"];
        if (!cmd)
            return;
        root.cleaning = what;
        cleanupProc.what = what;
        cleanupProc.command = cmd;
        cleanupProc.running = true;
    }

    Process {
        id: cleanupProc
        property string what: ""
        onExited: (code, status) => {
            root.cleaning = "";
            root.cleanupFinished(cleanupProc.what, code === 0);
            root.rescan();
        }
    }

    /// Opens a terminal running `args`, waiting for Enter at the end so the output stays.
    function runInTerminal(args): void {
        const terminal = Config.options?.apps?.terminal || "kitty -1";
        const cmd = terminal.split(" ").filter(part => part.length > 0);
        cmd.push("-e", "bash", "-c", '"$@"; printf "\\n[Press Enter to close] "; read -r', "ii-health", ...args);
        Quickshell.execDetached(cmd);
    }

    // ── Process ─────────────────────────────────────────────────────────
    function checkBinary(): void {
        probe.running = false;
        probe.running = true;
    }

    function restart(): void {
        root._restarting = true;
        Qt.callLater(() => root._restarting = false);
    }

    Component.onCompleted: {
        if (root.enabled)
            root.checkBinary();
    }
    onEnabledChanged: {
        if (root.enabled)
            root.checkBinary();
    }

    Process {
        id: probe
        command: ["sh", "-c", `[ -x "${root.binaryPath}" ] && echo 1 || echo 0`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.binaryPresent = this.text.trim() === "1";
                root.probed = true;
                root.refreshDumpAccess();
            }
        }
    }

    readonly property var srcOpts: root.opts?.sources ?? null
    readonly property var launchArgs: {
        const names = ["units", "userUnits", "appLaunches", "crashes", "journal", "drives", "filesystems", "firmware", "packages", "pressure", "thermals", "timesync"];
        const on = names.filter(n => root.srcOpts?.[n] ?? true);
        const noise = root.opts?.noise;
        const th = root.opts?.thresholds;
        return [
            "--state-dir", root.stateDir,
            "--sources", on.join(","),
            "--known-after", String(noise?.knownAfterBoots ?? 3),
            "--of-last", String(noise?.ofLastBoots ?? 5),
            "--quiet-days", String(noise?.quietDaysForNew ?? 14),
            "--disk-warn", String(th?.diskWarnPercent ?? 90),
            "--disk-crit", String(th?.diskCritPercent ?? 97),
            "--psi-mem", String(th?.psiMemPercent ?? 10),
            "--restart-loop", String(th?.restartLoop ?? 5),
            "--history-days", String(root.opts?.historyDays ?? 30)
        ];
    }
    readonly property string launchKey: root.launchArgs.join("|")
    onLaunchKeyChanged: {
        if (helper.running)
            root.restart();
    }

    /// Crashes restart it with a growing pause, so a helper that dies on start cannot spin.
    property int _failures: 0
    Timer {
        id: backoff
        onTriggered: root._restarting = false
    }

    Process {
        id: helper
        running: root.enabled && root.probed && root.binaryPresent && !root._restarting
        stdinEnabled: true
        command: [root.binaryPath, ...root.launchArgs]

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("[Health]", data)
        }

        onRunningChanged: {
            if (helper.running)
                root._callbacks = ({});
        }

        onExited: (code, status) => {
            const wasRunning = root.running;
            root.running = false;
            root.synced = false;
            for (const req in root._callbacks) {
                try {
                    root._callbacks[req](false, null, "exited");
                } catch (e) {}
            }
            root._callbacks = ({});
            if (root._restarting || !root.enabled)
                return;
            if (code !== 0) {
                console.warn(`[Health] helper exited with code ${code}`);
                root._failures = wasRunning ? 1 : root._failures + 1;
                root._restarting = true;
                backoff.interval = Math.min(300000, 2000 * Math.pow(2, Math.min(7, root._failures)));
                backoff.restart();
            }
        }
    }
}
