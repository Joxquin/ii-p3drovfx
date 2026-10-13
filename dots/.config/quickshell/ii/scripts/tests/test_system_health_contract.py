#!/usr/bin/env python3
"""Contract tests for System Health.

The helper and the shell meet at scripts/health/PROTOCOL.md; the assistant meets the
shell at the `health` tool domain. These pin the seams that break silently: a message
type the service never reads, a tool without a handler, a tool that could hand a crash
dump to a model, an island activity whose toggle cannot save, and an app folder the
module scanner never registers.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOTS = ROOT.parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


PROTOCOL = read("scripts/health/PROTOCOL.md")
SERVICE = read("services/HealthService.qml")
REGISTRY = read("services/ai/AiToolRegistry.qml")
AI = read("services/Ai.qml")
TOOLS = read("services/ai/AiTools.qml")
INTEGRATION = read("services/ai/integrations/AiHealthIntegration.qml")
ASSISTANT = read("modules/ii/health/components/HealthAssistant.qml")
CONFIG = read("modules/common/Config.qml")
FAMILY = read("panelFamilies/IllogicalImpulseFamily.qml")
ISLAND_REGISTRY = read("modules/ii/dynamicIsland/core/IslandRegistry.qml")
ISLAND_SOURCES = read("modules/ii/dynamicIsland/core/sources/IslandSources.qml")
HELPERS = read("scripts/rust-helpers.sh")

HEALTH_TOOLS = (
    "health_overview", "health_finding", "health_unit_log", "health_crash_trace",
    "health_journal_search", "health_package", "health_propose_fix",
)


class ProtocolTests(unittest.TestCase):
    def test_service_reads_every_stdout_message(self):
        stdout = PROTOCOL.split("## stdin")[0]
        kinds = set(re.findall(r'\{"t":"([a-z]+)"', stdout))
        self.assertTrue({"ready", "finding", "crashes", "reply"} <= kinds, kinds)
        for kind in kinds:
            self.assertIn(f'case "{kind}":', SERVICE, f"HealthService ignores '{kind}'")

    def test_state_dir_is_a_plain_path(self):
        self.assertRegex(SERVICE, r"stateDir: FileUtils\.trimFileProtocol\(")

    def test_no_request_returns_dump_bytes(self):
        self.assertIn("Nothing on stdin can return the bytes of a core dump", PROTOCOL)


class AssistantTests(unittest.TestCase):
    def test_every_tool_is_registered_and_handled(self):
        for tool in HEALTH_TOOLS:
            self.assertRegex(REGISTRY, rf'id: "{tool}",\s*\n\s*version: 1,\s*\n\s*domain: "health"', tool)
            self.assertIn(f'"{tool}": call =>', AI, f"no handler for {tool}")

    def test_tools_read_only_and_never_ask(self):
        for block in re.findall(r'\{\s*id: "health_[a-z_]+".*?needsSearch: false', REGISTRY, re.S):
            self.assertIn('kind: "localRead"', block)
            self.assertIn('network: "never"', block)
            self.assertIn('requiredServices: ["health"]', block)

    def test_health_service_availability_is_declared(self):
        self.assertIn("get health()", TOOLS)

    def test_crash_tool_drops_the_dump_path(self):
        self.assertIn("delete fields.COREDUMP_FILENAME", INTEGRATION)

    def test_proposals_run_only_from_a_click(self):
        # proposeFix only emits; runProposal is the single place that acts.
        propose = INTEGRATION.split("function proposeFix")[1].split("function runProposal")[0]
        for verb in ("HealthService.act(", "HealthService.cleanup(", "runInTerminal("):
            self.assertNotIn(verb, propose)
        self.assertIn("activeKey.length === 0", propose)

    def test_agent_is_lazy_and_scoped(self):
        self.assertRegex(ASSISTANT, r"Loader \{\s*id: taskLoader\s*active: false")
        self.assertIn('toolDomains: ["health"]', ASSISTANT)
        self.assertIn("HealthService.redactText", ASSISTANT)

    def test_assistant_obeys_its_switch_and_the_ai_policy(self):
        self.assertIn("health?.assistant?.enable", ASSISTANT)
        self.assertIn("SearchPanelRegistry.aiPolicyEnabled", ASSISTANT)


class WiringTests(unittest.TestCase):
    def test_app_folder_is_imported_so_the_scanner_registers_it(self):
        self.assertIn("import qs.modules.ii.health\n", FAMILY)
        self.assertIn('"../modules/ii/health/HealthApp.qml"', FAMILY)

    def test_island_activity_can_be_turned_off(self):
        self.assertIn('id: "health",', ISLAND_REGISTRY)
        self.assertIn("readonly property HealthSource health: HealthSource {}", ISLAND_SOURCES)
        self.assertIn("property bool disableHealth: false", CONFIG)
        self.assertRegex(CONFIG, r"property JsonObject health: JsonObject \{\s*property bool enable: true\s*\}")

    def test_helper_is_known_to_the_build_script(self):
        self.assertIn('"health_watch:health"', HELPERS)

    def test_keybind_and_window_rules(self):
        keybinds = (DOTS / "hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
        rules = (DOTS / "hypr/hyprland/rules.lua").read_text(encoding="utf-8")
        self.assertIn('"SUPER + CTRL + H", hl.dsp.global("quickshell:healthToggle")', keybinds)
        self.assertEqual(rules.count('"^(ii System Health)$"'), 2)


if __name__ == "__main__":
    unittest.main()
