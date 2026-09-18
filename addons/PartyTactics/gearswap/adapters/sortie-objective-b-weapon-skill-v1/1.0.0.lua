-- Exact-target weapon-skill finisher adapter for the Sortie B objective.
-- Exact target/action reservations wait for a legal cast slot and never
-- consume or cancel manual input.

local M={
    id='sortie-objective-b-weapon-skill-v1',version='1.0.0',
    controller='sortie-b-ws',protocol=1,
}

local ALLOWED_ZONES={[133]=true,[189]=true,[275]=true}
local TARGETS={
    ['Biune Fire Elemental']=true,['Biune Ice Elemental']=true,
    ['Biune Air Elemental']=true,['Biune Earth Elemental']=true,
    ['Biune Thunder Elemental']=true,['Biune Water Elemental']=true,
    ['Biune Light Elemental']=true,['Biune Dark Elemental']=true,
}
local POLL_INTERVAL=0.10
local MAX_MODEL_SIZE=10
local ACTIONS={
    COR={
        ['savage-blade']={kind='weaponskill',id=42,name='Savage Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,
            ttl=7.0,priority=100},
    },
    PLD={
        ['savage-blade']={kind='weaponskill',id=42,name='Savage Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,
            ttl=7.0,priority=100},
    },
    DNC={
        ['evisceration']={kind='weaponskill',id=25,name='Evisceration',
            command='/ws',range=3.2,min_tp=1000,engaged=true,
            ttl=7.0,priority=100},
    },
    BRD={
        ['savage-blade']={kind='weaponskill',id=42,name='Savage Blade',
            command='/ws',range=3.2,min_tp=1000,engaged=true,
            ttl=7.0,priority=100},
    },
    RDM={
        ['black-halo']={kind='weaponskill',id=169,name='Black Halo',
            command='/ws',range=3.2,min_tp=1000,engaged=true,
            ttl=7.0,priority=100},
    },
    GEO={
        ['black-halo']={kind='weaponskill',id=169,name='Black Halo',
            command='/ws',range=3.2,min_tp=1000,engaged=true,
            ttl=7.0,priority=100},
    },
}

local state={authority=nil,pending={},next_poll=0,accepted=0,
    dispatched=0,expired=0,last='idle'}
if rawget(_G,'PARTYTACTICS_SORTIE_B_WS_TEST_MODE')==true then
    M._test_state=state
    M._test_actions=ACTIONS
end

local function uint32(value)
    if type(value)~='string' or value:match('^%d+$')==nil
        or #value<1 or #value>10 then return nil end
    local number=tonumber(value)
    return number and number>=1 and number<=4294967295
        and number==math.floor(number) and number or nil
end

local function epoch(value)
    if type(value)~='string' or value:match('^%d+$')==nil
        or #value<1 or #value>12 then return nil end
    local number=tonumber(value)
    return number and number>=0 and number==math.floor(number)
        and number or nil
end

local function generation(value)
    return type(value)=='string' and #value<=64
        and value:match('^%d+%-%d+%-%d+$')~=nil
end

local function safe_token(value)
    return value==nil or value=='-'
        or type(value)=='string' and #value>=1 and #value<=64
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

local function logged_in_zone()
    local info=windower.ffxi.get_info()
    return info and info.logged_in
        and ALLOWED_ZONES[tonumber(info.zone)]==true
end

local function party_claimed(target)
    local claim=target and tonumber(target.claim_id)
    if not claim or claim==0 then return false end
    local live=windower.ffxi.get_player()
    if live and tonumber(live.id)==claim then return true end
    local party=windower.ffxi.get_party() or {}
    for index=0,5 do
        local member=party['p'..tostring(index)]
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
        and TARGETS[target.name]==true
        and tonumber(target.spawn_type)==16
        and target.valid_target==true and (tonumber(target.hpp) or 0)>0
        and target or nil
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

local function blocker(request,action,now)
    if now>=request.expires then return 'expired' end
    if not logged_in_zone() or current_job()~=request.job then
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
    if action.min_tp and (tonumber(current and current.tp) or 0)<action.min_tp then
        return 'waiting for TP'
    end
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
        if (tonumber(current and current.mp) or 0)
            <(tonumber(found.mp_cost) or 0)
        then return 'insufficient MP' end
    end
    if moving then return 'moving' end
    if type(midaction)=='function' and midaction() then return 'midaction' end
    if function_true('silent_check_disable') then return 'incapacitated' end
    return nil
end

local function clear_all(reason)
    state.pending={}
    state.last=reason or 'idle'
end

local function set_authority(gen,ep)
    if not generation(gen) or epoch(ep)==nil then return false end
    local parsed=epoch(ep)
    if state.authority and (state.authority.generation~=gen
        or state.authority.epoch~=parsed
        or state.authority.job~=current_job())
    then clear_all('profile generation changed') end
    state.authority={generation=gen,epoch=parsed,job=current_job()}
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
        if why=='expired' or type(why)=='string' and why:match('^invalid') then
            state.pending[semantic]=nil
            state.expired=state.expired+1
            state.last=semantic..' '..why
        elseif why==nil and (not selected
            or action.priority>selected_action.priority
            or action.priority==selected_action.priority
                and request.created<selected.created)
        then
            selected,selected_action=request,action
        end
    end
    if selected then return dispatch(selected,selected_action) end
    return false
end

local function reserve(semantic,args)
    if #args<3 or #args>4 then
        return false,'action requires target and authority'
    end
    local id,gen,ep,token=uint32(args[1]),args[2],args[3],args[4]
    if not id or not set_authority(gen,ep) or not safe_token(token) then
        return false,'invalid target or authority'
    end
    local job=current_job()
    local action=job and ACTIONS[job] and ACTIONS[job][semantic] or nil
    if not action then return false,'action is not available to this job' end
    if not logged_in_zone() then return false,'not in a Sortie instance' end
    local target=windower.ffxi.get_mob_by_id(id)
    local index=target and tonumber(target.index) or nil
    if not index or not exact_target(id,index) then
        return false,'target is not an exact live Biune elemental'
    end
    if not party_claimed(target) then
        return false,'Biune elemental is not party claimed'
    end
    local existing=state.pending[semantic]
    if existing and existing.id==id and existing.generation==gen
        and existing.epoch==epoch(ep) then
        -- Runtime retries extend the same reservation rather than multiplying
        -- it. A temporarily busy caster therefore gets the first legal slot.
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

function M.activate()
    clear_all('active')
    state.authority=nil
    state.next_poll=0
    return true
end

function M.deactivate(reason)
    local authority=state.authority
    clear_all(reason or 'inactive')
    state.authority=nil
    if authority and type(windower.send_command)=='function' then
        windower.send_command(('pt __controller_lost %s %s %d %d'):format(
            M.controller,authority.generation,authority.epoch,M.protocol))
    end
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
            or not set_authority(args[2],args[3])
        then return false,'invalid cancel' end
        local id=uint32(args[1])
        for key,request in pairs(state.pending) do
            if request.id==id then state.pending[key]=nil end
        end
        state.last='cancelled'
        return true,'cancelled'
    end
    return reserve(semantic,args)
end

function M.filter_pretarget() return false end
function M.filter_precast() return false end
function M.pre_tick() return poll() end
function M.user_job_tick() return poll() end
function M.prerender() poll() return false end
function M.zone_change() clear_all('zone changed') end
function M.logout() clear_all('logout') end
function M.unload() clear_all('unload') end

function M.status()
    local pending={}
    for semantic,request in pairs(state.pending) do
        pending[#pending+1]=semantic..'='..tostring(request.blocker or 'ready')
    end
    table.sort(pending)
    return ('pending=%s accepted=%d dispatched=%d expired=%d last=%s'):format(
        #pending>0 and table.concat(pending,',') or 'none',
        state.accepted,state.dispatched,state.expired,state.last)
end

return M
