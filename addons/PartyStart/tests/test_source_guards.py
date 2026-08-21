from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADDON = (ROOT / "PartyStart.lua").read_text(encoding="utf-8")
RDM = (ROOT / "gearswap" / "PartyStart_RDM.lua").read_text(encoding="utf-8")
BRD = (ROOT / "gearswap" / "PartyStart_BRD.lua").read_text(encoding="utf-8")
PLD = (ROOT / "gearswap" / "PartyStart_PLD.lua").read_text(encoding="utf-8")
DNC = (ROOT / "gearswap" / "PartyStart_DNC.lua").read_text(encoding="utf-8")
GEO = (ROOT / "gearswap" / "PartyStart_GEO.lua").read_text(encoding="utf-8")
COMPOSITIONS = (ROOT / "data" / "compositions.lua").read_text(
    encoding="utf-8"
)
LOCUS_RELOAD = (ROOT / "scripts" / "reload_locusbats_safe.txt").read_text(
    encoding="utf-8"
)
LOCUS_ACTIVATE = (
    ROOT / "scripts" / "activate_locusbats_safe.txt"
).read_text(encoding="utf-8")


class PartyStartSourceGuards(unittest.TestCase):
    def test_partystart_does_not_police_combat(self):
        self.assertNotIn("PARTYCOMBAT1", ADDON)
        self.assertNotIn("ffo ", ADDON.lower())
        maintenance = ADDON.split(
            "windower.register_event('prerender'", 1
        )[1]
        self.assertNotIn("input /attack off", maintenance)
        self.assertNotIn("combat_authorized", ADDON)
        self.assertIn("schedule_zone_rearm(8)", ADDON)
        self.assertIn("__zonerearm", ADDON)
        self.assertNotIn("pc on", ADDON.lower())
        self.assertNotIn("pc force", ADDON.lower())
        self.assertIn("pc policy %s %s %s %s %s %s %s %s", ADDON)

    def test_physical_profile_is_the_lean_rdm_profile(self):
        physical = RDM.split("accuracy =", 1)[0]
        self.assertNotIn("Frazzle", physical)
        self.assertIn("debuff_mp_floor = 45", physical)
        self.assertIn("debuff_min_target_hpp = 50", physical)

    def test_rdm_support_precedes_offensive_magic(self):
        action = RDM.split("local function pstart_rdm_action()", 1)[1]
        party = action.index("pstart_rdm_cast_party_buffs()")
        priority = action.index(
            "profile.priority_debuff and pstart_rdm_cast_debuff(profile)"
        )
        fallback = action.rindex("return pstart_rdm_cast_debuff(profile)")
        self.assertLess(priority, party)
        self.assertLess(party, fallback)
        master = RDM.split("master = {", 1)[1].split("physical = {", 1)[0]
        self.assertIn("party_shell = false", master)
        self.assertIn("routine_buff_mp_floor = 35", master)
        self.assertIn("tank_buff_mp_floor = 20", master)
        self.assertIn("{'Dia III', 'Dia II', 'Dia'}", RDM)
        self.assertIn("PSTART_RDM_LOSE_EFFECT_MESSAGES", RDM)
        self.assertIn("pstart_rdm_register_remote_buff_loss", RDM)
        self.assertIn("remote_loss_count", RDM)
        self.assertIn("pstart_rdm_cast_reactive_repair", RDM)
        self.assertIn("pstart_rdm_owns_buff", RDM)
        self.assertIn("pending.repair_key and not spell.interrupted", RDM)

    def test_debuffs_respect_mp_and_target_hp_reserves(self):
        self.assertIn(
            "player.mpp < (profile.debuff_mp_floor or 0)", RDM
        )
        self.assertIn(
            "target.hpp < (profile.debuff_min_target_hpp or 0)", RDM
        )

    def test_physical_profile_configures_all_follower_weapon_skills(self):
        expected = {
            "Tackleberry": ("Naegling", "Savage Blade", "1000"),
            "Kickpuncher": ("Tauret", "Evisceration", "1000"),
            "Barneystinson": ("Naegling", "Savage Blade", "1000"),
            "Smalls": ("Maxentius", "Black Halo", "1000"),
            "Achoo": ("Maxentius", "Black Halo", "1000"),
        }
        progression_offense = COMPOSITIONS.split(
            "progression = {", 1
        )[1].split("legacy = {", 1)[0].split("offense = {", 1)[1]
        for name, values in expected.items():
            start = progression_offense.index(f"                {name} = {{")
            block = progression_offense[start:].split(
                "\n                },", 1
            )[0]
            for value in values:
                self.assertIn(value, block)

    def test_partystart_only_stops_autows2_it_owns(self):
        self.assertIn("local autows2_owned = false", ADDON)
        owned_stop = ADDON.split("local function stop_owned_autows2()", 1)[1]
        owned_stop = owned_stop.split("\nend", 1)[0]
        self.assertIn("if autows2_owned then", owned_stop)
        self.assertIn("issue('aws2 off')", owned_stop)
        self.assertIn("Dolomedes = {", COMPOSITIONS)
        self.assertIn("COR = {weapon_mode='DualSavage'", COMPOSITIONS)

    def test_compositions_cover_all_six_characters_and_flexible_dolo_jobs(self):
        for name in (
            "Dolomedes", "Tackleberry", "Kickpuncher", "Barneystinson",
            "Smalls", "Achoo",
        ):
            self.assertIn(f"{name} = {{main=", COMPOSITIONS)
        self.assertIn("progression = {", COMPOSITIONS)
        self.assertIn("legacy = {", COMPOSITIONS)
        self.assertIn("['progression-blu'] = {", COMPOSITIONS)
        self.assertIn("puller = 'Tackleberry'", COMPOSITIONS)
        self.assertIn("puller = 'Dolomedes'", COMPOSITIONS)
        self.assertIn("weapon_mode='TizThib'", COMPOSITIONS)
        self.assertIn("ws='Expiacion'", COMPOSITIONS)

    def test_activation_is_atomic_and_preview_is_inert(self):
        finalize = ADDON.split("local function finalize_session", 1)[1]
        finalize = finalize.split("local function begin", 1)[0]
        self.assertLess(finalize.index("validate_session(session)"),
                        finalize.index("apply_profile(session)"))
        self.assertIn("if #errors > 0 then", finalize)
        self.assertIn("if session.preview then", finalize)
        self.assertIn("no automation was changed", finalize)
        self.assertIn("DISCOVERY_TIMEOUT = 8", ADDON)
        self.assertIn("session.decision = decision", finalize)
        self.assertIn("announce_decision(session)", finalize)
        self.assertIn("elseif kind == 'decision' then", ADDON)
        self.assertIn("session.roster = decode_roster(session, encoded)", ADDON)
        self.assertIn("if decision == 'commit' and #errors == 0", ADDON)
        self.assertIn("session.next_report_at = now + 0.5", ADDON)

    def test_activation_handshake_retries_without_reapplying_profiles(self):
        prerender = ADDON.split("windower.register_event('prerender'", 1)[1]
        self.assertIn("START_RETRY_INTERVAL = 0.75", ADDON)
        self.assertIn("DECISION_RETRY_INTERVAL = 0.75", ADDON)
        self.assertIn("DECISION_RETRY_WINDOW = 5", ADDON)
        self.assertIn("local function announce_start(session)", ADDON)
        self.assertIn("local function announce_decision(session)", ADDON)
        self.assertIn("and not roster_complete(session)", prerender)
        self.assertIn("announce_start(session)", prerender)
        self.assertIn("and session.decision == 'commit'", prerender)
        self.assertIn("announce_decision(session)", prerender)
        self.assertIn("if not session or session.applied", ADDON)

    def test_job_change_suspends_then_revalidates(self):
        self.assertIn("windower.register_event('job change'", ADDON)
        self.assertIn("job_revalidate_at = os.clock() + 10", ADDON)
        self.assertIn("stop_local{silent=true, preserve_revalidation=true}", ADDON)
        self.assertIn(
            "begin(pending.composition, pending.profile, false, true)", ADDON
        )

    def test_brd_has_one_party_song_owner(self):
        self.assertIn("pstart_brd_original_check_song()", BRD)
        self.assertIn("state.SongMode:set", BRD)
        self.assertNotIn("pstart_brd_cast_party_song", BRD)
        self.assertNotIn("pstart_brd_force_instrument", BRD)
        self.assertNotIn("pstart_brd_ensure_physical_weapon", BRD)

    def test_brd_heartbeat_does_not_duplicate_native_song_scheduler(self):
        tick_branch = BRD.split("if requested == 'tick' then", 1)[1].split(
            "elseif requested == 'sleep' then", 1
        )[0]
        self.assertIn("pstart_brd_maintenance(profile)", tick_branch)
        self.assertNotRegex(tick_branch, r"(?m)^\s*check_song\(\)\s*$")
        self.assertIn(
            "elseif not requested or requested == 'status' then", BRD
        )
        self.assertIn("PartyStart BRD songs: mode", BRD)

    def test_master_has_explicit_single_healing_owners(self):
        master_rdm = ADDON.split(
            "local function apply_rdm", 1
        )[1].split("local function apply_brd", 1)[0]
        master_pld = ADDON.split(
            "local function apply_pld", 1
        )[1].split("local function apply_dnc", 1)[0]
        self.assertIn("hb disable cure", master_rdm)
        self.assertIn("gs c pstartpld %s %s", master_pld)
        self.assertIn("PSTART_PLD_ROUTINE_HPP = 82", PLD)
        self.assertIn("PSTART_PLD_EMERGENCY_HPP = 55", PLD)
        self.assertIn("PSTART_PLD_CONSERVE_ROUTINE_HPP = 72", PLD)
        self.assertIn("PSTART_PLD_LOW_MP_ROUTINE_HPP = 65", PLD)
        self.assertIn("PSTART_PLD_CLUSTER_COUNT = 3", PLD)
        self.assertIn("pstart_pld_action()", PLD)

    def test_pld_healing_precedes_native_tank_tick(self):
        hook = PLD.split(
            "local pstart_pld_original_user_job_tick", 1
        )[1]
        heal = hook.index("pstart_pld_action()")
        native = hook.index("pstart_pld_original_user_job_tick()")
        self.assertLess(heal, native)
        self.assertIn("PSTART_PLD_CHIVALRY_TP = 1000", PLD)
        self.assertIn("PSTART_PLD_CHIVALRY_RESERVE_HPP = 45", PLD)
        self.assertIn("PSTART_PLD_CHIVALRY_USE_HPP = 45", PLD)
        self.assertIn("reserving 1000 TP for Chivalry", PLD)
        self.assertIn("gs c unset AutoTankFull", ADDON)

    def test_pld_war_defender_is_emergency_only(self):
        self.assertIn("PSTART_PLD_DEFENDER_TRIGGER_HPP = 50", PLD)
        self.assertIn("PSTART_PLD_DEFENDER_RELEASE_HPP = 70", PLD)
        command_hook = PLD.split(
            "function user_job_self_command(commandArgs, eventArgs)", 1
        )[1]
        self.assertIn("command == 'subjobenmity'", command_hook)
        self.assertIn("eventArgs.handled = true", command_hook)
        policy = PLD.split(
            "local function pstart_pld_war_subjob_enmity()", 1
        )[1].split("local function pstart_pld_tank_cooldown", 1)[0]
        emergency = policy.index(
            "hpp < PSTART_PLD_DEFENDER_TRIGGER_HPP"
        )
        defender = policy.index("PSTART_PLD_DEFENDER_ACTION_ID")
        warcry = policy.index("PSTART_PLD_WARCRY_ACTION_ID")
        self.assertLess(emergency, defender)
        self.assertLess(defender, warcry)
        self.assertIn("pstart_pld_cancel_offense_for_defender()", policy)
        self.assertGreaterEqual(
            policy.count("pstart_pld_cancel_offense_for_defender()"), 2
        )
        self.assertIn("buffactive['Defender']", policy)
        self.assertIn("hpp >= PSTART_PLD_DEFENDER_RELEASE_HPP", policy)
        self.assertIn("cancel defender", policy)

    def test_pld_cooldowns_are_owned_and_conditioned(self):
        self.assertIn("PSTART_PLD_SENTINEL_ACTION_ID = 48", PLD)
        self.assertIn("PSTART_PLD_RAMPART_ACTION_ID = 92", PLD)
        self.assertIn("PSTART_PLD_PALISADE_ACTION_ID = 278", PLD)
        cooldown = PLD.split(
            "local function pstart_pld_tank_cooldown", 1
        )[1].split("local function pstart_pld_member_in_range", 1)[0]
        self.assertIn("player.status ~= 'Engaged'", cooldown)
        self.assertIn("pstart_pld.flash_target_id == target.id", cooldown)
        self.assertIn("cluster_injured >= PSTART_PLD_RAMPART_CLUSTER_COUNT", cooldown)
        self.assertIn("pstart_pld.pressure_until", cooldown)
        self.assertIn("buffactive['Sentinel']", cooldown)

    def test_pld_mp_policy_throttles_without_delaying_emergencies(self):
        self.assertIn("PSTART_PLD_CURE_INTERVAL_HIGH = 3", PLD)
        self.assertIn("PSTART_PLD_CURE_INTERVAL_MID = 5", PLD)
        self.assertIn("PSTART_PLD_CURE_INTERVAL_LOW = 8", PLD)
        action = PLD.split("local function pstart_pld_action()", 1)[1]
        action = action.split("local function pstart_pld_status()", 1)[0]
        emergency = action.index("local emergency = lowest.hpp < policy.emergency_hpp")
        reserve = action.index(
            "player.mpp < policy.routine_mp_floor and not emergency"
        )
        self.assertLess(emergency, reserve)
        self.assertIn(
            "player.mpp < policy.chivalry_reserve_hpp",
            action,
        )
        self.assertIn("TP reservation must not suppress a needed cure", action)
        self.assertNotIn("if pstart_pld.autows_paused then return false end", action)
        ready_spell = PLD.split("local function pstart_pld_ready_spell", 1)[1]
        ready_spell = ready_spell.split("\nend", 1)[0]
        self.assertIn("pstart_pld_ready(spell)", ready_spell)

    def test_dnc_guards_merit_actions_and_preserves_waltzes(self):
        apply_dnc = ADDON.split(
            "local function apply_dnc", 1
        )[1].split("local function apply_cor", 1)[0]
        self.assertIn("gs c set DanceStance None", apply_dnc)
        self.assertNotIn("Saber Dance", apply_dnc)
        self.assertIn("pstart_dnc_known(action_id)", DNC)
        self.assertIn("Haste Samba", DNC)
        self.assertIn("Box Step", DNC)
        self.assertIn("PSTART_DNC_EMERGENCY_HPP = 42", DNC)
        self.assertNotIn("pstart_dnc_use(PSTART_DNC_ACTIONS.box_step, tostring(target.id)", DNC)
        self.assertIn("pstart_dnc_use(PSTART_DNC_ACTIONS.box_step, '<t>'", DNC)
        self.assertIn("no_foot_rise = 239", DNC)
        self.assertIn("pstart_dnc_has_any_finishing_move()", DNC)
        self.assertIn("PSTART_DNC_NO_FOOT_RISE_HEALTHY_HPP = 70", DNC)
        action = DNC.split("local function pstart_dnc_action()", 1)[1]
        self.assertLess(action.index("pstart_dnc_emergency_waltz(lowest)"),
                        action.index("pstart_dnc_no_foot_rise(lowest)"))

    def test_hostile_actions_use_synchronized_local_target(self):
        for source in (RDM, BRD, DNC):
            self.assertIn("get_mob_by_target('t')", source)
        self.assertIn("windower.chat.input('/ma \"'..spell.en..'\" <t>')", RDM)
        self.assertIn("windower.chat.input('/ma \"'..spell.en..'\" <t>')", BRD)

    def test_stop_cannot_reenable_autows2(self):
        dnc_off = DNC.split("elseif requested == 'off' then", 1)[1]
        dnc_off = dnc_off.split("elseif requested", 1)[0]
        self.assertNotIn("aws2 on", dnc_off)
        pld_off = PLD.split("elseif requested == 'off' then", 1)[1]
        pld_off = pld_off.split("elseif PSTART_PLD_PROFILES", 1)[0]
        self.assertNotIn("aws2 on", pld_off)

    def test_master_uses_stackable_physical_debuffs(self):
        master = ADDON.split("master = {", 1)[1].split("physical = {", 1)[0]
        self.assertIn("Carnage Elegy", master)
        self.assertIn("Dia III", master)
        self.assertIn("geo = {indi='Fury', geo='Frailty'", master)
        self.assertIn("Mage's Ballad III", master)
        self.assertIn("entrust='Refresh'", master)

    def test_rdm_refreshes_tanks_before_other_mp_jobs(self):
        self.assertIn("pstart_rdm_refresh_priority", RDM)
        apply_rdm = ADDON.split("local function apply_rdm", 1)[1]
        apply_rdm = apply_rdm.split("local function apply_brd", 1)[0]
        self.assertIn("job == 'PLD' or job == 'RUN'", apply_rdm)
        self.assertLess(
            apply_rdm.index("ipairs(refresh_tanks)"),
            apply_rdm.index("ipairs(refresh_others)"),
        )
        self.assertIn("table.insert(refresh_targets, 1, name)", apply_rdm)

    def test_sustained_rdm_refresh_scope_is_conservative(self):
        apply_rdm = ADDON.split("local function apply_rdm", 1)[1]
        apply_rdm = apply_rdm.split("local function apply_brd", 1)[0]
        self.assertIn("local sustained = profile.sustained == true", apply_rdm)
        self.assertIn("local sustained_refresh = sustained", apply_rdm)
        self.assertIn("name:lower() == player.name:lower()", apply_rdm)
        self.assertIn("or job == 'PLD' or job == 'RUN'", apply_rdm)
        self.assertIn("local refresh_wanted", apply_rdm)
        self.assertIn("or not sustained or sustained_refresh", apply_rdm)
        self.assertIn("local function haste_rank", apply_rdm)
        self.assertIn("{'Gain-MND', 'Gain-STR'}", RDM)
        self.assertIn("local function pstart_rdm_can_spend", RDM)
        self.assertIn("local post_cast_mpp", RDM)
        self.assertIn("return post_cast_mpp >= mp_floor", RDM)
        self.assertIn("Phalanx=225", RDM)
        self.assertIn("'Phalanx', 225, tank_floor", RDM)

    def test_geo_lean_mode_preserves_colure_automation(self):
        self.assertIn("buff_spell_lists.Auto = {}", GEO)
        self.assertNotIn("AutoBuffMode:set('Off')", GEO)
        self.assertIn("gs c pstartgeo lean", ADDON)

    def test_geo_is_inert_until_partystart_activates_it(self):
        self.assertIn("wait 2; gs c pstartgeo bootidle", GEO)
        boot = GEO.split("requested == 'bootidle'", 1)[1]
        boot = boot.split("elseif requested", 1)[0]
        self.assertIn("if not pstart_geo_active then", boot)
        self.assertIn("pstart_geo_set_autobuff('Off')", GEO)
        stop = ADDON.split("local function stop_local(options)", 1)[1]
        stop = stop.split("\nend", 1)[0]
        self.assertIn("gs c pstartgeo idle", stop)

    def test_ambuscade_profiles_limit_engagement_but_share_targets(self):
        self.assertGreaterEqual(
            ADDON.count(
                "'Dolomedes', 'Tackleberry', 'Kickpuncher', 'Smalls', 'Achoo',"
            ),
            2,
        )
        self.assertGreaterEqual(ADDON.count("target_all = true"), 2)
        self.assertIn("profile_targeters(profile, session.names, attackers)", ADDON)
        self.assertIn("pc policy %s %s %s %s %s %s %s %s", ADDON)
        self.assertIn("stop_owned_autows2()", ADDON)

    def test_v1_splits_urchins_to_two_attackers_only(self):
        v1 = ADDON.split("['ambuscade-v1'] = {", 1)[1].split(
            "['ambuscade-v2'] = {", 1
        )[0]
        self.assertIn("priority_target = 'Bozzetto Urchin'", v1)
        self.assertIn(
            "priority_attackers = {'Dolomedes', 'Kickpuncher'}", v1
        )
        self.assertIn("profile.priority_target:gsub(' ', '_')", ADDON)
        self.assertIn("profile.priority_attackers or {}", ADDON)
        self.assertIn(
            "free_look_observers = {'Barneystinson'}", v1
        )
        self.assertIn("profile.free_look_observers or {}", ADDON)
        self.assertIn(
            "free-look support; no forced target/AutoWS2", ADDON
        )

    def test_v1_uses_priority_silence_and_reserved_pld_cooldowns(self):
        self.assertIn("target_names={'Bozzetto Breadwinner'}", RDM)
        self.assertIn("abilities={'Stymie', 'Saboteur'}", RDM)
        self.assertIn("{spells={'Silence'}, duration=45", RDM)
        self.assertIn("priority_debuff = true", RDM)
        self.assertIn("PSTART_PLD_V1_HUNDRED_FISTS_HPP = 52", PLD)
        self.assertIn("Sentinel reserved for Breadwinner Hundred Fists", PLD)
        self.assertIn("Rampart follow-up during Breadwinner Hundred Fists", PLD)

    def test_brd_encounter_bars_and_exact_boss_debuffs(self):
        v1 = BRD.split("    ['ambuscade-v1'] = {", 1)[1].split(
            "    ['ambuscade-v2'] = {", 1
        )[0]
        self.assertIn("default_bar = {spell='Barstonra', buff='Barstone'}", v1)
        self.assertIn("{spell='Barsilencera', buff='Barsilence'}", BRD)
        self.assertIn("{spell='Barsleepra', buff='Barsleep'}", BRD)
        self.assertIn("warble_reactions = true", v1)
        self.assertIn("auto_urchin_sleep = true", v1)
        self.assertIn("debuff_target_names = {'Bozzetto Breadwinner'}", BRD)
        self.assertIn("debuff_target_names = {'Popular Penelope'}", BRD)
        self.assertIn("self_heal_hpp = 40", BRD)
        self.assertIn("startup_jas = {'Nightingale', 'Troubadour'}", BRD)
        self.assertIn("mechanic_duty = true", BRD)
        self.assertIn("local function pstart_brd_cast_self_heal", BRD)
        self.assertIn("emergency %s at %d%% HP", BRD)

    def test_brd_reacts_to_each_warble_before_routine_maintenance(self):
        expected = {
            "Fire Meeble Warble": ("Barfira", "Barfire"),
            "Blizzard Meeble Warble": ("Barblizzara", "Barblizzard"),
            "Aero Meeble Warble": ("Baraera", "Baraero"),
            "Stone Meeble Warble": ("Barstonra", "Barstone"),
            "Thunder Meeble Warble": ("Barthundra", "Barthunder"),
            "Water Meeble Warble": ("Barwatera", "Barwater"),
        }
        for ability, (spell, buff) in expected.items():
            self.assertIn(
                f"['{ability}'] = {{spell='{spell}', buff='{buff}'}}", BRD
            )
        self.assertIn("action.category == 7", BRD)
        self.assertIn("action.category == 6 or action.category == 11", BRD)
        self.assertIn(
            "windower.raw_register_event('action', pstart_brd_handle_warble)", BRD
        )
        self.assertIn("local function relay_v1_brd_mechanic", ADDON)
        self.assertIn("gs c pstartbrd %s %d", ADDON)
        self.assertIn("requested == 'warble' or requested == 'warblecomplete'", BRD)
        self.assertIn("pstart_brd_v1_mechanic_duty_active()", BRD)
        self.assertIn("PSTART_BRD_V1_SONG_WINDOW = 6", BRD)
        self.assertIn("pstart_brd.v1_song_window_available = false", BRD)
        maintenance = BRD.split("local function pstart_brd_maintenance", 1)[1]
        maintenance = maintenance.split("\nend", 1)[0]
        self.assertLess(
            maintenance.index("pstart_brd_cast_warble_bar"),
            maintenance.index("pstart_brd_cast_self_heal"),
        )

    def test_brd_auto_sleeps_visible_urchins_once_per_warble(self):
        self.assertIn("PSTART_BRD_URCHIN_SLEEP_WINDOW = 15", BRD)
        self.assertIn("PSTART_BRD_HORDE_MAX_RADIUS = 8", BRD)
        self.assertIn("PSTART_BRD_URCHIN_SLEEP_CHOICES", BRD)
        choices = BRD.split("local PSTART_BRD_URCHIN_SLEEP_CHOICES", 1)[1]
        choices = choices.split("}", 1)[0]
        self.assertIn("'Horde Lullaby II', 'Horde Lullaby'", choices)
        self.assertNotIn("Foe Lullaby", choices)
        self.assertIn("windower.ffxi.get_mob_array()", BRD)
        self.assertIn("mob.name == 'Bozzetto Urchin'", BRD)
        self.assertIn("closest_distance > PSTART_BRD_HORDE_MAX_RADIUS", BRD)
        self.assertIn("pstart_brd_set_observer_target(urchin)", BRD)
        self.assertIn("pstart_brd_restore_sleep_target(pending)", BRD)
        self.assertIn("kind = 'urchin_sleep'", BRD)

    def test_v1_has_one_aoe_barspell_owner(self):
        aoe_barspell = re.compile(
            r"['\"]Bar(?:fira|blizzara|aera|stonra|thundra|watera|silencera)['\"]"
        )
        self.assertRegex(BRD, aoe_barspell)
        for controller in (RDM, PLD, DNC, GEO):
            self.assertNotRegex(controller, aoe_barspell)

        apply_rdm = ADDON.split("local function apply_rdm", 1)[1].split(
            "local function apply_brd", 1
        )[0]
        apply_brd = ADDON.split("local function apply_brd", 1)[1].split(
            "local function apply_geo", 1
        )[0]
        self.assertIn("hb disable buff", apply_rdm)
        self.assertIn("hb off", apply_brd)

    def test_v1_requires_support_subjobs_and_maintains_reraise(self):
        v1 = ADDON.split("['ambuscade-v1'] = {", 1)[1].split(
            "['ambuscade-v2'] = {", 1
        )[0]
        self.assertIn("reraise = true", v1)
        self.assertIn("required_sub_jobs", v1)
        for name in ("Barneystinson", "Smalls", "Achoo"):
            self.assertIn(f"{name} = {{", v1)
        self.assertGreaterEqual(v1.count("jobs={'WHM'}"), 3)
        self.assertIn("profile.required_sub_jobs", ADDON)
        self.assertIn("pstart_rdm_cast_reraise(profile)", RDM)
        self.assertIn("{spell='Reraise', buff='Reraise'}", BRD)
        self.assertIn("requested == 'leanrr'", GEO)
        self.assertIn("gs c pstartgeo leanrr", ADDON)
        self.assertIn("NO RERAISE", ADDON)

    def test_v1_housemaker_alerts_before_earthshaker(self):
        self.assertIn("HOUSEMAKER_ACTIVATION_DISTANCE", ADDON)
        self.assertIn("v1_poll_housemaker(now)", ADDON)
        self.assertIn("get_mob_array()", ADDON)
        self.assertIn("HOUSEMAKER MOVING: BARNEY SEPARATE NOW", ADDON)
        self.assertIn("housemaker_alert(message, false)", ADDON)
        self.assertIn("windower.play_sound", ADDON)
        self.assertIn("HOUSEMAKER_REARM_DISTANCE", ADDON)
        self.assertIn("HOUSEMAKER RETURNED: BARNEY RETURN TO GROUP NOW", ADDON)
        self.assertIn("BARNEY TAKES 1,000 EVEN WHEN ISOLATED", ADDON)
        self.assertIn("DRILL CLAW: FRONTAL CONE DAMAGE", ADDON)

    def test_apex_bats_profile_is_sustained_and_status_aware(self):
        addon = ADDON.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        rdm = RDM.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        brd = BRD.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        self.assertIn("_addon.version = '1.4.7'", ADDON)
        self.assertIn("label = 'Sustained Apex Bats: Dho Gates'", addon)
        self.assertIn("sustained = true", addon)
        self.assertIn("Mage's Ballad III", addon)
        self.assertIn("Blade Madrigal", addon)
        self.assertIn("geo = {indi='Fury', geo='Frailty'", addon)
        self.assertIn("bats = 'apexbats'", ADDON)
        self.assertIn("apexefts = 'master'", ADDON)
        self.assertIn("sustained = true", rdm)
        self.assertIn("party_shell = false", rdm)
        self.assertIn("debuff_mp_floor = 55", rdm)
        self.assertIn("{spell='Barwatera', buff='Barwater'}", brd)
        self.assertIn("apexbats=true", PLD)
        self.assertIn("PSTART_PLD_SUSTAINED_PROFILES", PLD)
        self.assertIn(
            "'master','apexbats','locusbats','apexcrabs','limbus','physical'",
            DNC,
        )

    def test_friendly_composition_profile_shorthand_and_version_diagnostic(self):
        self.assertIn("_addon.version = '1.4.7'", ADDON)
        self.assertIn(
            "direct_composition and compositions[direct_composition] and args[1]",
            ADDON,
        )
        self.assertIn(
            "begin(direct_composition, normalize_profile(args[1]), false)",
            ADDON,
        )
        self.assertIn("elseif command == 'version' then", ADDON)
        self.assertIn("Loaded v'.._addon.version", ADDON)

    def test_locus_dire_bats_profile_is_accuracy_first_and_sustainable(self):
        addon = ADDON.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        rdm = RDM.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        brd = BRD.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        self.assertIn("Sustained Locus Dire Bats: King Ranperre's Tomb", addon)
        self.assertIn("sustained = true", addon)
        self.assertIn("stationary = true", addon)
        self.assertIn("cor = {'corsair', 'samurai'}", addon)
        self.assertIn("indi='Fury', geo='Frailty', entrust='Refresh'", addon)
        self.assertIn("1264 accuracy target", addon)
        self.assertIn("locus = 'locusbats'", ADDON)
        self.assertIn("direbats = 'locusbats'", ADDON)
        self.assertIn("tombbats = 'locusbats'", ADDON)
        self.assertIn("party_shell = false", rdm)
        self.assertIn("debuff_mp_floor = 55", rdm)
        self.assertLess(rdm.index("'Distract III'"), rdm.index("'Dia III'"))
        self.assertIn("{spell='Barblizzara', buff='Barblizzard'}", brd)
        self.assertIn("{spell='Victory March', buff='march'}", brd)
        self.assertIn("{spell=\"Mage's Ballad III\", buff='ballad'}", brd)
        self.assertIn("{spell='Blade Madrigal', buff='madrigal'}", brd)
        self.assertNotIn("Barwatera", brd)
        self.assertIn("locusbats=true", PLD)
        self.assertIn("'apexbats','locusbats','apexcrabs'", DNC)
        heal_policy = PLD.split(
            "local function pstart_pld_heal_policy()", 1
        )[1].split("local function pstart_pld_valid_name", 1)[0]
        self.assertNotIn("apexbats", heal_policy)
        self.assertNotIn("locusbats", heal_policy)
        self.assertIn("PSTART_PLD_DEFAULT_HEAL_POLICY", heal_policy)
        self.assertIn("windower.register_event('gain buff'", ADDON)
        self.assertIn("buff_id == 269", ADDON)
        self.assertIn("schedule_zone_rearm(3)", ADDON)
        for script in (LOCUS_RELOAD, LOCUS_ACTIVATE):
            self.assertIn("pstart use progression locusbats", script)
            self.assertIn("pstart status", script)
            self.assertIn("pc status", script)
            self.assertIn("send Tackleberry gs c pstartpld status", script)
            self.assertNotRegex(
                script.lower(), r"(?m)^\s*(?:send\s+\S+\s+)?pc on\s*$"
            )
        self.assertIn("send Barneystinson gs reload", LOCUS_RELOAD)
        for name in ("Tackleberry", "Kickpuncher", "Smalls", "Dolomedes"):
            self.assertNotIn(f"send {name} gs reload", LOCUS_RELOAD)
        self.assertLess(
            LOCUS_RELOAD.index("send Achoo lua r PartyStart"),
            LOCUS_RELOAD.index("send Barneystinson gs reload"),
        )
        self.assertLess(
            LOCUS_RELOAD.index("send Barneystinson gs reload"),
            LOCUS_RELOAD.index("pstart use progression locusbats"),
        )
        self.assertIn("wait 12", LOCUS_RELOAD)

    def test_support_stop_and_reload_revoke_stale_combat_readiness(self):
        self.assertIn("issue('pc invalidate partystart')", ADDON)
        self.assertIn("stop_local{invalidate_combat=true}", ADDON)
        self.assertIn("windower.register_event('unload'", ADDON)
        revalidation = ADDON.split(
            "local function queue_job_revalidation", 1
        )[1].split("windower.register_event('ipc message'", 1)[0]
        self.assertIn(
            "stop_local{silent=true, preserve_revalidation=true}",
            revalidation,
        )
        self.assertNotIn("invalidate_combat=true", revalidation)

    def test_apex_crabs_profile_is_sustained_and_event_driven(self):
        addon = ADDON.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        rdm = RDM.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        brd = BRD.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        self.assertIn("Sustained Apex Crabs: Dho Gates", addon)
        self.assertIn("sustained = true", addon)
        self.assertIn("stationary = true", addon)
        self.assertIn("profile.stationary and 'stationary' or 'mobile'", ADDON)
        self.assertIn("targeter_csv, movement_mode", ADDON)
        self.assertIn("session.movement_mode = movement_mode", ADDON)
        self.assertIn("crabs = 'apexcrabs'", ADDON)
        self.assertIn("party_shell = true", rdm)
        self.assertIn("['Bubble Curtain']=true", rdm)
        self.assertIn("['Metallic Body']=true", rdm)
        self.assertIn("['Scissor Guard']=true", rdm)
        self.assertIn("mp_floor=55", rdm)
        self.assertIn("min_target_hpp=15", rdm)
        self.assertIn("pstart_rdm_cast_dispel(profile)", RDM)
        self.assertIn("action.category == 11", RDM)
        self.assertIn("res.monster_abilities[action.param]", RDM)
        self.assertIn("actor and type(actor.name) == 'string'", RDM)
        self.assertIn("heal_hpp = 45", rdm)
        self.assertIn("PSTART_PLD_CRAB_HEAL_POLICY", PLD)
        self.assertIn("routine_hpp = 88", PLD)
        self.assertIn("cluster_count = 2", PLD)
        self.assertIn("emergency_hpp = 65", PLD)
        self.assertIn("chivalry_reserve_hpp = 60", PLD)
        self.assertIn("chivalry_use_hpp = 55", PLD)
        self.assertIn("chivalry_release_hpp = 70", PLD)
        self.assertIn("pstart_pld_chivalry_available()", PLD)
        self.assertIn("queue = {entries={}}", RDM)
        self.assertIn("entry = entry", RDM)
        self.assertIn("table.remove(queue.entries, 1)", RDM)
        self.assertIn("Consume the observation when issuing the command", RDM)
        action_handler = RDM.split(
            "windower.raw_register_event('action'", 1
        )[1].split("windower.raw_register_event('action message'", 1)[0]
        self.assertNotIn("pstart_rdm_valid_name(actor.name)", action_handler)
        self.assertNotIn("queue.expires =", action_handler)
        self.assertIn("Barwatera", brd)
        self.assertIn("apexcrabs=true", PLD)

    def test_every_unattended_xp_profile_is_stationary(self):
        master = ADDON.split("    master = {", 1)[1].split(
            "    apexbats = {", 1
        )[0]
        bats = ADDON.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        locus_bats = ADDON.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        crabs = ADDON.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        for profile in (master, bats, locus_bats, crabs):
            self.assertIn("sustained = true", profile)
            self.assertIn("stationary = true", profile)
        self.assertEqual(4, ADDON.count("stationary = true"))
        self.assertIn("profile.stationary and 'stationary' or 'mobile'", ADDON)

    def test_limbus_is_mobile_dolo_driven_and_has_one_shot_pack_sleep(self):
        addon = ADDON.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        rdm = RDM.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        brd = BRD.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        self.assertIn("Limbus 119: Mobile Speed Floors", addon)
        self.assertIn("target_source = 'command_leader'", addon)
        self.assertIn("physical_offense = true", addon)
        self.assertIn("pld_controller = true", addon)
        self.assertNotIn("stationary = true", addon)
        self.assertIn("runtime_puller(composition, active_names, profile)", ADDON)
        self.assertIn("elseif kind == 'sleep' then", ADDON)
        self.assertIn("elseif command == 'sleep' then", ADDON)
        self.assertIn("current_profile ~= 'limbus'", ADDON)
        self.assertIn("'Horde Lullaby II', 'Horde Lullaby'", BRD)
        self.assertIn("PSTART_BRD_SLEEP_WINDOW = 8", BRD)
        self.assertIn("local function pstart_brd_cast_sleep()", BRD)
        self.assertIn("pstart_brd.sleep_requested_until = 0", BRD)
        self.assertIn("debuff_min_target_hpp = 45", brd)
        self.assertIn("party_shell = true", rdm)
        self.assertIn("healing = true", rdm)
        self.assertIn("heal_hpp = 50", rdm)
        self.assertIn("debuff_mp_floor = 35", rdm)
        self.assertIn("limbus=true", PLD)
        self.assertIn("pstart_pld.profile == 'limbus'", PLD)
        self.assertIn("'apexcrabs','limbus','physical'", DNC)


if __name__ == "__main__":
    unittest.main()
