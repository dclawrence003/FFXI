-- Actual delayed Double-Up path; resource/client setup is simulated.
-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
local callbacks,scheduled,commands={},{},{}
local noop=function() end
_addon={}
debug.setmetatable(function() end,{__index={loop=noop}})
function S(values)
    return setmetatable(values,{__index={contains=function(self,v)
        for _,x in ipairs(self) do if x==v then return true end end
        return false
    end,map=function(self,fn)
        local out={}; for _,x in ipairs(self) do out[#out+1]=fn(x) end; return S(out)
    end}})
end
config={load=function(value) return value end,save=noop}
res={buffs={[309]={en='Double-Up Chance'}}}
require=function(name)
    assert(name=='luau' or name=='chat' or name=='chat.chars' or name=='packets' or name=='texts')
    return {}
end
coroutine.schedule=function(fn) scheduled[#scheduled+1]=fn end
windower={addon_path='./',add_to_chat=noop,
    register_event=function(name,fn) callbacks[name]=fn end,
    chat={input=function(s) commands[#commands+1]=s end},
    ffxi={get_player=function() return {buffs={309},main_job='COR'} end,
        get_ability_recasts=function() return {[194]=0} end}}
assert(loadfile('Roller2.lua'))()
-- Supply the initial state normally set by the resource-heavy load handler.
-- The actual delayed action and public stop handlers are not replaced.
autoroll=false
callbacks['addon command']('on')
begin_roll_sequence()
request_double_up('fixture positive control')
assert(#scheduled==1)
table.remove(scheduled,1)()
assert(commands[1]=='/ja "Double-Up" <me>','Actual Double-Up did not execute')
scheduled={}
begin_roll_sequence()
request_double_up('fixture stopped sequence')
local before=#commands
callbacks['addon command']('off')
for _,fn in ipairs(scheduled) do fn() end
assert(#commands==before and not autoroll,'Delayed Double-Up survived operator stop')
print('PASS Roller2 actual delayed action and operator stop fencing')
