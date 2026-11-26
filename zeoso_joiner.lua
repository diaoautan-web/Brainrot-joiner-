

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	repeat
		task.wait(0.05)
		LocalPlayer = Players.LocalPlayer
	until LocalPlayer
end

local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")

local function resolveUiParent()
	if PlayerGui then
		return PlayerGui
	end
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	local okCore, core = pcall(function()
		return CoreGui
	end)
	if okCore and core then
		return core
	end
	return LocalPlayer
end

local GuiParent = resolveUiParent()

pcall(function()
	for _, container in ipairs({ PlayerGui, CoreGui, GuiParent }) do
		if container then
			local oldGui = container:FindFirstChild("ZeosoHubGui")
			if oldGui then oldGui:Destroy() end
			local oldEsp = container:FindFirstChild("ZeosoEspFolder")
			if oldEsp then oldEsp:Destroy() end
		end
	end
end)

--// CONFIGURATION
local Config = {
	MinValue = 10_000_000,
	MaxValue = 50_000_000_000,
	Only100MPlus = false,
	AutoHop = false,
	HopDelay = 4.0,
	StopOnMatch = true,
	SkipMarkedServers = true,
	SortDescending = true,
	PreferHighPop = true,
	AutoClone = false,
	AutoSteal = false,
	AutoKickAfterBase = false,
	AntiRagdoll = false,
	AntiLag = true,
	TargetFps = 250,
	LaggerMode = false,
	DuelsScriptEnabled = false,
	DuelsLagMore = false,
	DuelsSpeed24 = false,
	SpeedBoostValue = 24,
	FlyClosestPlayer = false,
	InvisibleMode = false,
	HeadTagEnabled = true,
	HeadTagText = "[GUESS]",
	DeltaAutoExec = true,
	EspAll = false,
	InfJump = false,
	JumpPowerLift = 52,
	BestBrainrotFlySpeed = 120,
	ClosestPlayerFlySpeed = 42,
	LaggerRadius = 65,
	WebhookUrl = "",
	AlertCooldown = 8,
	CurrentJobId = (game.JobId ~= "" and game.JobId) or "STUDIO_TEST",
	VisitedServers = {},
	ServerQueue = {},
	NextCursor = "",
}

local SAVE_FILE = "ZeosoHub_MarkedServers.json"
local lastWebhookTime = 0
local isTeleporting = false
local lastHopAttempt = 0
local activeTargetId = nil
local lastCloneTick = 0
local lastStealRefreshTick = 0
local lastEspTick = 0
local lastRagdollTick = 0
local lastLaggerTick = 0
local lastDuelsTick = 0
local lastSpeedTick = 0
local lastFlyPlayerTick = 0
local lastInvisTick = 0
local lastBaseCheckTick = 0
local isFlyingBest = false
local activeBestFlyConn = nil
local heldPrompts = {}
local hiddenPartsState = {}
local stealAttemptActive = false
local stealAttemptTime = 0
local kickScheduled = false
local StatusLabel = nil
local LastScannedMatches = {}
local antiLagAppliedOnce = false

local function setStatus(msg, col)
	if StatusLabel and StatusLabel.Parent then
		StatusLabel.Text = tostring(msg)
		if col then
			StatusLabel.TextColor3 = col
		end
	end
end

--// SOUND ENGINE
local SoundFolder = Instance.new("Folder")
SoundFolder.Name = "ZeosoSounds"
pcall(function()
	SoundFolder.Parent = SoundService
end)

local function makeSound(id, vol, pitch)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.45
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundFolder
	return s
end

local ClickSfx = makeSound("rbxassetid://6895079853", 0.55, 1.08)
local ToggleOnSfx = makeSound("rbxassetid://12221967", 0.5, 1.25)
local ToggleOffSfx = makeSound("rbxassetid://12221967", 0.4, 0.85)
local AlertSfx = makeSound("rbxassetid://4590657391", 0.6, 1.12)

local function playUiSound(mode)
	pcall(function()
		if mode == "on" then
			ToggleOnSfx.TimePosition = 0
			ToggleOnSfx:Play()
		elseif mode == "off" then
			ToggleOffSfx.TimePosition = 0
			ToggleOffSfx:Play()
		elseif mode == "alert" then
			AlertSfx.TimePosition = 0
			AlertSfx:Play()
		else
			ClickSfx.TimePosition = 0
			ClickSfx:Play()
		end
	end)
end

--// 250 FPS CAP + ALWAYS-ON ANTI-LAG
local function applyFpsCap(fps)
	local target = tonumber(fps) or 250
	pcall(function()
		if typeof(setfpscap) == "function" then
			setfpscap(target)
		elseif typeof(set_fps_cap) == "function" then
			set_fps_cap(target)
		end
	end)
end

local function applyAntiLagOnce()
	if antiLagAppliedOnce then return end
	antiLagAppliedOnce = true

	applyFpsCap(Config.TargetFps)

	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 100000
		if typeof(sethiddenproperty) == "function" then
			pcall(sethiddenproperty, Lighting, "Technology", Enum.Technology.Compatibility)
		end
		for _, eff in ipairs(Lighting:GetChildren()) do
			if eff:IsA("PostEffect") or eff:IsA("Atmosphere") or eff:IsA("Clouds") then
				pcall(function() eff.Enabled = false end)
			end
		end
	end)

	pcall(function()
		if workspace.Terrain then
			workspace.Terrain.WaterWaveSize = 0
			workspace.Terrain.WaterWaveSpeed = 0
			workspace.Terrain.WaterReflectance = 0
			workspace.Terrain.WaterTransparency = 1
		end
	end)

	pcall(function()
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
				pcall(function() obj.Enabled = false end)
			elseif obj:IsA("BasePart") then
				obj.CastShadow = false
			end
		end
	end)
end

applyAntiLagOnce()

--// DELTA / EXECUTOR AUTO-EXECUTE ON TELEPORT
local function setupDeltaAutoExec()
	if not Config.DeltaAutoExec then return end
	local queueFn = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
		or (typeof(queueonteleport) == "function" and queueonteleport)
		or (syn and typeof(syn.queue_on_teleport) == "function" and syn.queue_on_teleport)
		or (typeof(fluxus_queue_on_teleport) == "function" and fluxus_queue_on_teleport)

	if queueFn then
		pcall(function()
			queueFn([[
				if not getgenv().ZeosoAutoExecQueued then
					getgenv().ZeosoAutoExecQueued = true
					task.delay(1.5, function()
						getgenv().ZeosoAutoExecQueued = false
					end)
				end
			]])
		end)
	end
end

pcall(setupDeltaAutoExec)

local ImageOverrides = {
	["Dragon Cannelloni"] = "",
	["Strawberry Elephant"] = "",
	["Meowl"] = "",
	["Skibidi Toilet"] = "",
	["Cash or Card"] = "",
	["La Grande Combinasion"] = "",
	["Tralalero Tralala"] = "",
	["Matteo"] = "",
}

local KnownHighTierNames = {
	"Matteo", "Tralalero Tralala", "Espresso Signora", "Odin Din Din Dun",
	"Statutino Libertino", "Trenostruzzo Turbo 3000", "Ballerino Lololo",
	"La Grande Combinasion", "Noodle Noodle Poodle", "Lavadorito Spinito",
	"Ketchuru and Musturu", "Tictac Sahur", "Ketupat Kepat", "La Fuse Machine",
	"Rubiko and Kubiko", "Cash or Card", "Dragon Cannelloni", "Griffin",
	"Dragon Aquanini", "Skibidi Toilet", "Strawberry Elephant", "Meowl",
	"Headless Horseman"
}

local function toOnlineThumbnail(raw)
	if not raw or raw == "" then
		return ""
	end
	local s = tostring(raw)
	if s:find("GuiImagePlaceholder") then
		return ""
	end
	if s:find("^rbxthumb://") or s:find("^rbxasset://") then
		return s
	end
	local digits = s:match("rbxassetid://(%d+)") or s:match("id=(%d+)") or s:match("^(%d+)$")
	if digits and digits ~= "0" then
		return string.format("rbxthumb://type=Asset&id=%s&w=150&h=150", digits)
	end
	return s
end

--// MARKED SERVER STORAGE
local function saveMarkedServers()
	if typeof(writefile) == "function" then
		pcall(function()
			writefile(SAVE_FILE, HttpService:JSONEncode(Config.VisitedServers))
		end)
	end
end

local function loadMarkedServers()
	if typeof(isfile) == "function" and typeof(readfile) == "function" then
		pcall(function()
			if isfile(SAVE_FILE) then
				local decoded = HttpService:JSONDecode(readfile(SAVE_FILE))
				if type(decoded) == "table" then
					Config.VisitedServers = decoded
				end
			end
		end)
	end
end

local function markServer(jobId, matchCount, topVal)
	if not jobId or jobId == "" then return end
	Config.VisitedServers[jobId] = {
		scannedAt = os.time(),
		matches = matchCount or 0,
		topValue = topVal or 0,
	}
	pcall(saveMarkedServers)
end

local function unmarkServer(jobId)
	if jobId and Config.VisitedServers[jobId] then
		Config.VisitedServers[jobId] = nil
		pcall(saveMarkedServers)
	end
end

local function isServerMarked(jobId)
	return jobId and Config.VisitedServers[jobId] ~= nil
end

local function countMarkedServers()
	local n = 0
	for _ in pairs(Config.VisitedServers) do
		n += 1
	end
	return n
end

pcall(loadMarkedServers)
markServer(Config.CurrentJobId, 0, 0)

--// EXECUTOR-SAFE HTTP & DISCORD WEBHOOK
local function doHttpRequest(payloadTable)
	local reqFn = (syn and syn.request)
		or (http and http.request)
		or http_request
		or request

	if type(reqFn) == "function" then
		return pcall(function()
			return reqFn(payloadTable)
		end)
	end

	if payloadTable.Method == "POST" and payloadTable.Body then
		return pcall(function()
			return HttpService:PostAsync(
				payloadTable.Url,
				payloadTable.Body,
				Enum.HttpContentType.ApplicationJson,
				false
			)
		end)
	end

	return false, "No HTTP request function available"
end

local function fetchUrlText(url)
	local ok, res = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(res) == "string" and #res > 0 then
		return true, res
	end

	local reqOk, reqRes = doHttpRequest({
		Url = url,
		Method = "GET",
		Headers = { ["Accept"] = "application/json" }
	})
	if reqOk and type(reqRes) == "table" and type(reqRes.Body) == "string" and #reqRes.Body > 0 then
		return true, reqRes.Body
	end

	return false, nil
end

local function sendWebhookAlert(matches)
	local url = Config.WebhookUrl:match("^%s*(.-)%s*$")
	if url == "" or not url:find("^https://") then
		return false, "No webhook URL"
	end
	if #matches == 0 then return false, "No matches" end
	if os.clock() - lastWebhookTime < Config.AlertCooldown then
		return false, "Cooldown"
	end

	lastWebhookTime = os.clock()

	local lines = {}
	for i = 1, math.min(#matches, 10) do
		local m = matches[i]
		table.insert(lines, string.format("**%d. %s** — `%s`", i, m.Name, m.RateText))
	end

	local joinCode = string.format(
		'game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)',
		game.PlaceId,
		tostring(Config.CurrentJobId)
	)

	local body = HttpService:JSONEncode({
		username = "ZEOSO HUB",
		embeds = {{
			title = "ZEOSO HUB | Target Brainrot Detected",
			color = 14423100,
			fields = {
				{
					name = "Found (" .. tostring(#matches) .. ")",
					value = table.concat(lines, "\n"),
					inline = false
				},
				{
					name = "Server JobId",
					value = "`" .. tostring(Config.CurrentJobId) .. "`",
					inline = true
				},
				{
					name = "PlaceId",
					value = "`" .. tostring(game.PlaceId) .. "`",
					inline = true
				},
				{
					name = "Join Script",
					value = "```lua\n" .. joinCode .. "\n```",
					inline = false
				}
			}
		}}
	})

	return doHttpRequest({
		Url = url,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = body
	})
end

--// REAL RATE PARSING & FORMATTING
local function parseCompactNumber(str)
	if type(str) ~= "string" then return nil end
	local cleaned = str:gsub(",", ""):gsub("%$", ""):gsub("/s", ""):gsub("/S", ""):gsub("PER SEC", ""):upper()
	local numPart, suffix = cleaned:match("([%d%.]+)%s*([KMBT]?)")
	local n = tonumber(numPart)
	if not n then return nil end
	if suffix == "K" then return n * 1_000 end
	if suffix == "M" then return n * 1_000_000 end
	if suffix == "B" then return n * 1_000_000_000 end
	if suffix == "T" then return n * 1_000_000_000_000 end
	return n
end

local function parseRealPerSecondRate(obj)
	if not obj then return nil, nil end

	local parent = obj.Parent
	local checkObjs = { obj }
	if parent then table.insert(checkObjs, parent) end
	if parent and parent.Parent then table.insert(checkObjs, parent.Parent) end

	for _, target in ipairs(checkObjs) do
		for attrName, attrVal in pairs(target:GetAttributes()) do
			local low = attrName:lower()
			if low:find("rate") or low:find("income") or low:find("persec") or low:find("gen") or low:find("mps") or low:find("cps") then
				if type(attrVal) == "number" and attrVal > 0 then
					return attrVal, tostring(attrVal) .. "/s"
				elseif type(attrVal) == "string" then
					local parsed = parseCompactNumber(attrVal)
					if parsed and parsed > 0 then
						return parsed, attrVal
					end
				end
			end
		end
	end

	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		local raw = (obj.Text or ""):match("^%s*(.-)%s*$")
		if raw == "" or #raw > 120 then return nil, nil end

		local low = raw:lower()
		local hasPerSec = low:find("/s", 1, true) ~= nil
			or low:find("/sec", 1, true) ~= nil
			or low:find("per sec", 1, true) ~= nil

		local objNameLow = obj.Name:lower()
		local isRateNamed = objNameLow:find("rate")
			or objNameLow:find("income")
			or objNameLow:find("mps")
			or objNameLow:find("gen")
			or objNameLow:find("earn")
			or objNameLow:find("cash")

		if not hasPerSec and not isRateNamed then
			return nil, nil
		end
		if low:find("cost") or low:find("price") or low:find("buy") or low:find("rebirth") then
			return nil, nil
		end

		local val = parseCompactNumber(raw)
		if val and val > 0 then
			return val, raw
		end
	end

	return nil, nil
end

local function formatCompact(n)
	if n >= 1_000_000_000_000 then
		return string.format("%.2fT", n / 1_000_000_000_000)
	elseif n >= 1_000_000_000 then
		return string.format("%.2fB", n / 1_000_000_000)
	elseif n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("%.1fK", n / 1_000)
	end
	return tostring(math.floor(n))
end

local function getEffectiveMinValue()
	if Config.Only100MPlus then
		return math.max(Config.MinValue, 100_000_000)
	end
	return Config.MinValue
end

local function isInTargetRange(val)
	if not val then return false end
	return val >= getEffectiveMinValue() and val <= Config.MaxValue
end

local function extractDeepVisual(name, startObj, modelAncestor)
	if ImageOverrides[name] and tostring(ImageOverrides[name]) ~= "" then
		local ov = toOnlineThumbnail(ImageOverrides[name])
		if ov ~= "" then
			return ov, nil
		end
	end

	local searchRoots = {}
	if startObj then
		table.insert(searchRoots, startObj)
		if startObj.Parent then table.insert(searchRoots, startObj.Parent) end
		if startObj.Parent and startObj.Parent.Parent then table.insert(searchRoots, startObj.Parent.Parent) end
		if startObj.Parent and startObj.Parent.Parent and startObj.Parent.Parent.Parent then
			table.insert(searchRoots, startObj.Parent.Parent.Parent)
		end
	end
	if modelAncestor then
		table.insert(searchRoots, modelAncestor)
	end

	for _, rootObj in ipairs(searchRoots) do
		for attrName, attrVal in pairs(rootObj:GetAttributes()) do
			local low = attrName:lower()
			if (low:find("img") or low:find("image") or low:find("icon") or low:find("thumb") or low:find("asset")) and attrVal ~= nil then
				local thumb = toOnlineThumbnail(tostring(attrVal))
				if thumb ~= "" then
					return thumb, nil
				end
			end
		end

		if rootObj:IsA("ImageLabel") or rootObj:IsA("ImageButton") then
			local thumb = toOnlineThumbnail(rootObj.Image)
			if thumb ~= "" then return thumb, nil end
		end

		for _, desc in ipairs(rootObj:GetDescendants()) do
			if desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
				local thumb = toOnlineThumbnail(desc.Image)
				if thumb ~= "" then return thumb, nil end
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				local thumb = toOnlineThumbnail(desc.Texture)
				if thumb ~= "" then return thumb, nil end
			elseif desc:IsA("ShirtGraphic") then
				local thumb = toOnlineThumbnail(desc.Graphic)
				if thumb ~= "" then return thumb, nil end
			end
		end

		for _, desc in ipairs(rootObj:GetDescendants()) do
			if desc:IsA("MeshPart") and desc.TextureID ~= "" then
				local thumb = toOnlineThumbnail(desc.TextureID)
				if thumb ~= "" then return thumb, nil end
			elseif desc:IsA("SpecialMesh") and desc.TextureId ~= "" then
				local thumb = toOnlineThumbnail(desc.TextureId)
				if thumb ~= "" then return thumb, nil end
			end
		end
	end

	return "", modelAncestor
end

--// SCANNER
local function scanCurrentServer()
	local found = {}
	local seenKeys = {}

	local function findNearbyName(startObj, modelAncestor)
		local containers = {}
		if startObj.Parent then table.insert(containers, startObj.Parent) end
		if startObj.Parent and startObj.Parent.Parent then table.insert(containers, startObj.Parent.Parent) end
		if modelAncestor then table.insert(containers, modelAncestor) end

		for _, container in ipairs(containers) do
			for attrName, attrVal in pairs(container:GetAttributes()) do
				if type(attrVal) == "string" and #attrVal >= 2 and not parseCompactNumber(attrVal) then
					local low = attrName:lower()
					if low:find("name") or low:find("brainrot") or low:find("pet") or low:find("unit") or low:find("title") then
						return attrVal
					end
				end
			end

			for _, desc in ipairs(container:GetDescendants()) do
				if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc ~= startObj then
					local clean = (desc.Text or ""):match("^%s*(.-)%s*$")
					if clean and #clean >= 2 and #clean <= 50 then
						local low = clean:lower()
						local hasNum = parseCompactNumber(clean) ~= nil
						local isMoney = clean:match("^%$?[%d%.,]+%s*[KMBT]?/s?$") ~= nil
						local isNoise = low:find("steal") or low:find("collect") or low:find("locked") or low:find("owner")
						if not hasNum and not isMoney and not isNoise then
							return clean
						end
					end
				elseif desc:IsA("StringValue") then
					if #desc.Value >= 2 and not parseCompactNumber(desc.Value) then
						return desc.Value
					end
				end
			end
		end

		return nil
	end

	local function resolveAnchorPart(obj, modelAncestor)
		if modelAncestor then
			if modelAncestor.PrimaryPart then
				return modelAncestor.PrimaryPart
			end
			local bp = modelAncestor:FindFirstChildWhichIsA("BasePart", true)
			if bp then return bp end
		end
		local directPart = obj:FindFirstAncestorWhichIsA("BasePart")
		if directPart then return directPart end
		if obj.Parent then
			local siblingPart = obj.Parent:FindFirstChildWhichIsA("BasePart", true)
			if siblingPart then return siblingPart end
		end
		return nil
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			local val, rawRateText = parseRealPerSecondRate(obj)
			if isInTargetRange(val) then
				local modelAncestor = obj:FindFirstAncestorOfClass("Model")
				if modelAncestor then
					local mLow = modelAncestor.Name:lower()
					if mLow == "workspace" or mLow:find("map") or mLow:find("baseplate") then
						modelAncestor = nil
					end
				end

				local nearbyName = findNearbyName(obj, modelAncestor)
				if not nearbyName then
					local txt = obj.Text or ""
					for _, known in ipairs(KnownHighTierNames) do
						if txt:lower():find(known:lower(), 1, true) then
							nearbyName = known
							break
						end
					end
				end

				if not nearbyName and modelAncestor then
					local mLow = modelAncestor.Name:lower()
					if not mLow:find("stand") and not mLow:find("slot") and not mLow:find("base") and not mLow:find("podium") then
						nearbyName = modelAncestor.Name
					end
				end

				local finalName = nearbyName or ("Brainrot (" .. formatCompact(val) .. "/s)")
				local compactStr = formatCompact(val)
				local cleanRaw = (rawRateText or (compactStr .. "/s")):gsub("%s+", " ")
				local rateDisplay = string.format("%s  [%s/s]", cleanRaw, compactStr)
				local imgUrl, previewModel = extractDeepVisual(finalName, obj, modelAncestor)
				local anchorPart = resolveAnchorPart(obj, modelAncestor)

				local posKey = anchorPart and string.format("%d_%d", math.floor(anchorPart.Position.X / 4), math.floor(anchorPart.Position.Z / 4)) or "0"
				local key = finalName .. "_" .. tostring(math.floor(val)) .. "_" .. posKey

				if not seenKeys[key] then
					seenKeys[key] = true
					table.insert(found, {
						Name = finalName,
						Value = val,
						ValueText = compactStr,
						RateText = rateDisplay,
						Image = imgUrl,
						PreviewModel = previewModel,
						AnchorPart = anchorPart,
						JobId = Config.CurrentJobId,
					})
				end
			end
		end
	end

	table.sort(found, function(a, b)
		return a.Value > b.Value
	end)

	LastScannedMatches = found
	local topVal = (#found > 0 and found[1].Value) or 0
	markServer(Config.CurrentJobId, #found, topVal)
	return found
end

--// CHARACTER & MOVEMENT HELPERS
local function getRootPart()
	local char = LocalPlayer.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
end

--// TINY BLUE [GUESS] OVERHEAD TAG
local function attachHeadTag(char)
	if not char then return end
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if not head then return end

	for _, old in ipairs(head:GetChildren()) do
		if old.Name == "ZeosoHeadTag" or old.Name == "ZeosoOwnerTag" then
			pcall(function() old:Destroy() end)
		end
	end

	if not Config.HeadTagEnabled then return end

	local bbg = Instance.new("BillboardGui")
	bbg.Name = "ZeosoHeadTag"
	bbg.Adornee = head
	bbg.Size = UDim2.new(0, 56, 0, 14)
	bbg.StudsOffset = Vector3.new(0, 1.85, 0)
	bbg.AlwaysOnTop = true
	bbg.MaxDistance = 250
	bbg.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundColor3 = Color3.fromRGB(10, 20, 38)
	lbl.BackgroundTransparency = 0.25
	lbl.BorderSizePixel = 0
	lbl.Text = Config.HeadTagText
	lbl.TextColor3 = Color3.fromRGB(70, 175, 255)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 8
	lbl.Parent = bbg
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 3)
end

--// FLY TO BEST BRAINROT
local function clearFlyMovers(root)
	if not root then return end
	for _, name in ipairs({ "ZeosoBestBV", "ZeosoBestBG", "ZeosoCarpetBV", "ZeosoCarpetBG" }) do
		local old = root:FindFirstChild(name)
		if old then
			pcall(function() old:Destroy() end)
		end
	end
end

local function stopBestBrainrotFlight()
	isFlyingBest = false
	if activeBestFlyConn then
		activeBestFlyConn:Disconnect()
		activeBestFlyConn = nil
	end
	local root = getRootPart()
	if root then
		clearFlyMovers(root)
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
		end)
	end
end

local function resolveLiveTargetPosition(targetItem)
	if targetItem and targetItem.AnchorPart and targetItem.AnchorPart.Parent then
		return targetItem.AnchorPart.Position
	end
	if targetItem and targetItem.PreviewModel and targetItem.PreviewModel.Parent then
		local part = targetItem.PreviewModel.PrimaryPart or targetItem.PreviewModel:FindFirstChildWhichIsA("BasePart", true)
		if part then
			targetItem.AnchorPart = part
			return part.Position
		end
	end
	return nil
end

local function flyToBestBrainrot(specificItem)
	if isFlyingBest then
		stopBestBrainrotFlight()
		setStatus("Stopped Fly to Best Brainrot", Color3.fromRGB(235, 195, 110))
		return
	end

	if #LastScannedMatches == 0 then
		scanCurrentServer()
	end

	local targetItem = specificItem or LastScannedMatches[1]
	local rawPos = resolveLiveTargetPosition(targetItem)
	if not targetItem or not rawPos then
		scanCurrentServer()
		targetItem = specificItem or LastScannedMatches[1]
		rawPos = resolveLiveTargetPosition(targetItem)
	end

	if not targetItem or not rawPos then
		setStatus("No best brainrot found in server!", Color3.fromRGB(255, 115, 115))
		return
	end

	local root = getRootPart()
	if not root then
		setStatus("Character not ready!", Color3.fromRGB(255, 115, 115))
		return
	end

	clearFlyMovers(root)
	isFlyingBest = true

	local bv = Instance.new("BodyVelocity")
	bv.Name = "ZeosoBestBV"
	bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	bv.Velocity = Vector3.zero
	bv.Parent = root

	local bg = Instance.new("BodyGyro")
	bg.Name = "ZeosoBestBG"
	bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
	bg.P = 12000
	bg.CFrame = root.CFrame
	bg.Parent = root

	setStatus(
		string.format("Flying to BEST: %s (%s/s)...", targetItem.Name, targetItem.ValueText),
		Color3.fromRGB(255, 210, 110)
	)

	local startedAt = os.clock()
	activeBestFlyConn = RunService.Heartbeat:Connect(function(dt)
		if not isFlyingBest or not root or not root.Parent then
			stopBestBrainrotFlight()
			return
		end

		local livePos = resolveLiveTargetPosition(targetItem)
		if not livePos then
			stopBestBrainrotFlight()
			setStatus("Target brainrot no longer exists!", Color3.fromRGB(255, 120, 120))
			return
		end

		if os.clock() - startedAt > 25 then
			stopBestBrainrotFlight()
			setStatus("Fly to best timed out", Color3.fromRGB(235, 195, 110))
			return
		end

		local goalPos = livePos + Vector3.new(0, 3.5, 0)
		local delta = goalPos - root.Position
		local dist = delta.Magnitude

		if dist <= 5.5 then
			pcall(function()
				root.CFrame = CFrame.new(goalPos)
			end)
			stopBestBrainrotFlight()
			setStatus(
				string.format("Reached BEST: %s (%s/s)!", targetItem.Name, targetItem.ValueText),
				Color3.fromRGB(130, 255, 175)
			)
			return
		end

		local dir = delta.Unit
		local speed = math.min(Config.BestBrainrotFlySpeed, math.max(38, dist * 5.5))
		bv.Velocity = dir * speed
		pcall(function()
			bg.CFrame = CFrame.lookAt(root.Position, Vector3.new(goalPos.X, root.Position.Y, goalPos.Z))
			if dist < 24 then
				root.CFrame = CFrame.lookAt(root.Position + (dir * math.min(dist - 4.5, speed * dt * 0.65)), Vector3.new(goalPos.X, root.Position.Y, goalPos.Z))
			end
		end)
	end)
end

--// AUTO FLY TO CLOSEST PLAYER
local function findClosestPlayer()
	local root = getRootPart()
	if not root then return nil, nil, nil end

	local closestPlr = nil
	local closestRoot = nil
	local bestDist = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			local pRoot = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChildWhichIsA("BasePart")
			if pRoot and (not hum or hum.Health > 0) then
				local d = (pRoot.Position - root.Position).Magnitude
				if d < bestDist then
					bestDist = d
					closestPlr = plr
					closestRoot = pRoot
				end
			end
		end
	end

	return closestPlr, closestRoot, bestDist
end

local function stepFlyClosestPlayer()
	local root = getRootPart()
	if not root then return end

	local targetPlr, targetRoot, dist = findClosestPlayer()
	if not targetPlr or not targetRoot then
		setStatus("Fly Plr: No other player in server", Color3.fromRGB(235, 195, 110))
		return
	end

	local goalPos = targetRoot.Position + Vector3.new(0, 2.5, 0)
	local delta = goalPos - root.Position
	local mag = delta.Magnitude

	if mag > 4.5 then
		local dir = delta.Unit
		local moveSpeed = math.min(Config.ClosestPlayerFlySpeed, math.max(16, mag * 2.0))
		local stepDist = math.min(mag - 3.5, moveSpeed * 0.12)
		if stepDist > 0 then
			pcall(function()
				root.CFrame = CFrame.lookAt(root.Position + (dir * stepDist), Vector3.new(goalPos.X, root.Position.Y, goalPos.Z))
				root.AssemblyLinearVelocity = dir * math.min(moveSpeed, 38)
			end)
		end
	end

	setStatus(
		string.format("Flying to %s (%dm @ %d spd)", targetPlr.DisplayName, math.floor(dist or 0), Config.ClosestPlayerFlySpeed),
		Color3.fromRGB(165, 225, 255)
	)
end

--// IMPROVED INVISIBLE MODE
local function isBrainrotItemName(name)
	local low = (name or ""):lower()
	return low:find("brainrot", 1, true) ~= nil
		or low:find("pet", 1, true) ~= nil
		or low:find("unit", 1, true) ~= nil
		or low:find("carry", 1, true) ~= nil
end

local function recordAndHidePart(part, tuckUnderground)
	if not part or not part:IsA("BasePart") or part.Name == "HumanoidRootPart" then
		return
	end

	if not hiddenPartsState[part] then
		hiddenPartsState[part] = {
			transparency = part.Transparency,
			canCollide = part.CanCollide,
			anchored = part.Anchored,
			wasTucked = false,
		}
	end

	local saved = hiddenPartsState[part]
	pcall(function()
		part.Transparency = 1
		part.CanCollide = false
		if tuckUnderground and not part:IsDescendantOf(LocalPlayer.Character) then
			local root = getRootPart()
			local floorY = root and (root.Position.Y - 7) or -10
			local tx = root and root.Position.X or part.Position.X
			local tz = root and root.Position.Z or part.Position.Z
			part.Anchored = true
			part.CFrame = CFrame.new(tx, floorY, tz)
			saved.wasTucked = true
		end
	end)
end

local function applyImprovedInvisibleStep()
	local char = LocalPlayer.Character
	local root = getRootPart()
	if not char or not root then return end

	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			recordAndHidePart(desc, false)
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			if not hiddenPartsState[desc] then
				hiddenPartsState[desc] = { transparency = desc.Transparency, isDecal = true }
			end
			pcall(function() desc.Transparency = 1 end)
		elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			if desc.Name ~= "ZeosoHeadTag" then
				if not hiddenPartsState[desc] then
					hiddenPartsState[desc] = { enabled = desc.Enabled, isGui = true }
				end
				pcall(function() desc.Enabled = false end)
			end
		end
	end

	for _, item in ipairs(LastScannedMatches) do
		if item.AnchorPart and item.AnchorPart.Parent and not item.AnchorPart:IsDescendantOf(char) then
			if (item.AnchorPart.Position - root.Position).Magnitude <= 26 then
				recordAndHidePart(item.AnchorPart, true)
			end
		end
		if item.PreviewModel and item.PreviewModel.Parent and not item.PreviewModel:IsDescendantOf(char) then
			for _, p in ipairs(item.PreviewModel:GetDescendants()) do
				if p:IsA("BasePart") and (p.Position - root.Position).Magnitude <= 26 then
					recordAndHidePart(p, true)
				end
			end
		end
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and not obj:IsDescendantOf(char) and (obj.Position - root.Position).Magnitude <= 18 then
			local parentName = obj.Parent and obj.Parent.Name or ""
			if isBrainrotItemName(obj.Name) or isBrainrotItemName(parentName) then
				recordAndHidePart(obj, true)
			end
		end
	end
end

local function restoreInvisibleMode()
	for obj, saved in pairs(hiddenPartsState) do
		if obj and obj.Parent then
			pcall(function()
				if saved.isGui then
					obj.Enabled = saved.enabled
				elseif saved.isDecal then
					obj.Transparency = saved.transparency
				else
					obj.Transparency = saved.transparency
					obj.CanCollide = saved.canCollide
					if saved.wasTucked then
						obj.Anchored = saved.anchored
					end
				end
			end)
		end
	end
	table.clear(hiddenPartsState)
end

--// ANTI-RAGDOLL BYPASS
local function runAntiRagdollStep()
	local char = LocalPlayer.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum.PlatformStand = false
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			local state = hum:GetState()
			if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end

	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("Motor6D") then
			desc.Enabled = true
		elseif desc:IsA("BallSocketConstraint") or desc:IsA("HingeConstraint") then
			desc.Enabled = false
		elseif desc:IsA("BasePart") then
			pcall(function()
				desc.CanCollide = desc.Name ~= "HumanoidRootPart"
			end)
		end
	end
end

--// LAGGER MODE
local function runLaggerModeStep()
	local root = getRootPart()
	if not root then return end

	local affectedCount = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local pRoot = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChildWhichIsA("BasePart")
			if pRoot and (pRoot.Position - root.Position).Magnitude <= Config.LaggerRadius then
				affectedCount += 1
				pcall(function()
					if typeof(sethiddenproperty) == "function" then
						sethiddenproperty(LocalPlayer, "SimulationRadius", 140)
					end
					for _, part in ipairs(plr.Character:GetChildren()) do
						if part:IsA("BasePart") and not part.Anchored then
							part.AssemblyAngularVelocity = Vector3.new(0, 9, 0)
						end
					end
				end)
			end
		end
	end

	setStatus(
		string.format("Lagger ON | Nearby targets: %d", affectedCount),
		Color3.fromRGB(255, 175, 110)
	)
end

--// TOGGLEABLE DUELS SCRIPT (ONLY RUNS WHEN Config.DuelsScriptEnabled IS TRUE)
local function activateBatTool()
	local char = LocalPlayer.Character
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local batTool = nil

	if char then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and item.Name:lower():find("bat") then
				batTool = item
				break
			end
		end
	end

	if not batTool and backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and item.Name:lower():find("bat") then
				batTool = item
				if char then
					pcall(function() item.Parent = char end)
				end
				break
			end
		end
	end

	if batTool then
		pcall(function() batTool:Activate() end)
		return true
	end
	return false
end

local function runDuelsLagMoreStep()
	local root = getRootPart()
	if not root then return end

	local hitCount = 0
	local hasBat = activateBatTool()

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local pRoot = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChildWhichIsA("BasePart")
			if pRoot and (pRoot.Position - root.Position).Magnitude <= 35 then
				hitCount += 1
				pcall(function()
					if typeof(sethiddenproperty) == "function" then
						sethiddenproperty(LocalPlayer, "SimulationRadius", 160)
					end
					for _, part in ipairs(plr.Character:GetChildren()) do
						if part:IsA("BasePart") and not part.Anchored then
							part.AssemblyAngularVelocity = Vector3.new(0, 18, 0)
							part.AssemblyLinearVelocity += Vector3.new(0, 4, 0)
						end
					end
				end)
			end
		end
	end

	if hasBat then
		pcall(function()
			local char = LocalPlayer.Character
			local equipped = char and char:FindFirstChildWhichIsA("Tool")
			if equipped then equipped:Activate() end
		end)
	end

	setStatus(
		string.format("DUELS LAG MORE | Bat:%s | Targets:%d", hasBat and "HIT" or "READY", hitCount),
		Color3.fromRGB(255, 105, 115)
	)
end

local function applyDuelsSpeed24()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		pcall(function()
			if hum.WalkSpeed < Config.SpeedBoostValue then
				hum.WalkSpeed = Config.SpeedBoostValue
			end
		end)
	end
end

--// AUTO KICK AFTER BRAINROT IS IN YOUR BASE
local function executeKickNow(reasonText)
	if kickScheduled then return end
	kickScheduled = true
	setStatus(reasonText or "Brainrot in base! Kicking...", Color3.fromRGB(255, 110, 130))
	task.delay(0.25, function()
		pcall(function()
			LocalPlayer:Kick("[ZEOSO HUB] Auto-Kick: Brainrot secured in your base.")
		end)
	end)
end

local function isNearOwnBaseOrSlot(pos)
	if not pos then return false end
	local myNameLow = (LocalPlayer.Name or ""):lower()
	local myDisplayLow = (LocalPlayer.DisplayName or ""):lower()

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local nLow = obj.Name:lower()
			local pLow = (obj.Parent and obj.Parent.Name or ""):lower()
			local matchesBase = nLow:find("base", 1, true) ~= nil
				or nLow:find("slot", 1, true) ~= nil
				or nLow:find("podium", 1, true) ~= nil
				or pLow:find("base", 1, true) ~= nil
				or pLow:find("slot", 1, true) ~= nil
				or pLow:find("podium", 1, true) ~= nil

			if matchesBase then
				local matchesOwner = (myNameLow ~= "" and (nLow:find(myNameLow, 1, true) or pLow:find(myNameLow, 1, true)))
					or (myDisplayLow ~= "" and (nLow:find(myDisplayLow, 1, true) or pLow:find(myDisplayLow, 1, true)))
					or tostring(obj:GetAttribute("Owner") or ""):lower() == myNameLow
					or tostring(obj.Parent:GetAttribute("Owner") or ""):lower() == myNameLow

				if matchesOwner and (obj.Position - pos).Magnitude <= 18 then
					return true
				end
			end
		end
	end
	return false
end

local function checkBrainrotInBaseKick()
	if not Config.AutoKickAfterBase or kickScheduled then return end

	local char = LocalPlayer.Character
	local root = getRootPart()
	if not char or not root then return end

	if stealAttemptActive and isNearOwnBaseOrSlot(root.Position) then
		executeKickNow("Brainrot reached your base! Auto-kicking...")
		return
	end

	if stealAttemptActive and (os.clock() - stealAttemptTime >= 1.2) then
		local stillCarrying = false
		for _, child in ipairs(char:GetChildren()) do
			if (child:IsA("Model") or child:IsA("Tool")) and isBrainrotItemName(child.Name) then
				stillCarrying = true
				break
			end
		end
		if not stillCarrying and isNearOwnBaseOrSlot(root.Position) then
			executeKickNow("Brainrot banked in base! Auto-kicking...")
		end
	end
end

--// BUILD GUI IMMEDIATELY (DELTA SAFE)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZeosoHubGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local mountedOk = pcall(function()
	ScreenGui.Parent = GuiParent
end)
if not mountedOk or not ScreenGui.Parent then
	pcall(function()
		ScreenGui.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or CoreGui
	end)
end

local EspFolder = Instance.new("Folder")
EspFolder.Name = "ZeosoEspFolder"
pcall(function()
	EspFolder.Parent = ScreenGui.Parent or GuiParent
end)

local function isInsideOwnGui(obj)
	return obj:IsDescendantOf(ScreenGui)
end

local function fireGuiButton(btn)
	pcall(function()
		if typeof(firesignal) == "function" then
			firesignal(btn.MouseButton1Down)
			firesignal(btn.MouseButton1Click)
			firesignal(btn.Activated)
		end
	end)
	pcall(function()
		if typeof(getconnections) == "function" then
			for _, sigName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down" }) do
				local okConns, conns = pcall(getconnections, btn[sigName])
				if okConns and type(conns) == "table" then
					for _, conn in ipairs(conns) do
						pcall(function()
							if conn.Function then
								conn.Function()
							elseif type(conn.Fire) == "function" then
								conn:Fire()
							end
						end)
					end
				end
			end
		end
	end)
end

local function triggerCloneOnce()
	local used = 0
	local root = getRootPart()

	local char = LocalPlayer.Character
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local searchContainers = {}
	if char then table.insert(searchContainers, char) end
	if backpack then table.insert(searchContainers, backpack) end

	for _, container in ipairs(searchContainers) do
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") then
				local low = item.Name:lower()
				if low:find("clone") or low:find("decoy") or low:find("copy") or low:find("dupe") then
					pcall(function()
						if item.Parent == backpack and char then
							item.Parent = char
						end
						item:Activate()
					end)
					used += 1
				end
			end
		end
	end

	local pGui = PlayerGui or LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pGui then
		for _, guiObj in ipairs(pGui:GetDescendants()) do
			if guiObj.Parent and not isInsideOwnGui(guiObj) then
				if (guiObj:IsA("TextButton") or guiObj:IsA("ImageButton")) and guiObj.Visible then
					local txt = guiObj:IsA("TextButton") and guiObj.Text:lower() or ""
					local nm = guiObj.Name:lower()
					if txt:find("clone", 1, true) or nm:find("clone", 1, true) or txt:find("decoy", 1, true) then
						fireGuiButton(guiObj)
						used += 1
					end
				end
			end
		end
	end

	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("ProximityPrompt") and desc.Enabled then
			local combined = ((desc.ActionText or "") .. " " .. (desc.ObjectText or "") .. " " .. (desc.Parent and desc.Parent.Name or "")):lower()
			if combined:find("clone", 1, true) or combined:find("decoy", 1, true) or combined:find("copy", 1, true) then
				local inRange = true
				if root and desc.Parent then
					local tp = desc.Parent:IsA("BasePart") and desc.Parent or desc.Parent:FindFirstChildWhichIsA("BasePart", true)
					if tp then
						inRange = (root.Position - tp.Position).Magnitude <= 60
					end
				end
				if inRange then
					pcall(function()
						if typeof(fireproximityprompt) == "function" then
							fireproximityprompt(desc)
						else
							desc:InputHoldBegin()
							task.delay(0.1, function()
								pcall(function() desc:InputHoldEnd() end)
							end)
						end
					end)
					used += 1
				end
			end
		end
	end

	return used
end

--// AUTO STEAL (SUSTAINED HOLD + TRIGGER FALLBACK)
local function refreshSustainedStealHold()
	local root = getRootPart()
	if not root then return end

	local activeNow = {}
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("ProximityPrompt") and desc.Enabled then
			local combined = ((desc.ActionText or "") .. " " .. (desc.ObjectText or "") .. " " .. (desc.Parent and desc.Parent.Name or "")):lower()
			if combined:find("steal", 1, true) or combined:find("grab", 1, true) or combined:find("take", 1, true) or combined:find("yoink", 1, true) or combined:find("snatch", 1, true) then
				local distOk = true
				if desc.Parent then
					local tp = desc.Parent:IsA("BasePart") and desc.Parent or desc.Parent:FindFirstChildWhichIsA("BasePart", true)
					if tp then
						local maxRange = math.max((desc.MaxActivationDistance or 12) + 10, 26)
						distOk = (root.Position - tp.Position).Magnitude <= maxRange
					end
				end

				if distOk then
					activeNow[desc] = true
					pcall(function()
						if (desc.HoldDuration or 0) <= 0.05 and typeof(fireproximityprompt) == "function" then
							fireproximityprompt(desc)
						else
							if not heldPrompts[desc] then
								heldPrompts[desc] = true
								desc:InputHoldBegin()
							end
						end
					end)
					stealAttemptActive = true
					stealAttemptTime = os.clock()
				end
			end
		end
	end

	for promptObj in pairs(heldPrompts) do
		if not activeNow[promptObj] then
			heldPrompts[promptObj] = nil
			pcall(function()
				promptObj:InputHoldEnd()
			end)
		end
	end
end

local function releaseAllHeldPrompts()
	for promptObj in pairs(heldPrompts) do
		pcall(function()
			promptObj:InputHoldEnd()
		end)
	end
	table.clear(heldPrompts)
end

local function clearEspVisuals()
	for _, child in ipairs(EspFolder:GetChildren()) do
		child:Destroy()
	end
end

local function createEspTag(adornee, titleText, subText, accentColor)
	if not adornee or not adornee.Parent then return end

	local bbg = Instance.new("BillboardGui")
	bbg.Name = "ZeosoEspTag"
	bbg.Adornee = adornee
	bbg.Size = UDim2.new(0, 148, 0, 34)
	bbg.StudsOffset = Vector3.new(0, 3.2, 0)
	bbg.AlwaysOnTop = true
	bbg.MaxDistance = 400
	bbg.Parent = EspFolder

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	frame.BackgroundTransparency = 0.2
	frame.BorderColor3 = accentColor
	frame.BorderSizePixel = 1
	frame.Parent = bbg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 5)

	local topLbl = Instance.new("TextLabel")
	topLbl.Size = UDim2.new(1, -6, 0, 16)
	topLbl.Position = UDim2.new(0, 3, 0, 1)
	topLbl.BackgroundTransparency = 1
	topLbl.Text = titleText
	topLbl.TextColor3 = accentColor
	topLbl.Font = Enum.Font.GothamBold
	topLbl.TextSize = 10
	topLbl.TextTruncate = Enum.TextTruncate.AtEnd
	topLbl.Parent = frame

	local botLbl = Instance.new("TextLabel")
	botLbl.Size = UDim2.new(1, -6, 0, 14)
	botLbl.Position = UDim2.new(0, 3, 0, 17)
	botLbl.BackgroundTransparency = 1
	botLbl.Text = subText
	botLbl.TextColor3 = Color3.fromRGB(235, 235, 245)
	botLbl.Font = Enum.Font.Code
	botLbl.TextSize = 9
	botLbl.TextTruncate = Enum.TextTruncate.AtEnd
	botLbl.Parent = frame
end

local function refreshEspAll()
	clearEspVisuals()
	if not Config.EspAll then return end

	local root = getRootPart()
	local tagCount = 0
	local maxTags = 80

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local hrp = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChildWhichIsA("BasePart")
			if hrp and tagCount < maxTags then
				local dist = root and math.floor((root.Position - hrp.Position).Magnitude) or 0
				createEspTag(hrp, plr.DisplayName, dist .. "m | Player", Color3.fromRGB(255, 95, 110))
				tagCount += 1
			end
		end
	end

	for _, item in ipairs(LastScannedMatches) do
		if tagCount >= maxTags then break end
		if item.AnchorPart and item.AnchorPart.Parent then
			local dist = root and math.floor((root.Position - item.AnchorPart.Position).Magnitude) or 0
			createEspTag(
				item.AnchorPart,
				item.Name .. " (" .. item.ValueText .. "/s)",
				dist .. "m | " .. item.RateText,
				Color3.fromRGB(130, 255, 175)
			)
			tagCount += 1
		end
	end
end

UserInputService.JumpRequest:Connect(function()
	if not Config.InfJump then return end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
	if hum and root and hum.Health > 0 then
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
			root.AssemblyLinearVelocity = Vector3.new(
				root.AssemblyLinearVelocity.X,
				math.max(root.AssemblyLinearVelocity.Y, Config.JumpPowerLift),
				root.AssemblyLinearVelocity.Z
			)
		end)
	end
end)

--// SERVER JOINER (MULTI-ENDPOINT + DIRECT FALLBACK)
local function tryFetchServerBatch(sortOrder, cursorStr)
	local cursorParam = (cursorStr and cursorStr ~= "")
		and ("&cursor=" .. HttpService:UrlEncode(cursorStr))
		or ""

	local endpoints = {
		string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100%s", game.PlaceId, sortOrder, cursorParam),
		string.format("https://games.roblox.com/v1/games/%d/servers/0?sortOrder=%s&limit=100%s", game.PlaceId, sortOrder, cursorParam),
	}

	for _, url in ipairs(endpoints) do
		local ok, res = fetchUrlText(url)
		if ok and res then
			local decodedOk, data = pcall(function()
				return HttpService:JSONDecode(res)
			end)
			if decodedOk and type(data) == "table" and type(data.data) == "table" then
				return data
			end
		end
	end

	return nil
end

local function refillServerQueue(ignoreMarks)
	local sortOrder = Config.SortDescending and "Desc" or "Asc"
	local data = tryFetchServerBatch(sortOrder, Config.NextCursor)
	if not data then
		Config.NextCursor = ""
		data = tryFetchServerBatch(sortOrder, "")
	end
	if not data then
		return false
	end

	Config.NextCursor = data.nextPageCursor or ""

	local candidates = {}
	local queuedSet = {}
	for _, qId in ipairs(Config.ServerQueue) do
		queuedSet[qId] = true
	end

	for _, srv in ipairs(data.data) do
		local id = srv.id
		local playing = tonumber(srv.playing) or 0
		local maxPlayers = tonumber(srv.maxPlayers) or 99
		local validId = type(id) == "string" and #id >= 8 and id ~= game.JobId
		local hasSpace = playing > 0 and playing < maxPlayers
		local markedCheck = ignoreMarks or (not Config.SkipMarkedServers) or (not isServerMarked(id))

		if validId and hasSpace and markedCheck and not queuedSet[id] then
			queuedSet[id] = true
			table.insert(candidates, {
				id = id,
				playing = playing,
				maxPlayers = maxPlayers,
			})
		end
	end

	table.sort(candidates, function(a, b)
		if Config.PreferHighPop then
			return a.playing > b.playing
		else
			return a.playing < b.playing
		end
	end)

	for _, c in ipairs(candidates) do
		table.insert(Config.ServerQueue, c.id)
	end

	return #candidates > 0
end

local function popNextServerId()
	while #Config.ServerQueue > 0 do
		local nextId = table.remove(Config.ServerQueue, 1)
		if nextId and nextId ~= game.JobId then
			if (not Config.SkipMarkedServers) or (not isServerMarked(nextId)) then
				return nextId
			end
		end
	end

	for _ = 1, 2 do
		refillServerQueue(false)
		while #Config.ServerQueue > 0 do
			local nextId = table.remove(Config.ServerQueue, 1)
			if nextId and nextId ~= game.JobId then
				if (not Config.SkipMarkedServers) or (not isServerMarked(nextId)) then
					return nextId
				end
			end
		end
		if Config.NextCursor == "" then
			break
		end
	end

	if #Config.ServerQueue == 0 then
		refillServerQueue(true)
		while #Config.ServerQueue > 0 do
			local nextId = table.remove(Config.ServerQueue, 1)
			if nextId and nextId ~= game.JobId then
				return nextId
			end
		end
	end

	return nil
end

local function runTeleportCall(targetId, useFallbackPlace)
	pcall(setupDeltaAutoExec)
	local ok, err = pcall(function()
		if useFallbackPlace or not targetId or targetId == "" then
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		else
			TeleportService:TeleportToPlaceInstance(game.PlaceId, tostring(targetId), LocalPlayer)
		end
	end)
	return ok, err
end

local function executeServerHop(manualJobId, statusCallback)
	if os.clock() - lastHopAttempt < 1.5 then
		return false
	end
	lastHopAttempt = os.clock()
	isTeleporting = true

	local cleanManual = manualJobId and manualJobId:match("^%s*(.-)%s*$") or ""
	local targetId = (cleanManual ~= "") and cleanManual or popNextServerId()
	activeTargetId = targetId

	if statusCallback then
		if targetId then
			statusCallback("Joining server: " .. tostring(targetId):sub(1, 10) .. "...", Color3.fromRGB(165, 215, 255))
		else
			statusCallback("Hopping via PlaceId...", Color3.fromRGB(235, 195, 110))
		end
	end

	if targetId and cleanManual == "" then
		markServer(targetId, 0, 0)
	end

	local ok, err = runTeleportCall(targetId, targetId == nil)

	if not ok and targetId then
		local fbOk, fbErr = runTeleportCall(nil, true)
		if fbOk then
			ok = true
		else
			err = fbErr
		end
	end

	task.delay(3.5, function()
		isTeleporting = false
		activeTargetId = nil
	end)

	if not ok and statusCallback then
		statusCallback("Joiner retry/blocked: " .. tostring(err), Color3.fromRGB(255, 110, 110))
	end
	return ok
end

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
	if player and player ~= LocalPlayer then return end
	isTeleporting = false
	local failedId = activeTargetId
	activeTargetId = nil

	if failedId and (teleportResult == Enum.TeleportResult.GameFull or teleportResult == Enum.TeleportResult.GameEnded) then
		unmarkServer(failedId)
	end

	setStatus(
		string.format("Joiner failed (%s) — retrying...", tostring(teleportResult.Name)),
		Color3.fromRGB(255, 130, 120)
	)
end)

--// DARK OBSIDIAN UI + TARGETED RED ACCENTS
local function styleControl(frame, borderColor, bgColor, cornerRadius)
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, cornerRadius or 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = borderColor or Color3.fromRGB(68, 68, 86)
	stroke.Thickness = 1.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	if bgColor then
		frame.BackgroundColor3 = bgColor
	end
end

local function makeSideButton(name, text, yOffset, borderCol, textCol)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 108, 0, 30)
	btn.Position = UDim2.new(1, -122, 0.20, yOffset)
	btn.Text = text
	btn.TextColor3 = textCol
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 10
	btn.Active = true
	btn.Draggable = true
	btn.Parent = ScreenGui
	styleControl(btn, borderCol, Color3.fromRGB(18, 18, 24), 7)
	return btn
end

local SideToggle = makeSideButton("ZeosoSideToggle", "ZEOSO HUB", 0, Color3.fromRGB(220, 45, 65), Color3.fromRGB(245, 245, 250))
local SideDuelsToggleBtn = makeSideButton("ZeosoSideDuelsToggle", "DUELS: OFF", 34, Color3.fromRGB(235, 45, 60), Color3.fromRGB(255, 130, 140))
local SideDuelsLagBtn = makeSideButton("ZeosoSideDuelsLag", "LAG MORE: OFF", 68, Color3.fromRGB(235, 45, 60), Color3.fromRGB(255, 130, 140))
local SideSpeed24Btn = makeSideButton("ZeosoSideSpeed24", "SPD 24: OFF", 102, Color3.fromRGB(90, 185, 255), Color3.fromRGB(175, 225, 255))
local SideFlyBestBtn = makeSideButton("ZeosoSideFlyBest", "FLY BEST", 136, Color3.fromRGB(235, 180, 75), Color3.fromRGB(255, 225, 135))
local SideInvisBtn = makeSideButton("ZeosoSideInvis", "INVIS: OFF", 170, Color3.fromRGB(165, 115, 255), Color3.fromRGB(220, 195, 255))
local SideCloneBtn = makeSideButton("ZeosoSideClone", "CLONE: OFF", 204, Color3.fromRGB(85, 195, 155), Color3.fromRGB(175, 245, 215))
local SideStealBtn = makeSideButton("ZeosoSideSteal", "STEAL: OFF", 238, Color3.fromRGB(235, 55, 70), Color3.fromRGB(255, 155, 165))

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 380, 0, 592)
MainFrame.Position = UDim2.new(0.5, -190, 0.5, -296)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
styleControl(MainFrame, Color3.fromRGB(215, 42, 60), Color3.fromRGB(13, 13, 17), 10)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BorderSizePixel = 0
Header.Parent = MainFrame
styleControl(Header, Color3.fromRGB(195, 38, 55), Color3.fromRGB(22, 18, 24), 10)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -84, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "ZEOSO HUB"
TitleLabel.TextColor3 = Color3.fromRGB(245, 245, 252)
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 28, 0, 24)
MinimizeBtn.Position = UDim2.new(1, -66, 0.5, -12)
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 14
MinimizeBtn.Parent = Header
styleControl(MinimizeBtn, Color3.fromRGB(90, 90, 110), Color3.fromRGB(34, 34, 44), 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 24)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -12)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Parent = Header
styleControl(CloseBtn, Color3.fromRGB(255, 75, 90), Color3.fromRGB(165, 26, 40), 6)

--// TABS BAR: MAIN vs AUX DUELS
local MainTabBtn = Instance.new("TextButton")
MainTabBtn.Size = UDim2.new(0.485, 0, 0, 26)
MainTabBtn.Position = UDim2.new(0, 8, 0, 46)
MainTabBtn.Text = "MAIN"
MainTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MainTabBtn.Font = Enum.Font.GothamBlack
MainTabBtn.TextSize = 10
MainTabBtn.Parent = MainFrame
styleControl(MainTabBtn, Color3.fromRGB(220, 45, 65), Color3.fromRGB(42, 20, 26), 6)

local AuxDuelsTabBtn = Instance.new("TextButton")
AuxDuelsTabBtn.Size = UDim2.new(0.485, 0, 0, 26)
AuxDuelsTabBtn.Position = UDim2.new(0.507, 0, 0, 46)
AuxDuelsTabBtn.Text = "AUX DUELS"
AuxDuelsTabBtn.TextColor3 = Color3.fromRGB(210, 210, 225)
AuxDuelsTabBtn.Font = Enum.Font.GothamBlack
AuxDuelsTabBtn.TextSize = 10
AuxDuelsTabBtn.Parent = MainFrame
styleControl(AuxDuelsTabBtn, Color3.fromRGB(85, 85, 105), Color3.fromRGB(24, 24, 32), 6)

--// TAB 1 CONTAINER (MAIN)
local MainTabPage = Instance.new("Frame")
MainTabPage.Name = "MainTabPage"
MainTabPage.Size = UDim2.new(1, 0, 1, -104)
MainTabPage.Position = UDim2.new(0, 0, 0, 76)
MainTabPage.BackgroundTransparency = 1
MainTabPage.Parent = MainFrame

--// TAB 2 CONTAINER (AUX DUELS)
local AuxDuelsPage = Instance.new("Frame")
AuxDuelsPage.Name = "AuxDuelsPage"
AuxDuelsPage.Size = UDim2.new(1, 0, 1, -104)
AuxDuelsPage.Position = UDim2.new(0, 0, 0, 76)
AuxDuelsPage.BackgroundTransparency = 1
AuxDuelsPage.Visible = false
AuxDuelsPage.Parent = MainFrame

local function makeBtn(parent, text, pos, size, bg, fg, textSz, borderCol)
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.Text = text
	b.TextColor3 = fg or Color3.fromRGB(235, 235, 245)
	b.Font = Enum.Font.GothamBold
	b.TextSize = textSz or 10
	b.Parent = parent
	styleControl(b, borderCol or Color3.fromRGB(72, 72, 92), bg or Color3.fromRGB(24, 24, 32), 6)
	return b
end

local function makeBox(parent, placeholder, pos, size, initialText)
	local tb = Instance.new("TextBox")
	tb.Position = pos
	tb.Size = size
	tb.PlaceholderText = placeholder
	tb.Text = initialText or ""
	tb.TextColor3 = Color3.fromRGB(240, 240, 250)
	tb.PlaceholderColor3 = Color3.fromRGB(130, 130, 150)
	tb.Font = Enum.Font.Code
	tb.TextSize = 10
	tb.ClearTextOnFocus = false
	tb.Parent = parent
	styleControl(tb, Color3.fromRGB(78, 78, 98), Color3.fromRGB(20, 20, 27), 6)
	return tb
end

--// MAIN TAB CONTROLS
local MinStepBtn = makeBtn(MainTabPage, "MIN: 10M", UDim2.new(0, 8, 0, 2), UDim2.new(0.23, 0, 0, 26), Color3.fromRGB(25, 25, 34), Color3.fromRGB(175, 215, 255), 10)
local RangeBtn = makeBtn(MainTabPage, "10M - 50B", UDim2.new(0.26, 0, 0, 2), UDim2.new(0.23, 0, 0, 26), Color3.fromRGB(25, 25, 34), Color3.fromRGB(225, 225, 240), 9)
local AutoHopBtn = makeBtn(MainTabPage, "AUTO JOINER: OFF", UDim2.new(0.51, 0, 0, 2), UDim2.new(0.47, 0, 0, 26), Color3.fromRGB(26, 26, 36), Color3.fromRGB(255, 120, 130), 10, Color3.fromRGB(175, 55, 70))

local ScanNowBtn = makeBtn(MainTabPage, "SCAN SERVER", UDim2.new(0, 8, 0, 32), UDim2.new(0.32, 0, 0, 28), Color3.fromRGB(36, 30, 58), Color3.fromRGB(235, 225, 255), 10, Color3.fromRGB(125, 95, 205))
local FlyBestBtn = makeBtn(MainTabPage, "FLY BEST", UDim2.new(0.34, 0, 0, 32), UDim2.new(0.31, 0, 0, 28), Color3.fromRGB(54, 42, 22), Color3.fromRGB(255, 225, 135), 10, Color3.fromRGB(205, 155, 55))
local HopNowBtn = makeBtn(MainTabPage, "NEXT SERVER", UDim2.new(0.67, 0, 0, 32), UDim2.new(0.31, 0, 0, 28), Color3.fromRGB(26, 44, 66), Color3.fromRGB(180, 225, 255), 10, Color3.fromRGB(75, 145, 215))

local AutoCloneBtn = makeBtn(MainTabPage, "CLONE: OFF", UDim2.new(0, 8, 0, 64), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(22, 34, 32), Color3.fromRGB(165, 235, 205), 9)
local AutoStealBtn = makeBtn(MainTabPage, "STEAL: OFF", UDim2.new(0.255, 0, 0, 64), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(38, 22, 26), Color3.fromRGB(255, 165, 175), 9, Color3.fromRGB(185, 55, 70))
local KickAfterBaseBtn = makeBtn(MainTabPage, "KICK BASE: OFF", UDim2.new(0.50, 0, 0, 64), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(40, 22, 28), Color3.fromRGB(255, 150, 170), 8)
local AntiRagdollBtn = makeBtn(MainTabPage, "ANTI RAG: OFF", UDim2.new(0.745, 0, 0, 64), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(22, 34, 40), Color3.fromRGB(155, 230, 255), 8)

local LaggerModeBtn = makeBtn(MainTabPage, "LAGGER: OFF", UDim2.new(0, 8, 0, 94), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(40, 28, 20), Color3.fromRGB(255, 195, 145), 9)
local FlyClosestPlrBtn = makeBtn(MainTabPage, "FLY PLR: OFF", UDim2.new(0.255, 0, 0, 94), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(22, 32, 42), Color3.fromRGB(165, 225, 255), 9)
local InvisModeBtn = makeBtn(MainTabPage, "INVIS: OFF", UDim2.new(0.50, 0, 0, 94), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(32, 24, 46), Color3.fromRGB(215, 190, 255), 9)
local EspAllBtn = makeBtn(MainTabPage, "ESP ALL: OFF", UDim2.new(0.745, 0, 0, 94), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(22, 36, 28), Color3.fromRGB(160, 245, 190), 9)

local InfJumpBtn = makeBtn(MainTabPage, "INF JUMP: OFF", UDim2.new(0, 8, 0, 124), UDim2.new(0.235, 0, 0, 26), Color3.fromRGB(32, 26, 44), Color3.fromRGB(210, 185, 255), 9)
local SkipMarkedBtn = makeBtn(MainTabPage, "SKIP MARK: ON", UDim2.new(0.255, 0, 0, 124), UDim2.new(0.255, 0, 0, 26), Color3.fromRGB(22, 34, 28), Color3.fromRGB(145, 245, 180), 8)
local ClearMarksBtn = makeBtn(MainTabPage, "CLEAR", UDim2.new(0.525, 0, 0, 124), UDim2.new(0.21, 0, 0, 26), Color3.fromRGB(40, 22, 28), Color3.fromRGB(255, 165, 175), 9)
local ViewMarkedBtn = makeBtn(MainTabPage, "MARKED", UDim2.new(0.75, 0, 0, 124), UDim2.new(0.23, 0, 0, 26), Color3.fromRGB(32, 30, 48), Color3.fromRGB(215, 210, 250), 9)

local WebhookBox = makeBox(MainTabPage, "Paste Discord Webhook URL...", UDim2.new(0, 8, 0, 154), UDim2.new(0.74, 0, 0, 26), Config.WebhookUrl)
local TestHookBtn = makeBtn(MainTabPage, "TEST HOOK", UDim2.new(0.76, 0, 0, 154), UDim2.new(0.23, 0, 0, 26), Color3.fromRGB(38, 32, 62), Color3.fromRGB(230, 220, 255), 10)

local JobIdBox = makeBox(MainTabPage, "Target Server JobId (blank = queued server)...", UDim2.new(0, 8, 0, 184), UDim2.new(1, -16, 0, 26), "")

local ResultsList = Instance.new("ScrollingFrame")
ResultsList.Size = UDim2.new(1, -16, 1, -218)
ResultsList.Position = UDim2.new(0, 8, 0, 214)
ResultsList.ScrollBarThickness = 4
ResultsList.CanvasSize = UDim2.new(0, 0, 0, 0)
ResultsList.Parent = MainTabPage
styleControl(ResultsList, Color3.fromRGB(65, 65, 85), Color3.fromRGB(18, 18, 24), 7)

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = ResultsList

--// AUX DUELS TAB CONTROLS
local DuelsMasterBtn = makeBtn(
	AuxDuelsPage,
	"DUELS SCRIPT: OFF (TAP TO ENABLE)",
	UDim2.new(0, 8, 0, 6),
	UDim2.new(1, -16, 0, 36),
	Color3.fromRGB(32, 22, 26),
	Color3.fromRGB(255, 145, 155),
	11,
	Color3.fromRGB(215, 42, 60)
)

local DuelsLagMoreBtn = makeBtn(
	AuxDuelsPage,
	"LAG MORE (FAST BAT HIT): OFF",
	UDim2.new(0, 8, 0, 50),
	UDim2.new(1, -16, 0, 42),
	Color3.fromRGB(36, 20, 24),
	Color3.fromRGB(255, 130, 140),
	11,
	Color3.fromRGB(225, 48, 65)
)

local DuelsSpeed24Btn = makeBtn(
	AuxDuelsPage,
	"SPEED BOOST 24: OFF",
	UDim2.new(0, 8, 0, 100),
	UDim2.new(1, -16, 0, 42),
	Color3.fromRGB(22, 32, 44),
	Color3.fromRGB(165, 225, 255),
	11,
	Color3.fromRGB(85, 175, 245)
)

local DuelsAntiRagBtn = makeBtn(
	AuxDuelsPage,
	"DUELS ANTI-RAGDOLL: OFF",
	UDim2.new(0, 8, 0, 150),
	UDim2.new(0.48, -10, 0, 34),
	Color3.fromRGB(22, 34, 40),
	Color3.fromRGB(165, 235, 255),
	10
)

local DuelsInvisBtn = makeBtn(
	AuxDuelsPage,
	"DUELS INVIS: OFF",
	UDim2.new(0.50, 2, 0, 150),
	UDim2.new(0.50, -10, 0, 34),
	Color3.fromRGB(32, 24, 46),
	Color3.fromRGB(215, 190, 255),
	10
)

local DuelsInfoBox = Instance.new("TextLabel")
DuelsInfoBox.Size = UDim2.new(1, -16, 0, 96)
DuelsInfoBox.Position = UDim2.new(0, 8, 0, 194)
DuelsInfoBox.Text = "• DUELS SCRIPT: Stays OFF until toggled ON (side or tab).\n• LAG MORE: Rapidly triggers bat/tool hits near rivals.\n• SPEED BOOST 24: Keeps WalkSpeed at 24 while active."
DuelsInfoBox.TextColor3 = Color3.fromRGB(215, 215, 230)
DuelsInfoBox.Font = Enum.Font.GothamSemibold
DuelsInfoBox.TextSize = 10
DuelsInfoBox.TextWrapped = true
DuelsInfoBox.TextXAlignment = Enum.TextXAlignment.Left
DuelsInfoBox.TextYAlignment = Enum.TextYAlignment.Top
DuelsInfoBox.Parent = AuxDuelsPage
styleControl(DuelsInfoBox, Color3.fromRGB(68, 68, 88), Color3.fromRGB(20, 20, 27), 7)

--// SHARED BOTTOM STATUS BAR
StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -16, 0, 22)
StatusLabel.Position = UDim2.new(0, 8, 1, -26)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = string.format("ZEOSO HUB Ready | Tag: [GUESS] | ID:%s", tostring(Config.CurrentJobId):sub(1, 10))
StatusLabel.TextColor3 = Color3.fromRGB(175, 225, 195)
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextSize = 10
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame

local function switchTab(tabName)
	playUiSound("click")
	local isDuels = (tabName == "duels")
	MainTabPage.Visible = not isDuels
	AuxDuelsPage.Visible = isDuels

	if isDuels then
		AuxDuelsTabBtn.BackgroundColor3 = Color3.fromRGB(48, 22, 28)
		AuxDuelsTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		MainTabBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
		MainTabBtn.TextColor3 = Color3.fromRGB(200, 200, 215)
		setStatus("AUX DUELS tab active", Color3.fromRGB(255, 130, 140))
	else
		MainTabBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 26)
		MainTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		AuxDuelsTabBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
		AuxDuelsTabBtn.TextColor3 = Color3.fromRGB(200, 200, 215)
		setStatus("MAIN tab active", Color3.fromRGB(185, 215, 255))
	end
end

MainTabBtn.MouseButton1Click:Connect(function() switchTab("main") end)
AuxDuelsTabBtn.MouseButton1Click:Connect(function() switchTab("duels") end)

local function clearResults()
	for _, child in ipairs(ResultsList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function attachCardVisual(card, item)
	if item.Image and item.Image ~= "" then
		local thumb = Instance.new("ImageLabel")
		thumb.Size = UDim2.new(0, 54, 0, 54)
		thumb.Position = UDim2.new(0, 5, 0.5, -27)
		thumb.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
		thumb.Image = item.Image
		thumb.ScaleType = Enum.ScaleType.Fit
		thumb.Parent = card
		Instance.new("UICorner", thumb).CornerRadius = UDim.new(0, 6)
		return
	end

	if item.PreviewModel and item.PreviewModel.Parent then
		local okVp = pcall(function()
			local vp = Instance.new("ViewportFrame")
			vp.Size = UDim2.new(0, 54, 0, 54)
			vp.Position = UDim2.new(0, 5, 0.5, -27)
			vp.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
			vp.Ambient = Color3.fromRGB(205, 205, 220)
			vp.LightColor = Color3.fromRGB(255, 255, 255)
			vp.LightDirection = Vector3.new(-1, -2, -1)
			vp.Parent = card
			Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 6)

			local clone = item.PreviewModel:Clone()
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
					d:Destroy()
				end
			end
			clone.Parent = vp

			local cf, size = clone:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z, 2)
			local dist = maxDim * 1.65

			local cam = Instance.new("Camera")
			cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist * 0.65, dist * 0.35, dist * 0.85), cf.Position)
			cam.Parent = vp
			vp.CurrentCamera = cam
		end)
		if okVp then return end
	end

	local fallback = Instance.new("ImageLabel")
	fallback.Size = UDim2.new(0, 54, 0, 54)
	fallback.Position = UDim2.new(0, 5, 0.5, -27)
	fallback.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
	fallback.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	fallback.ScaleType = Enum.ScaleType.Fit
	fallback.Parent = card
	Instance.new("UICorner", fallback).CornerRadius = UDim.new(0, 6)
end

local function addBrainrotCard(item, index)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -8, 0, 66)
	card.LayoutOrder = index
	card.Parent = ResultsList
	styleControl(card, Color3.fromRGB(72, 72, 92), Color3.fromRGB(24, 24, 33), 7)

	attachCardVisual(card, item)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -138, 0, 20)
	nameLbl.Position = UDim2.new(0, 65, 0, 5)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = (index == 1 and "★ " or "") .. item.Name
	nameLbl.TextColor3 = index == 1 and Color3.fromRGB(255, 220, 115) or Color3.fromRGB(245, 245, 252)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 12
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Parent = card

	local rateLbl = Instance.new("TextLabel")
	rateLbl.Size = UDim2.new(1, -138, 0, 18)
	rateLbl.Position = UDim2.new(0, 65, 0, 25)
	rateLbl.BackgroundTransparency = 1
	rateLbl.Text = "Real Rate: " .. item.RateText
	rateLbl.TextColor3 = Color3.fromRGB(130, 250, 175)
	rateLbl.Font = Enum.Font.GothamBold
	rateLbl.TextSize = 10
	rateLbl.TextXAlignment = Enum.TextXAlignment.Left
	rateLbl.TextTruncate = Enum.TextTruncate.AtEnd
	rateLbl.Parent = card

	local idLbl = Instance.new("TextLabel")
	idLbl.Size = UDim2.new(1, -138, 0, 14)
	idLbl.Position = UDim2.new(0, 65, 0, 45)
	idLbl.BackgroundTransparency = 1
	idLbl.Text = "ID: " .. tostring(item.JobId)
	idLbl.TextColor3 = Color3.fromRGB(165, 165, 190)
	idLbl.Font = Enum.Font.Code
	idLbl.TextSize = 9
	idLbl.TextXAlignment = Enum.TextXAlignment.Left
	idLbl.TextTruncate = Enum.TextTruncate.AtEnd
	idLbl.Parent = card

	local flyCardBtn = Instance.new("TextButton")
	flyCardBtn.Size = UDim2.new(0, 64, 0, 22)
	flyCardBtn.Position = UDim2.new(1, -70, 0, 8)
	flyCardBtn.Text = "FLY HERE"
	flyCardBtn.TextColor3 = Color3.fromRGB(255, 245, 220)
	flyCardBtn.Font = Enum.Font.GothamBold
	flyCardBtn.TextSize = 9
	flyCardBtn.Parent = card
	styleControl(flyCardBtn, Color3.fromRGB(205, 155, 55), Color3.fromRGB(58, 44, 22), 5)

	local copyIdBtn = Instance.new("TextButton")
	copyIdBtn.Size = UDim2.new(0, 64, 0, 22)
	copyIdBtn.Position = UDim2.new(1, -70, 0, 35)
	copyIdBtn.Text = "COPY ID"
	copyIdBtn.TextColor3 = Color3.fromRGB(225, 225, 245)
	copyIdBtn.Font = Enum.Font.GothamBold
	copyIdBtn.TextSize = 9
	copyIdBtn.Parent = card
	styleControl(copyIdBtn, Color3.fromRGB(95, 95, 120), Color3.fromRGB(34, 34, 46), 5)

	flyCardBtn.MouseButton1Click:Connect(function()
		playUiSound("click")
		flyToBestBrainrot(item)
	end)

	copyIdBtn.MouseButton1Click:Connect(function()
		playUiSound("click")
		if typeof(setclipboard) == "function" then
			pcall(setclipboard, tostring(item.JobId))
			copyIdBtn.Text = "COPIED"
			task.delay(1.2, function()
				if copyIdBtn.Parent then copyIdBtn.Text = "COPY ID" end
			end)
		end
	end)
end

local function showMarkedServersList()
	clearResults()
	local idx = 0
	for jobId, meta in pairs(Config.VisitedServers) do
		idx += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 44)
		row.LayoutOrder = idx
		row.Parent = ResultsList
		styleControl(row, Color3.fromRGB(68, 68, 88), Color3.fromRGB(22, 22, 30), 6)

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -72, 1, -6)
		lbl.Position = UDim2.new(0, 8, 0, 3)
		lbl.BackgroundTransparency = 1
		lbl.Text = string.format("ID: %s\nMatches: %d | Top: %s/s", tostring(jobId), meta.matches or 0, formatCompact(meta.topValue or 0))
		lbl.TextColor3 = Color3.fromRGB(225, 225, 240)
		lbl.Font = Enum.Font.Code
		lbl.TextSize = 9
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Parent = row

		local joinBtn = Instance.new("TextButton")
		joinBtn.Size = UDim2.new(0, 58, 0, 24)
		joinBtn.Position = UDim2.new(1, -64, 0.5, -12)
		joinBtn.Text = "JOIN"
		joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		joinBtn.Font = Enum.Font.GothamBold
		joinBtn.TextSize = 9
		joinBtn.Parent = row
		styleControl(joinBtn, Color3.fromRGB(85, 155, 225), Color3.fromRGB(30, 54, 82), 5)

		joinBtn.MouseButton1Click:Connect(function()
			playUiSound("click")
			executeServerHop(tostring(jobId), setStatus)
		end)
	end
	ResultsList.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
	setStatus("Showing " .. tostring(idx) .. " marked server IDs", Color3.fromRGB(190, 200, 245))
end

local function refreshScanUI(allowWebhook)
	Config.WebhookUrl = WebhookBox.Text
	clearResults()
	local matches = scanCurrentServer()
	for i, item in ipairs(matches) do
		addBrainrotCard(item, i)
	end
	ResultsList.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)

	local markedCount = countMarkedServers()
	if #matches > 0 then
		if allowWebhook ~= false then
			pcall(sendWebhookAlert, matches)
		end
		playUiSound("alert")
		setStatus(
			string.format("Top: %s (%s/s) | %d match(es)", matches[1].Name, matches[1].ValueText, #matches),
			Color3.fromRGB(130, 255, 175)
		)
		if Config.StopOnMatch and Config.AutoHop then
			Config.AutoHop = false
			AutoHopBtn.Text = "AUTO JOINER: OFF (FOUND)"
			AutoHopBtn.TextColor3 = Color3.fromRGB(130, 255, 175)
		end
		return true
	else
		setStatus(
			string.format("Marked:%d | Q:%d | No match in %s", markedCount, #Config.ServerQueue, tostring(Config.CurrentJobId):sub(1, 10)),
			Color3.fromRGB(235, 195, 110)
		)
		return false
	end
end

local function syncCloneVisuals()
	local label = Config.AutoClone and "CLONE: ON" or "CLONE: OFF"
	local col = Config.AutoClone and Color3.fromRGB(130, 255, 175) or Color3.fromRGB(165, 235, 205)
	AutoCloneBtn.Text = label
	AutoCloneBtn.TextColor3 = col
	SideCloneBtn.Text = label
	SideCloneBtn.TextColor3 = col
end

local function syncStealVisuals()
	local label = Config.AutoSteal and "STEAL: ON" or "STEAL: OFF"
	local col = Config.AutoSteal and Color3.fromRGB(255, 95, 110) or Color3.fromRGB(255, 165, 175)
	AutoStealBtn.Text = label
	AutoStealBtn.TextColor3 = col
	SideStealBtn.Text = label
	SideStealBtn.TextColor3 = col
end

local function syncLaggerVisuals()
	local label = Config.LaggerMode and "LAGGER: ON" or "LAGGER: OFF"
	local col = Config.LaggerMode and Color3.fromRGB(255, 175, 110) or Color3.fromRGB(255, 195, 145)
	LaggerModeBtn.Text = label
	LaggerModeBtn.TextColor3 = col
end

local function syncDuelsMasterVisuals()
	local tabLabel = Config.DuelsScriptEnabled and "DUELS SCRIPT: ON" or "DUELS SCRIPT: OFF (TAP TO ENABLE)"
	local sideLabel = Config.DuelsScriptEnabled and "DUELS: ON" or "DUELS: OFF"
	local col = Config.DuelsScriptEnabled and Color3.fromRGB(130, 255, 175) or Color3.fromRGB(255, 130, 140)
	DuelsMasterBtn.Text = tabLabel
	DuelsMasterBtn.TextColor3 = col
	SideDuelsToggleBtn.Text = sideLabel
	SideDuelsToggleBtn.TextColor3 = col
end

local function syncDuelsLagVisuals()
	local label = Config.DuelsLagMore and "LAG MORE (FAST BAT HIT): ON" or "LAG MORE (FAST BAT HIT): OFF"
	local sideLabel = Config.DuelsLagMore and "LAG MORE: ON" or "LAG MORE: OFF"
	local col = Config.DuelsLagMore and Color3.fromRGB(255, 85, 100) or Color3.fromRGB(255, 130, 140)
	DuelsLagMoreBtn.Text = label
	DuelsLagMoreBtn.TextColor3 = col
	SideDuelsLagBtn.Text = sideLabel
	SideDuelsLagBtn.TextColor3 = col
end

local function syncDuelsSpeed24Visuals()
	local label = Config.DuelsSpeed24 and "SPEED BOOST 24: ON" or "SPEED BOOST 24: OFF"
	local sideLabel = Config.DuelsSpeed24 and "SPD 24: ON" or "SPD 24: OFF"
	local col = Config.DuelsSpeed24 and Color3.fromRGB(130, 255, 175) or Color3.fromRGB(165, 225, 255)
	DuelsSpeed24Btn.Text = label
	DuelsSpeed24Btn.TextColor3 = col
	SideSpeed24Btn.Text = sideLabel
	SideSpeed24Btn.TextColor3 = col
end

local function syncInvisVisuals()
	local mainLabel = Config.InvisibleMode and "INVIS: ON" or "INVIS: OFF"
	local sideLabel = Config.InvisibleMode and "INVIS: ON" or "INVIS: OFF"
	local duelsLabel = Config.InvisibleMode and "DUELS INVIS: ON" or "DUELS INVIS: OFF"
	local col = Config.InvisibleMode and Color3.fromRGB(130, 255, 175) or Color3.fromRGB(215, 190, 255)
	InvisModeBtn.Text = mainLabel
	InvisModeBtn.TextColor3 = col
	SideInvisBtn.Text = sideLabel
	SideInvisBtn.TextColor3 = col
	DuelsInvisBtn.Text = duelsLabel
	DuelsInvisBtn.TextColor3 = col
end

local function syncAntiRagdollVisuals()
	local label = Config.AntiRagdoll and "ANTI RAG: ON" or "ANTI RAG: OFF"
	local duelsLabel = Config.AntiRagdoll and "DUELS ANTI-RAGDOLL: ON" or "DUELS ANTI-RAGDOLL: OFF"
	local col = Config.AntiRagdoll and Color3.fromRGB(130, 255, 195) or Color3.fromRGB(155, 230, 255)
	AntiRagdollBtn.Text = label
	AntiRagdollBtn.TextColor3 = col
	DuelsAntiRagBtn.Text = duelsLabel
	DuelsAntiRagBtn.TextColor3 = col
end

local function toggleDuelsScript()
	Config.DuelsScriptEnabled = not Config.DuelsScriptEnabled
	playUiSound(Config.DuelsScriptEnabled and "on" or "off")
	if Config.DuelsScriptEnabled then
		Config.DuelsLagMore = true
		Config.DuelsSpeed24 = true
		applyDuelsSpeed24()
		setStatus("Duels Script ENABLED (Lag More + Speed 24)", Color3.fromRGB(130, 255, 175))
	else
		Config.DuelsLagMore = false
		Config.DuelsSpeed24 = false
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum.WalkSpeed = 16 end)
		end
		setStatus("Duels Script OFF", Color3.fromRGB(195, 200, 215))
	end
	syncDuelsMasterVisuals()
	syncDuelsLagVisuals()
	syncDuelsSpeed24Visuals()
end

local function toggleAutoClone()
	Config.AutoClone = not Config.AutoClone
	playUiSound(Config.AutoClone and "on" or "off")
	syncCloneVisuals()
	if Config.AutoClone then
		triggerCloneOnce()
		setStatus("Full Auto Clone: ON", Color3.fromRGB(130, 255, 175))
	else
		setStatus("Full Auto Clone: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local function toggleAutoSteal()
	Config.AutoSteal = not Config.AutoSteal
	playUiSound(Config.AutoSteal and "on" or "off")
	syncStealVisuals()
	if Config.AutoSteal then
		refreshSustainedStealHold()
		setStatus("Auto Steal: ON", Color3.fromRGB(130, 255, 175))
	else
		releaseAllHeldPrompts()
		setStatus("Auto Steal: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local function toggleLaggerMode()
	Config.LaggerMode = not Config.LaggerMode
	playUiSound(Config.LaggerMode and "on" or "off")
	syncLaggerVisuals()
	if Config.LaggerMode then
		runLaggerModeStep()
	else
		setStatus("Lagger Mode: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local function toggleDuelsLagMore()
	Config.DuelsLagMore = not Config.DuelsLagMore
	if Config.DuelsLagMore and not Config.DuelsScriptEnabled then
		Config.DuelsScriptEnabled = true
	end
	playUiSound(Config.DuelsLagMore and "on" or "off")
	syncDuelsMasterVisuals()
	syncDuelsLagVisuals()
	if Config.DuelsLagMore then
		runDuelsLagMoreStep()
	else
		setStatus("Duels Lag More: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local function toggleDuelsSpeed24()
	Config.DuelsSpeed24 = not Config.DuelsSpeed24
	if Config.DuelsSpeed24 and not Config.DuelsScriptEnabled then
		Config.DuelsScriptEnabled = true
	end
	playUiSound(Config.DuelsSpeed24 and "on" or "off")
	syncDuelsMasterVisuals()
	syncDuelsSpeed24Visuals()
	if Config.DuelsSpeed24 then
		applyDuelsSpeed24()
		setStatus("Speed Boost 24: ON", Color3.fromRGB(130, 255, 175))
	else
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum.WalkSpeed = 16 end)
		end
		setStatus("Speed Boost 24: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local function toggleInvisibleMode()
	Config.InvisibleMode = not Config.InvisibleMode
	playUiSound(Config.InvisibleMode and "on" or "off")
	syncInvisVisuals()
	if Config.InvisibleMode then
		applyImprovedInvisibleStep()
		setStatus("Invisible Mode: ON (Cloaked + Brainrot Hidden)", Color3.fromRGB(130, 255, 175))
	else
		restoreInvisibleMode()
		setStatus("Invisible Mode: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local function toggleAntiRagdoll()
	Config.AntiRagdoll = not Config.AntiRagdoll
	playUiSound(Config.AntiRagdoll and "on" or "off")
	syncAntiRagdollVisuals()
	if Config.AntiRagdoll then
		runAntiRagdollStep()
		setStatus("Anti-Ragdoll Bypass: ON", Color3.fromRGB(130, 255, 195))
	else
		setStatus("Anti-Ragdoll Bypass: OFF", Color3.fromRGB(195, 200, 215))
	end
end

local minSteps = { 10_000_000, 50_000_000, 100_000_000, 250_000_000 }
local minStepIndex = 1

MinStepBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	minStepIndex += 1
	if minStepIndex > #minSteps then minStepIndex = 1 end
	Config.MinValue = minSteps[minStepIndex]
	MinStepBtn.Text = "MIN: " .. formatCompact(Config.MinValue)
	refreshScanUI(false)
	if Config.EspAll then refreshEspAll() end
end)

RangeBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	Config.Only100MPlus = not Config.Only100MPlus
	if Config.Only100MPlus then
		RangeBtn.Text = "100M - 50B+"
		RangeBtn.TextColor3 = Color3.fromRGB(255, 195, 85)
	else
		RangeBtn.Text = "10M - 50B"
		RangeBtn.TextColor3 = Color3.fromRGB(225, 225, 240)
	end
	refreshScanUI(false)
end)

AutoHopBtn.MouseButton1Click:Connect(function()
	Config.AutoHop = not Config.AutoHop
	playUiSound(Config.AutoHop and "on" or "off")
	if Config.AutoHop then
		AutoHopBtn.Text = "AUTO JOINER: ON"
		AutoHopBtn.TextColor3 = Color3.fromRGB(130, 255, 175)
		task.spawn(function()
			refillServerQueue(false)
			if not isTeleporting then
				local foundMatch = refreshScanUI(true)
				if not foundMatch or not Config.StopOnMatch then
					executeServerHop(nil, setStatus)
				end
			end
		end)
	else
		AutoHopBtn.Text = "AUTO JOINER: OFF"
		AutoHopBtn.TextColor3 = Color3.fromRGB(255, 120, 130)
	end
end)

FlyBestBtn.MouseButton1Click:Connect(function() playUiSound("click"); flyToBestBrainrot(nil) end)
SideFlyBestBtn.MouseButton1Click:Connect(function() playUiSound("click"); flyToBestBrainrot(nil) end)

AutoCloneBtn.MouseButton1Click:Connect(toggleAutoClone)
SideCloneBtn.MouseButton1Click:Connect(toggleAutoClone)

AutoStealBtn.MouseButton1Click:Connect(toggleAutoSteal)
SideStealBtn.MouseButton1Click:Connect(toggleAutoSteal)

InvisModeBtn.MouseButton1Click:Connect(toggleInvisibleMode)
SideInvisBtn.MouseButton1Click:Connect(toggleInvisibleMode)
DuelsInvisBtn.MouseButton1Click:Connect(toggleInvisibleMode)

DuelsMasterBtn.MouseButton1Click:Connect(toggleDuelsScript)
SideDuelsToggleBtn.MouseButton1Click:Connect(toggleDuelsScript)

DuelsLagMoreBtn.MouseButton1Click:Connect(toggleDuelsLagMore)
SideDuelsLagBtn.MouseButton1Click:Connect(toggleDuelsLagMore)

DuelsSpeed24Btn.MouseButton1Click:Connect(toggleDuelsSpeed24)
SideSpeed24Btn.MouseButton1Click:Connect(toggleDuelsSpeed24)

KickAfterBaseBtn.MouseButton1Click:Connect(function()
	Config.AutoKickAfterBase = not Config.AutoKickAfterBase
	playUiSound(Config.AutoKickAfterBase and "on" or "off")
	kickScheduled = false
	if Config.AutoKickAfterBase then
		KickAfterBaseBtn.Text = "KICK BASE: ON"
		KickAfterBaseBtn.TextColor3 = Color3.fromRGB(255, 110, 130)
		setStatus("Kick After Brainrot in Base: ON", Color3.fromRGB(255, 110, 130))
	else
		KickAfterBaseBtn.Text = "KICK BASE: OFF"
		KickAfterBaseBtn.TextColor3 = Color3.fromRGB(255, 150, 170)
		setStatus("Kick After Brainrot in Base: OFF", Color3.fromRGB(195, 200, 215))
	end
end)

AntiRagdollBtn.MouseButton1Click:Connect(toggleAntiRagdoll)
DuelsAntiRagBtn.MouseButton1Click:Connect(toggleAntiRagdoll)

LaggerModeBtn.MouseButton1Click:Connect(toggleLaggerMode)

FlyClosestPlrBtn.MouseButton1Click:Connect(function()
	Config.FlyClosestPlayer = not Config.FlyClosestPlayer
	playUiSound(Config.FlyClosestPlayer and "on" or "off")
	FlyClosestPlrBtn.Text = Config.FlyClosestPlayer and "FLY PLR: ON" or "FLY PLR: OFF"
	FlyClosestPlrBtn.TextColor3 = Config.FlyClosestPlayer and Color3.fromRGB(130, 255, 175) or Color3.fromRGB(165, 225, 255)
	if Config.FlyClosestPlayer then
		stepFlyClosestPlayer()
	else
		setStatus("Fly Closest Player: OFF", Color3.fromRGB(195, 200, 215))
	end
end)

EspAllBtn.MouseButton1Click:Connect(function()
	Config.EspAll = not Config.EspAll
	playUiSound(Config.EspAll and "on" or "off")
	if Config.EspAll then
		EspAllBtn.Text = "ESP ALL: ON"
		EspAllBtn.TextColor3 = Color3.fromRGB(130, 255, 175)
		refreshEspAll()
		setStatus("ESP All enabled (Players + Brainrots)", Color3.fromRGB(130, 255, 175))
	else
		EspAllBtn.Text = "ESP ALL: OFF"
		EspAllBtn.TextColor3 = Color3.fromRGB(160, 245, 190)
		clearEspVisuals()
		setStatus("ESP All disabled", Color3.fromRGB(195, 200, 215))
	end
end)

InfJumpBtn.MouseButton1Click:Connect(function()
	Config.InfJump = not Config.InfJump
	playUiSound(Config.InfJump and "on" or "off")
	if Config.InfJump then
		InfJumpBtn.Text = "INF JUMP: ON"
		InfJumpBtn.TextColor3 = Color3.fromRGB(130, 255, 175)
		setStatus("Infinite Jump ON", Color3.fromRGB(130, 255, 175))
	else
		InfJumpBtn.Text = "INF JUMP: OFF"
		InfJumpBtn.TextColor3 = Color3.fromRGB(210, 185, 255)
		setStatus("Infinite Jump OFF", Color3.fromRGB(195, 200, 215))
	end
end)

SkipMarkedBtn.MouseButton1Click:Connect(function()
	Config.SkipMarkedServers = not Config.SkipMarkedServers
	playUiSound(Config.SkipMarkedServers and "on" or "off")
	if Config.SkipMarkedServers then
		SkipMarkedBtn.Text = "SKIP MARK: ON"
		SkipMarkedBtn.TextColor3 = Color3.fromRGB(145, 245, 180)
	else
		SkipMarkedBtn.Text = "SKIP MARK: OFF"
		SkipMarkedBtn.TextColor3 = Color3.fromRGB(235, 185, 110)
	end
end)

ClearMarksBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	Config.VisitedServers = {}
	Config.ServerQueue = {}
	Config.NextCursor = ""
	pcall(saveMarkedServers)
	markServer(Config.CurrentJobId, 0, 0)
	setStatus("Cleared marks & queue | Marked: 1", Color3.fromRGB(255, 175, 180))
end)

ViewMarkedBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	showMarkedServersList()
end)

TestHookBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	Config.WebhookUrl = WebhookBox.Text
	local ok, err = sendWebhookAlert({
		{ Name = "Dragon Cannelloni", RateText = "$250M/s [250.0M/s]", JobId = Config.CurrentJobId }
	})
	if ok then
		setStatus("Webhook alert sent!", Color3.fromRGB(130, 255, 175))
	else
		setStatus("Webhook error: " .. tostring(err), Color3.fromRGB(255, 110, 110))
	end
end)

ScanNowBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	refreshScanUI(true)
	if Config.EspAll then refreshEspAll() end
end)

HopNowBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	local manual = JobIdBox.Text:match("^%s*(.-)%s*$")
	executeServerHop(manual ~= "" and manual or nil, setStatus)
end)

MinimizeBtn.MouseButton1Click:Connect(function()
	playUiSound("click")
	MainFrame.Visible = not MainFrame.Visible
end)

CloseBtn.MouseButton1Click:Connect(function()
	playUiSound("off")
	Config.AutoHop = false
	Config.AutoClone = false
	Config.AutoSteal = false
	Config.AutoKickAfterBase = false
	Config.AntiRagdoll = false
	Config.LaggerMode = false
	Config.DuelsScriptEnabled = false
	Config.DuelsLagMore = false
	Config.DuelsSpeed24 = false
	Config.FlyClosestPlayer = false
	Config.InvisibleMode = false
	Config.EspAll = false
	releaseAllHeldPrompts()
	restoreInvisibleMode()
	stopBestBrainrotFlight()
	clearEspVisuals()
	ScreenGui:Destroy()
end)

SideToggle.MouseButton1Click:Connect(function()
	playUiSound("click")
	MainFrame.Visible = not MainFrame.Visible
end)

if LocalPlayer.Character then
	pcall(attachHeadTag, LocalPlayer.Character)
	if Config.DuelsScriptEnabled and Config.DuelsSpeed24 then
		applyDuelsSpeed24()
	end
end

LocalPlayer.CharacterAdded:Connect(function(newChar)
	task.wait(0.35)
	pcall(attachHeadTag, newChar)
	if Config.DuelsScriptEnabled and Config.DuelsSpeed24 then
		applyDuelsSpeed24()
	end
	if Config.AntiRagdoll then
		runAntiRagdollStep()
	end
	if Config.InvisibleMode then
		applyImprovedInvisibleStep()
	end
end)

RunService.Heartbeat:Connect(function()
	if not ScreenGui.Parent then return end
	local now = os.clock()

	if Config.InvisibleMode and (now - lastInvisTick >= 0.14) then
		lastInvisTick = now
		applyImprovedInvisibleStep()
	end

	if Config.AutoKickAfterBase and (now - lastBaseCheckTick >= 0.28) then
		lastBaseCheckTick = now
		checkBrainrotInBaseKick()
	end

	if Config.AntiRagdoll and (now - lastRagdollTick >= 0.14) then
		lastRagdollTick = now
		runAntiRagdollStep()
	end

	if Config.DuelsScriptEnabled then
		if Config.DuelsSpeed24 and (now - lastSpeedTick >= 0.12) then
			lastSpeedTick = now
			applyDuelsSpeed24()
		end

		if Config.DuelsLagMore and (now - lastDuelsTick >= 0.03) then
			lastDuelsTick = now
			runDuelsLagMoreStep()
		end
	end

	if Config.AutoClone and (now - lastCloneTick >= 0.5) then
		lastCloneTick = now
		triggerCloneOnce()
	end

	if Config.AutoSteal and (now - lastStealRefreshTick >= 0.45) then
		lastStealRefreshTick = now
		refreshSustainedStealHold()
	end

	if Config.FlyClosestPlayer and (now - lastFlyPlayerTick >= 0.12) then
		lastFlyPlayerTick = now
		stepFlyClosestPlayer()
	end

	if Config.LaggerMode and (now - lastLaggerTick >= 0.35) then
		lastLaggerTick = now
		runLaggerModeStep()
	end

	if Config.EspAll and (now - lastEspTick >= 1.8) then
		lastEspTick = now
		refreshEspAll()
	end
end)

task.spawn(function()
	task.wait(1.2)
	if ScreenGui.Parent then
		pcall(refreshScanUI, true)
		pcall(refillServerQueue, false)
	end

	while ScreenGui.Parent do
		task.wait(Config.HopDelay)
		if Config.AutoHop and ScreenGui.Parent and not isTeleporting then
			local foundMatch = refreshScanUI(true)
			if not foundMatch or not Config.StopOnMatch then
				executeServerHop(nil, setStatus)
			end
		end
	end
end)

print("[ZEOSO HUB] Loaded.")
