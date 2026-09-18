-- Actual addon; simulated inventory and scheduled/client boundaries.
-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
local callbacks,commands,chats,scheduled={},{},{},{}
local now=100
local inventory={max=80,count=1,[1]={id=5365,count=1,status=0}}
local noop=function() end
os.clock=function() return now end
require=function(name)
    assert(name=='config')
    return {load=function(defaults) defaults.save=noop; return defaults end}
end
coroutine.schedule=function(fn) scheduled[#scheduled+1]=fn end
windower={register_event=function(name,fn) callbacks[name]=fn end,
    add_to_chat=function(_,s) chats[#chats+1]=s end,send_ipc_message=noop,
    send_command=function(s) commands[#commands+1]=s end,
    ffxi={get_info=function() return {zone=73} end,
        get_player=function() return {name='Dolomedes'} end,
        get_party=function() return {} end,
        get_items=function(bag) return bag=='inventory' and inventory or {} end,
        drop_item=function() error('Unexpected drop') end,
        lot_item=function() error('Unexpected lot') end,
        pass_item=function() error('Unexpected pass') end}}
assert(loadfile('addons/SalvageCells/SalvageCells.lua'))()
callbacks.load()
assert(#commands==0,'Mid-run load consumed a cell before state was known')
callbacks['addon command']('begin')
for _,fn in ipairs(scheduled) do fn() end
assert(#commands==1 and commands[1]=='input /item "Incus Cell" <me>',
    'Fresh run did not request the expected cell')
callbacks['addon command']('status')
assert(chats[#chats]:find('20 unlocks remaining',1,true),'Unconfirmed use was treated as consumption')
now=now+1
callbacks.prerender()
assert(#commands==1,'Pending use was duplicated')
inventory[1]=nil
now=now+1
callbacks.prerender()
callbacks['addon command']('status')
assert(chats[#chats]:find('19 unlocks remaining',1,true),'Inventory decrement was not recognized')
inventory[2]={id=5374,count=1,status=0}
callbacks['addon command']('off')
now=now+10
callbacks.prerender()
assert(#commands==1,'Paused addon issued a new cell action')
print('PASS SalvageCells unknown-state hold, inventory confirmation and explicit pause')
