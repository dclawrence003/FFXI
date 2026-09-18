local preflight = assert(loadfile('addons/PartyTactics/lib/preflight.lua'))()

local resources = {
    items = {
        [100]={id=100, en='Rostam'},
        [101]={id=101, en='Tauret'},
        [102]={id=102, en='Death Penalty'},
        [103]={id=103, en='Staunch Tathlum +1'},
        [104]={id=104, en='Animikii Bullet'},
        [105]={id=105, en='Living Bullet'},
        [106]={id=106, en='Thunder Card'},
        [107]={id=107, en='Trump Card'},
        [108]={id=108, en='Compensator'},
    },
    job_abilities = {
        [129]={id=129, en='Thunder Shot'},
        [132]={id=132, en='Dark Shot'},
        [75]={id=75, en='Elemental Seal'},
    },
    weapon_skills = {
        [221]={id=221, en='Last Stand'},
    },
    spells = {
        [167]={id=167, en='Thunder IV', levels={[5]=92,[21]=91}},
        [168]={id=168, en='Thunder V', levels={[4]=92,[21]=100}},
        [252]={id=252, en='Stun', levels={[4]=45,[8]=37}},
    },
    key_items = {
        [2894]={id=2894, en='tribulens'},
        [2949]={id=2949, en="Genbu's Honor"},
        [3031]={id=3031, en='radialens'},
    },
    buffs = {
        [214]={id=214, en='March'},
        [190]={id=190, en='Magic Atk. Boost'},
        [551]={id=551, en='Magic Atk. Boost'},
    },
}

local player = {
    name='Dolomedes', main_job='COR', main_job_id=17, main_job_level=99,
    sub_job='DNC', sub_job_id=19, sub_job_level=49,
    job_points={cor={jp_spent=2100}}, buffs={214},
}

local equipment = {
    main=1, main_bag=8,
    sub=2, sub_bag=8,
    range=3, range_bag=8,
    -- Idle ammo is deliberately not part of the profile contract.
    ammo=4, ammo_bag=8,
}

local equipped = {
    ['8:1']={id=100,count=1},
    ['8:2']={id=101,count=1},
    ['8:3']={id=102,count=1},
    ['8:4']={id=103,count=1},
}

local bags = {
    Inventory={enabled=true,
        {id=106,count=8},
    },
    Wardrobe={enabled=true,
        {id=104,count=1},
        {id=105,count=20},
    },
}

local key_items = {2894,2949}
local learned = {}
local abilities = {job_abilities={129,132}, weapon_skills={221}}
local zone = 289

local ffxi = {}
function ffxi.get_player() return player end
function ffxi.get_items(bag, index)
    if bag == nil then return {equipment=equipment} end
    if index ~= nil then return equipped[tostring(bag)..':'..tostring(index)] end
    return bags[bag] or {enabled=false}
end
function ffxi.get_key_items() return key_items end
function ffxi.get_spells() return learned end
function ffxi.get_abilities() return abilities end
function ffxi.get_info() return {logged_in=true, zone=zone} end

local policy = {
    all={
        key_items={{ids={2894,3031}, label='Tribulens or Radialens'}},
    },
    members={
        Dolomedes={
            buffs={'March'},
            equipment={main='Rostam', sub='Tauret', range='Death Penalty'},
            items={
                {name='Animikii Bullet', minimum=1},
                {name='Living Bullet', minimum=1, warn_below=12},
                {any_of={'Thunder Card','Trump Card'}, minimum=1,
                    bag_group='inventory'},
            },
            key_items={{id=2949, label="Genbu's Honor"}},
            actions={
                {kind='ability', name='Thunder Shot'},
                {kind='weaponskill', name='Last Stand'},
                {kind='ability', name='Dark Shot', optional=true},
            },
        },
    },
}

local function joined(values) return table.concat(values or {}, '\n') end
local function contains(values, wanted)
    return joined(values):find(wanted, 1, true) ~= nil
end
local function assert_payload_safe(result)
    for _, bucket in ipairs{'errors','warnings','details'} do
        for _, message in ipairs(result[bucket]) do
            assert(not message:find('|', 1, true))
            assert(not message:find('\r', 1, true))
            assert(not message:find('\n', 1, true))
            assert(#message <= 180)
        end
    end
end

-- Happy path proves that an idle defensive ammo item is ignored. Animikii and
-- Living Bullet are inventory requirements, not idle equipment requirements.
local passing = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(passing.passed)
assert(#passing.errors == 0)
assert(contains(passing.details, 'equipment range Death Penalty'))
assert(contains(passing.details, 'item Animikii Bullet 1'))
assert(contains(passing.details, 'item Living Bullet 20'))
assert(not joined(passing.errors):find('Staunch', 1, true))
assert(contains(passing.details, 'buff March active'))
assert(preflight.summary(passing) == 'PASS errors=0 warnings=0 details=12')
assert_payload_safe(passing)

-- A profile may pin its read-only barrier to one exact zone. This catches an
-- otherwise valid pop contract before any encounter runtime can bind a
-- same-named enemy elsewhere.
policy.zone = 289
local correct_zone = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(correct_zone.passed)
assert(contains(correct_zone.details, 'zone 289'))
zone = 130
local wrong_zone = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(not wrong_zone.passed)
assert(contains(wrong_zone.errors, 'zone expected 289 found 130'))
zone = 289
policy.zone = nil

-- Missing/wrong fight gear, consumables and an unavailable WS are independent
-- hard failures and are all reported in one deterministic result.
equipped['8:3'] = {id=108,count=1}
bags.Wardrobe = {enabled=true, {id=105,count=20}}
bags.Inventory = {enabled=true}
abilities.weapon_skills = {}
local failing = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(not failing.passed)
assert(contains(failing.errors,
    'equipment range expected Death Penalty found Compensator'))
assert(contains(failing.errors, 'item Animikii Bullet 0 found need 1'))
assert(contains(failing.errors,
    'item Thunder Card or Trump Card 0 found need 1'))
assert(contains(failing.errors, 'action Last Stand unavailable'))
assert_payload_safe(failing)

-- Required and optional key items differ only in severity. Low stock and an
-- optional unavailable action warn without making an otherwise valid result
-- fail.
equipped['8:3'] = {id=102,count=1}
bags.Wardrobe = {enabled=true,
    {id=104,count=1}, {id=105,count=2},
}
bags.Inventory = {enabled=true, {id=107,count=3}}
abilities.weapon_skills = {221}
abilities.job_abilities = {129}
policy.members.Dolomedes.key_items[#policy.members.Dolomedes.key_items + 1] = {
    id=9999, label='Optional test key|item\nline', optional=true,
}
local warning = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(warning.passed)
assert(contains(warning.warnings, 'item Living Bullet low 2 recommend 12'))
assert(contains(warning.warnings, 'action Dark Shot unavailable'))
assert(contains(warning.warnings, 'key item Optional test key item line missing'))
assert_payload_safe(warning)

-- Required key-item loss fails closed.
key_items = {2894}
local missing_honor = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(not missing_honor.passed)
assert(contains(missing_honor.errors, "key item Genbu's Honor missing"))
key_items = {2894,2949}

-- Required live effects are local, read-only pre-pop evidence. Missing or
-- unknown buffs fail closed instead of assuming support commands landed.
player.buffs = {}
local missing_buff = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(not missing_buff.passed)
assert(contains(missing_buff.errors, 'buff March missing'))
player.buffs = {214}
policy.members.Dolomedes.buffs = {'Unknown Test Buff'}
local unknown_buff = preflight.evaluate(policy, 'Dolomedes', ffxi, resources)
assert(not unknown_buff.passed)
assert(contains(unknown_buff.errors, 'buff Unknown Test Buff unknown'))
policy.members.Dolomedes.buffs = {'March'}

-- Duplicate English resource names are ambiguous. Profiles can pin an exact
-- status ID so Indi-Acumen (551) cannot be mistaken for effect 190.
policy.members.Dolomedes.buffs = {{id=551, label='Indi-Acumen'}}
player.buffs = {190}
local wrong_duplicate_buff = preflight.evaluate(
    policy, 'Dolomedes', ffxi, resources)
assert(not wrong_duplicate_buff.passed)
assert(contains(wrong_duplicate_buff.errors, 'buff Indi-Acumen missing'))
player.buffs = {551}
local exact_duplicate_buff = preflight.evaluate(
    policy, 'Dolomedes', ffxi, resources)
assert(exact_duplicate_buff.passed, joined(exact_duplicate_buff.errors))
assert(contains(exact_duplicate_buff.details, 'buff Indi-Acumen active'))
policy.members.Dolomedes.buffs = {'March'}
player.buffs = {214}

-- Spell availability checks learned state and current main/subjob access,
-- including the resource convention that level 100 denotes a JP-gift spell.
local magic_policy = {
    members={
        Achoo={actions={
            {kind='spell', name='Thunder V'},
            {kind='spell', name='Stun'},
            {kind='ability', name='Elemental Seal'},
        }},
    },
}
player = {
    name='Achoo', main_job='GEO', main_job_id=21, main_job_level=99,
    sub_job='BLM', sub_job_id=4, sub_job_level=49,
    job_points={geo={jp_spent=2100}},
}
learned = {[168]=true,[252]=true}
abilities = {job_abilities={75},weapon_skills={}}
local magic = preflight.evaluate(magic_policy, 'Achoo', ffxi, resources)
assert(magic.passed, joined(magic.errors))
assert(contains(magic.details, 'action Thunder V available'))
assert(contains(magic.details, 'action Stun available'))

learned[252] = nil
local missing_spell = preflight.evaluate(magic_policy, 'Achoo', ffxi, resources)
assert(not missing_spell.passed)
assert(contains(missing_spell.errors, 'action Stun unavailable'))

-- Output order is stable and a mismatched local identity cannot be audited as
-- another member.
local first = preflight.evaluate(magic_policy, 'Achoo', ffxi, resources)
local second = preflight.evaluate(magic_policy, 'Achoo', ffxi, resources)
assert(joined(first.errors) == joined(second.errors))
assert(joined(first.warnings) == joined(second.warnings))
assert(joined(first.details) == joined(second.details))
local wrong_identity = preflight.evaluate(magic_policy, 'Dolomedes', ffxi, resources)
assert(not wrong_identity.passed)
assert(contains(wrong_identity.errors,
    'local player expected Dolomedes found Achoo'))

print('PartyTactics preflight evaluator tests passed')
