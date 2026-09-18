-- Diagnostic wrapper for validate_gearswap_runtime.lua.
-- REFERENCE_JOB selects the Selendrile/Katie user-setup and common gear files
-- without loading a character-specific inventory override.

local reference_job = os.getenv('REFERENCE_JOB') or 'PLD'
player.main_job = reference_job

function select_default_macro_book() end
function update_job_states() end
function update_defense_mode() end
function set_lockstyle() end

function user_setup()
    include('Common/'..reference_job..'_UserSetup_Common.lua')
end

function init_gear_sets()
    include('Common/'..reference_job..'_Common.lua')
end
