pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Every word System Health shows about a finding.
 *
 * The helper sends codes and facts (`why: "exec-missing"`, `exitStatus: 203`); this turns
 * them into sentences through `Translation.tr`, so they can be translated and so the app,
 * the island strip, the notification fallback and the assistant all say the same thing.
 * Nothing here formats layout: callers decide how much of it fits.
 */
Singleton {
    id: root

    // ── Small formatters ────────────────────────────────────────────────
    function plural(n, one, many) {
        return (Number(n) === 1 ? one : many).arg(n);
    }

    /// "3 h", "1 d 22 h", "12 min", "now" — the age of something, compact.
    function age(ms, now) {
        const t = Number(ms ?? 0);
        if (!(t > 0))
            return "";
        const diff = Math.max(0, (now ?? Date.now()) - t);
        const min = Math.floor(diff / 60000);
        if (min < 1)
            return Translation.tr("now");
        if (min < 60)
            return Translation.tr("%1 min").arg(min);
        const h = Math.floor(min / 60);
        if (h < 24)
            return Translation.tr("%1 h").arg(h);
        const d = Math.floor(h / 24);
        const rest = h % 24;
        return rest > 0 && d < 7 ? Translation.tr("%1 d %2 h").arg(d).arg(rest) : Translation.tr("%1 d").arg(d);
    }

    /// The day a crash or an update happened, relative to today: "Today", "Yesterday", "Thu".
    function dayName(ms, now) {
        const d = new Date(Number(ms));
        const today = new Date(now ?? Date.now());
        const start = t => new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
        const days = Math.round((start(today) - start(d)) / 86400000);
        if (days === 0)
            return Translation.tr("Today");
        if (days === 1)
            return Translation.tr("Yesterday");
        return Qt.locale().dayName(d.getDay(), Locale.ShortFormat);
    }

    /// Binary sizes, the way a disk tool shows them: 477 GiB, 96 MiB.
    function bytes(b) {
        let v = Number(b ?? 0);
        if (!(v > 0))
            return Translation.tr("0 B");
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
    }

    /// Decimal terabytes for SMART "data written", as drive makers rate endurance.
    function terabytes(b) {
        const tb = Number(b ?? 0) / 1e12;
        return tb >= 10 ? `${Math.round(tb)} TB` : `${tb.toFixed(1)} TB`;
    }

    function unitName(unit) {
        // app-com.anthropic.Claude.OpenInCode@d893….service → com.anthropic.Claude.OpenInCode
        const s = String(unit ?? "");
        const m = s.match(/^app-(?:[^-]+-)?(.+?)(?:@[0-9a-f]+)?\.(?:service|scope)$/);
        return m ? m[1] : s;
    }

    function signalName(sig, name) {
        if (name && String(name).length > 0)
            return String(name);
        const names = { 1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGBUS", 8: "SIGFPE", 9: "SIGKILL", 11: "SIGSEGV", 13: "SIGPIPE", 15: "SIGTERM", 31: "SIGSYS" };
        return names[Number(sig)] ?? `SIG${sig}`;
    }

    /// What a signal means, as the one phrase a crash card leads with.
    function signalMeaning(sig) {
        switch (Number(sig)) {
        case 6:
            return Translation.tr("Aborted itself on purpose");
        case 11:
            return Translation.tr("Touched memory it did not own");
        case 7:
            return Translation.tr("Read memory that was not there");
        case 4:
            return Translation.tr("Ran an invalid instruction");
        case 8:
            return Translation.tr("Did an impossible calculation");
        case 5:
            return Translation.tr("Stopped at a debug trap");
        case 31:
            return Translation.tr("Made a forbidden system call");
        case 3:
            return Translation.tr("Was told to quit and dump");
        default:
            return Translation.tr("Crashed");
        }
    }

    // ── Units ───────────────────────────────────────────────────────────
    /// The plain reason a unit failed, from the helper's `why` code.
    function unitWhy(d) {
        const why = String(d?.why ?? "unknown");
        switch (why) {
        case "exec-missing":
            return Translation.tr("The program it starts does not exist");
        case "exec-perm":
            return Translation.tr("The program it starts cannot be run");
        case "user":
            return Translation.tr("The user it runs as does not exist");
        case "namespace":
            return Translation.tr("Its sandbox could not be set up");
        case "start-limit":
            return Translation.tr("It failed too often, so systemd stopped retrying");
        case "timeout":
            return Translation.tr("It took too long to start or stop");
        case "oom":
            return Translation.tr("The kernel killed it to free memory");
        case "signal":
            return Translation.tr("It was killed by %1").arg(root.signalName(d?.exitStatus));
        case "core":
            return Translation.tr("It crashed");
        case "dependency":
            return Translation.tr("Something it needs failed first");
        case "exit":
            return Translation.tr("It exited with status %1").arg(d?.exitStatus ?? "?");
        default:
            return Translation.tr("It stopped with an error");
        }
    }

    /// "203/EXEC · start-limit-hit", the technical line under the plain one.
    function unitStatus(d) {
        const parts = [];
        const st = d?.exitStatus;
        const code = String(d?.exitCode ?? "");
        if (code === "killed" || code === "dumped")
            parts.push(root.signalName(st));
        else if (st !== undefined && st !== null && Number(st) !== 0) {
            const names = { 200: "CHDIR", 203: "EXEC", 209: "STDOUT", 217: "USER", 226: "NAMESPACE", 126: "", 127: "" };
            const label = names[Number(st)];
            parts.push(label ? `${st}/${label}` : String(st));
        }
        const result = String(d?.result ?? "");
        if (result.length > 0 && result !== "success" && result !== "exit-code")
            parts.push(result);
        return parts.join(" · ");
    }

    // ── Findings ────────────────────────────────────────────────────────
    /// The one-line title of a finding.
    function title(f) {
        const d = f?.data ?? {};
        switch (String(f?.kind ?? "")) {
        case "unit":
            return Translation.tr("%1 failed").arg(d.unit ?? "");
        case "appLaunch":
            return Translation.tr("%1 did not start").arg(d.description && d.description.length > 0 ? d.description : root.unitName(d.unit));
        case "restartLoop":
            return Translation.tr("%1 keeps restarting").arg(d.unit ?? "");
        case "crash":
            return f.count > 1 ? Translation.tr("%1 crashed %2 times").arg(d.name ?? "").arg(f.count)
                               : Translation.tr("%1 crashed").arg(d.name ?? "");
        case "journal":
            return Translation.tr("New error from %1").arg(root.sourceLabel(d.source));
        case "disk":
            return Translation.tr("%1 is %2 % full").arg(d.mount ?? "").arg(Math.round(Number(d.usedPct ?? 0)));
        case "drive":
            return Translation.tr("%1 needs attention").arg(d.model ?? Translation.tr("A drive"));
        case "firmware":
            return Translation.tr("Firmware update for %1").arg(d.name ?? d.device ?? "");
        case "security":
            return Translation.tr("Platform security: level %1").arg(d.hsiLevel ?? 0);
        case "reboot":
            return Translation.tr("Restart to finish the kernel update");
        case "deletedLibs":
            return root.plural((d.processes ?? []).length, Translation.tr("%1 program uses replaced libraries"), Translation.tr("%1 programs use replaced libraries"));
        case "pacnew":
            return root.plural((d.files ?? []).length, Translation.tr("%1 config file to merge"), Translation.tr("%1 config files to merge"));
        case "timesync":
            return Translation.tr("The clock is not synchronised");
        case "pressure":
            return d.resource === "memory" ? Translation.tr("The system is short of memory")
                 : d.resource === "io" ? Translation.tr("The disks cannot keep up")
                 : Translation.tr("The processor is overloaded");
        case "thermal":
            return Translation.tr("The processor is throttling");
        case "rebuild": {
            const pkgs = Array.from(d.packages ?? []);
            return pkgs.some(p => p.reason === "quickshell")
                ? Translation.tr("Rebuild Quickshell before you log out")
                : root.plural(pkgs.length, Translation.tr("%1 package needs a rebuild"), Translation.tr("%1 packages need a rebuild"));
        }
        case "shellHelper":
            return Translation.tr("%1 is out of date").arg(d.name ?? "");
        case "shellMemory":
            return Translation.tr("The shell is using %1 of memory").arg(root.bytes(Number(d.rssMb ?? 0) * 1048576));
        case "shellErrors":
            return root.plural(d.kinds ?? f.count, Translation.tr("The shell logged %1 QML error"), Translation.tr("The shell logged %1 QML errors"));
        case "slowBoot":
            return Translation.tr("This boot took %1").arg(root.seconds(d.total));
        case "config":
            return d.state === "malformed" ? Translation.tr("The shell's settings file is broken") : Translation.tr("The shell's settings were repaired");
        default:
            return Translation.tr("Something needs attention");
        }
    }

    /// A unit action's verb as the button that ran it says it.
    function verbLabel(verb) {
        switch (String(verb ?? "")) {
        case "restart": return Translation.tr("Restart");
        case "stop": return Translation.tr("Stop");
        case "start": return Translation.tr("Start");
        case "resetFailed": return Translation.tr("Clear the failure");
        case "disable": return Translation.tr("Disable");
        case "enable": return Translation.tr("Enable");
        default: return String(verb ?? "");
        }
    }

    /// "17.5 s", "1 min 3 s" from milliseconds.
    function seconds(ms) {
        const s = Number(ms ?? 0) / 1000;
        if (s < 60)
            return Translation.tr("%1 s").arg(s < 10 ? s.toFixed(1) : Math.round(s));
        return Translation.tr("%1 min %2 s").arg(Math.floor(s / 60)).arg(Math.round(s % 60));
    }

    /// One package of a `rebuild` finding, in words: why it needs the rebuild.
    function rebuildReason(p) {
        switch (String(p?.reason ?? "")) {
        case "quickshell":
            return p.built && p.installed ? Translation.tr("built for Qt %1, Qt %2 is installed").arg(p.built).arg(p.installed)
                : Translation.tr("built for another Qt");
        case "lib":
            return Translation.tr("cannot find %1").arg(Array.from(p.libs ?? []).slice(0, 3).join(", "));
        case "qt":
            return Translation.tr("uses Qt internals and was built before Qt %1").arg(p.qt ?? "");
        case "python":
            return Translation.tr("installed for %1, %2 is installed now").arg(Array.from(p.python ?? []).join(", ")).arg(p.current ?? "");
        default:
            return "";
        }
    }

    /// The second line: why, in words, and how long.
    function detail(f, now) {
        const d = f?.data ?? {};
        const since = root.age(f?.since, now);
        switch (String(f?.kind ?? "")) {
        case "unit":
        case "appLaunch":
            return [root.unitWhy(d), since].filter(s => s.length > 0).join(" · ");
        case "restartLoop":
            return Translation.tr("%1 restarts in 10 minutes").arg(d.nRestarts ?? f.count);
        case "crash":
            return [root.signalMeaning(d.signal), d.package ? `${d.package} ${d.version ?? ""}`.trim() : ""].filter(s => s.length > 0).join(" · ");
        case "journal":
            return String(d.sample ?? d.template ?? "");
        case "disk":
            return d.etaDays !== null && d.etaDays !== undefined
                ? Translation.tr("%1 free · full in about %2 days").arg(root.bytes(d.avail)).arg(Math.max(1, Math.round(d.etaDays)))
                : Translation.tr("%1 free").arg(root.bytes(d.avail));
        case "drive":
            return root.driveProblems(d).join(" · ");
        case "firmware":
            return d.newVersion ? Translation.tr("%1 → %2").arg(d.version ?? "?").arg(d.newVersion) : "";
        case "security":
            return d.runtimeIssue ? Translation.tr("fwupd reports a runtime issue") : Translation.tr("Some platform checks fail");
        case "reboot":
            return Translation.tr("Running %1, its modules are gone from disk").arg(d.running ?? "");
        case "deletedLibs":
            return (d.processes ?? []).slice(0, 3).map(p => p.comm).join(", ");
        case "pacnew":
            return (d.files ?? []).slice(0, 2).join(", ");
        case "timesync":
            return Translation.tr("Logins, TLS and two-factor codes can fail");
        case "pressure":
            return Translation.tr("%1 % of the last minute was spent waiting").arg(Number(d.avg60 ?? 0).toFixed(1));
        case "thermal":
            return Translation.tr("%1 slowdowns in 5 minutes").arg(d.events5min ?? 0);
        case "rebuild": {
            const pkgs = Array.from(d.packages ?? []);
            const qs = pkgs.find(p => p.reason === "quickshell");
            return qs ? Translation.tr("It was %1; the shell may not start again").arg(root.rebuildReason(qs))
                : pkgs.slice(0, 3).map(p => p.name).join(", ");
        }
        case "shellHelper":
            return Translation.tr("Built from older sources than the shell's");
        case "shellErrors":
            return String(Array.from(d.errors ?? [])[0]?.message ?? "");
        case "shellMemory":
            return d.grown ? Translation.tr("%1 more than in its first hour").arg(root.bytes((Number(d.rssMb ?? 0) - Number(d.baseMb ?? 0)) * 1048576))
                : Translation.tr("Above the %1 limit").arg(root.bytes(Number(d.limitMb ?? 0) * 1048576));
        case "slowBoot":
            return d.unit ? Translation.tr("Usually %1; %2 took %3").arg(root.seconds(d.median)).arg(d.unit).arg(root.seconds(d.unitMs))
                : Translation.tr("Usually %1").arg(root.seconds(d.median));
        case "config":
            return d.state === "malformed" ? Translation.tr("Defaults are in use until it is fixed") : Translation.tr("Some values were reset to their defaults");
        default:
            return "";
        }
    }

    function driveProblems(d) {
        const out = [];
        for (const p of Array.from(d?.problems ?? [])) {
            if (p === "spare") out.push(Translation.tr("spare blocks running out"));
            else if (p === "media") out.push(Translation.tr("media errors"));
            else if (p === "wear") out.push(Translation.tr("%1 % of its rated life used").arg(d.percentUsed ?? "?"));
            else if (p === "critical-warning") out.push(Translation.tr("the drive raised a critical warning"));
            else if (p === "ata-failing") out.push(Translation.tr("SMART predicts failure"));
            else if (p === "selftest") out.push(Translation.tr("the last self-test failed"));
            else if (p === "temperature") out.push(Translation.tr("too hot"));
        }
        return out;
    }

    function sourceLabel(src) {
        const s = String(src ?? "");
        if (s === "kernel")
            return Translation.tr("the kernel");
        const m = s.match(/^user@\d+(?:\.service)?\/(.+)$/);
        return m ? m[1] : s;
    }

    function severityLabel(sev) {
        return sev === "critical" ? Translation.tr("Needs attention") : sev === "warning" ? Translation.tr("Worth a look") : Translation.tr("For your information");
    }

    function journalSeen(g) {
        const seen = Number(g?.bootsSeen ?? 0);
        const window = Number(g?.bootsWindow ?? 5);
        if (seen <= 1)
            return Translation.tr("this boot only");
        if (seen >= window)
            return Translation.tr("every boot");
        return Translation.tr("%1 of %2 boots").arg(seen).arg(window);
    }

    /// A one-sentence summary of what needs attention, for the Overview hero.
    function summary(items, now) {
        const list = Array.from(items ?? []);
        if (list.length === 0)
            return Translation.tr("Services are running, nothing crashed this week and no new errors appeared.");
        return list.slice(0, 2).map(f => `${root.title(f)}: ${root.detail(f, now)}.`).join(" ");
    }
}
