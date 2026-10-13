--[[
	Waits for things that may legitimately take a while to appear (leaderstats are created by the
	server only after the player's profile loaded, PlayerModule loads asynchronously) without
	triggering Roblox's "Infinite yield possible" warning. Polls instead of blocking forever.
]]

local WaitFor = {}

local POLL_INTERVAL = 0.2

--- Waits for `parent[name]`. Returns nil when `timeout` (seconds, optional) runs out.
function WaitFor.Child(parent, name, timeout)
	local deadline = timeout and os.clock() + timeout
	local child = parent:FindFirstChild(name)
	while not child do
		if not parent:IsDescendantOf(game) or (deadline and os.clock() >= deadline) then
			return nil
		end
		task.wait(POLL_INTERVAL)
		child = parent:FindFirstChild(name)
	end
	return child
end

return WaitFor
