#!/usr/bin/env python3
"""Landmarks for the Settings search: the visible words of a page that are not cloneable controls.

SearchRegistry clones ``ContentSection``s and their ``Config*`` controls, which is all a
page used to be made of. The redesigned pages draw their headings on hero cards, panes,
tiles and chips (``ColorsPalettePane``'s "Color scheme"), so a query for any of them
found nothing. A landmark is such a string with the page that shows it; the search
result is a link that opens the page and flashes the text, not a clone.

Each page is crawled from its file and its registered sub-pages through every settings
component they instantiate (ColorsThemesConfig -> ColorsPalettePane -> ...). This runs
out of process: scanning ~270 files in the shell's JS engine held its UI thread for
seconds.

Usage: search_landmarks.py <shell root> '<pages JSON: [{id, component, subPages}]>'
Prints {"landmarks": [{pageId, subPage, key, subPageTitle}]}; keys are untranslated.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

CONFIGS = "modules/settings/configs/"

# Prose rather than names: a word inside one of these is not where a user expects
# the setting to be called that, and they would bury the real hits.
PROSE_PROPS = {
    "tooltip", "description", "summary", "hint", "message", "body", "helperText",
    "supportingText", "placeholder", "placeholderText", "subtitle", "explanation",
    "detail", "details", "caption", "warning", "toolTipText", "infoText",
}
MAX_CHARS = 48
MAX_WORDS = 6
MAX_DEPTH = 6

TR_RE = re.compile(r"""Translation\.tr\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')""")
TYPE_RE = re.compile(r"(^|[^\w.])([A-Z][A-Za-z0-9_]*)\s*\{")
IMPORT_RE = re.compile(r"""^\s*import\s+(?:"([^"]+)"|(qs(?:\.[A-Za-z_]\w*)+))""", re.M)
ROW_RE = re.compile(r"ConfigSubpageRow\s*\{")
STRING_RE = re.compile(r""""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`""")
COMMENT_OR_STRING_RE = re.compile(
    r"""//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`""", re.S)
PROP_RE = re.compile(r"([A-Za-z_]\w*)\s*:\s*[^:]*$")
LINE_PROP_RE = re.compile(r"^\s*([A-Za-z_][\w.]*)\s*:")


def strip_comments(text: str) -> str:
    """Comments carry quotes and braces that are not code ("the user's ...")."""
    return COMMENT_OR_STRING_RE.sub(lambda m: m.group(0) if m.group(0)[0] in "\"'`" else " ", text)


def unquote(literal: str) -> str:
    body = literal[1:-1]
    return re.sub(r"\\([\"'\\])", r"\1", body).replace("\\n", " ")


def is_landmark_text(s: str) -> bool:
    s = s.strip()
    if len(s) < 2 or len(s) > MAX_CHARS:
        return False
    # Templates ("%1 · customized") are filled in at runtime.
    if re.search(r"%\d", s):
        return False
    if not re.search(r"[A-Za-z\u00C0-\u024F]{2}", s):
        return False
    # A sentence is a description, not a name; "Checking…" is a status.
    if s[-1] in ".!?:…":
        return False
    return len(s.split()) <= MAX_WORDS


def property_for(code: str, offset: int) -> str:
    """The property a string is bound to: the nearest `name:` before it on its line."""
    line_start = code.rfind("\n", 0, offset) + 1
    before = code[line_start:offset]
    m = PROP_RE.search(before)
    if m:
        return m.group(1)
    m = LINE_PROP_RE.match(before)
    return m.group(1) if m else ""


def extract_landmarks(text: str) -> list[str]:
    """Short translated strings bound to a property in this file, in source order."""
    code = strip_comments(text)
    found: list[str] = []
    for m in TR_RE.finditer(code):
        s = unquote(m.group(1)).strip()
        if not is_landmark_text(s):
            continue
        # A string a function computes (`return ...`, `parts.push(...)`) is a runtime
        # label chosen among others; only bound ones are fixed names.
        prop = property_for(code, m.start())
        if not prop or prop.split(".")[-1] in PROSE_PROPS:
            continue
        # `.arg(...)` fills the string in at runtime; it never shows as written.
        if re.match(r"\s*\)\s*\.arg\b", code[m.end():m.end() + 12]):
            continue
        if s not in found:
            found.append(s)
    return found


def referenced_types(text: str) -> list[str]:
    code = STRING_RE.sub('""', strip_comments(text))
    types: list[str] = []
    for m in TYPE_RE.finditer(code):
        if m.group(2) not in types:
            types.append(m.group(2))
    return types


def import_dirs(text: str, file_path: str, shell_root: str) -> list[str]:
    """Its own directory and each local import (`qs.modules.settings.configs.colors`, `"colors"`)."""
    own = os.path.dirname(file_path) + "/"
    dirs = [own]
    for m in IMPORT_RE.finditer(strip_comments(text)):
        if m.group(1):
            if m.group(1).endswith(".js"):
                continue
            d = os.path.normpath(own + m.group(1)) + "/"
        else:
            d = shell_root + "/".join(m.group(2).split(".")[1:]) + "/"
        if d not in dirs:
            dirs.append(d)
    return dirs


def child_files(text: str, file_path: str, shell_root: str, file_set: set[str]) -> list[str]:
    """Settings components this file instantiates. Common widgets are not crawled:
    their strings are generic and they belong to every page."""
    dirs = import_dirs(text, file_path, shell_root)
    files: list[str] = []
    for t in referenced_types(text):
        for d in dirs:
            candidate = d + t + ".qml"
            if candidate != file_path and candidate in file_set:
                if candidate not in files:
                    files.append(candidate)
                break
    return files


def block_after(code: str, start: int) -> str:
    depth, j, quote = 1, start, ""
    while j < len(code) and depth > 0:
        ch = code[j]
        if quote:
            if ch == "\\":
                j += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'`":
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        j += 1
    return code[start:j]


def sub_page_titles(text: str, file_path: str) -> dict[str, str]:
    """Titles of the rows that open a sub-page, by the sub-page's absolute path."""
    code = strip_comments(text)
    titles: dict[str, str] = {}
    for m in ROW_RE.finditer(code):
        block = block_after(code, m.end())
        page = re.search(r'configPage\s*:\s*(?:Qt\.resolvedUrl\(\s*)?"([^"]+\.qml)"', block)
        title = re.search(r'title\s*:\s*Translation\.tr\(\s*"((?:\\.|[^"\\])*)"', block)
        if page and title:
            titles[os.path.normpath(os.path.dirname(file_path) + "/" + page.group(1))] = unquote('"' + title.group(1) + '"')
    return titles


def fallback_title(sub_page: str) -> str:
    """"widgets/WallpaperEngineConfig.qml" -> "Wallpaper Engine", for a sub-page no row names."""
    base = re.sub(r"Config$", "", Path(sub_page).stem)
    base = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", base)
    return re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", base)


def crawl(shell_root: str, pages: list[dict]) -> list[dict]:
    shell_root = shell_root.rstrip("/") + "/"
    configs = shell_root + CONFIGS
    file_set = {os.path.join(d, f) for d, _, fs in os.walk(configs) for f in fs if f.endswith(".qml")}
    texts: dict[str, str] = {}
    titles: dict[str, str] = {}
    landmarks: list[dict] = []

    def read(path: str) -> str | None:
        if path not in texts:
            try:
                texts[path] = Path(path).read_text(encoding="utf-8")
            except OSError:
                texts[path] = None
        return texts[path]

    for page in pages:
        seen: set[tuple[str, str]] = set()
        queue = [(shell_root + page["component"], "", 0)]
        queue += [(configs + sub, sub, 0) for sub in page.get("subPages") or []]
        visited: set[tuple[str, str]] = set()
        while queue:
            path, sub_page, depth = queue.pop(0)
            if (path, sub_page) in visited:
                continue
            visited.add((path, sub_page))
            text = read(path)
            if text is None:
                continue
            titles.update(sub_page_titles(text, path))
            for key in extract_landmarks(text):
                if (sub_page, key) in seen:
                    continue
                seen.add((sub_page, key))
                landmarks.append({"pageId": page["id"], "subPage": sub_page, "key": key})
            if depth < MAX_DEPTH:
                queue += [(child, sub_page, depth + 1) for child in child_files(text, path, shell_root, file_set)]

    for lm in landmarks:
        sub = lm["subPage"]
        lm["subPageTitle"] = (titles.get(os.path.normpath(configs + sub)) or fallback_title(sub)) if sub else ""
    return landmarks


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    pages = [p for p in json.loads(argv[2]) if p.get("searchable") is not False]
    json.dump({"landmarks": crawl(argv[1], pages)}, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
