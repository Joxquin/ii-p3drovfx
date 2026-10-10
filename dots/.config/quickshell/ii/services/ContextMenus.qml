pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * The ii right-click menus as data: which menus exist, the entries each one
 * can carry, and how the user arranged them (Config.options.contextMenu).
 *
 * A menu still decides at runtime which of its entries apply - an origin, a
 * family, a clipboard holding files - and hands those live entries to
 * `arrange()`. That puts them in the user's order, drops the hidden ones,
 * splits off the icon bar in the compact style and adds the user's own
 * command entries. Separators are entries too ("separator", "separator-2"…),
 * so a group break is something the user can move or remove like any row.
 *
 * A new menu joins by adding a declaration to `menus` and passing its live
 * entries through `arrange(id, entries)`; the style, the editor in Settings
 * and the custom entries then work for it with nothing else to wire.
 */
Singleton {
    id: root

    readonly property var cfg: Config.options.contextMenu
    readonly property bool compact: (root.cfg?.style ?? "comfortable") === "compact"
    readonly property bool cascade: (root.cfg?.submenus ?? "inline") === "cascade"

    // ── Metrics ──────────────────────────────────────────────────────────────
    // Compact: the card fits its content between these, the rows are 34 px.
    // A strip of wallpapers takes the full width.
    readonly property real compactMaxWidth: 220
    readonly property real compactMinWidth: 200
    // A page with a grid on it (colors, presets) needs more than a row does.
    readonly property real compactPageWidth: 260
    // Between the menu and a cascaded submenu card.
    readonly property real cascadeGap: 6
    readonly property real compactPadding: 6
    readonly property real comfortablePadding: 8

    // ── Declarations ─────────────────────────────────────────────────────────
    // `bar`: placed in the compact icon bar unless the user moved it.
    // `submenu`: opens a page (a chevron in the list, the page in a bar icon).
    // `block`: a run of entries supplied at runtime (an app's own actions);
    // it moves and hides as one, its rows are not editable one by one.
    readonly property var menus: [
        {
            "id": "desktop",
            "name": "Desktop",
            "icon": "desktop_windows",
            "description": "Right-click on the wallpaper, the bar or the dock",
            "entries": [
                { "id": "colors", "symbol": "palette", "title": "Colors & themes", "submenu": true, "bar": true },
                { "id": "presets", "symbol": "style", "title": "Presets", "submenu": true, "bar": true },
                { "id": "style", "symbol": "wallpaper", "title": "Wallpaper & style", "defaultHidden": true },
                { "id": "widgets", "symbol": "widgets", "title": "Desktop widgets", "defaultHidden": true },
                { "id": "apps", "symbol": "apps", "title": "Home screen apps" },
                { "id": "edit", "symbol": "edit", "title": "Edit layout", "bar": true },
                { "id": "separator", "separator": true },
                { "id": "new", "symbol": "add", "title": "New", "submenu": true },
                { "id": "paste", "symbol": "content_paste", "title": "Paste" },
                { "id": "icons", "symbol": "grid_view", "title": "Desktop icons", "submenu": true },
                { "id": "separator-2", "separator": true },
                { "id": "settings", "symbol": "settings", "title": "Settings", "bar": true }
            ]
        },
        {
            "id": "desktopItem",
            "name": "Desktop icon",
            "icon": "draft",
            "description": "Right-click on a file, folder or app on the desktop",
            "entries": [
                { "id": "open", "symbol": "open_in_new", "title": "Open" },
                { "id": "pinDock", "symbol": "push_pin", "title": "Pinned to dock" },
                { "id": "separator", "separator": true },
                { "id": "rename", "symbol": "edit", "title": "Rename", "submenu": true, "bar": true },
                { "id": "icon", "symbol": "image", "title": "Change icon", "submenu": true },
                { "id": "details", "symbol": "info", "title": "Details", "submenu": true, "bar": true },
                { "id": "reveal", "symbol": "folder_open", "title": "Show in folder" },
                { "id": "copy", "symbol": "content_copy", "title": "Copy", "submenu": true, "bar": true },
                { "id": "separator-2", "separator": true },
                { "id": "arrange", "symbol": "align_horizontal_left", "title": "Arrange selection", "submenu": true },
                { "id": "screen", "symbol": "screen_share", "title": "Move to screen", "submenu": true },
                { "id": "separator-3", "separator": true },
                { "id": "remove", "symbol": "delete", "title": "Move to trash", "bar": true }
            ]
        }
    ]

    function definition(menuId: string): var {
        return root.menus.find(m => m.id === menuId) ?? null;
    }

    function isSeparator(id: string): bool {
        return id === "separator" || id.startsWith("separator-");
    }

    function customEntriesFor(menuId: string): var {
        return (root.cfg?.customEntries ?? []).filter(e => e && e.menu === menuId);
    }

    // What the menu looks like with nothing changed: declared order, the
    // declared bar entries, the entries that ship hidden.
    function defaultLayout(menuId: string): var {
        const def = root.definition(menuId);
        const entries = def ? def.entries : [];
        return {
            "menu": menuId,
            "order": entries.map(e => e.id),
            "bar": entries.filter(e => e.bar).map(e => e.id),
            "hidden": entries.filter(e => e.defaultHidden).map(e => e.id)
        };
    }

    function storedLayout(menuId: string): var {
        return (root.cfg?.layouts ?? []).find(l => l && l.menu === menuId) ?? null;
    }

    function isCustomised(menuId: string): bool {
        return root.storedLayout(menuId) !== null;
    }

    // The user's layout with every id the menu can carry placed somewhere:
    // an entry declared after the layout was saved (a newer shell) lands
    // after its declared predecessor, a custom entry missing from the order
    // goes last, and ids that no longer exist are dropped.
    function layoutFor(menuId: string): var {
        const base = root.defaultLayout(menuId);
        const stored = root.storedLayout(menuId);
        const customIds = root.customEntriesFor(menuId).map(e => e.id);
        const known = new Set(base.order.concat(customIds));
        if (!stored) {
            return {
                "menu": menuId,
                "order": base.order.concat(customIds),
                "bar": base.bar,
                "hidden": base.hidden
            };
        }
        const order = (stored.order ?? []).filter(id => known.has(id) || root.isSeparator(id));
        const seen = new Set(order);
        for (let i = 0; i < base.order.length; i++) {
            const id = base.order[i];
            if (seen.has(id))
                continue;
            let at = 0;
            for (let j = i - 1; j >= 0; j--) {
                const k = order.indexOf(base.order[j]);
                if (k >= 0) {
                    at = k + 1;
                    break;
                }
            }
            order.splice(at, 0, id);
            seen.add(id);
        }
        for (const id of customIds) {
            if (!seen.has(id))
                order.push(id);
        }
        return {
            "menu": menuId,
            "order": order,
            "bar": (stored.bar ?? []).filter(id => known.has(id)),
            "hidden": (stored.hidden ?? []).filter(id => known.has(id))
        };
    }

    /**
     * live: [{ id, symbol, title, ... }] - the entries that apply right now.
     * An entry with `items` is a block and expands in place.
     * Returns { bar: [...], rows: [...] }; rows may hold { separator: true },
     * never two in a row, never first or last.
     */
    function arrange(menuId: string, live: var): var {
        const layout = root.layoutFor(menuId);
        const byId = {};
        for (const e of live)
            byId[e.id] = e;
        for (const c of root.customEntriesFor(menuId)) {
            byId[c.id] = {
                "id": c.id,
                "symbol": c.symbol || "terminal",
                "title": c.title || c.command,
                "custom": true,
                "command": c.command
            };
        }
        const hidden = new Set(layout.hidden);
        const inBar = new Set(root.compact ? layout.bar : []);
        const bar = [];
        const rows = [];
        for (const id of layout.order) {
            if (hidden.has(id))
                continue;
            if (root.isSeparator(id)) {
                if (rows.length > 0 && !rows[rows.length - 1].separator)
                    rows.push({ "id": id, "separator": true });
                continue;
            }
            const entry = byId[id];
            if (!entry)
                continue;
            if (entry.items) {
                for (const item of entry.items)
                    rows.push(item);
                continue;
            }
            if (inBar.has(id))
                bar.push(entry);
            else
                rows.push(entry);
        }
        while (rows.length > 0 && rows[rows.length - 1].separator)
            rows.pop();
        return { "bar": bar, "rows": rows };
    }

    // Rows split at the separators, for hosts that draw groups.
    function groupsOf(rows: var): var {
        const groups = [[]];
        for (const r of rows) {
            if (r.separator)
                groups.push([]);
            else
                groups[groups.length - 1].push(r);
        }
        return groups.filter(g => g.length > 0);
    }

    // ── Writing ──────────────────────────────────────────────────────────────
    function setLayout(menuId: string, layout: var): void {
        const next = (root.cfg.layouts ?? []).filter(l => l && l.menu !== menuId);
        next.push({
            "menu": menuId,
            "order": layout.order.slice(),
            "bar": layout.bar.slice(),
            "hidden": layout.hidden.slice()
        });
        root.cfg.layouts = next;
    }

    function resetLayout(menuId: string): void {
        root.cfg.layouts = (root.cfg.layouts ?? []).filter(l => l && l.menu !== menuId);
        root.cfg.customEntries = (root.cfg.customEntries ?? []).filter(e => e && e.menu !== menuId);
    }

    function addCustom(menuId: string, symbol: string, title: string, command: string): string {
        const id = "custom-" + Date.now().toString(36);
        const list = (root.cfg.customEntries ?? []).slice();
        list.push({ "id": id, "menu": menuId, "symbol": symbol, "title": title, "command": command });
        root.cfg.customEntries = list;
        const layout = root.layoutFor(menuId);
        if (layout.order.indexOf(id) < 0)
            layout.order.push(id);
        root.setLayout(menuId, layout);
        return id;
    }

    function updateCustom(id: string, symbol: string, title: string, command: string): void {
        root.cfg.customEntries = (root.cfg.customEntries ?? []).map(e => e && e.id === id
            ? { "id": id, "menu": e.menu, "symbol": symbol, "title": title, "command": command } : e);
    }

    function removeCustom(id: string): void {
        const entry = (root.cfg.customEntries ?? []).find(e => e && e.id === id);
        root.cfg.customEntries = (root.cfg.customEntries ?? []).filter(e => e && e.id !== id);
        if (!entry)
            return;
        const layout = root.layoutFor(entry.menu);
        layout.order = layout.order.filter(x => x !== id);
        layout.bar = layout.bar.filter(x => x !== id);
        layout.hidden = layout.hidden.filter(x => x !== id);
        root.setLayout(entry.menu, layout);
    }

    function runCustom(entry: var, target: string): void {
        if (!entry || !entry.command)
            return;
        Quickshell.execDetached(["env", "II_CONTEXT_TARGET=" + (target ?? ""), "bash", "-c", entry.command]);
    }
}
