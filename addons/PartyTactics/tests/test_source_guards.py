from pathlib import Path
import hashlib
import json
import os
import re
import unittest

CHECK_INSTALLED = os.environ.get('FFXI_TEST_INSTALLED') == '1'


ROOT = Path(__file__).resolve().parents[1]
CORE = [ROOT / "PartyTactics.lua", *sorted((ROOT / "lib").glob("*.lua"))]
PROFILE_ROOT = ROOT / "profiles"
PROFILE_REGISTRY = ROOT / "data" / "profile_registry.lua"
IDENTITY_EXTENSIONS = ROOT / "lib" / "identity_extensions.lua"
SUPPLEMENTAL_ALIAS_ROOT = ROOT / "data" / "supplemental_aliases"
PARTYSTART_GS = ROOT.parent / "PartyStart" / "gearswap"
GEARSWAP_HOST = ROOT / "gearswap" / "PartyTactics_Host.lua"
PROFILE_ADAPTER_ROOT = ROOT / "gearswap" / "adapters"
GENMEI_ADAPTER = (
    ROOT / "gearswap" / "adapters"
    / "escha-ruaun-genbu-genmei" / "2.1.0.lua"
)
LEGACY_GEARSWAP = ROOT / "gearswap" / "legacy" / "1.0.0"
PARTYSTART_COMPOSITIONS = ROOT.parent / "PartyStart" / "data" / "compositions.lua"
LIVE_COMMON = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\data\Common"
)
LIVE_PARTYTACTICS = Path(
    r"C:\Program Files (x86)\Windower\addons\PartyTactics"
)
LEGACY_HELPERS = {
    "BRD": (LEGACY_GEARSWAP / "PartyTactics_Legacy_BRD.lua",
            LIVE_COMMON / "PartyStart_BRD.lua"),
    "RDM": (LEGACY_GEARSWAP / "PartyTactics_Legacy_RDM.lua",
            LIVE_COMMON / "PartyStart_RDM.lua"),
    "GEO": (LEGACY_GEARSWAP / "PartyTactics_Legacy_GEO.lua",
            LIVE_COMMON / "PartyStart_GEO.lua"),
    "PLD": (LEGACY_GEARSWAP / "PartyTactics_Legacy_PLD.lua",
            LIVE_COMMON / "PartyStart_PLD.lua"),
    "DNC": (LEGACY_GEARSWAP / "PartyTactics_Legacy_DNC.lua",
            LIVE_COMMON / "PartyStart_DNC.lua"),
}
LIVE_GEARSWAP_HOST = LIVE_COMMON / "PartyTactics" / "PartyTactics_Host.lua"
LIVE_PROFILE_ADAPTER_ROOT = LIVE_COMMON / "PartyTactics" / "adapters"
LIVE_PARTYTACTICS_PROFILE_ADAPTER_ROOT = (
    LIVE_PARTYTACTICS / "gearswap" / "adapters"
)

# Reviewed integration artifacts. Adapters/helpers are append-only: behavior
# changes get a new versioned path. The single stable host may advance only by
# an explicit revision bump plus full cross-profile regression coverage.
# Hashing normalizes line endings so the contract survives Git on Windows.
FROZEN_ARTIFACT_SHA256 = {
    "gearswap/PartyTactics_Host.lua": "02a7213d2baaa804f56c7328601f29feb90d482d2e07940b3c4018b07f40c770",
    "gearswap/legacy/1.0.0/PartyTactics_Legacy_BRD.lua": "7c4989efe7c457c61da0da40eb00b04dabac08f51050c7e5b9f8d7ff8f6f8282",
    "gearswap/legacy/1.0.0/PartyTactics_Legacy_DNC.lua": "442e4fa284a15beb8698459fc21d9dcdd8a6e34d8e60009f6fc22018d9b36610",
    "gearswap/legacy/1.0.0/PartyTactics_Legacy_GEO.lua": "a71d18344b724225ec36087681d96e2da584c8bd8e56e46f8b93f0d56b39dde2",
    "gearswap/legacy/1.0.0/PartyTactics_Legacy_PLD.lua": "2f669c33029cc2ad6f45a0b68b9e3812fb06a235e33c7910dff93e3a6210e557",
    "gearswap/legacy/1.0.0/PartyTactics_Legacy_RDM.lua": "3fd77d19fa45564798a12b76007631f62c978796ec051542825cdb9767385378",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.1.0.lua": "f93d3ebfcbd2f155c12ad97b46e6e3ebea60b975a4aebc9854d67e8b088094b1",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.2.0.lua": "adcdd21799b85ca55678172a2e891dc617ad1fb8f4f74ce5da6c68adb0286149",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.3.0.lua": "720a0b1e995ccaaae05b8d9829f1a6ae96dff24d0d721f3227bc4ca57404b974",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.4.0.lua": "269a90225d6d3babd225f704b9282b87cba4b595d882aaf0295e984b4039a1a4",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.5.0.lua": "94362e22d55900abef90d19027953f7ed49411aedb1764ac3b4f8c37095925c9",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.6.0.lua": "b661b5d91212ae8e60fcb3365cdafaa1830205a57e2cdd83e3df9f125fb181d7",
    "gearswap/adapters/escha-ruaun-genbu-genmei/2.7.0.lua": "985d6c8cc547417b04b852fa8b7608ae138a3cc12257ed6dd1c35b70679335ba",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.0.0.lua": "cf65d018022257a7afc6f51dac138dbe7a9ffcb8dd452329099376751b8f7ba4",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.1.0.lua": "8d19c93fd9b9fb4bbc91917792bc48ccb810bdb166baf4af1a3be15465a2d50f",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.2.0.lua": "7faa1414542868b06be816b14cd8f5f19bbbbabbff2de7523335772ee9a9dc1b",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.3.0.lua": "0b5d2f9b7ec2c25493d6efeb44e88494b5d3e73ee4b5c41e724d73c9acbd8380",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.4.0.lua": "5c92cdd409cc4a7ac7ed0283f7363d07137816a0194173d95d0201bfe206e7c6",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.5.0.lua": "b7c14b265c4948482a3e2e2c53a5669bd2bbf5c362fcf7280304826b305dc500",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.6.0.lua": "5cae257311ac6dc27db3bcbab6e4d65c093a5b0652414f0cc17600232e16d612",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.7.0.lua": "542c8771487e39a73643a82457c5f49000497c7108fdbb7074f0b9d0bd42a487",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.8.0.lua": "88bbddfde45a22e079e6b5618ba2731c28e44dbdec2ada1890341634db58c1f0",
    "gearswap/adapters/locus-dire-bats-tomb-signet/1.8.1.lua": "6d682144d6e8d423a63ee261facd0b9e765da734ca8a67fefad6d3a0d12bf80a",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig/1.0.0.lua": "6a7766c35128e2b471f43457f12b190ab64111e59f2d7ba68e80641602f0a3aa",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig/1.1.0.lua": "5e1c9ecc45b1d8dd4a0b8089566e544678bdcb6d9b3c945c97d30a9b58c1d939",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.0.0.lua": "354e8d242426f15569084c6473d4746bb843323e732ff2ce3631201397baf9f2",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.1.0.lua": "4fcda9869763f6f034c78c92afaae5e2d330d7b53a832625f88f8da2bf0acdf6",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.2.0.lua": "271e3c7d98e984f37d4f1f7ccd7ed8b409f6bead9b4ae823d6d7e35fd6b55b20",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.3.0.lua": "1dbdee4b2c0a3e967ae863951ee96fb54ba61adb9c926827d21193dcacb0de3c",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.4.0.lua": "a0b1f1825110247ff479ab11b1887531975b79ab39e24e82290f4220d100105e",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.5.0.lua": "34c1a720feea8b3f0de7bd6b85e5705d44c267f4e69ce6a421896a1ca5e02a2d",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.6.0.lua": "fd047d957b29070db6f04115bc6a18b14961c4e7a050158ffc2d54df1a515c40",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.7.0.lua": "1aedee1beb5ad7e43e9ebb4728edfc74ede5fc112f60571243bfe26ea49f2cbf",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.8.0.lua": "a109985f5e20efd87d984a8628353e8ed847db72021947da009e728b7a3000de",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.9.0.lua": "079091a94238aa1f9e635cc2d32c1918bbf8f72af269dc13fccaaf3f85dbbcba",
    "gearswap/adapters/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.10.0.lua": "293aaea45ed05484e3fc19b05b1c208622d27ca3f9b11b51108847a1b2f6c1b4",
    "gearswap/adapters/ambuscade-2026-09-v2-hydra-alluttu/1.0.0.lua": "e8ad6eb4f3e767db79ca7e3c0408352e2814606d9ef3ed2b68500f16ba10117c",
    "gearswap/adapters/vagary-direct-rancibus/1.0.0.lua": "e3da0e724d00c956b3e4feaad8a987c6d0bf913b3ed6942b29f7e18b2d1a895b",
    "gearswap/adapters/vagary-direct-rancibus/1.0.1.lua": "810c0029b4b613e5a7818a42d50961027324cd33229626d57ac7dfff4c2c276e",
    "gearswap/adapters/vagary-direct-rancibus/1.0.2.lua": "8624fe9e7ae35d58dcbc585e3aea72b46e1054597514934d5fbfc407ca4eba12",
    "gearswap/adapters/vagary-direct-rancibus/1.1.0.lua": "a6382dbbd6d60c64c60ec3d25283d17267e8c38f514f89a0cf333cfaf9501e0d",
    "gearswap/adapters/sortie-objective-c-magic-burst-v1/1.0.0.lua": "fec370186e5099337d36b369550f7cb00fe15e0387ab39ff7caddfff11ed10c9",
    "gearswap/adapters/sortie-objective-a-magic-kill-v1/1.0.0.lua": "0087ac0e32fcf2ba80eab0e7bc286351eeab6a276859125dec21d7ffba3f1bbc",
    "gearswap/adapters/sortie-objective-a-magic-kill-v1/1.1.0.lua": "91dc20fcd1549c7733248045695348d447cf5b20deb686330d36cfbdec250592",
    "gearswap/adapters/sortie-objective-b-weapon-skill-v1/1.0.0.lua": "d8e330e77947da08372adbcc033c1c0b642c7d41ff9890e03e907da67fbe0b84",
    "gearswap/adapters/sortie-main-v1/1.1.0.lua": "eb096e6522255dc6ddf8de5811965b27e27d40f6aa1fd9903a9174f32d611543",
    "gearswap/adapters/sortie-main-v1/1.2.0.lua": "0de6721a1fcacac426c11a5e0632222145c119982e8a572df3d2997f300f48c5",
    "adapters/manual/brd-pack-sleep.lua": "e3863b48e2a54e8b59817b0e92aa48425aabdc5e9a8528e3c707c22761e5bb27",
    "adapters/manual/clarion-extra-song.lua": "cfac3cadd507c85ab2e0b96dbe6a28a5604cbe5f02c9e8df9b55fdf29cf8e30c",
    "adapters/manual/exact-enemy-action.lua": "c5ec86e7ce6bee3cff3a69b421e67e134ec79adfa12c421ac4a06867040cfbbf",
    "adapters/manual/rdm-exact-silence.lua": "16ea4bc3d447746aed1ca0cd9929c4c73a328f56ed1411cf48f94dd9297f5bac",
    "adapters/manual/typed-action.lua": "101dd55fcee37151df959dd83a3717dccd6fe525cfbc7482cbc51da35fb1c1d6",
}
LIVE_GENMEI_ADAPTER = (
    LIVE_COMMON / "PartyTactics" / "adapters"
    / "escha-ruaun-genbu-genmei" / "2.1.0.lua"
)
LIVE_BARNEY = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\data"
    r"\Barneystinson\Barneystinson_BRD_Gear.lua"
)
LIVE_DOLO_COR = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\data"
    r"\Dolomedes\Dolomedes_COR_Gear.lua"
)
LIVE_HOST_JOB_FILES = {
    "Dolomedes": LIVE_DOLO_COR,
    "Tackleberry": Path(
        r"C:\Program Files (x86)\Windower\addons\GearSwap\data"
        r"\Tackleberry\Tackleberry_PLD_Gear.lua"
    ),
    "Kickpuncher": Path(
        r"C:\Program Files (x86)\Windower\addons\GearSwap\data"
        r"\Kickpuncher\Kickpuncher_DNC_Gear.lua"
    ),
    "Barneystinson": LIVE_BARNEY,
    "Smalls": Path(
        r"C:\Program Files (x86)\Windower\addons\GearSwap\data"
        r"\Smalls\Smalls_RDM_Gear.lua"
    ),
    "Achoo": Path(
        r"C:\Program Files (x86)\Windower\addons\GearSwap\data"
        r"\Achoo\Achoo_GEO_Gear.lua"
    ),
}
LIVE_JOB_HELPERS = {
    "Dolomedes": None,
    "Tackleberry": "PartyStart_PLD.lua",
    "Kickpuncher": "PartyStart_DNC.lua",
    "Barneystinson": "PartyStart_BRD.lua",
    "Smalls": "PartyStart_RDM.lua",
    "Achoo": "PartyStart_GEO.lua",
}
LIVE_SEL_INCLUDE = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\libs\Sel-Include.lua"
)
LIVE_SEL_UTILITY = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\libs\Sel-Utility.lua"
)
DYNA_RELOAD = (ROOT / "scripts" / "reload_dynamis_w1_safe.txt").read_text(
    encoding="utf-8"
)
ENGINE_RELOAD = (ROOT / "scripts" / "reload_partytactics_safe.txt").read_text(
    encoding="utf-8"
)
LOCUS_SUPPORT_RELOAD = (
    ROOT / "scripts" / "reload_locus_support_safe.txt"
).read_text(encoding="utf-8")
LOCUS_SIGNET_RELOAD = (
    ROOT / "scripts" / "reload_locus_signet_safe.txt"
).read_text(encoding="utf-8")
GENMEI_PREFLIGHT_RELOAD = (
    ROOT / "scripts" / "reload_genmei_preflight_safe.txt"
).read_text(encoding="utf-8")
KAMMAVACA_RELOAD = (
    ROOT / "scripts" / "reload_kammavaca_safe.txt"
).read_text(encoding="utf-8")
SEPTEMBER_AMBU_RELOAD = (
    ROOT / "scripts" / "reload_september_ambu_safe.txt"
).read_text(encoding="utf-8")
QUTRUB_NO_CAIT_ACTIVATE = (
    ROOT / "scripts" / "activate_qutrub_nocait_cooperative.txt"
).read_text(encoding="utf-8")


class PartyTacticsSourceGuards(unittest.TestCase):
    def test_locus_signet_derivative_preserves_ordinary_locus_contract(self):
        ordinary = PROFILE_ROOT / "locus-dire-bats-tomb" / "profile.lua"
        digest = hashlib.sha256(
            ordinary.read_bytes().replace(b"\r\n", b"\n")
        ).hexdigest().upper()
        self.assertEqual(
            digest,
            "011461EB3DB097B76B172D45FEC59D9A52F3B3D11C475191CD0C6CF14C287186",
        )
        derivative = (
            PROFILE_ROOT / "locus-dire-bats-tomb-signet" / "profile.lua"
        ).read_text(encoding="utf-8").lower()
        self.assertNotRegex(derivative, r"\beasyfarm\s*=")
        current_adapter = (
            PROFILE_ADAPTER_ROOT / "locus-dire-bats-tomb-signet" / "1.8.1.lua"
        ).read_text(encoding="utf-8").lower()
        self.assertNotIn("issue('pc on')", current_adapter)
        self.assertNotIn("issue('pc off')", current_adapter)
        self.assertNotIn("local command = 'pc on;", current_adapter)
        self.assertNotIn("local command = 'pc off;", current_adapter)
        self.assertIn("pc reconcile on", current_adapter)
        self.assertIn("pc reconcile off", current_adapter)
        self.assertIn("local engine_version = '0.13.3'", current_adapter)
        self.assertIn("local opener_ttl = 30", current_adapter)
        self.assertIn("local companion_load_retry_interval = 6", current_adapter)
        self.assertIn("(state.companion_load_attempts.sk or 0) < 2", current_adapter)
        self.assertIn("semantic == 'companion-ready'", current_adapter)
        self.assertIn("helper == 'sk' and #arguments == 11", current_adapter)
        self.assertIn("helper ~= 'sk' and #arguments == 10", current_adapter)
        self.assertIn("semantic == 'keeper-instance'", current_adapter)
        self.assertIn("sk gsreload %s %d", current_adapter)
        self.assertNotIn("issue(('pt __recover_controller", current_adapter)
        self.assertIn("arguments[7] ~= engine_version", current_adapter)
        self.assertIn("sk __ackpt %s %d", current_adapter)
        self.assertIn("lp __ackpt %s %d", current_adapter)
        self.assertIn("jk __ackpt %s %d", current_adapter)
        self.assertNotIn("local function exact_bat", current_adapter)
        self.assertIn("target eligibility and distance belong to locuspuller",
                      current_adapter)

    def test_reviewed_integration_artifacts_are_append_only(self):
        actual_paths = {"gearswap/PartyTactics_Host.lua"}
        actual_paths.update(
            path.relative_to(ROOT).as_posix()
            for path in LEGACY_GEARSWAP.glob("*.lua")
        )
        actual_paths.update(
            path.relative_to(ROOT).as_posix()
            for path in PROFILE_ADAPTER_ROOT.glob("*/*.lua")
        )
        actual_paths.update(
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / "adapters" / "manual").glob("*.lua")
        )
        self.assertEqual(actual_paths, set(FROZEN_ARTIFACT_SHA256))
        for relative, expected in FROZEN_ARTIFACT_SHA256.items():
            payload = (ROOT / relative).read_bytes().replace(b"\r\n", b"\n")
            self.assertEqual(
                hashlib.sha256(payload).hexdigest(),
                expected,
                f"reviewed artifact changed unexpectedly: {relative}; add a "
                "new adapter/helper version, or explicitly bump and regress "
                "the stable host revision",
            )

    def test_new_profiles_use_only_reviewed_queue_safe_manual_adapters(self):
        # These two profiles predate the operator-action queue contract.
        # Preserve them until each mechanic gets an exact, job-specific queue;
        # do not let their immediate typed actions become the template for a
        # new fight.
        legacy_direct_profiles = {
            "dynamis-divergence-wave1-route-corsair",
            "dynamis-divergence-wave1-boss-magic",
        }
        queue_safe_adapters = {
            "brd-pack-sleep",
            "rdm-exact-silence",
        }
        for path in PROFILE_ROOT.glob("*/profile.lua"):
            if path.parent.name in legacy_direct_profiles:
                continue
            text = path.read_text(encoding="utf-8")
            adapters = set(re.findall(r"adapter\s*=\s*'([^']+)'", text))
            self.assertLessEqual(
                adapters,
                queue_safe_adapters,
                f"{path.parent.name} introduced a non-queued operator action",
            )

    def test_core_has_no_fight_id_branches(self):
        text = "\n".join(path.read_text(encoding="utf-8") for path in CORE)
        for fight_id in (
            "locus-dire-bats-tomb",
            "limbus-119-stationary",
            "ambuscade-2026-08-v1-breadwinner",
            "ambuscade-2026-09-v1-qutrub-bigwig",
            "ambuscade-2026-09-v1-qutrub-bigwig-no-cait",
            "ambuscade-2026-09-v2-hydra-alluttu",
            "dynamis-divergence-wave1-route-corsair",
            "dynamis-divergence-wave1-boss-magic",
            "escha-ruaun-genbu-genmei",
            "escha-ruaun-kammavaca",
            "vagary-direct-rancibus",
            "sortie-objective-c-device-kill-v1",
            "sortie-objective-d-demisang-clear-v1",
        ):
            self.assertNotIn(fight_id, text)

    def test_public_profile_identities_are_append_only_and_collision_safe(self):
        registry = PROFILE_REGISTRY.read_text(encoding="utf-8")
        extensions = IDENTITY_EXTENSIONS.read_text(encoding="utf-8")
        loader = (ROOT / "lib" / "profile_loader.lua").read_text(
            encoding="utf-8"
        )
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        self.assertIn(
            "local base_identity_registry = load_module('data/profile_registry.lua')",
            core,
        )
        self.assertIn(
            "local identity_registry, identity_extension_errors = "
            "identity_extensions.extend(",
            core,
        )
        self.assertIn("util, base_identity_registry,", core)
        self.assertIn("data/profile_identities/", core)
        self.assertIn("sandboxed_loadfile)", core)
        self.assertIn("for _, message in ipairs(identity_extension_errors)", core)
        self.assertIn("profile_loader.discover(", core)
        self.assertIn("identity_registry)", core)

        # The seven established identities remain in one frozen bootstrap;
        # every later identity is a separately sandboxed sidecar. A syntax or
        # validation error in a new sidecar is accumulated as a catalog issue
        # instead of making the bootstrap chunk unloadable.
        self.assertIn("Frozen bootstrap ownership registry", registry)
        self.assertIn("local function valid_identity", extensions)
        self.assertIn("identity.id ~= filename", extensions)
        self.assertIn("local loader, load_error = load_file(path)", extensions)
        self.assertIn("local ok, identity = pcall(loader)", extensions)
        self.assertIn("invalid isolated profile identity", extensions)
        self.assertIn("local next_ordinal = #result.identities + 1", extensions)
        self.assertIn("identity.ordinal ~= next_ordinal", extensions)
        self.assertIn("result.identities[#result.identities + 1] = identity", extensions)
        self.assertIn("local function prepare_registry", loader)
        self.assertIn("identity.ordinal == index", loader)
        self.assertIn("reuses established command", loader)
        self.assertIn("missing immutable profile identity", loader)
        for ordinal, profile_id in enumerate((
            "locus-dire-bats-tomb",
            "limbus-119-stationary",
            "ambuscade-2026-08-v1-breadwinner",
            "dynamis-divergence-wave1-route-corsair",
            "dynamis-divergence-wave1-boss-magic",
            "escha-ruaun-kammavaca",
            "escha-ruaun-genbu-genmei",
        ), start=1):
            self.assertIn(f"ordinal={ordinal}", registry)
            self.assertIn(f"id='{profile_id}'", registry)

    def test_supplemental_aliases_are_isolated_and_fail_closed(self):
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        loader = (ROOT / "lib" / "supplemental_aliases.lua").read_text(
            encoding="utf-8"
        )
        expected = {
            "ambuscade-2026-08-v1-breadwinner.lua": "v1-breadwinner",
            "ambuscade-2026-09-v1-qutrub-bigwig.lua": "v1-qutrub",
            "ambuscade-2026-09-v1-qutrub-bigwig-no-cait.lua":
                "v1-qutrub-nocait",
            "ambuscade-2026-09-v2-hydra-alluttu.lua": "v2-hydra",
        }
        self.assertEqual(
            {path.name for path in SUPPLEMENTAL_ALIAS_ROOT.glob("*.lua")},
            set(expected),
        )
        for filename, alias in expected.items():
            text = (SUPPLEMENTAL_ALIAS_ROOT / filename).read_text(
                encoding="utf-8"
            )
            self.assertIn(f"target='{filename[:-4]}'", text)
            self.assertIn(f"aliases={{'{alias}'}}", text)

        self.assertIn(
            "load_module('lib/supplemental_aliases.lua')", core
        )
        self.assertIn("supplemental_aliases.discover(", core)
        self.assertIn("data/supplemental_aliases/", core)
        self.assertIn("supplemental_aliases.apply(", core)
        self.assertLess(
            core.index("profiles[id], plans[id] = nil, nil"),
            core.index("aliases, supplemental_apply_errors ="),
        )
        self.assertIn("loaded_profiles[id].manual_actions", core)
        self.assertIn("identity_registry,\n    loaded_manual_actions", core)
        self.assertIn("'supplemental alias '..message", core)
        self.assertIn("catalog issue(s) were quarantined", core)

        engine_sources = core.split("local engine_sources = {", 1)[1].split(
            "\n}", 1
        )[0]
        self.assertIn("lib/supplemental_aliases.lua", engine_sources)
        self.assertNotIn("data/supplemental_aliases", engine_sources)
        self.assertNotIn("supplemental_sources", core)

        self.assertIn("local directory_ok, directory = pcall(get_dir, root)", loader)
        self.assertIn("local exists_ok, exists = pcall(file_exists, path)", loader)
        self.assertIn("local load_ok, loader, load_error = pcall(load_file, path)", loader)
        self.assertIn("local ok, sidecars, errors = pcall(discover, ...)", loader)
        self.assertIn("local ok, result, errors = pcall(apply, util", loader)
        self.assertIn("sidecar.target ~= id", loader)
        self.assertIn("namespace[alias]", loader)
        self.assertIn("(manual_actions or {})[alias]", loader)
        self.assertIn("not canonical_ids[target]", loader)
        self.assertIn("not profiles[target]", loader)

    def test_every_gearswap_profile_adapter_is_unique_pinned_and_inert(self):
        pins = {}
        adapter_owners = {}
        adapter_block = re.compile(
            r"(?ms)^\s{4}gearswap_adapter\s*=\s*\{(.*?)^\s{4}\},"
        )
        field = lambda name, body: re.search(
            rf"\b{name}\s*=\s*'([^']+)'", body
        )

        for profile_path in sorted(PROFILE_ROOT.glob("*/profile.lua")):
            profile_text = profile_path.read_text(encoding="utf-8")
            blocks = adapter_block.findall(profile_text)
            self.assertLessEqual(
                len(blocks), 1,
                f"{profile_path.parent.name} declares multiple GearSwap adapters",
            )
            if not blocks:
                continue
            body = blocks[0]
            parsed = {name: field(name, body) for name in (
                "id", "version", "controller",
            )}
            for name, match in parsed.items():
                self.assertIsNotNone(
                    match, f"{profile_path.parent.name} adapter lacks {name}",
                )
            adapter_id = parsed["id"].group(1)
            version = parsed["version"].group(1)
            controller = parsed["controller"].group(1)
            protocol = re.search(r"\bprotocol\s*=\s*(\d+)", body)
            self.assertIsNotNone(protocol)
            expected_protocol = (
                "2" if adapter_id == "locus-dire-bats-tomb-signet" else "1"
            )
            self.assertEqual(protocol.group(1), expected_protocol)
            self.assertRegex(adapter_id, r"^[a-z0-9][a-z0-9-]*$")
            self.assertRegex(controller, r"^[a-z0-9][a-z0-9-]*$")
            self.assertRegex(version, r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
            self.assertEqual(
                adapter_id, profile_path.parent.name,
                "a fight adapter must be owned by the profile with the same id",
            )
            self.assertNotIn(
                adapter_id, adapter_owners,
                f"multiple profiles claim adapter family {adapter_id}",
            )
            adapter_owners[adapter_id] = {
                "owner": profile_path.parent.name,
                "controller": controller,
                "version": version,
                "protocol": expected_protocol,
            }

            key = (adapter_id, version)
            self.assertNotIn(
                key, pins,
                f"{adapter_id}@{version} is shared with {pins.get(key)}",
            )
            pins[key] = profile_path.parent.name
            expected = PROFILE_ADAPTER_ROOT / adapter_id / f"{version}.lua"
            self.assertTrue(
                expected.is_file(),
                f"{profile_path.parent.name} pins missing adapter {expected}",
            )

            # A profile adapter is routed on every client, not merely the job
            # that happens to act first. These declarations are typed routing
            # metadata; their later capability probes are diagnostic and may
            # never become permission to load or fight.
            controller_proofs = re.findall(
                r"controller\s*=\s*\{\s*name\s*=\s*'([^']+)'\s*,\s*"
                r"protocol\s*=\s*(\d+)\s*\}",
                profile_text,
            )
            self.assertEqual(len(controller_proofs), 6)
            self.assertTrue(all(
                name == controller and routed_protocol == expected_protocol
                for name, routed_protocol in controller_proofs
            ))

        source_adapters = set(PROFILE_ADAPTER_ROOT.glob("*/*.lua"))
        pinned_adapters = {
            PROFILE_ADAPTER_ROOT / adapter_id / f"{version}.lua"
            for adapter_id, version in pins
        }
        self.assertLessEqual(
            pinned_adapters, source_adapters,
            "every current profile pin must resolve to a source adapter",
        )
        frozen_profile_adapters = {
            ROOT / relative
            for relative in FROZEN_ARTIFACT_SHA256
            if relative.startswith("gearswap/adapters/")
        }
        self.assertEqual(
            source_adapters, frozen_profile_adapters,
            "current and historical adapter versions must all be hash frozen",
        )
        for historical in source_adapters - pinned_adapters:
            adapter_id, version = historical.parent.name, historical.stem
            self.assertIn(
                adapter_id, adapter_owners,
                f"historical adapter family has no owning profile: {historical}",
            )
            current = adapter_owners[adapter_id]["version"]
            self.assertLess(
                tuple(map(int, version.split("."))),
                tuple(map(int, current.split("."))),
                f"unreferenced adapter is not older than current pin: {historical}",
            )
        self.assertGreater(len(source_adapters), 0)

        required_methods = {"activate", "deactivate", "handle_action", "status"}
        allowed_methods = required_methods | {
            "pre_tick", "user_job_tick", "user_job_self_command",
            "filter_pretarget", "filter_precast", "job_aftercast", "file_unload",
            "action_event", "prerender", "zone_change", "logout",
            "unload", "status_change",
        }
        global_callbacks = (
            "pre_tick", "user_job_tick", "user_filter_pretarget",
            "user_filter_precast", "job_aftercast", "user_job_self_command",
            "file_unload",
        )
        for path in sorted(source_adapters):
            text = path.read_text(encoding="utf-8")
            lower = text.lower()
            adapter_id, version = path.parent.name, path.stem
            self.assertIn(adapter_id, adapter_owners)
            owner = adapter_owners[adapter_id]["owner"]
            profile_text = (
                PROFILE_ROOT / owner / "profile.lua"
            ).read_text(encoding="utf-8")
            block = adapter_block.search(profile_text).group(1)
            controller = adapter_owners[adapter_id]["controller"]
            expected_protocol = (
                "2" if adapter_id == "locus-dire-bats-tomb-signet"
                and version in {
                    "1.1.0", "1.2.0", "1.3.0", "1.4.0", "1.5.0", "1.6.0",
                    "1.7.0", "1.8.0", "1.8.1"
                }
                else "1"
            )

            self.assertRegex(text, rf"\bid\s*=\s*'{re.escape(adapter_id)}'")
            self.assertRegex(text, rf"\bversion\s*=\s*'{re.escape(version)}'")
            self.assertRegex(text, rf"\bcontroller\s*=\s*'{re.escape(controller)}'")
            self.assertRegex(
                text, rf"\bprotocol\s*=\s*{expected_protocol}\b"
            )
            exported = set(re.findall(r"(?m)^function\s+M\.([a-z_]+)\s*\(", text))
            self.assertGreaterEqual(exported, required_methods)
            self.assertLessEqual(exported, allowed_methods)

            # Only the stable host may own global GearSwap callbacks or raw
            # Windower event registrations. Fight adapters return methods for
            # the host to invoke, and may not load more code or touch gear.
            self.assertNotRegex(
                text,
                r"(?m)^\s*function\s+(?!M\.)[A-Za-z_][A-Za-z0-9_.:]*\s*\(",
            )
            for callback in global_callbacks:
                self.assertNotRegex(
                    text,
                    rf"(?m)^\s*{callback}\s*=",
                )
            self.assertNotRegex(
                text, r"windower\.(?:raw_)?register_event\s*\(",
            )
            self.assertNotRegex(
                text, r"\b(?:include|require|loadfile|dofile|loadstring)\s*\(",
            )
            self.assertNotRegex(text, r"\bio(?:\.|:)" )
            self.assertNotRegex(
                lower,
                r"\b(?:equip|forceequip|disable|enable|lockstyle|"
                r"packets\.inject)\s*\(",
            )
            for raw_equipment_surface in (
                "/equip", "gs c disable", "gs c enable", "input //equip",
            ):
                self.assertNotIn(raw_equipment_surface, lower)

    def test_profiles_cannot_embed_raw_commands(self):
        for path in PROFILE_ROOT.glob("*/profile.lua"):
            text = path.read_text(encoding="utf-8").lower()
            self.assertNotRegex(text, r"\b(commands|setup|teardown)\s*=")
            self.assertNotIn("equip ", text)
            self.assertNotIn("gs c disable", text)
            self.assertNotIn("gs c enable", text)

    def test_every_manual_adapter_stays_inside_the_typed_action_surface(self):
        manual_root = ROOT / "adapters" / "manual"
        paths = sorted(manual_root.glob("*.lua"))
        self.assertEqual(
            {path.stem for path in paths},
            {
                "brd-pack-sleep", "clarion-extra-song",
                "exact-enemy-action", "rdm-exact-silence", "typed-action",
            },
        )
        for path in paths:
            text = path.read_text(encoding="utf-8")
            lower = text.lower()
            self.assertRegex(text, rf"\bid\s*=\s*'{re.escape(path.stem)}'")
            self.assertIn("execute", text)
            self.assertNotRegex(
                text,
                r"\b(?:windower|send_command|include|require|loadfile|dofile|"
                r"loadstring|io)\b",
            )
            self.assertNotRegex(
                text,
                r"ctx\.(?:command|issue|equip|disable|enable)\b",
            )
            self.assertNotRegex(
                lower,
                r"\b(?:equip|forceequip|disable|enable|lockstyle|"
                r"packets\.inject)\s*\(",
            )

    def test_runtime_has_no_raw_command_or_equipment_api(self):
        for path in PROFILE_ROOT.glob("*/runtime.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotRegex(text, r"ctx\.(command|issue|equip|disable|enable)\b")
            self.assertNotRegex(text, r"\b(windower|send_command|require|loadfile|dofile|io)\b")
            self.assertNotRegex(text.lower(), r"\b(range|ammo|main|sub)\s*=")

    def test_qutrub_runtime_factories_do_not_nest_callbacks(self):
        # Lua 5.1 makes locals used by nested callbacks upvalues of their
        # enclosing factory.  Combining every callback below M.create pushed
        # these large, profile-local state machines over Lua's 60-upvalue
        # function limit even though each callback was independently valid.
        profile_ids = (
            "ambuscade-2026-09-v1-qutrub-bigwig",
            "ambuscade-2026-09-v1-qutrub-bigwig-no-cait",
        )
        for profile_id in profile_ids:
            path = PROFILE_ROOT / profile_id / "runtime.lua"
            text = path.read_text(encoding="utf-8")
            factory = text.split("function M.create()", 1)[1]
            self.assertNotRegex(
                factory,
                r"function\s+self:",
                f"{profile_id} nested a callback inside M.create",
            )

    def test_qutrub_runtimes_compile_with_lua51_when_available(self):
        try:
            from lupa.lua51 import LuaRuntime
        except (ImportError, ModuleNotFoundError):
            self.skipTest("optional lupa Lua 5.1 runtime is unavailable")

        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_lua = lua.eval(
            "function(source, name) "
            "local chunk, err = loadstring(source, name); "
            "return chunk ~= nil, err end"
        )
        profile_ids = (
            "ambuscade-2026-09-v1-qutrub-bigwig",
            "ambuscade-2026-09-v1-qutrub-bigwig-no-cait",
        )
        for profile_id in profile_ids:
            path = PROFILE_ROOT / profile_id / "runtime.lua"
            ok, error = compile_lua(
                path.read_text(encoding="utf-8"),
                "@" + path.as_posix(),
            )
            self.assertTrue(ok, error)

    def test_action_api_has_no_equipment_surface(self):
        text = (ROOT / "lib" / "action_api.lua").read_text(encoding="utf-8")
        public_functions = set(re.findall(r"function api\.([a-z_]+)", text))
        self.assertEqual(
            public_functions,
            {
                "cast", "ability", "weaponskill", "item", "controller",
                "profile_adapter", "profile_adapter_probe",
                "combat_force", "combat_force_members", "combat_stop_members",
                "combat_observe",
                "combat_stop",
            },
        )
        client_functions = set(
            re.findall(r"function client\.([a-z_]+)", text)
        )
        self.assertEqual(client_functions, {"auto_target", "engage_once"})
        self.assertIn("numeric_id >= 1", text)
        self.assertIn("numeric_id <= 4294967295", text)
        self.assertIn("issue('pc forceid '..encoded)", text)
        self.assertIn("issue(('pc forceidto %s %s'):format(", text)
        self.assertIn("issue('pc stopto '..recipients)", text)
        self.assertIn("issue('pc observeid '..encoded)", text)
        self.assertIn("issue('pc engageonceid '..encoded)", text)
        self.assertIn("invalid one-shot engage target id", text)
        self.assertIn("issue('input /autotarget '..(enabled and 'on' or 'off'))", text)
        self.assertIn("actions={silence='uint32'}", text)
        self.assertIn("invalid controller target id", text)
        self.assertIn(
            "local command = ('gs c ptgs action %s %s %s %s %.0f')",
            text,
        )
        self.assertIn("command = command..' '..tostring(request_token)", text)
        self.assertIn("issue(command)", text)
        self.assertIn("issue(('gs c ptgs action %s probe %s %.0f %.0f')", text)
        self.assertIn("current profile adapter authority is unavailable", text)

    def test_core_integrates_partycombat_without_permission_gates(self):
        text = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        self.assertIn("_addon.version = '0.13.3'", text)
        self.assertNotRegex(text.lower(), r"lua\s+(?:load|unload|r)\s+partystart")
        self.assertNotIn("../PartyStart/gearswap/", text)
        self.assertIn("local LEGACY_GEARSWAP_VERSION = '1.0.0'", text)
        self.assertIn("source ~= live", text)
        self.assertIn("local gearswap_host_ready =", text)
        self.assertIn("local catalog_warnings = {}", text)
        self.assertNotIn("not legacy_gearswap_ready or not gearswap_host_ready", text)
        self.assertGreaterEqual(text.count("gearswap_host_source_digest"), 4)
        self.assertGreaterEqual(text.count("gearswap_host_live_digest"), 4)
        self.assertNotIn("issue('lua load PartyCombat')", text)
        self.assertIn(
            "context.actions, context.client = action_api.create(issue, function()", text
        )
        self.assertIn("return active and active.nonce", text)
        self.assertIn("context.current_target = function()", text)
        self.assertIn("windower.ffxi.get_mob_by_target('t')", text)
        self.assertIn("context.operator_armed = function()", text)
        self.assertIn("local operator_source_sequence = 0", text)
        self.assertIn("process_operator_request = function", text)
        self.assertIn("process_operator_state = function", text)
        self.assertIn("carry_operator_snapshot(record, revision + 1", text)
        self.assertIn("local CONTROLLER_PROBE_RETRY_INTERVAL = 2", text)
        self.assertIn("local function repair_required_controller(now)", text)
        self.assertIn("authorize_required_controller(profile, active)", text)
        self.assertIn("return probe_required_controller(profile, player, 0)", text)
        self.assertIn("active.next_controller_probe_at = nil", text)
        self.assertIn("local function issue_profile_combat_off(profile, visible)", text)
        self.assertIn("issue(silent and 'pc reconcile off' or 'pc off')", text)
        self.assertIn("local function local_is_combat_participant(profile)", text)
        self.assertIn("util.same_name(name, combat.leader)", text)
        self.assertIn("util.same_name(name, combat.puller)", text)
        self.assertIn("util.contains_name(combat.attackers or {}, name)", text)
        self.assertIn("util.contains_name(combat.targeters or {}, name)", text)
        self.assertIn(
            "local function apply_legacy_combat_state_locally(profile, enabled)",
            text,
        )
        self.assertIn("issue('pc reconcile off')", text)
        self.assertEqual(text.count("issue(enabled and 'pc on' or 'pc off')"), 1)
        self.assertNotIn("issue('pc on')", text)
        self.assertIn("if not enabled and (not local_is_leader(profile) or protocol_two)", text)
        self.assertIn("converge the leader locally as well as every remote member", text)
        self.assertIn("if pending_reapply then", text)
        self.assertNotIn("local function application_ready", text)
        self.assertNotIn("local function activation_ready", text)
        self.assertNotIn("broadcast_fault", text)
        self.assertNotIn("runtime_faulting", text)

        combat_ready = text.split(
            "context.combat_ready = function()", 1
        )[1].split("context.operator_armed = function()", 1)[0]
        self.assertIn("return active ~= nil and not pending_reapply", combat_ready)
        for forbidden in (
            "preflight", "ack", "controller", "host_ready", "legacy_ready",
        ):
            self.assertNotIn(forbidden, combat_ready.lower())

        arm = text.split("elseif command == 'arm' then", 1)[1].split(
            "elseif command == 'disarm' then", 1
        )[0]
        self.assertIn("request_operator_state(true)", arm)
        for forbidden in (
            "preflight", "ack", "controller_ready", "host_ready",
            "application_ready", "activation_ready",
        ):
            self.assertNotIn(forbidden, arm.lower())

        force = text.split("elseif command == 'force' then", 1)[1].split(
            "elseif command == 'check'", 1
        )[0]
        self.assertIn("request_operator_state(true)", force)
        self.assertIn("profile.runtime_owns_pull == true", force)
        self.assertIn("active.runtime", force)
        self.assertIn("issue('pc force')", force)
        self.assertIn("adapter.lifecycle_authorization == true", force)
        self.assertIn("tonumber(adapter.protocol) >= 2", force)
        self.assertIn("if ordered_lifecycle then", force)
        for forbidden in (
            "preflight", "ack", "controller_ready", "host_ready",
            "application_ready", "activation_ready",
        ):
            self.assertNotIn(forbidden, force.lower())

        operator = text.split("process_operator_state = function(", 1)[1].split(
            "request_operator_state = function", 1
        )[0]
        self.assertIn("util.contains_name(names, source)", operator)
        self.assertIn("if not local_is_leader(profile) then return true end", operator)
        self.assertIn("source_sequence < prior.sequence", operator)
        self.assertIn("if prior.bit ~= bit then return false end", operator)
        self.assertIn("if revision < current_revision then return false end", operator)
        self.assertIn("if record.operator_armed ~= desired then return false end", operator)
        self.assertIn("apply_operator_locally(record, profile)", operator)
        self.assertIn("carry_operator_snapshot(record, revision, desired)", operator)
        self.assertNotIn("preflight", operator.lower())
        self.assertNotRegex(operator.lower(), r"\back\b")

        self.assertIn("elseif kind == 'stop' and #fields == 10 then", text)
        self.assertIn("elseif kind == 'state' and #fields == 15 then", text)
        self.assertIn("elseif kind == 'operator-request' and #fields == 11", text)
        self.assertIn("elseif kind == 'operator-state' and #fields == 11", text)
        self.assertIn("if kind == 'prepare' and #fields == 14 then", text)
        self.assertIn("elseif kind == 'commit' and #fields == 14 then", text)
        self.assertIn("apply_epoch = valid_epoch_token(apply_epoch)", text)
        self.assertIn("adapter.lifecycle_stop_fences or {}", text)
        self.assertIn("gs c ptgs action %s retire", text)
        self.assertGreaterEqual(text.count("if #args == 4 then"), 3)
        self.assertIn("if #args == 10 or #args == 12 then", text)

        prepare = text.split("local function process_prepare(", 1)[1].split(
            "local function announce_prepare", 1
        )[0]
        self.assertIn("ready = true", prepare)
        self.assertIn("setup warning: '..diagnostic", prepare)

        finalize = text.split("finalize_session = function(", 1)[1].split(
            "local function deactivate_runtime", 1
        )[0]
        self.assertIn("session.decided = 'commit'", finalize)
        self.assertIn("Loading %s on %d/%d ready clients (best-effort).", finalize)
        self.assertNotIn("announce_abort(session, 'validation", finalize)

        manual = text.split("local function request_manual(action)", 1)[1].split(
            "local function preflight_bucket", 1
        )[0]
        self.assertIn("process_manual(nonce", manual)
        for forbidden in (
            "preflight_", "active.acks", "acknowledgement_count",
            "controller_ready", "host_ready", "application_ready",
            "activation_ready",
        ):
            self.assertNotIn(forbidden, manual.lower())

        runtime_failure = text.split("local function invoke_runtime(", 1)[1].split(
            "local function adapter_action_allowed", 1
        )[0]
        self.assertIn("record.runtime_failed_methods[method]", runtime_failure)
        self.assertIn(
            "record.runtime_failed_methods[method] = true", runtime_failure
        )
        self.assertNotIn("record.runtime_failed = true", runtime_failure)
        self.assertIn("Other profile callbacks, manual controls", runtime_failure)
        self.assertNotIn("issue('pc off')", runtime_failure)
        self.assertNotIn("send_ipc", runtime_failure)

        claim = text.split("context.party_claimed = function(mob)", 1)[1].split(
            "context.alert = function", 1
        )[0]
        self.assertIn("for index = 0, 5 do", claim)
        self.assertIn("windower.ffxi.get_player()", claim)
        self.assertIn("tonumber(player.id) == claim_id", claim)
        self.assertIn("party['p'..tostring(index)]", claim)
        self.assertIn("member.mob.id", claim)
        self.assertNotRegex(claim, r"\ba[0-9]+\b")

        unload = text.split("windower.register_event('unload'", 1)[1].split(
            "end)", 1
        )[0]
        self.assertIn(
            "stop_local('PartyTactics unloaded locally', nil, true)", unload
        )
        self.assertNotIn("send_ipc", unload)
        self.assertIn(
            "compiler.teardown(job, owns_autows2, local_only == true)", text
        )
        compiler = (ROOT / "lib" / "compiler.lua").read_text(encoding="utf-8")
        self.assertIn("local_only and 'pc localinvalidate partytactics'", compiler)
        self.assertIn("record.runtime_deactivated", text)

    def test_maintenance_uses_the_narrow_gearswap_fast_lane(self):
        text = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        invocation = "issue('lua i GearSwap party_tactics_maintenance_tick')"
        self.assertIn(invocation, text)
        for legacy_command in (
            "gs c pstartbrd tick",
            "gs c pstartrdm tick",
            "gs c pstartpld tick",
            "gs c pstartdnc tick",
            "gs c pstartgeo tick",
            "gs c pstartwhm tick",
        ):
            self.assertEqual(text.count(legacy_command), 1)

        maintenance = text.split(
            "local function maintenance_tick(now)", 1
        )[1].split("windower.register_event('ipc message'", 1)[0]
        self.assertLess(
            maintenance.index("not active or pending_reapply"),
            maintenance.index(invocation),
        )
        self.assertIn("now < next_maintenance", maintenance)
        self.assertIn("next_maintenance = now + MAINTENANCE_INTERVAL", maintenance)
        self.assertIn("gearswap_maintenance_fast_lane", maintenance)
        self.assertIn("issue(fallback)", maintenance)
        self.assertNotIn("gs c pstart", maintenance)
        self.assertIn(
            "local gearswap_maintenance_fast_lane = fingerprint.contains(",
            text,
        )
        self.assertIn("function party_tactics_maintenance_tick()", text)

    def test_stable_host_capability_probe_is_epoch_bound_and_failure_is_local(self):
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        host = GEARSWAP_HOST.read_text(encoding="utf-8")
        schema = (ROOT / "lib" / "schema.lua").read_text(encoding="utf-8")

        self.assertIn("local GEARSWAP_HOST_REVISION = '1.2.1'", core)
        self.assertIn("local function request_gearswap_host_probe(record)", core)
        self.assertIn(
            "issue(('gs c ptgs probe %s %.0f'):format(record.nonce, epoch))",
            core,
        )
        self.assertGreaterEqual(
            core.count("request_gearswap_host_probe(active)"), 2,
            "initial apply and post-zone reapply must both refresh host status",
        )
        self.assertIn("local function process_gearswap_host_ready", core)
        self.assertIn("record.host_ready_revision ~= GEARSWAP_HOST_REVISION", core)
        self.assertIn("tonumber(record.host_ready_epoch) ~= epoch", core)
        self.assertIn("active.host_ready_revision = revision", core)
        self.assertIn("active.host_ready_epoch = epoch", core)
        self.assertIn("elseif command == '__gearswap_host_ready' then", core)
        self.assertIn("__gearswap_host_ready=true", schema)

        self.assertIn("local HOST_REVISION = '1.2.1'", host)
        self.assertIn(
            "local SUPPORTED_ADAPTER_PROTOCOLS = {[1]=true, [2]=true}", host
        )
        self.assertIn("elseif operation == 'probe' then", host)
        self.assertIn("safe_generation(command_args[3])", host)
        self.assertIn("safe_epoch(command_args[4]) == nil", host)
        self.assertIn(
            "windower.send_command(('pt __gearswap_host_ready %s %s %d')",
            host,
        )
        self.assertIn("notify_host_lost('adapter-error')", host)
        self.assertLess(
            host.index("notify_host_lost('adapter-error')"),
            host.index("call_deactivate(record, 'error:'..method)"),
            "adapter failure must report capability loss before local cleanup",
        )

        host_lost = core.split(
            "elseif command == '__gearswap_host_lost' then", 1
        )[1].split("if command == 'use' then", 1)[0]
        self.assertIn("manual controls and profile support remain available", host_lost)
        self.assertNotIn("stop_local", host_lost)
        self.assertNotIn("issue('pc off')", host_lost)
        self.assertNotIn("runtime_failed", host_lost)

    def test_missing_or_mismatched_dependencies_warn_without_withholding_profiles(self):
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        for dependency in (
            "PartyCombat.lua", "AutoWS2.lua", "Roller2.lua", "HealBot.lua",
            "GearSwap host source", "GearSwap host live copy",
        ):
            self.assertIn(dependency, core)
        self.assertIn("if source == 'unavailable' or live == 'unavailable'", core)
        self.assertIn("source ~= live", core)
        self.assertIn("local catalog_warnings = {}", core)
        self.assertIn("if not gearswap_host_ready then", core)
        self.assertIn("if digest == 'unavailable' then", core)
        self.assertIn("affected actions will remain best-effort", core)
        self.assertIn("__gearswap_adapter_source_digest ~= 'unavailable'", core)
        self.assertIn("__gearswap_adapter_live_digest ~= 'unavailable'", core)
        self.assertIn(
            "__gearswap_adapter_source_digest\n"
            "                == profiles[id].__gearswap_adapter_live_digest",
            core,
        )
        self.assertIn("if profile_adapter and not profile_adapter_ready then", core)
        self.assertIn("the profile remains selectable and unaffected lanes still run", core)
        self.assertIn("local engine_signature = fingerprint.combine(engine_sources)", core)
        self.assertIn("ok, signature = pcall(fingerprint.plan,", core)
        self.assertEqual(core.count("profiles[id], plans[id] = nil, nil"), 1)
        for forbidden in (
            "if not legacy_gearswap_ready or not gearswap_host_ready then",
            "if engine_sources_ready and profile_adapter_ready then",
            "quarantined: shared GearSwap adapter closure is unavailable",
            "quarantined: a required engine dependency is unavailable",
            "quarantined: pinned GearSwap host/adapter is missing ",
        ):
            self.assertNotIn(forbidden, core)

    def test_frozen_legacy_gearswap_sources_match_authored_copies(self):
        for job, (source, live) in LEGACY_HELPERS.items():
            self.assertTrue(source.is_file(), f"missing frozen {job} source")
            authored = PARTYSTART_GS / f"PartyStart_{job}.lua"
            self.assertTrue(authored.is_file(), f"missing authored {job} helper")
            self.assertEqual(
                source.read_bytes(), authored.read_bytes(),
                f"frozen {job} source differs from its reviewed authored copy",
            )

    @unittest.skipUnless(CHECK_INSTALLED, 'installed-file checks are opt-in')
    def test_frozen_legacy_gearswap_sources_match_installed_common_copies(self):
        for job, (source, live) in LEGACY_HELPERS.items():
            self.assertTrue(live.is_file(), f"missing live {job} helper")
            self.assertEqual(
                source.read_bytes(), live.read_bytes(),
                f"frozen {job} helper differs from the loaded Common copy",
            )

    def test_each_frozen_helper_reports_an_epoch_bound_capability_probe(self):
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        schema = (ROOT / "lib" / "schema.lua").read_text(encoding="utf-8")
        self.assertIn("local LEGACY_GEARSWAP_VERSION = '1.0.0'", core)
        self.assertIn("local LEGACY_HELPER_PREFIX = {", core)
        self.assertIn("local function request_legacy_helper_probe(record)", core)
        self.assertIn(
            "issue(('gs c %s probe %s %.0f %s'):format(", core
        )
        self.assertGreaterEqual(core.count("request_legacy_helper_probe(active)"), 2)
        self.assertIn("local function process_legacy_helper_ready", core)
        self.assertIn("record.legacy_ready_revision ~= LEGACY_GEARSWAP_VERSION", core)
        self.assertIn("record.legacy_ready_job ~= record.job", core)
        self.assertIn("tonumber(record.legacy_ready_epoch) ~= epoch", core)
        self.assertIn("elseif command == '__legacy_helper_ready' then", core)
        self.assertIn("__legacy_helper_ready=true", schema)

        for job, (canonical, _) in LEGACY_HELPERS.items():
            text = canonical.read_text(encoding="utf-8")
            lower = job.lower()
            self.assertIn(
                f"local PSTART_{job}_HELPER_VERSION = '1.0.0'", text
            )
            self.assertIn(
                f"local function pstart_{lower}_prove_helper(", text
            )
            self.assertIn("generation:match('^%d+%-%d+%-%d+$')", text)
            self.assertIn("epoch ~= math.floor(epoch)", text)
            self.assertIn("if requested == 'probe' then", text)
            self.assertIn(
                f"pt __legacy_helper_ready %s {job} %s %d", text
            )

    def test_universal_sleep_is_bounded_to_barneys_existing_controller(self):
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        schema = (ROOT / "lib" / "schema.lua").read_text(encoding="utf-8")
        adapter = (
            ROOT / "adapters" / "manual" / "brd-pack-sleep.lua"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "sleep={character='Barneystinson', adapter='brd-pack-sleep'}",
            core,
        )
        self.assertNotIn("application_ready(", core)
        self.assertNotIn("activation_ready(", core)
        self.assertIn("elseif command == 'sleep' then", core)
        self.assertIn("manual_adapters['brd-pack-sleep']", core)
        fallback = core.split(
            "local function manual_action_policy(profile, action)", 1
        )[1].split("local function expected_names", 1)[0]
        self.assertLess(
            fallback.index("UNIVERSAL_MANUAL_ACTIONS[action]"),
            fallback.index("profile.manual_actions"),
        )
        self.assertIn("action == 'sleep'", schema)
        self.assertIn("audit=true, sleep=true", schema)
        self.assertIn(
            "RESERVED_COMMANDS[action] and action ~= 'sleep'", schema
        )
        self.assertIn("policy.character ~= 'Barneystinson'", schema)
        self.assertIn("policy.adapter ~= 'brd-pack-sleep'", schema)
        self.assertIn("ctx.actions.controller('brd', 'sleep')", adapter)
        self.assertNotRegex(adapter.lower(), r"\b(windower|send_command|equip)\b")

        request = core.split("local function request_manual(action)", 1)[1].split(
            "local function preflight_bucket", 1
        )[0]
        self.assertIn("process_manual(nonce", request)
        self.assertIn("policy.character ~= 'Barneystinson'", request)
        self.assertIn("policy.adapter ~= 'brd-pack-sleep'", request)
        for forbidden in (
            "preflight_", "active.acks", "acknowledgement_count",
            "controller_ready", "host_ready", "application_ready",
            "activation_ready",
        ):
            self.assertNotIn(forbidden, request.lower())

    def test_exact_enemy_adapter_has_only_bounded_typed_action_surface(self):
        text = (
            ROOT / "adapters" / "manual" / "exact-enemy-action.lua"
        ).read_text(encoding="utf-8")
        lower = text.lower()
        self.assertIn("ctx.actions[policy.kind]", text)
        self.assertIn("ctx.mob_array()", text)
        self.assertIn("mob.spawn_type == 16", text)
        self.assertIn("mob.valid_target", text)
        self.assertIn("mob.id >= 1", text)
        self.assertIn("mob.id <= 4294967295", text)
        self.assertIn("policy.prefer_highest_hpp == true", text)
        self.assertNotIn("windower", lower)
        self.assertNotIn("send_command", lower)
        self.assertNotRegex(text, r"ctx\.(command|issue|equip|disable|enable)\b")
        self.assertNotRegex(lower, r"\b(equip|engage|target)\s*\(")

    def test_rdm_exact_silence_adapter_requires_party_claim_and_typed_queue(self):
        text = (
            ROOT / "adapters" / "manual" / "rdm-exact-silence.lua"
        ).read_text(encoding="utf-8")
        schema = (ROOT / "lib" / "schema.lua").read_text(encoding="utf-8")
        lower = text.lower()
        self.assertIn("ctx.actions.controller('rdm', 'silence', selected.id)", text)
        self.assertIn("ctx.party_claimed(mob)", text)
        self.assertIn("ctx.mob_array()", text)
        self.assertIn("mob.spawn_type == 16", text)
        self.assertIn("mob.id <= 4294967295", text)
        self.assertIn("policy.adapter == 'rdm-exact-silence'", schema)
        self.assertIn("member_requirement(profile, policy.character)", schema)
        self.assertIn("~= 'RDM'", schema)
        self.assertNotIn("windower", lower)
        self.assertNotIn("send_command", lower)
        self.assertNotRegex(text, r"ctx\.(command|issue|equip|disable|enable)\b")
        self.assertNotRegex(lower, r"\b(equip|engage|target)\s*\(")

    def test_locus_support_fixes_are_opt_in_and_shell_stays_off(self):
        profile = (PROFILE_ROOT / "locus-dire-bats-tomb" / "profile.lua").read_text(
            encoding="utf-8"
        )
        rdm = (PARTYSTART_GS / "PartyStart_RDM.lua").read_text(encoding="utf-8")
        geo = (PARTYSTART_GS / "PartyStart_GEO.lua").read_text(encoding="utf-8")

        self.assertIn("preset='locusbats-protect'", profile)
        self.assertIn("mode='leanmanaged'", profile)
        self.assertIn("combat_entrust_only=false", profile)

        legacy = rdm.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        isolated = rdm.split("    ['locusbats-protect'] = {", 1)[1].split(
            "\n    },\n}", 1
        )[0]
        self.assertIn("party_shell = false", legacy)
        self.assertNotIn("party_protect_first", legacy)
        self.assertIn("party_shell = false", isolated)
        self.assertIn("party_protect = true", isolated)
        self.assertIn("party_protect_first = true", isolated)
        self.assertIn("local function pstart_geo_managed_action()", geo)

    def test_each_profile_is_a_self_contained_directory(self):
        directories = sorted(path for path in PROFILE_ROOT.iterdir() if path.is_dir())
        base_registry = PROFILE_REGISTRY.read_text(encoding="utf-8")
        base_count = len(re.findall(r"\bordinal\s*=\s*\d+", base_registry))
        extension_count = len(list(
            (ROOT / "data" / "profile_identities").glob("*.lua")
        ))
        self.assertEqual(len(directories), base_count + extension_count)
        for directory in directories:
            self.assertTrue((directory / "profile.lua").is_file())
            self.assertTrue((directory / "research.md").is_file())

    def test_profile_cloner_keeps_inherited_easyfarm_assets_local(self):
        tool = (ROOT / "tools" / "New-PartyTacticsProfile.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("$easyFarmSource = Join-Path $source 'easyfarm'", tool)
        self.assertIn("Copy-Item -LiteralPath $easyFarmSource", tool)
        self.assertIn("-Destination $resolvedDestination", tool)
        self.assertIn("-Recurse", tool)

    def test_profile_cloner_creates_an_isolated_identity_and_no_adapter_alias(self):
        tool = (ROOT / "tools" / "New-PartyTacticsProfile.ps1").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            tool.count("[ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')]"),
            2,
        )
        self.assertIn("data\\profile_identities", tool)
        self.assertIn("$identityPath = Join-Path $identityRoot ($Id + '.lua')", tool)
        self.assertIn("Isolated append-only identity for $Id", tool)
        self.assertIn("id='$Id'", tool)
        self.assertIn("policy_id='$policyId'", tool)
        self.assertIn("aliases={}", tool)
        self.assertIn("gearswap_adapter\\s*=\\s*\\{", tool)
        self.assertIn("controller\\s*=\\s*\\{", tool)
        self.assertIn("adapter whose id matches $Id", tool)

        # Refuse an existing sidecar before creating or copying the profile;
        # otherwise a scaffold typo could overwrite append-only ownership.
        collision = "if (Test-Path -LiteralPath $identityPath)"
        self.assertIn(collision, tool)
        self.assertLess(
            tool.index(collision),
            tool.index("New-Item -ItemType Directory -Path $resolvedDestination"),
        )

        # The bootstrap is read-only input for calculating the next ordinal.
        # It may never become a Set-Content/Copy-Item destination.
        self.assertNotRegex(
            tool,
            r"(?is)(?:Set-Content|Copy-Item).*?-LiteralPath\s+"
            r"\$?(?:profileRegistry|registryPath)",
        )

    def test_frozen_profile_aliases_precede_active_manual_shorthands(self):
        core = (ROOT / "PartyTactics.lua").read_text(encoding="utf-8")
        alias_dispatch = "elseif resolve_profile(command) then"
        manual_dispatch = "elseif active and profiles[active.id].manual_actions"
        self.assertIn(alias_dispatch, core)
        self.assertIn(manual_dispatch, core)
        self.assertLess(core.index(alias_dispatch), core.index(manual_dispatch))
        self.assertIn("begin(resolve_profile(command), false, false, true)", core)

    def test_locus_easyfarm_artifact_matches_profile_contract(self):
        profile_directory = PROFILE_ROOT / "locus-dire-bats-tomb"
        profile_text = (profile_directory / "profile.lua").read_text(
            encoding="utf-8"
        )
        easyfarm = profile_text.split("    easyfarm = {", 1)[1].split(
            "\n    },", 1
        )[0]

        def string_field(name):
            match = re.search(
                rf"\b{name}\s*=\s*(['\"])(.*?)\1", easyfarm
            )
            self.assertIsNotNone(match, f"missing easyfarm.{name}")
            return match.group(2)

        def number_field(name):
            match = re.search(rf"\b{name}\s*=\s*(\d+(?:\.\d+)?)", easyfarm)
            self.assertIsNotNone(match, f"missing easyfarm.{name}")
            return float(match.group(1))

        metadata = {
            "character": string_field("character"),
            "expected_target": string_field("expected_target"),
            "artifact": string_field("artifact"),
            "detection_distance": number_field("detection_distance"),
            "pull_action": string_field("pull_action"),
            "pull_distance": number_field("pull_distance"),
        }
        self.assertEqual(metadata["character"], "Tackleberry")
        self.assertEqual(metadata["expected_target"], "Locus Dire Bat")
        self.assertEqual(
            metadata["artifact"],
            "easyfarm/Tackleberry-Locus-Dire-Bats-Stationary.eup",
        )

        artifact_path = profile_directory / metadata["artifact"]
        self.assertTrue(artifact_path.is_file())
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))

        # This exact one-entry allowlist is the main cross-profile safety
        # boundary: no default or previously used target may leak in.
        self.assertEqual(
            artifact["TargetedMobs"], [metadata["expected_target"]]
        )
        self.assertEqual(artifact["DetectionDistance"], 18)
        self.assertEqual(
            artifact["DetectionDistance"], metadata["detection_distance"]
        )
        self.assertIs(artifact["IsApproachEnabled"], False)
        self.assertIs(artifact["IsEngageEnabled"], True)

        pull_lists = [
            battle_list
            for battle_list in artifact["BattleLists"]
            if battle_list["Name"] == "Pull"
        ]
        self.assertEqual(len(pull_lists), 1)
        enabled_pull_actions = [
            action
            for action in pull_lists[0]["Actions"]
            if action["IsEnabled"]
        ]
        self.assertEqual(len(enabled_pull_actions), 1)
        flash = enabled_pull_actions[0]
        self.assertEqual(flash["Name"], "Flash")
        self.assertEqual(flash["Name"], metadata["pull_action"])
        self.assertEqual(flash["Distance"], 20)
        self.assertEqual(flash["Distance"], metadata["pull_distance"])
        self.assertEqual(flash["Command"], "/magic Flash <t>")

    def test_limbus_easyfarm_artifact_matches_reviewed_allowlist(self):
        profile_directory = PROFILE_ROOT / "limbus-119-stationary"
        profile_text = (profile_directory / "profile.lua").read_text(
            encoding="utf-8"
        )
        easyfarm = profile_text.split("    easyfarm = {", 1)[1].split(
            "\n    },", 1
        )[0]

        def string_field(name):
            match = re.search(
                rf"\b{name}\s*=\s*(['\"])(.*?)\1", easyfarm
            )
            self.assertIsNotNone(match, f"missing easyfarm.{name}")
            return match.group(2)

        def number_field(name):
            match = re.search(rf"\b{name}\s*=\s*(\d+(?:\.\d+)?)", easyfarm)
            self.assertIsNotNone(match, f"missing easyfarm.{name}")
            return float(match.group(1))

        metadata = {
            "character": string_field("character"),
            "artifact": string_field("artifact"),
            "detection_distance": number_field("detection_distance"),
            "pull_action": string_field("pull_action"),
            "pull_distance": number_field("pull_distance"),
        }
        self.assertEqual(metadata["character"], "Tackleberry")
        self.assertEqual(
            metadata["artifact"],
            "easyfarm/Tackleberry-Limbus-119-Stationary.eup",
        )

        artifact_path = profile_directory / metadata["artifact"]
        self.assertTrue(artifact_path.is_file())
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))

        reviewed_targets = {
            "Om'Xzomit",
            "Om'Aern",
            "Om'Hpemde",
            "Om'Yovra",
            "Om'Phuabo",
            "Uptala",
            "Apollyon Eft",
            "Apollyon Lizard",
            "Apollyon Raptor",
            "Apollyon Shadow Dragon",
            "Apollyon Cyhiraeth",
            "Apollyon Gargouille",
            "Apollyon Demon",
            "Apollyon Ahriman",
        }
        targets = artifact["TargetedMobs"]
        self.assertEqual(len(targets), 14)
        self.assertEqual(set(targets), reviewed_targets)
        self.assertFalse(
            any(re.match(r"^(Apex|Locus)", target, re.IGNORECASE)
                for target in targets),
            "Limbus artifact inherited an XP-camp target",
        )
        self.assertEqual(artifact["IgnoredMobs"], [r"\bElemental\b"])

        self.assertEqual(artifact["DetectionDistance"], 18)
        self.assertEqual(
            artifact["DetectionDistance"], metadata["detection_distance"]
        )
        self.assertIs(artifact["IsApproachEnabled"], False)
        self.assertIs(artifact["IsEngageEnabled"], True)
        self.assertIn("movement='stationary'", profile_text)

        pull_lists = [
            battle_list
            for battle_list in artifact["BattleLists"]
            if battle_list["Name"] == "Pull"
        ]
        self.assertEqual(len(pull_lists), 1)
        enabled_pull_actions = [
            action
            for action in pull_lists[0]["Actions"]
            if action["IsEnabled"]
        ]
        self.assertEqual(len(enabled_pull_actions), 1)
        flash = enabled_pull_actions[0]
        self.assertEqual(flash["Name"], "Flash")
        self.assertEqual(flash["Name"], metadata["pull_action"])
        self.assertEqual(flash["Distance"], 20)
        self.assertEqual(flash["Distance"], metadata["pull_distance"])
        self.assertEqual(flash["Command"], "/magic Flash <t>")

    def test_no_partytactics_file_writes_into_gearswap(self):
        production_files = [ROOT / "PartyTactics.lua"]
        production_files.extend((ROOT / "lib").glob("*.lua"))
        production_files.extend((ROOT / "adapters").rglob("*.lua"))
        production_files.extend(PROFILE_ROOT.rglob("*.lua"))
        for path in production_files:
            text = path.read_text(encoding="utf-8").lower()
            self.assertNotIn("program files (x86)", text)
            # The engine may hash relative GearSwap integration sources as a
            # read-only compatibility signature. Ignore only those calls; a
            # command, output path, or any other GearSwap/data use still fails.
            without_read_only_hashes = re.sub(
                r"fingerprint\.file\(.*?\)", "", text,
                flags=re.DOTALL,
            )
            self.assertNotIn("gearswap/data", without_read_only_hashes)
            self.assertNotRegex(text, r"io\.(output|write)")
            self.assertNotRegex(
                text, r"io\.open\([^\n)]*,\s*['\"][^'\"]*[wa+]"
            )
            if path.name == "fingerprint.lua":
                self.assertEqual(text.count("io.open(path, 'rb')"), 1)
                text = text.replace("io.open(path, 'rb')", "")
            self.assertNotIn("io.open", text)

    def test_genmei_runtime_uses_only_exact_bounded_typed_surfaces(self):
        text = (
            PROFILE_ROOT / "escha-ruaun-genbu-genmei" / "runtime.lua"
        ).read_text(encoding="utf-8")
        self.assertIn("ctx.operator_armed()", text)
        self.assertIn("ctx.authorize_encounter(boss.id)", text)
        self.assertIn("ctx.party_claimed(boss)", text)
        self.assertIn("ctx.client.engage_once(boss.id)", text)
        self.assertIn("ctx.actions.combat_force(boss.id)", text)
        self.assertIn("ctx.actions.combat_stop()", text)
        self.assertIn("ctx.actions.party_adapter(", text)
        for action in (
            "barwatera", "setup", "crusade", "divine-emblem",
            "sentinel", "flash", "provoke", "haste-samba", "presto", "box-step",
            "shoot", "evisceration", "savage-blade", "last-stand",
            "triple-shot", "proc", "burst", "combat-start",
            "combat-end",
        ):
            self.assertIn(f"'{action}'", text)
        self.assertNotIn("'harden-shell-rdm'", text)
        self.assertNotIn("'harden-shell-brd'", text)
        self.assertNotIn("ctx.actions.controller('genmei'", text)
        for removed_gate in (
            "ctx.encounter_ready", "ctx.combat_ready", "setup_ready",
            "MIN_PARTY_HPP", "abort_chain", "ctx.alert",
        ):
            self.assertNotIn(removed_gate, text)
        self.assertNotRegex(
            text.lower(),
            r"\b(windower|send_command|equip|forceequip|lockstyle)\b",
        )

    def test_genmei_gearswap_adapter_is_fixed_exact_and_equipment_inert(self):
        text = GENMEI_ADAPTER.read_text(encoding="utf-8")
        self.assertIn("id = 'escha-ruaun-genbu-genmei'", text)
        self.assertIn("version = '2.1.0'", text)
        self.assertIn("controller = 'genmei'", text)
        self.assertIn("protocol = 1", text)
        for fixed in (
            "id=25, name='Evisceration'",
            "id=42, name='Savage Blade'",
            "id=221, name='Last Stand'",
            "id=129, name='Thunder Shot'",
            "id=164, name='Thunder'",
            "id=167, name='Thunder IV'",
            "id=820, name='Geo-Malaise'",
            "target.index == request.index",
            "info.zone ~= request.zone",
            "request.expires",
            "request.inflight_until",
            "pt __controller_ready genmei",
            "pt __controller_lost genmei",
        ):
            self.assertIn(fixed, text)
        # Assert the safety behavior, not private implementation names: those
        # may be renamed without changing this pinned adapter's contract.
        self.assertRegex(text, r"local [A-Z0-9_]*ZONE\s*=\s*289")
        self.assertRegex(text, r"local [A-Z0-9_]*EMERGENCY_HPP\s*=\s*70")
        self.assertRegex(text, r"local [A-Z0-9_]*MAX_MODEL_SIZE\s*=\s*10")
        self.assertIn("tonumber(target.claim_id)", text)
        self.assertIn("key:match('^p[0-5]$')", text)
        self.assertIn("generation:match('^%d+%-%d+%-%d+$')", text)
        self.assertIn("capability.generation == generation", text)
        self.assertIn("capability.epoch == epoch", text)
        self.assertIn("[78]=true", text)
        self.assertIn("[84]=true", text)
        self.assertIn("math.sqrt(squared)", text)
        self.assertIn("math.min(", text)
        for method in (
            "activate", "deactivate", "handle_action", "status",
            "pre_tick", "user_job_tick", "filter_pretarget",
            "filter_precast", "job_aftercast", "file_unload",
            "action_event", "prerender", "zone_change", "logout",
            "unload", "status_change",
        ):
            self.assertIn(f"function M.{method}", text)
        self.assertIn("windower.chat.input(action.command", text)
        self.assertNotRegex(
            text.lower(),
            r"\b(equip|forceequip|disable|enable|lockstyle|packets\.inject)\s*\(",
        )
        self.assertNotRegex(
            text,
            r"(?m)^function\s+(?:pre_tick|user_job_tick|"
            r"user_filter_pretarget|user_filter_precast|job_aftercast|"
            r"user_job_self_command|file_unload)\s*\(",
        )
        self.assertNotIn("windower.raw_register_event", text)
        self.assertNotIn("windower.register_event", text)

    def test_current_cooperative_adapters_never_filter_manual_actions(self):
        cooperative = (
            ("escha-ruaun-genbu-genmei", "2.7.0"),
            ("ambuscade-2026-09-v1-qutrub-bigwig-no-cait", "1.10.0"),
        )
        for adapter_id, version in cooperative:
            with self.subTest(adapter=adapter_id):
                path = (
                    ROOT / "gearswap" / "adapters"
                    / adapter_id / f"{version}.lua"
                )
                text = path.read_text(encoding="utf-8")
                self.assertIn(f"version = '{version}'", text)
                self.assertIn("function M.filter_pretarget", text)
                self.assertIn("function M.filter_precast", text)
                self.assertGreaterEqual(text.count("return false"), 2)
                self.assertIn("manual-pass-through", text)
                self.assertNotIn("event_args.cancel", text)
                self.assertNotIn("windower.raw_register_event", text)
                self.assertNotRegex(
                    text.lower(),
                    r"\b(equip|forceequip|lockstyle|packets\.inject)\s*\(",
                )

        rancibus = (
            ROOT / "gearswap" / "adapters"
            / "vagary-direct-rancibus" / "1.1.0.lua"
        ).read_text(encoding="utf-8")
        self.assertNotIn("function M.filter_pretarget", rancibus)
        self.assertNotIn("function M.filter_precast", rancibus)
        self.assertNotIn("event_args.cancel", rancibus)
        self.assertNotIn("windower.raw_register_event", rancibus)
        self.assertNotRegex(
            rancibus.lower(),
            r"\b(equip|forceequip|lockstyle|packets\.inject)\s*\(",
        )

    def test_schema_and_host_share_the_exact_profile_adapter_grammar(self):
        schema = (ROOT / "lib" / "schema.lua").read_text(encoding="utf-8")
        host = GEARSWAP_HOST.read_text(encoding="utf-8")
        self.assertIn("local function valid_adapter_identifier", schema)
        self.assertIn("value:match('^[a-z0-9][a-z0-9%-]*$')", schema)
        self.assertIn("local function valid_adapter_semantic", schema)
        self.assertIn("value:match('^[a-z0-9][a-z0-9_%-]*$')", schema)
        self.assertIn("local function valid_adapter_version", schema)
        self.assertIn("adapter.id ~= profile.id", schema)
        self.assertIn("fight adapters cannot be shared between profiles", schema)
        self.assertIn("local function supported_controller_protocol", schema)
        self.assertIn("return value == 1 or value == 2", schema)
        self.assertIn("not supported_controller_protocol(adapter.protocol)", schema)
        self.assertIn("if tonumber(adapter.protocol) == 2", schema)
        self.assertIn("revisioned operator semantic", schema)
        self.assertIn("action == 'probe'", schema)
        self.assertIn(
            "type(policy.required_before_combat) ~= 'boolean'", schema
        )
        self.assertNotIn(
            "profile.preflight.required_before_combat ~= true", schema
        )
        self.assertIn("for member_name, _ in pairs(profile.members or {})", schema)
        self.assertIn("controller.name ~= adapter.controller", schema)
        self.assertIn(
            "controller routing metadata for '..tostring(member_name)", schema
        )

        self.assertIn("local function safe_identifier", host)
        self.assertIn("value:match('^[a-z0-9][a-z0-9%-]*$')", host)
        self.assertIn("local function safe_semantic", host)
        self.assertIn("value:match('^[a-z0-9][a-z0-9_%-]*$')", host)
        self.assertIn("local function safe_semver", host)
        self.assertIn("module.id ~= adapter_id", host)
        self.assertIn("module.version ~= version", host)
        self.assertIn("SUPPORTED_ADAPTER_PROTOCOLS = {[1]=true, [2]=true}", host)
        self.assertIn("not SUPPORTED_ADAPTER_PROTOCOLS[module.protocol]", host)
        self.assertNotIn("module.protocol ~= HOST_PROTOCOL", host)

    def test_gearswap_host_is_the_only_callback_and_raw_event_owner(self):
        text = GEARSWAP_HOST.read_text(encoding="utf-8")
        for callback in (
            "pre_tick", "user_job_tick", "user_filter_pretarget",
            "user_filter_precast", "job_aftercast", "user_job_self_command",
            "file_unload",
        ):
            self.assertRegex(text, rf"(?m)^function {callback}\(")
        for event in (
            "action", "prerender", "zone change", "logout", "unload",
            "status change",
        ):
            self.assertIn(f"windower.raw_register_event('{event}'", text)
        self.assertIn("include('Common/PartyTactics/PartyTactics_Host.lua')", text)
        self.assertIn(
            "return 'Common/PartyTactics/adapters/'..adapter_id..'/'"
            "..version..'.lua'",
            text,
        )
        self.assertIn("record, 'handle_action', controller, semantic, arguments", text)
        self.assertNotRegex(
            text.lower(),
            r"\b(equip|forceequip|disable|enable|lockstyle|packets\.inject)\s*\(",
        )

    @unittest.skipUnless(
        CHECK_INSTALLED and LIVE_GEARSWAP_HOST.is_file(),
        "live PartyTactics GearSwap host not deployed",
    )
    def test_live_host_and_every_pinned_adapter_match_reviewed_source(self):
        self.assertEqual(LIVE_GEARSWAP_HOST.read_bytes(), GEARSWAP_HOST.read_bytes())
        adapter_block = re.compile(
            r"(?ms)^\s{4}gearswap_adapter\s*=\s*\{(.*?)^\s{4}\},"
        )
        pinned_sources = []
        for profile_path in sorted(PROFILE_ROOT.glob("*/profile.lua")):
            text = profile_path.read_text(encoding="utf-8")
            match = adapter_block.search(text)
            if not match:
                continue
            body = match.group(1)
            adapter_id = re.search(r"\bid\s*=\s*'([^']+)'", body).group(1)
            version = re.search(r"\bversion\s*=\s*'([^']+)'", body).group(1)
            pinned_sources.append(
                PROFILE_ADAPTER_ROOT / adapter_id / f"{version}.lua"
            )
        for source in pinned_sources:
            relative = source.relative_to(PROFILE_ADAPTER_ROOT)
            for label, root in (
                ("GearSwap Common", LIVE_PROFILE_ADAPTER_ROOT),
                ("PartyTactics deployment", LIVE_PARTYTACTICS_PROFILE_ADAPTER_ROOT),
            ):
                live = root / relative
                self.assertTrue(
                    live.is_file(), f"missing {label} adapter {relative}"
                )
                self.assertEqual(
                    live.read_bytes(), source.read_bytes(),
                    f"{label} adapter differs from reviewed source: {relative}",
                )

    @unittest.skipUnless(CHECK_INSTALLED, 'installed-file checks are opt-in')
    def test_live_job_files_load_stable_host_once_at_true_eof(self):
        host_include = "include('Common/PartyTactics/PartyTactics_Host.lua')"
        for character, path in LIVE_HOST_JOB_FILES.items():
            self.assertTrue(path.is_file(), f"missing {character} job file")
            text = path.read_text(encoding="utf-8")
            self.assertEqual(
                text.count(host_include), 1,
                f"{character} must load the PartyTactics host exactly once",
            )
            self.assertTrue(
                text.rstrip().endswith(host_include),
                f"{character} must load the PartyTactics host at true EOF",
            )
            helper_name = LIVE_JOB_HELPERS[character]
            helper_includes = re.findall(
                r"include\(['\"]Common/PartyStart_[A-Z]+\.lua['\"]\)", text
            )
            if helper_name is None:
                self.assertEqual(
                    helper_includes, [],
                    f"{character} has no frozen helper assignment",
                )
            else:
                helper_include = f"include('Common/{helper_name}')"
                self.assertEqual(
                    text.count(helper_include), 1,
                    f"{character} must load exactly {helper_name}",
                )
                self.assertEqual(helper_includes, [helper_include])
                self.assertLess(
                    text.index(helper_include), text.index(host_include),
                    f"{character} must load its frozen helper before the host "
                    "captures callbacks",
                )

    def test_kammavaca_runtime_uses_only_bounded_typed_surfaces(self):
        text = (
            PROFILE_ROOT / "escha-ruaun-kammavaca" / "runtime.lua"
        ).read_text(encoding="utf-8")
        self.assertIn("ctx.alert", text)
        for name in ("Clionid", "Limule", "Murex", "Amoeban"):
            self.assertIn(f'"Kammavaca\'s {name}"', text)
        self.assertIn("ctx.party_claimed(boss)", text)
        self.assertIn("ctx.actions.controller('rdm', 'silence', boss.id)", text)
        self.assertNotIn("ctx.actions.cast('Silence'", text)
        self.assertIn("ctx.combat_ready()", text)
        self.assertIn("ADD_ASSOCIATION_RADIUS", text)
        self.assertIn("ctx.party_claimed(mob)", text)
        self.assertIn("if claim_id and claim_id ~= 0 then return false end", text)
        self.assertIn("ctx.actions.combat_observe(anchor.id)", text)
        self.assertIn("ctx.current_target()", text)
        self.assertIn("ctx.actions.controller('brd', 'sleep')", text)
        self.assertIn("ctx.actions.combat_force(target.id)", text)
        self.assertIn("ctx.client.auto_target(false)", text)
        self.assertIn("ctx.client.auto_target(true)", text)
        self.assertIn("MAX_SILENCE_ATTEMPTS", text)
        self.assertIn("MAX_OBSERVE_ATTEMPTS", text)
        self.assertIn("MAX_FORCE_ATTEMPTS", text)
        self.assertNotRegex(
            text,
            r"ctx\.actions\.cast\(\s*['\"]Horde Lullaby II['\"]",
        )
        self.assertNotRegex(
            text.lower(),
            r"\b(windower|send_command|equip|forceequip|lockstyle)\b",
        )

    def test_kammavaca_autotarget_helpers_are_exact_and_inert(self):
        members = (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        )
        for state in ("off", "on"):
            path = ROOT / "scripts" / f"kammavaca_autotarget_{state}.txt"
            lines = [
                line.strip()
                for line in path.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            sends = [line for line in lines if line.startswith("send ")]
            self.assertEqual(
                sends,
                [f"send {name} input /autotarget {state}" for name in members],
            )
            self.assertEqual(len(sends), 6)
            for line in lines:
                self.assertTrue(
                    line.startswith("echo ") or line in sends,
                    f"unexpected active command in {path.name}: {line}",
                )
            active_text = "\n".join(sends).lower()
            for forbidden in (
                " pc ", " pt ", "gs ", "aws2", "r2 ", "hb ",
                "exec ", "wait ", "/attack", "/target", "/equip",
            ):
                self.assertNotIn(forbidden, active_text)

    def test_dynamis_reload_is_staggered_and_inert(self):
        for name in ("Tackleberry", "Kickpuncher", "Barneystinson", "Smalls"):
            self.assertEqual(DYNA_RELOAD.count(f"send {name} gs reload"), 1)
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        ):
            self.assertEqual(
                DYNA_RELOAD.count(f"send {name} lua r PartyTactics"), 1
            )
        lower = DYNA_RELOAD.lower()
        self.assertNotIn("pc on", lower)
        self.assertNotIn("pc force", lower)
        self.assertNotIn("pt use", lower)

    def test_engine_reload_is_six_client_and_inert(self):
        lines = [line.strip() for line in ENGINE_RELOAD.splitlines() if line.strip()]
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        ):
            for addon in ("PartyCombat", "PartyTactics", "AutoWS2", "HealBot"):
                unload = f"send {name} lua unload {addon}"
                load = f"send {name} lua load {addon}"
                self.assertEqual(ENGINE_RELOAD.count(unload), 1)
                self.assertEqual(ENGINE_RELOAD.count(load), 1)
                unload_index = lines.index(unload)
                self.assertEqual(lines[unload_index + 1], "wait 1")
                self.assertEqual(lines[unload_index + 2], load)
                self.assertIn(
                    lines[unload_index + 3], {"wait 2", "wait 3"},
                    f"{name} {addon} load is not staggered",
                )
        for operation in ("unload", "load"):
            self.assertEqual(
                ENGINE_RELOAD.count(
                    f"send Dolomedes lua {operation} Roller2"
                ),
                1,
            )
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo"
        ):
            command = f"send {name} gs reload"
            self.assertEqual(ENGINE_RELOAD.count(command), 1)
            self.assertEqual(lines[lines.index(command) + 1], "wait 10")
        self.assertEqual(ENGINE_RELOAD.count("send Dolomedes pt off"), 1)
        lower = ENGINE_RELOAD.lower()
        self.assertNotIn("pc on", lower)
        self.assertNotIn("pc force", lower)
        self.assertNotIn("pt use", lower)
        self.assertNotIn("pt arm", lower)
        self.assertFalse(any(line.startswith("+") for line in lines))

    def test_genmei_preflight_reload_is_scoped_and_inert(self):
        lines = [line.strip() for line in GENMEI_PREFLIGHT_RELOAD.splitlines()
                 if line.strip()]
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        ):
            for addon in ("PartyCombat", "PartyTactics", "AutoWS2", "HealBot"):
                unload = f"send {name} lua unload {addon}"
                load = f"send {name} lua load {addon}"
                self.assertEqual(GENMEI_PREFLIGHT_RELOAD.count(unload), 1)
                self.assertEqual(GENMEI_PREFLIGHT_RELOAD.count(load), 1)
                index = lines.index(unload)
                self.assertEqual(lines[index + 1], "wait 1")
                self.assertEqual(lines[index + 2], load)
                self.assertIn(lines[index + 3], {"wait 2", "wait 3"})
        for operation in ("unload", "load"):
            self.assertEqual(
                GENMEI_PREFLIGHT_RELOAD.count(
                    f"send Dolomedes lua {operation} Roller2"
                ),
                1,
            )
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo"
        ):
            command = f"send {name} lua reload GearSwap"
            self.assertEqual(GENMEI_PREFLIGHT_RELOAD.count(command), 1)
            self.assertEqual(lines[lines.index(command) + 1], "wait 10")
            self.assertEqual(
                GENMEI_PREFLIGHT_RELOAD.count(
                    f"send {name} gs c ptgs status"
                ),
                1,
            )
            self.assertNotIn(f"send {name} gs reload", GENMEI_PREFLIGHT_RELOAD)
        lower = "\n".join(
            line for line in lines if not line.startswith("echo ")
        ).lower()
        for forbidden in ("pt use", "pt arm", "pc on", "pc force"):
            self.assertNotIn(forbidden, lower)

    def test_kammavaca_reload_repairs_dependencies_and_stays_inert(self):
        lines = [line.strip() for line in KAMMAVACA_RELOAD.splitlines()
                 if line.strip()]
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        ):
            for addon in ("PartyCombat", "PartyTactics"):
                unload = f"send {name} lua unload {addon}"
                load = f"send {name} lua load {addon}"
                self.assertEqual(KAMMAVACA_RELOAD.count(unload), 1)
                self.assertEqual(KAMMAVACA_RELOAD.count(load), 1)
                index = lines.index(unload)
                self.assertEqual(lines[index + 1], "wait 1")
                self.assertEqual(lines[index + 2], load)
                self.assertIn(lines[index + 3], {"wait 2", "wait 3"})
        self.assertEqual(
            KAMMAVACA_RELOAD.count("send Barneystinson gs reload"), 1
        )
        lower = "\n".join(
            line for line in lines if not line.startswith("echo ")
        ).lower()
        for forbidden in ("pt use", "pt arm", "pc on", "pc force"):
            self.assertNotIn(forbidden, lower)

    def test_september_ambu_reload_is_scoped_staggered_and_inert(self):
        lines = [line.strip() for line in SEPTEMBER_AMBU_RELOAD.splitlines()
                 if line.strip()]
        members = (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        )
        self.assertEqual(
            SEPTEMBER_AMBU_RELOAD.count("send Dolomedes pt off"), 1
        )
        for name in members:
            unload = f"send {name} lua unload PartyTactics"
            load = f"send {name} lua load PartyTactics"
            self.assertEqual(SEPTEMBER_AMBU_RELOAD.count(unload), 1)
            self.assertEqual(SEPTEMBER_AMBU_RELOAD.count(load), 1)
            index = lines.index(unload)
            self.assertEqual(lines[index + 1], "wait 1")
            self.assertEqual(lines[index + 2], load)
            self.assertIn(lines[index + 3], {"wait 2", "wait 3"})
            self.assertEqual(
                SEPTEMBER_AMBU_RELOAD.count(
                    f"send {name} gs c ptgs status"
                ),
                1,
            )
        active_lines = "\n".join(
            line for line in lines if not line.startswith("echo ")
        ).lower()
        for forbidden in (
            "pt use", "pt arm", "pc on", "pc force", "gs reload",
            "partystart",
        ):
            self.assertNotIn(forbidden, active_lines)

    def test_qutrub_no_cait_activation_pins_the_revised_live_contract(self):
        text = QUTRUB_NO_CAIT_ACTIVATE
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        members = (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        )
        policy = (
            "pc policy pt-ambu2609v1-qutrub-nocait Dolomedes Dolomedes "
            "Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Achoo "
            "Dolomedes,Kickpuncher,Barneystinson mobile - - -"
        )
        self.assertIn("PartyCombat v0.6.18", text)
        self.assertIn("AutoWS2 v0.3.7", text)
        self.assertIn("PartyTactics v0.11.2", text)
        self.assertIn("no-Cait Qutrub v1.14.0", text)
        self.assertIn("send Smalls gs reload", text)
        self.assertEqual(text.count("bind ^p pt arm"), 1)
        self.assertNotIn("bind ^p pt force", text)
        self.assertEqual(text.count("send Dolomedes pt v1-qutrub-nocait"), 1)
        profile_index = lines.index("send Dolomedes pt v1-qutrub-nocait")
        for name in members:
            command = f"send {name} {policy}"
            self.assertEqual(text.count(command), 1)
            self.assertGreater(lines.index(command), profile_index)
        self.assertIn("send Tackleberry aws2 status", text)
        for name in members[:4] + (members[5],):
            self.assertEqual(text.count(f"send {name} lua load AutoWS2"), 1)
        active_lines = "\n".join(
            line for line in lines if not line.startswith("echo ")
        ).lower()
        self.assertNotIn(" pc on", active_lines)
        self.assertNotIn(" pt force", active_lines)

    def test_locus_support_reload_is_scoped_staggered_and_inert(self):
        self.assertEqual(LOCUS_SUPPORT_RELOAD.count("send Smalls gs reload"), 1)
        self.assertEqual(LOCUS_SUPPORT_RELOAD.count("send Achoo gs reload"), 1)
        for untouched in (
            "Dolomedes", "Tackleberry", "Kickpuncher", "Barneystinson"
        ):
            self.assertNotIn(f"send {untouched} gs reload", LOCUS_SUPPORT_RELOAD)
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        ):
            self.assertEqual(
                LOCUS_SUPPORT_RELOAD.count(f"send {name} lua r PartyTactics"), 1
            )
        lower = LOCUS_SUPPORT_RELOAD.lower()
        self.assertNotIn("pt use", lower)
        self.assertNotIn("pt arm", lower)
        self.assertNotIn("pc on", lower)

    def test_locus_signet_reload_has_one_companion_owner_and_new_partycombat(self):
        members = (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        )
        for name in members:
            self.assertEqual(
                LOCUS_SIGNET_RELOAD.count(
                    f"send {name} lua reload PartyCombat"
                ),
                1,
            )
            self.assertEqual(
                LOCUS_SIGNET_RELOAD.count(
                    f"send {name} lua unload SignetKeeper"
                ),
                1,
            )
            self.assertNotIn(
                f"send {name} lua load SignetKeeper", LOCUS_SIGNET_RELOAD
            )
        self.assertNotIn("lua load JubileeKeeper", LOCUS_SIGNET_RELOAD)
        self.assertNotIn("lua load LocusPuller", LOCUS_SIGNET_RELOAD)
        active = "\n".join(
            line for line in LOCUS_SIGNET_RELOAD.lower().splitlines()
            if not line.strip().startswith("echo ")
        )
        self.assertNotIn("pt locus-signet", active)
        self.assertNotIn("pc on", active)

    @unittest.skipUnless(CHECK_INSTALLED and LIVE_BARNEY.is_file(), "installed-file check disabled or local Barney GearSwap absent")
    def test_local_barney_magic_tank_mode_keeps_gearswap_as_instrument_owner(self):
        text = LIVE_BARNEY.read_text(encoding="utf-8")
        mode = text.split("\tMagicTank = {", 1)[1].split("\t},", 1)[0]
        self.assertIn("Victory March", mode)
        self.assertIn("Knight's Minne V", mode)
        self.assertIn("Mage's Ballad III", mode)
        self.assertIn("'MagicTank'", text)
        self.assertIn("range=song_instrument", text)
        self.assertIn("sets.midcast.Daurdabla", text)
        self.assertIn("function check_song()", text)

    @unittest.skipUnless(
        CHECK_INSTALLED and LIVE_DOLO_COR.is_file()
        and LIVE_SEL_INCLUDE.is_file()
        and LIVE_SEL_UTILITY.is_file(),
        "local COR GearSwap integration absent",
    )
    def test_local_cor_profile_ammo_and_stability_guards(self):
        gear = LIVE_DOLO_COR.read_text(encoding="utf-8")
        include = LIVE_SEL_INCLUDE.read_text(encoding="utf-8")
        utility = LIVE_SEL_UTILITY.read_text(encoding="utf-8")
        locus = (PROFILE_ROOT / "locus-dire-bats-tomb" / "profile.lua").read_text(
            encoding="utf-8"
        )
        limbus = (PROFILE_ROOT / "limbus-119-stationary" / "profile.lua").read_text(
            encoding="utf-8"
        )
        v1 = (
            PROFILE_ROOT / "ambuscade-2026-08-v1-breadwinner" / "profile.lua"
        ).read_text(encoding="utf-8")
        partystart = PARTYSTART_COMPOSITIONS.read_text(encoding="utf-8")
        self.assertIn(
            "sets.weapons.DualSavage = "
            "{main='Naegling', sub=gleti_knife, range=empty}",
            gear,
        )
        self.assertNotIn("DualSavageMelee", gear)
        self.assertIn("weapon_mode='DualSavage'", locus)
        self.assertIn("weapon_mode='DualSavage'", limbus)
        self.assertIn("weapon_mode='DualSavage'", v1)
        self.assertIn("COR = {weapon_mode='DualSavage'", partystart)
        self.assertIn("local function selected_cor_mode_uses_gun()", gear)
        self.assertIn("function extra_user_customize_idle_set(idle_set)", gear)
        self.assertIn("function extra_user_customize_melee_set(melee_set)", gear)
        self.assertIn("function user_job_post_precast(spell, spell_map, event_args)", gear)
        self.assertIn("function user_job_post_midcast(spell, spell_map, event_args)", gear)
        self.assertIn("return set_combine(equip_set, {ammo=gear.RAbullet})", gear)
        self.assertIn(
            "sets.weapons.DualLastStandRanged = "
            "{main=rostam_a, sub='Tauret', range=death_penalty}",
            gear,
        )
        self.assertIn("ammo='Animikii Bullet'", gear)
        self.assertIn("ammo='Living Bullet'", gear)
        self.assertIn("if player.sub_job == 'THF' then", gear)
        self.assertIn("state.TreasureMode:set('Tag')", gear)
        self.assertIn("sets.TreasureHunter = {waist='Chaac Belt'}", gear)
        self.assertNotRegex(
            gear,
            r"sets\.TreasureHunter\s*=\s*\{[^}]*ammo\s*=",
        )
        self.assertIn("local function expected_equipment_name(item)", include)
        self.assertIn("return item.name", include)
        for slot in ("main", "sub", "range"):
            self.assertIn(
                f"player.equipment.{slot} ~= expected_equipment_name(",
                include,
            )
        self.assertIn("if sets.Kiting and not wasmoving and not (", utility)
        self.assertRegex(
            gear,
            r"local generic_ws\s*=\s*\{\s*ammo='Aurgelmir Orb \+1'",
        )
        self.assertRegex(
            gear,
            r"local savage\s*=\s*\{\s*ammo='Aurgelmir Orb \+1'",
        )
        self.assertRegex(
            gear,
            r"local savage_fodder\s*=\s*set_combine\(savage\s*,\s*\{",
        )
        self.assertRegex(
            gear,
            r"sets\.precast\.WS\['Savage Blade'\]\s*=\s*"
            r"melee_ws_family\(savage\s*,\s*savage_fodder\)",
        )
        self.assertRegex(
            gear,
            r"local engaged_normal\s*=\s*\{\s*ammo='Aurgelmir Orb \+1'",
        )
        self.assertRegex(
            gear,
            r"local idle_normal\s*=\s*\{\s*ammo='Staunch Tathlum \+1'",
        )
        self.assertRegex(
            gear,
            r"local last_stand\s*=\s*\{\s*ammo='Living Bullet'",
        )
        self.assertRegex(
            gear,
            r"local wildfire\s*=\s*\{\s*ammo='Living Bullet'",
        )


if __name__ == "__main__":
    unittest.main()
