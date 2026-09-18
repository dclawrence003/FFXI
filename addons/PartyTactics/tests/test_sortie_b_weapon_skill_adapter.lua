local source=debug.getinfo(1,'S').source:gsub('^@','')
local test_dir=source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path=arg and arg[1] or (test_dir..'/../gearswap/adapters/'
    ..'sortie-objective-b-weapon-skill-v1/1.0.0.lua')

local function shallow(value)
    local out={}; for key,entry in pairs(value) do out[key]=entry end
    return out
end

local function world(job,options)
    options=options or {}
    local clock=100
    local inputs={}
    local identities={COR={1001,'Dolomedes'},PLD={1002,'Tackleberry'},
        DNC={1003,'Kickpuncher'},BRD={1004,'Barneystinson'},
        RDM={1005,'Smalls'},GEO={1006,'Achoo'}}
    local identity=assert(identities[job])
    local player={id=identity[1],name=identity[2],main_job=job,
        status=options.engaged==false and 'Idle' or 'Engaged',
        mp=1500,tp=options.tp or 3000}
    local target={id=17990002,index=412,
        name=options.name or 'Biune Fire Elemental',
        claim_id=options.unclaimed and 0 or 1001,spawn_type=16,
        valid_target=true,hpp=40,distance=4,model_size=1.5}
    local busy=options.busy==true
    local party={}
    for index,entry in ipairs{
        {1001,'Dolomedes'},{1002,'Tackleberry'},
        {1003,'Kickpuncher'},{1004,'Barneystinson'},
        {1005,'Smalls'},{1006,'Achoo'},
    } do party['p'..tostring(index-1)]={name=entry[2],mob={id=entry[1]}} end
    local env=setmetatable({}, {__index=_G}); env._G=env
    env.PARTYTACTICS_SORTIE_B_WS_TEST_MODE=true
    env.os=setmetatable({clock=function() return clock end},{__index=os})
    env.player=player; env.moving=false; env.tickdelay=0; env.next_cast=0
    env.midaction=function() return busy end
    env.silent_check_disable=function() return false end
    env.res={weapon_skills={
        [25]={id=25,en='Evisceration'},
        [42]={id=42,en='Savage Blade'},
        [169]={id=169,en='Black Halo'},
    },spells={}}
    env.windower={chat={input=function(command) inputs[#inputs+1]=command end},
        send_command=function() end,
        ffxi={
            get_player=function() return shallow(player) end,
            get_info=function() return {logged_in=true,zone=options.zone or 275} end,
            get_mob_by_id=function(id)
                return tonumber(id)==target.id and shallow(target) or nil
            end,
            get_mob_by_target=function(token)
                return token=='bt' and shallow(target) or nil
            end,
            get_party=function() return party end,
            get_abilities=function()
                return {weapon_skills={25,42,169},job_abilities={}}
            end,
            get_spells=function() return {} end,
            get_spell_recasts=function() return {} end,
        }}
    local loader,load_error
    if setfenv then
        loader,load_error=loadfile(adapter_path); if loader then setfenv(loader,env) end
    else loader,load_error=loadfile(adapter_path,'t',env) end
    assert(loader,load_error)
    local adapter=loader(); assert(adapter.activate()==true)
    local w={adapter=adapter,state=adapter._test_state,inputs=inputs,
        player=player,target=target,generation='1700000000-1001-1',epoch='0'}
    function w:set_busy(value) busy=value==true end
    function w:advance(seconds) clock=clock+seconds end
    function w:command(semantic,token)
        return self.adapter.handle_action('sortie-b-ws',semantic,
            {tostring(self.target.id),self.generation,self.epoch,token or 'lane'})
    end
    return w
end

local tests={}
local function test(name,callback) tests[#tests+1]={name=name,callback=callback} end

test('manual hooks always pass through',function()
    local w=world('COR')
    assert(w.adapter.filter_pretarget()==false)
    assert(w.adapter.filter_precast()==false)
    assert(w.adapter.pre_tick()==false)
end)

test('every party job dispatches its pinned learned weapon skill',function()
    for _,case in ipairs{
        {'COR','savage-blade','Savage Blade'},
        {'PLD','savage-blade','Savage Blade'},
        {'DNC','evisceration','Evisceration'},
        {'BRD','savage-blade','Savage Blade'},
        {'RDM','black-halo','Black Halo'},
        {'GEO','black-halo','Black Halo'},
    } do
        local w=world(case[1])
        assert(w:command(case[2])==true,w.adapter.status())
        assert(w.inputs[1]==('/ws "%s" %d'):format(case[3],w.target.id),
            tostring(w.inputs[1]))
    end
end)

test('all eight exact Biune elemental names are accepted',function()
    for _,element in ipairs{
        'Fire','Ice','Air','Earth','Thunder','Water','Light','Dark',
    } do
        local w=world('COR',{name='Biune '..element..' Elemental'})
        assert(w:command('savage-blade')==true,element)
        assert(#w.inputs==1,element)
    end
end)

test('lookalikes zones claims TP and engagement fail closed',function()
    for _,name in ipairs{
        'Biune Elemental','Biune Fake Elemental','Abject Acuex',
    } do
        local w=world('COR',{name=name})
        assert(w:command('savage-blade')==false and #w.inputs==0,name)
    end
    local zone=world('COR',{zone=267})
    assert(zone:command('savage-blade')==false and #zone.inputs==0)
    local claim=world('COR',{unclaimed=true})
    assert(claim:command('savage-blade')==false and #claim.inputs==0)
    local tp=world('COR',{tp=999})
    assert(tp:command('savage-blade')==true and #tp.inputs==0)
    local idle=world('COR',{engaged=false})
    assert(idle:command('savage-blade')==true and #idle.inputs==0)
end)

test('blocked work remains queued and is cancellable or expiring',function()
    local w=world('RDM',{busy=true})
    assert(w:command('black-halo')==true and #w.inputs==0)
    assert(w.state.pending['black-halo'])
    w:set_busy(false); w:advance(0.2); w.adapter.pre_tick()
    assert(w.inputs[1]=='/ws "Black Halo" '..tostring(w.target.id))

    local cancelled=world('DNC',{busy=true})
    assert(cancelled:command('evisceration')==true)
    assert(cancelled.adapter.handle_action('sortie-b-ws','cancel',
        {tostring(cancelled.target.id),cancelled.generation,
            cancelled.epoch})==true)
    assert(next(cancelled.state.pending)==nil)
    assert(cancelled:command('evisceration','retry')==true)
    cancelled:set_busy(false); cancelled:advance(7.1)
    cancelled.adapter.pre_tick()
    assert(next(cancelled.state.pending)==nil and cancelled.state.expired==1)
end)

for _,entry in ipairs(tests) do
    local ok,failure=pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end
io.write(('Sortie B weapon-skill adapter tests passed: %d\n'):format(#tests))
