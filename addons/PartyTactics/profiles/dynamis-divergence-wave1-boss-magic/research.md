# Dynamis-D Wave 1 boss research

Retrieved 2026-09-01. This is the boss half of the paired Dynamis-D Wave 1
strategy. The route half is `dynamis-divergence-wave1-route-corsair`.

## Operator-supplied baseline

Umbra's supplied plan is the strategy authority for this profile:
PLD/RDM/BRD/GEO/COR/DNC; BRD, RDM, and GEO on /WHM; COR using Death
Penalty with Tactician/Wizard en route and Samurai/Wizard at the boss; only PLD
and COR in boss range; March, Minne, and two Ballads through Clarion Call;
Shell V, Haste II, Refresh III, Phalanx II, Acumen/Malaise, broad RDM
enfeebles, and heavy healing; PLD's Crusade/Divine Emblem/one-hit/Sentinel/
Flash pull; then CDC -> Leaden Salute -> Wildfire for Darkness into Double
Darkness. The profile changes only what local capability or safety requires:
it splits route and boss into separate activation barriers, leaves the chain
manual, guards the fourth song, and provides a conditional Rudra opener.

## Sources and encounter model

- [BG Wiki: Dynamis - Divergence](https://www.bg-wiki.com/ffxi/Category%3ADynamis_-_Divergence)
  identifies the four level-132 Wave 1 mid-bosses, party/alliance proximity
  hate, the 30-minute boss extension, and the immediate Wave 1 to Wave 2
  transition. It also records a -75% resistance to Geomancy effects on
  Divergence NMs.
- [BG Wiki's endgame progression guide](https://www.bg-wiki.com/ffxi/Endgame_Progression_Guide)
  summarizes the four mid-bosses as heavily physically resistant and favorable
  to ranged/magical damage. The shared Replica kit is Seismostomp (AoE physical
  damage plus Stun), auto-regain, and a zone-specific conal status move.
- [Mu'Sha Effigy](https://www.bg-wiki.com/ffxi/Mu%27Sha_Effigy),
  [Evincing Idol](https://www.bg-wiki.com/ffxi/Evincing_Idol), and
  [Impish Golem](https://www.bg-wiki.com/ffxi/Impish_Golem) each list only 12.5%
  physical damage taken versus 100% magical damage taken. Their conal effects
  are Gravity, Curse, and Sleep respectively. The San d'Oria Replica family
  uses Numbing Glare (Paralysis). This supports two in-range actors, back-line
  spacing, status removal, Malaise, and magical weapon skills.
- Mu'Sha's page recommends tanks/DDs on the left and mages on the right at its
  spawn. Evincing Idol recommends the Windurst Waters zone line with the tank
  on the bridge and warns that new statues spawn there immediately. Impish
  Golem is at the Jeuno palace second floor and has a narrow aggro range. San
  d'Oria should likewise keep support away from the ramp used by Wave 2.
- [Chant du Cygne](https://www.bg-wiki.com/ffxi/Chant_du_Cygne) has Light /
  Distortion properties. [Leaden Salute](https://www.bg-wiki.com/ffxi/Leaden_Salute)
  has Gravitation / Transfixion. Distortion into Gravitation makes Darkness;
  [Wildfire](https://www.bg-wiki.com/ffxi/Wildfire) has Darkness / Gravitation,
  so it follows with Double Darkness. BG Wiki gives a 3-10 second skillchain
  window that shrinks with each step. [Rudra's Storm](https://www.bg-wiki.com/ffxi/Rudra%27s_Storm)
  provides Darkness / Distortion as the conditional DNC opener.
- [BG Wiki's song category](https://www.bg-wiki.com/ffxi/Category%3ASong),
  [Clarion Call](https://www.bg-wiki.com/ffxi/Clarion_Call), and
  [Blurred Harp](https://www.bg-wiki.com/ffxi/Blurred_Harp) establish two base
  songs, one additional instrument song, and one Clarion Call song. The extra
  instrument must be present for the fourth slot, and a lost extra song cannot
  be restored after Clarion expires unless its effect is still active.
- The repeated-WS resistance is documented here only as community observation:
  [FFXIAH: Dynamis Divergence boss damage mechanics](https://www.ffxiah.com/forum/topic/52621/dynamis-divergance-boss-damage-mechanics/).
  Reports show rapid damage decay from repeating one WS and recovery when
  alternating. Exact formula and reset timing remain unverified, so no runtime
  attempts to automate around it.

No local offline BG Wiki mirror was found in the workspace or Windower tree.
Installed Windower resources and GearSwap files were used as the local source.

## Local capability audit

- Dolomedes has `DualLeaden` and `DualWildfire` modes; both select Death
  Penalty, and dedicated Leaden Salute/Wildfire precast sets are present.
- Tackleberry's PLD file has a Chant du Cygne set, but its weapon modes are
  Naegling, NaeglingDPS, and None. No local Almace/Brunello evidence or proof of
  the permanent CDC unlock was found. The boss profile therefore treats CDC as
  a pre-entry check and exposes a DNC fallback rather than claiming readiness.
- Kickpuncher's DNC file has Tauret and a Rudra's Storm set, but local data does
  not prove the WS unlock. Verify it before relying on the fallback.
- Barneystinson has Blurred Harp +1 configured with one extra song and a
  100-spent-JP gate. Every local song precast/midcast path keeps instrument
  selection inside GearSwap. The additive `MagicTank` native song mode is
  March, Minne, and Ballad III; PartyTactics never equips or locks a slot.

## Encoded ownership and sequence

1. COR maintains Samurai's and Wizard's Rolls. BRD's native GearSwap scheduler
   maintains three base songs. The fourth Ballad is a guarded one-shot request:
   Clarion Call must be visibly active before it can be sent.
2. RDM maintains Shell V, Haste II, Refresh III, Phalanx II, aggressive backup
   cures, and bounded Frazzle/Dia/Distract/Slow/Paralyze/Blind/Addle. GEO owns
   Indi-Acumen, Geo-Malaise, and entrusted Refresh. BRD and GEO HealBot surfaces
   are cure/status-only; buff, debuff, assist, follow, and attack are disabled.
3. DNC uses the reusable `tankheal` preset: emergency Waltzes only, with no
   Samba, Step, Flourish, melee, or AutoWS behavior.
4. PLD uses the reusable `manualsc` healing preset with this profile's additive
   native-buff and native-tank switches set Off. This prevents a normal native
   Flash or self-buff from consuming Divine Emblem or reordering the explicit
   pull. Typed Flash and optional `/WAR` Provoke requests own hate actions.
   The controller never consumes skillchain TP with Chivalry, never turns
   AutoWS2 back on, and never applies Warcry/Aggressor/Berserk.
5. PartyCombat has only Dolo and Tackle as attackers. Kick, Smalls, and Achoo
   are target-only observers, so their controllers can act without moving,
   facing, or engaging. Barney is not a targeter. The conditional Rudra fallback
   therefore requires the operator to move Kick in, manually engage/build TP,
   fire the typed Rudra request, then disengage and move her back out.
6. The pull and every WS are explicit typed GearSwap requests. No timed runtime
   guesses at TP, recast, skillchain window, or the repeated-WS resistance.

The exact pull handoff matters: with PartyCombat still inert, use Crusade and
Divine Emblem, manually move Tackle in for one autoattack, and use Sentinel.
Then arm PartyCombat and allow its authority message to reach Tackle before the
typed Flash request. Tackle is the configured puller, so that post-arm Flash
establishes and broadcasts the boss target. A Flash completed before arming
cannot be used retroactively as a synchronization event.

## Zone notes and live validation

- Keep support outside the conal/status and Seismostomp danger area, roughly
  16-19 yalms when geometry and cure range permit. Treat that as a starting
  point, not a proven universal AoE radius.
- Jeuno takes only 85% dark-element damage while fire is 115%; expect Leaden to
  be weaker there and use Wildfire variation. Windurst has 130% ice affinity,
  making the optional Blizzard burst especially attractive.
- Confirm four songs on both PLD and COR before pulling. Confirm that Barney's
  range slot changes only through normal GearSwap logs/behavior.
- Confirm AutoWS2 remains Off on Dolo and Tackle throughout one full manual
  chain, including a low-MP PLD interval. This specifically validates the new
  `manualsc` ownership boundary.
- Disarm on the killing blow and record where Wave 2 statues actually appear in
  each zone. Geometry belongs in later zone-specific child profiles only if the
  generic positioning proves insufficient.
