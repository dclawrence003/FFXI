-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
-- Real coordinators and stable GearSwap hosts; helper readiness remains mocked.
PARTYTACTICS_EXPORT_FIXTURE=true
local lab=assert(loadfile('addons/PartyTactics/tests/test_six_client_activation.lua'))()
PARTYTACTICS_EXPORT_FIXTURE=nil
local unpack_values=table.unpack or unpack
local held={}
local hold=false
local fault=arg and arg[1]=='--drop-host-ack'
local replies=0
local function words(s)
    local t={}; for w in s:gmatch('%S+') do t[#t+1]=w end; return t
end
local function deliver(c,s)
    local t=words(s)
    assert(table.remove(t,1)=='pt','Unexpected host command: '..s)
    lab.fire(c,'addon command',unpack_values(t))
end
for _,c in ipairs(lab.clients) do
    c.host_probe_enabled=false -- Never synthesize host success in this fixture.
    local env=setmetatable({}, {__index=_G})
    env._G=env
    env.include=function() error('Ordinary Locus must not load a fight adapter') end
    env.windower={raw_register_event=function() end,add_to_chat=function() end,
        send_command=function(s)
            assert(s:match('^pt __gearswap_host_ready '),'Unexpected host output: '..s)
            replies=replies+1
            if fault and c.player.name=='Achoo' then
                print('INJECTED FAULT: dropped actual host reply')
            elseif hold then held[#held+1]={client=c,message=s}
            else deliver(c,s) end
        end}
    local loader,err
    if setfenv then
        loader,err=loadfile('addons/PartyTactics/gearswap/PartyTactics_Host.lua')
        if loader then setfenv(loader,env) end
    else loader,err=loadfile('addons/PartyTactics/gearswap/PartyTactics_Host.lua','t',env) end
    assert(loader,err)()
    c.command_sink=function(s)
        if s:match('^gs c ptgs probe ') then
            local t=words(s); table.remove(t,1); table.remove(t,1)
            local event={}
            env.user_job_self_command(t,event)
            assert(event.handled,'Actual host did not handle coordinator probe')
        end
    end
end
local leader=lab.named('Dolomedes')
local function status_contains(needle)
    local start=#leader.chats
    lab.fire(leader,'addon command','status')
    for i=start+1,#leader.chats do
        if leader.chats[i].message:find(needle,1,true) then return true end
    end
    return false
end
local function on_count()
    local n=0
    for _,c in ipairs(lab.clients) do
        for _,s in ipairs(c.commands) do if s=='pc on' then n=n+1 end end
    end
    return n
end
lab.fire(leader,'addon command','use','locus')
lab.tick(2.1)
assert(replies>=6,'Actual hosts were not probed on every client')
assert(status_contains('acks 6/6'),'HOST_READINESS_FAILURE: actual host replies missing')
lab.fire(leader,'addon command','off')
hold=true
lab.fire(leader,'addon command','use','locus')
lab.tick(2.1)
assert(#held>=6,'No actual host replies retained for delay test')
assert(not status_contains('acks 6/6'),'Missing host replies falsely reported full readiness')
lab.fire(leader,'addon command','off')
local before=on_count()
hold=false
for _,item in ipairs(held) do deliver(item.client,item.message) end
lab.tick(6)
assert(on_count()==before,'Late host reply restarted combat after stop')
assert(not status_contains('acks 6/6'),'Retired host replies falsely restored full readiness')
lab.fire(leader,'addon command','use','locus')
lab.tick(2.1)
assert(status_contains('acks 6/6'),'Fresh host replies failed after retired generation')
print('PASS - real coordinator host readiness and stopped late replies')
