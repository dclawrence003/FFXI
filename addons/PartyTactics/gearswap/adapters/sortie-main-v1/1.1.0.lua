-- Exact-generation GearSwap adapter for the persistent Sortie profile.
-- It owns only queued semantic actions and support modes for this adapter
-- instance. It never emits PartyTactics or PartyCombat lifecycle commands.

local M={
    id='sortie-main-v1',version='1.1.0',
    controller='sortie-main',protocol=1,
}

local ALLOWED_ZONES={[133]=true,[189]=true,[275]=true}
local POLL_INTERVAL=0.10
local MOVEMENT_DELAY=6.0
local MAX_MODEL_SIZE=10
local MAZURKA_SPELL=465
local MAZURKA_BUFF=219

local ACTIONS={
    COR={
        ['savage-blade']={kind='weaponskill',id=42,name='Savage Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=100},
    },
    PLD={
        ['savage-blade']={kind='weaponskill',id=42,name='Savage Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=100},
        ['flat-blade']={kind='weaponskill',id=35,name='Flat Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=120},
    },
    DNC={
        ['evisceration']={kind='weaponskill',id=25,name='Evisceration',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=100},
    },
    BRD={
        ['savage-blade']={kind='weaponskill',id=42,name='Savage Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=100},
    },
    RDM={
        ['black-halo']={kind='weaponskill',id=169,name='Black Halo',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=90},
        ['red-lotus-blade']={kind='weaponskill',id=34,name='Red Lotus Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=120},
        ['thunder']={kind='spell',id=164,name='Thunder',command='/ma',
            range=20.4,ttl=10,priority=110},
        ['fire-iv']={kind='spell',id=147,name='Fire IV',command='/ma',
            range=20.4,ttl=10,priority=130},
        ['fire-iii']={kind='spell',id=146,name='Fire III',command='/ma',
            range=20.4,ttl=10,priority=125},
    },
    GEO={
        ['black-halo']={kind='weaponskill',id=169,name='Black Halo',
            command='/ws',range=3.2,min_tp=1000,engaged=true,ttl=8,priority=90},
        ['thunder']={kind='spell',id=164,name='Thunder',command='/ma',
            range=20.4,ttl=10,priority=110},
    },
}

local state={authority=nil,pending={},next_poll=0,accepted=0,
    dispatched=0,expired=0,last='idle',pending_mode='movement',
    mode_due=0,applied_mode=nil,mazurka_pending=false}

if rawget(_G,'PARTYTACTICS_SORTIE_MAIN_TEST_MODE')==true then
    M._test_state=state
    M._test_actions=ACTIONS
end

local function uint32(value)
    if type(value)=='number' then
        return value>=1 and value<=4294967295 and value==math.floor(value)
            and value or nil
    end
    if type(value)~='string' or #value<1 or #value>10
        or value:match('^%d+$')==nil then return nil end
    local number=tonumber(value)
    return number and number>=1 and number<=4294967295
        and number==math.floor(number) and number or nil
end

local function epoch(value)
    if type(value)=='number' then
        return value>=0 and value==math.floor(value) and value or nil
    end
    if type(value)~='string' or #value<1 or #value>12
        or value:match('^%d+$')==nil then return nil end
    local number=tonumber(value)
    return number and number>=0 and number==math.floor(number)
        and number or nil
end

local function generation(value)
    return type(value)=='string' and #value<=64
        and value:match('^%d+%-%d+%-%d+$')~=nil
end

local function safe_token(value)
    return value==nil or value=='-' or type(value)=='string'
        and #value>=1 and #value<=64
        and value:match('^[a-z0-9][a-z0-9_-]*$')~=nil
end

local function current_player()
    local live=windower.ffxi.get_player()
    return type(player)=='table' and player or live,live
end

local function current_job()
    local current,live=current_player()
    return current and current.main_job or live and live.main_job or nil
end

local function logged_in_sortie()
    local info=windower.ffxi.get_info()
    return info and info.logged_in
        and ALLOWED_ZONES[tonumber(info.zone)]==true
end

local function party_claimed(target)
    local claim=target and tonumber(target.claim_id)
    if not claim or claim==0 then return false end
    local live=windower.ffxi.get_player()
    if live and tonumber(live.id)==claim then return true end
    local party_members=windower.ffxi.get_party() or {}
    for index=0,5 do
        local member=party_members['p'..tostring(index)]
        local id=type(member)=='table' and tonumber(
            member.mob and member.mob.id or member.mob_id or member.id) or nil
        if id==claim then return true end
    end
    return false
end

local function exact_target(id,expected_index)
    local target=windower.ffxi.get_mob_by_id(id)
    return type(target)=='table' and tonumber(target.id)==id
        and tonumber(target.index)==expected_index
        and tonumber(target.spawn_type)==16 and target.valid_target==true
        and (tonumber(target.hpp) or 0)>0 and target or nil
end

local function resource(action)
    if type(res)~='table' then return nil end
    local collection=action.kind=='spell' and res.spells
        or action.kind=='weaponskill' and res.weapon_skills or nil
    local found=collection and collection[action.id] or nil
    if not found or tonumber(found.id)~=action.id
        or (found.en or found.english)~=action.name then return nil end
    return found
end

local function collection_has(collection,wanted)
    if type(collection)~='table' then return false end
    if collection[wanted]==true or collection[wanted]==1
        or tonumber(collection[wanted])==wanted then return true end
    for key,value in pairs(collection) do
        if tonumber(value)==wanted
            or (value==true or value==1) and tonumber(key)==wanted
        then return true end
    end
    return false
end

local function learned(action)
    if action.kind=='spell' then
        return collection_has(windower.ffxi.get_spells() or {},action.id)
    end
    local abilities=windower.ffxi.get_abilities() or {}
    return collection_has(abilities.weapon_skills or {},action.id)
end

local function distance(target)
    local squared=tonumber(target and target.distance)
    return squared and squared>=0 and math.sqrt(squared) or nil
end

local function engaged_with(id)
    local current,live=current_player()
    local status=current and current.status or live and live.status
    if status~='Engaged' and status~=1 then return false end
    local battle=windower.ffxi.get_mob_by_target('bt')
    return not battle or tonumber(battle.id)==id
end

local function function_true(name,...)
    local callback=_G[name]
    if type(callback)~='function' then return false end
    local ok,value=pcall(callback,...)
    return ok and value==true
end

local function has_buff(id)
    local current=current_player()
    for _,buff in ipairs(current and current.buffs or {}) do
        if tonumber(buff)==id then return true end
    end
    return false
end

local function blocker(request,action,now)
    if now>=request.expires then return 'expired' end
    if not logged_in_sortie() or current_job()~=request.job then
        return 'invalid zone/job'
    end
    local target=exact_target(request.id,request.index)
    if not target then return 'invalid target' end
    if not party_claimed(target) then return 'waiting for party claim' end
    local found=resource(action)
    if not found or not learned(action) then return 'unavailable' end
    local observed=distance(target)
    local size=math.max(0,math.min(MAX_MODEL_SIZE,
        tonumber(target.model_size) or 0))
    if not observed or observed>(tonumber(action.range) or 0)+size then
        return 'out of range'
    end
    local current=current_player()
    if action.min_tp and (tonumber(current and current.tp) or 0)<action.min_tp
    then return 'waiting for TP' end
    if action.engaged and not engaged_with(request.id) then
        return 'waiting for matching engagement'
    end
    if action.kind=='spell' then
        local recasts=windower.ffxi.get_spell_recasts() or {}
        if (tonumber(recasts[found.recast_id or found.id]) or 0)
            >=(tonumber(spell_latency) or tonumber(latency) or 1)
        then return 'on recast' end
        if type(silent_can_use)=='function'
            and not function_true('silent_can_use',action.id)
        then return 'spell unavailable now' end
        if (tonumber(current and current.mp) or 0)<(tonumber(found.mp_cost) or 0)
        then return 'insufficient MP' end
    end
    if moving then return 'moving' end
    if type(midaction)=='function' and midaction() then return 'midaction' end
    if function_true('silent_check_disable') then return 'incapacitated' end
    return nil
end

local function issue(command)
    if type(command)=='string' and command~=''
        and type(windower.send_command)=='function'
    then windower.send_command(command) end
end

local function schedule_mode(mode,delay)
    state.pending_mode=mode
    state.mode_due=os.clock()+(tonumber(delay) or 0)
    if mode=='combat' then state.mazurka_pending=false end
end

local function apply_mode(now)
    local mode=state.pending_mode
    if not mode or now<state.mode_due or not logged_in_sortie() then return false end
    state.pending_mode=nil
    if mode==state.applied_mode then
        state.last=mode..' mode retained'
        return true
    end
    local job=current_job()
    if mode=='combat' then
        issue('cancel '..tostring(MAZURKA_BUFF))
        if job=='COR' then
            issue('r2 roll1 chaos; r2 roll2 samurai; r2 on')
        end
        state.mazurka_pending=false
    elseif mode=='movement' then
        if job=='COR' then
            issue('r2 roll1 bolter; r2 roll2 tactician; r2 on')
        elseif job=='BRD' then
            state.mazurka_pending=true
        end
    end
    state.applied_mode=mode
    state.last=mode..' mode applied'
    return true
end

local function try_mazurka()
    if not state.mazurka_pending or state.applied_mode~='movement'
        or current_job()~='BRD' or not logged_in_sortie()
    then return false end
    if has_buff(MAZURKA_BUFF) then
        state.mazurka_pending=false
        return true
    end
    local current=current_player()
    local status=current and current.status
    if status=='Engaged' or status==1 or moving
        or type(midaction)=='function' and midaction()
    then return false end
    local spell=res and res.spells and res.spells[MAZURKA_SPELL] or nil
    if not spell or not collection_has(
        windower.ffxi.get_spells() or {},MAZURKA_SPELL)
    then
        state.mazurka_pending=false
        state.last='Chocobo Mazurka unavailable'
        return false
    end
    local recasts=windower.ffxi.get_spell_recasts() or {}
    if (tonumber(recasts[spell.recast_id or spell.id]) or 0)
        >=(tonumber(spell_latency) or tonumber(latency) or 1)
    then return false end
    windower.chat.input('/ma "Chocobo Mazurka" <me>')
    state.mazurka_pending=false
    state.last='Chocobo Mazurka dispatched'
    return true
end

local function clear_actions(reason)
    state.pending={}
    state.last=reason or 'idle'
end

local function set_authority(gen,ep)
    ep=epoch(ep)
    if not generation(gen) or ep==nil then return false end
    if state.authority and (state.authority.generation~=gen
        or state.authority.epoch~=ep or state.authority.job~=current_job())
    then clear_actions('profile generation changed') end
    state.authority={generation=gen,epoch=ep,job=current_job()}
    return true
end

local function dispatch(request,action)
    windower.chat.input(('%s "%s" %d'):format(
        action.command,action.name,request.id))
    state.pending[request.semantic]=nil
    state.dispatched=state.dispatched+1
    state.last=action.name..' dispatched'
    return true
end

local function poll()
    local now=os.clock()
    if now<state.next_poll then return false end
    state.next_poll=now+POLL_INTERVAL
    apply_mode(now)
    try_mazurka()
    if type(midaction)=='function' and midaction() then return false end
    if type(tickdelay)=='number' and now<tickdelay then return false end
    if type(next_cast)=='number' and now<next_cast then return false end
    local selected,selected_action
    for semantic,request in pairs(state.pending) do
        local action=ACTIONS[request.job] and ACTIONS[request.job][semantic]
        local why
        if action then why=blocker(request,action,now)
        else why='invalid action' end
        request.blocker=why
        if why=='expired' or type(why)=='string' and why:match('^invalid')
        then
            state.pending[semantic]=nil
            state.expired=state.expired+1
            state.last=semantic..' '..why
        elseif why==nil and (not selected
            or action.priority>selected_action.priority
            or action.priority==selected_action.priority
                and request.created<selected.created)
        then selected,selected_action=request,action end
    end
    if selected then return dispatch(selected,selected_action) end
    return false
end

local function reserve(semantic,args)
    if #args<3 or #args>4 then return false,'action requires target and authority' end
    local id,gen,ep,token=uint32(args[1]),args[2],args[3],args[4]
    if not id or not set_authority(gen,ep) or not safe_token(token) then
        return false,'invalid target or authority'
    end
    local job=current_job()
    local action=job and ACTIONS[job] and ACTIONS[job][semantic] or nil
    if not action then return false,'action is not available to this job' end
    if not logged_in_sortie() then return false,'not in a Sortie instance' end
    local target=windower.ffxi.get_mob_by_id(id)
    local index=target and tonumber(target.index) or nil
    if not index or not exact_target(id,index) then
        return false,'target is not an exact live enemy'
    end
    if not party_claimed(target) then
        return false,'target is not claimed by this party'
    end
    local existing=state.pending[semantic]
    if existing and existing.id==id and existing.generation==gen
        and existing.epoch==epoch(ep)
    then
        existing.expires=os.clock()+action.ttl
        return true,'already pending'
    end
    state.pending[semantic]={semantic=semantic,id=id,index=index,job=job,
        generation=gen,epoch=epoch(ep),token=token,created=os.clock(),
        expires=os.clock()+action.ttl}
    state.accepted=state.accepted+1
    state.last=semantic..' pending'
    poll()
    return true,'pending'
end

local function handle_mode(semantic,args)
    if #args<3 or #args>4 or not uint32(args[1])
        or not set_authority(args[2],args[3]) or not safe_token(args[4])
    then return false,'invalid mode authority' end
    if semantic=='combat-mode' then schedule_mode('combat',0)
    elseif semantic=='movement-mode' then schedule_mode('movement',MOVEMENT_DELAY)
    elseif semantic=='acuex-mode' then
        if current_job()=='RDM' then issue('gs c weapons KajaSword') end
        state.last='Acuex weapon mode requested'
        return true,'mode accepted'
    elseif semantic=='normal-mode' then
        if current_job()=='RDM' then issue('gs c weapons Maxentius') end
        state.last='normal weapon mode requested'
        return true,'mode accepted'
    else return false,'unknown mode' end
    poll()
    return true,'mode accepted'
end

function M.activate()
    clear_actions('active')
    state.authority=nil
    state.next_poll=0
    state.applied_mode=nil
    state.mazurka_pending=false
    schedule_mode('movement',1.0)
    return true
end

function M.deactivate(reason)
    clear_actions(reason or 'inactive')
    state.authority=nil
    state.pending_mode=nil
    state.mazurka_pending=false
    state.applied_mode=nil
end

function M.handle_action(controller,semantic,args)
    if controller~=M.controller or type(args)~='table' then
        return false,'controller mismatch'
    end
    if semantic=='probe' then
        if #args~=3 or not set_authority(args[1],args[2])
            or tonumber(args[3])~=M.protocol then return false,'invalid probe' end
        if type(windower.send_command)=='function' then
            windower.send_command(('pt __controller_ready %s %s %d %d'):format(
                M.controller,args[1],epoch(args[2]),M.protocol))
        end
        return true,'ready'
    elseif semantic=='cancel' then
        if #args<3 or #args>4 or not uint32(args[1])
            or not set_authority(args[2],args[3]) or not safe_token(args[4])
        then return false,'invalid cancel' end
        local id=uint32(args[1])
        for key,request in pairs(state.pending) do
            if request.id==id then state.pending[key]=nil end
        end
        state.last='target requests cancelled'
        return true,'cancelled'
    elseif semantic=='movement-mode' or semantic=='combat-mode'
        or semantic=='acuex-mode' or semantic=='normal-mode'
    then return handle_mode(semantic,args) end
    return reserve(semantic,args)
end

function M.filter_pretarget() return false end
function M.filter_precast() return false end
function M.pre_tick() return poll() end
function M.user_job_tick() return poll() end
function M.prerender() poll(); return false end
function M.zone_change() clear_actions('zone changed'); state.pending_mode=nil end
function M.logout() M.deactivate('logout') end
function M.unload() M.deactivate('unload') end

function M.status()
    local pending={}
    for semantic,request in pairs(state.pending) do
        pending[#pending+1]=semantic..'='..tostring(request.blocker or 'ready')
    end
    table.sort(pending)
    return ('mode=%s pending=%s accepted=%d dispatched=%d expired=%d last=%s')
        :format(state.applied_mode or state.pending_mode or 'none',
            #pending>0 and table.concat(pending,',') or 'none',
            state.accepted,state.dispatched,state.expired,state.last)
end

return M
