-- Frozen bootstrap ownership registry for public profile identities.
--
-- These seven entries and the command list never move or change. New profiles
-- add an isolated data/profile_identities/<profile-id>.lua sidecar; a syntax
-- error in that new file cannot prevent this established registry from loading.
return {
    schema = 1,
    -- Public control verbs and established direct manual-action shorthands
    -- can never become a profile id or alias. This v1 list is frozen. New
    -- fight actions use `//pt action <name>` instead of adding top-level
    -- shorthands; a future core command needs an explicit namespace migration.
    reserved_commands = {
        'use','preview','reapply','on','start','off','stop','arm','disarm',
        'force','action','status','check','preflight','version','list','show',
        'errors','audit','sleep',
        'acumen','clarion','ballad2','crusade','emblem','sentinel','flash',
        'provoke','cdc','leaden','wildfire','rudra','blizzard','silence',
    },
    identities = {
        {
            ordinal=1,
            id='locus-dire-bats-tomb',
            policy_id='pt-locus-bats',
            aliases={'locus','locusbats','direbats','tombbats','ranperre'},
        },
        {
            ordinal=2,
            id='limbus-119-stationary',
            policy_id='pt-limbus119',
            aliases={'limbus','lim','limbus119','limbus-stationary'},
        },
        {
            ordinal=3,
            id='ambuscade-2026-08-v1-breadwinner',
            policy_id='pt-ambu2608v1',
            aliases={'v1','ambuv1','breadwinner','ambuscade-v1'},
        },
        {
            ordinal=4,
            id='dynamis-divergence-wave1-route-corsair',
            policy_id='pt-ddw1-route',
            aliases={'ddw1route','dyna-w1-route','dynamis-w1-route'},
        },
        {
            ordinal=5,
            id='dynamis-divergence-wave1-boss-magic',
            policy_id='pt-ddw1-boss',
            aliases={'ddw1boss','dyna-w1-boss','dynamis-w1-boss'},
        },
        {
            ordinal=6,
            id='escha-ruaun-kammavaca',
            policy_id='pt-ruaun-kammavaca',
            aliases={'kammavaca','kamma','ruaun-kammavaca'},
        },
        {
            ordinal=7,
            id='escha-ruaun-genbu-genmei',
            policy_id='pt-genbu-genmei',
            aliases={'genmei','genbu','eschagenbu','genmeishield'},
        },
    },
}
