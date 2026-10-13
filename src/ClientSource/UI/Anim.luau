local TweenService = game:GetService("TweenService")

local Anim = {}

--- Tweens a Vide source (or any callable setter) from its current value to `target`.
--- Returns the tween so callers can cancel it.
function Anim.TweenSource(setter, from, target, time, style, direction)
	local value = Instance.new("NumberValue")
	value.Value = from
	value.Changed:Connect(function(newValue)
		setter(newValue)
	end)

	local tween = TweenService:Create(
		value,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		{ Value = target }
	)
	tween.Completed:Connect(function()
		value:Destroy()
	end)
	tween:Play()
	return tween
end

--- Formats seconds as m:ss (or h:mm:ss).
function Anim.FormatTime(seconds)
	seconds = math.max(math.ceil(seconds), 0)
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, secs)
	end
	return ("%d:%02d"):format(minutes, secs)
end

function Anim.EaseOutQuart(x)
	return 1 - (1 - x) ^ 4
end

function Anim.EaseOutBack(x)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

return Anim
