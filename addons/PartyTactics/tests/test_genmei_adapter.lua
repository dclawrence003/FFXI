-- Behavioral tests for Genbu's manual-pass-through GearSwap adapter.

local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1]
    or (test_dir
        ..'/../gearswap/adapters/escha-ruaun-genbu-genmei/2.7.0.lua')

local function new_world(job, options)
    options = options or {}
    local clock = 100
    local input, commands, cancelled = {}, {}, {}
    local busy = options.busy == true
    local player = {
        id=1001, name='Tester', main_job=job, status='Engaged',
        hpp=100, mp=1000, tp=options.tp or 2000,
        buffs=options.buffs or {},
    }
    local target = {
        id=17990001, index=411, name='Genbu', claim_id=1001,
        spawn_type=16, valid_target=true, hpp=100,
        distance=options.distance or 9, model_size=2,
    }
    local party = {p0={name='Tester', mob={id=1001}}}
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.os = setmetatable({clock=function() return clock end}, {__index=os})
    env.player = player
    env.res = {
        spells={
            [164]={id=164, en='Thunder', recast_id=164, mp_cost=25},
            [167]={id=167, en='Thunder IV', recast_id=167, mp_cost=138},
        },
        weapon_skills={
            [42]={id=42, en='Savage Blade'},
        },
        job_abilities={
            [129]={id=129, en='Thunder Shot', recast_id=195},
            [301]={id=301, en='Triple Shot', recast_id=84},
        },
    }
    env.midaction = function() return busy end
    env.next_cast = 0
    env.tickdelay = 0
    env.moving = false
    env.silent_check_disable = function() return false end
    env.silent_can_use = function(spell_id)
        if options.silent_can_use_error then
            error('silent_can_use received unexpected id '..tostring(spell_id))
        end
        return options.silent_can_use ~= false
    end
    env.windower = {
        chat={input=function(command) input[#input + 1] = command end},
        send_command=function(command) commands[#commands + 1] = command end,
        ffxi={
            get_player=function() return player end,
            get_info=function()
                return {logged_in=true, zone=options.zone or 289}
            end,
            get_mob_by_id=function(id)
                return tonumber(id) == target.id and target or nil
            end,
            get_party=function() return party end,
            get_spells=function() return {[164]=true, [167]=true} end,
            get_abilities=function()
                return {weapon_skills={[42]=true}}
            end,
            get_spell_recasts=function() return {[164]=0, [167]=0} end,
            get_ability_recasts=function() return {[84]=0, [195]=0} end,
            get_mob_by_target=function(token)
                return token == 'bt' and target or nil
            end,
            cancel_buff=function(id) cancelled[#cancelled + 1] = id end,
        },
    }

    local load, load_error
    if setfenv then
        load, load_error = loadfile(adapter_path)
        if load then setfenv(load, env) end
    else
        load, load_error = loadfile(adapter_path, 't', env)
    end
    assert(load, load_error)
    local adapter = load()
    assert(adapter.activate() == true)

    local world = {
        adapter=adapter, env=env, player=player, target=target,
        party=party, input=input, commands=commands,
        cancelled=cancelled,
    }
    function world:advance(seconds) clock = clock + seconds end
    function world:set_busy(value) busy = value == true end
    function world:action(semantic, token)
        local arguments = {
            tostring(self.target.id), '1700000000-1001-1', '0',
        }
        if token then arguments[4] = token end
        return self.adapter.handle_action('genmei', semantic, arguments)
    end
    return world
end

local metadata = new_world('COR')
assert(metadata.adapter.id == 'escha-ruaun-genbu-genmei')
assert(metadata.adapter.version == '2.7.0')
assert(metadata.adapter.controller == 'genmei')
assert(metadata.adapter.protocol == 1)

-- Probe reporting remains available for diagnostics, but ordinary actions do
-- not require a prior probe or readiness proof.
local cor = new_world('COR')
assert(cor:action('shoot') == true)
assert(cor.input[1] == '/ra 17990001')
cor:advance(1)
assert(cor:action('last-stand') == true)
assert(cor.input[2] == '/ws "Last Stand" 17990001')
local probe = cor.adapter.handle_action('genmei', 'probe', {
    '1700000000-1001-1', '0', '1',
})
assert(probe == true)
assert(cor.commands[#cor.commands]
    == 'pt __controller_ready genmei 1700000000-1001-1 0 1')

-- One request never owns GearSwap callbacks. Every manual action passes while
-- automated work is active and immediately after it is submitted.
local manual = {id=999, english='Savage Blade', action_type='Weaponskill'}
assert(cor.adapter.filter_pretarget(manual, nil, {}) == false)
assert(cor.adapter.filter_precast(manual, nil, {}) == false)
assert(cor:action('shoot') == true)
assert(cor.adapter.filter_precast(manual, nil, {}) == false)

-- Same-semantic ticks are coalesced briefly instead of creating a command
-- flood; a later request still runs normally.
local before = #cor.input
assert(cor:action('shoot') == true)
assert(#cor.input == before)
cor:advance(1)
assert(cor:action('shoot') == true)
assert(#cor.input == before + 1)

-- Thunder Shot uses the same bounded next-legal polling model, so an in-flight
-- ranged attack cannot silently consume the sole proc request. COR never
-- consumes its native automatic job tick and manual input stays unrestricted.
local cor_proc = new_world('COR', {busy=true})
assert(cor_proc:action('combat-start') == true)
assert(cor_proc:action('proc') == true)
assert(#cor_proc.input == 0)
assert(cor_proc.adapter.user_job_tick() == false,
    'COR proc queue consumed the native job tick')
assert(cor_proc.adapter.filter_pretarget(manual, nil, {}) == false)
assert(cor_proc.adapter.filter_precast(manual, nil, {}) == false)
cor_proc:set_busy(false)
cor_proc:advance(0.2)
assert(cor_proc.adapter.prerender() == true)
assert(cor_proc.input[1] == '/ja "Thunder Shot" 17990001')
cor_proc.adapter.job_aftercast({id=129, interrupted=false})
assert(cor_proc.adapter.prerender() == false)

-- Triple Shot is a lower-priority self action. A waiting proc replaces it;
-- once the proc completes, a later Triple Shot still routes through GearSwap.
local triple = new_world('COR', {busy=true})
assert(triple:action('combat-start') == true)
assert(triple:action('triple-shot') == true)
assert(triple:action('proc') == true)
triple:set_busy(false)
triple:advance(0.2)
assert(triple.adapter.prerender() == true)
assert(triple.input[1] == '/ja "Thunder Shot" 17990001',
    'lower-priority Triple Shot displaced the Invincible proc')
triple.adapter.job_aftercast({id=129, interrupted=false})
triple:advance(2)
assert(triple:action('triple-shot') == true)
assert(triple.input[2] == '/ja "Triple Shot" <me>')
triple.adapter.job_aftercast({id=301, interrupted=false})

-- Selindrile's silent_can_use() is spell-only. Real resource IDs overlap:
-- Thunder Shot (ability 129) is Protectra V (spell 129), and Triple Shot
-- (ability 301) is Garuda (spell 301). Neither COR ability may ever be passed
-- to the spell predicate, regardless of the predicate's result.
local ability_predicate = new_world('COR', {
    busy=true, silent_can_use=false, silent_can_use_error=true,
})
assert(ability_predicate:action('combat-start') == true)
assert(ability_predicate:action('proc') == true)
ability_predicate:set_busy(false)
ability_predicate:advance(0.2)
assert(ability_predicate.adapter.prerender() == true)
assert(ability_predicate.input[1] == '/ja "Thunder Shot" 17990001')
ability_predicate.adapter.job_aftercast({id=129, interrupted=false})
ability_predicate:advance(2)
assert(ability_predicate:action('triple-shot') == true)
assert(ability_predicate.input[2] == '/ja "Triple Shot" <me>')
ability_predicate.adapter.job_aftercast({id=301, interrupted=false})

-- If Triple Shot has already entered flight, a higher-priority Thunder Shot
-- waits in the bounded deferred slot and fires at the next legal moment.
local cor_deferred = new_world('COR')
assert(cor_deferred:action('combat-start') == true)
assert(cor_deferred:action('triple-shot') == true)
assert(cor_deferred.input[1] == '/ja "Triple Shot" <me>')
assert(cor_deferred:action('proc') == true)
assert(#cor_deferred.input == 1)
cor_deferred.adapter.job_aftercast({id=301, interrupted=false})
cor_deferred:advance(2)
assert(cor_deferred.adapter.prerender() == true)
assert(cor_deferred.input[2] == '/ja "Thunder Shot" 17990001')
cor_deferred.adapter.job_aftercast({id=129, interrupted=false})

-- Tackle's coordinated Savage Blade is retained while Majesty healing owns
-- the current action. Only the automatic PLD helper tick yields; manual input
-- remains unconditional, and the request is released immediately on result.
local pld_queued = new_world('PLD', {busy=true})
assert(pld_queued:action('combat-start') == true)
assert(pld_queued.adapter.user_job_tick() == false,
    'combat binding alone suppressed PLD maintenance')
assert(pld_queued:action('savage-blade') == true)
assert(#pld_queued.input == 0,
    'busy PLD discarded ordering by submitting Savage Blade immediately')
assert(pld_queued.adapter.user_job_tick() == true,
    'queued Savage Blade did not reserve the automatic PLD tick')
assert(pld_queued.adapter.user_job_self_command(
    {'pstartpld', 'tick'}, {}) == true,
    'queued Savage Blade did not reserve coordinator PLD maintenance')
assert(pld_queued.adapter.user_job_self_command(
    {'pstartrdm', 'tick'}, {}) == false)
assert(pld_queued.adapter.filter_pretarget(manual, nil, {}) == false)
assert(pld_queued.adapter.filter_precast(manual, nil, {}) == false)
pld_queued:set_busy(false)
pld_queued:advance(0.2)
assert(pld_queued.adapter.prerender() == true)
assert(pld_queued.input[1] == '/ws "Savage Blade" 17990001')
pld_queued.adapter.action_event({
    actor_id=1001, category=3, param=42,
    targets={{id=17990001, actions={{message=1, param=1234}}}},
})
assert(pld_queued.adapter.user_job_tick() == false,
    'completed Savage Blade retained the PLD helper reservation')

-- Completed Invincible retires a Cure-delayed WS locally, without waiting
-- for the runtime's redundant scoped cancel. A future chain can rebind.
local pld_invincible = new_world('PLD', {busy=true})
assert(pld_invincible:action('combat-start') == true)
assert(pld_invincible:action('savage-blade') == true)
pld_invincible.adapter.action_event({
    actor_id=17990001, category=6, param=22,
    targets={{id=17990001, actions={{message=1, param=1}}}},
})
assert(pld_invincible.adapter.user_job_tick() == false)
assert(pld_invincible.adapter.status():find('queue=idle', 1, true))
assert(pld_invincible:action('combat-end') == true,
    'combat-end rejected routing already cleared by Invincible')
pld_invincible:set_busy(false)
pld_invincible:advance(1)
assert(pld_invincible:action('savage-blade') == true)
assert(pld_invincible.input[1] == '/ws "Savage Blade" 17990001',
    'post-Invincible intended chain could not rebind PLD routing')
pld_invincible.adapter.job_aftercast({id=42, interrupted=false})

-- Live TP, range, and engagement are checked at the eventual action edge.
-- A request below 1000 TP remains bounded and fires once the WS is legal.
local pld_tp = new_world('PLD', {tp=999})
assert(pld_tp:action('combat-start') == true)
assert(pld_tp:action('savage-blade') == true)
assert(#pld_tp.input == 0)
assert(pld_tp.adapter.user_job_tick() == false,
    'low-TP Savage request suppressed Majesty healing')
assert(pld_tp.adapter.user_job_self_command(
    {'pstartpld', 'tick'}, {}) == false,
    'low-TP Savage request suppressed coordinator PLD maintenance')
pld_tp.player.tp = 1000
pld_tp:advance(0.2)
assert(pld_tp.adapter.prerender() == true)
assert(pld_tp.input[1] == '/ws "Savage Blade" 17990001')
pld_tp.adapter.job_aftercast({id=42, interrupted=false})

local pld_range = new_world('PLD', {distance=100})
assert(pld_range:action('combat-start') == true)
assert(pld_range:action('savage-blade') == true)
assert(pld_range.adapter.user_job_tick() == false,
    'out-of-range Savage request suppressed Majesty healing')

local pld_idle = new_world('PLD')
pld_idle.player.status = 'Idle'
assert(pld_idle:action('combat-start') == true)
assert(pld_idle:action('savage-blade') == true)
assert(pld_idle.adapter.user_job_tick() == false,
    'disengaged Savage request suppressed Majesty healing')

local pld_backoff = new_world('PLD')
assert(pld_backoff:action('combat-start') == true)
assert(pld_backoff:action('savage-blade') == true)
pld_backoff.adapter.job_aftercast({id=42, interrupted=true})
assert(pld_backoff.adapter.user_job_tick() == false,
    'Savage retry backoff suppressed Majesty healing')

-- If no legal edge arrives, the PLD request expires and maintenance resumes;
-- it never turns into a readiness barrier or an unbounded retry.
local pld_expiry = new_world('PLD', {busy=true})
assert(pld_expiry:action('combat-start') == true)
assert(pld_expiry:action('savage-blade') == true)
pld_expiry:advance(7.1)
assert(pld_expiry.adapter.user_job_tick() == false)
assert(#pld_expiry.input == 0)

-- Every supported job action is a fixed name and normal input command.
local pld = new_world('PLD')
for _, case in ipairs{
    {'crusade', '/ma "Crusade" <me>'},
    {'divine-emblem', '/ja "Divine Emblem" <me>'},
    {'sentinel', '/ja "Sentinel" <me>'},
    {'flash', '/ma "Flash" 17990001'},
    {'provoke', '/ja "Provoke" 17990001'},
    {'savage-blade', '/ws "Savage Blade" 17990001'},
} do
    assert(pld:action(case[1]) == true)
    assert(pld.input[#pld.input] == case[2])
    pld:advance(1)
end

local dnc = new_world('DNC')
for _, case in ipairs{
    {'haste-samba', '/ja "Haste Samba" <me>'},
    {'presto', '/ja "Presto" <me>'},
    {'box-step', '/ja "Box Step" 17990001'},
    {'evisceration', '/ws "Evisceration" 17990001'},
} do
    assert(dnc:action(case[1]) == true)
    assert(dnc.input[#dnc.input] == case[2])
    dnc:advance(1)
end

local geo = new_world('GEO')
assert(geo:action('setup') == true)
assert(geo.input[1] == '/ma "Geo-Malaise" 17990001')
geo:advance(1)
assert(geo:action('combat-start') == true)
assert(geo:action('proc') == true)
assert(geo.input[2] == '/ma "Thunder" 17990001')
geo.adapter.job_aftercast({id=164, interrupted=false})
geo:advance(2)
assert(geo:action('burst') == true)
assert(geo.input[3] == '/ma "Thunder IV" 17990001')

local rdm = new_world('RDM')
assert(rdm:action('dispel') == true)
assert(rdm.input[1] == '/ma "Dispel" 17990001')

-- The adapter ignores only Genbu's unerasable Weight aura for the life of this
-- profile. HealBot NA stays enabled for real Poison, Accuracy Down, and other
-- removable ailments; deactivation returns Weight to the normal unignored
-- cross-profile baseline.
local rdm_proc = new_world('RDM', {busy=true})
assert(rdm_proc.commands[1] == 'hb ignore_debuff always weight')
assert(rdm_proc:action('combat-start') == true)
assert(rdm_proc:action('proc') == true)
assert(#rdm_proc.commands == 1)
assert(rdm_proc.adapter.user_job_tick() == true)
rdm_proc:set_busy(false)
rdm_proc:advance(0.2)
assert(rdm_proc.adapter.prerender() == true)
assert(rdm_proc.input[1] == '/ma "Thunder" 17990001')
rdm_proc.adapter.job_aftercast({id=164, interrupted=false})
assert(rdm_proc.adapter.user_job_tick() == false)

local rdm_cleanup = new_world('RDM', {busy=true})
assert(rdm_cleanup.commands[1] == 'hb ignore_debuff always weight')
assert(rdm_cleanup:action('combat-start') == true)
assert(rdm_cleanup:action('proc') == true)
assert(rdm_cleanup:action('combat-end') == true)
assert(#rdm_cleanup.commands == 1,
    'combat end disabled the profile-scoped Weight policy too early')
assert(rdm_cleanup.adapter.deactivate('test cleanup') == true)
assert(rdm_cleanup.commands[2] == 'hb unignore_debuff always weight')

-- A combat binding by itself never pauses the native helper. If Light arrives
-- while the character is busy, the exact Thunder IV waits for the next legal
-- tick and only that short pending/in-flight interval is consumed. Both the
-- ordinary user_job_tick path and PartyTactics' private pstartrdm tick path
-- are covered. Manual input remains unconditional pass-through throughout.
local queued = new_world('RDM', {busy=true})
assert(queued:action('combat-start') == true)
assert(queued.adapter.user_job_tick() == false,
    'combat binding suppressed ordinary RDM maintenance')
assert(queued.adapter.user_job_self_command({'pstartrdm', 'tick'}, {}) == false,
    'combat binding suppressed coordinator RDM maintenance')
assert(queued:action('burst') == true)
assert(#queued.input == 0, 'busy RDM submitted Thunder IV immediately')
assert(queued.adapter.user_job_tick() == true,
    'pending burst did not reserve the automatic helper tick')
assert(queued.adapter.user_job_self_command({'unrelated'}, {}) == false)
assert(queued.adapter.user_job_self_command({'pstartgeo', 'tick'}, {}) == false)
assert(queued.adapter.user_job_self_command(
    {'pstartrdm', 'tick', 'manual-extra'}, {}) == false)
assert(queued.adapter.user_job_self_command({'pstartrdm', 'tick'}, {}) == true,
    'pending burst did not reserve coordinator RDM maintenance')
assert(queued.adapter.filter_pretarget(manual, nil, {}) == false)
assert(queued.adapter.filter_precast(manual, nil, {}) == false)
queued:set_busy(false)
queued:advance(0.2)
assert(queued.adapter.user_job_self_command({'pstartrdm', 'tick'}, {}) == true)
assert(queued.input[1] == '/ma "Thunder IV" 17990001')
assert(queued.adapter.user_job_tick() == true,
    'in-flight burst released the automatic helper too early')
queued.adapter.job_aftercast({id=167, interrupted=true})
queued:advance(1.6)
assert(queued.adapter.user_job_tick() == true)
assert(queued.input[2] == '/ma "Thunder IV" 17990001',
    'interrupted Thunder IV did not receive its bounded retry')
queued.adapter.job_aftercast({id=167, interrupted=false})
assert(queued.adapter.user_job_tick() == false,
    'completed burst kept routine RDM maintenance suppressed')
assert(queued.adapter.user_job_self_command({'pstartrdm', 'tick'}, {}) == false,
    'completed burst kept coordinator RDM maintenance suppressed')
assert(queued:action('combat-end') == true)

local queued_geo = new_world('GEO', {busy=true})
assert(queued_geo:action('combat-start') == true)
assert(queued_geo:action('burst') == true)
assert(queued_geo.adapter.user_job_self_command({'pstartgeo', 'tick'}, {}) == true,
    'pending GEO burst did not reserve coordinator GEO maintenance')
assert(queued_geo.adapter.user_job_self_command({'pstartrdm', 'tick'}, {}) == false)
queued_geo:set_busy(false)
queued_geo:advance(0.2)
assert(queued_geo.adapter.user_job_self_command({'pstartgeo', 'tick'}, {}) == true)
assert(queued_geo.input[1] == '/ma "Thunder IV" 17990001')
queued_geo.adapter.job_aftercast({id=167, interrupted=false})
assert(queued_geo.adapter.user_job_self_command({'pstartgeo', 'tick'}, {}) == false)

-- A higher-priority Light burst arriving while low-tier Thunder is already in
-- flight is retained with its original burst-window TTL. Completion promotes
-- it without releasing this client's helper tick or filtering manual input.
local deferred = new_world('RDM')
assert(deferred:action('combat-start') == true)
assert(deferred:action('proc') == true)
assert(deferred.input[1] == '/ma "Thunder" 17990001')
assert(deferred:action('burst') == true)
assert(#deferred.input == 1, 'deferred burst fired over an in-flight spell')
assert(deferred.adapter.status():find('deferred=Thunder IV#17990001', 1, true))
assert(deferred.adapter.user_job_tick() == true)
assert(deferred.adapter.filter_pretarget(manual, nil, {}) == false)
assert(deferred.adapter.filter_precast(manual, nil, {}) == false)
deferred.adapter.job_aftercast({id=164, interrupted=false})
assert(deferred.adapter.user_job_tick() == true)
deferred:advance(2)
assert(deferred.adapter.prerender() == true)
assert(deferred.input[2] == '/ma "Thunder IV" 17990001')
deferred.adapter.job_aftercast({id=167, interrupted=false})
assert(deferred.adapter.user_job_tick() == false)

-- An interrupted or server-rejected lower-priority spell hands off to the
-- deferred burst instead of spending the burst window retrying low Thunder.
local deferred_interrupt = new_world('RDM')
assert(deferred_interrupt:action('combat-start') == true)
assert(deferred_interrupt:action('proc') == true)
assert(deferred_interrupt:action('burst') == true)
deferred_interrupt.adapter.job_aftercast({id=164, interrupted=true})
deferred_interrupt:advance(2)
assert(deferred_interrupt.adapter.prerender() == true)
assert(deferred_interrupt.input[2] == '/ma "Thunder IV" 17990001')

local deferred_reject = new_world('RDM')
assert(deferred_reject:action('combat-start') == true)
assert(deferred_reject:action('proc') == true)
assert(deferred_reject:action('burst') == true)
deferred_reject.adapter.action_event({
    actor_id=1001, category=4, param=164,
    targets={{id=17990001, actions={{message=4}}}},
})
deferred_reject:advance(2)
assert(deferred_reject.adapter.prerender() == true)
assert(deferred_reject.input[2] == '/ma "Thunder IV" 17990001')

-- Missing completion packets also promote the higher-priority work after the
-- bounded result timeout; they do not retry the displaced low-tier spell.
local deferred_timeout = new_world('RDM')
assert(deferred_timeout:action('combat-start') == true)
assert(deferred_timeout:action('proc') == true)
assert(deferred_timeout:action('burst') == true)
deferred_timeout:advance(4.1)
assert(deferred_timeout.adapter.prerender() == true)
deferred_timeout:advance(0.2)
assert(deferred_timeout.adapter.prerender() == true)
assert(deferred_timeout.input[2] == '/ma "Thunder IV" 17990001')

-- Current-request expiry also promotes live deferred work. This covers a low
-- Thunder that waited almost its whole TTL before entering flight.
local deferred_at_expiry = new_world('RDM', {busy=true})
assert(deferred_at_expiry:action('combat-start') == true)
assert(deferred_at_expiry:action('proc') == true)
deferred_at_expiry:advance(5.8)
deferred_at_expiry:set_busy(false)
assert(deferred_at_expiry.adapter.prerender() == true)
assert(deferred_at_expiry.input[1] == '/ma "Thunder" 17990001')
assert(deferred_at_expiry:action('burst') == true)
deferred_at_expiry:advance(0.3)
assert(deferred_at_expiry.adapter.prerender() == true)
deferred_at_expiry:advance(1.4)
assert(deferred_at_expiry.adapter.prerender() == true)
assert(deferred_at_expiry.input[2] == '/ma "Thunder IV" 17990001',
    'current expiry erased the still-live deferred burst')

-- Promotion never refreshes a deferred request's original TTL. A Thunder Shot
-- whose six-second proc window expires behind Triple Shot is discarded.
local deferred_expired = new_world('COR')
assert(deferred_expired:action('combat-start') == true)
assert(deferred_expired:action('triple-shot') == true)
assert(deferred_expired:action('proc') == true)
assert(#deferred_expired.input == 1)
deferred_expired:advance(6.1)
deferred_expired.adapter.job_aftercast({id=301, interrupted=false})
deferred_expired:advance(2)
assert(deferred_expired.adapter.prerender() == false)
assert(#deferred_expired.input == 1,
    'expired deferred Thunder Shot received a fresh TTL')

-- Encounter cleanup clears both the in-flight and deferred slots.
local deferred_cleanup = new_world('RDM')
assert(deferred_cleanup:action('combat-start') == true)
assert(deferred_cleanup:action('proc') == true)
assert(deferred_cleanup:action('burst') == true)
assert(deferred_cleanup:action('combat-end') == true)
deferred_cleanup:advance(10)
assert(deferred_cleanup.adapter.prerender() == false)
assert(deferred_cleanup.adapter.status():find('queue=idle deferred=idle', 1, true))
assert(#deferred_cleanup.input == 1)

-- GEO receives the same collision-safe behavior, independently. A request
-- that stays blocked expires with the burst window instead of owning future
-- automatic ticks.
local geo_queued = new_world('GEO', {busy=true})
assert(geo_queued:action('combat-start') == true)
assert(geo_queued.adapter.user_job_tick() == false)
assert(geo_queued:action('burst') == true)
assert(geo_queued.adapter.user_job_tick() == true)
geo_queued:advance(8.1)
assert(geo_queued.adapter.user_job_tick() == false,
    'expired GEO burst kept the native helper suppressed')
assert(#geo_queued.input == 0)

local brd = new_world('BRD')
assert(brd:action('barwatera') == true)
assert(brd.input[1] == '/ma "Barwatera" <me>')
brd:advance(1)
assert(brd:action('finale') == true)
assert(brd.input[2] == '/ma "Magic Finale" 17990001')

-- Tortoise recovery is fixed, token-deduped, and delegates recasting to the
-- existing BRD/COR helpers. It changes no equipment state.
local songs = new_world('BRD', {buffs={214, 197, 196}})
assert(songs:action('recover-songs', 'tortoise-1') == true)
assert(#songs.cancelled == 3)
assert(songs:action('recover-songs', 'tortoise-1') == true)
assert(#songs.cancelled == 3)

local rolls = new_world('COR', {buffs={321, 314}})
assert(rolls:action('recover-rolls', 'tortoise-1') == true)
assert(#rolls.cancelled == 2)
assert(rolls.cancelled[1] == 314 and rolls.cancelled[2] == 321,
    'Tortoise recovery did not prioritize Warlock before Samurai')

-- Exact target checks reject foreign claims and unrelated entities. Disarm
-- can still issue the one fixed local disengage after the target disappears.
local exact = new_world('RDM')
exact.target.claim_id = 9999
assert(exact:action('dispel') == false)
exact.target.claim_id = 0
assert(exact:action('dispel') == true)
exact.target.name = 'Not Genbu'
exact:advance(1)
assert(exact:action('dispel') == false)

cor.target.valid_target = false
cor:advance(1)
assert(cor:action('disengage') == true)
assert(cor.input[#cor.input] == '/attack off')

local status = cor.adapter.status()
assert(type(status) == 'string')
assert(status:find('manual-pass-through', 1, true))
assert(cor.adapter.deactivate('test') == true)
assert(cor.commands[#cor.commands]
    == 'pt __controller_lost genmei 1700000000-1001-1 0 1')

print('genmei adapter tests passed')
