--[[
	The loading screen shown once when a player joins (see Preload_Controller). It covers the game while the custom
	animations, fruits, watering cans and training stations are preloaded, so nothing pops in during the first minute.

	MinTime   seconds the screen stays at least (so a very fast load doesn't flash it)
	MaxTime   seconds after which the game is shown anyway, whatever is still loading (a slow asset never traps a player)
	FadeTime  seconds of the fade-out
	Tips      one is shown at random under the progress bar
]]

local LoadingConfig = {}

LoadingConfig.Title = "Grow a Megaplant"
LoadingConfig.MinTime = 1.2
LoadingConfig.MaxTime = 8
LoadingConfig.FadeTime = 0.45

LoadingConfig.Tips = {
	"Water the plant together with everyone to make it grow faster!",
	"Training Strength gives your watering can a bigger capacity.",
	"Training Mobility makes you run faster.",
	"Rarer plants pay more coins when they are harvested.",
	"Spend coins in the Upgrade Shop to fill and water faster.",
	"Higher training zones give much bigger multipliers.",
}

return LoadingConfig
