return {
    schema = 1,
    id = 'dynamis-divergence-wave1-boss-magic',
    version = '1.2.1',
    policy_id = 'pt-ddw1-boss',
    label = 'Dynamis-D Wave 1 boss: PLD/COR manual Darkness',
    aliases = {'ddw1boss','dyna-w1-boss','dynamis-w1-boss'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR'}},
        Kickpuncher={main_job='DNC'},
        Barneystinson={main_job='BRD', sub_jobs={'WHM'}},
        Smalls={main_job='RDM', sub_jobs={'WHM'}},
        Achoo={main_job='GEO', sub_jobs={'WHM'}},
    },

    roles = {
        tank='Tackleberry', puller='Tackleberry',
        damage_closer='Dolomedes', skillchain_opener='Tackleberry',
        fallback_opener='Kickpuncher', primary_healer='Smalls',
        support_healers='Barneystinson', bubble_support='Achoo',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='mobile',
        attackers={'Dolomedes','Tackleberry'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher','Smalls','Achoo'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        cor={rolls={'samurai','wizard'}},
        brd={
            preset='magicboss', target_source='Tackleberry',
            healbot='cure-na',
        },
        rdm={
            preset='magicboss-protect', target_source='Tackleberry',
            haste={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
            refresh={'Smalls','Tackleberry','Achoo','Barneystinson'},
            phalanx={'Dolomedes','Tackleberry'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
        },
        geo={
            mode='leanrrmanaged', zerg=false, indi='Acumen', geo='Malaise',
            entrust='Refresh', entrustee='Tackleberry', healbot='cure-na',
            combat_entrust_only=false,
        },
        pld={
            preset='manualsc', leader='Dolomedes',
            native_buffs=false, native_tank=false,
        },
        dnc={preset='tankheal', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={
            weapon_mode='DualLeaden', ws='Leaden Salute', tp=1000,
            automatic=false,
        },
        Tackleberry={
            weapon_mode='Naegling', ws='Chant du Cygne', tp=1000,
            automatic=false,
        },
        Kickpuncher={
            weapon_mode='Tauret', ws="Rudra's Storm", tp=1000,
            automatic=false,
        },
    },

    manual_actions = {
        clarion={
            character='Barneystinson', adapter='typed-action',
            kind='ability', name='Clarion Call', target='<me>',
        },
        ballad2={
            character='Barneystinson', adapter='clarion-extra-song',
            kind='cast', name="Mage's Ballad II", target='<me>',
        },
        crusade={
            character='Tackleberry', adapter='typed-action',
            kind='cast', name='Crusade', target='<me>',
        },
        emblem={
            character='Tackleberry', adapter='typed-action',
            kind='ability', name='Divine Emblem', target='<me>',
        },
        sentinel={
            character='Tackleberry', adapter='typed-action',
            kind='ability', name='Sentinel', target='<me>',
        },
        flash={
            character='Tackleberry', adapter='typed-action',
            kind='cast', name='Flash', target='<t>',
        },
        provoke={
            character='Tackleberry', adapter='typed-action',
            kind='ability', name='Provoke', target='<t>',
        },
        cdc={
            character='Tackleberry', adapter='typed-action',
            kind='weaponskill', name='Chant du Cygne', target='<t>',
        },
        leaden={
            character='Dolomedes', adapter='typed-action',
            kind='weaponskill', name='Leaden Salute', target='<t>',
        },
        wildfire={
            character='Dolomedes', adapter='typed-action',
            kind='weaponskill', name='Wildfire', target='<t>',
        },
        rudra={
            character='Kickpuncher', adapter='typed-action',
            kind='weaponskill', name="Rudra's Storm", target='<t>',
        },
        blizzard={
            character='Achoo', adapter='typed-action',
            kind='cast', name='Blizzard V', target='<t>',
        },
    },

    safety = {reraise=true},

    advisories = {
        'Profile activation starts support but leaves PartyCombat and both attacker AutoWS loops Off. Keep the back line roughly 16-19 yalms from the boss while preserving cure range.',
        'Keep EasyFarm paused and manage FastFollow/positions manually. Those user-owned tools are not changed by this profile.',
        'Wait for March, Minne, and Ballad III. Use //pt clarion, confirm the effect, then //pt ballad2; Ballad II is blocked unless Clarion Call is active.',
        'Pull with support-only automation: //pt crusade, //pt emblem, manually drive Tackle in alone for one attack, then //pt sentinel. Use //pt arm, allow Tackle to receive authority, and only then //pt flash; that Flash establishes the shared boss target.',
        'Native PLD buff/hate automation is Off so it cannot consume Divine Emblem or reorder the pull. Use //pt flash on recast and //pt provoke when Tackle is /WAR to work hate manually.',
        'At coordinated TP use //pt cdc, //pt leaden, //pt wildfire inside the shrinking skillchain windows. Use //pt blizzard only as a timed optional magic burst.',
        'If Tackle lacks unlocked CDC, keep this profile unarmed until Kick is deliberately moved in and manually engaged to build TP; PartyCombat will not engage her. Use //pt rudra, //pt leaden, //pt wildfire, then disengage and move Kick back out.',
        'Use //pt disarm immediately when the boss dies. Wave 2 statues appear at once; do not let the party acquire or approach a new target.',
    },
}
