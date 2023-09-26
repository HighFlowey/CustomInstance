local RunService = game:GetService("RunService")

local UNSUPPORTED = {"table", "function"}
local PROXY = {
	Events = {},
	Functions = {},
	CustomFunctions = {},
	CustomProperties = {},
}

-- TYPECHECKING [ignore]
local fakeProxy = {}
function fakeProxy:GetPropertyChangedSignal(property: string): RBXScriptSignal

end
function fakeProxy:Destroy(): nil

end
export type CustomInstance = {RobloxInstance: Instance} & typeof(fakeProxy)
-- TYPECHECKING [ignore]

local remote = script:WaitForChild("Remote")
local remoteActions = {
	"ClientReady", "CreateFullInstance", "UpdateInstanceProperty"
}

local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

local module = {}
module.EventCooldown = 0
module.PropertyMemory = {}
module.Memory = {}

function module.new(object: Instance): (CustomInstance)
	if object == nil then
		object = Instance.new("BinaryStringValue")
		object.Name = "CustomInstance"
	elseif module.Memory[object] then
		return module.Memory[object]
	end
	
	local proxy: typeof(PROXY) = deepCopy(PROXY)
	
	function proxy.Functions:GetPropertyChangedSignal(property: string): RBXScriptSignal
		local isRobloxProperty = pcall(function()
			object[property] = object[property]
		end)

		if isRobloxProperty then
			return object:GetPropertyChangedSignal(property)
		else
			if proxy.Events[property] == nil then
				proxy.Events[property] = Instance.new("BindableEvent")
			end
			print("returned event")
			return proxy.Events[property].Event
		end
	end
	
	function proxy.Functions:Destroy(): nil
		object:Destroy()
	end
	
	object.Destroying:Connect(function()
		module.Memory[object] = nil
		proxy = nil
	end)
	
	local meta = {}
	
	meta.__index = function(t, i)
		if i == "Proxy.Dev" then
			return proxy
		end
		
		if i == "RobloxInstance" then
			return object
		elseif proxy.Functions[i] then
			return proxy.Functions[i]
		end
		
		if proxy.CustomProperties[i] then
			return proxy.CustomProperties[i]
		elseif proxy.CustomFunctions[i] then
			return proxy.CustomFunctions[i]
		end
		
		return object[i]
	end
	
	local function isBuiltinProperty(i, v)
		object[i] = v
		module.PropertyMemory[object.ClassName][i] = true
	end
	
	meta.__newindex = function(t, i, v)
		local isUNSUPPORTED = table.find(UNSUPPORTED, typeof(v))
		
		if UNSUPPORTED[isUNSUPPORTED] == "function" then
			proxy.CustomFunctions[i] = v
			proxy.CustomProperties[i] = nil
		else
			if proxy.CustomProperties[i]
				or module.PropertyMemory[object.ClassName][i] ~= true
				or not pcall(isBuiltinProperty, i, v) then
				
				proxy.CustomProperties[i] = v
				proxy.CustomFunctions[i] = nil
				
				if RunService:IsServer() then
					local action = table.find(remoteActions, "UpdateInstanceProperty")
					
					task.delay(module.EventCooldown, function()
						remote:FireAllClients(action, object, i, v)
					end)
					
					module.EventCooldown += 0.5
				end
				
				if proxy.Events[i] then
					proxy.Events[i]:Fire()
				end
			end
		end
	end
	
	local class = setmetatable({}, meta)
	
	module.PropertyMemory[object.ClassName] = {}
	module.Memory[object] = class
	
	return class
end

module.get = module.new
module.memory = module.Memory

local function DetectClientReady()
	
	--[[
	
	[HELP FROM DEVFORUM]
	
	"This did not work for me.
	In the end I created a script that waited
	until 4 seconds of nothing new being added to the game
	to conclude they are fully loaded."
	
	]]
	
	local timer = 0 do
		local connections = {}

		connections[1] = game.DescendantAdded:Connect(function()
			timer = 0
		end)

		connections[2] = RunService.Heartbeat:Connect(function(delta)
			if timer >= 4 then
				connections[1]:Disconnect()
				connections[2]:Disconnect()
				connections = nil
				timer = nil
				return
			end

			timer += delta
		end)
	end

	repeat
		task.wait(.1)
	until timer == nil
end

if RunService:IsClient() then
	local action = table.find(remoteActions, "ClientReady")
	
	local function CreateFullInstance(object: Instance, customProperties: {})
		local class = module.new(object)
		
		for i, v in customProperties do
			class[i] = v
		end
	end
	
	local function UpdateInstanceProperty(object: Instance, i, v)
		local class = module.new(object)
		class[i] = v
	end
	
	local customPropertiesLoaded = Instance.new("BindableEvent")
	DetectClientReady()
	
	remote:FireServer(action)
	remote.OnClientEvent:Connect(function(action: number, ...)
		if remoteActions[action] == "CreateFullInstance" then
			CreateFullInstance(...)
		elseif remoteActions[action] == "UpdateInstanceProperty" then
			UpdateInstanceProperty(...)
		elseif remoteActions[action] == "ClientReady" then
			customPropertiesLoaded:Fire()
		end
	end)
	
	customPropertiesLoaded.Event:Wait()
	customPropertiesLoaded:Destroy()
elseif RunService:IsServer() then
	local function ClientReady(player: Player)
		for object: Instance, class in module.memory do
			local action = table.find(remoteActions, "CreateFullInstance")
			
			remote:FireClient(player, action, object, class["Proxy.Dev"].CustomProperties)
		end
		
		local action = table.find(remoteActions, "ClientReady")
		
		remote:FireClient(player, action)
	end
	
	remote.OnServerEvent:Connect(function(player: Player, action: number, ...)
		if remoteActions[action] == "ClientReady" then
			ClientReady(player)
		end
	end)
end

RunService.Heartbeat:Connect(function(delta)
	module.EventCooldown = math.max(module.EventCooldown - delta, 0)
end)

return module
