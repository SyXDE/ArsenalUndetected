--[[
	VAULT ESP  —  full standalone script
	Library: WindUI-Shiny (Xyraniz/VaultUI)

	Just execute this file.

	OPENING THE MENU AGAIN AFTER CLOSING/MINIMIZING:
	  - press Right Shift (rebindable in the Settings tab), or
	  - tap the floating "Open Vault" button that appears on screen.

	Highlight chams / name / health / distance tags  ->  work on any executor
	Boxes / tracers / healthbars                     ->  need a Drawing library
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
--  ESP ENGINE
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
	TracerOrigin        = "Bottom", -- Bottom | Center | Mouse

	UseTeamColor        = false,
	Color               = Color3.fromRGB(0, 170, 255),
	OutlineColor        = Color3.fromRGB(255, 255, 255),
	TextColor           = Color3.fromRGB(255, 255, 255),
}

-- character hiding (separate from ESP visuals)
ESP.Hide = {
	Enabled         = false,
	Target          = "Teammates", -- Teammates | Enemies | Everyone
	Transparency    = 1,           -- 1 = fully invisible
	HideTags        = true,        -- roblox name/health bar above head
	HideAccessories = true,
	HideGuis        = true,        -- custom BillboardGui/SurfaceGui nametags
	HideWeapons     = true,        -- tools + welded gun models outside the char
	HideEffects     = true,        -- particles, trails, beams, lights
}

ESP.Objects     = {}
ESP.Connections = {}
ESP.Running     = false

ESP._humCache   = {}    -- [humanoid] = {nameDist, healthDist}
ESP._decalCache = {}    -- [decal]    = original transparency
ESP._guiCache   = {}    -- [gui/emitter] = original .Enabled
ESP._extraParts = {}    -- stuff hidden outside the character (guns etc)
ESP._hideWasOn  = false
ESP._hideClock  = 0
ESP.HideInterval = 0.2  -- seconds between hide passes

-- Drawing support probe
ESP.HasDrawing = pcall(function()
	local t = Drawing.new("Line")
	t:Remove()
end)

local function getGuiParent()
	if gethui then
		local ok, res = pcall(gethui)
		if ok and res then return res end
	end
	if pcall(function() return CoreGui.Name end) then
		return CoreGui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

ESP.Container = Instance.new("Folder")
ESP.Container.Name = "VaultESP_" .. tostring(math.random(1e5, 1e6))
ESP.Container.Parent = getGuiParent()

local function newDrawing(class, props)
	local d = Drawing.new(class)
	for k, v in pairs(props) do d[k] = v end
	return d
end

local function isTeammate(player)
	return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
end

--=====================================================================
--  PER-PLAYER OBJECTS
--=====================================================================

function ESP:_create(player)
	if player == LocalPlayer or self.Objects[player] then return end
	local s = self.Settings
	local o = {}

	o.Highlight                     = Instance.new("Highlight")
	o.Highlight.Name                = "H" .. player.UserId
	o.Highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	o.Highlight.FillTransparency    = s.FillTransparency
	o.Highlight.OutlineTransparency = s.OutlineTransparency
	o.Highlight.Enabled             = false
	o.Highlight.Parent              = self.Container

	o.Billboard             = Instance.new("BillboardGui")
	o.Billboard.Name        = "B" .. player.UserId
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
	o.Label.Text                   = ""
	o.Label.Parent                 = o.Billboard

	if self.HasDrawing then
		o.BoxOutline = newDrawing("Square", {
			Thickness = 3, Filled = false, Visible = false,
			Color = Color3.new(0, 0, 0), Transparency = 0.55, ZIndex = 1,
		})
		o.Box = newDrawing("Square", {
			Thickness = 1, Filled = false, Visible = false,
			Color = s.Color, ZIndex = 2,
		})
		o.BarOutline = newDrawing("Square", {
			Thickness = 1, Filled = true, Visible = false,
			Color = Color3.new(0, 0, 0), Transparency = 0.6, ZIndex = 2,
		})
		o.Bar = newDrawing("Square", {
			Thickness = 1, Filled = true, Visible = false,
			Color = Color3.fromRGB(80, 255, 120), ZIndex = 3,
		})
		o.Tracer = newDrawing("Line", {
			Thickness = 1, Visible = false, Color = s.Color, ZIndex = 2,
		})
	end

	self.Objects[player] = o
end

function ESP:_hide(o)
	o.Highlight.Enabled = false
	o.Billboard.Enabled = false
	if o.Box then
		o.Box.Visible        = false
		o.BoxOutline.Visible = false
		o.Bar.Visible        = false
		o.BarOutline.Visible = false
		o.Tracer.Visible     = false
	end
end

function ESP:_remove(player)
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

--=====================================================================
--  CHARACTER HIDING
--=====================================================================

function ESP:_shouldHide(player)
	local h = self.Hide
	if not h.Enabled then return false end
	if h.Target == "Everyone"  then return true end
	if h.Target == "Teammates" then return isTeammate(player) end
	return not isTeammate(player) -- Enemies
end

-- anything whose visibility is just an .Enabled flag
local ENABLE_CLASSES = {
	BillboardGui = "gui", SurfaceGui = "gui",
	ParticleEmitter = "fx", Trail = "fx", Beam = "fx",
	Fire = "fx", Smoke = "fx", Sparkles = "fx",
	PointLight = "fx", SpotLight = "fx", SurfaceLight = "fx",
}

-- handles a single instance: part, decal, gui or effect
function ESP:_processObject(d, hidden, t, h)
	if d:IsA("BasePart") then
		if hidden and (h.HideAccessories or not d:FindFirstAncestorOfClass("Accessory")) then
			d.LocalTransparencyModifier = t
		else
			d.LocalTransparencyModifier = 0
		end

	elseif d:IsA("Decal") or d:IsA("Texture") then
		if hidden then
			if self._decalCache[d] == nil then
				self._decalCache[d] = d.Transparency
			end
			d.Transparency = t
		elseif self._decalCache[d] ~= nil then
			d.Transparency = self._decalCache[d]
			self._decalCache[d] = nil
		end

	else
		local kind = ENABLE_CLASSES[d.ClassName]
		if kind then
			local wanted = (kind == "gui" and h.HideGuis) or (kind == "fx" and h.HideEffects)
			if hidden and wanted then
				if self._guiCache[d] == nil then
					self._guiCache[d] = d.Enabled
				end
				d.Enabled = false
			elseif self._guiCache[d] ~= nil then
				d.Enabled = self._guiCache[d]
				self._guiCache[d] = nil
			end
		end
	end
end

function ESP:_applyToChar(char, hidden, extras)
	local h = self.Hide
	local t = hidden and math.clamp(h.Transparency, 0, 1) or 0

	-- everything inside the character (body, faces, accessories,
	-- custom nametag BillboardGuis, equipped Tools)
	for _, d in ipairs(char:GetDescendants()) do
		self:_processObject(d, hidden, t, h)
	end

	-- roblox's built-in name / health bar
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		if hidden and h.HideTags then
			if not self._humCache[hum] then
				self._humCache[hum] = { hum.NameDisplayDistance, hum.HealthDisplayDistance }
			end
			hum.NameDisplayDistance   = 0
			hum.HealthDisplayDistance = 0
		elseif self._humCache[hum] then
			hum.NameDisplayDistance   = self._humCache[hum][1]
			hum.HealthDisplayDistance = self._humCache[hum][2]
			self._humCache[hum] = nil
		end
	end

	-- guns and other models welded to the character but parented elsewhere.
	-- rescanned every pass, so swapping weapons is picked up automatically.
	if hidden and h.HideWeapons and extras then
		local anchor = char:FindFirstChild("HumanoidRootPart")
			or char:FindFirstChildWhichIsA("BasePart")

		if anchor then
			local models = {}

			for _, part in ipairs(anchor:GetConnectedParts(true)) do
				if not part:IsDescendantOf(char) then
					local model = part:FindFirstAncestorOfClass("Model")
					if model and model ~= char and not model:IsDescendantOf(char) then
						models[model] = true -- grab the whole gun, not just the welded bit
					else
						self:_processObject(part, true, t, h)
						extras[part] = true
						self._extraParts[part] = true
					end
				end
			end

			for model in pairs(models) do
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")
						or ENABLE_CLASSES[d.ClassName] then
						self:_processObject(d, true, t, h)
						extras[d] = true
						self._extraParts[d] = true
					end
				end
			end
		end
	end
end

function ESP:_restoreAll()
	local h = self.Hide

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			pcall(self._applyToChar, self, char, false, nil)
		end
	end

	for obj in pairs(self._extraParts) do
		pcall(function()
			if obj.Parent then self:_processObject(obj, false, 0, h) end
		end)
	end
	self._extraParts = {}

	for hum, vals in pairs(self._humCache) do
		pcall(function()
			hum.NameDisplayDistance   = vals[1]
			hum.HealthDisplayDistance = vals[2]
		end)
	end
	self._humCache = {}

	for d, orig in pairs(self._decalCache) do
		pcall(function() d.Transparency = orig end)
	end
	self._decalCache = {}

	for g, orig in pairs(self._guiCache) do
		pcall(function() g.Enabled = orig end)
	end
	self._guiCache = {}
end

-- throttled: rebuilding descendant lists every frame is wasteful
function ESP:_updateHiding(dt)
	local h = self.Hide

	if not h.Enabled then
		if self._hideWasOn then
			self._hideWasOn = false
			self:_restoreAll()
		end
		return
	end
	self._hideWasOn = true

	self._hideClock = self._hideClock + dt
	if self._hideClock < self.HideInterval then return end
	self._hideClock = 0

	local extras = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local char = player.Character
			if char then
				pcall(self._applyToChar, self, char, self:_shouldHide(player), extras)
			end
		end
	end

	-- anything we hid last pass that is no longer attached (dropped or
	-- swapped weapon) gets put back the way it was
	for obj in pairs(self._extraParts) do
		if not extras[obj] then
			pcall(function()
				if obj.Parent then self:_processObject(obj, false, 0, h) end
			end)
			self._extraParts[obj] = nil
		end
	end
end

--=====================================================================
--  ESP UPDATE
--=====================================================================

local function tracerOrigin(mode, viewport)
	if mode == "Mouse" then
		local m = UserInputService:GetMouseLocation()
		return Vector2.new(m.X, m.Y)
	elseif mode == "Center" then
		return viewport / 2
	end
	return Vector2.new(viewport.X / 2, viewport.Y)
end

function ESP:_update(player, o)
	local s = self.Settings
	local camera = workspace.CurrentCamera
	if not (s.Enabled and camera) then return self:_hide(o) end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum and hum.Health > 0) then return self:_hide(o) end

	if s.TeamCheck and isTeammate(player) then return self:_hide(o) end

	local dist = (camera.CFrame.Position - root.Position).Magnitude
	if dist > s.MaxDistance then return self:_hide(o) end

	local color = s.Color
	if s.UseTeamColor and player.TeamColor then
		color = player.TeamColor.Color
	end

	local hpPct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	local hpCol = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(80, 255, 120), hpPct)

	------------------------------------------------ highlight
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

	------------------------------------------------ text tags
	if s.Names or s.Health or s.Distance then
		local lines = {}
		if s.Names then
			local n = player.DisplayName
			if n ~= player.Name then n = n .. " (@" .. player.Name .. ")" end
			table.insert(lines, n)
		end
		if s.Health then
			table.insert(lines, string.format(
				'<font color="#%s">%d HP</font>', hpCol:ToHex(), math.floor(hum.Health + 0.5)))
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

	------------------------------------------------ 2D drawings
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
		o.Box.Size      = Vector2.new(width, height)
		o.Box.Position  = pos
		o.Box.Color     = color
		o.Box.Thickness = s.BoxThickness
		o.Box.Visible   = true

		o.BoxOutline.Size      = o.Box.Size
		o.BoxOutline.Position  = pos
		o.BoxOutline.Thickness = s.BoxThickness + 2
		o.BoxOutline.Visible   = true
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
--  LIFECYCLE
--=====================================================================

function ESP:Start()
	if self.Running then return end
	self.Running = true

	for _, p in ipairs(Players:GetPlayers()) do self:_create(p) end

	table.insert(self.Connections, Players.PlayerAdded:Connect(function(p)
		self:_create(p)
	end))
	table.insert(self.Connections, Players.PlayerRemoving:Connect(function(p)
		self:_remove(p)
	end))
	table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
		for player, o in pairs(self.Objects) do
			if player.Parent then
				local ok, err = pcall(self._update, self, player, o)
				if not ok then
					warn("[VaultESP] " .. tostring(err))
					self:_hide(o)
				end
			else
				self:_remove(player)
			end
		end
		pcall(self._updateHiding, self, dt)
	end))
end

function ESP:Destroy()
	self.Settings.Enabled = false
	self.Hide.Enabled = false
	self:_restoreAll()
	for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
	self.Connections = {}
	for player in pairs(self.Objects) do self:_remove(player) end
	if self.Container then self.Container:Destroy() end
	self.Running = false
end

ESP:Start()

--=====================================================================
--  WINDOW
--=====================================================================

local S = ESP.Settings
local H = ESP.Hide

local Window = WindUI:CreateWindow({
	Title        = "Vault",
	Icon         = "eye",
	Author       = "ESP",
	Folder       = "VaultESP",
	Size         = UDim2.fromOffset(580, 430),
	Transparent  = true,
	Theme        = "Dark",
	Resizable    = true,
	SideBarWidth = 170,
	ToggleKey    = Enum.KeyCode.RightShift,

	-- floating button that brings the menu back after you close it
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

Window:Tag({ Title = "v1.2", Color = Color3.fromRGB(0, 170, 255) })

--=====================================================================
--  TAB: ESP
--=====================================================================

local MainTab = Window:Tab({ Title = "ESP", Icon = "eye" })

MainTab:Toggle({
	Title = "Enable ESP",
	Desc  = "Master switch for everything below",
	Value = S.Enabled,
	Callback = function(v)
		S.Enabled = v
		if not v then
			for _, o in pairs(ESP.Objects) do ESP:_hide(o) end
		end
	end,
})

MainTab:Toggle({
	Title = "Team Check",
	Desc  = "Ignore players on your own team",
	Value = S.TeamCheck,
	Callback = function(v) S.TeamCheck = v end,
})

MainTab:Slider({
	Title = "Max Distance",
	Desc  = "Hide targets further away than this",
	Value = { Min = 100, Max = 5000, Default = S.MaxDistance },
	Step  = 50,
	Callback = function(v) S.MaxDistance = tonumber(v) or S.MaxDistance end,
})

MainTab:Divider()

MainTab:Toggle({
	Title = "Highlight (Chams)",
	Value = S.Highlight,
	Callback = function(v) S.Highlight = v end,
})

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

--=====================================================================
--  TAB: HIDE CHARACTERS
--=====================================================================

local HideTab = Window:Tab({ Title = "Hide", Icon = "user-x" })

HideTab:Paragraph({
	Title = "Client-side only",
	Desc  = "Makes characters, their nametags, weapons and effects invisible on your screen. Nothing replicates and hitboxes are unaffected.",
})

HideTab:Toggle({
	Title = "Hide Characters",
	Desc  = "Turn the hider on",
	Value = H.Enabled,
	Callback = function(v) H.Enabled = v end,
})

HideTab:Dropdown({
	Title  = "Who to hide",
	Values = { "Teammates", "Enemies", "Everyone" },
	Value  = H.Target,
	Callback = function(v)
		local pick = (typeof(v) == "table") and v[1] or v
		if pick ~= H.Target then
			ESP:_restoreAll()   -- un-hide the previous group first
			H.Target = pick
		end
	end,
})

HideTab:Slider({
	Title = "Transparency",
	Desc  = "1 = fully invisible, 0.5 = ghost",
	Value = { Min = 0, Max = 1, Default = H.Transparency },
	Step  = 0.05,
	Callback = function(v) H.Transparency = tonumber(v) or 1 end,
})

HideTab:Toggle({
	Title = "Hide Accessories",
	Desc  = "Also hide hats, hair and gear",
	Value = H.HideAccessories,
	Callback = function(v)
		H.HideAccessories = v
		ESP:_restoreAll()
	end,
})

HideTab:Toggle({
	Title = "Hide Nametags",
	Desc  = "Roblox's built-in name and health bar",
	Value = H.HideTags,
	Callback = function(v)
		H.HideTags = v
		if not v then ESP:_restoreAll() end
	end,
})

HideTab:Toggle({
	Title = "Hide Custom GUIs",
	Desc  = "BillboardGui / SurfaceGui tags the game puts on the character",
	Value = H.HideGuis,
	Callback = function(v)
		H.HideGuis = v
		if not v then ESP:_restoreAll() end
	end,
})

HideTab:Toggle({
	Title = "Hide Weapons",
	Desc  = "Tools and gun models welded to the character, even when parented elsewhere",
	Value = H.HideWeapons,
	Callback = function(v)
		H.HideWeapons = v
		if not v then ESP:_restoreAll() end
	end,
})

HideTab:Toggle({
	Title = "Hide Effects",
	Desc  = "Particles, trails, beams and lights (muzzle flashes, auras)",
	Value = H.HideEffects,
	Callback = function(v)
		H.HideEffects = v
		if not v then ESP:_restoreAll() end
	end,
})

HideTab:Slider({
	Title = "Refresh Rate",
	Desc  = "Seconds between hide passes. Lower catches weapon swaps faster, costs more FPS.",
	Value = { Min = 0.05, Max = 1, Default = ESP.HideInterval },
	Step  = 0.05,
	Callback = function(v) ESP.HideInterval = tonumber(v) or 0.2 end,
})

HideTab:Button({
	Title = "Force restore everyone",
	Desc  = "Use this if a character stays invisible",
	Callback = function()
		H.Enabled = false
		ESP:_restoreAll()
		WindUI:Notify({ Title = "Vault", Content = "All characters restored.", Duration = 3 })
	end,
})

--=====================================================================
--  TAB: 2D
--=====================================================================

local DrawTab = Window:Tab({ Title = "2D", Icon = "square-dashed" })

if ESP.HasDrawing then
	DrawTab:Toggle({ Title = "Boxes", Value = S.Boxes,
		Callback = function(v) S.Boxes = v end })

	DrawTab:Slider({
		Title = "Box Thickness",
		Value = { Min = 1, Max = 5, Default = S.BoxThickness },
		Step  = 1,
		Callback = function(v) S.BoxThickness = tonumber(v) or 1 end,
	})

	DrawTab:Toggle({
		Title = "Health Bars",
		Desc  = "Vertical bar on the left of the box",
		Value = S.HealthBars,
		Callback = function(v) S.HealthBars = v end,
	})

	DrawTab:Divider()

	DrawTab:Toggle({ Title = "Tracers", Value = S.Tracers,
		Callback = function(v) S.Tracers = v end })

	DrawTab:Dropdown({
		Title  = "Tracer Origin",
		Values = { "Bottom", "Center", "Mouse" },
		Value  = S.TracerOrigin,
		Callback = function(v)
			S.TracerOrigin = (typeof(v) == "table") and v[1] or v
		end,
	})
else
	DrawTab:Paragraph({
		Title = "Not supported",
		Desc  = "Your executor has no Drawing library, so boxes, health bars and tracers are unavailable. Everything on the ESP tab still works.",
	})
end

--=====================================================================
--  TAB: COLORS
--=====================================================================

local ColorTab = Window:Tab({ Title = "Colors", Icon = "palette" })

ColorTab:Toggle({
	Title = "Use Team Color",
	Desc  = "Override the custom color with each player's team color",
	Value = S.UseTeamColor,
	Callback = function(v) S.UseTeamColor = v end,
})

ColorTab:Colorpicker({ Title = "Main Color",        Default = S.Color,
	Callback = function(c) S.Color = c end })
ColorTab:Colorpicker({ Title = "Highlight Outline", Default = S.OutlineColor,
	Callback = function(c) S.OutlineColor = c end })
ColorTab:Colorpicker({ Title = "Text Color",        Default = S.TextColor,
	Callback = function(c) S.TextColor = c end })

--=====================================================================
--  TAB: SETTINGS
--=====================================================================

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

SettingsTab:Paragraph({
	Title = "Reopening the menu",
	Desc  = "Press the toggle key below (Right Shift by default), or tap the floating 'Open Vault' bubble. The bubble is draggable, so move it somewhere out of the way.",
})

SettingsTab:Keybind({
	Title = "Toggle UI",
	Value = "RightShift",
	Callback = function(key)
		pcall(function() Window:SetToggleKey(Enum.KeyCode[key]) end)
	end,
})

SettingsTab:Button({
	Title = "Minimize now",
	Callback = function() Window:Close() end,
})

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
		S.Enabled = false
		H.Enabled = false
		for _, o in pairs(ESP.Objects) do ESP:_hide(o) end
		ESP:_restoreAll()
		WindUI:Notify({ Title = "Vault", Content = "ESP and hiding disabled.", Duration = 3, Icon = "eye-off" })
	end,
})

SettingsTab:Button({
	Title = "Unload script",
	Callback = function()
		ESP:Destroy()
		Window:Destroy()
	end,
})

SettingsTab:Paragraph({
	Title = "Drawing support",
	Desc  = ESP.HasDrawing and "Detected - boxes, bars and tracers available."
		or "Not detected - only Highlight and tag ESP available.",
})

--=====================================================================
--  DONE
--=====================================================================

MainTab:Select()

WindUI:Notify({
	Title    = "Vault ESP loaded",
	Content  = "Right Shift toggles the menu. The floating bubble reopens it too.",
	Duration = 6,
	Icon     = "eye",
})
