local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Template_Service = Knit.CreateService({
	Name = "Template_Service",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
Template_Service.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	Template_Service.Components[v.Name] = require(v)
end
Template_Service.GetComponent = require(componentsFolder["Get()"])
Template_Service.SetComponent = require(componentsFolder["Set()"])

---- Knit Servicesa

function Template_Service:KnitStart() end

function Template_Service:KnitInit()
	---- Components Initializer
	componentsInitializer(script)
end

return Template_Service
