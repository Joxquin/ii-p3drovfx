pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import "./discordVoice" as DiscordPackage

Singleton {
    id: root

    signal requestCenter(string identifier)

    readonly property var discordVoiceIcon: Component { DiscordPackage.TaskbarGlyph {} }

    readonly property var widgetSymbols: {
        "crosshair": "point_scan",
        "fpsLimiter": "animation",
        "floatingImage": "imagesmode",
        "recorder": "screen_record",
        "media": "music_note",
        "resources": "browse_activity",
        "notes": "note_stack",
        "volumeMixer": "volume_up",
        "discordVoice": "voice_chat",
        "perfMonitor": "speed"
    }

    readonly property list<var> availableWidgets: {
        if (!Config?.ready) return []

        let result = []
        const configButtons = Config.options.overlay.buttons ?? []

        for (let i = 0; i < configButtons.length; i++) {
            const id = configButtons[i]
            if (widgetSymbols.hasOwnProperty(id)) {
                const entry = {
                    identifier: id,
                    materialSymbol: widgetSymbols[id]
                }
                if (id === "discordVoice") {
                    entry.iconComponent = root.discordVoiceIcon
                }
                result.push(entry)
            }
        }

        return result
    }
    readonly property bool hasPinnedWidgets: root.pinnedWidgetIdentifiers.length > 0

    property list<string> pinnedWidgetIdentifiers: []
    // The sampler of the live performance HUD, for its IPC.
    property QtObject perfSampler: null
    property list<var> clickableWidgets: []

    function pin(identifier: string, pin = true) {
        if (pin) {
            if (!root.pinnedWidgetIdentifiers.includes(identifier)) {
                root.pinnedWidgetIdentifiers.push(identifier)
            }
        } else {
            root.pinnedWidgetIdentifiers = root.pinnedWidgetIdentifiers.filter(id => id !== identifier)
        }
    }

    // Shows or hides the performance HUD pinned over the game, without opening
    // the overlay (IPC `perfMonitor toggle` / the perfMonitorToggle shortcut).
    function togglePerfMonitor() {
        const id = "perfMonitor";
        const entry = Persistent.states.overlay.perfMonitor;
        const open = Persistent.states.overlay.open;
        if (open.includes(id) && entry.pinned) {
            Persistent.states.overlay.open = open.filter(w => w !== id);
            root.pin(id, false);
            return;
        }
        if (!open.includes(id))
            Persistent.states.overlay.open = [...open, id];
        entry.pinned = true;
        // Pinning here too arms the overlay window, which creates the widget.
        root.pin(id, true);
    }

    // A pinned HUD comes back with the shell. Other widgets only register
    // once the overlay window exists, so the window has to be armed for it.
    function restorePinnedPerfMonitor() {
        if (!Persistent.ready)
            return;
        const entry = Persistent.states.overlay.perfMonitor;
        if (entry?.pinned && Persistent.states.overlay.open.includes("perfMonitor")) {
            root.pin("perfMonitor", true);
            return;
        }
        // Not coming back: a crash may have left MangoHud logging armed for
        // a HUD nobody is running (the script disarms only when it is idle).
        if (!root.perfIdleChecked) {
            root.perfIdleChecked = true;
            Quickshell.execDetached(["python3", `${Directories.scriptPath}/perfOverlay/perf_monitor.py`, "disarm"]);
        }
    }
    property bool perfIdleChecked: false

    // -------------------------------------------------------------- auto pin
    // The Discord overlay and the performance HUD put themselves on screen,
    // pinned, while their condition holds: a voice call for the former, a
    // detected game for the latter. The pin follows that condition both ways,
    // so a missed signal or a shell restart cannot leave one pinned behind.
    // With the option off the widget is left alone, which is how a HUD the
    // user keeps pinned on purpose is kept.

    function setAutoPin(identifier: string, wanted: bool) {
        if (!Persistent.ready || !root.availableWidgets.some(w => w.identifier === identifier))
            return;
        if (Config.options.overlay?.[identifier]?.autoPin === false)
            return;
        const entry = Persistent.states.overlay[identifier];
        if (!entry)
            return;
        const open = Persistent.states.overlay.open;
        if (wanted) {
            if (!open.includes(identifier))
                Persistent.states.overlay.open = [...open, identifier];
            if (!entry.pinned)
                entry.pinned = true;
            // Pinning here too arms the overlay window, which creates the widget.
            root.pin(identifier, true);
        } else {
            if (open.includes(identifier))
                Persistent.states.overlay.open = open.filter(id => id !== identifier);
            if (entry.pinned)
                entry.pinned = false;
            root.pin(identifier, false);
        }
    }

    // Also runs on boot, so a call or a game already up comes back pinned.
    function syncAutoPins() {
        root.setAutoPin("discordVoice", DiscordVoice.inVoice);
        root.setAutoPin("perfMonitor", GameDetector.gameRunning);
    }

    Component.onCompleted: {
        root.restorePinnedPerfMonitor();
        root.syncAutoPins();
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restorePinnedPerfMonitor();
            root.syncAutoPins();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.syncAutoPins();
        }
    }
    // Flipping the option on while a call or a game is already up pins at once.
    Connections {
        target: Config.options?.overlay?.discordVoice ?? null
        function onAutoPinChanged() {
            root.setAutoPin("discordVoice", DiscordVoice.inVoice);
        }
    }
    Connections {
        target: Config.options?.overlay?.perfMonitor ?? null
        function onAutoPinChanged() {
            root.setAutoPin("perfMonitor", GameDetector.gameRunning);
        }
    }
    Connections {
        target: DiscordVoice
        function onInVoiceChanged() {
            root.setAutoPin("discordVoice", DiscordVoice.inVoice);
        }
    }
    Connections {
        target: GameDetector
        function onGameRunningChanged() {
            root.setAutoPin("perfMonitor", GameDetector.gameRunning);
        }
    }

    function registerClickableWidget(widget: QtObject, clickable = true) {
        if (clickable) {
            if (!root.clickableWidgets.includes(widget)) {
                root.clickableWidgets.push(widget)
            }
        } else {
            root.clickableWidgets = root.clickableWidgets.filter(w => w !== widget)
        }
    }
}
