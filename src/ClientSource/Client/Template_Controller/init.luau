local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Template_Controller = Knit.CreateController({
	Name = "Template_Controller",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
Template_Controller.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	Template_Controller.Components[v.Name] = require(v)
end
Template_Controller.GetComponent = require(componentsFolder["Get()"])
Template_Controller.SetComponent = require(componentsFolder["Set()"])

--- Knit Services

--- Knit Controllers

function Template_Controller:KnitStart() end

function Template_Controller:KnitInit()
	componentsInitializer(script)
end

return Template_Controller
