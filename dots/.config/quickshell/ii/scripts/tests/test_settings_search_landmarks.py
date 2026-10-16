#!/usr/bin/env python3
"""Settings search landmarks: headings the redesigned pages draw outside cloneable controls."""

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "settings"))

import search_landmarks as L  # noqa: E402


def registry_pages():
    src = (ROOT / "modules/common/SettingsPageRegistry.qml").read_text(encoding="utf-8")
    literal = src.split("readonly property var pages:", 1)[1].split("\n    ]\n", 1)[0] + "]"
    literal = re.sub(r"^\s*//.*$", "", literal, flags=re.M)
    literal = re.sub(r",(\s*[\]}])", r"\1", literal)
    return json.loads(literal)


class Extraction(unittest.TestCase):
    def test_bound_short_strings_only(self):
        text = (
            'Item { text: Translation.tr("Color scheme") // "x\n'
            ' tooltip: Translation.tr("Nope")\n'
            ' label: c ? Translation.tr("Alpha beta") : Translation.tr("Gamma delta")\n'
            ' x: Translation.tr("%1 items").arg(n)\n'
            ' y: Translation.tr("Dark mode").arg(1)\n'
            ' z: Translation.tr("Checking…")\n'
            ' function f() { return Translation.tr("Computed label") }\n'
            ' w: Translation.tr("A whole sentence describing a thing.") }')
        self.assertEqual(L.extract_landmarks(text), ["Color scheme", "Alpha beta", "Gamma delta"])

    def test_model_literals(self):
        text = 'model: [{ label: Translation.tr("Built-in"), value: 1 }, { description: Translation.tr("Skip me") }]'
        self.assertEqual(L.extract_landmarks(text), ["Built-in"])

    def test_types_ignore_strings_and_comments(self):
        text = 'ColumnLayout { ColorsPalettePane { text: "Fake {" } // Commented {\n Loader { sourceComponent: Foo{} } }'
        self.assertEqual(L.referenced_types(text), ["ColumnLayout", "ColorsPalettePane", "Loader", "Foo"])

    def test_import_dirs(self):
        text = 'import qs.modules.settings.configs.colors\nimport "../widgets"\nimport "x.js" as X'
        self.assertEqual(L.import_dirs(text, "/r/modules/settings/configs/A.qml", "/r/"),
                         ["/r/modules/settings/configs/", "/r/modules/settings/configs/colors/", "/r/modules/settings/widgets/"])

    def test_sub_page_titles(self):
        text = 'ConfigSubpageRow { title: Translation.tr("OpenRGB"); configPage: Qt.resolvedUrl("widgets/OpenRGBConfig.qml") }'
        self.assertEqual(L.sub_page_titles(text, "/r/c/Page.qml"), {"/r/c/widgets/OpenRGBConfig.qml": "OpenRGB"})
        self.assertEqual(L.fallback_title("widgets/WallpaperEngineConfig.qml"), "Wallpaper Engine")


class RealPages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pages = registry_pages()
        cls.landmarks = L.crawl(str(ROOT), [p for p in cls.pages if p.get("searchable") is not False])

    def has(self, page_id, key, sub_page=""):
        return any(l["pageId"] == page_id and l["key"] == key and l["subPage"] == sub_page for l in self.landmarks)

    def test_colors_page_headings(self):
        for key in ("Color scheme", "Wallpaper colors", "Themes", "Custom", "Customize", "Change wallpaper",
                    "Light mode", "Automation & integrations", "App theming", "Wallpaper Engine", "OpenRGB integration"):
            self.assertTrue(self.has("colors", key), key)

    def test_sub_page_landmarks_open_the_sub_page(self):
        self.assertTrue(self.has("colors", "Installed Wallpapers", "widgets/WallpaperEngineConfig.qml"))

    def test_no_prose_or_templates(self):
        for l in self.landmarks:
            self.assertNotRegex(l["key"], r"%\d")
            self.assertLessEqual(len(l["key"]), L.MAX_CHARS)
            self.assertFalse(l["key"].endswith((".", "…")), l["key"])
        self.assertFalse(self.has("colors", "From your wallpaper"))

    def test_every_page_with_its_own_file_has_landmarks(self):
        ids = {l["pageId"] for l in self.landmarks}
        # Network draws only tabs whose sections are indexed through searchSources.
        missing = [p["id"] for p in self.pages if p.get("searchable") is not False and p["id"] not in ids and p["id"] != "network"]
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
