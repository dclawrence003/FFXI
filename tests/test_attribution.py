from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class AttributionAudit(unittest.TestCase):
    def assert_contains(self, relative_path, *needles):
        text = (ROOT / relative_path).read_text(encoding="utf-8")
        for needle in needles:
            self.assertIn(needle, text, f"{relative_path} is missing {needle!r}")

    def test_derivative_notices_are_retained(self):
        self.assert_contains(
            "addons/Roller2/Roller2.lua",
            "Copyright (c) 2016, Selindrile",
            "Redistribution and use in source and binary forms",
        )
        self.assert_contains(
            "addons/EventGuard/EventGuard.lua",
            "Copyright © 2019, Akaden of Asura",
            "Neither the name of superwarp",
            "credits Ivaar",
        )

    def test_independent_integrations_name_their_influences(self):
        self.assert_contains(
            "addons/AutoWS2/AutoWS2.lua",
            "github.com/lorand-ffxi/addons/tree/master/AutoWS",
            "No AutoWS source is redistributed",
        )
        self.assert_contains(
            "addons/PartyCombat/PartyCombat.lua",
            "github.com/Selindrile/SendAllTarget",
            "No SendAllTarget source is redistributed",
        )
        self.assert_contains(
            "addons/PartyStart/PartyStart.lua",
            "github.com/Selindrile/GearSwap",
            "Motenten",
        )

    def test_every_published_project_documents_authorship(self):
        readmes = [
            "addons/AutoWS2/README.md",
            "addons/EventGuard/README.md",
            "addons/PartyCombat/README.md",
            "addons/PartyStart/README.md",
            "addons/Roller2/README.md",
            "patches/HealBot/README.md",
            "patches/MultiCtrl/README.md",
            "tools/FFXI-Core-Manager/README.md",
            "tools/InventoryCore/README.md",
            "tools/InventoryCore/windower/LootAdvisor/README.md",
        ]
        for readme in readmes:
            text = (ROOT / readme).read_text(encoding="utf-8").lower()
            self.assertTrue(
                any(word in text for word in ("attribution", "authorship")),
                f"{readme} has no attribution or authorship section",
            )


if __name__ == "__main__":
    unittest.main()
