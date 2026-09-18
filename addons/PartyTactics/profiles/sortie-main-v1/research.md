# Sortie main profile contract

This profile is the sole PartyTactics owner for the active Sortie route. It is
loaded once after entry and is not replaced when the party changes targets or
objectives.

- Any hostile action by a configured party member may bind the exact target
  and emits one exact-target synchronization edge. Tackleberry remains the
  preferred puller for initial threat but is never an activation gate.
- Cachaemic Skeletons and Ghouls use Evisceration into Savage Blade for Fragmentation, followed by
  Thunder from both magic-capable clients. After a confirmed Magic Burst, all
  six use physical weapon skills normally. Other Cachaemics, including the
  Bhoot, use the ordinary full-damage recipe.
- Biunes and ordinary targets use full-party physical damage with no pause.
- Abject Acuex use Flat Blade into Red Lotus Blade for Liquefaction. Physical
  attackers are stopped only for a live chain/finish attempt, and Smalls uses
  Fire IV/III for the killing blow with Aquaveil maintained by the persistent
  RDM support preset. A failed chain emits one exact-target resume edge before
  the next attempt, so nobody remains stranded at full TP.
- Skomora and Ghatjot use the ordinary physical burn. Leshonn has a dedicated
  five-WS lane: Savage Blade and Black Halo only; Kick continues melee and Box
  Step but holds automatic WS. This prevents Wind/Lightning-aligned
  Fragmentation from Evisceration into Savage Blade.
- Leshonn uses a common-denominator support policy for either random opening
  form: no persistent enemy debuffs, no automated Flash, and no Sentinel.
  Existing reviewed `magicboss` BRD and `manualsc` PLD presets provide that
  behavior without changing the frozen shared helpers. GEO bubbles and Box
  Step remain active.
- Standard entity data does not expose the visible hand aura. The runtime
  therefore never guesses the opening form. Chokehold/Tearing Gust confirm
  Wind at that action; Zap/Concussive Shock confirm Thunder. References
  disagree about the post-action state of Shrieking Gale and Undulating
  Shockwave, so those return optional form behavior to neutral. Confirmed Wind
  may request Last Resort only from a character actually on /DRK; the present
  /WHM support composition does not depend on it.
- Movement/combat support changes are adapter-local modes inside this one
  profile. Travel uses the no-debuff/no-native-tank baseline; an ordinary
  hostile action restores physical BRD and normal PLD automation before the
  shared target is released. They do not invoke PartyTactics profile loads or
  PartyCombat arm state changes.

The runtime and adapter are forbidden from loading, stopping, arming,
disarming, or reapplying PartyTactics. Deactivation clears only requests owned
by this exact adapter instance.
