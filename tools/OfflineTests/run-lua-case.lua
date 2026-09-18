-- A success marker is emitted only after the entire test returns normally.
-- Fengari may otherwise return exit code zero after an assertion failure.
local path=assert(arg[1],'Test path required')
arg={}
assert(loadfile(path))()
print('OFFLINE_LUA_CASE_COMPLETED')
