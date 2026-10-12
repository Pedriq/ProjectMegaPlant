local function componentsInitializer(selectedScript)
	for _, v in pairs(selectedScript.Components:GetDescendants()) do
		if v:IsA("ModuleScript") then
			local module = require(v)
			if typeof(module) ~= "function" then
				if not module.Init then
					warn("Component " .. v.Name .. " does not have an Init function")
					continue
				end

				local succ, err = pcall(function()
					module.Init()
				end)

				if not succ then
					warn("Error initializing component: " .. err)
				end

				if module.Start and typeof(module.Start) == "function" then
					task.spawn(function()
						local startSucc, startErr = pcall(function()
							module.Start()
						end)

						if not startSucc then
							warn("Error starting component " .. v.Name .. ": " .. startErr)
						end
					end)
				end
			end
		end
	end
end

return componentsInitializer
