local decision = dofile('Roller2Decision.lua')
local passed = 0

local function expect(name, context, expected)
    local action, reason = decision.decide(context)
    assert(action == expected, ('%s: expected %s, got %s (%s)'):format(
        name, expected, action, reason))
    passed = passed + 1
end

expect('lucky stops', {
    total = 4, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = true, fold_ready = true,
}, 'stop')
expect('XI stops', {
    total = 11, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = true, fold_ready = true,
}, 'stop')
expect('bust stops', {
    total = 12, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = true, fold_ready = true,
}, 'stop')
expect('invalid total stops', {
    total = 0, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = true, fold_ready = true,
}, 'stop')
expect('conservative safely doubles five', {
    total = 5, lucky = 4, unlucky = 8, policy = 'conservative',
    snake_eye_ready = false, fold_ready = true,
}, 'double_up')
expect('conservative stops six with Fold', {
    total = 6, lucky = 4, unlucky = 8, policy = 'conservative',
    snake_eye_ready = false, fold_ready = true,
}, 'stop')
expect('balanced doubles seven with Fold', {
    total = 7, lucky = 4, unlucky = 8, policy = 'balanced',
    snake_eye_ready = false, fold_ready = true,
}, 'double_up')
expect('balanced stops eight', {
    total = 8, lucky = 4, unlucky = 9, policy = 'balanced',
    snake_eye_ready = false, fold_ready = true,
}, 'stop')
expect('aggressive doubles eight with Fold', {
    total = 8, lucky = 4, unlucky = 9, policy = 'aggressive',
    snake_eye_ready = false, fold_ready = true,
}, 'double_up')
expect('aggressive stops eight without Fold', {
    total = 8, lucky = 4, unlucky = 9, policy = 'aggressive',
    snake_eye_ready = false, fold_ready = false,
}, 'stop')
expect('every policy stops raw nine', {
    total = 9, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = false, fold_ready = true,
}, 'stop')
expect('Snake Eye handles ten', {
    total = 10, lucky = 4, unlucky = 8, policy = 'conservative',
    snake_eye_ready = true, fold_ready = false,
}, 'snake_eye')
expect('ten stops without Snake Eye', {
    total = 10, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = false, fold_ready = true,
}, 'stop')
expect('Snake Eye guarantees lucky', {
    total = 3, lucky = 4, unlucky = 8, policy = 'conservative',
    snake_eye_ready = true, fold_ready = false,
}, 'snake_eye')
expect('Snake Eye escapes high unlucky', {
    total = 8, lucky = 4, unlucky = 8, policy = 'conservative',
    snake_eye_ready = true, fold_ready = false,
}, 'snake_eye')
expect('Crooked Cards prevents continuation', {
    total = 3, lucky = 4, unlucky = 8, policy = 'aggressive',
    snake_eye_ready = true, fold_ready = true, crooked = true,
}, 'stop')
expect('invalid policy becomes conservative', {
    total = 6, lucky = 4, unlucky = 8, policy = 'reckless',
    snake_eye_ready = false, fold_ready = true,
}, 'stop')

assert(decision.allows_snake_eye_reuse('conservative', 10, true) == false,
    'conservative must not reuse Snake Eye')
assert(decision.allows_snake_eye_reuse('balanced', 9, true) == false,
    'balanced must not reuse Snake Eye on 9')
assert(decision.allows_snake_eye_reuse('balanced', 10, true) == true,
    'balanced may reuse Snake Eye only to guarantee XI')
assert(decision.allows_snake_eye_reuse('aggressive', 8, true) == true,
    'aggressive may reuse a preserved Snake Eye')
passed = passed + 4

for _, policy in ipairs({'conservative', 'balanced', 'aggressive'}) do
    for total = 1, 10 do
        local action = decision.decide({
            total = total, lucky = 4, unlucky = 8, policy = policy,
            snake_eye_ready = false, fold_ready = true,
        })
        assert(not (total >= 9 and action == 'double_up'),
            policy .. ' issued a prohibited high-total Double-Up')
        if policy == 'conservative' then
            assert(not (total > 5 and action == 'double_up'),
                'conservative exceeded its ceiling')
        elseif policy == 'balanced' then
            assert(not (total > 7 and action == 'double_up'),
                'balanced exceeded its ceiling')
        else
            assert(not (total > 8 and action == 'double_up'),
                'aggressive exceeded its ceiling')
        end
        passed = passed + 1
    end
end

print(('Roller2 decision tests passed: %d'):format(passed))
