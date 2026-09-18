local source=debug.getinfo(1,'S').source:gsub('^@','')
local test_dir=source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path=arg and arg[1] or (test_dir
    ..'/../gearswap/adapters/sortie-main-v1/1.2.0.lua')

local function shallow(value)
    local out={}; for key,entry in pairs(value) do out[key]=entry end
    return out
end

local IDS={COR=1001,PLD=1002,DNC=1003,BRD=1004,RDM=1005,GEO=1006}
local NAMES={COR='Dolomedes',PLD='Tackleberry',DNC='Kickpuncher',
    BRD='Barneystinson',RDM='Smalls',GEO='Achoo'}

local function world(job,options)
    options=options or {}
    local clock=100
    local inputs,commands={},{ }
    local player={id=IDS[job],name=NAMES[job],main_job=job,
        sub_job=options.sub_job or 'WHM',
        status=options.status or 'Engaged',mp=1500,tp=3000,
        buffs=options.buffs or {}}
    local target={id=17990001,index=411,name=options.name or 'Skomora',
        claim_id=1001,spawn_type=16,valid_target=true,hpp=100,
        distance=4,model_size=1.5}
    local party={p0={name='Dolomedes',mob={id=1001}},
        p1={name='Tackleberry',mob={id=1002}},
        p2={name='Kickpuncher',mob={id=1003}},
        p3={name='Barneystinson',mob={id=1004}},
        p4={name='Smalls',mob={id=1005}},p5={name='Achoo',mob={id=1006}}}
    local busy=options.busy==true
    local env=setmetatable({}, {__index=_G}); env._G=env
    env.PARTYTACTICS_SORTIE_MAIN_TEST_MODE=true
    env.os=setmetatable({clock=function() return clock end},{__index=os})
    env.player=player; env.moving=false; env.tickdelay=0; env.next_cast=0
    env.latency=1; env.spell_latency=1
    env.midaction=function() return busy end
    env.silent_check_disable=function() return false end
    env.silent_can_use=function() return true end
    env.res={
        weapon_skills={
            [25]={id=25,en='Evisceration'},[34]={id=34,en='Red Lotus Blade'},
            [35]={id=35,en='Flat Blade'},[42]={id=42,en='Savage Blade'},
            [169]={id=169,en='Black Halo'},
        },
        spells={
            [146]={id=146,en='Fire III',recast_id=146,mp_cost=64},
            [147]={id=147,en='Fire IV',recast_id=147,mp_cost=119},
            [164]={id=164,en='Thunder',recast_id=164,mp_cost=25},
            [465]={id=465,en='Chocobo Mazurka',recast_id=465,mp_cost=0},
        },
    }
    env.windower={chat={input=function(command) inputs[#inputs+1]=command end},
        send_command=function(command) commands[#commands+1]=command end,
        ffxi={
            get_player=function() return shallow(player) end,
            get_info=function() return {logged_in=true,zone=options.zone or 275} end,
            get_mob_by_id=function(id)
                return tonumber(id)==target.id and shallow(target) or nil
            end,
            get_mob_by_target=function(token)
                return (token=='bt' or token=='t') and shallow(target) or nil
            end,
            get_party=function() return party end,
            get_abilities=function()
                return {weapon_skills={25,34,35,42,169},
                    job_abilities=options.last_resort and {51} or {}}
            end,
            get_ability_recasts=function() return {[87]=0} end,
            get_spells=function()
                return {[146]=true,[147]=true,[164]=true,[465]=true}
            end,
            get_spell_recasts=function()
                return {[146]=0,[147]=0,[164]=0,[465]=0}
            end,
        }}
    local loader,load_error
    if setfenv then
        loader,load_error=loadfile(adapter_path)
        if loader then setfenv(loader,env) end
    else loader,load_error=loadfile(adapter_path,'t',env) end
    assert(loader,load_error)
    local adapter=loader(); assert(adapter.activate()==true)
    local w={adapter=adapter,state=adapter._test_state,inputs=inputs,
        commands=commands,player=player,target=target,
        generation='1700000000-1001-1',epoch='0'}
    if options.hold_poll then w.state.next_poll=math.huge end
    function w:advance(seconds) clock=clock+seconds end
    function w:set_busy(value) busy=value==true end
    function w:command(semantic,token)
        return self.adapter.handle_action('sortie-main',semantic,
            {tostring(self.target.id),self.generation,self.epoch,token})
    end
    return w
end

local tests={}
local function test(name,callback) tests[#tests+1]={name=name,callback=callback} end

test('every combat action dispatches an exact live target',function()
    for _,case in ipairs{
        {'COR','savage-blade'},{'PLD','flat-blade'},
        {'DNC','evisceration'},{'BRD','savage-blade'},
        {'RDM','red-lotus-blade'},{'RDM','fire-iv'},
        {'RDM','fire-iii'},{'RDM','thunder'},
        {'GEO','black-halo'},{'GEO','thunder'},
    } do
        local w=world(case[1],{busy=true,hold_poll=true})
        assert(w:command(case[2],'lane')==true,w.adapter.status())
        assert(w.state.pending[case[2]],w.adapter.status())
        assert(w.state.pending[case[2]].job==case[1],
            tostring(w.state.pending[case[2]].job))
        w.state.next_poll=0
        w:set_busy(false); w:advance(0.2); w.adapter.pre_tick()
        assert(#w.inputs==1,w.adapter.status())
        assert(w.inputs[1]:find(tostring(w.target.id),1,true),w.inputs[1])
    end
end)

test('busy actions queue and cancel without consuming manual input',function()
    local w=world('RDM',{busy=true})
    assert(w:command('fire-iv','fire')==true and #w.inputs==0)
    assert(w.state.pending['fire-iv'])
    assert(w.adapter.handle_action('sortie-main','cancel',
        {tostring(w.target.id),w.generation,w.epoch})==true)
    assert(next(w.state.pending)==nil and #w.inputs==0)
    assert(w.adapter.filter_pretarget()==false)
    assert(w.adapter.filter_precast()==false)
end)

test('combat and delayed movement modes are local support changes',function()
    local cor=world('COR')
    assert(cor:command('combat-mode')==true)
    assert(cor.commands[1]=='cancel 219')
    assert(cor.commands[2]=='r2 roll1 chaos; r2 roll2 samurai; r2 on')
    assert(cor:command('movement-mode')==true)
    cor:advance(5.9); cor.adapter.pre_tick()
    assert(#cor.commands==2)
    cor:advance(0.2); cor.adapter.pre_tick()
    assert(cor.commands[3]=='r2 roll1 bolter; r2 roll2 tactician; r2 on')

    local brd=world('BRD',{status='Idle'})
    brd:advance(1.1); brd.adapter.pre_tick()
    assert(brd.inputs[1]=='/ma "Chocobo Mazurka" <me>')
end)

test('Leshonn support is exact-target safe and restores by ordinary mode',function()
    local wrong=world('BRD',{name='Skomora'})
    assert(wrong:command('leshonn-mode')==false)
    assert(#wrong.commands==0)

    local brd=world('BRD',{name='Leshonn'})
    assert(brd:command('leshonn-mode')==true)
    assert(brd.commands[1]=='cancel 219')
    assert(brd.commands[2]=='gs c pstartbrd magicboss Tackleberry')
    assert(brd.adapter.filter_pretarget()==false)
    assert(brd.adapter.filter_precast()==false)
    assert(brd.adapter.user_job_tick()==true)
    -- A different party member can improvise onto another target before
    -- local target synchronization reaches this client.  Ordinary combat
    -- must not briefly restore Elegy-capable support while Leshonn remains
    -- selected locally.
    assert(brd:command('combat-mode')==true)
    assert(brd.commands[#brd.commands]
        =='gs c pstartbrd magicboss Tackleberry')
    brd.target.name='Skomora'
    brd:advance(0.2); brd.adapter.pre_tick()
    assert(brd.commands[#brd.commands]
        =='gs c pstartbrd physical Tackleberry')

    local pld=world('PLD',{name='Leshonn'})
    assert(pld:command('leshonn-mode')==true)
    assert(pld.commands[2]
        =='gs c set AutoBuffMode Off; gs c unset AutoTankMode; '
            ..'gs c unset AutoTankFull; gs c pstartpld manualsc Dolomedes')
    assert(pld:command('combat-mode')==true)
    assert(pld.commands[#pld.commands]
        =='gs c set AutoBuffMode Off; gs c unset AutoTankMode; '
            ..'gs c unset AutoTankFull; gs c pstartpld manualsc Dolomedes')
    pld.target.name='Skomora'
    pld:advance(0.2); pld.adapter.pre_tick()
    assert(pld.commands[#pld.commands]
        =='gs c set AutoBuffMode Auto; gs c set AutoTankMode; '
            ..'gs c unset AutoTankFull; gs c pstartpld locusbats Dolomedes')
end)

test('confirmed Wind offers Last Resort only to an actual DRK subjob',function()
    local drk=world('BRD',{name='Leshonn',sub_job='DRK',last_resort=true})
    assert(drk:command('leshonn-mode')==true)
    assert(drk:command('leshonn-wind-mode')==true)
    drk:advance(0.2); drk.adapter.pre_tick()
    assert(drk.inputs[#drk.inputs]=='/ja "Last Resort" <me>')
    drk.player.buffs={64}
    assert(drk:command('leshonn-thunder-mode')==true)
    drk:advance(0.2); drk.adapter.pre_tick()
    assert(drk.commands[#drk.commands]=='cancel 64')

    local whm=world('BRD',{name='Leshonn',sub_job='WHM',last_resort=true})
    assert(whm:command('leshonn-wind-mode')==true)
    assert(#whm.inputs==0)
end)

test('a new combat mode cancels a pending movement cast',function()
    local brd=world('BRD',{status='Idle'})
    assert(brd:command('movement-mode')==true)
    brd:advance(2); assert(brd:command('combat-mode')==true)
    brd:advance(10); brd.adapter.pre_tick()
    assert(#brd.inputs==0)
    assert(brd.commands[#brd.commands-1]=='cancel 219')
    assert(brd.commands[#brd.commands]
        =='gs c pstartbrd physical Tackleberry')
end)

test('Acuex weapon changes are RDM local and reversible',function()
    local w=world('RDM')
    assert(w:command('acuex-mode')==true)
    assert(w.commands[#w.commands]=='gs c weapons KajaSword')
    assert(w:command('normal-mode')==true)
    assert(w.commands[#w.commands]=='gs c weapons Maxentius')
end)

test('invalid target ownership and authority fail closed',function()
    local claim=world('RDM'); claim.target.claim_id=0
    assert(claim:command('fire-iv','x')==false and #claim.inputs==0)
    local zone=world('RDM',{zone=267})
    assert(zone:command('fire-iv','x')==false and #zone.inputs==0)
    local bad=world('RDM'); bad.generation='bad;command'
    assert(bad:command('fire-iv','x')==false and #bad.inputs==0)
end)

test('deactivation clears only this adapter state',function()
    local w=world('RDM',{busy=true})
    assert(w:command('fire-iv','x')==true)
    local command_count=#w.commands
    w.adapter.deactivate('profile changed')
    assert(next(w.state.pending)==nil)
    assert(w.state.pending_mode==nil and w.state.authority==nil)
    assert(#w.commands==command_count)
end)

for _,entry in ipairs(tests) do
    local ok,failure=pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end
io.write(('Persistent Sortie adapter tests passed: %d\n'):format(#tests))
