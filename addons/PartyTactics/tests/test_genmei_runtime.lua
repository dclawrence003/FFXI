-- Behavioral tests for Genbu's nonblocking best-effort runtime.
--
-- This is deliberately an encounter-level harness rather than a collection
-- of implementation-detail tests.  Packet categories, actor identities, TP
-- costs, timing windows, and operator controls mirror the live interfaces the
-- runtime receives from Windower/PartyTactics.

local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local sandbox = module('lib/sandbox.lua')
local loader, load_error = sandbox.load(
    BASE..'profiles/escha-ruaun-genbu-genmei/runtime.lua', loadfile)
assert(loader, load_error)
local runtime_module = loader()

local ACTOR = {
    Dolomedes=1001,
    Tackleberry=7802,
    Kickpuncher=7803,
    Barneystinson=7804,
    Smalls=7805,
    Achoo=7806,
}
local SPELL = {ThunderIV=167, ShellV=51}
local JOB_ABILITY = {
    Invincible=22, HasteSamba=189, BoxStep=202, Presto=261,
    TripleShot=301,
}
local MONSTER = {HardenShell=1050, TortoiseSong=1047}
local WS = {Evisceration=25, SavageBlade=42, LastStand=221}

local spells = {
    [SPELL.ThunderIV]={id=SPELL.ThunderIV, en='Thunder IV'},
    [SPELL.ShellV]={id=SPELL.ShellV, en='Shell V'},
}
local monster = {
    [MONSTER.HardenShell]={id=MONSTER.HardenShell, en='Harden Shell'},
    [MONSTER.TortoiseSong]={id=MONSTER.TortoiseSong, en='Tortoise Song'},
}
local job_abilities = {
    [JOB_ABILITY.Invincible]={id=JOB_ABILITY.Invincible, en='Invincible'},
    [JOB_ABILITY.HasteSamba]={
        id=JOB_ABILITY.HasteSamba, en='Haste Samba',
    },
    [JOB_ABILITY.BoxStep]={id=JOB_ABILITY.BoxStep, en='Box Step'},
    [JOB_ABILITY.Presto]={id=JOB_ABILITY.Presto, en='Presto'},
    [JOB_ABILITY.TripleShot]={
        id=JOB_ABILITY.TripleShot, en='Triple Shot',
    },
}
local weapon_skills = {
    [WS.Evisceration]={id=WS.Evisceration, en='Evisceration'},
    [WS.SavageBlade]={id=WS.SavageBlade, en='Savage Blade'},
    [WS.LastStand]={id=WS.LastStand, en='Last Stand'},
}

local function make_harness()
    local party_mobs = {}
    for name, id in pairs(ACTOR) do
        party_mobs[id] = {
            id=id, index=id % 2048, name=name, spawn_type=13,
        }
    end

    local h = {
        now=0,
        armed=false,
        zone=289,
        calls={},
        tp={Dolomedes=0, Tackleberry=0, Kickpuncher=0},
        authorize_result=true,
        adapter_result=true,
        party_mobs=party_mobs,
        boss={
            id=300, index=1300, name='Genbu', spawn_type=16,
            valid_target=true, hpp=100, claim_id=0,
        },
    }
    h.runtime = runtime_module.create()

    function h:record(kind, fields)
        fields = fields or {}
        fields.kind = kind
        fields.at = self.now
        self.calls[#self.calls + 1] = fields
    end

    function h:count(kind, fields)
        local total = 0
        for _, call in ipairs(self.calls) do
            local match = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then match = false end
            end
            if match then total = total + 1 end
        end
        return total
    end

    function h:last(kind, fields)
        for index = #self.calls, 1, -1 do
            local call = self.calls[index]
            local match = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then match = false end
            end
            if match then return call end
        end
        return nil
    end

    h.ctx = {
        now=function() return h.now end,
        player_name=function() return 'Dolomedes' end,
        zone_id=function() return h.zone end,
        current_target=function() return h.boss end,
        mob_array=function()
            local mobs = {h.boss}
            for _, mob in pairs(h.party_mobs) do
                mobs[#mobs + 1] = mob
            end
            return mobs
        end,
        mob_by_id=function(id)
            id = tonumber(id)
            if id == h.boss.id then return h.boss end
            return h.party_mobs[id]
        end,
        party_claimed=function(mob)
            return mob == h.boss
                and h.party_mobs[tonumber(h.boss.claim_id)] ~= nil
        end,
        party_tp=function(name) return h.tp[name] or 0 end,
        monster_ability=function(id) return monster[tonumber(id)] end,
        job_ability=function(id) return job_abilities[tonumber(id)] end,
        spell=function(id) return spells[tonumber(id)] end,
        weapon_skill=function(id) return weapon_skills[tonumber(id)] end,
        operator_armed=function() return h.armed end,
        authorize_encounter=function(id)
            h:record('authorize', {id=id})
            return h.authorize_result
        end,
        release_encounter=function(id)
            h:record('release', {id=id})
            return true
        end,
        actions={
            party_adapter=function(recipient, semantic, id, token)
                h:record('adapter', {
                    recipient=recipient,
                    semantic=semantic,
                    id=id,
                    token=token,
                })
                return h.adapter_result
            end,
            combat_force=function(id)
                h:record('force', {id=id})
                return true
            end,
            combat_stop=function()
                h:record('stop')
                return true
            end,
        },
        client={
            engage_once=function(id)
                h:record('engage-once', {id=id})
                return true
            end,
        },
    }

    function h:activate()
        self.runtime:on_activate(self.ctx)
    end

    function h:tick(at)
        self.now = at
        self.runtime:on_tick(self.ctx, at)
    end

    function h:action(packet, at)
        self.now = at
        self.runtime:on_action(self.ctx, packet)
    end

    return h
end

-- Category 7 is only the monster's readying packet.  For category 7 the
-- ability ID is in target.actions[1].param, not action.param.
local function ready_action(h, id)
    return {
        category=7,
        actor_id=h.boss.id,
        param=0,
        targets={{id=ACTOR.Dolomedes, actions={{param=id}}}},
    }
end

-- Category 11 is the completed monster ability packet and action.param is the
-- ability ID.
local function monster_action(h, id)
    return {
        category=11,
        actor_id=h.boss.id,
        param=id,
        targets={{id=ACTOR.Dolomedes, actions={{param=1}}}},
    }
end

-- Invincible is a completed category-6 job ability with resource ID 22.
local function job_ability_action(h, id)
    return {
        category=6,
        actor_id=h.boss.id,
        param=id,
        targets={{id=h.boss.id, actions={{param=1}}}},
    }
end

local function member_job_ability_action(h, actor, id, target_id, message)
    return {
        category=6,
        actor_id=assert(ACTOR[actor]),
        param=id,
        targets={{
            id=assert(target_id),
            actions={{param=1, message=message}},
        }},
    }
end

local function member_ability_action(h, actor, id, target_id, message,
    category)
    return {
        category=category or 6,
        actor_id=assert(ACTOR[actor]),
        param=id,
        targets={{
            id=assert(target_id),
            actions={{param=1, message=message}},
        }},
    }
end

local function spell_action(h, id)
    return {
        category=4,
        actor_id=h.boss.id,
        param=id,
        targets={{id=h.boss.id, actions={{param=1}}}},
    }
end

local function ws_action(h, actor, id, light, message)
    return {
        category=3,
        actor_id=assert(ACTOR[actor]),
        param=id,
        targets={{
            id=h.boss.id,
            actions={{
                param=1000,
                message=message,
                add_effect_message=light and 288 or nil,
                add_effect_param=light and 500 or nil,
            }},
        }},
    }
end

local function light_action(h)
    return ws_action(h, 'Dolomedes', WS.LastStand, true)
end

local function physical_action(h, actor, damage, message, category)
    return {
        category=category or 1,
        actor_id=assert(ACTOR[actor]),
        param=0,
        targets={{
            id=h.boss.id,
            actions={{param=damage or 0, message=message}},
        }},
    }
end

local function activate_armed(h, at)
    h:activate()
    h.armed = true
    h:tick(at or 0)
end

local function finish_opening(h)
    h:tick(0.3)
    h:tick(1.6)
    h:tick(1.9)
    h:tick(2.2)
    h:tick(5.2)
    h:tick(6.7)
    h:tick(8.2)
end

local function assert_no_physical_ws(h, message)
    assert(h:count('adapter', {semantic='evisceration'}) == 0
        and h:count('adapter', {semantic='savage-blade'}) == 0
        and h:count('adapter', {semantic='last-stand'}) == 0,
        message or 'physical WS was dispatched unexpectedly')
end

-- Loading is inert, and an unarmed profile never acquires or pulls a target.
local inert = make_harness()
inert:activate()
inert:tick(0)
assert(inert:count('authorize') == 0)
assert(inert:count('adapter') == 0)
assert(inert:count('force') == 0)

-- Arm is the only start switch.  Force and Dolo's cooperative engage happen
-- immediately on the arm edge, without waiting on buffs, packets, or probes.
local opening = make_harness()
activate_armed(opening, 0)
assert(opening:count('authorize') == 1)
assert(opening:count('adapter', {
    recipient='Dolomedes', semantic='combat-start',
}) == 1)
assert(opening:count('adapter', {
    recipient='Tackleberry', semantic='combat-start',
}) == 1)
assert(opening:count('adapter', {
    recipient='Smalls', semantic='combat-start',
}) == 1)
assert(opening:count('adapter', {
    recipient='Achoo', semantic='combat-start',
}) == 1)
assert(opening:count('force') == 1,
    'arm did not force the selected Genbu immediately')
assert(opening:count('engage-once') == 1,
    'arm did not immediately give Dolo the cooperative engage edge')
opening:tick(0.3)
assert(opening:last('adapter', {
    recipient='Barneystinson', semantic='barwatera',
}))
assert(opening:last('adapter', {
    recipient='Tackleberry', semantic='sentinel',
}))
assert(opening:last('adapter', {
    recipient='Dolomedes', semantic='proc', token='opening-proc',
}), 'bind did not issue one best-effort opening Thunder Shot')
assert(opening:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 0, 'opening proc did not receive the intended first Dolo action slot')
opening:tick(1.6)
assert(opening:count('force') == 2)
assert(opening:count('engage-once') == 2)
opening:tick(1.9)
assert(opening:last('adapter', {
    recipient='Tackleberry', semantic='crusade',
}))
assert(opening:last('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}), 'opening Thunder Shot permanently suppressed Triple Shot')
opening:action(member_job_ability_action(opening, 'Dolomedes',
    JOB_ABILITY.TripleShot, ACTOR.Dolomedes), 2.0)
opening:tick(2.2)
assert(opening:last('adapter', {recipient='Achoo', semantic='setup'}))
opening:tick(5.2)
assert(opening:last('adapter', {
    recipient='Tackleberry', semantic='divine-emblem',
}))
assert(opening:last('adapter', {
    recipient='Dolomedes', semantic='shoot',
}))
opening:tick(6.7)
assert(opening:last('adapter', {
    recipient='Tackleberry', semantic='flash',
}))
opening:tick(8.2)
assert(opening:last('adapter', {
    recipient='Tackleberry', semantic='provoke',
}))
opening:tick(12)
assert(opening:count('force') == 2
    and opening:count('engage-once') == 2,
    'bounded startup handoff became a persistent target lock')
opening.tp.Dolomedes = 1500
opening:tick(301.9)
assert(opening:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 1, 'completed Triple Shot retried before its real five-minute recast')
opening.tp.Dolomedes = 0
opening:tick(302.3)
assert(opening:count('adapter', {
    recipient='Achoo', semantic='setup',
}) == 1, 'runtime competed with native AutoGeo for periodic Malaise renewal')
assert(opening:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 2, 'Triple Shot did not receive its completion-timed refresh')

-- If an Invincible completion arrives on the same bind edge, it replaces the
-- still-pending opening task or merges with the just-submitted request. It may
-- not spend a second Quick Draw charge for the same opening immunity.
local opening_proc_merge = make_harness()
activate_armed(opening_proc_merge, 0)
opening_proc_merge:tick(0.3)
opening_proc_merge:action(job_ability_action(
    opening_proc_merge, JOB_ABILITY.Invincible), 0.4)
opening_proc_merge:tick(0.7)
assert(opening_proc_merge:count('adapter', {
    recipient='Dolomedes', semantic='proc',
}) == 1, 'same-edge Invincible duplicated the opening Thunder Shot')

-- Opening Barwater receives one bounded refresh near seven minutes. Even a
-- rejected submission is independent of a ready physical chain.
local barwater_refresh = make_harness()
activate_armed(barwater_refresh, 0)
finish_opening(barwater_refresh)
assert(barwater_refresh:count('adapter', {
    recipient='Barneystinson', semantic='barwatera',
}) == 1)
barwater_refresh:tick(419.9)
assert(barwater_refresh:count('adapter', {
    recipient='Barneystinson', semantic='barwatera',
}) == 1, 'Barwater maintenance fired before seven minutes')
barwater_refresh.adapter_result = false
barwater_refresh.tp.Dolomedes = 1600
barwater_refresh.tp.Tackleberry = 1300
barwater_refresh.tp.Kickpuncher = 1100
barwater_refresh:tick(420.2)
assert(barwater_refresh:count('adapter', {
    recipient='Barneystinson', semantic='barwatera',
}) == 2, 'seven-minute Barwater maintenance was not requested')
assert(barwater_refresh:last('adapter', {semantic='evisceration'}),
    'rejected Barwater maintenance blocked the physical chain')

-- A request that never produces a completed action packet gets another
-- bounded chance after twelve seconds, not a guessed full recast delay.
local missing_triple = make_harness()
missing_triple.adapter_result = false
activate_armed(missing_triple, 0)
missing_triple:tick(0.3)
missing_triple:tick(1.9)
missing_triple.tp.Dolomedes = 1500
missing_triple:tick(11.9)
assert(missing_triple:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 1)
missing_triple.tp.Dolomedes = 0
missing_triple:tick(12.2)
assert(missing_triple:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 2, 'missing Triple Shot request postponed itself for a full cycle')

-- Two observed completions at pull and five minutes make a third bounded use
-- eligible inside an eleven-minute encounter.
local triple_cadence = make_harness()
activate_armed(triple_cadence, 0)
triple_cadence:tick(0.3)
triple_cadence:tick(1.9)
triple_cadence:action(member_job_ability_action(triple_cadence, 'Dolomedes',
    JOB_ABILITY.TripleShot, ACTOR.Dolomedes), 2.0)
triple_cadence:tick(302.1)
triple_cadence:action(member_job_ability_action(triple_cadence, 'Dolomedes',
    JOB_ABILITY.TripleShot, ACTOR.Dolomedes), 302.2)
assert(triple_cadence:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 2)
triple_cadence.tp.Dolomedes = 0
triple_cadence:tick(602.3)
assert(triple_cadence:count('adapter', {
    recipient='Dolomedes', semantic='triple-shot',
}) == 3, 'eleven-minute fight could not request a third Triple Shot')

-- If a frame is very late, combat is still established before hostile GEO
-- setup on that same frame.  This is deterministic ordering, not a gate.
local delayed = make_harness()
delayed:activate()
delayed.armed = true
delayed:tick(0)
delayed:tick(7.0)
local force_index, geo_index
for index, call in ipairs(delayed.calls) do
    if call.kind == 'force' and not force_index then force_index = index end
    if call.kind == 'adapter' and call.recipient == 'Achoo'
        and call.semantic == 'setup' and not geo_index
    then
        geo_index = index
    end
end
assert(force_index and geo_index and force_index < geo_index,
    'late-frame GEO setup preceded the immediate combat edge')

-- Controller identity metadata is fail-open: a failed authorization result
-- cannot stop immediate force, the opener, or later combat requests.
local no_auth = make_harness()
no_auth.authorize_result = false
activate_armed(no_auth, 0)
no_auth:tick(0.3)
no_auth:tick(1.6)
no_auth:tick(2.2)
assert(no_auth:count('force') == 2)
assert(no_auth:count('engage-once') == 2)
assert(no_auth:count('adapter') > 0)
assert(no_auth:count('authorize') == 1,
    'identity authorization became a readiness polling loop')

-- DNC support uses the real TP costs. At 349 TP, Haste Samba must not be
-- attempted; the lower-cost Step lane may prepare with Presto. Only a
-- successful Presto packet opens the enhanced Box Step path. Once member
-- spacing clears and TP reaches 350, Samba still retains its existing
-- priority over maintenance Step work.
local samba = make_harness()
samba.tp.Kickpuncher = 349
activate_armed(samba, 0)
assert(samba:count('adapter', {semantic='haste-samba'}) == 0)
assert(samba:count('adapter', {semantic='presto'}) == 1)
assert(samba:count('adapter', {semantic='box-step'}) == 0,
    'Box Step treated a Presto submission as a successful completion')
samba:action(member_job_ability_action(samba, 'Kickpuncher',
    JOB_ABILITY.Presto, ACTOR.Kickpuncher), 0.1)
samba.tp.Kickpuncher = 350
samba:tick(0.3)
assert(samba:count('adapter', {semantic='haste-samba'}) == 0,
    'DNC member spacing was ignored after Presto')
samba:tick(1.6)
assert(samba:count('adapter', {semantic='haste-samba'}) == 1,
    'Haste Samba did not retain priority at its real 350-TP cost')
samba:action(member_job_ability_action(samba, 'Kickpuncher',
    JOB_ABILITY.HasteSamba, ACTOR.Kickpuncher), 1.7)
samba:tick(3.1)
assert(samba:count('adapter', {semantic='box-step'}) == 1,
    'successful Presto did not lead to Box Step after Samba')

local box = make_harness()
box.tp.Kickpuncher = 99
activate_armed(box, 0)
assert(box:count('adapter', {semantic='presto'}) == 0)
assert(box:count('adapter', {semantic='box-step'}) == 0)
box.tp.Kickpuncher = 100
box:tick(0.3)
assert(box:count('adapter', {semantic='presto'}) == 1,
    'Presto did not become eligible at Box Step\'s real 100-TP cost')
assert(box:count('adapter', {semantic='box-step'}) == 0)
box:action(member_job_ability_action(box, 'Kickpuncher',
    JOB_ABILITY.Presto, ACTOR.Kickpuncher), 0.4)
box:tick(1.7)
assert(box:count('adapter', {semantic='box-step'}) == 1,
    'completion-confirmed Presto did not release Box Step')

-- A submitted DNC command is not treated as success.  With no completion
-- packet, or with a known failure result, it retries after five seconds
-- without holding any other combat lane.
local lost_samba = make_harness()
lost_samba.tp.Kickpuncher = 350
activate_armed(lost_samba, 0)
lost_samba.runtime.next_step = math.huge -- isolate Samba retry behavior
lost_samba:tick(4.9)
lost_samba:tick(5.2)
assert(lost_samba:count('adapter', {semantic='haste-samba'}) == 2,
    'unconfirmed Haste Samba did not retry after five seconds')

-- Presto itself is bounded. Two unconfirmed or failed submissions consume at
-- most five seconds; ordinary Box Step then proceeds instead of becoming
-- dependent on an enhancement result.
local lost_presto = make_harness()
lost_presto.tp.Kickpuncher = 100
activate_armed(lost_presto, 0)
lost_presto:tick(1.6)
lost_presto:tick(2.1)
assert(lost_presto:count('adapter', {semantic='presto'}) == 2)
assert(lost_presto:count('adapter', {semantic='box-step'}) == 0)
lost_presto:tick(5.1)
assert(lost_presto:count('adapter', {semantic='box-step'}) == 1,
    'missing Presto completion gated ordinary Box Step')

local failed_presto = make_harness()
failed_presto.tp.Kickpuncher = 100
activate_armed(failed_presto, 0)
failed_presto:action(member_job_ability_action(failed_presto,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher, 75), 0.1)
failed_presto:tick(2.1)
failed_presto:action(member_job_ability_action(failed_presto,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher, 75), 2.2)
failed_presto:tick(5.1)
assert(failed_presto:count('adapter', {semantic='presto'}) == 2)
assert(failed_presto:count('adapter', {semantic='box-step'}) == 1,
    'failed Presto packet gated ordinary Box Step')

local failed_box = make_harness()
failed_box.tp.Kickpuncher = 100
activate_armed(failed_box, 0)
failed_box:action(member_job_ability_action(failed_box, 'Kickpuncher',
    JOB_ABILITY.Presto, ACTOR.Kickpuncher), 0.1)
failed_box:tick(1.6)
failed_box:action(member_job_ability_action(failed_box, 'Kickpuncher',
    JOB_ABILITY.BoxStep, failed_box.boss.id, 75), 1.7)
failed_box:tick(6.4)
failed_box:tick(6.7)
assert(failed_box:count('adapter', {semantic='box-step'}) == 2,
    'failed Box Step incorrectly entered its long refresh window')
assert(failed_box:count('adapter', {semantic='presto'}) == 1,
    'failed Box Step discarded still-active Presto')

-- Successful action packets, including manual actions, start the long
-- maintenance interval.  They are observations only and never reserve input.
local confirmed_dnc = make_harness()
confirmed_dnc.tp.Kickpuncher = 350
activate_armed(confirmed_dnc, 0)
confirmed_dnc:action(member_job_ability_action(confirmed_dnc, 'Kickpuncher',
    JOB_ABILITY.HasteSamba, ACTOR.Kickpuncher), 0.1)
confirmed_dnc:tick(1.6)
confirmed_dnc:action(member_job_ability_action(confirmed_dnc, 'Kickpuncher',
    JOB_ABILITY.Presto, ACTOR.Kickpuncher), 1.7)
confirmed_dnc:tick(3.1)
confirmed_dnc:action(member_job_ability_action(confirmed_dnc, 'Kickpuncher',
    JOB_ABILITY.BoxStep, confirmed_dnc.boss.id), 3.2)
confirmed_dnc:tick(8.2)
assert(confirmed_dnc:count('adapter', {semantic='haste-samba'}) == 1,
    'confirmed Haste Samba retried before its long refresh')
assert(confirmed_dnc:count('adapter', {semantic='presto'}) == 1,
    'confirmed Presto was redundantly repeated before Box Step')
assert(confirmed_dnc:count('adapter', {semantic='box-step'}) == 1,
    'confirmed Box Step retried before its long refresh')
confirmed_dnc:tick(48.3)
assert(confirmed_dnc:count('adapter', {semantic='presto'}) == 2,
    'successful Box Step did not clear Presto for the next maintenance cycle')
assert(confirmed_dnc:count('adapter', {semantic='box-step'}) == 1)

-- A manually completed Presto is observed but never reserved or filtered.
-- If Step is due, the next automatic action can use that live enhancement.
local manual_presto = make_harness()
activate_armed(manual_presto, 0)
manual_presto:action(member_job_ability_action(manual_presto,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher), 2.0)
manual_presto.tp.Kickpuncher = 100
manual_presto:tick(2.3)
assert(manual_presto:count('adapter', {semantic='presto'}) == 0)
assert(manual_presto:count('adapter', {semantic='box-step'}) == 1,
    'manual Presto completion was ignored while Box Step was due')

local manual_samba = make_harness()
activate_armed(manual_samba, 0)
manual_samba:action(member_job_ability_action(manual_samba, 'Kickpuncher',
    JOB_ABILITY.HasteSamba, ACTOR.Kickpuncher), 2.0)
manual_samba.tp.Kickpuncher = 350
manual_samba:tick(6.9)
assert(manual_samba:count('adapter', {semantic='haste-samba'}) == 0,
    'manual Haste Samba completion was ignored')
manual_samba:tick(82.1)
assert(manual_samba:count('adapter', {semantic='haste-samba'}) == 1,
    'manual Haste Samba did not become eligible after its refresh')

-- A category-7 readying packet must not start Invincible handling. In
-- particular, it cannot replace the one opening proc or suppress an otherwise
-- eligible Presto/Box Step sequence.
local ready_invincible = make_harness()
activate_armed(ready_invincible, 0)
ready_invincible:action(ready_action(
    ready_invincible, JOB_ABILITY.Invincible), 0.1)
ready_invincible.tp.Kickpuncher = 100
ready_invincible:tick(0.3)
assert(ready_invincible:count('adapter', {semantic='proc'}) == 1,
    'category-7 readying created a second proc beyond opening insurance')
assert(ready_invincible:count('adapter', {semantic='presto'}) == 1,
    'category-7 readying was mistaken for completed Invincible')
ready_invincible:action(member_job_ability_action(ready_invincible,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher), 0.4)
ready_invincible:tick(1.7)
assert(ready_invincible:count('adapter', {semantic='box-step'}) == 1)

-- The real category-6 completion starts the fixed 30-second immunity window.
-- It also clears a completion-confirmed Presto that would expire during the
-- hold. Step work resumes with a fresh Presto, without a readiness gate.
local invincible_dnc = make_harness()
invincible_dnc.tp.Kickpuncher = 100
activate_armed(invincible_dnc, 0)
invincible_dnc:action(member_job_ability_action(invincible_dnc,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher), 0.05)
invincible_dnc:action(job_ability_action(
    invincible_dnc, JOB_ABILITY.Invincible), 0.1)
invincible_dnc:tick(0.3)
invincible_dnc:tick(29.9)
assert(invincible_dnc:count('adapter', {semantic='presto'}) == 1,
    'Presto leaked into Invincible')
assert(invincible_dnc:count('adapter', {semantic='box-step'}) == 0,
    'Box Step leaked into Invincible')
assert_no_physical_ws(invincible_dnc,
    'automatic physical WS leaked into Invincible')
invincible_dnc:tick(30.2)
assert(invincible_dnc:count('adapter', {semantic='presto'}) == 2,
    'Invincible did not discard stale Presto and request a fresh one')
assert(invincible_dnc:count('adapter', {semantic='box-step'}) == 0)
invincible_dnc:action(member_job_ability_action(invincible_dnc,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher), 30.3)
invincible_dnc:tick(31.6)
assert(invincible_dnc:count('adapter', {semantic='box-step'}) == 1,
    'Box Step did not resume after the fixed Invincible window')

-- A successful Thunder stagger can remove the immunity early. Zero damage is
-- not enough; the first positive physical result from a party actor releases
-- the suppression immediately while the nominal 30-second timer remains the
-- fail-open fallback when no such packet arrives.
local staggered_invincible = make_harness()
activate_armed(staggered_invincible, 0)
staggered_invincible:action(member_job_ability_action(staggered_invincible, 'Kickpuncher',
    JOB_ABILITY.HasteSamba, ACTOR.Kickpuncher), 0.05)
staggered_invincible:action(job_ability_action(
    staggered_invincible, JOB_ABILITY.Invincible), 0.1)
staggered_invincible.tp.Kickpuncher = 100
staggered_invincible:action(physical_action(
    staggered_invincible, 'Kickpuncher', 0), 0.5)
staggered_invincible:tick(0.8)
assert(staggered_invincible:count('adapter', {semantic='box-step'}) == 0,
    'zero physical damage resumed physical automation')
staggered_invincible:action(physical_action(
    staggered_invincible, 'Kickpuncher', 250), 1.0)
staggered_invincible:tick(1.3)
assert(staggered_invincible:count('adapter', {semantic='presto'}) == 1,
    'positive post-stagger physical result did not resume Step preparation')
assert(staggered_invincible:count('adapter', {semantic='box-step'}) == 0)
staggered_invincible:action(member_job_ability_action(staggered_invincible,
    'Kickpuncher', JOB_ABILITY.Presto, ACTOR.Kickpuncher), 1.4)
staggered_invincible:tick(2.7)
assert(staggered_invincible:count('adapter', {semantic='box-step'}) == 1,
    'completion-confirmed Presto did not release post-stagger Box Step')
assert(staggered_invincible:count('adapter', {
    recipient='Achoo', semantic='cancel',
}) == 1, 'early stagger did not cancel Achoo fallback')
assert(staggered_invincible:count('adapter', {
    recipient='Smalls', semantic='cancel',
}) == 1, 'early stagger did not cancel Smalls fallback')
staggered_invincible:tick(4.0)
assert(staggered_invincible:count('adapter', {
    recipient='Achoo', semantic='proc',
}) == 0, 'Achoo cast redundant Thunder after physical immunity ended')
assert(staggered_invincible:count('adapter', {
    recipient='Smalls', semantic='proc',
}) == 0, 'Smalls cast redundant Thunder after physical immunity ended')

-- Three-step Light: Evisceration -> Savage Blade -> Last Stand.  Completed
-- WS packets from the correct actors drive each next request.  Both gaps are
-- at least the documented 3.0-second skillchain minimum (configured 3.1s).
local chain = make_harness()
chain.tp.Dolomedes = 1600
chain.tp.Tackleberry = 1300
chain.tp.Kickpuncher = 1100
activate_armed(chain, 0)
finish_opening(chain)
chain:tick(9.8)
assert(chain:count('adapter', {semantic='evisceration'}) == 0,
    'chain spent Tackle TP before the ten-second opener settled')
local presto_before_evis = chain:count('adapter', {
    recipient='Kickpuncher', semantic='presto',
})
local box_before_evis = chain:count('adapter', {
    recipient='Kickpuncher', semantic='box-step',
})
chain:tick(10.1)
local evis = assert(chain:last('adapter', {
    recipient='Kickpuncher', semantic='evisceration',
}), 'ready three-step chain did not start with Kickpuncher Evisceration')
assert(chain:count('adapter', {
        recipient='Kickpuncher', semantic='presto',
    }) == presto_before_evis
    and chain:count('adapter', {
        recipient='Kickpuncher', semantic='box-step',
    }) == box_before_evis, 'Step preparation displaced a ready Evisceration opener')
chain:action(ws_action(
    chain, 'Kickpuncher', WS.Evisceration), 10.5)
chain:tick(13.5)
assert(chain:count('adapter', {semantic='savage-blade'}) == 0,
    'Savage Blade was requested before 3.1 seconds elapsed')
chain:tick(13.8)
local savage = assert(chain:last('adapter', {
    recipient='Tackleberry', semantic='savage-blade',
}), 'observed Kickpuncher Evisceration did not schedule Savage Blade')
assert(savage.at - 10.5 >= 3.1)
chain:action(ws_action(
    chain, 'Tackleberry', WS.SavageBlade), 14.0)
chain:tick(17.0)
assert(chain:count('adapter', {semantic='last-stand'}) == 0,
    'Last Stand was requested before 3.1 seconds elapsed')
chain:tick(17.3)
local last = assert(chain:last('adapter', {
    recipient='Dolomedes', semantic='last-stand',
}), 'observed Tackleberry Savage Blade did not schedule Last Stand')
assert(last.at - 14.0 >= 3.1)
assert(evis.at >= 10.0)

-- Kick is optional.  Low Kick TP must immediately select the complete
-- Savage Blade -> Last Stand Light chain once the opening window has elapsed.
local two_step = make_harness()
two_step.tp.Dolomedes = 1600
two_step.tp.Tackleberry = 1300
activate_armed(two_step, 0)
finish_opening(two_step)
two_step:tick(10.1)
assert(two_step:last('adapter', {
    recipient='Tackleberry', semantic='savage-blade',
}), 'low Kick TP stalled the ready two-step Light chain')
two_step:action(ws_action(
    two_step, 'Tackleberry', WS.SavageBlade), 10.5)
two_step:tick(13.5)
assert(two_step:count('adapter', {semantic='last-stand'}) == 0)
two_step:tick(13.8)
assert(two_step:last('adapter', {
    recipient='Dolomedes', semantic='last-stand',
}))

-- If requested Evisceration never completes, its eight-second result timeout
-- cannot deadlock the fight.  The next attempt bypasses Kick and falls back to
-- Tackle's two-step opener.
local missed_evis = make_harness()
missed_evis.tp.Dolomedes = 1600
missed_evis.tp.Tackleberry = 1300
missed_evis.tp.Kickpuncher = 1100
activate_armed(missed_evis, 0)
finish_opening(missed_evis)
missed_evis:tick(10.1)
assert(missed_evis:count('adapter', {semantic='evisceration'}) == 1)
missed_evis:tick(18.1)
assert(missed_evis:count('adapter', {semantic='savage-blade'}) == 0,
    'chain timed out at, rather than after, its deadline')
missed_evis:tick(18.4)
missed_evis:tick(18.8)
assert(missed_evis:count('adapter', {semantic='savage-blade'}) == 0)
missed_evis:tick(19.1)
assert(missed_evis:last('adapter', {
    recipient='Tackleberry', semantic='savage-blade',
}), 'missed Evisceration did not fail over to the two-step chain')
assert(missed_evis:count('adapter', {semantic='evisceration'}) == 1,
    'missed Evisceration was immediately retried instead of bypassed')

-- A completed packet carrying a known miss/failure message is not a valid
-- chain step.  It follows the same bounded timeout and two-step fallback as a
-- command that produced no completion packet at all.
local failed_evis = make_harness()
failed_evis.tp.Dolomedes = 1600
failed_evis.tp.Tackleberry = 1300
failed_evis.tp.Kickpuncher = 1100
activate_armed(failed_evis, 0)
finish_opening(failed_evis)
failed_evis:tick(10.1)
failed_evis:action(ws_action(
    failed_evis, 'Kickpuncher', WS.Evisceration, false, 158), 10.5)
failed_evis:tick(13.8)
assert(failed_evis:count('adapter', {semantic='savage-blade'}) == 0,
    'failed Evisceration was treated as a completed chain step')
failed_evis:tick(18.4)
failed_evis:tick(19.0)
assert(failed_evis:last('adapter', {
    recipient='Tackleberry', semantic='savage-blade',
}), 'failed Evisceration did not reach the two-step fallback')

-- Actor identity is authoritative.  Another character's Savage Blade does
-- not advance the lane, while a manually issued Tackleberry Savage Blade does
-- recover or replace stale in-flight state and receives an automatic closer.
local manual_recovery = make_harness()
manual_recovery.tp.Dolomedes = 1600
manual_recovery.tp.Tackleberry = 1300
manual_recovery.tp.Kickpuncher = 1100
activate_armed(manual_recovery, 0)
finish_opening(manual_recovery)
manual_recovery:tick(10.1)
manual_recovery:action(ws_action(
    manual_recovery, 'Barneystinson', WS.SavageBlade), 10.3)
manual_recovery:tick(13.5)
assert(manual_recovery:count('adapter', {semantic='last-stand'}) == 0,
    'wrong actor identity advanced the skillchain')
manual_recovery:action(ws_action(
    manual_recovery, 'Tackleberry', WS.SavageBlade), 13.6)
manual_recovery:tick(16.6)
assert(manual_recovery:count('adapter', {semantic='last-stand'}) == 0)
manual_recovery:tick(16.9)
assert(manual_recovery:last('adapter', {
    recipient='Dolomedes', semantic='last-stand',
}), 'manual Tackleberry Savage Blade did not recover the closer')

-- Dolo must not remain parked forever if Tackle never reaches opener TP.  A
-- bounded ten-second partner wait ends in standalone Last Stand, after which
-- coordinated chain acquisition remains available for later TP cycles.
local solo_dolo = make_harness()
solo_dolo.tp.Dolomedes = 1600
activate_armed(solo_dolo, 0)
finish_opening(solo_dolo)
solo_dolo:tick(10.1)
solo_dolo:tick(20.0)
assert(solo_dolo:count('adapter', {semantic='last-stand'}) == 0,
    'standalone Dolo fail-open fired before its partner wait elapsed')
solo_dolo:tick(20.3)
assert(solo_dolo:last('adapter', {
    recipient='Dolomedes', semantic='last-stand',
}), 'Dolo stayed parked when Tackle could not supply an opener')

-- Live evidence showed that every Dispel and Finale attempt against Genbu
-- failed. Harden Shell therefore consumes no action lane; Tortoise Song is
-- still handled only on category-11 completion. Its category-7 readying packet
-- schedules nothing and cannot consume the completion dedupe entry.
local harden = make_harness()
activate_armed(harden, 0)
finish_opening(harden)
harden:action(ready_action(harden, MONSTER.HardenShell), 9.0)
harden:tick(9.3)
assert(harden:count('adapter', {semantic='dispel'}) == 0)
assert(harden:count('adapter', {semantic='finale'}) == 0)
harden:action(monster_action(harden, MONSTER.HardenShell), 9.4)
harden:tick(10.7)
assert(harden:count('adapter', {semantic='dispel'}) == 0)
assert(harden:count('adapter', {semantic='finale'}) == 0)

local tortoise = make_harness()
activate_armed(tortoise, 0)
finish_opening(tortoise)
tortoise:action(ready_action(tortoise, MONSTER.TortoiseSong), 9.0)
tortoise:tick(9.3)
assert(tortoise:count('adapter', {semantic='recover-songs'}) == 0)
assert(tortoise:count('adapter', {semantic='recover-rolls'}) == 0)
tortoise:action(monster_action(tortoise, MONSTER.TortoiseSong), 9.4)
tortoise:tick(9.7)
assert(tortoise:last('adapter', {
    recipient='Barneystinson', semantic='recover-songs',
}))
tortoise:tick(10.7)
assert(tortoise:last('adapter', {
    recipient='Dolomedes', semantic='recover-rolls',
}))

-- Shell V is likewise left alone instead of displacing a Thunder/buff action
-- with a removal spell that was observed to resist every time.
local shell = make_harness()
activate_armed(shell, 0)
finish_opening(shell)
shell:action(spell_action(shell, SPELL.ShellV), 9.0)
shell:tick(9.3)
assert(shell:count('adapter', {semantic='dispel'}) == 0)
assert(shell:count('adapter', {semantic='finale'}) == 0)

-- Invincible is category 6, not a monster category-11 action.  The completion
-- schedules independent Thunder attempts and suppresses physical WS for the
-- full fixed immunity duration.  A duplicate inside the dedupe window cannot
-- create another proc cycle.
local proc_window = make_harness()
activate_armed(proc_window, 0)
finish_opening(proc_window)
local shots_before_invincible = proc_window:count('adapter', {
    recipient='Dolomedes', semantic='shoot',
})
local dolo_proc_before_invincible = proc_window:count('adapter', {
    recipient='Dolomedes', semantic='proc',
})
proc_window:action(job_ability_action(
    proc_window, JOB_ABILITY.Invincible), 9.4)
proc_window:tick(9.7)
assert(proc_window:count('adapter', {
    recipient='Dolomedes', semantic='proc',
}) == dolo_proc_before_invincible + 1,
    'Invincible did not schedule a fresh Thunder Shot immediately')
proc_window:tick(12.0)
proc_window:tick(17.3)
assert(proc_window:count('adapter', {
    recipient='Dolomedes', semantic='shoot',
}) == shots_before_invincible,
    'normal ranged fire starved the eight-second Thunder Shot action window')
proc_window:tick(17.6)
assert(proc_window:count('adapter', {
    recipient='Dolomedes', semantic='shoot',
}) == shots_before_invincible + 1,
    'normal ranged fire did not resume after the bounded proc window')

local invincible = make_harness()
activate_armed(invincible, 0)
finish_opening(invincible)
local proc_before_readying = invincible:count('adapter', {semantic='proc'})
invincible:action(ready_action(
    invincible, JOB_ABILITY.Invincible), 9.0)
invincible:tick(9.3)
assert(invincible:count('adapter', {semantic='proc'}) == proc_before_readying)
local dolo_proc_before_completion = invincible:count('adapter', {
    recipient='Dolomedes', semantic='proc',
})
invincible:action(job_ability_action(
    invincible, JOB_ABILITY.Invincible), 9.4)
assert(invincible:last('adapter', {
    recipient='Tackleberry', semantic='cancel',
}), 'Invincible did not retire Tackle\'s queued Savage Blade')
invincible.tp.Dolomedes = 1600
invincible.tp.Tackleberry = 1300
invincible.tp.Kickpuncher = 1100
invincible:tick(9.7)
invincible:action(member_job_ability_action(invincible, 'Kickpuncher',
    JOB_ABILITY.HasteSamba, ACTOR.Kickpuncher), 9.8)
invincible:tick(10.8)
assert(invincible:count('adapter', {
    recipient='Dolomedes', semantic='proc',
}) == dolo_proc_before_completion + 1,
    'completed Invincible did not schedule a fresh Dolo proc')
invincible:tick(11.2)
assert(invincible:last('adapter', {recipient='Achoo', semantic='proc'}))
invincible:tick(12.7)
assert(invincible:last('adapter', {recipient='Smalls', semantic='proc'}))
local proc_count = invincible:count('adapter', {semantic='proc'})
invincible:action(job_ability_action(
    invincible, JOB_ABILITY.Invincible), 12.8)
invincible:tick(13.1)
assert(invincible:count('adapter', {semantic='proc'}) == proc_count,
    'duplicate Invincible completion scheduled another response cycle')
invincible:tick(39.1)
assert_no_physical_ws(invincible,
    'automatic physical WS resumed before Invincible expired')
invincible:tick(39.5)
assert(invincible:last('adapter', {
    recipient='Kickpuncher', semantic='evisceration',
}), 'automatic skillchain did not resume after Invincible')

-- A real Light additional-effect message schedules independent RDM and GEO
-- bursts.  It does not reserve or filter any manual action.
local burst = make_harness()
activate_armed(burst, 0)
finish_opening(burst)
burst:action(light_action(burst), 9.0)
burst:tick(9.3)
assert(burst:last('adapter', {recipient='Smalls', semantic='burst'}))
burst:tick(10.0)
assert(burst:last('adapter', {recipient='Achoo', semantic='burst'}))

-- A live unclaimed current Genbu stays bound before the pull.  After a party
-- claim has been observed, an unclaimed gap receives one fixed grace period.
local claim_gap = make_harness()
activate_armed(claim_gap, 0)
claim_gap:tick(30)
assert(claim_gap:count('authorize', {id=claim_gap.boss.id}) == 1)
assert(claim_gap:count('release', {id=claim_gap.boss.id}) == 0)
claim_gap.boss.claim_id = ACTOR.Dolomedes
claim_gap:tick(30.3)
claim_gap.boss.claim_id = 0
claim_gap:tick(30.6)
claim_gap:tick(32.1)
assert(claim_gap:count('release', {id=claim_gap.boss.id}) == 0)
claim_gap:tick(32.6)
assert(claim_gap:count('release', {id=claim_gap.boss.id}) == 1,
    'postclaim loss kept refreshing its own grace period')
assert(claim_gap:count('stop') == 1)

local initially_claimed = make_harness()
initially_claimed.boss.claim_id = ACTOR.Dolomedes
activate_armed(initially_claimed, 0)
initially_claimed.boss.claim_id = 0
initially_claimed:tick(0.3)
initially_claimed:tick(2.3)
assert(initially_claimed:count('release', {
    id=initially_claimed.boss.id,
}) == 1, 'claim observed during bind was mistaken for preclaim state')

-- Recovery tokens include encounter identity and event time, so the first
-- Tortoise Song of a second pop cannot be deduped by the first encounter.
local repeat_farm = make_harness()
activate_armed(repeat_farm, 0)
repeat_farm:action(monster_action(
    repeat_farm, MONSTER.TortoiseSong), 1)
repeat_farm:tick(1.1)
local first_recovery = assert(repeat_farm:last('adapter', {
    recipient='Barneystinson', semantic='recover-songs',
})).token
repeat_farm.boss.hpp = 0
repeat_farm:tick(4)
repeat_farm.armed = false
repeat_farm.boss = {
    id=301, index=1301, name='Genbu', spawn_type=16,
    valid_target=true, hpp=100, claim_id=0,
}
repeat_farm:tick(5)
repeat_farm.armed = true
repeat_farm:tick(5.3)
repeat_farm:action(monster_action(
    repeat_farm, MONSTER.TortoiseSong), 6)
repeat_farm:tick(6.1)
local second_recovery = assert(repeat_farm:last('adapter', {
    recipient='Barneystinson', semantic='recover-songs',
})).token
assert(first_recovery ~= second_recovery,
    'two encounters reused the same Tortoise recovery token')

-- A PartyTactics reapply recreates runtime counters while a same-version
-- GearSwap adapter may retain its recovery-token cache.  Simulate that with
-- two fresh runtime instances using the same server ID at different times.
local before_reapply = make_harness()
activate_armed(before_reapply, 20)
before_reapply:action(monster_action(
    before_reapply, MONSTER.TortoiseSong), 21)
before_reapply:tick(21.3)
local before_token = assert(before_reapply:last('adapter', {
    recipient='Barneystinson', semantic='recover-songs',
})).token

local after_reapply = make_harness()
activate_armed(after_reapply, 30)
after_reapply:action(monster_action(
    after_reapply, MONSTER.TortoiseSong), 31)
after_reapply:tick(31.3)
local after_token = assert(after_reapply:last('adapter', {
    recipient='Barneystinson', semantic='recover-songs',
})).token
assert(before_token ~= after_token,
    'runtime reapply recreated a cached Tortoise recovery token')

-- Disarm/off is immediate and does not wait for setup, combat, or a mechanic.
invincible.armed = false
invincible:tick(40.0)
assert(invincible:count('adapter', {
    recipient='Dolomedes', semantic='combat-end',
}) == 1)
assert(invincible:count('adapter', {
    recipient='Tackleberry', semantic='combat-end',
}) == 1)
assert(invincible:count('adapter', {
    recipient='Smalls', semantic='combat-end',
}) == 1)
assert(invincible:count('adapter', {
    recipient='Achoo', semantic='combat-end',
}) == 1)
assert(invincible:last('adapter', {
    recipient='Dolomedes', semantic='disengage',
}))
assert(invincible:count('stop') == 1)
assert(invincible:count('release') == 1)

print('genmei runtime tests passed')
