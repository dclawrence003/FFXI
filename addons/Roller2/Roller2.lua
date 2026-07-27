	--Copyright (c) 2016, Selindrile
--All rights reserved.

--Redistribution and use in source and binary forms, with or without
--modification, are permitted provided that the following conditions are met:

--    * Redistributions of source code must retain the above copyright
--      notice, this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above copyright
--      notice, this list of conditions and the following disclaimer in the
--      documentation and/or other materials provided with the distribution.
--    * Neither the name of RollTracker nor the
--      names of its contributors may be used to endorse or promote products
--      derived from this software without specific prior written permission.

--THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
--ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
--WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
--DISCLAIMED. IN NO EVENT SHALL THOMAS ROGERS BE LIABLE FOR ANY
--DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
--(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
--LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
--ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
--SOFTWARE, EVEN IFIF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

_addon.name = 'Roller2'
_addon.version = '2.1.0-prototype'
_addon.author = 'Selindrile; Roller2 safety iteration by Codex'
_addon.commands = {'roller2','r2'}

require('luau')
chat = require('chat')
chars = require('chat.chars')
packets = require('packets')
texts = require('texts')
local decision = dofile(windower.addon_path .. 'Roller2Decision.lua')

defaults = {}
defaults.Roll_ind_1 = 8
defaults.Roll_ind_2 = 12
defaults.showdisplay = true
defaults.displayx = nil
defaults.displayy = nil
defaults.engaged = false
defaults.snakeeye_policy = 'conservative'
defaults.auto_random_deal = false
defaults.debug = false
zonedelay = 6
stealthy = ''
was_stealthy = ''

lastRollCrooked = false
midRoll = false
snakeEyeUsedThisRoll = false
snakeEyeRequestPending = false
snakeEyeCommandSent = false
snakeEyeDoubleUpPending = false
snakeEyeSequenceId = 0
rollSequenceActive = false
pendingRollAction = nil
lastDecision = 'Waiting'
lastDecisionTotal = nil
lastDecisionRoll = nil

settings = config.load(defaults)

local validSnakeEyePolicies = S{'conservative', 'balanced', 'aggressive'}

function reset_snake_eye_state()
	snakeEyeSequenceId = snakeEyeSequenceId + 1
	snakeEyeUsedThisRoll = false
	snakeEyeRequestPending = false
	snakeEyeCommandSent = false
	snakeEyeDoubleUpPending = false
	rollSequenceActive = false
	pendingRollAction = nil
	midRoll = false
end

function begin_roll_sequence()
	snakeEyeSequenceId = snakeEyeSequenceId + 1
	snakeEyeUsedThisRoll = false
	snakeEyeRequestPending = false
	snakeEyeCommandSent = false
	snakeEyeDoubleUpPending = false
	rollSequenceActive = true
	pendingRollAction = nil
	midRoll = false
end

function roll_policy()
	return decision.normalize_policy(settings.snakeeye_policy)
end

function snake_eye_policy()
	return roll_policy()
end

function snake_eye_policy_allows_reuse(rollNum)
	return decision.allows_snake_eye_reuse(
		roll_policy(), rollNum, snakeEyeUsedThisRoll)
end

function available_job_abilities()
	local abilities = windower.ffxi.get_abilities()
	return S(abilities and abilities.job_abilities or {})
end

function ability_recasts()
	return windower.ffxi.get_ability_recasts() or {}
end

function snake_eye_is_ready(rollNum, available_ja, abil_recasts)
	if not available_ja:contains(177) or abil_recasts[197] ~= 0 then
		return false
	end

	if haveBuff('Snake Eye') or snakeEyeRequestPending or snakeEyeDoubleUpPending then
		return false
	end

	if not snake_eye_policy_allows_reuse(rollNum) then
		return false
	end
	return true
end

function set_last_decision(roll_name, total, action, reason)
	lastDecisionRoll = roll_name
	lastDecisionTotal = total
	lastDecision = action:upper() .. ': ' .. reason
	if settings.debug then
		windower.add_to_chat(207, ('[Roller2] %s %s -> %s (%s)'):format(
			roll_name, tostring(total), action:upper(), reason))
	end
	update_displaybox()
end

function finish_snake_eye_request_if_failed(sequenceId)
	if sequenceId ~= snakeEyeSequenceId then return end
	if snakeEyeRequestPending and not haveBuff('Snake Eye') then
		snakeEyeRequestPending = false
		snakeEyeCommandSent = false
		snakeEyeDoubleUpPending = false
		pendingRollAction = nil
		midRoll = false
		windower.add_to_chat(167, '[Roller2] Snake Eye was not confirmed; the roll was stopped safely.')
		update_displaybox()
	end
end

function send_snake_eye_when_ready(attempt, sequenceId)
	attempt = attempt or 1
	if sequenceId ~= snakeEyeSequenceId or not autoroll
		or not snakeEyeRequestPending or snakeEyeCommandSent then
		return
	end

	-- Wait for the Double-Up Chance buff as confirmation that the initial
	-- Phantom Roll has completed. The small initial delay also respects the
	-- game's post-ability lock without hard-coding the later Double-Up timing.
	if haveBuff('Double-Up Chance') then
		local recasts = ability_recasts()
		if recasts[197] == 0 then
			snakeEyeCommandSent = true
			windower.chat.input('/ja "Snake Eye" <me>')
		elseif attempt < 20 then
			coroutine.schedule(function()
				send_snake_eye_when_ready(attempt + 1, sequenceId)
			end, 0.15)
		end
	elseif attempt < 20 then
		coroutine.schedule(function()
			send_snake_eye_when_ready(attempt + 1, sequenceId)
		end, 0.15)
	end
end

function double_up_after_snake_eye(attempt, sequenceId)
	attempt = attempt or 1
	if sequenceId ~= snakeEyeSequenceId then return end
	if not snakeEyeDoubleUpPending then return end

	if not haveBuff('Double-Up Chance') then
		snakeEyeDoubleUpPending = false
		pendingRollAction = nil
		midRoll = false
		update_displaybox()
		return
	end

	local abil_recasts = ability_recasts()
	if haveBuff('Snake Eye') and abil_recasts[194] == 0 then
		snakeEyeDoubleUpPending = false
		pendingRollAction = 'double_up_sent'
		windower.chat.input('/ja "Double-Up" <me>')
		coroutine.schedule(function()
			confirm_double_up_result(sequenceId)
		end, 2)
		return
	end

	if attempt < 30 then
		coroutine.schedule(function()
			double_up_after_snake_eye(attempt + 1, sequenceId)
		end, 0.2)
	else
		snakeEyeDoubleUpPending = false
		pendingRollAction = nil
		midRoll = false
		windower.add_to_chat(167, '[Roller2] Timed out waiting to use Double-Up after Snake Eye.')
		update_displaybox()
	end
end

function request_snake_eye(reason)
	midRoll = true
	snakeEyeRequestPending = true
	snakeEyeCommandSent = false
	pendingRollAction = 'snake_eye'
	if settings.debug then
		windower.add_to_chat(207, '[Roller2] Snake Eye queued: ' .. tostring(reason))
	end
	update_displaybox()
	local requestSequenceId = snakeEyeSequenceId
	coroutine.schedule(function()
		send_snake_eye_when_ready(1, requestSequenceId)
	end, 1.1)
	coroutine.schedule(function()
		finish_snake_eye_request_if_failed(requestSequenceId)
	end, 5)
end

function confirm_double_up_result(sequenceId)
	if sequenceId ~= snakeEyeSequenceId or pendingRollAction ~= 'double_up_sent' then
		return
	end
	pendingRollAction = nil
	midRoll = false
	if haveBuff('Double-Up Chance') then
		windower.add_to_chat(
			167,
			'[Roller2] Double-Up was not confirmed. The sequence was stopped without retrying.')
	end
	update_displaybox()
end

function double_up_when_ready(attempt, sequenceId)
	attempt = attempt or 1
	if sequenceId ~= snakeEyeSequenceId or pendingRollAction ~= 'double_up' then
		return
	end
	if not autoroll or not haveBuff('Double-Up Chance') or haveBuff('Bust') then
		pendingRollAction = nil
		midRoll = false
		update_displaybox()
		return
	end

	local blocked = haveBuff('amnesia') or haveBuff('impairment')
	local recasts = ability_recasts()
	if not blocked and recasts[194] == 0 then
		pendingRollAction = 'double_up_sent'
		windower.chat.input('/ja "Double-Up" <me>')
		coroutine.schedule(function()
			confirm_double_up_result(sequenceId)
		end, 2)
		return
	end

	if attempt < 40 then
		coroutine.schedule(function()
			double_up_when_ready(attempt + 1, sequenceId)
		end, 0.2)
	else
		pendingRollAction = nil
		midRoll = false
		windower.add_to_chat(167, '[Roller2] Timed out waiting for Double-Up to become ready.')
		update_displaybox()
	end
end

function request_double_up(reason)
	midRoll = true
	pendingRollAction = 'double_up'
	if settings.debug then
		windower.add_to_chat(207, '[Roller2] Double-Up queued: ' .. tostring(reason))
	end
	update_displaybox()
	local requestSequenceId = snakeEyeSequenceId
	coroutine.schedule(function()
		double_up_when_ready(1, requestSequenceId)
	end, 1)
end

windower.register_event('addon command',function (...)
    cmd = {...}

	 if cmd[1] ~= nil then
		cmd[1] = cmd[1]:lower()
	end

	if cmd[2] ~= nil then
		cmd[2] = cmd[2]:lower()
	end

	if cmd[1] == nil or cmd[1] == "rolls" or cmd[1] == "status" then

		if autoroll == true then
			windower.add_to_chat(7,'Automatic Rolling is ON.')
		else
			windower.add_to_chat(7,'Automatic Rolling is OFF.')
		end

		windower.add_to_chat(7,'Roll 1: '..Rollindex[settings.Roll_ind_1]..'')
		windower.add_to_chat(7,'Roll 2: '..Rollindex[settings.Roll_ind_2]..'')
		windower.add_to_chat(7,'Roll policy: '..roll_policy())
		windower.add_to_chat(7,'Automatic Random Deal: '..
			(settings.auto_random_deal and 'ON' or 'OFF'))
		local display_x, display_y = display_position()
		windower.add_to_chat(7,('Display: %s at %d, %d'):format(
			settings.showdisplay and 'ON' or 'OFF', display_x, display_y))

    else
		if cmd[1] == "help" then
			windower.add_to_chat(7,'To start or stop auto rolling type //roller2 roll')
			windower.add_to_chat(7,'To set rolls use //roller2 roll# rollname')
			windower.add_to_chat(7,'Chaos/Samurai preset: //roller2 chaos-samurai')
			windower.add_to_chat(7,'Roll policy: //roller2 policy conservative|balanced|aggressive')
			windower.add_to_chat(7,'Display: //roller2 display on|off|pos x y|reset|status')
			windower.add_to_chat(7,'Diagnostics: //roller2 debug on|off')
		elseif cmd[1] == "policy" or cmd[1] == "snakeeye" or cmd[1] == "sepolicy" then
			if cmd[2] == nil then
				windower.add_to_chat(7,'Roll policy: '..roll_policy())
			elseif validSnakeEyePolicies:contains(cmd[2]) then
				settings.snakeeye_policy = cmd[2]
				config.save(settings)
				windower.add_to_chat(7,'Roll policy set to: '..cmd[2])
			else
				windower.add_to_chat(7,'Valid roll policies: conservative, balanced, aggressive')
			end
		elseif cmd[1] == "display" then
			if cmd[2] == nil then
				settings.showdisplay = not settings.showdisplay
				config.save(settings)
			elseif cmd[2] == 'on' or cmd[2] == 'show' then
				settings.showdisplay = true
				config.save(settings)
				windower.add_to_chat(7,'Display On.')
			elseif cmd[2] == 'off' or cmd[2] == 'hide' then
				settings.showdisplay = false
				config.save(settings)
				windower.add_to_chat(7,'Display Off.')
			elseif cmd[2] == 'pos' or cmd[2] == 'position' then
				local x = tonumber(cmd[3])
				local y = tonumber(cmd[4])
				if not x or not y then
					windower.add_to_chat(167,'Usage: //roller2 display pos <x> <y>')
				else
					settings.displayx = math.floor(x)
					settings.displayy = math.floor(y)
					config.save(settings)
					create_display(settings)
					windower.add_to_chat(7,('Display position: %d, %d'):format(
						settings.displayx, settings.displayy))
				end
			elseif cmd[2] == 'reset' then
				settings.displayx, settings.displayy = default_display_position()
				config.save(settings)
				create_display(settings)
				windower.add_to_chat(7,('Display reset to: %d, %d'):format(
					settings.displayx, settings.displayy))
			elseif cmd[2] == 'status' then
				local x, y = display_position()
				windower.add_to_chat(7,('Display is %s at %d, %d'):format(
					settings.showdisplay and 'ON' or 'OFF', x, y))
			else
				windower.add_to_chat(7,'Display commands: on, off, pos x y, reset, status')
			end
		elseif cmd[1] == "randomdeal" or cmd[1] == "rd" then
			if cmd[2] == 'on' then
				settings.auto_random_deal = true
			elseif cmd[2] == 'off' then
				settings.auto_random_deal = false
			elseif cmd[2] ~= nil then
				windower.add_to_chat(167,'Usage: //roller2 randomdeal on|off')
				return
			end
			config.save(settings)
			windower.add_to_chat(7,'Automatic Random Deal: '..
				(settings.auto_random_deal and 'ON' or 'OFF'))
		elseif cmd[1] == "debug" then
			if cmd[2] == 'on' then
				settings.debug = true
			elseif cmd[2] == 'off' then
				settings.debug = false
			elseif cmd[2] ~= nil then
				windower.add_to_chat(167,'Usage: //roller2 debug on|off')
				return
			end
			config.save(settings)
			windower.add_to_chat(7,'Decision diagnostics: '..
				(settings.debug and 'ON' or 'OFF'))
		elseif cmd[1] == "engaged" then
			if cmd[2] == nil then
				settings.engaged = not settings.engaged
				config.save(settings)
			elseif cmd[2] == 'on' or cmd[2] == 'true' then
				settings.engaged = true
				config.save(settings)
				windower.add_to_chat(7,'Engaged Only: On.')
			elseif cmd[2] == 'off' or cmd[2] == 'false' then
				settings.engaged = false
				config.save(settings)
				windower.add_to_chat(7,'Engaged Only: Off.')
			else
				windower.add_to_chat(7,'Not a recognized engaged subcommand. (on, off)')
			end
		elseif cmd[1] == "midroll" and cmd[2] == 'off' then
			midRoll = false
			reset_snake_eye_state()
		elseif cmd[1] == "start" or cmd[1] == "go" or cmd[1] == "begin" or cmd[1] == "enable" or cmd[1] == "on" or cmd[1] == "engage" or cmd[1] == "resume" then
			zonedelay = 6
			if autoroll == false then
				autoroll = true
				windower.add_to_chat(7,'Enabling Automatic Rolling.')
			elseif autoroll == true then
				windower.add_to_chat(7,'Automatic Rolling already enabled.')
			end
		elseif cmd[1] == "stop" or cmd[1] == "quit" or cmd[1] == "end" or cmd[1] == "disable" or cmd[1] == "off" or cmd[1] == "disengage" or cmd[1] == "pause" then
			zonedelay = 6
			reset_snake_eye_state()
			if autoroll == true then
				autoroll = false
				windower.add_to_chat(7,'Disabling Automatic Rolling.')
			elseif autoroll == false then
				windower.add_to_chat(7,'Automatic Rolling already disabled.')
			end
		elseif cmd[1] == "roll" then
			if cmd[2] == "roll1" then
				reset_snake_eye_state()
				windower.chat.input('/ja "'..Rollindex[settings.Roll_ind_1]..'" <me>')
			elseif cmd[2] == "roll2" then
				reset_snake_eye_state()
				windower.chat.input('/ja "'..Rollindex[settings.Roll_ind_2]..'" <me>')
			else
				zonedelay = 6
				if autoroll == false then
					autoroll = true
					windower.add_to_chat(7,'Enabling Automatic Rolling.')
				elseif autoroll == true then
					autoroll = false
					reset_snake_eye_state()
					windower.add_to_chat(7,'Disabling Automatic Rolling.')
				end
			end

		elseif cmd[1] == "chaos-samurai" or cmd[1] == "chaossam" then
			settings.Roll_ind_1 = 8
			settings.Roll_ind_2 = 12
			config.save(settings)
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')

		elseif cmd[1] == "melee" then
			settings.Roll_ind_1 = 12
			settings.Roll_ind_2 = 8
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1]:startswith('exp') or cmd[1]:startswith('cap') or cmd[1] == "cp" then
			settings.Roll_ind_1 = 17
			settings.Roll_ind_2 = 19
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "tp" or cmd[1] == "stp" then
			settings.Roll_ind_1 = 12
			settings.Roll_ind_2 = 1
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "speed" or cmd[1] == "movespeed" or cmd[1]:startswith('bolt') then
			settings.Roll_ind_1 = 21
			settings.Roll_ind_2 = 21
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1]:startswith('acc') or cmd[1] == "highacc" then
			settings.Roll_ind_1 = 12
			settings.Roll_ind_2 = 11
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "ws" or cmd[1] == "wsd" then
			settings.Roll_ind_1 = 8
			settings.Roll_ind_2 = 1
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "nuke" or cmd[1] == "burst" or cmd[1] == "matk" or cmd[1]:startswith('mag')  then
			settings.Roll_ind_1 = 4
			settings.Roll_ind_2 = 5
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "pet" or cmd[1]:startswith("petphy") then
			settings.Roll_ind_1 = 9
			settings.Roll_ind_2 = 14
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "petnuke" or cmd[1]:startswith('petma') then
			settings.Roll_ind_1 = 18
			settings.Roll_ind_2 = 28
			windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			config.save(settings)

		elseif cmd[1] == "roll1" then
			local rollchange = false
			if cmd[2] == nil then windower.add_to_chat(7,'Roll 1: '..Rollindex[settings.Roll_ind_1]..'') return
			elseif cmd[2]:startswith("warlock") or cmd[2]:startswith("macc") or cmd[2]:startswith("magic ac") or cmd[2]:startswith("rdm") then settings.Roll_ind_1 = 5 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("fight") or cmd[2]:startswith("double") or cmd[2]:startswith("dbl") or cmd[2]:startswith("war") then settings.Roll_ind_1 = 1 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("monk") or cmd[2]:startswith("subtle") or cmd[2]:startswith("mnk") then settings.Roll_ind_1 = 2 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("heal") or cmd[2]:startswith("cure") or cmd[2]:startswith("whm") then settings.Roll_ind_1 = 3 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("wizard") or cmd[2]:startswith("matk") or cmd[2]:startswith("magic at") or cmd[2]:startswith("blm") then settings.Roll_ind_1 = 4 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("rogue") or cmd[2]:startswith("crit") or cmd[2]:startswith("thf") then settings.Roll_ind_1 = 6 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("gallant") or cmd[2]:startswith("def") or cmd[2]:startswith("pld") then settings.Roll_ind_1 = 7 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("chaos") or cmd[2]:startswith("attack") or cmd[2]:startswith("atk") or cmd[2]:startswith("drk") then settings.Roll_ind_1 = 8 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("beast") or cmd[2]:startswith("pet at") or cmd[2]:startswith("bst") then settings.Roll_ind_1 = 9 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("choral") or cmd[2]:startswith("inter") or cmd[2]:startswith("spell inter") or cmd[2]:startswith("brd") then settings.Roll_ind_1 = 10 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("hunt") or cmd[2]:startswith("acc") or  cmd[2]:startswith("rng") then settings.Roll_ind_1 = 11 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("sam") or cmd[2]:startswith("stp") or cmd[2]:startswith("store") then settings.Roll_ind_1 = 12 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("nin") or cmd[2]:startswith("eva") then settings.Roll_ind_1 = 13 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("drach") or cmd[2]:startswith("pet ac") or cmd[2]:startswith("drg") then settings.Roll_ind_1 = 14 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("evoke") or cmd[2]:startswith("refresh") or cmd[2]:startswith("smn") then settings.Roll_ind_1 = 15 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("magus") or cmd[2]:startswith("mdb") or cmd[2]:startswith("magic d") or cmd[2]:startswith("blu") then settings.Roll_ind_1 = 16 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("cor") or cmd[2]:startswith("exp") then settings.Roll_ind_1 = 17 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("pup") or cmd[2]:startswith("pet m") then settings.Roll_ind_1 = 18 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("dance") or cmd[2]:startswith("regen") or cmd[2]:startswith("dnc") then settings.Roll_ind_1 = 19 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("sch") or cmd[2]:startswith("conserve m") then settings.Roll_ind_1 = 20 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("bolt") or cmd[2]:startswith("move") or cmd[2]:startswith("flee") or cmd[2]:startswith("speed") then settings.Roll_ind_1 = 21 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("cast") or cmd[2]:startswith("fast") or cmd[2]:startswith("fc") then settings.Roll_ind_1 = 22 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("course") or cmd[2]:startswith("snap") then settings.Roll_ind_1 = 23 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("blitz") or cmd[2]:startswith("delay") then settings.Roll_ind_1 = 24 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("tact") or cmd[2]:startswith("regain") then settings.Roll_ind_1 = 25 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("all") or cmd[2]:startswith("skillchain") then settings.Roll_ind_1 = 26 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("miser") or cmd[2]:startswith("save tp") or cmd[2]:startswith("conserve t") then settings.Roll_ind_1 = 27 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("companion") or cmd[2]:startswith("pet r") then settings.Roll_ind_1 = 28 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("avenge") or cmd[2]:startswith("counter") then settings.Roll_ind_1 = 29 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("natural") or cmd[2]:startswith("enhance") or cmd[2]:startswith("duration") then settings.Roll_ind_1 = 30 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("run") or cmd[2]:startswith("meva") or cmd[2]:startswith("magic e") then settings.Roll_ind_1 = 31 config.save(settings) rollchange = true
			end

			if rollchange == true then
				windower.add_to_chat(7,'Setting Roll 1 to: '..Rollindex[settings.Roll_ind_1]..'')
			else
				windower.add_to_chat(7,'Invalid roll name, Roll 1 remains: '..Rollindex[settings.Roll_ind_1]..'')
			end

		elseif cmd[1] == "roll2" then
			local rollchange = false
			if cmd[2] == nil then windower.add_to_chat(7,'Roll 2: '..Rollindex[settings.Roll_ind_2]..'') return
			elseif cmd[2]:startswith("warlock") or cmd[2]:startswith("macc") or cmd[2]:startswith("magic ac") or cmd[2]:startswith("rdm") then settings.Roll_ind_2 = 5 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("fight") or cmd[2]:startswith("double") or cmd[2]:startswith("dbl") or cmd[2]:startswith("war") then settings.Roll_ind_2 = 1 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("monk") or cmd[2]:startswith("subtle") or cmd[2]:startswith("mnk") then settings.Roll_ind_2 = 2 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("heal") or cmd[2]:startswith("cure") or cmd[2]:startswith("whm") then settings.Roll_ind_2 = 3 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("wizard") or cmd[2]:startswith("matk") or cmd[2]:startswith("magic at") or cmd[2]:startswith("blm") then settings.Roll_ind_2 = 4 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("rogue") or cmd[2]:startswith("crit") or cmd[2]:startswith("thf") then settings.Roll_ind_2 = 6 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("gallant") or cmd[2]:startswith("def") or cmd[2]:startswith("pld") then settings.Roll_ind_2 = 7 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("chaos") or cmd[2]:startswith("attack") or cmd[2]:startswith("atk") or cmd[2]:startswith("drk") then settings.Roll_ind_2 = 8 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("beast") or cmd[2]:startswith("pet at") or cmd[2]:startswith("bst") then settings.Roll_ind_2 = 9 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("choral") or cmd[2]:startswith("inter") or cmd[2]:startswith("spell inter") or cmd[2]:startswith("brd") then settings.Roll_ind_2 = 10 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("hunt") or cmd[2]:startswith("acc") or  cmd[2]:startswith("rng") then settings.Roll_ind_2 = 11 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("sam") or cmd[2]:startswith("stp") or cmd[2]:startswith("store") then settings.Roll_ind_2 = 12 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("nin") or cmd[2]:startswith("eva") then settings.Roll_ind_2 = 13 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("drach") or cmd[2]:startswith("pet ac") or cmd[2]:startswith("drg") then settings.Roll_ind_2 = 14 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("evoke") or cmd[2]:startswith("refresh") or cmd[2]:startswith("smn") then settings.Roll_ind_2 = 15 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("magus") or cmd[2]:startswith("mdb") or cmd[2]:startswith("magic d") or cmd[2]:startswith("blu") then settings.Roll_ind_2 = 16 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("cor") or cmd[2]:startswith("exp") then settings.Roll_ind_2 = 17 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("pup") or cmd[2]:startswith("pet m") then settings.Roll_ind_2 = 18 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("dance") or cmd[2]:startswith("regen") or cmd[2]:startswith("dnc") then settings.Roll_ind_2 = 19 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("sch") or cmd[2]:startswith("conserve m") then settings.Roll_ind_2 = 20 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("bolt") or cmd[2]:startswith("move") or cmd[2]:startswith("flee") or cmd[2]:startswith("speed") then settings.Roll_ind_2 = 21 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("cast") or cmd[2]:startswith("fast") or cmd[2]:startswith("fc") then settings.Roll_ind_2 = 22 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("course") or cmd[2]:startswith("snap") then settings.Roll_ind_2 = 23 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("blitz") or cmd[2]:startswith("delay") then settings.Roll_ind_2 = 24 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("tact") or cmd[2]:startswith("regain") then settings.Roll_ind_2 = 25 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("all") or cmd[2]:startswith("skillchain") then settings.Roll_ind_2 = 26 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("miser") or cmd[2]:startswith("save tp") or cmd[2]:startswith("conserve t") then settings.Roll_ind_2 = 27 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("companion") or cmd[2]:startswith("pet r") then settings.Roll_ind_2 = 28 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("avenge") or cmd[2]:startswith("counter") then settings.Roll_ind_2 = 29 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("natural") or cmd[2]:startswith("enhance") or cmd[2]:startswith("duration") then settings.Roll_ind_2 = 30 config.save(settings) rollchange = true
			elseif cmd[2]:startswith("run") or cmd[2]:startswith("meva") or cmd[2]:startswith("magic e") then settings.Roll_ind_2 = 31 config.save(settings) rollchange = true
			end

			if rollchange == true then
				windower.add_to_chat(7,'Setting Roll 2 to: '..Rollindex[settings.Roll_ind_2]..'')
			else
				windower.add_to_chat(7,'Invalid roll name, Roll 2 remains: '..Rollindex[settings.Roll_ind_2]..'')
			end
         end

    end

	update_displaybox()
end)

windower.register_event('load', function()

	autoroll = false

	buffId = S{309} + S(res.buffs:english(string.endswith-{' Roll'})):map(table.get-{'en'})

    Rollindex = {'Fighter\'s Roll','Monk\'s Roll','Healer\'s Roll','Wizard\'s Roll','Warlock\'s Roll','Rogue\'s Roll','Gallant\'s Roll','Chaos Roll','Beast Roll',
				 'Choral Roll','Hunter\'s Roll','Samurai Roll','Ninja Roll','Drachen Roll','Evoker\'s Roll','Magus\'s Roll','Corsair\'s Roll','Puppet Roll',
				 'Dancer\'s Roll','Scholar\'s Roll','Bolter\'s Roll','Caster\'s Roll','Courser\'s Roll','Blitzer\'s Roll','Tactician\'s Roll','Allies\' Roll',
				 'Miser\'s Roll','Companion\'s Roll','Avenger\'s Roll','Naturalist\'s Roll','Runeist\'s Roll'}

    local rollInfoTemp = {
        -- Okay, this goes 1-11 boost, Bust effect, Effect, Lucky, +1 Phantom Roll Effect, Bonus Equipment and Effect,
        ['Chaos'] = {6,8,9,25,11,13,16,3,17,19,31,"-4", '% Attack!', 4, 8},
        ['Fighter\'s'] = {2,2,3,4,12,5,6,7,1,9,18,'-4','% Double-Attack!', 5, 9},
        ['Wizard\'s'] = {4,6,8,10,25,12,14,17,2,20,30, "-10", ' MAB', 5, 9},
        ['Evoker\'s'] = {1,1,1,1,3,2,2,2,1,3,4,'-1', ' Refresh!',5, 9},
        ['Rogue\'s'] = {2,2,3,4,12,5,6,6,1,8,14,'-6', '% Critical Hit Rate!', 5, 9},
        ['Corsair\'s'] = {10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24, '-6', '% Experience Bonus',5, 9},
        ['Hunter\'s'] = {10,13,15,40,18,20,25,5,27,30,50,'-?', ' Accuracy Bonus',4, 8},
        ['Magus\'s'] = {5,20,6,8,9,3,10,13,14,15,25,'-8',' Magic Defense Bonus',2, 6},
        ['Healer\'s'] = {3,4,12,5,6,7,1,8,9,10,16,'-4','% Cure Potency',3, 7},
        ['Drachen'] = {10,13,15,40,18,20,25,5,28,30,50,'-8',' Pet: Accuracy Bonus',4, 8},
        ['Choral'] = {8,42,11,15,19,4,23,27,31,35,50,'+25', '- Spell Interruption Rate',2, 6},
        ['Monk\'s'] = {8,10,32,12,14,15,4,20,22,24,40,'-?', ' Subtle Blow', 3, 7},
        ['Beast'] = {6,8,9,25,11,13,16,3,17,19,31,'-10', '% Pet: Attack Bonus',4, 8},
        ['Samurai'] = {7,32,10,12,14,4,16,20,22,24,40,'-10',' Store TP Bonus',2, 6},
        ['Warlock\'s'] = {2,3,4,12,5,6,7,1,8,9,15,'-5',' Magic Accuracy Bonus',4, 8},
        ['Puppet'] = {5,8,35,11,14,18,2,22,26,30,40,'-8',' Pet: Magic Attack Bonus',3, 7},
        ['Gallant\'s'] = {4,5,15,6,7,8,3,9,10,11,20,'-10','% Defense Bonus', 3, 7},
        ['Dancer\'s'] = {3,4,12,5,6,7,1,8,9,10,16,'-4',' Regen',3, 7},
        ['Bolter\'s'] = {0.3,0.3,0.8,0.4,0.4,0.5,0.5,0.6,0.2,0.7,1.0,'-8','% Movement Speed',3, 9},
        ['Caster\'s'] = {6,15,7,8,9,10,5,11,12,13,20,'-10','% Fast Cast',2, 7},
        ['Tactician\'s'] = {10,10,10,10,30,10,10,0,20,20,40,'-10',' Regain',5, 8},
        ['Miser\'s'] = {30,50,70,90,200,110,20,130,150,170,250,'0',' Save TP',5, 7},
        ['Ninja'] = {4,5,5,14,6,7,9,2,10,11,18,'-10',' Evasion Bonus',4, 8},
        ['Scholar\'s'] = {'?','?','?','?','?','?','?','?','?','?','?','?',' Conserve MP',2, 6},
        ['Allies\''] = {6,7,17,9,11,13,15,17,17,5,17,'?','% Skillchain Damage',3, 10},
        ['Companion\'s'] = {{4,20},{20, 50},{6,20},{8, 20},{10,30},{12,30},{14,30},{16,40},{18, 40}, {3,10},{30, 70},'-?',' Pet: Regen/Regain',2, 10},
        ['Avenger\'s'] = {'?','?','?','?','?','?','?','?','?','?','?','?',' Counter Rate',4, 8},
        ['Blitzer\'s'] = {2,3.4,4.5,11.3,5.3,6.4,7.2,8.3,1.5,10.2,12.1,'-?', '% Attack delay reduction',4, 9},
        ['Courser\'s'] = {'?','?','?','?','?','?','?','?','?','?','?','?',' Snapshot',3, 9},
        ['Runeist\'s'] = {'?','?','?','?','?','?','?','?','?','?','?','?',' Magic Evasion',4, 8},
        ['Naturalist\'s'] = {'?','?','?','?','?','?','?','?','?','?','?','?',' Enhancing Magic Duration',3, 7}
    }

    rollInfo = {}
    for key, val in pairs(rollInfoTemp) do
        rollInfo[res.job_abilities:with('english', key .. ' Roll').id] = {key, unpack(val)}
    end

    settings = config.load(defaults)
	settings.snakeeye_policy = roll_policy()
	settings.Roll_ind_1 = tonumber(settings.Roll_ind_1) or defaults.Roll_ind_1
	settings.Roll_ind_2 = tonumber(settings.Roll_ind_2) or defaults.Roll_ind_2
	if settings.Roll_ind_1 < 1 or settings.Roll_ind_1 > #Rollindex then
		settings.Roll_ind_1 = defaults.Roll_ind_1
	end
	if settings.Roll_ind_2 < 1 or settings.Roll_ind_2 > #Rollindex then
		settings.Roll_ind_2 = defaults.Roll_ind_2
	end
	config.save(settings)
	create_display(settings)
end)

windower.register_event('action', function(act)
	if act.category ~= 6 or not rollInfo or not table.containskey(rollInfo, act.param) then
		return
	end

	local player = windower.ffxi.get_player()
	local target = act.targets and act.targets[1]
	local result = target and target.actions and target.actions[1]
	if not player or act.actor_id ~= player.id or not result then
		return
	end

	local rollID = act.param
	local rollNum = tonumber(result.param)
	if not rollNum then return end

	if not rollSequenceActive then
		begin_roll_sequence()
	end

	-- Any result packet supersedes a delayed request from the preceding total.
	pendingRollAction = nil
	snakeEyeDoubleUpPending = false
	midRoll = false

	if result.message ~= 424 then
		lastRollCrooked = false
	end

	local roll_name = rollInfo[rollID][1] .. ' Roll'
	if not autoroll then
		set_last_decision(roll_name, rollNum, 'stop', 'autoroll is off')
		return
	end
	if haveBuff('amnesia') or haveBuff('impairment') then
		set_last_decision(roll_name, rollNum, 'stop', 'player cannot use job abilities')
		return
	end

	local available_ja = available_job_abilities()
	local abil_recasts = ability_recasts()
	local main_cor = player.main_job == 'COR'
	local snake_ready = main_cor
		and snake_eye_is_ready(rollNum, available_ja, abil_recasts)
	local fold_ready = main_cor
		and available_ja:contains(178)
		and abil_recasts[198] == 0
	local action, reason = decision.decide({
		total = rollNum,
		lucky = rollInfo[rollID][15],
		unlucky = rollInfo[rollID][16],
		policy = roll_policy(),
		snake_eye_ready = snake_ready,
		fold_ready = fold_ready,
		crooked = lastRollCrooked,
	})

	set_last_decision(roll_name, rollNum, action, reason)
	if action == 'snake_eye' then
		request_snake_eye(reason)
	elseif action == 'double_up' then
		request_double_up(reason)
	end
end)

function haveBuff(...)
	local args = S{...}:map(string.lower)
	local player = windower.ffxi.get_player()
	if (player ~= nil) and (player.buffs ~= nil) then
		for _,bid in pairs(player.buffs) do
			local buff = res.buffs[bid]
			if buff and buff.en and args:contains(buff.en:lower()) then
				return true
			end
		end
	end
	return false
end

Cities = S{
    "Ru'Lude Gardens",
    "Upper Jeuno",
    "Lower Jeuno",
    "Port Jeuno",
    "Port Windurst",
    "Windurst Waters",
    "Windurst Woods",
    "Windurst Walls",
    "Heavens Tower",
    "Port San d'Oria",
    "Northern San d'Oria",
    "Southern San d'Oria",
	"Chateau d'Oraguille",
    "Port Bastok",
    "Bastok Markets",
    "Bastok Mines",
    "Metalworks",
    "Aht Urhgan Whitegate",
	"The Colosseum",
    "Tavanazian Safehold",
    "Nashmau",
    "Selbina",
    "Mhaura",
	"Rabao",
    "Norg",
    "Kazham",
    "Eastern Adoulin",
    "Western Adoulin",
	"Celennia Memorial Library",
	"Mog Garden",
	"Leafallia"
}

function confirm_phantom_roll(sequenceId)
	if sequenceId ~= snakeEyeSequenceId or pendingRollAction ~= 'phantom_roll_sent' then
		return
	end
	pendingRollAction = nil
	midRoll = false
	windower.add_to_chat(167, '[Roller2] Phantom Roll was not confirmed; automation is ready to retry.')
	update_displaybox()
end

function send_phantom_roll(roll_name, sequenceId)
	if sequenceId ~= snakeEyeSequenceId or not autoroll then
		return
	end
	pendingRollAction = 'phantom_roll_sent'
	windower.chat.input('/ja "' .. roll_name .. '" <me>')
	coroutine.schedule(function()
		confirm_phantom_roll(sequenceId)
	end, 3)
	update_displaybox()
end

function request_phantom_roll(roll_name, use_crooked)
	local requestSequenceId = snakeEyeSequenceId
	midRoll = true
	if use_crooked then
		pendingRollAction = 'crooked_cards'
		windower.chat.input('/ja "Crooked Cards" <me>')
		coroutine.schedule(function()
			if requestSequenceId == snakeEyeSequenceId
				and pendingRollAction == 'crooked_cards' and autoroll then
				send_phantom_roll(roll_name, requestSequenceId)
			end
		end, 2)
	else
		send_phantom_roll(roll_name, requestSequenceId)
	end
	update_displaybox()
end

function doRoll()
	--if Cities:contains(res.zones[windower.ffxi.get_info().zone].english) then return end
	if not autoroll or haveBuff('amnesia') or haveBuff('impairment') or midRoll then return end
	if haveBuff('Sneak') or haveBuff('Invisible') then
		stealthy = true
	else
		stealthy = false
	end
	if not (stealthy == was_stealthy) then update_displaybox() end
	was_stealthy = stealthy
	if stealthy then return end
	local player = windower.ffxi.get_player()
	if not player then return end
	if not (player.main_job == 'COR' or player.sub_job == 'COR') then return end
	local status_resource = res.statuses[player.status]
	local status = status_resource and status_resource.english
	if not (((status == 'Idle') and not settings.engaged) or status == 'Engaged') then return end
	local abil_recasts = ability_recasts()
	local available_ja = available_job_abilities()

	if settings.auto_random_deal and player.main_job == 'COR'
		and available_ja:contains(133)
		and abil_recasts[198] and abil_recasts[198] > 0
		and abil_recasts[197] and abil_recasts[197] > 0
		and abil_recasts[193] == 0 and abil_recasts[196] == 0 then
		windower.send_command('input /ja "Random Deal" <me>')
		return
	end

	if player.main_job == 'COR' and haveBuff('Bust') and available_ja:contains(178) and abil_recasts[198] and abil_recasts[198] == 0 then windower.send_command('input /ja "Fold" <me>') return end
	if not abil_recasts[193] or abil_recasts[193] > 0 then return end

	if not haveBuff(Rollindex[settings.Roll_ind_1]) and not haveBuff(Rollindex[settings.Roll_ind_2]) then
		lastRollCrooked = false
	end

	if not haveBuff(Rollindex[settings.Roll_ind_1]) then
		if player.main_job == 'COR' and player.main_job_level > 94 and abil_recasts[96] == 0 then
			request_phantom_roll(Rollindex[settings.Roll_ind_1], true)
		else
			request_phantom_roll(Rollindex[settings.Roll_ind_1], false)
		end

	elseif player.main_job == 'COR' and not haveBuff(Rollindex[settings.Roll_ind_2]) and not haveBuff('Bust') then
		request_phantom_roll(Rollindex[settings.Roll_ind_2], false)
	end

end

windower.register_event('gain buff', function(buff_id)
	if buff_id == 308 then
		-- A fresh Double-Up Chance window identifies a new Phantom Roll sequence.
		if not rollSequenceActive then
			begin_roll_sequence()
		end
	elseif buff_id == 357 then
		-- Confirm the ability actually activated. This also catches manual use.
		local requestedByRoller2 = snakeEyeRequestPending
		snakeEyeUsedThisRoll = true
		snakeEyeRequestPending = false
		snakeEyeCommandSent = false
		if requestedByRoller2 then
			snakeEyeDoubleUpPending = true
			pendingRollAction = 'snake_eye_double_up'
			midRoll = true
			local requestSequenceId = snakeEyeSequenceId
			coroutine.schedule(function()
				double_up_after_snake_eye(1, requestSequenceId)
			end, 0.2)
		end
		update_displaybox()
	elseif buff_id == 309 then
		pendingRollAction = nil
		midRoll = false
		update_displaybox()
	end
end)

windower.register_event('lose buff', function(buff_id)
	if buff_id == 601 then
		local abil_recasts = ability_recasts()

		if (abil_recasts[193] or 0) > 40 and haveBuff("Double-Up Chance") then
			lastRollCrooked = true
		end
	elseif buff_id == 308 then
		midRoll = false
		reset_snake_eye_state()
		update_displaybox()
	end
end)


windower.register_event('zone change', function()
	zonedelay = 0
	autoroll = false
	lastRollCrooked = false
	lastDecision = 'Waiting'
	lastDecisionTotal = nil
	lastDecisionRoll = nil
	reset_snake_eye_state()
	update_displaybox()
end)

windower.register_event('job change', function()
	zonedelay = 0
	autoroll = false
	lastRollCrooked = false
	lastDecision = 'Waiting'
	lastDecisionTotal = nil
	lastDecisionRoll = nil
	reset_snake_eye_state()
	update_displaybox()
end)

windower.register_event('unload', function()
	if displayBox then
		displayBox:destroy()
		displayBox = nil
	end
end)

function default_display_position()
	return 20, 50
end

function display_position()
	local default_x, default_y = default_display_position()
	local x = tonumber(settings.displayx) or default_x
	local y = tonumber(settings.displayy) or default_y
	local windowersettings = windower.get_windower_settings() or {}
	local width = tonumber(windowersettings.ui_x_res) or 1280
	local height = tonumber(windowersettings.ui_y_res) or 720
	x = math.max(0, math.min(math.floor(x), math.max(0, width - 20)))
	y = math.max(0, math.min(math.floor(y), math.max(0, height - 24)))
	return x, y
end

function create_display()
	if displayBox then displayBox:destroy() end
	local x, y = display_position()
	displayBox = texts.new()
	displayBox:pos(x, y)
	displayBox:font('Arial')
	displayBox:size(12)
	displayBox:bold(true)
	displayBox:bg_alpha(0)
	displayBox:right_justified(false)
	displayBox:stroke_width(2)
	displayBox:stroke_transparency(192)
	update_displaybox()
end

function update_displaybox()
	if not displayBox then return end
	local player = windower.ffxi.get_player()
	if not player or not settings.showdisplay
		or not (player.main_job == 'COR' or player.sub_job == 'COR') then
		displayBox:hide()
		return
	end

	displayBox:clear()
	displayBox:append("Roll 1: "..Rollindex[settings.Roll_ind_1])
	if player.main_job == 'COR' and settings.Roll_ind_1 ~= settings.Roll_ind_2 then
		displayBox:append("   Roll 2: "..Rollindex[settings.Roll_ind_2])
	end

	displayBox:append("\nAutoroll: ")
	if autoroll then
		if haveBuff('Invisible') then
			displayBox:append("Suspended: Invisible")
		elseif haveBuff('Sneak') then
			displayBox:append("Suspended: Sneak")
		else
			displayBox:append("On")
		end
	else
		displayBox:append("Off")
	end
	displayBox:append("   Policy: "..roll_policy())
	if settings.engaged then
		displayBox:append("   Engaged only")
	end
	if settings.auto_random_deal then
		displayBox:append("   RD: Auto")
	end
	if pendingRollAction then
		displayBox:append("   Pending: "..pendingRollAction)
	end

	if lastDecisionRoll and lastDecisionTotal then
		displayBox:append(("\nLast: %s %s - %s"):format(
			lastDecisionRoll, tostring(lastDecisionTotal), lastDecision))
	end
	displayBox:update({})
	displayBox:show()
end

windower.register_event('outgoing chunk', function(id, data)
    if id == 0x00D and displayBox then
        displayBox:hide()
    end
end)

windower.register_event('incoming chunk', function(id, data)
    if id == 0x00A and displayBox then
        update_displaybox()
    end
end)

doRoll:loop(3)
