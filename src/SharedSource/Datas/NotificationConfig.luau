--[[
	Notifications ("You have no water!", "Zone 3 is locked"...): short messages shown to a single player in a
	stack of toasts (see Notification_Controller). The server decides WHEN (Notification_Service:Notify(player, id)),
	the texts live here, so wording never needs a code change.

	Message fields:
		Type      key of `Types` (look + default sound)
		Title     main line. `{Name}` placeholders are filled from the params passed to Notify.
		Hint      (optional) smaller second line, same placeholders
		Sound     (optional) AudioConfig slot to play, `false` for silence (e.g. when the caller already plays a sound)
		Duration  (optional) seconds on screen, defaults to Display.Duration

	To add a notification: add an entry to `Messages` and call Notification_Service:Notify(player, "<Id>", { ... }).
]]

local NotificationConfig = {}

NotificationConfig.Types = {
	Error = { Color = Color3.fromRGB(226, 96, 96), Glyph = "!", Sound = "PurchaseFail" },
	Warning = { Color = Color3.fromRGB(238, 170, 74), Glyph = "!", Sound = "PurchaseFail" },
	Info = { Color = Color3.fromRGB(100, 168, 228), Glyph = "i", Sound = "UiClick" },
	Success = { Color = Color3.fromRGB(110, 196, 112), Glyph = "✓", Sound = "Purchase" },
}

NotificationConfig.Display = {
	MaxVisible = 4, -- more than this and the oldest toast leaves at once
	Duration = 2.6, -- seconds on screen (a repeated message starts its time again)
	-- the server ignores the SAME message to the SAME player more often than this (hold prompts can retrigger fast)
	Cooldown = 1.2,
}

NotificationConfig.Messages = {
	NoWater = {
		Type = "Error",
		Title = "You have no water!",
		Hint = "Fill your can at the water source first",
	},
	OutOfWater = {
		Type = "Warning",
		Title = "Out of water!",
		Hint = "Refill your can to keep watering",
	},
	CanFull = {
		Type = "Info",
		Title = "Your can is full!",
		Hint = "Go and water the plant",
	},
	ZoneLocked = {
		Type = "Error",
		Title = "{Zone} is locked",
		Hint = "{Requirement}",
	},
	TutorialStep = {
		Type = "Success",
		Title = "Step complete!",
		Hint = "Next: {Next}",
	},
	TutorialDone = {
		Type = "Success",
		Title = "Tutorial complete!",
		Hint = "Grow plants to unlock higher training zones",
		Duration = 4,
	},
	NotEnoughCoins = {
		Type = "Error",
		Title = "Not enough coins!",
		Sound = false, -- the shop already plays its own "purchase failed" sound
	},
}

--- Fills `{Name}` placeholders from `params`; unknown placeholders stay as they are.
local function fill(text, params)
	if not text then
		return nil
	end
	return (text:gsub("{(%w+)}", function(name)
		local value = params and params[name]
		if value == nil then
			return nil
		end
		return tostring(value)
	end))
end

--- Resolves a message into what the UI shows: { Type, Title, Hint, Sound, Duration, Color, Glyph }, or nil if the
--- id is unknown.
function NotificationConfig.Resolve(id, params)
	local message = NotificationConfig.Messages[id]
	if not message then
		return nil
	end
	local style = NotificationConfig.Types[message.Type] or NotificationConfig.Types.Info
	local sound = message.Sound
	if sound == nil then
		sound = style.Sound
	end
	return {
		Id = id,
		Type = message.Type,
		Title = fill(message.Title, params),
		Hint = fill(message.Hint, params),
		Sound = sound or nil,
		Duration = message.Duration or NotificationConfig.Display.Duration,
		Color = style.Color,
		Glyph = style.Glyph,
	}
end

return NotificationConfig
