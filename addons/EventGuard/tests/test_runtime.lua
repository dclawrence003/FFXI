-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
-- Actual EventGuard; packets and persisted menu data stay in memory.
local callbacks,outgoing,incoming={}, {}, {}
local zone=100
local saved=nil
local noop=function() end
_addon={}
string.pack=function() return 'simulated packet bytes' end
local packets={parse=function(_,value) return value end,
    new=function(direction,id,fields) fields.id=id; return fields end,
    inject=function(value) outgoing[#outgoing+1]=value end}
require=function(name)
    if name=='packets' then return packets end
    assert(name=='strings' or name=='coroutine'); return true
end
coroutine.schedule=noop
io.open=function(_,mode)
    if mode=='r' and not saved then return nil end
    return {write=function(_,value) saved=value end,
        read=function() return saved end,close=noop}
end
windower={windower_path='SIMULATED/',add_to_chat=noop,
    register_event=function(name,fn) callbacks[name]=fn end,
    ffxi={get_player=function() return {name='Fixture',id=1,status=0} end,
        get_info=function() return {zone=zone} end},
    packets={inject_incoming=function(id,value) incoming[#incoming+1]={id,value} end}}
assert(loadfile('addons/EventGuard/EventGuard.lua'))()
callbacks['addon command']('menu')
assert(#outgoing==0 and #incoming==0,'Missing menu caused recovery packets')
callbacks['incoming chunk'](0x034,nil,{NPC=123,['NPC Index']=12,Zone=100,['Menu ID']=456})
assert(saved and #outgoing==0,'Passive menu observation did not remain passive')
zone=101
callbacks['addon command']('menu')
assert(#outgoing==0 and #incoming==0,'Stale-zone menu caused cancellation')
zone=100
callbacks['addon command']('menu')
assert(#outgoing==1 and outgoing[1].id==0x05B and outgoing[1].Target==123
    and outgoing[1].Zone==100 and outgoing[1]['Menu ID']==456,'Wrong menu cancelled')
assert(#incoming==3,'Expected local release sequence missing')
callbacks['addon command']('local')
assert(#incoming==3,'Local status repair ignored confirmation requirement')
print('PASS EventGuard passive recording, stale-zone refusal and exact menu cancellation')
