pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The System Health assistant's finished answers, one per subject, kept on disk.
 *
 * An answer outlives its sheet, the tab, the window and a shell restart; only the
 * card's close button removes it, and a new question on the same subject replaces it.
 * Keys are the assistant's subject keys ("overview", "finding:<id>", "crash:<exe>",
 * journal groups). Only finished answers are kept: a run cut off half way has nothing
 * worth reading later.
 *
 * One top-level `var` in the adapter, as AppUsage and AiUsage do: a `var` inside a
 * nested JsonObject trips Quickshell's JSON adapter.
 */
Singleton {
    id: root

    /// { key: { question, answer, proposal, folded, at } }
    property var entries: ({})
    property bool ready: false
    /// Old answers make way for new ones past this many subjects.
    readonly property int maxEntries: 40

    readonly property string path: FileUtils.trimFileProtocol(`${Directories.state}/user/health/answers.json`)

    function entry(key: string): var {
        return root.entries[key] ?? null;
    }

    function put(key: string, value: var): void {
        if (key.length === 0)
            return;
        const next = Object.assign({}, root.entries);
        next[key] = {
            question: String(value?.question ?? ""),
            answer: String(value?.answer ?? ""),
            proposal: value?.proposal ?? null,
            folded: value?.folded === true,
            at: Date.now()
        };
        const keys = Object.keys(next).sort((a, b) => (next[b].at ?? 0) - (next[a].at ?? 0));
        for (const old of keys.slice(root.maxEntries))
            delete next[old];
        root.entries = next;
        saveTimer.restart();
    }

    function patch(key: string, fields: var): void {
        const current = root.entries[key];
        if (!current)
            return;
        const next = Object.assign({}, root.entries);
        next[key] = Object.assign({}, current, fields);
        root.entries = next;
        saveTimer.restart();
    }

    function remove(key: string): void {
        if (root.entries[key] === undefined)
            return;
        const next = Object.assign({}, root.entries);
        delete next[key];
        root.entries = next;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: {
            // A change before the file was read would otherwise overwrite what it holds.
            if (!root.ready) {
                saveTimer.restart();
                return;
            }
            adapter.entries = root.entries;
            fileView.writeAdapter();
        }
    }

    FileView {
        id: fileView
        path: root.path
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const loaded = adapter.entries;
            if (loaded && typeof loaded === "object" && !Array.isArray(loaded))
                root.entries = Object.assign({}, loaded, root.entries);
            root.ready = true;
        }
        onLoadFailed: error => {
            // No file yet is the normal first start; anything else still must not
            // block saving.
            root.ready = true;
        }

        adapter: JsonAdapter {
            id: adapter
            property var entries: ({})
        }
    }
}
