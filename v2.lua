--[[
	VAULT  v2  —  standalone script
	Library: WindUI-Shiny (Xyraniz/VaultUI)

	Tabs:  ESP  |  Hide  |  Lock On  |  2D  |  Colors  |  Settings

	Reopen the menu with Right Shift or the floating "Open Vault" bubble.

	Lock On assumptions (all changeable in the tab):
	  - a click nominates whoever you aimed at; the lock only fires once
	    he actually loses health, so wall shots are ignored
	  - the lock is bound to that exact character, so a respawn releases it
	  - your position is saved the moment you lock on and restored when the
	    target dies, when the timer runs out, or when you press the break key
--]]

--=====================================================================
--  SERVICES
--=====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--=====================================================================
--  LOAD WINDUI
--=====================================================================

local WindUI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Xyraniz/VaultUI/main/Libraries/WindUI-Shiny/source.lua"
))()

--=====================================================================
--  SHARED HELPERS
--=====================================================================

local HasDrawing = pcall(function()
	local t = Drawing.new("Line")
	t:Remove()
end)

local function getGuiParent()
	if gethui then
		local ok, res = pcall(gethui)
		if ok and res then return res end
	end
	if pcall(function() return CoreGui.Name end) then return CoreGui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function isTeammate(player)
	return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function humOf(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player)
	local hum = humOf(player)
	return hum ~= nil and hum.Health > 0
end

local function newDrawing(class, props)
	local d = Drawing.new(class)
	for k, v in pairs(props) do d[k] = v end
	return d
end

--=====================================================================
--  ESP
--=====================================================================

local ESP = {}

ESP.Settings = {
	Enabled             = false,
	TeamCheck           = true,
	MaxDistance         = 1500,

	Highlight           = true,
	FillTransparency    = 0.65,
	OutlineTransparency = 0,

	Names               = true,
	Health              = true,
	Distance            = true,
	TextSize            = 14,

	Boxes               = false,
	BoxThickness        = 1,
	HealthBars          = false,
	Tracers             = false,
	TracerOrigin        = "Bottom",

	UseTeamColor        = false,
	Color               = Color3.fromRGB(0, 170, 255),
	OutlineColor        = Color3.fromRGB(255, 255, 255),
	TextColor           = Color3.fromRGB(255, 255, 255),
}

ESP.Objects = {}

ESP.Container = Instance.new("Folder")
ESP.Container.Name = "Vault_" .. tostring(math.random(1e5, 1e6))
ESP.Container.Parent = getGuiParent()

function ESP:Create(player)
	if player == LocalPlayer or self.Objects[player] then return end
	local s = self.Settings
	local o = {}

	o.Highlight                     = Instance.new("Highlight")
	o.Highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	o.Highlight.FillTransparency    = s.FillTransparency
	o.Highlight.OutlineTransparency = s.OutlineTransparency
	o.Highlight.Enabled             = false
	o.Highlight.Parent              = self.Container

	o.Billboard             = Instance.new("BillboardGui")
	o.Billboard.Size        = UDim2.new(0, 220, 0, 60)
	o.Billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	o.Billboard.AlwaysOnTop = true
	o.Billboard.MaxDistance = math.huge
	o.Billboard.Enabled     = false
	o.Billboard.Parent      = self.Container

	o.Label                        = Instance.new("TextLabel")
	o.Label.BackgroundTransparency = 1
	o.Label.Size                   = UDim2.fromScale(1, 1)
	o.Label.Font                   = Enum.Font.GothamBold
	o.Label.TextSize               = s.TextSize
	o.Label.TextColor3             = s.TextColor
	o.Label.TextStrokeTransparency = 0.35
	o.Label.RichText               = true
	o.Label.Parent                 = o.Billboard

	if HasDrawing then
		o.BoxOutline = newDrawing("Square", { Thickness = 3, Filled = false, Visible = false,
			Color = Color3.new(0, 0, 0), Transparency = 0.55, ZIndex = 1 })
		o.Box        = newDrawing("Square", { Thickness = 1, Filled = false, Visible = false,
			Color = s.Color, ZIndex = 2 })
		o.BarOutline = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false,
			Color = Color3.new(0, 0, 0), Transparency = 0.6, ZIndex = 2 })
		o.Bar        = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false,
			Color = Color3.fromRGB(80, 255, 120), ZIndex = 3 })
		o.Tracer     = newDrawing("Line", { Thickness = 1, Visible = false,
			Color = s.Color, ZIndex = 2 })
	end

	self.Objects[player] = o
end

function ESP:HideOne(o)
	o.Highlight.Enabled = false
	o.Billboard.Enabled = false
	if o.Box then
		o.Box.Visible, o.BoxOutline.Visible = false, false
		o.Bar.Visible, o.BarOutline.Visible = false, false
		o.Tracer.Visible = false
	end
end

function ESP:HideAll()
	for _, o in pairs(self.Objects) do self:HideOne(o) end
end

function ESP:Remove(player)
	local o = self.Objects[player]
	if not o then return end
	if o.Highlight then o.Highlight:Destroy() end
	if o.Billboard then o.Billboard:Destroy() end
	if o.Box then
		o.Box:Remove(); o.BoxOutline:Remove()
		o.Bar:Remove(); o.BarOutline:Remove()
		o.Tracer:Remove()
	end
	self.Objects[player] = nil
end

local function tracerOrigin(mode, viewport)
	if mode == "Mouse" then
		local m = UserInputService:GetMouseLocation()
		return Vector2.new(m.X, m.Y)
	elseif mode == "Center" then
		return viewport / 2
	end
	return Vector2.new(viewport.X / 2, viewport.Y)
end

function ESP:Update(player, o)
	local s = self.Settings
	local camera = workspace.CurrentCamera
	if not (s.Enabled and camera) then return self:HideOne(o) end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum and hum.Health > 0) then return self:HideOne(o) end
	if s.TeamCheck and isTeammate(player) then return self:HideOne(o) end

	local dist = (camera.CFrame.Position - root.Position).Magnitude
	if dist > s.MaxDistance then return self:HideOne(o) end

	local color = s.Color
	if s.UseTeamColor and player.TeamColor then color = player.TeamColor.Color end

	local hpPct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	local hpCol = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(80, 255, 120), hpPct)

	if s.Highlight then
		o.Highlight.Adornee             = char
		o.Highlight.FillColor           = color
		o.Highlight.OutlineColor        = s.OutlineColor
		o.Highlight.FillTransparency    = s.FillTransparency
		o.Highlight.OutlineTransparency = s.OutlineTransparency
		o.Highlight.Enabled             = true
	else
		o.Highlight.Enabled = false
	end

	if s.Names or s.Health or s.Distance then
		local lines = {}
		if s.Names then
			local n = player.DisplayName
			if n ~= player.Name then n = n .. " (@" .. player.Name .. ")" end
			table.insert(lines, n)
		end
		if s.Health then
			table.insert(lines, string.format('<font color="#%s">%d HP</font>',
				hpCol:ToHex(), math.floor(hum.Health + 0.5)))
		end
		if s.Distance then
			table.insert(lines, string.format("%d studs", math.floor(dist)))
		end
		o.Label.Text        = table.concat(lines, "\n")
		o.Label.TextSize    = s.TextSize
		o.Label.TextColor3  = s.TextColor
		o.Billboard.Adornee = char:FindFirstChild("Head") or root
		o.Billboard.Enabled = true
	else
		o.Billboard.Enabled = false
	end

	if not o.Box then return end

	if not (s.Boxes or s.Tracers or s.HealthBars) then
		o.Box.Visible, o.BoxOutline.Visible = false, false
		o.Bar.Visible, o.BarOutline.Visible = false, false
		o.Tracer.Visible = false
		return
	end

	local center, onScreen = camera:WorldToViewportPoint(root.Position)
	if not onScreen then
		o.Box.Visible, o.BoxOutline.Visible = false, false
		o.Bar.Visible, o.BarOutline.Visible = false, false
		o.Tracer.Visible = false
		return
	end

	local top    = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3.1, 0))
	local bottom = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.4, 0))
	local height = math.abs(top.Y - bottom.Y)
	local width  = height / 2
	local pos    = Vector2.new(center.X - width / 2, top.Y)

	if s.Boxes then
		o.Box.Size, o.Box.Position   = Vector2.new(width, height), pos
		o.Box.Color, o.Box.Thickness = color, s.BoxThickness
		o.Box.Visible                = true
		o.BoxOutline.Size            = o.Box.Size
		o.BoxOutline.Position        = pos
		o.BoxOutline.Thickness       = s.BoxThickness + 2
		o.BoxOutline.Visible         = true
	else
		o.Box.Visible, o.BoxOutline.Visible = false, false
	end

	if s.HealthBars then
		local barX = pos.X - 6
		o.BarOutline.Size     = Vector2.new(4, height)
		o.BarOutline.Position = Vector2.new(barX - 1, pos.Y)
		o.BarOutline.Visible  = true
		o.Bar.Size     = Vector2.new(2, height * hpPct)
		o.Bar.Position = Vector2.new(barX, pos.Y + height * (1 - hpPct))
		o.Bar.Color    = hpCol
		o.Bar.Visible  = true
	else
		o.Bar.Visible, o.BarOutline.Visible = false, false
	end

	if s.Tracers then
		o.Tracer.From    = tracerOrigin(s.TracerOrigin, camera.ViewportSize)
		o.Tracer.To      = Vector2.new(center.X, bottom.Y)
		o.Tracer.Color   = color
		o.Tracer.Visible = true
	else
		o.Tracer.Visible = false
	end
end

--=====================================================================
--  HIDER  (one switch, hides everything about the character)
--=====================================================================

local Hider = {
	Enabled = false,
	Target  = "Teammates", -- Teammates | Enemies | Everyone
}

local ENABLE_CLASSES = {
	BillboardGui = true, SurfaceGui = true,
	ParticleEmitter = true, Trail = true, Beam = true,
	Fire = true, Smoke = true, Sparkles = true,
	PointLight = true, SpotLight = true, SurfaceLight = true,
}

Hider._hum   = {}   -- [humanoid] = {nameDist, healthDist}
Hider._decal = {}   -- [decal]    = original transparency
Hider._gui   = {}   -- [gui/fx]   = original .Enabled
Hider._extra = {}   -- objects hidden outside the character (weapons)
Hider._wasOn = false
Hider._clock = 0
Hider.Interval = 0.2

function Hider:ShouldHide(player)
	if not self.Enabled then return false end
	if self.Target == "Everyone"  then return true end
	if self.Target == "Teammates" then return isTeammate(player) end
	return not isTeammate(player)
end

function Hider:Process(d, hidden)
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = hidden and 1 or 0

	elseif d:IsA("Decal") or d:IsA("Texture") then
		if hidden then
			if self._decal[d] == nil then self._decal[d] = d.Transparency end
			d.Transparency = 1
		elseif self._decal[d] ~= nil then
			d.Transparency = self._decal[d]
			self._decal[d] = nil
		end

	elseif ENABLE_CLASSES[d.ClassName] then
		if hidden then
			if self._gui[d] == nil then self._gui[d] = d.Enabled end
			d.Enabled = false
		elseif self._gui[d] ~= nil then
			d.Enabled = self._gui[d]
			self._gui[d] = nil
		end
	end
end

function Hider:Apply(char, hidden, extras)
	for _, d in ipairs(char:GetDescendants()) do
		self:Process(d, hidden)
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		if hidden then
			if not self._hum[hum] then
				self._hum[hum] = { hum.NameDisplayDistance, hum.HealthDisplayDistance }
			end
			hum.NameDisplayDistance   = 0
			hum.HealthDisplayDistance = 0
		elseif self._hum[hum] then
			hum.NameDisplayDistance   = self._hum[hum][1]
			hum.HealthDisplayDistance = self._hum[hum][2]
			self._hum[hum] = nil
		end
	end

	-- guns / models welded to the character but parented somewhere else.
	-- rescanned each pass so weapon swaps are picked up.
	if hidden and extras then
		local anchor = char:FindFirstChild("HumanoidRootPart")
			or char:FindFirstChildWhichIsA("BasePart")

		if anchor then
			local models = {}
			for _, part in ipairs(anchor:GetConnectedParts(true)) do
				if not part:IsDescendantOf(char) then
					local model = part:FindFirstAncestorOfClass("Model")
					if model and model ~= char and not model:IsDescendantOf(char) then
						models[model] = true
					else
						self:Process(part, true)
						extras[part], self._extra[part] = true, true
					end
				end
			end
			for model in pairs(models) do
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")
						or ENABLE_CLASSES[d.ClassName] then
						self:Process(d, true)
						extras[d], self._extra[d] = true, true
					end
				end
			end
		end
	end
end

function Hider:RestoreAll()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then pcall(self.Apply, self, char, false, nil) end
	end
	for obj in pairs(self._extra) do
		pcall(function() if obj.Parent then self:Process(obj, false) end end)
	end
	self._extra = {}
	for hum, v in pairs(self._hum) do
		pcall(function()
			hum.NameDisplayDistance   = v[1]
			hum.HealthDisplayDistance = v[2]
		end)
	end
	self._hum = {}
	for d, orig in pairs(self._decal) do
		pcall(function() d.Transparency = orig end)
	end
	self._decal = {}
	for g, orig in pairs(self._gui) do
		pcall(function() g.Enabled = orig end)
	end
	self._gui = {}
end

function Hider:Step(dt)
	if not self.Enabled then
		if self._wasOn then
			self._wasOn = false
			self:RestoreAll()
		end
		return
	end
	self._wasOn = true

	self._clock = self._clock + dt
	if self._clock < self.Interval then return end
	self._clock = 0

	local extras = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local char = player.Character
			if char then
				pcall(self.Apply, self, char, self:ShouldHide(player), extras)
			end
		end
	end

	for obj in pairs(self._extra) do
		if not extras[obj] then
			pcall(function() if obj.Parent then self:Process(obj, false) end end)
			self._extra[obj] = nil
		end
	end
end

--=====================================================================
--  LOCK ON  (fling to the target, come back when they die)
--=====================================================================

local Lock = {}

Lock.Settings = {
	Enabled       = false,
	Trigger       = "Mouse Click", -- Mouse Click | Keybind
	LockKey       = "E",
	BreakKey      = "X",
	TeamCheck     = true,
	RequireTool   = false,
	ClickThruGui  = false, -- fire even when a game GUI swallowed the click

	MaxDistance   = 400,   -- raycast length
	Tolerance     = 40,    -- px of slack around the crosshair, 0 = pixel perfect
	RequireHit    = true,  -- only lock once he actually loses health
	HitWindow     = 0.6,   -- seconds the shot has to land in
	HitFallback   = true,  -- if the game exposes no health at all, lock on click
	RelockDelay   = 0.5,   -- seconds you can't lock again after a release
	ReturnHold    = 0.5,   -- seconds we pin you to the saved spot

	Mode          = "Follow Behind", -- Follow Behind | Fling
	Offset        = 4,
	Height        = 0,
	Smooth        = 1,
	Spin          = 90,
	CameraLock    = true,

	ReturnOnDeath = true,
	Timeout       = 15,

	-- games that don't use a normal Humanoid death need these
	BreakOnJump   = true,  -- he teleported (respawn, reset, lobby)
	JumpStuds     = 50,    -- studs in one step that counts as a teleport
	BreakOnHeal   = true,  -- his health snapped back up = new life
	Debug         = false, -- print what his humanoid is doing
}

Lock.Target       = nil   -- Player
Lock.TargetChar   = nil   -- the exact character model we locked onto
Lock.Origin       = nil
Lock.Started      = 0
Lock.Restore      = nil
Lock.RestoreUntil = 0
Lock.CooldownEnd  = 0
Lock.TargetConns  = {}
Lock.Pending      = nil   -- candidate waiting for the shot to land
Lock.LastPos      = nil
Lock.LastHealth   = nil
Lock.DebugClock   = 0

local RAY_FILTER = (function()
	local ok, v = pcall(function() return Enum.RaycastFilterType.Exclude end)
	if ok and v then return v end
	return Enum.RaycastFilterType.Blacklist
end)()

local function playerFromInstance(inst)
	local node = inst
	while node and node ~= workspace do
		local plr = Players:GetPlayerFromCharacter(node)
		if plr then return plr end
		node = node.Parent
	end
	return nil
end

-- ray through the crosshair. effect parts, bullets and floating gun models
-- get skipped instead of eating the shot; a solid wall stops the search.
function Lock:RayTarget()
	local s = self.Settings
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local m   = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)

	local ignore = {}
	if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end

	local params = RaycastParams.new()
	params.FilterType  = RAY_FILTER
	params.IgnoreWater = true

	local origin, dir = ray.Origin, ray.Direction * s.MaxDistance

	for _ = 1, 8 do
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, dir, params)
		if not hit then return nil end

		local player = playerFromInstance(hit.Instance)
		if player then return player end

		-- a real wall blocks the shot, anything else we shoot through
		if hit.Instance.CanCollide and hit.Instance.Anchored then return nil end
		table.insert(ignore, hit.Instance)
	end

	return nil
end

-- slack for when the ray clips a hitbox edge or a weird welded model
function Lock:NearestToCrosshair()
	local s = self.Settings
	if s.Tolerance <= 0 then return nil end

	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local m = UserInputService:GetMouseLocation()
	local mousePos = Vector2.new(m.X, m.Y)

	local best, bestDist = nil, s.Tolerance

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and isAlive(player) then
			if not (s.TeamCheck and isTeammate(player)) then
				local root = rootOf(player)
				if root then
					local sp, onScreen = camera:WorldToViewportPoint(root.Position)
					if onScreen then
						local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
						local worldDist = (camera.CFrame.Position - root.Position).Magnitude
						if d < bestDist and worldDist <= s.MaxDistance then
							best, bestDist = player, d
						end
					end
				end
			end
		end
	end

	return best
end

function Lock:Pick()
	local s = self.Settings

	local player = self:RayTarget()
	if not player then player = self:NearestToCrosshair() end
	if not player or player == LocalPlayer then return nil end
	if not isAlive(player) then return nil end
	if s.TeamCheck and isTeammate(player) then return nil end

	return player
end

function Lock:ClearPending()
	self.Pending = nil
end

-- your game keeps Humanoid.Health untouched (that's why death detection
-- needed the teleport check), so watching only Humanoid.Health never fires.
-- grab every number that looks like health instead: the humanoid, any
-- NumberValue/IntValue named health/hp anywhere on the character or the
-- player, and any numeric attribute with a health-ish name.
local function looksLikeHealth(name)
	local n = string.lower(name)
	return n:find("health") ~= nil or n:find("hp") ~= nil or n:find("hitpoint") ~= nil
end

function Lock:HealthSnapshot(player)
	local values, attrs, count = {}, {}, 0
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")

	if hum then
		values[hum] = hum.Health
		count = count + 1
	end

	local function scanValues(root)
		if not root then return end
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("NumberValue") or d:IsA("IntValue")) and looksLikeHealth(d.Name) then
				values[d] = d.Value
				count = count + 1
			end
		end
	end
	scanValues(char)
	scanValues(player)

	for _, holder in ipairs({ char, hum }) do
		if holder then
			local ok, list = pcall(function() return holder:GetAttributes() end)
			if ok and list then
				for name, val in pairs(list) do
					if type(val) == "number" and looksLikeHealth(name) then
						table.insert(attrs, { holder = holder, name = name, value = val })
						count = count + 1
					end
				end
			end
		end
	end

	return { values = values, attrs = attrs }, count
end

function Lock:DamageSeen(pending)
	for inst, old in pairs(pending.values) do
		if inst.Parent then
			local cur = inst:IsA("Humanoid") and inst.Health or inst.Value
			if cur < old - 0.01 then return true end
			if cur > old then pending.values[inst] = cur end -- heals reset the baseline
		end
	end

	for _, a in ipairs(pending.attrs) do
		local cur = a.holder:GetAttribute(a.name)
		if type(cur) == "number" then
			if cur < a.value - 0.01 then return true end
			if cur > a.value then a.value = cur end
		end
	end

	return false
end

-- a click only nominates someone. the lock fires when he actually takes
-- damage, so shooting a wall in front of him does nothing.
function Lock:TryLock(player)
	local s = self.Settings

	if not s.RequireHit then
		return self:Engage(player)
	end

	local snap, count = self:HealthSnapshot(player)

	if count == 0 then
		-- the game hides health from us entirely, nothing to measure
		if s.HitFallback then return self:Engage(player) end
		if s.Debug then warn("[Vault] no health source on " .. player.Name) end
		return
	end

	self:ClearPending()
	snap.player  = player
	snap.expires = os.clock() + s.HitWindow
	self.Pending = snap

	if s.Debug then
		warn(string.format("[Vault] nominated %s, watching %d health sources",
			player.Name, count))
	end
end

function Lock:CheckPending()
	local p = self.Pending
	if not p then return end

	if os.clock() > p.expires then
		if self.Settings.Debug then warn("[Vault] no hit landed, candidate dropped") end
		return self:ClearPending()
	end

	if not (p.player.Parent and isAlive(p.player)) then
		return self:ClearPending()
	end

	if self:DamageSeen(p) then
		local player = p.player
		self:ClearPending()
		if not self.Target and os.clock() >= self.CooldownEnd then
			self:Engage(player)
		end
	end
end

function Lock:ClearTargetConns()
	for _, c in ipairs(self.TargetConns) do
		pcall(function() c:Disconnect() end)
	end
	self.TargetConns = {}
end

function Lock:Engage(target)
	local root = rootOf(LocalPlayer)
	local char = target and target.Character
	if not (root and char) then return end

	self:ClearTargetConns()

	self.Target     = target
	self.TargetChar = char       -- bound to THIS body, not the player slot
	self.Origin     = root.CFrame
	self.Started    = os.clock()
	self.LastPos    = nil
	self.LastHealth = nil

	-- react the instant he dies or gets a new body, don't wait for a poll
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		self.LastHealth = hum.Health

		table.insert(self.TargetConns, hum.Died:Connect(function()
			if self.Target == target then self:Release(self.Settings.ReturnOnDeath) end
		end))

		table.insert(self.TargetConns, hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Dead and self.Target == target then
				self:Release(self.Settings.ReturnOnDeath)
			end
		end))
	end
	table.insert(self.TargetConns, target.CharacterAdded:Connect(function()
		if self.Target == target then self:Release(self.Settings.ReturnOnDeath) end
	end))
	table.insert(self.TargetConns, char.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.Target == target then
			self:Release(self.Settings.ReturnOnDeath)
		end
	end))

	WindUI:Notify({
		Title    = "Locked on",
		Content  = target.DisplayName,
		Duration = 2,
		Icon     = "crosshair",
	})
end

function Lock:Release(goBack)
	local s      = self.Settings
	local target = self.Target
	if not target then return end

	self.Target     = nil
	self.TargetChar = nil
	self.CooldownEnd = os.clock() + s.RelockDelay
	self:ClearTargetConns()
	self:ClearPending()

	local root   = rootOf(LocalPlayer)
	local origin = self.Origin
	self.Origin  = nil

	local valid = origin ~= nil and origin.Position.X == origin.Position.X -- NaN guard

	if goBack and valid then
		if root then
			root.AssemblyAngularVelocity = Vector3.zero
			root.AssemblyLinearVelocity  = Vector3.zero
			root.CFrame = origin
		end
		-- one teleport loses to leftover momentum, so hold the spot
		self.Restore      = origin
		self.RestoreUntil = os.clock() + (root and s.ReturnHold or math.max(s.ReturnHold, 1.5))
	elseif root then
		root.AssemblyAngularVelocity = Vector3.zero
		root.AssemblyLinearVelocity  = Vector3.zero
	end

	WindUI:Notify({
		Title    = goBack and "Back to your spot" or "Released",
		Content  = target.DisplayName,
		Duration = 2,
		Icon     = "crosshair",
	})
end

-- camera tracking, every frame
function Lock:Render()
	local s = self.Settings
	if not (s.Enabled and s.CameraLock and self.Target) then return end

	local tRoot  = rootOf(self.Target)
	local camera = workspace.CurrentCamera
	if tRoot and camera then
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, tRoot.Position)
	end
end

-- movement runs on Heartbeat, after physics, so we win the tug of war
function Lock:Move()
	local s = self.Settings

	self:CheckPending()

	-- pinning you back to your saved spot wins over everything else
	if self.Restore then
		local root = rootOf(LocalPlayer)
		if root and os.clock() < self.RestoreUntil then
			root.CFrame = self.Restore
			root.AssemblyLinearVelocity  = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			return
		end
		if os.clock() >= self.RestoreUntil then
			self.Restore = nil
		end
	end

	if not s.Enabled then
		if self.Target then self:Release(false) end
		return
	end
	if not self.Target then return end

	local char = self.Target.Character

	-- he respawned into a different body: that is a different guy to us
	if char ~= self.TargetChar or not self.TargetChar or not self.TargetChar.Parent then
		return self:Release(s.ReturnOnDeath)
	end

	local hum   = self.TargetChar:FindFirstChildOfClass("Humanoid")
	local tRoot = self.TargetChar:FindFirstChild("HumanoidRootPart")

	-- dead, ragdolled away, or the root got stripped
	if not (self.Target.Parent and hum and hum.Health > 0 and tRoot and tRoot.Parent) then
		return self:Release(s.ReturnOnDeath)
	end

	if os.clock() - self.Started > s.Timeout then
		return self:Release(s.ReturnOnDeath)
	end

	-- not every game kills the Humanoid. some teleport the same body back to
	-- spawn, some just refill health. both look like "nothing happened" to
	-- Died/CharacterAdded, so watch for the symptoms instead.
	local pos = tRoot.Position

	if s.BreakOnJump and self.LastPos then
		-- a sprinting player covers well under a stud per step
		if (pos - self.LastPos).Magnitude > s.JumpStuds then
			self.LastPos = nil
			return self:Release(s.ReturnOnDeath)
		end
	end
	self.LastPos = pos

	if s.BreakOnHeal and self.LastHealth then
		if hum.Health > self.LastHealth + (hum.MaxHealth * 0.5) then
			self.LastHealth = nil
			return self:Release(s.ReturnOnDeath)
		end
	end
	self.LastHealth = hum.Health

	if hum:GetState() == Enum.HumanoidStateType.Dead then
		return self:Release(s.ReturnOnDeath)
	end

	if s.Debug then
		self.DebugClock = self.DebugClock + 1
		if self.DebugClock >= 60 then
			self.DebugClock = 0
			warn(string.format(
				"[Vault] %s  hp %.1f/%.1f  state %s  char %s",
				self.Target.Name, hum.Health, hum.MaxHealth,
				tostring(hum:GetState()), tostring(self.TargetChar == self.Target.Character)))
		end
	end

	local myRoot = rootOf(LocalPlayer)
	if not myRoot then
		-- we died mid-lock, let go quietly
		self.Target, self.TargetChar, self.Origin = nil, nil, nil
		self:ClearTargetConns()
		return
	end

	local tCF = tRoot.CFrame
	local aim = tCF.Position + Vector3.new(0, s.Height, 0)
	local goal

	if s.Mode == "Fling" then
		goal = tCF * CFrame.new(0, s.Height, 0)
	else
		local spot = (tCF * CFrame.new(0, s.Height, math.max(s.Offset, 0.5))).Position
		goal = CFrame.lookAt(spot, aim)
	end

	local pos = goal.Position
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then return end

	if s.Smooth >= 1 then
		myRoot.CFrame = goal
	else
		myRoot.CFrame = myRoot.CFrame:Lerp(goal, math.clamp(s.Smooth, 0.05, 1))
	end

	if s.Mode == "Fling" then
		myRoot.AssemblyAngularVelocity = Vector3.new(s.Spin, s.Spin, s.Spin)
		myRoot.AssemblyLinearVelocity  = Vector3.new(0, s.Spin * 0.5, 0)
	else
		myRoot.AssemblyLinearVelocity  = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
	end
end

--=====================================================================
--  MAIN LOOP + CONNECTIONS
--=====================================================================

local Connections = {}

for _, p in ipairs(Players:GetPlayers()) do ESP:Create(p) end

table.insert(Connections, Players.PlayerAdded:Connect(function(p) ESP:Create(p) end))
table.insert(Connections, Players.PlayerRemoving:Connect(function(p)
	if Lock.Target == p then Lock:Release(Lock.Settings.ReturnOnDeath) end
	ESP:Remove(p)
end))

table.insert(Connections, RunService.RenderStepped:Connect(function(dt)
	for player, o in pairs(ESP.Objects) do
		if player.Parent then
			local ok, err = pcall(ESP.Update, ESP, player, o)
			if not ok then warn("[Vault] " .. tostring(err)); ESP:HideOne(o) end
		else
			ESP:Remove(player)
		end
	end
	pcall(Hider.Step, Hider, dt)
	pcall(Lock.Render, Lock)
end))

table.insert(Connections, RunService.Heartbeat:Connect(function()
	pcall(Lock.Move, Lock)
end))

table.insert(Connections, UserInputService.InputBegan:Connect(function(input, processed)
	local s = Lock.Settings
	if not s.Enabled then return end
	-- some games put a fullscreen HUD over everything, which eats the click
	if processed and not s.ClickThruGui then return end

	-- break key always works
	if input.KeyCode == Enum.KeyCode[s.BreakKey] then
		if Lock.Target then Lock:Release(true) end
		return
	end

	local fired =
		(s.Trigger == "Mouse Click" and input.UserInputType == Enum.UserInputType.MouseButton1)
		or (s.Trigger == "Keybind" and input.KeyCode == Enum.KeyCode[s.LockKey])

	if not fired then return end

	if Lock.Target then
		if s.Trigger == "Keybind" then Lock:Release(true) end
		return
	end

	-- no jumping straight onto the next guy after a kill
	if os.clock() < Lock.CooldownEnd then return end

	if s.RequireTool then
		local char = LocalPlayer.Character
		if not (char and char:FindFirstChildOfClass("Tool")) then return end
	end

	local target = Lock:Pick()
	if target then Lock:TryLock(target) end
end))

local function Unload()
	Lock:Release(false)
	Hider.Enabled = false
	Hider:RestoreAll()
	for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
	for player in pairs(ESP.Objects) do ESP:Remove(player) end
	if ESP.Container then ESP.Container:Destroy() end
end

--=====================================================================
--  WINDOW
--=====================================================================

local S = ESP.Settings
local L = Lock.Settings

local Window = WindUI:CreateWindow({
	Title        = "Vault",
	Icon         = "eye",
	Author       = "v2",
	Folder       = "Vault",
	Size         = UDim2.fromOffset(580, 440),
	Transparent  = true,
	Theme        = "Dark",
	Resizable    = true,
	SideBarWidth = 170,
	ToggleKey    = Enum.KeyCode.RightShift,

	OpenButton = {
		Title           = "Open Vault",
		Icon            = "eye",
		CornerRadius    = UDim.new(1, 0),
		StrokeThickness = 2,
		Enabled         = true,
		Draggable       = true,
		OnlyMobile      = false,
		Color           = ColorSequence.new(
			Color3.fromHex("#00AAFF"),
			Color3.fromHex("#7B4BFF")
		),
	},
})

Window:Tag({ Title = "v2", Color = Color3.fromRGB(0, 170, 255) })

--------------------------------------------------------------------- ESP

local MainTab = Window:Tab({ Title = "ESP", Icon = "eye" })

MainTab:Toggle({
	Title = "Enable ESP",
	Desc  = "Master switch for everything below",
	Value = S.Enabled,
	Callback = function(v)
		S.Enabled = v
		if not v then ESP:HideAll() end
	end,
})

MainTab:Toggle({ Title = "Team Check", Desc = "Ignore players on your own team",
	Value = S.TeamCheck, Callback = function(v) S.TeamCheck = v end })

MainTab:Slider({
	Title = "Max Distance",
	Value = { Min = 100, Max = 5000, Default = S.MaxDistance },
	Step  = 50,
	Callback = function(v) S.MaxDistance = tonumber(v) or S.MaxDistance end,
})

MainTab:Divider()

MainTab:Toggle({ Title = "Highlight (Chams)", Value = S.Highlight,
	Callback = function(v) S.Highlight = v end })

MainTab:Slider({
	Title = "Fill Transparency",
	Value = { Min = 0, Max = 1, Default = S.FillTransparency },
	Step  = 0.05,
	Callback = function(v) S.FillTransparency = tonumber(v) or 0.65 end,
})

MainTab:Slider({
	Title = "Outline Transparency",
	Value = { Min = 0, Max = 1, Default = S.OutlineTransparency },
	Step  = 0.05,
	Callback = function(v) S.OutlineTransparency = tonumber(v) or 0 end,
})

MainTab:Divider()

MainTab:Toggle({ Title = "Names",    Value = S.Names,
	Callback = function(v) S.Names = v end })
MainTab:Toggle({ Title = "Health",   Value = S.Health,
	Callback = function(v) S.Health = v end })
MainTab:Toggle({ Title = "Distance", Value = S.Distance,
	Callback = function(v) S.Distance = v end })

MainTab:Slider({
	Title = "Text Size",
	Value = { Min = 8, Max = 28, Default = S.TextSize },
	Step  = 1,
	Callback = function(v) S.TextSize = tonumber(v) or 14 end,
})

--------------------------------------------------------------------- HIDE

local HideTab = Window:Tab({ Title = "Hide", Icon = "user-x" })

HideTab:Paragraph({
	Title = "One switch",
	Desc  = "Hides the body, face, accessories, nametags, custom GUIs, held weapons and effects in one go. Client-side only, hitboxes are untouched.",
})

HideTab:Toggle({
	Title = "Hide Characters",
	Value = Hider.Enabled,
	Callback = function(v) Hider.Enabled = v end,
})

HideTab:Dropdown({
	Title  = "Who to hide",
	Values = { "Teammates", "Enemies", "Everyone" },
	Value  = Hider.Target,
	Callback = function(v)
		local pick = (typeof(v) == "table") and v[1] or v
		if pick ~= Hider.Target then
			Hider:RestoreAll()
			Hider.Target = pick
		end
	end,
})

HideTab:Button({
	Title = "Force restore everyone",
	Desc  = "Use if someone stays invisible",
	Callback = function()
		Hider.Enabled = false
		Hider:RestoreAll()
		WindUI:Notify({ Title = "Vault", Content = "Characters restored.", Duration = 3 })
	end,
})

--------------------------------------------------------------------- LOCK ON

local LockTab = Window:Tab({ Title = "Lock On", Icon = "crosshair" })

LockTab:Paragraph({
	Title = "How it works",
	Desc  = "Shoot an enemy. The lock only fires once he actually takes damage, so hitting the wall next to him does nothing. You get parked behind his back and follow him until he dies, the timer runs out, or you press the break key, then you snap back to where you started.",
})

LockTab:Toggle({
	Title = "Enable Lock On",
	Value = L.Enabled,
	Callback = function(v)
		L.Enabled = v
		if not v and Lock.Target then Lock:Release(true) end
	end,
})

LockTab:Dropdown({
	Title  = "Trigger",
	Values = { "Mouse Click", "Keybind" },
	Value  = L.Trigger,
	Callback = function(v) L.Trigger = (typeof(v) == "table") and v[1] or v end,
})

LockTab:Keybind({
	Title = "Lock Key",
	Desc  = "Used when trigger is set to Keybind. Press again to release.",
	Value = L.LockKey,
	Callback = function(k) L.LockKey = k end,
})

LockTab:Keybind({
	Title = "Break Key",
	Desc  = "Release and go back, any time",
	Value = L.BreakKey,
	Callback = function(k) L.BreakKey = k end,
})

LockTab:Toggle({ Title = "Team Check", Desc = "Never lock onto your own team",
	Value = L.TeamCheck, Callback = function(v) L.TeamCheck = v end })

LockTab:Toggle({ Title = "Only With Weapon Equipped",
	Desc = "Ignore clicks when you aren't holding a tool",
	Value = L.RequireTool, Callback = function(v) L.RequireTool = v end })

LockTab:Divider()

LockTab:Slider({
	Title = "Max Distance",
	Desc  = "How far the aim ray reaches",
	Value = { Min = 20, Max = 2000, Default = L.MaxDistance },
	Step  = 20,
	Callback = function(v) L.MaxDistance = tonumber(v) or 400 end,
})

LockTab:Toggle({
	Title = "Require Hit",
	Desc  = "Only lock once he actually takes damage. Shooting the wall in front of him does nothing.",
	Value = L.RequireHit,
	Callback = function(v) L.RequireHit = v end,
})

LockTab:Toggle({
	Title = "Lock If Health Hidden",
	Desc  = "If the game exposes no health value at all, fall back to locking on the click",
	Value = L.HitFallback,
	Callback = function(v) L.HitFallback = v end,
})

LockTab:Slider({
	Title = "Hit Window",
	Desc  = "Seconds the shot has to land in after you click. Raise it for slow projectiles.",
	Value = { Min = 0.1, Max = 3, Default = L.HitWindow },
	Step  = 0.1,
	Callback = function(v) L.HitWindow = tonumber(v) or 0.6 end,
})

LockTab:Slider({
	Title = "Aim Tolerance",
	Desc  = "Pixels of slack when picking who you aimed at. Harmless with Require Hit on.",
	Value = { Min = 0, Max = 200, Default = L.Tolerance },
	Step  = 5,
	Callback = function(v) L.Tolerance = tonumber(v) or 40 end,
})

LockTab:Toggle({
	Title = "Click Through GUI",
	Desc  = "Turn on if the game's HUD swallows your clicks and nothing locks",
	Value = L.ClickThruGui,
	Callback = function(v) L.ClickThruGui = v end,
})

LockTab:Slider({
	Title = "Re-lock Delay",
	Desc  = "Seconds before you can grab another target after a release",
	Value = { Min = 0, Max = 10, Default = L.RelockDelay },
	Step  = 0.5,
	Callback = function(v) L.RelockDelay = tonumber(v) or 0.5 end,
})

LockTab:Divider()

LockTab:Dropdown({
	Title  = "Mode",
	Values = { "Follow Behind", "Fling" },
	Value  = L.Mode,
	Callback = function(v) L.Mode = (typeof(v) == "table") and v[1] or v end,
})

LockTab:Slider({
	Title = "Offset",
	Desc  = "Studs behind their back. 3-5 is a good shooting distance.",
	Value = { Min = 0.5, Max = 15, Default = L.Offset },
	Step  = 0.5,
	Callback = function(v) L.Offset = tonumber(v) or 4 end,
})

LockTab:Slider({
	Title = "Height",
	Value = { Min = -10, Max = 10, Default = L.Height },
	Step  = 0.5,
	Callback = function(v) L.Height = tonumber(v) or 0 end,
})

LockTab:Slider({
	Title = "Smoothness",
	Desc  = "1 snaps instantly, lower drags along more softly",
	Value = { Min = 0.1, Max = 1, Default = L.Smooth },
	Step  = 0.05,
	Callback = function(v) L.Smooth = tonumber(v) or 1 end,
})

LockTab:Slider({
	Title = "Fling Power",
	Desc  = "Fling mode only",
	Value = { Min = 10, Max = 500, Default = L.Spin },
	Step  = 10,
	Callback = function(v) L.Spin = tonumber(v) or 90 end,
})

LockTab:Toggle({ Title = "Camera Lock", Desc = "Keep the camera pointed at them",
	Value = L.CameraLock, Callback = function(v) L.CameraLock = v end })

LockTab:Divider()

LockTab:Toggle({ Title = "Return On Release",
	Desc = "Snap back to your saved spot when the lock ends",
	Value = L.ReturnOnDeath, Callback = function(v) L.ReturnOnDeath = v end })

LockTab:Slider({
	Title = "Return Hold",
	Desc  = "Seconds spent pinning you to the saved spot so physics can't drag you off",
	Value = { Min = 0.1, Max = 3, Default = L.ReturnHold },
	Step  = 0.1,
	Callback = function(v) L.ReturnHold = tonumber(v) or 0.5 end,
})

LockTab:Divider()

LockTab:Paragraph({
	Title = "Auto release",
	Desc  = "Some games never kill the Humanoid, they just teleport the same body to spawn or refill its health. These catch that.",
})

LockTab:Toggle({
	Title = "Break On Teleport",
	Desc  = "Release when he suddenly jumps across the map",
	Value = L.BreakOnJump,
	Callback = function(v) L.BreakOnJump = v end,
})

LockTab:Slider({
	Title = "Teleport Distance",
	Desc  = "Studs in a single step that count as a teleport. Lower = more sensitive.",
	Value = { Min = 10, Max = 300, Default = L.JumpStuds },
	Step  = 5,
	Callback = function(v) L.JumpStuds = tonumber(v) or 50 end,
})

LockTab:Toggle({
	Title = "Break On Heal",
	Desc  = "Release when his health snaps back up, which usually means a new life",
	Value = L.BreakOnHeal,
	Callback = function(v) L.BreakOnHeal = v end,
})

LockTab:Toggle({
	Title = "Debug",
	Desc  = "Print his health and humanoid state to the console once a second",
	Value = L.Debug,
	Callback = function(v) L.Debug = v end,
})

LockTab:Divider()

LockTab:Slider({
	Title = "Timeout",
	Desc  = "Seconds before the lock gives up",
	Value = { Min = 1, Max = 60, Default = L.Timeout },
	Step  = 1,
	Callback = function(v) L.Timeout = tonumber(v) or 15 end,
})

LockTab:Button({
	Title = "Release now",
	Callback = function() Lock:Release(true) end,
})

--------------------------------------------------------------------- 2D

local DrawTab = Window:Tab({ Title = "2D", Icon = "square-dashed" })

if HasDrawing then
	DrawTab:Toggle({ Title = "Boxes", Value = S.Boxes,
		Callback = function(v) S.Boxes = v end })

	DrawTab:Slider({
		Title = "Box Thickness",
		Value = { Min = 1, Max = 5, Default = S.BoxThickness },
		Step  = 1,
		Callback = function(v) S.BoxThickness = tonumber(v) or 1 end,
	})

	DrawTab:Toggle({ Title = "Health Bars", Value = S.HealthBars,
		Callback = function(v) S.HealthBars = v end })

	DrawTab:Divider()

	DrawTab:Toggle({ Title = "Tracers", Value = S.Tracers,
		Callback = function(v) S.Tracers = v end })

	DrawTab:Dropdown({
		Title  = "Tracer Origin",
		Values = { "Bottom", "Center", "Mouse" },
		Value  = S.TracerOrigin,
		Callback = function(v) S.TracerOrigin = (typeof(v) == "table") and v[1] or v end,
	})
else
	DrawTab:Paragraph({
		Title = "Not supported",
		Desc  = "Your executor has no Drawing library, so boxes, bars and tracers are unavailable. Everything else still works.",
	})
end

--------------------------------------------------------------------- COLORS

local ColorTab = Window:Tab({ Title = "Colors", Icon = "palette" })

ColorTab:Toggle({ Title = "Use Team Color", Value = S.UseTeamColor,
	Callback = function(v) S.UseTeamColor = v end })

ColorTab:Colorpicker({ Title = "Main Color", Default = S.Color,
	Callback = function(c) S.Color = c end })
ColorTab:Colorpicker({ Title = "Highlight Outline", Default = S.OutlineColor,
	Callback = function(c) S.OutlineColor = c end })
ColorTab:Colorpicker({ Title = "Text Color", Default = S.TextColor,
	Callback = function(c) S.TextColor = c end })

--------------------------------------------------------------------- SETTINGS

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

SettingsTab:Paragraph({
	Title = "Reopening the menu",
	Desc  = "Press the toggle key below, or tap the floating 'Open Vault' bubble. The bubble is draggable.",
})

SettingsTab:Keybind({
	Title = "Toggle UI",
	Value = "RightShift",
	Callback = function(key)
		pcall(function() Window:SetToggleKey(Enum.KeyCode[key]) end)
	end,
})

SettingsTab:Button({ Title = "Minimize now", Callback = function() Window:Close() end })

SettingsTab:Dropdown({
	Title  = "Theme",
	Values = { "Dark", "Light", "Rose", "Indigo", "Plant", "Ocean" },
	Value  = "Dark",
	Callback = function(v)
		local theme = (typeof(v) == "table") and v[1] or v
		pcall(function() Window:SetTheme(theme) end)
	end,
})

SettingsTab:Button({
	Title = "Panic (disable everything)",
	Callback = function()
		S.Enabled, L.Enabled, Hider.Enabled = false, false, false
		ESP:HideAll()
		Lock:Release(true)
		Hider:RestoreAll()
		WindUI:Notify({ Title = "Vault", Content = "Everything disabled.", Duration = 3, Icon = "eye-off" })
	end,
})

SettingsTab:Button({
	Title = "Unload script",
	Callback = function()
		Unload()
		Window:Destroy()
	end,
})

SettingsTab:Paragraph({
	Title = "Drawing support",
	Desc  = HasDrawing and "Detected - boxes, bars and tracers available."
		or "Not detected - Highlight and tag ESP only.",
})

--=====================================================================

MainTab:Select()

WindUI:Notify({
	Title    = "Vault v2 loaded",
	Content  = "Right Shift toggles the menu.",
	Duration = 5,
	Icon     = "eye",
})
