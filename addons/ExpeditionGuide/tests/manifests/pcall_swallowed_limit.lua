-- Regression manifest: when pcall was exposed, declarative content could
-- catch the instruction-budget hook and still return apparently valid data.
local swallowed, reason = pcall(function()
    while true do
        -- The host-side instruction hook must terminate this loop.
    end
end)

return {
    exploit_succeeded = true,
    swallowed = swallowed,
    reason = tostring(reason),
}
