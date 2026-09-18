local source=debug.getinfo(1,'S').source:gsub('^@','')
local test_dir=source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path=arg and arg[1] or (test_dir..'/../gearswap/adapters/'
    ..'sortie-objective-a-magic-kill-v1/1.1.0.lua')

local function shallow(value)
    local out={}; for key,entry in pairs(value) do out[key]=entry end
    return out
end

local function world(job,options)
    options=options or {}
    local clock=100
    local inputs,commands={},{}
    local identities={PLD={id=1002,name='Tackleberry'},
        RDM={id=1005,name='Smalls'}}
    local identity=assert(identities[job])
    local player={id=identity.id,name=identity.name,main_job=job,
        status='Engaged',mp=1500,tp=3000}
    local target={id=17990001,index=411,name=options.name or 'Abject Acuex',
        claim_id=1001,spawn_type=16,valid_target=true,hpp=31,
        distance=4,model_size=1.5}
    local party={p0={name='Dolomedes',mob={id=1001}},
        p1={name='Tackleberry',mob={id=1002}},
        p4={name='Smalls',mob={id=1005}},p5={name='Achoo',mob={id=1006}}}
    local recasts={[146]=0,[147]=0,[148]=0}
    local busy=options.busy==true
    local env=setmetatable({}, {__index=_G}); env._G=env
    env.PARTYTACTICS_SORTIE_A_MAGIC_TEST_MODE=true
    env.os=setmetatable({clock=function() return clock end},{__index=os})
    env.player=player; env.moving=false; env.tickdelay=0; env.next_cast=0
    env.latency=1; env.spell_latency=1
    env.midaction=function() return busy end
    env.silent_check_disable=function() return false end
    env.silent_can_use=function() return true end
    env.res={
        weapon_skills={
            [34]={id=34,en='Red Lotus Blade'},
            [35]={id=35,en='Flat Blade'},
        },
        spells={
            [146]={id=146,en='Fire III',recast_id=146,mp_cost=64},
            [147]={id=147,en='Fire IV',recast_id=147,mp_cost=119},
            [148]={id=148,en='Fire V',recast_id=148,mp_cost=156},
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
                return token=='bt' and shallow(target) or nil
            end,
            get_party=function() return party end,
            get_abilities=function() return {weapon_skills={34,35},job_abilities={}} end,
            get_spells=function() return {[146]=true,[147]=true,[148]=true} end,
            get_spell_recasts=function() return recasts end,
        }}
    local loader,load_error
    if setfenv then
        loader,load_error=loadfile(adapter_path); if loader then setfenv(loader,env) end
    else loader,load_error=loadfile(adapter_path,'t',env) end
    assert(loader,load_error)
    local adapter=loader(); assert(adapter.activate()==true)
    local w={adapter=adapter,state=adapter._test_state,inputs=inputs,
        commands=commands,player=player,target=target,recasts=recasts,
        generation='1700000000-1001-1',epoch='0'}
    function w:set_busy(value) busy=value==true end
    function w:advance(seconds) clock=clock+seconds end
    function w:command(semantic,token)
        return self.adapter.handle_action('sortie-a-magic',semantic,
            {tostring(self.target.id),self.generation,self.epoch,token or 'lane'})
    end
    return w
end

local tests={}
local function test(name,callback) tests[#tests+1]={name=name,callback=callback} end

test('manual hooks are unconditional pass-through',function()
    local w=world('RDM')
    assert(w.adapter.filter_pretarget()==false)
    assert(w.adapter.filter_precast()==false)
    assert(w.adapter.pre_tick()==false)
end)

test('busy finisher queues survive and Fire V wins priority',function()
    local w=world('RDM',{busy=true})
    assert(w:command('fire-iv','low')==true)
    assert(w:command('fire-v','high')==true)
    assert(#w.inputs==0)
    assert(w.state.pending['fire-v'] and w.state.pending['fire-iv'])
    assert(w.state.pending['fire-v'].job=='RDM',
        tostring(w.state.pending['fire-v'].job))
    assert(w.adapter._test_actions.RDM['fire-v'])
    w:set_busy(false); w:advance(0.2); w.adapter.pre_tick()
    assert(w.inputs[1]=='/ma "Fire V" '..tostring(w.target.id),
        tostring(w.inputs[1])..' | '..w.adapter.status())
    w:advance(0.2); w.adapter.pre_tick()
    assert(w.inputs[2]=='/ma "Fire IV" '..tostring(w.target.id))
end)

test('PLD opener and every RDM chain or Fire action dispatch exact IDs',function()
    for _,case in ipairs{{'PLD','flat-blade'},
        {'RDM','red-lotus-blade'},{'RDM','fire-v'},
        {'RDM','fire-iv'},{'RDM','fire-iii'}} do
        local w=world(case[1])
        assert(w:command(case[2])==true)
        assert(#w.inputs==1,w.adapter.status())
        assert(w.inputs[1]:find(tostring(w.target.id),1,true))
    end
end)

test('foreign targets, zones, claims, and malformed authority fail closed',function()
    local foreign=world('RDM',{name='Abject Leech'})
    assert(foreign:command('fire-v')==false and #foreign.inputs==0)
    local zone=world('RDM',{zone=267})
    assert(zone:command('fire-v')==false and #zone.inputs==0)
    local claim=world('RDM'); claim.target.claim_id=0
    assert(claim:command('fire-v')==false and #claim.inputs==0)
    local bad=world('RDM'); bad.generation='bad;command'
    assert(bad:command('fire-v')==false and #bad.inputs==0)
end)

test('blocked work is cancellable and expires without touching input',function()
    local w=world('RDM',{busy=true})
    assert(w:command('fire-v')==true)
    assert(w.adapter.handle_action('sortie-a-magic','cancel',
        {tostring(w.target.id),w.generation,w.epoch})==true)
    assert(next(w.state.pending)==nil)
    assert(w:command('fire-v','retry')==true)
    w:set_busy(false); w:advance(10.1); w.adapter.pre_tick()
    assert(next(w.state.pending)==nil and w.state.expired==1)
end)

for _,entry in ipairs(tests) do
    local ok,failure=pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end
io.write(('Sortie A magic-kill adapter tests passed: %d\n'):format(#tests))
