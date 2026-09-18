-- Actual PartyTactics + PartyCombat, simulated Windower and server boundaries.
-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
PARTYTACTICS_EXPORT_FIXTURE=true
local lab=assert(loadfile('addons/PartyTactics/tests/test_six_client_activation.lua'))()
PARTYTACTICS_EXPORT_FIXTURE=nil
local unpack_values=table.unpack or unpack
if not math.atan2 then math.atan2=function(y,x) return math.atan(y,x) end end
function string.startswith(value,prefix) return value:sub(1,#prefix)==prefix end
local queue={}
local inject_fault=arg and arg[1]=='--inject-stale-stop'
local function words(text)
    local result={}; for word in text:gmatch('%S+') do result[#result+1]=word end
    return result
end
local function attach(c)
    local pc={callbacks={},packets={},stops=0,commands={},chats={}}
    c.pc=pc
    c.player.status=0; c.player.index=c.player.id; c.player.target_index=0
    local self_mob={id=c.player.id,index=c.player.id,name=c.player.name,
        spawn_type=1,hpp=100,valid_target=true,x=0,y=0,z=0,distance=0}
    local packets={new=function(direction,id,fields)
        fields.direction=direction; fields.packet_id=id; return fields
    end,inject=function(p)
        pc.packets[#pc.packets+1]=p
        if p.direction=='outgoing' then
            assert(p.packet_id==0x01A,'Unexpected outgoing packet')
            c.battle=c.mobs[p['Target Index']]
            assert(c.battle and c.battle.id==p.Target,'Unknown packet target')
            c.current_target=c.battle; c.player.status=1
            c.player.target_index=c.battle.index
        else assert(p.packet_id==0x058,'Unexpected incoming packet') end
    end}
    local env=setmetatable({_addon={},os={clock=lab.now}}, {__index=_G})
    env.require=function(name)
        if name=='packets' then return packets end
        if name=='resources' then return {action_messages={[1]={color='D'}}} end
        assert(name=='strings','Unexpected PartyCombat dependency: '..name); return true
    end
    env.windower={addon_path='addons/PartyCombat/',
        add_to_chat=function(_,s) pc.chats[#pc.chats+1]=s end,
        register_event=function(...)
            local a={...}; for i=1,#a-1 do pc.callbacks[a[i]]=a[#a] end
        end,
        send_command=function(s)
            pc.commands[#pc.commands+1]=s
            if s=='input /attack off' then
                pc.stops=pc.stops+1; c.player.status=0; c.battle=nil
            end
        end,
        send_ipc_message=function(s)
            for _,peer in ipairs(lab.clients) do
                if peer~=c and peer.pc then peer.pc.callbacks['ipc message'](s) end
            end
        end,
        ffxi={get_player=function() return c.player end,
            get_party=c.environment.windower.ffxi.get_party,
            get_mob_array=function() return c.mobs end,
            get_mob_by_id=c.environment.windower.ffxi.get_mob_by_id,
            get_mob_by_target=function(token)
                if token=='me' then return self_mob end
                if token=='bt' then return c.battle end
                if token=='t' then return c.current_target end
            end,
            run=function() end,turn=function() end},
    }
    local chunk,err=loadfile('addons/PartyCombat/PartyCombat.lua','t',env)
    assert(chunk,err)()
    c.command_sink=function(command)
        local delay=0
        for part in command:gmatch('[^;]+') do
            part=part:match('^%s*(.-)%s*$')
            local wait=part:match('^wait%s+(%d+%.?%d*)$')
            if wait then delay=delay+tonumber(wait)
            elseif part:match('^pc%s+') then
                queue[#queue+1]={at=lab.now()+delay,client=c,args=words(part:sub(4))}
            end
        end
    end
end
for _,c in ipairs(lab.clients) do attach(c) end
local function drain()
    local pending=queue; queue={}
    for _,entry in ipairs(pending) do
        if entry.at<=lab.now() then entry.client.pc.callbacks['addon command'](unpack_values(entry.args))
        else queue[#queue+1]=entry end
    end
end
local function tick(seconds)
    lab.tick(seconds); drain()
    for _,c in ipairs(lab.clients) do c.pc.callbacks.prerender() end
end
local dolo=lab.named('Dolomedes')
local function assert_policy(expected)
    for _,c in ipairs(lab.clients) do
        c.pc.callbacks['addon command']('status')
        assert(c.pc.chats[#c.pc.chats-1]:find('Policy '..expected..' |',1,true),
            'Real consumer has wrong policy: '..c.player.name)
    end
end
for _,c in ipairs(lab.clients) do c.zone=275 end
lab.fire(dolo,'addon command','sortie-boss-skomora-v1')
for i=1,8 do tick(0.5) end
assert_policy('pt-sortie-skomora')
local old_target={id=50000,index=500,name='Skomora',spawn_type=16,
    valid_target=true,hpp=100,claim_id=0,distance=4,x=2,y=0,z=0}
for _,c in ipairs(lab.clients) do c.mobs[500]=old_target; c.current_target=old_target end
lab.fire(dolo,'addon command','force')
tick(0.5)
old_target.claim_id=lab.named('Tackleberry').player.id
local opener={actor_id=old_target.claim_id,category=1,
    targets={{id=old_target.id,actions={{message=1,param=100}}}}}
for _,c in ipairs(lab.clients) do
    lab.fire(c,'action',opener); c.pc.callbacks.action(opener)
end
for i=1,6 do tick(0.5) end
for _,c in ipairs(lab.clients) do
    assert(c.player.status==1,'Sortie did not engage real consumer '..c.player.name)
end
print('TRACE real PartyCombat initial Sortie engagement=6')
lab.hold(function(message)
    return message:find('PARTYTACTICS1|stop|',1,true)==1
end)
lab.fire(dolo,'addon command','off')
local old_stops=lab.release()
assert(#old_stops>=5,'No real old-profile stop messages captured')
for i=1,4 do tick(0.5) end
lab.fire(dolo,'addon command','locus')
for i=1,10 do tick(0.5) end
assert_policy('pt-locus-bats')
local target={id=50001,index=501,name='Locus Dire Bat',spawn_type=16,
    valid_target=true,hpp=100,claim_id=dolo.player.id,distance=4,x=2,y=0,z=0}
for _,c in ipairs(lab.clients) do c.mobs[target.index]=target; c.current_target=target end
-- Use the coordinator's public force command, not a fixture-invented success.
lab.fire(dolo,'addon command','force')
for i=1,6 do tick(0.5) end
local engaged={}
for _,c in ipairs(lab.clients) do
    if c.player.status==1 then engaged[#engaged+1]={client=c,stops=c.pc.stops} end
end
assert(#engaged==6,'Consumer lab did not establish all six replacement-profile engagements')
print('TRACE real PartyCombat engaged consumers='..#engaged)
for _,entry in ipairs(old_stops) do lab.fire(entry.recipient,'ipc message',entry.message) end
if inject_fault then
    -- Sensitivity control: model a leaked, unfenced old-owner command at the
    -- transport boundary. Real PartyCombat must execute it; the same assertion
    -- below must catch the resulting stop. This is not the historical cause.
    print('INJECTED FAULT: leaked old-owner OFF reaches real PartyCombat')
    engaged[1].client.pc.callbacks['addon command']('off')
end
for i=1,12 do tick(0.5) end
for _,entry in ipairs(engaged) do
    assert(entry.client.pc.stops==entry.stops and entry.client.player.status==1,
        'STALE_SORTIE_DISRUPTED_REPLACEMENT: '..entry.client.player.name)
end
assert_policy('pt-locus-bats')
lab.fire(dolo,'addon command','off')
for i=1,4 do tick(0.5) end
for _,entry in ipairs(engaged) do
    assert(entry.client.player.status==0,'Explicit operator stop failed in real consumer')
end
print('PASS - real coordinator/consumer stale Sortie stop isolation and explicit stop')
