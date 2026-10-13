# health_watch protocol

`health_watch` is the System Health helper. It reads system state as the user,
never as root, and speaks newline-delimited JSON: one object per line on stdout,
one object per line on stdin. `services/HealthService.qml` is the only reader.

Every object has a `t` (type) key. Times are Unix **milliseconds**. Sizes are
**bytes**. Temperatures are **°C**. Unknown keys must be ignored by both sides, so
either side can grow without breaking the other.

The helper sends **facts and codes, never prose**: text the user reads is built in
QML through `Translation.tr`, so it can be translated. The one exception is raw
system text (log lines, stack frames, unit descriptions), which is passed through.

## Command line

```
health_watch [--state-dir DIR] [--once]
             [--sources units,userUnits,appLaunches,crashes,journal,drives,filesystems,firmware,packages,pressure,thermals,timesync]
             [--known-after 3] [--of-last 5] [--quiet-days 14]
             [--disk-warn 90] [--disk-crit 97] [--psi-mem 10] [--restart-loop 5]
             [--history-days 30]
```

- `--state-dir` defaults to `$XDG_STATE_HOME/quickshell/health` (falling back to
  `~/.local/state/quickshell/health`). Created if missing. A `file://` URL is
  accepted and read as the path it names. `--key=value` works as well as `--key value`.
- `--sources` lists the enabled sources; a source not listed is never touched.
  Default: all of them.
- `--once` runs every enabled source once, prints `ready`, every message the
  initial scan produces, `synced`, and exits 0. Used by tests.
- Thresholds are percentages (0–100). `--restart-loop N`: a unit that restarted
  N or more times within 10 minutes is a restart loop.

## stdout

### `ready` (first line, always)
```json
{"t":"ready","version":1,"stateDir":"/home/u/.local/state/quickshell/health",
 "sources":{"units":true,"userUnits":true,"appLaunches":true,"crashes":true,
            "journal":"full","drives":true,"filesystems":true,"firmware":true,
            "packages":"pacman","pressure":true,"thermals":true,"timesync":true},
 "dumpAccess":"granted","user":"scrimas","bootId":"5b92…"}
```
- `journal`: `"full"` (system journal readable), `"user"` (own journal only), `"none"`.
- `packages`: `"pacman"`, `"dnf"` or `"none"`.
- Any other source: `true` when it works on this machine, `false` when its backend is
  missing (no fwupd, no UDisks2, no thermal_throttle, …) or it was disabled.
- `dumpAccess`: `"granted"` when the user has a read ACL on
  `/var/lib/systemd/coredump` (default ACL included), `"denied"` otherwise.

### `synced`
`{"t":"synced"}` after the initial scan of every enabled source. Findings sent before
it are the starting state; findings after it are live and may alert.

### `finding`
```json
{"t":"finding","op":"upsert","f":{ …Finding… }}
{"t":"finding","op":"resolve","id":"unit:user:zeron.service"}
```
A Finding:

| key | type | meaning |
|---|---|---|
| `id` | string | stable id, see kinds below |
| `kind` | string | see kinds below |
| `sev` | `"critical"`, `"warning"`, `"info"` | |
| `since` | ms | when the problem started |
| `count` | int | occurrences (restarts, crashes, lines), 1 when not countable |
| `fp` | string | noise fingerprint where one applies, else `""`. Unit, app launch and restart-loop findings use their `id` as `fp`, so `mute` works on them too |
| `muted` | bool | the user muted this fingerprint (or, for `crash`, this program). Muted findings are still sent; they never alert |
| `alert` | bool | true only for a live, new, unmuted, critical finding not yet alerted this boot. Never true for `appLaunch` |
| `data` | object | kind-specific facts, below |

Severities the helper assigns: `unit` is `critical` for a `.service`, `warning` for any
other unit type; `restartLoop` is `critical`; `crash` is `critical` while the newest
crash is under 24 h old, else `warning`; `drive` is `critical` for a critical-warning
bit, spare at or below threshold, media errors or ATA failing, else `warning`.
`count` for `unit` is `max(1, NRestarts)`; `since` for `journal` is the group's first
line this boot. Findings whose facts did not change are not re-sent.

Kinds and their `data`:

- `unit` — id `unit:<scope>:<name>`; a failed unit. `data`: `{scope:"system"|"user",
  unit, description, result, exitCode, exitStatus, why, execPath, execExists,
  nRestarts, fragmentPath, activeState, subState}`.
  `exitCode` is systemd's `ExecMainCode` name (`"exited"`, `"killed"`, `"dumped"`),
  `exitStatus` the number. `why` is a code the UI explains:
  `exec-missing` (203, or the ExecStart path does not exist), `exec-perm` (126/203 with
  the file present), `user` (217), `namespace` (226), `start-limit` (result
  `start-limit-hit`), `timeout` (result `timeout`), `oom` (result `oom-kill`),
  `signal` (killed by a signal, `exitStatus` = signal number), `core` (dumped core),
  `dependency` (result `dependency`, `exitStatus` 0), `exit` (any other non-zero exit),
  `unknown`.
- `appLaunch` — id `app:<scope>:<name>`; a failed `app-*@*.service` or `app-*.scope`
  unit created by uwsm/app2unit. `sev` is always `info`, `alert` always false. `data`
  as for `unit`, plus `app` (the desktop id taken from the unit name when it can be).
- `restartLoop` — id `loop:<scope>:<name>`; a unit that restarted `--restart-loop` times
  in 10 minutes and is still restarting. `data`: `{scope, unit, description, nRestarts}`.
- `crash` — id `crash:<exe>`; at least one coredump of that executable in the last 7
  days that was not dismissed. `count` = crashes in 7 days. `data` is a CrashGroup
  without `events` (see `crashes`).
- `journal` — id `journal:<fp>`; a **new** error group (see noise model). `sev` is
  `warning` (or `critical` for priority ≤ 2). `data`: `{source, template, sample,
  priority, countBoot}`.
- `disk` — id `disk:<mount>`; a filesystem over `--disk-warn` (warning) or
  `--disk-crit` (critical), or inodes over the same thresholds. `data`: `{mount,
  device, fstype, total, avail, usedPct, inodesPct, etaDays}`.
- `drive` — id `drive:<udisks id>`; SMART trouble: NVMe critical warning bits, spare
  below threshold, media errors growing, `percentUsed` ≥ 90, ATA `SmartFailing` or
  failing attributes, or a failed self-test. `data`: the Drive object (see `drives`)
  plus `problems: ["spare","media","wear","critical-warning","ata-failing","selftest","temperature"]`.
- `firmware` — id `firmware:<deviceId>`; an fwupd upgrade. `sev` `warning` for a
  security update, else `info`. `data`: `{device, name, vendor, version, newVersion,
  summary, urgency, security}`.
- `security` — id `security:hsi`; fwupd HSI below 2, or a runtime issue (`!`). `sev`
  `info`. `data`: the `system.fwupd` object.
- `reboot` — id `reboot:kernel`; the running kernel's `/usr/lib/modules/<release>` is
  gone. `sev` `warning`. `data`: `{running, installed:[…]}`.
- `deletedLibs` — id `deletedLibs`; own processes mapping a deleted `.so`. `sev`
  `info`. `data`: `{processes:[{pid, comm, exe, libs:[…]}]}`.
- `pacnew` — id `pacnew`; `.pacnew`/`.rpmnew` files under `/etc`. `sev` `info`.
  `data`: `{files:[…]}`.
- `timesync` — id `timesync`; the kernel clock reported unsynchronised (adjtimex
  `STA_UNSYNC`) on two checks in a row, five minutes apart. `sev` `warning`. `data`:
  `{ntp, synced}`. `ntp` comes from timedate1 and is asked only at start and on
  `rescan`, so timedated is not woken every five minutes; `null` when unknown.
- `pressure` — id `pressure:memory` (or `io`, `cpu`); `some avg60` above `--psi-mem`
  (memory) or 40 (io, cpu) for at least 60 s. `sev` `warning`. `data`: `{resource,
  avg10, avg60, top:[{pid, comm, rssBytes}]}` (top 3 own processes by RSS for memory).
- `thermal` — id `thermal:throttle`; 20 or more new throttle events in 5 minutes.
  `sev` `warning`. `data`: `{events5min, total, tempC}`.

### `crashes`
Sent at start and whenever the 7-day set changes:
```json
{"t":"crashes","groups":[{
  "exe":"/usr/lib/fprintd","name":"fprintd","root":true,"count":6,
  "package":"fprintd","version":"1.94.5-1","signal":6,"signalName":"SIGABRT",
  "unit":"fprintd.service","last":1791787756000,"first":1791299499000,
  "trace":[{"fn":"abort","module":"libc.so.6"},{"fn":"fpi_device_verify_complete","module":"libfprint-2.so.2"}],
  "ownFrame":2,
  "afterUpdate":{"name":"fprintd","from":"1.94.4-1","to":"1.94.5-1","time":1791200000000},
  "coreReadable":false,"muted":false,"dismissedAt":0,
  "events":[{"time":1791787756000,"pid":628436,"uid":0,"signal":6,"coreFile":"/var/lib/systemd/coredump/core.fprintd…zst","coreReadable":false}]}]}
```
- Groups come from journal entries with `MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1`
  (systemd-coredump), last 7 days, grouped by `COREDUMP_EXE`.
- `root`: the crashing uid was 0. `trace`: the first thread's frames of the newest
  crash, parsed from the message's "Stack trace of thread" block, at most 12.
- `ownFrame`: index of the first frame whose module is not libc, libstdc++, libgcc,
  ld-linux, libglib/libgobject/libgio, libpthread or libsystemd; `-1` when none.
- `afterUpdate`: the newest `upgraded`/`installed` line in the package log for the
  crash's package, if it happened within the 7 days *and* before the first crash.
- `muted`: the user muted this program. Muted groups are still listed.

### `updates`
```json
{"t":"updates","transactions":[{"time":1791200000000,"count":42,"names":["fprintd","hyprland","…"]}]}
```
Package transactions of the last 7 days, newest last, `names` capped at 30.

### `journal`
Sent after the initial scan and at most every 5 s while new groups arrive:
```json
{"t":"journal","access":"full","groups":[{
  "fp":"kernel|intel-ipu7 #:#:#.#: Failed to get runtime PM","source":"kernel",
  "template":"intel-ipu7 #:#:#.#: Failed to get runtime PM",
  "sample":"intel-ipu7 0000:00:05.0: Failed to get runtime PM","priority":3,
  "countBoot":9,"bootsSeen":1,"bootsWindow":5,"firstSeen":…,"lastSeen":…,
  "state":"new"}],
 "noise":{"knownGroups":206,"knownLines":1050,"mutedGroups":0}}
```
- `state`: `"new"`, `"known"`, `"muted"`. At most 300 groups: every `new` and
  `muted` group, then `known` groups by `countBoot`. Only `new` groups become `journal`
  findings: muting or marking a new group known resolves its finding.

### `drives`
```json
{"t":"drives","drives":[{"id":"SAMSUNG_MZVL81T0HELB_…","path":"/org/freedesktop/UDisks2/drives/…",
  "model":"SAMSUNG MZVL81T0HELB-00BKS","kind":"nvme","size":1024209543168,"tempC":33,
  "percentUsed":3,"availSpare":100,"spareThresh":5,"powerOnHours":3094,
  "dataWritten":24670024704000,"dataRead":42201167872000,"mediaErrors":0,
  "unsafeShutdowns":95,"criticalWarning":[],"ataFailing":false,"ataFailingAttrs":0,
  "selftest":"success","selftestPct":-1,"smartUpdated":1791888148000}]}
```
NVMe and ATA drives that expose SMART through UDisks2. Unknown fields are `null`.
`tempC` has one decimal. A drive at 70 °C or more gets the `temperature` problem.

### `vitals`
Every 15 s, every 2 s while the app is visible:
```json
{"t":"vitals","psi":{"memory":{"some10":0.0,"some60":0.03,"full10":0.0},"io":{…},"cpu":{…}},
 "psiHistory":[0.0,0.03,…],"throttle":{"total":0,"last5min":0},"cpuTempC":46,
 "fs":[{"mount":"/","device":"/dev/nvme0n1p2","fstype":"ext4","total":…,"avail":…,
        "usedPct":47.1,"inodesPct":3.2,"etaDays":null}],
 "memory":{"total":…,"available":…}}
```
- `psiHistory`: memory `some10` samples, oldest first, at most 120 (one per sample).
- `fs`: real filesystems from `/proc/self/mounts`, one entry per device (the shortest
  mount point names it). Re-read every 60 s; `vitals` in between repeat the last read.
  `etaDays`: days until full at the last 24 h fill rate, `null` when not filling or
  observed for less than an hour.
- `pressure` is polled, not triggered: `/proc/pressure/*` is read with every `vitals`.

### `system`
At start, after every package transaction, and every 30 minutes:
```json
{"t":"system",
 "kernel":{"running":"7.2.9-2-cachyos","modulesPresent":true,"installed":["7.2.9-2-cachyos","7.2.9-arch1-1"]},
 "packages":{"manager":"pacman","lastUpgrade":1791787756000,"orphans":["…"],"pacnew":["/etc/…pacnew"]},
 "deletedLibs":[{"pid":1234,"comm":"firefox","exe":"/usr/lib/firefox/firefox","libs":["/usr/lib/libssl.so.3"]}],
 "fwupd":{"available":true,"hsi":"HSI:1!","hsiLevel":1,"runtimeIssue":true,
          "attrs":[{"id":"org.fwupd.hsi.Kernel.Lockdown","name":"Linux kernel lockdown","success":false,"result":"not-enabled","level":1}],
          "upgrades":[]},
 "timesync":{"ntp":true,"synced":true},
 "cleanup":{"journal":222400000,"pacmanCache":100663296,"coredumps":3100000,"trash":0}}
```

### `history`
```json
{"t":"history","days":[{"date":"2026-10-13","failed":3,"crashes":2,"newErrors":2,"diskPct":47.1,"psiMemPeak":0.4}]}
```
Daily summary, oldest first, `--history-days` long. Sent once the initial scan has
filled today's row, and when a day rolls. `failed` is the most failed units seen at
once that day.

### `access`
`{"t":"access","dumpAccess":"granted"}` after every `rescan`, so the UI sees a grant or
revoke done by `crash-access.sh` without restarting the helper.

`fwupd.attrs` entries also carry `runtimeIssue` (bool) and `flags` (fwupd's own flag
names). Runtime attributes have no HSI level; their `level` is `0`.

### `reply`
`{"t":"reply","req":7,"ok":true,"data":…}` or `{"t":"reply","req":7,"ok":false,"error":"code","message":"raw detail"}`.

### `log`
`{"t":"log","level":"warn","msg":"…"}` for diagnostics; the shell prints them.

## stdin

```json
{"t":"visible","app":true}            app window shown/hidden: fast vitals while shown
{"t":"rescan"}                        re-run every source now, then send `synced`
{"t":"query","req":1,"what":"unitLog","scope":"user","unit":"zeron.service","lines":40}
      → data: {"lines":["Oct 11 14:16:59 host systemd[1452]: …"]}
{"t":"query","req":2,"what":"crashInfo","exe":"/usr/lib/fprintd"}
      → data: {"message":"full systemd-coredump message text of the newest crash (30 days)",
               "fields":{COREDUMP_EXE, _COMM, _PID, _UID, _SIGNAL, _SIGNAL_NAME, _TIMESTAMP,
                         _UNIT, _USER_UNIT, _FILENAME, _PACKAGE_JSON}}
      Never COREDUMP_CMDLINE, _ENVIRON, _CWD, _OPEN_FDS or any _PROC_* field: they can
      hold secrets. Unknown `what` → error "unknown"; a unit or identifier starting with
      "-" → error "args".
{"t":"query","req":3,"what":"journalGroup","fp":"kernel|…","lines":20}
      → data: {"lines":["…"]}
{"t":"query","req":4,"what":"journalSearch","unit":"","identifier":"","grep":"","priority":3,"sinceHours":24,"limit":40}
      → data: {"lines":["…"]}   (limit capped at 100, sinceHours at 168)
{"t":"query","req":5,"what":"package","path":"/usr/lib/fprintd"}
      → data: {"name":"fprintd","version":"1.94.5-1"}
{"t":"act","req":6,"verb":"restart","scope":"system","unit":"foo.service"}
      verbs: restart, stop, start, resetFailed, disable, enable. System scope goes through
      systemd's D-Bus API with interactive authorization allowed, so polkit asks.
      → data: {} once the job is queued
{"t":"act","req":7,"verb":"selftest","drive":"/org/freedesktop/UDisks2/drives/…"}
{"t":"mute","fp":"…"}  {"t":"unmute","fp":"…"}  {"t":"markKnown","fp":"…"}
{"t":"muteProgram","exe":"/usr/bin/x"}  {"t":"unmuteProgram","exe":"/usr/bin/x"}
{"t":"dismiss","id":"crash:/usr/lib/fprintd"}    hides a crash or appLaunch finding until it happens again
{"t":"resetNoise"}                    forget every mute, known group and dismissal; rebuild the baseline
{"t":"quit"}
```

Nothing on stdin can return the bytes of a core dump. `crashInfo` returns the journal
message only.

## Noise model

- **Fingerprint**: `<source>|<template>`. `source` is `kernel` for transport `kernel`;
  else `user@<uid>/<unit>` from `_SYSTEMD_USER_UNIT`; else `_SYSTEMD_UNIT`; else
  `SYSLOG_IDENTIFIER`; else `_COMM`. Units named per boot (`*.scope`, `session-*`,
  `app-*`) and the user manager `user@<uid>.service` are skipped in favour of the
  identifier, or the same complaint would get a new fingerprint every boot. Instance
  units lose their instance: `systemd-coredump@1-4097-…service` → `systemd-coredump@#.service`.
  `template` is `MESSAGE_ID` when set, else the first line of `MESSAGE` with: paths
  under `$HOME` → `~/#path`, other absolute paths kept, PCI ids (`0000:00:05.0`) →
  `#:#:#.#`, MACs, UUIDs and IPv4 (with an optional port) → `#`, `0x…` runs and
  standalone hex words of six or more characters containing a digit → `#`, digit runs
  → `#` unless they follow a letter (`ipu7`, `x86`, `PNP0C0B` stay), collapsed
  whitespace, cut at 160 chars. IPv6 is not matched as a whole; its hex groups mostly
  fall to the hex and digit rules.
- **Known**: seen on `--known-after` or more of the last `--of-last` boots (current boot
  included). **New**: never seen, or not seen for `--quiet-days`. **Muted**: by user.
- **Baseline**: on the first run (no state file), every fingerprint from the boots
  journald still holds (up to `--of-last`) is recorded, so nothing in that history is
  `new`.
- Journal input is priority `err` and worse (`-p 0..3`) from the current boot,
  followed live. Coredump messages arrive the same way (they are priority 2) and feed
  `crashes` rather than journal groups.

## State files (in the state dir)

- `state.json` — fingerprints `{fp: {boots:[bootId…], firstSeen, lastSeen, muted, known}}`,
  `mutedPrograms`, `dismissed {id: ms}`, `alerted {fp|id: bootId}`, `journalCursor`.
- `history.json` — the daily summaries.
Both are written atomically (temp file + rename), at most once a minute and on quit.
