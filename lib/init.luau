local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Prism = require(script.Packages.Prism)
local Signal = require(script.Packages.AcidSignal)

local Predict = {}

local SyncRemote = Prism.new("Predict.Emit", {
	Name = Prism.String,
	StartTime = Prism.F64,
	Data = Prism.Any,
})
export type Context = {
	Data: any,
	Elapsed: number,
	StartTime: number,
}
local Handlers: { [string]: { callback: (context: Context) -> (), event: typeof(Signal.new()) } } = {}

function Predict.Now()
	return workspace:GetServerTimeNow()
end

function Predict.Register(name: string, callback: (context: Context) -> (), overwrite: boolean?)
	assert(
		overwrite or not Handlers[name],
		`[Predict]: "{name}" is already registered. Pass overwrite = true to replace it.`
	)

	Handlers[name] = { callback = callback, event = Signal.new() :: any }
end

function Predict.Unregister(name: string)
	if not Handlers[name] then
		return
	end

	Handlers[name].event:Destroy()
	Handlers[name] = nil
end

function Predict.GetSignal(name: string)
	local handler = Handlers[name]

	assert(handler, `[Predict] No handler registered for "{name}".`)

	return handler.event
end

local function LocalHandle(name: string, data: any?, startTime: number, ignoreElapsed: boolean)
	local handler = Handlers[name]

	if not handler then
		warn(`[Predict] No handler registered for "{name}". Call Predict:Register("{name}", callback).`)
		return
	end

	local now = Predict.Now()

	if startTime > now then
		task.delay(startTime - now, function()
			LocalHandle(name, data, startTime, true)
		end)

		return
	end

	local context: Context = {
		Data = data,
		StartTime = startTime,
		Elapsed = ignoreElapsed and 0 or now - startTime,
	}

	handler.callback(context)
	handler.event:Fire(context)
end

function Predict.Emit(name: string, data: any?, startTime: number?)
	local ignoreElapsed = not startTime
	startTime = startTime or Predict.Now()

	LocalHandle(name, data, startTime, ignoreElapsed)

	if RunService:IsServer() then
		SyncRemote:Send({ Name = name, Data = data, StartTime = startTime }, Players:GetPlayers())
	end
end

if RunService:IsClient() then
	SyncRemote.Event:Connect(function(data)
		LocalHandle(data.Name, data.Data, data.StartTime, false)
	end)
end

return Predict
