pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.health.components

/**
 * Every System Health option: alerts, what to watch, the noise model, thresholds, the
 * assistant, and the helper with its one privileged extra — read access to system crash
 * dumps. Writes go straight to Config; the helper restarts with the new values.
 */
Rectangle {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width

    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2, root.wide ? 1240 : ClockStyle.sheetMaxWidth * 1.3)
    readonly property var h: Config.options.health

    property bool confirmGrant: false
    property bool confirmReset: false

    color: ClockStyle.colBackground

    component Toggle: StyledSwitch {
        property var target
        property string key
        checked: Boolean(target?.[key])
        checkable: false
        onClicked: target[key] = !target[key]
    }

    component Stepper: ClockStepper {
        property var target
        property string key
        value: Number(target?.[key] ?? 0)
        onMoved: v => target[key] = v
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 3
        clip: true

        GridLayout {
            id: column
            x: (flick.width - width) / 2
            y: ClockStyle.gapSmall
            width: root.contentWidth
            columns: root.wide ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gapHuge
            uniformCellWidths: true

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Alerts")
                symbol: "notifications"

                ClockSettingsRow {
                    first: true
                    symbol: "smart_display"
                    title: Translation.tr("Island alert for new problems")
                    description: Translation.tr("A strip with the fix as its button, for a service that failed or a program that crashed")
                    Toggle { target: root.h.alerts; key: "island" }
                }
                ClockSettingsRow {
                    symbol: "notifications"
                    title: Translation.tr("Notification when the island is off")
                    Toggle { target: root.h.alerts; key: "notifyFallback" }
                }
                ClockSettingsRow {
                    symbol: "fullscreen"
                    title: Translation.tr("Hold alerts in fullscreen and Do Not Disturb")
                    description: Translation.tr("They arrive as one summary when you leave")
                    Toggle { target: root.h.alerts; key: "holdInFullscreen" }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "speed"
                    title: Translation.tr("At most, every 10 minutes")
                    description: Translation.tr("More fold into one summary")
                    Stepper { target: root.h.alerts; key: "maxPer10Min"; from: 1; to: 10 }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("What to watch")
                symbol: "visibility"

                Repeater {
                    model: [
                        { key: "units", symbol: "settings_alert", title: Translation.tr("System services") },
                        { key: "userUnits", symbol: "person", title: Translation.tr("Your services") },
                        { key: "appLaunches", symbol: "rocket_launch", title: Translation.tr("App launches that fail") },
                        { key: "crashes", symbol: "heart_broken", title: Translation.tr("Crashes") },
                        { key: "journal", symbol: "receipt_long", title: Translation.tr("New journal errors") },
                        { key: "drives", symbol: "storage", title: Translation.tr("Drive health (SMART)") },
                        { key: "filesystems", symbol: "hard_drive", title: Translation.tr("Free space") },
                        { key: "firmware", symbol: "memory", title: Translation.tr("Firmware and platform security") },
                        { key: "packages", symbol: "package_2", title: Translation.tr("Update chores") },
                        { key: "pressure", symbol: "speed", title: Translation.tr("Memory and disk pressure") },
                        { key: "thermals", symbol: "device_thermostat", title: Translation.tr("Throttling") },
                        { key: "timesync", symbol: "schedule", title: Translation.tr("Clock synchronisation") }
                    ]

                    ClockSettingsRow {
                        required property var modelData
                        required property int index
                        first: index === 0
                        last: index === 11
                        symbol: modelData.symbol
                        title: modelData.title
                        Toggle { target: root.h.sources; key: modelData.key }
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Noise")
                symbol: "volume_off"

                ClockSettingsRow {
                    first: true
                    symbol: "event_repeat"
                    title: Translation.tr("Known after this many boots")
                    description: Translation.tr("An error group seen this often never alerts")
                    Stepper { target: root.h.noise; key: "knownAfterBoots"; from: 1; to: root.h.noise.ofLastBoots }
                }
                ClockSettingsRow {
                    symbol: "history"
                    title: Translation.tr("Out of the last boots")
                    Stepper { target: root.h.noise; key: "ofLastBoots"; from: 2; to: 20 }
                }
                ClockSettingsRow {
                    symbol: "hourglass_empty"
                    title: Translation.tr("New again after a quiet spell of")
                    Stepper { target: root.h.noise; key: "quietDaysForNew"; from: 1; to: 90; format: v => Translation.tr("%1 d").arg(v) }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "restart_alt"
                    title: Translation.tr("Forget mutes and known groups")
                    description: root.confirmReset ? Translation.tr("Press again: every mute and dismissal goes, and the baseline is rebuilt") : Translation.tr("Rebuilds the baseline from the boots the journal still has")
                    ClockButton {
                        label: root.confirmReset ? Translation.tr("Forget") : Translation.tr("Reset")
                        danger: root.confirmReset
                        onClicked: {
                            if (!root.confirmReset) {
                                root.confirmReset = true;
                                return;
                            }
                            root.confirmReset = false;
                            HealthService.resetNoise();
                        }
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Thresholds")
                symbol: "tune"

                ClockSettingsRow {
                    first: true
                    symbol: "hard_drive"
                    title: Translation.tr("Warn when a disk is this full")
                    Stepper { target: root.h.thresholds; key: "diskWarnPercent"; from: 50; to: root.h.thresholds.diskCritPercent - 1; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    symbol: "error"
                    title: Translation.tr("Critical when a disk is this full")
                    Stepper { target: root.h.thresholds; key: "diskCritPercent"; from: root.h.thresholds.diskWarnPercent + 1; to: 99; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    symbol: "memory"
                    title: Translation.tr("Memory stall to warn at")
                    description: Translation.tr("Share of the last minute spent waiting for memory")
                    Stepper { target: root.h.thresholds; key: "psiMemPercent"; from: 1; to: 80; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "autorenew"
                    title: Translation.tr("A restart loop is this many restarts")
                    description: Translation.tr("Within 10 minutes")
                    Stepper { target: root.h.thresholds; key: "restartLoop"; from: 2; to: 50 }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Assistant")
                symbol: "auto_awesome"

                ClockSettingsRow {
                    first: true
                    symbol: "auto_awesome"
                    title: Translation.tr("Explain with the assistant")
                    description: SearchPanelRegistry.aiPolicyEnabled
                        ? Translation.tr("Shows the ✦ button. Nothing is sent until you press it.")
                        : Translation.tr("AI is off for the whole shell, so the button stays hidden.")
                    Toggle { target: root.h.assistant; key: "enable" }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "visibility_off"
                    title: Translation.tr("Redact before sending")
                    description: Translation.tr("User and host names, the home path, IP and MAC addresses. Crash dumps are never sent.")
                    Toggle { target: root.h.assistant; key: "redact" }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Helper and access")
                symbol: "build"

                ClockSettingsRow {
                    first: true
                    symbol: "deployed_code"
                    title: "health_watch"
                    description: HealthService.helperBuild.building ? (HealthService.helperBuild.progressText || Translation.tr("Building…"))
                        : HealthService.helperBuild.buildResult === "failed" ? Translation.tr("The build failed: %1").arg(HealthService.helperBuild.failureSummary?.(HealthService.helperBuild.buildOutput.split("\n")) ?? "")
                        : !HealthService.binaryPresent ? Translation.tr("Not built yet")
                        : HealthService.helperBuild.outdated ? Translation.tr("Built from older sources; rebuild to get the fixes")
                        : HealthService.running ? Translation.tr("Running") : Translation.tr("Stopped")
                    ClockButton {
                        visible: HealthService.helperBuild.cargoAvailable && (HealthService.helperBuild.outdated || !HealthService.binaryPresent || HealthService.helperBuild.buildResult === "failed")
                        enabled: !HealthService.helperBuild.building
                        label: HealthService.binaryPresent ? Translation.tr("Rebuild") : Translation.tr("Build")
                        symbol: "build"
                        onClicked: HealthService.helperBuild.build()
                    }
                }
                ClockSettingsRow {
                    symbol: "receipt_long"
                    title: Translation.tr("Journal access")
                    description: HealthService.journalAccess === "full" ? Translation.tr("The whole system's journal is readable")
                        : HealthService.journalAccess === "user" ? Translation.tr("Only your own. Join the systemd-journal group for the rest.")
                        : Translation.tr("Unknown until the helper runs")
                }
                ClockSettingsRow {
                    symbol: "lock_open"
                    title: Translation.tr("Read system crash dumps")
                    description: HealthService.accessBusy ? Translation.tr("Waiting for the password…")
                        : HealthService.accessError === "cancelled" ? Translation.tr("The password prompt was dismissed; nothing changed.")
                        : HealthService.accessError.length > 0 ? Translation.tr("It did not work: %1").arg(HealthService.accessError)
                        : HealthService.dumpAccess === "granted" ? Translation.tr("Granted to your account. Dumps never leave this computer.")
                        : Translation.tr("Only root can read them. The journal's stack trace still shows on the Crashes page.")
                    ClockButton {
                        visible: !root.confirmGrant
                        enabled: !HealthService.accessBusy
                        label: HealthService.dumpAccess === "granted" ? Translation.tr("Revoke") : Translation.tr("Allow")
                        danger: HealthService.dumpAccess === "granted"
                        onClicked: {
                            if (HealthService.dumpAccess === "granted")
                                HealthService.setDumpAccess(false);
                            else
                                root.confirmGrant = true;
                        }
                    }
                }
                // Said in words before the password prompt, as promised.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.confirmGrant
                    implicitHeight: grantColumn.implicitHeight + ClockStyle.gapLarge * 2
                    color: ClockStyle.colTertiaryContainer
                    radius: ClockStyle.radiusSmall / 2

                    ColumnLayout {
                        id: grantColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: ClockStyle.cardPadding
                        }
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Let your account read crash dumps of system programs. A dump is a copy of a program's memory and can contain passwords or keys. They never leave this computer, and the assistant never sees them.")
                            wrapMode: Text.Wrap
                            font.pixelSize: ClockStyle.textSmall + 1
                            color: ClockStyle.colOnTertiaryContainer
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: ClockStyle.gapSmall
                            ClockButton {
                                label: Translation.tr("Cancel")
                                variant: "text"
                                onClicked: root.confirmGrant = false
                            }
                            ClockButton {
                                label: Translation.tr("Allow, ask for my password")
                                variant: "filled"
                                symbol: "lock_open"
                                onClicked: {
                                    root.confirmGrant = false;
                                    HealthService.setDumpAccess(true);
                                }
                            }
                        }
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "history"
                    title: Translation.tr("Keep daily summaries for")
                    Stepper { target: root.h; key: "historyDays"; from: 7; to: 365; format: v => Translation.tr("%1 d").arg(v) }
                }
            }
        }
    }
}
