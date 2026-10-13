--[[
	Runs a per-player "hold" action (filling water, pouring water) on Heartbeat.

		local sessions = HoldSessions.new()
		sessions:Start(player, function(dt) ... return true end, onStop)
		sessions:Stop(player)

	The tick function returns false (or errors) to end the session. Only one session per player.
]]

local RunService = game:GetService("RunService")

local HoldSessions = {}
HoldSessions.__index = HoldSessions

function HoldSessions.new()
	return setmetatable({
		_sessions = {},
		_connection = nil,
	}, HoldSessions)
end

function HoldSessions:_ensureConnection()
	if self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(dt)
		for player, session in pairs(self._sessions) do
			local ok, keepGoing = pcall(session.tick, dt)
			if not ok then
				warn("HoldSessions: tick failed: " .. tostring(keepGoing))
			end
			if not ok or keepGoing == false then
				self:Stop(player)
			end
		end
	end)
end

function HoldSessions:IsActive(player)
	return self._sessions[player] ~= nil
end

function HoldSessions:Start(player, tick, onStop)
	self:Stop(player)
	self._sessions[player] = { tick = tick, onStop = onStop }
	self:_ensureConnection()
end

function HoldSessions:Stop(player)
	local session = self._sessions[player]
	if not session then
		return
	end
	self._sessions[player] = nil
	if session.onStop then
		local ok, err = pcall(session.onStop)
		if not ok then
			warn("HoldSessions: onStop failed: " .. tostring(err))
		end
	end
	if self._connection and next(self._sessions) == nil then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function HoldSessions:StopAll()
	for player in pairs(table.clone(self._sessions)) do
		self:Stop(player)
	end
end

return HoldSessions
