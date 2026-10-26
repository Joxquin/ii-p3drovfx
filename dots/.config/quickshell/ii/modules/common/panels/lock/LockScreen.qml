pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import Qt5Compat.GraphicalEffects

Scope {
    id: root

    // Ensure Idle service is always loaded so the idle inhibitor works in both panel families
    // (e.g. even when "Keep right sidebar loaded" is off in ii).
    Item {
        id: idleServiceAnchor
        property bool _ensureIdleLoaded: Idle.inhibit
    }

    required property Component lockSurface
    property alias context: lockContext
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"

        Loader {
            id: lockSurfaceLoader
            property bool wasLockedOnce: false
            active: wasLockedOnce || GlobalStates.screenLocked
            onActiveChanged: {
                if (active) wasLockedOnce = true;
            }
            visible: GlobalStates.screenLocked || opacity > 0.01
            anchors.fill: parent
            opacity: GlobalStates.screenLocked ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            sourceComponent: root.lockSurface

            // The surface's own screen, for surfaces that ask (the ii lock keys its
            // Always On Display on it).
            Binding {
                target: lockSurfaceLoader.item !== null && lockSurfaceLoader.item.screenName !== undefined ? lockSurfaceLoader.item : null
                property: "screenName"
                value: sessionLockSurface.screen?.name ?? ""
            }
        }

        // Privacy shade: opaque cover shown *instantly* when locking for sleep, so the last
        // frame presented before suspend never shows the desktop mid-transition. Hidden again
        // (with a fade) on wake via the `lockFocus` hook, or on unlock as a fallback.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0Base
            visible: opacity > 0.01
            opacity: root.sleepShade ? 1 : 0
            Behavior on opacity {
                enabled: !root.sleepShade // instant on, animated off
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    // True between `lock sleep` (hypridle before_sleep_cmd) and wake/unlock
    property bool sleepShade: false

    // Second privacy shade, on the Overlay layer. The lock surface's first buffer can come in at
    // scale 1 on fractionally scaled outputs, covering only part of the screen; with
    // misc:session_lock_xray on (needed to show the background layer under the lock surface)
    // the live desktop would show through the rest. This window is mapped at the right scale
    // and is what xray reveals instead.
    Variants {
        id: shadeVariants
        model: Quickshell.screens
        PanelWindow {
            id: shadeWindow
            required property ShellScreen modelData
            screen: modelData
            visible: root.sleepShade || shadeRect.opacity > 0.01
            onBackingWindowVisibleChanged: root.tryCompleteSleepLock()
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:sleepShade"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {}

            Rectangle {
                id: shadeRect
                anchors.fill: parent
                color: Appearance.colors.colLayer0Base
                opacity: root.sleepShade ? 1 : 0
                Behavior on opacity {
                    enabled: !root.sleepShade
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                    "UNLOCK_PASSWORD": lockContext.currentText
                }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        });
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    if (GlobalStates.overlayOpen) {
                        GlobalStates.overlayOpen = false;
                    }
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                }
            }
        }

        onUnlocked: targetAction => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring)
                root.unlockKeyring(); // Async

            // Unlock the screen before exiting, or the compositor will display a
            // fallback lock you can't interact with.
            // Suppress workspace numbers before screenLocked changes so the
            // temporary lock workspace ID cannot flash during unlock.
            GlobalStates.workspaceRestoreInProgress = true;
            GlobalStates.screenLocked = false;
            root.sleepShade = false;

            // Reset
            lockContext.reset();

            // Post-unlock actions
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    function lock() {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        GlobalStates.screenLocked = true;
    }

    // Lock for suspend: no animations race the sleep, and the fingerprint prompt is
    // stopped in the same blocking call. Meant for hypridle's before_sleep_cmd.
    // The shade windows are raised first and the lock itself waits until they are mapped:
    // Wayland requests are handled in order, so the shade is presented before the session lock
    // and the workspace switch it triggers. Otherwise the windows vanish a frame or two before
    // the shade covers the wallpaper.
    property bool sleepLockPending: false
    function lockForSleep() {
        root.sleepShade = true;
        // Latches the inhibit, so the deferred lock won't re-arm the reader
        lockContext.suspendFingerUnlock();
        root.sleepLockPending = true;
        sleepLockFailsafeTimer.restart();
        root.tryCompleteSleepLock();
    }
    function tryCompleteSleepLock() {
        if (!root.sleepLockPending)
            return;
        if (!shadeVariants.instances.every(w => w.backingWindowVisible))
            return;
        root.completeSleepLock();
    }
    function completeSleepLock() {
        sleepLockFailsafeTimer.stop();
        root.sleepLockPending = false;
        root.lock();
    }
    Timer {
        id: sleepLockFailsafeTimer
        interval: 150
        onTriggered: root.completeSleepLock()
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function sleep(): void {
            root.lockForSleep();
        }
        function focus(): void {
            root.sleepShade = false;
            lockContext.shouldReFocus();
        }
        function fingerStop(): void {
            lockContext.suspendFingerUnlock();
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock();
        }
    }

    GlobalShortcut {
        name: "lockFingerStop"
        description: "Stops the lock screen's fingerprint prompt. Meant for hypridle's before_sleep_cmd:" + " suspending with a fingerprint operation in flight crashes some readers' drivers"

        onPressed: {
            lockContext.suspendFingerUnlock();
        }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason" + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            root.sleepShade = false;
            lockContext.shouldReFocus();
        }
    }

    // ── Fast-path startup lock ───────────────────────────────────────────────
    //
    // The full Config singleton (Config.qml, 440 KB) takes several seconds to
    // parse on every cold start. initIfReady() is gated on Config.ready, so the
    // WlSessionLock only activates after that parsing is done — the user sees a
    // live desktop for 3-6 s even when lock.launchOnStartup is true.
    //
    // To fix that: read ONLY the relevant key (lock.launchOnStartup) from the
    // raw config.json file the moment LockScreen mounts, using a lightweight
    // FileView. If the key is true and this is a new Hyprland session, set
    // screenLocked immediately — the compositor blacks out the desktop within
    // one frame instead of waiting for the full parse.
    //
    // The HYPRLAND_INSTANCE_SIGNATURE env var changes on every real login;
    // Persistent.states.hyprlandInstanceSignature stores the last one. We
    // replicate that check here with a Process-free env read so we don't need
    // Persistent.ready either.
    //
    // The existing initIfReady() path still runs when Config and Persistent are
    // ready, but at that point screenLocked is already true so it only picks up
    // whatever else the full config says (useHyprlock, etc.).
    property bool fastLockApplied: false

    FileView {
        id: fastConfigView
        // Same path Config.qml uses; Directories singleton is not yet ready
        // here, so we build it from Quickshell.env directly.
        path: (Quickshell.env("HOME") || "") + "/.config/illogical-impulse/config.json"
        printErrors: false
        onLoaded: {
            // Already locked — nothing to do.
            if (GlobalStates.screenLocked || root.fastLockApplied)
                return;
            try {
                const cfg = JSON.parse(fastConfigView.text());
                const launchOnStartup = cfg?.lock?.launchOnStartup ?? false;
                if (!launchOnStartup)
                    return;
                // If launchOnStartup is enabled, apply lock immediately on boot.
                root.fastLockApplied = true;
                GlobalStates.screenLocked = true;
            } catch (e) {
                // Fall through to normal initIfReady
            }
        }
        Component.onCompleted: fastConfigView.reload()
    }

    FileView {
        id: fastStateView
        path: (Quickshell.env("HOME") || "") + "/.local/state/quickshell/states.json"
        printErrors: false
        Component.onCompleted: fastStateView.reload()
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready)
            return;
        // Fast-path already locked the screen — skip the lock() call but still
        // do any other startup work that needs Config (e.g. fingerprint / keyring).
        if (GlobalStates.screenLocked && root.fastLockApplied) {
            lockContext.tryFingerUnlock();
            return;
        }
        if (Config.options.lock.launchOnStartup && (Persistent.isNewHyprlandInstance || !Persistent.ready)) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }

    Component.onCompleted: initIfReady()

    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
