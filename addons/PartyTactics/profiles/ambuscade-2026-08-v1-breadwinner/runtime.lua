local M = {}

local WARBLE_ALERTS = {
    ['Fire Meeble Warble']='FIRE WARBLE: Barney -> Barfira; expect Plague/Burn.',
    ['Blizzard Meeble Warble']='ICE WARBLE: Barney -> Barblizzara; expect Paralyze/Frost.',
    ['Thunder Meeble Warble']='THUNDER WARBLE: Barney -> Barthundra; expect Stun/Shock.',
    ['Stone Meeble Warble']='STONE WARBLE: Barney -> Barstonra; expect Petrify/Rasp.',
    ['Water Meeble Warble']='WATER WARBLE: Barney -> Barwatera; expect Poison/Drown.',
    ['Aero Meeble Warble']='WIND WARBLE: Barney -> Baraera; expect Silence/Choke.',
    ['Meeble Warble']='WARBLE ready: element was not exposed by the action resource.',
}

local function ability_from_action(ctx, action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = ctx.monster_ability(result.param)
                if ability then return ability, 'ready' end
            end
        end
    elseif action.category == 6 or action.category == 11 then
        return ctx.monster_ability(action.param), 'complete'
    end
    return nil
end

function M.create()
    local self = {alerts={}, next_housemaker_poll=0, housemakers={}}

    function self:on_action(ctx, action)
        local ability, phase = ability_from_action(ctx, action)
        local actor = ability and ctx.mob_by_id(action.actor_id) or nil
        if not actor or type(actor.name) ~= 'string' then return end
        local message
        if actor.name == 'Bozzetto Breadwinner' then
            if WARBLE_ALERTS[ability.en] and ability.en ~= 'Meeble Warble'
                and ctx.player_job() == 'BRD'
            then
                ctx.actions.controller('brd',
                    phase == 'ready' and 'warble' or 'warblecomplete', ability.id)
            end
            message = WARBLE_ALERTS[ability.en]
            if ability.en == 'Hundred Fists' then
                message = 'HUNDRED FISTS: reserved PLD mitigation is activating; Gale Spikes can reflect damage.'
            elseif ability.en == 'Drill Claw' then
                message = 'DRILL CLAW: FRONTAL CONE + 75% MAX HP DOWN. KEEP BREADWINNER FACING THE WALL.'
            end
        elseif actor.name:lower():find('housemaker', 1, true)
            and type(ability.en) == 'string'
            and ability.en:find('Earthshaker', 1, true)
        then
            message = 'HOUSEMAKER EARTHSHAKER: BARNEY RETURN TO GROUP FOR CURE/PARALYNA.'
        end
        if not message then return end
        local key = tostring(actor.id)..':'..tostring(ability.id)
        local now = ctx.now()
        if now - (self.alerts[key] or 0) < 6 then return end
        self.alerts[key] = now
        ctx.alert(message, false)
    end

    function self:on_tick(ctx, now)
        if now < self.next_housemaker_poll then return end
        self.next_housemaker_poll = now + 0.20
        for index, mob in pairs(ctx.mob_array() or {}) do
            if type(mob) == 'table' and type(mob.name) == 'string'
                and mob.name:lower():find('housemaker', 1, true)
                and tonumber(mob.x) and tonumber(mob.y)
            then
                local key = tostring(mob.id or index)
                local tracked = self.housemakers[key]
                if not tracked then
                    self.housemakers[key] = {
                        home_x=tonumber(mob.x), home_y=tonumber(mob.y), away=false,
                    }
                else
                    local dx = tonumber(mob.x) - tracked.home_x
                    local dy = tonumber(mob.y) - tracked.home_y
                    local distance = math.sqrt(dx * dx + dy * dy)
                    if not tracked.away and distance >= 0.75 then
                        tracked.away = true
                        ctx.alert('HOUSEMAKER MOVING: BARNEY SEPARATE NOW; EVERYONE ELSE STAY PUT.', true)
                    elseif tracked.away and distance <= 0.35 then
                        tracked.away = false
                        ctx.alert('HOUSEMAKER RETURNED: BARNEY RETURN TO GROUP; CURE/PARALYNA, THEN BARS.', false)
                    end
                end
            end
        end
    end

    return self
end

return M
