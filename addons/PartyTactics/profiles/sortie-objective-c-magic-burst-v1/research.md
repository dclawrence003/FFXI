# Sortie C automatic Magic Burst objective profile

## Scope and cornerstone route context

This profile is the reusable combat transaction for Shard C and Metal C in the
first two-boss training route. Umbra's workbook remains the cornerstone for the
party's broader Sortie job assignments and boss strategy:

- `C:\Users\DC03\Downloads\Sortie Melee Checklist.xlsx`
- `Sortie - Melee Comp!A8:H8`: Skomora assignments
- `Jobs and Reqs!A1:D7`: advanced equipment assumptions

This objective is deliberately isolated from the Skomora boss profile. A later
route controller can load and arm it at each Cachaemic pack without coupling
the chest condition to boss movement or boss mechanics.

## Mechanics checked 2026-09-12

- Local BG Wiki mirror:
  `C:\Users\DC03\Documents\Tesseract\FFXI\reference\bg-wiki\categories\category-sortie.md`
- Current Sortie category:
  https://www.bg-wiki.com/ffxi/Category:Sortie
- Current Japanese FFXI Wiki Sortie table:
  https://wikiwiki.jp/ffxi/%E3%82%BD%E3%83%BC%E3%83%86%E3%82%A3
- Installed Windower action messages:
  `C:\Program Files (x86)\Windower\res\action_messages.lua`
- Installed Windower weapon skills and spells:
  `C:\Program Files (x86)\Windower\res\weapon_skills.lua` and
  `C:\Program Files (x86)\Windower\res\spells.lua`

Shard C is awarded after Magic Bursting three normal Cachaemic foes before
they die; three additional qualifying foes award Metal C. The normal Sector C
names are Cachaemic Skeleton, Cachaemic Ghoul, Cachaemic Corse, and Cachaemic
Ghost. Cachaemic Bhoot is a separate NM and is explicitly rejected.

Evisceration (resource ID 25) has Gravitation/Transfixion properties and Savage
Blade (resource ID 42) has Fragmentation/Scission. In the selected order,
Evisceration followed by Savage Blade can produce Fragmentation. Thunder
(spell ID 164) bursts Fragmentation. The runtime recognizes Fragmentation only
from action-message ID 291 with positive additional-effect damage. It recognizes
actual spell Magic Burst damage only from message IDs 252 or 265 with positive
damage.

## Executable party boundary

The profile uses only modes already established for the six-character party:
Dolo `DualSavage`, Kick `Tauret`, and Naegling modes for Tackle and Barney.
Tactician's Roll helps bank TP without consuming target HP, Samurai Roll raises
TP efficiency, and MagicTank songs plus Indi-Refresh conserve recovery MP.
Geo-Haste helps the two pre-credit attackers without amplifying their WS damage
the way Frailty would.

AutoWS2 and native automatic WS are off for every member. Before credit, broad
PartyCombat synchronization contains only Dolo and Kick. After an observed
Magic Burst, the runtime directs Tackle and Barney to the already-authorized
exact target and independently requests finishers from all four attackers.

## Nonblocking control contract

The live route loads and arms the profile once. Each target requires only that
Dolo select one exact normal Cachaemic. The runtime directs Tackle first, then
releases Dolo and Kick on his hostile action or party claim; a two-second
fallback prevents lost claim evidence from blocking the timer. `//pt arm` and
Ctrl-P use the same runtime-owned pull path. The runtime binds no arbitrary
nearby mob and never scans forward to choose one. Submitted commands are not evidence; only
successful, correct-actor, correct-target packets advance the automatic chain.

Action requests expire in bounded windows. A failed opener, closer, or burst
returns to chain acquisition. Manual Evisceration, manual Savage Blade with a
real Fragmentation effect, and any real party spell Magic Burst can advance or
complete the same transaction. GearSwap pretarget and precast hooks explicitly
return without filtering. Low target HP generates a warning only; it never
forces a stop or rejects manual play.

Target end, bounded post-claim loss, disarm, profile replacement, or zone exit
cancels only queued profile requests and releases exact-target authority. The
profile stays loaded and armed for the operator's next exact target; Alt-P
remains authoritative because no background poll re-arms it. Chest appearance and ExpeditionGuide's
all-six temporary-item evidence—not an internal kill count—remain authoritative.
