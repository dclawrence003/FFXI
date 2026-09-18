# Direct Vagary: Rancibus research and automation contract

## Scope

This profile is only for **Vagary: Rancibus** in Ra'Kaznar Turris (zone
277). It is not a Brash Gate route. The battlefield contains one Rancibus,
allows one to six players, and has a 30-minute limit. There are no columns,
Brimboil adds, wave transitions, or Vagary proc requirements to automate.

Every entrant must have completed **Watery Grave** and must hold a
**prototype sigil pearl**. The pearl is consumed from every member on entry.
The direct battlefield is for the Rancibus Ravager title and Empyrean-feet
reforging unlock; it does not provide the normal Vagary loot/experience/RoE
credit.

## Evidence used

Local cache was consulted first:

- `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/content/other/rancibus.md`
- `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/categories/category-vagary.md`
- `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/misc/endgame-progression-guide.md`
- `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/zones/ra-kaznar-turris.md`

Public corroboration and mechanics:

- https://www.bg-wiki.com/ffxi/Rancibus
- https://www.bg-wiki.com/ffxi/Category:Vagary#Alternative_Battlefields
- https://www.bg-wiki.com/ffxi/Category:Plovid
- https://forum.square-enix.com/ffxi/threads/54525
- https://github.com/Windower/Resources/blob/master/resources_data/monster_abilities.lua
- https://wiki.ffo.jp/html/37456.html
- https://wiki.ffo.jp/html/34857.html

The local Windower resources currently identify the original Plovid move
block as 3372 through 3376. The runtime pins those IDs and records no phase
from a textual name.

## Relevant mechanics

Current direct-battlefield data lists level 128 and roughly 445,000 HP. A
direct-run report says its displayed HP gauge is hidden, so the controller
does not read `hpp` for encounter binding, phase changes, victory, or safety.
It binds only exact name, spawn type, uint32 ID, uint16 index, zone, current
authority, and entity validity.

All physical categories, including ranged, are 100%. Elemental multipliers
are Earth 85%; Fire/Wind/Thunder/Light 70%; Ice 50%; Water 15%; Dark 5%.
The plan therefore uses physical Evisceration, Savage Blade, Last Stand, and
ordinary ranged attacks. It deliberately excludes Leaden Salute, Water, and
Dark damage.

The dangerous move set is:

- **Cesspool (3372):** Water damage, Plague, knockback, and a strong
  boss-centered Poison aura.
- **Fetid Eddies (3373):** Water damage, Gravity, and a narrow poison field at
  the target's location.
- **Nullifying Rain (3374):** Water damage, multiple dispels, and 25% Max HP
  Down.
- **Noyade (3375):** Water damage, Silence, and a narrow poison field at the
   visible poison sphere; reports differ slightly on whether its center follows
   the target or the boss.
- **Clobbering Wave (3376):** conal Water damage and knockback.

Rancibus can Manafont repeatedly. The conservative interrupt list is the
union reported for the direct fight: Water VI, Waterga III/IV, Waterja,
Flood II, Blizzaga III/IV, Blizzaja, Freeze II, Bindga, Silencega, Dispelga,
and the low-confidence Death report. Stun is reported to work; it is treated
as a best-effort mitigation tool, never a condition that must land before
damage can continue. Manafont is detected by resolved resource name because
Windower exposes multiple monster-ability IDs for that name.

## Fixed-party strategy

- **Dolomedes:** COR/DNC or COR/NIN. Death Penalty ranged build, Chaos Roll +
  Magus's Roll, automatic ranged attacks, and Last Stand. Magus is chosen over
  Samurai for the first pearl-consuming clear because repeated Water magic is
  the main failure risk.
- **Tackleberry:** PLD/WAR. Wall-tank with the boss faced away. Crusade,
  Sentinel, and one Flash pull are attempted on a short timeline. Rampart is
  saved for Manafont rather than consumed during the opening sequence. A
  missed or unavailable Flash never blocks another lane or manual recovery.
- **Kickpuncher:** DNC/WAR. Sole close melee behind Rancibus; primary Violent
  Flourish interrupter and independent Evisceration damage. The frozen DNC helper uses
  heal-only `tankheal`; the private adapter owns pre-pull No Foot Rise, Box
  Step, the interrupt, and automatic Evisceration requests. The adapter never
  rejects Reverse Flourish or any other manual action.
- **Barneystinson, Smalls, Achoo:** BRD/WHM, RDM/WHM, GEO/WHM. This supplies
  distributed cures, Erase, Viruna, Silena, and Barwatera/Barsilencera.
  Achoo uses Indi-Refresh, Geo-Frailty, and Entrust Indi-Fend on Kick.

Initial buffs are applied while all six are clustered. For combat, place
Tackle against a wall, Kick behind the boss, and keep everyone in the safe
rear arc. Dolo and Barney should remain near the outer edge of roll/song
coverage so an automatic recovery cast can still reach the melee pair;
Smalls and Achoo can stand farther back. Move every affected character out of
a visible Noyade or Fetid Eddies poison sphere. If a sphere is under Tackle,
slide him along the wall while preserving facing.

## Automated plan

1. `//pt rancibus` loads the configuration and remains inert. Position first.
   `//pt check` can report setup observations, but it is optional and never
   authorizes combat.
2. `//pt arm` is the sole start switch. It immediately binds the exact
   Rancibus and independently requests Crusade, No Foot Rise, Barwatera,
   Barsilencera, Sentinel, and one Flash pull. There is no ACK, check,
   controller, buff, setup, or action-result prerequisite.
3. After party claim, PartyCombat controls only Tackle and Kick. Dolo receives
   one exact-ID local engage request, with no persistent facing, movement,
   retarget, or re-engage ownership, then independently alternates ranged
   attacks and Last Stand according to TP.
4. Kick's Evisceration, Tackle's Savage Blade, and Dolo's Last Stand run as
   independent TP lanes. No skillchain packet, party-HP threshold, prior
   weaponskill, or support result can hold damage.
5. PLD enmity, DNC Box Step, RDM debuffs, Geo-Frailty, and Barspell refreshes
   run on separate time-based lanes. Dangerous moves and spells schedule
   bounded Violent Flourish and Shield Bash attempts; Manafont schedules
   Rampart. A blocked or unavailable action expires without stopping another
   character.
6. The 1.1.0 adapter has no pretarget or precast filters and never consumes a
   native GearSwap tick. Every manual target change, spell, ability, ranged
   attack, weapon skill, item, and emergency action remains available.
7. `//pt disarm`, profile replacement, zone change, claim loss, victory, or
   `//pt off` clears this profile's requests and stops PartyCombat. It emits no
   audible retry loop.

## Deliberate exclusions and first-run telemetry

- No HPP threshold or loot-based victory condition.
- No Brash Gate adds, columns, waves, proc logic, or route assumptions.
- No magic burst lane on the first version; full-strength physical damage is
  safer and simpler than adding a marginal elemental action queue.
- The initial adapters 1.0.0, 1.0.1, and 1.0.2 remain frozen. Cooperative
  behavior lives only in the new 1.1.0 adapter and matching profile/runtime.
  PartyCombat 0.6.12 retains the exact-name/ID/party-claim path needed for the
  hidden gauge and adds one local engage edge for Dolo without synchronized
  targeting. No character GearSwap set or instrument-selection code is
  modified.

The first retail clear should verify exact move IDs, cast/move categories,
field radius, rear-line spacing, ranged-attack cadence, and whether native
recovery restores the stripped front-line buffs quickly enough. Any revisions
belong in a new Rancibus profile/adapter version, not in an established fight.
