#!/usr/bin/env python3
"""Inventory-backed AH gap audit for the six active FFXI job profiles.

The character-specific GearSwap overrides intentionally contain only owned gear.
This audit therefore compares each character against two reference layers:

* the live BG Wiki ``All Jobs Gear Sets/<Job>`` equipment-set templates; and
* the corresponding Selendrile/Katie ``Common/<JOB>_Common.lua`` runtime sets.

It prints JSON to stdout.  It never changes GearSwap or inventory data.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sqlite3
import subprocess
import sys
import urllib.parse
import urllib.request
from collections import defaultdict


WORKSPACE = pathlib.Path(__file__).resolve().parents[1]
GEARSWAP_DATA = pathlib.Path(r"C:\Program Files (x86)\Windower\addons\GearSwap\data")
ITEMS_LUA = pathlib.Path(r"C:\Program Files (x86)\Windower\res\items.lua")
INVENTORY_DB = pathlib.Path(r"C:\Users\DC03\AppData\Local\FFXIInventory\inventory.db")
ITEM_BASIC_SQL = pathlib.Path(
    r"C:\Users\DC03\AppData\Local\FFXIInventory\landsandboat-item-basic.sql"
)
PNPM = pathlib.Path(
    r"C:\Users\DC03\.cache\codex-runtimes\codex-primary-runtime"
    r"\dependencies\bin\fallback\pnpm.cmd"
)
NODE_BIN = pathlib.Path(
    r"C:\Users\DC03\.cache\codex-runtimes\codex-primary-runtime"
    r"\dependencies\node\bin"
)

ROSTER = {
    "Tackleberry": ("PLD", "Paladin"),
    "Dolomedes": ("COR", "Corsair"),
    "Kickpuncher": ("DNC", "Dancer"),
    "Smalls": ("RDM", "Red Mage"),
    "Achoo": ("GEO", "Geomancer"),
    "Barneystinson": ("BRD", "Bard"),
}

EQUIPMENT_FIELDS = {
    "Main",
    "Sub",
    "Range",
    "Ammo",
    "Head",
    "Neck",
    "Ear1",
    "Ear2",
    "Body",
    "Hands",
    "Ring1",
    "Ring2",
    "Back",
    "Waist",
    "Legs",
    "Feet",
}


def lua_unescape(value: str) -> str:
    """Decode the small escape subset used by Windower's generated resources."""

    return (
        value.replace(r"\"", '"')
        .replace(r"\'", "'")
        .replace(r"\\", "\\")
    )


def normalize_name(value: str) -> str:
    value = re.sub(r"<!--[\s\S]*?-->", "", value)
    value = re.sub(r"\[\[[^]|]+\|([^]]+)\]\]", r"\1", value)
    value = re.sub(r"\[\[([^]]+)\]\]", r"\1", value)
    value = re.sub(r"\s*\(Level\s+\d+(?:\s+[IVX]+)?\)\s*$", "", value, flags=re.I)
    value = value.replace("’", "'").strip()
    return re.sub(r"\s+", " ", value)


def load_items() -> tuple[dict[int, dict], dict[str, int]]:
    items: dict[int, dict] = {}
    names: dict[str, int] = {}
    row = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{(.*)\},\s*$")
    quoted = lambda key, body: re.search(
        rf'(?:^|,){key}="((?:\\.|[^"\\])*)"', body
    )
    integer = lambda key, body: re.search(rf"(?:^|,){key}=(\d+)", body)

    with ITEMS_LUA.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = row.match(line)
            if not match:
                continue
            item_id = int(match.group(1))
            body = match.group(2)
            en_match = quoted("en", body)
            if not en_match:
                continue
            en = lua_unescape(en_match.group(1))
            enl_match = quoted("enl", body)
            category_match = quoted("category", body)
            stack_match = integer("stack", body)
            items[item_id] = {
                "id": item_id,
                "name": en,
                "long_name": lua_unescape(enl_match.group(1)) if enl_match else "",
                "category": category_match.group(1) if category_match else "",
                "stack": int(stack_match.group(1)) if stack_match else 1,
            }
            for alias in (en, items[item_id]["long_name"]):
                if alias:
                    names[normalize_name(alias).casefold()] = item_id
    return items, names


def load_ah_metadata() -> dict[int, dict]:
    metadata: dict[int, dict] = {}
    pattern = re.compile(r"INSERT INTO `item_basic` VALUES \((\d+),([\s\S]*?)\);")
    sql = ITEM_BASIC_SQL.read_text(encoding="utf-8", errors="replace")
    for match in pattern.finditer(sql):
        tail = re.search(r",([^,]+),(\d+)\s*$", match.group(2))
        if tail:
            metadata[int(match.group(1))] = {
                "category": tail.group(1).strip(),
                # LandSandBoat assigns a display category to some Rare/Ex
                # equipment.  The explicit flag, not the category alone,
                # determines whether the real Auction House accepts it.
                "no_auction": "@FLAG_NOAUCTION" in match.group(2),
            }
    return metadata


def load_inventory() -> tuple[dict[str, set[int]], dict[str, dict[int, int]]]:
    owned: dict[str, set[int]] = defaultdict(set)
    counts: dict[str, dict[int, int]] = defaultdict(lambda: defaultdict(int))
    with sqlite3.connect(INVENTORY_DB) as connection:
        for character, item_id, count in connection.execute(
            "SELECT character, item_id, SUM(count) FROM inventory "
            "GROUP BY character, item_id"
        ):
            if count > 0:
                owned[character].add(int(item_id))
                counts[character][int(item_id)] += int(count)
    return owned, counts


def balanced_template(text: str, start: int) -> str:
    depth = 0
    cursor = start
    while cursor < len(text) - 1:
        token = text[cursor : cursor + 2]
        if token == "{{":
            depth += 1
            cursor += 2
            continue
        if token == "}}":
            depth -= 1
            cursor += 2
            if depth == 0:
                return text[start:cursor]
            continue
        cursor += 1
    raise ValueError(f"Unbalanced template at offset {start}")


def first_field(block: str, field: str) -> str:
    match = re.search(
        rf"^[ \t]*\|[ \t]*{re.escape(field)}[ \t]*=[ \t]*(.*?)[ \t]*$",
        block,
        flags=re.M | re.I,
    )
    return normalize_name(match.group(1)) if match else ""


def fetch_all_jobs(job_page: str) -> tuple[str, list[dict]]:
    page = f"All Jobs Gear Sets/{job_page}"
    url = "https://www.bg-wiki.com/api.php?" + urllib.parse.urlencode(
        {
            "action": "parse",
            "page": page,
            "prop": "wikitext",
            "format": "json",
            "formatversion": "2",
        }
    )
    request = urllib.request.Request(
        url, headers={"User-Agent": "Codex FFXI inventory-backed gear audit/1.0"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    text = payload["parse"]["wikitext"]
    sets: list[dict] = []
    guide_start = re.compile(r"\{\{[ \t\r\n]*Guide Equipment Set(?![ \t]+Table\b)", re.I)
    equipment_start = re.compile(r"\{\{[ \t\r\n]*Equipment Set\b", re.I)
    for guide_number, guide_match in enumerate(guide_start.finditer(text), start=1):
        guide = balanced_template(text, guide_match.start())
        set_name = first_field(guide, "Set Name") or f"Guide set {guide_number}"
        for variant_number, equipment_match in enumerate(
            equipment_start.finditer(guide), start=1
        ):
            equipment = balanced_template(guide, equipment_match.start())
            caption = first_field(equipment, "CaptionTop") or f"variant {variant_number}"
            label = f"{set_name} — {caption}"
            slots: dict[str, str] = {}
            for field in EQUIPMENT_FIELDS:
                value = first_field(equipment, field)
                if value:
                    slots[field] = value
            sets.append({"label": label, "slots": slots})
    return f"https://www.bg-wiki.com/ffxi/{urllib.parse.quote(page.replace(' ', '_'))}", sets


def reference_runtime_dump(job: str) -> list[tuple[str, str]]:
    common = GEARSWAP_DATA / "Common"
    setup_file = common / f"{job}_UserSetup_Common.lua"
    common_file = common / f"{job}_Common.lua"
    source = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in (setup_file, common_file)
    )
    conditional_names = sorted(
        {
            match.group(1)
            for match in re.finditer(
                r'''item_(?:available|owned)\s*\(\s*['\"]([^'\"]+)['\"]''',
                source,
                flags=re.I,
            )
        }
    )
    environment = os.environ.copy()
    environment["REFERENCE_JOB"] = job
    environment["GEARSWAP_OWNED"] = "|".join(conditional_names)
    environment["PATH"] = str(NODE_BIN) + os.pathsep + environment.get("PATH", "")
    command = [
        str(PNPM),
        "--package=fengari-node-cli",
        "dlx",
        "fengari",
        str(WORKSPACE / "tools" / "validate_gearswap_runtime.lua"),
        str(WORKSPACE / "tools" / "dump_reference_job_sets.lua"),
        "-",
        "-",
        "dump",
    ]
    result = subprocess.run(
        command,
        cwd=WORKSPACE,
        env=environment,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(
            f"{job} reference runtime failed ({result.returncode}):\n{result.stderr}\n{result.stdout}"
        )
    values: list[tuple[str, str]] = []
    for line in result.stdout.splitlines():
        if not line.startswith("set-item\t"):
            continue
        _, path, name = line.split("\t", 2)
        values.append((path, normalize_name(name)))
    return values


def resolve(name: str, names: dict[str, int]) -> int | None:
    normalized = normalize_name(name).casefold()
    return names.get(normalized)


def is_auctionable_equipment(item: dict, ah_metadata: dict | None) -> bool:
    return (
        item.get("category") in {"Armor", "Weapon"}
        and ah_metadata is not None
        and not ah_metadata["no_auction"]
        and ah_metadata["category"] not in {None, "@NONE", "0", "99"}
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--include-owned",
        action="store_true",
        help="Include references already owned by the mapped character.",
    )
    args = parser.parse_args()

    items, names = load_items()
    ah_metadata = load_ah_metadata()
    owned, owned_counts = load_inventory()
    output = {
        "method": {
            "inventory": str(INVENTORY_DB),
            "bags": "all FindAll-exported bags, including storage slips",
            "all_jobs_fetched_live": True,
            "template_conditionals": "highest item_available/item_owned branch",
        },
        "characters": {},
        "unresolved": {},
    }

    for character, (job, job_page) in ROSTER.items():
        page_url, all_jobs_sets = fetch_all_jobs(job_page)
        all_jobs_usage: dict[int, set[str]] = defaultdict(set)
        lua_usage: dict[int, set[str]] = defaultdict(set)
        all_jobs_quantities: dict[int, dict[str, int]] = defaultdict(
            lambda: defaultdict(int)
        )
        lua_quantities: dict[int, dict[str, int]] = defaultdict(lambda: defaultdict(int))
        unresolved = {"all_jobs": set(), "lua": set()}

        for equipment_set in all_jobs_sets:
            for name in equipment_set["slots"].values():
                item_id = resolve(name, names)
                if item_id is None:
                    unresolved["all_jobs"].add(name)
                else:
                    all_jobs_usage[item_id].add(equipment_set["label"])
                    all_jobs_quantities[item_id][equipment_set["label"]] += 1

        runtime_items = reference_runtime_dump(job)
        for path, name in runtime_items:
            item_id = resolve(name, names)
            if item_id is None:
                unresolved["lua"].add(name)
            else:
                set_path = path.rsplit(".", 1)[0]
                lua_usage[item_id].add(set_path)
                lua_quantities[item_id][set_path] += 1

        candidate_ids = set(all_jobs_usage) | set(lua_usage)
        candidates = []
        for item_id in candidate_ids:
            item = items[item_id]
            if not is_auctionable_equipment(item, ah_metadata.get(item_id)):
                continue
            count = owned_counts.get(character, {}).get(item_id, 0)
            required_copies = max(
                [1]
                + list(all_jobs_quantities.get(item_id, {}).values())
                + list(lua_quantities.get(item_id, {}).values())
            )
            missing_copies = max(0, required_copies - count)
            if not missing_copies and not args.include_owned:
                continue
            candidates.append(
                {
                    "id": item_id,
                    "name": item["name"],
                    "owned": count,
                    "required_copies": required_copies,
                    "missing_copies": missing_copies,
                    "ah_category": ah_metadata[item_id]["category"],
                    "stack": item["stack"],
                    "all_jobs_count": len(all_jobs_usage.get(item_id, ())),
                    "all_jobs_sets": sorted(all_jobs_usage.get(item_id, ())),
                    "lua_count": len(lua_usage.get(item_id, ())),
                    "lua_sets": sorted(lua_usage.get(item_id, ())),
                    "impact_count": len(all_jobs_usage.get(item_id, ()))
                    + len(lua_usage.get(item_id, ())),
                }
            )
        candidates.sort(
            key=lambda row: (
                -row["all_jobs_count"],
                -row["lua_count"],
                row["name"].casefold(),
            )
        )
        output["characters"][character] = {
            "job": job,
            "all_jobs_url": page_url,
            "all_jobs_variant_count": len(all_jobs_sets),
            "reference_lua_path_count": len({path for path, _ in runtime_items}),
            "missing_auctionable": candidates,
        }
        output["unresolved"][character] = {
            source: sorted(values) for source, values in unresolved.items()
        }

    json.dump(output, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
