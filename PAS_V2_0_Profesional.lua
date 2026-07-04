--//====================================================
--// PAS - Precision Assist System V2.0 Profesional
--// Proyecto 3/3 - Puntería Asistida para TUS propios juegos de Roblox Studio
--// LocalScript en StarterPlayer > StarterPlayerScripts
--//====================================================

--[[
	PAS V2.0 Profesional

	Objetivo:
	- Sistema de puntería asistida legítimo para tus propios juegos de Roblox Studio.
	- No modifica daño.
	- No dispara por el jugador.
	- No atraviesa seguridad de servidor.
	- Solo mueve la cámara local hacia objetivos válidos usando filtros configurables.

	Mejoras V2.0:
	- Interfaz pequeña estilo SVT movible.
	- Botón flotante movible.
	- FOV circular con color, tamaño, grosor y transparencia.
	- Detección automática PC / móvil / consola.
	- PC: apunta al mantener clic derecho.
	- Móvil: apunta mientras PAS esté activo.
	- Target Engine con Players y NPCs.
	- Team Check.
	- Wall Check.
	- Prioridad por visibilidad incluso si Wall Check está OFF.
	- Selección de parte: Auto, Cabeza, Cuerpo, Brazos, Piernas.
	- Prediction Engine profesional:
		* Velocidad real con AssemblyLinearVelocity.
		* Predicción adaptativa por distancia.
		* Multiplicador para vehículos / alta velocidad.
		* Límite de predicción para evitar saltos exagerados.
		* Suavizado con aceleración/desaceleración.
	- Debug panel básico.
	- Preparado para integrarse después con SVT + THS + TCS.
]]

--//====================================================
--// SERVICIOS
--//====================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local PAS = {}

--//====================================================
--// CONFIG
--//====================================================

PAS.Config = {
	SystemEnabled = false,
	MenuOpen = true,
	ShowDebug = true,

	-- Objetivos
	TargetPlayers = true,
	TargetNPCs = false,
	TeamCheck = true,
	MaxDistance = 700,
	MaxTargets = 60,
	TargetPartMode = "Auto", -- "Auto", "Cabeza", "Cuerpo", "Brazos", "Piernas"
	PriorityMode = "Visible", -- "Visible", "Cercano", "CentroFOV"

	-- FOV
	ShowFOV = true,
	FOVRadius = 180,
	FOVThickness = 2,
	FOVTransparency = 0.25,
	FOVColor = Color3.fromRGB(0, 220, 255),

	-- Visibilidad
	WallCheck = true,
	PrioritizeVisible = true,
	MinimumVisibleParts = 1,
	VisibilityMode = "Partes", -- "Basico", "Partes"

	-- Aim
	AimStrength = 0.18,
	AimAcceleration = true,
	AimMinStrength = 0.035,
	AimMaxStrength = 0.55,
	AimDeadzone = 2,

	-- Prediction Engine
	PredictionEnabled = true,
	PredictionStrength = 0.42,
	PredictionLimit = 10,
	AdaptivePrediction = true,
	VehiclePredictionBoost = true,
	VehiclePredictionMultiplier = 1.35,
	HighSpeedThreshold = 32,

	-- Plataforma
	MobileAlwaysAim = true,
	PCRequiresRightClick = true,

	-- Teclas
	MenuKey = Enum.KeyCode.RightShift,
	ToggleKey = Enum.KeyCode.P,
	DebugKey = Enum.KeyCode.F8,
}

PAS.Runtime = {
	Connections = {},
	TargetCache = {},
	LastTargetScan = 0,
	TargetScanRate = 0.35,

	CurrentTarget = nil,
	CurrentAimPoint = nil,
	CurrentVisibility = 0,
	CurrentDevice = "PC",

	IsRightMouseDown = false,
	IsDraggingUI = false,
	IsDraggingBubble = false,

	LastUpdate = 0,
	UpdateRate = 0.016,

	SmoothStrength = 0,
	FPS = 0,
	FrameCounter = 0,
	LastFPSUpdate = 0,
	LastFrameMs = 0,

	DetectedTargets = 0,
	LastStatus = "Listo",
	Destroyed = false,
}

--//====================================================
--// TEMA ESTILO SVT
--//====================================================

local Theme = {
	Background = Color3.fromRGB(12, 14, 18),
	Panel = Color3.fromRGB(20, 24, 31),
	PanelLight = Color3.fromRGB(30, 36, 46),
	Accent = Color3.fromRGB(0, 145, 255),
	AccentLight = Color3.fromRGB(0, 220, 255),
	Text = Color3.fromRGB(240, 245, 255),
	MutedText = Color3.fromRGB(165, 175, 190),
	Green = Color3.fromRGB(90, 255, 150),
	Red = Color3.fromRGB(255, 90, 90),
	Orange = Color3.fromRGB(255, 170, 70),
}

local Palette = {
	{ Name = "Celeste", Color = Color3.fromRGB(0, 220, 255) },
	{ Name = "Azul", Color = Color3.fromRGB(0, 145, 255) },
	{ Name = "Verde", Color = Color3.fromRGB(90, 255, 150) },
	{ Name = "Rojo", Color = Color3.fromRGB(255, 90, 90) },
	{ Name = "Morado", Color = Color3.fromRGB(180, 120, 255) },
	{ Name = "Naranja", Color = Color3.fromRGB(255, 170, 0) },
	{ Name = "Blanco", Color = Color3.fromRGB(245, 245, 245) },
}

--//====================================================
--// UTILIDADES
--//====================================================

local function create(className, props, parent)
	local obj = Instance.new(className)

	for prop, value in pairs(props or {}) do
		obj[prop] = value
	end

	obj.Parent = parent
	return obj
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(PAS.Runtime.Connections, c)
	return c
end

local function clampNumber(value, minValue, maxValue)
	local number = tonumber(value)
	if not number then
		return minValue
	end
	return math.clamp(number, minValue, maxValue)
end

local function round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end

local function getDeviceType()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Móvil"
	end

	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Consola"
	end

	return "PC"
end

local function cycleString(current, list)
	local index = table.find(list, current) or 1
	index += 1
	if index > #list then
		index = 1
	end
	return list[index]
end

local function getNextColor(current)
	local bestIndex = 1
	local bestDistance = math.huge

	for i, entry in ipairs(Palette) do
		local c = entry.Color
		local d = math.abs(c.R - current.R) + math.abs(c.G - current.G) + math.abs(c.B - current.B)
		if d < bestDistance then
			bestDistance = d
			bestIndex = i
		end
	end

	local nextIndex = bestIndex + 1
	if nextIndex > #Palette then
		nextIndex = 1
	end

	return Palette[nextIndex].Color
end

local function colorName(color)
	local bestName = "Personalizado"
	local bestDistance = math.huge

	for _, entry in ipairs(Palette) do
		local c = entry.Color
		local d = math.abs(c.R - color.R) + math.abs(c.G - color.G) + math.abs(c.B - color.B)
		if d < bestDistance then
			bestDistance = d
			bestName = entry.Name
		end
	end

	return bestName
end

local function makeCorner(obj, radius)
	create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8)
	}, obj)
end

local function makeStroke(obj, color, thickness, transparency)
	create("UIStroke", {
		Color = color or Theme.Accent,
		Thickness = thickness or 1,
		Transparency = transparency or 0.45
	}, obj)
end

--//====================================================
--// TARGET ENGINE
--//====================================================

local function getCharacterData(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")

	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end

	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Head = head or root,
		Name = model.Name,
		Player = nil,
		Team = nil,
		Type = "NPC",
	}
end

local function isNPCModel(model)
	if not model or not model:IsA("Model") then
		return false
	end

	if Players:GetPlayerFromCharacter(model) then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil
end

local function getBodyParts(model)
	local parts = {}

	local names = {
		"Head",
		"HumanoidRootPart",
		"UpperTorso",
		"LowerTorso",
		"Torso",

		"LeftUpperArm",
		"LeftLowerArm",
		"LeftHand",
		"RightUpperArm",
		"RightLowerArm",
		"RightHand",

		"LeftUpperLeg",
		"LeftLowerLeg",
		"LeftFoot",
		"RightUpperLeg",
		"RightLowerLeg",
		"RightFoot",

		"Left Arm",
		"Right Arm",
		"Left Leg",
		"Right Leg",
	}

	for _, name in ipairs(names) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end

	return parts
end

local function findFirstPart(model, names)
	for _, name in ipairs(names) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

function PAS:GetAimPart(target)
	if not target or not target.Model then
		return nil
	end

	local mode = self.Config.TargetPartMode

	if mode == "Cabeza" then
		return findFirstPart(target.Model, { "Head" }) or target.Root
	end

	if mode == "Cuerpo" then
		return findFirstPart(target.Model, { "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart" }) or target.Root
	end

	if mode == "Brazos" then
		return findFirstPart(target.Model, {
			"RightHand", "RightLowerArm", "RightUpperArm", "Right Arm",
			"LeftHand", "LeftLowerArm", "LeftUpperArm", "Left Arm",
		}) or target.Root
	end

	if mode == "Piernas" then
		return findFirstPart(target.Model, {
			"RightFoot", "RightLowerLeg", "RightUpperLeg", "Right Leg",
			"LeftFoot", "LeftLowerLeg", "LeftUpperLeg", "Left Leg",
		}) or target.Root
	end

	-- Auto: preferimos torso porque es estable; cabeza si está muy visible se puede priorizar después.
	return findFirstPart(target.Model, { "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart", "Head" }) or target.Root
end

function PAS:IsPartVisible(part, targetModel)
	if not part or not Camera then
		return false
	end

	local origin = Camera.CFrame.Position
	local direction = part.Position - origin

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		LocalPlayer.Character,
		Camera,
	}
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, params)

	if not result then
		return true
	end

	if result.Instance and result.Instance:IsDescendantOf(targetModel) then
		return true
	end

	return false
end

function PAS:GetVisibilityScore(target)
	if not target or not target.Model then
		return 0
	end

	if self.Config.VisibilityMode == "Basico" then
		local part = self:GetAimPart(target)
		return self:IsPartVisible(part, target.Model) and 1 or 0
	end

	local parts = getBodyParts(target.Model)
	if #parts <= 0 then
		return 0
	end

	local visible = 0
	for _, part in ipairs(parts) do
		if self:IsPartVisible(part, target.Model) then
			visible += 1
		end
	end

	return visible / #parts
end

function PAS:IsAllowedByTeam(target)
	if not self.Config.TeamCheck then
		return true
	end

	if not target.Player then
		return true
	end

	if not LocalPlayer.Team or not target.Player.Team then
		return true
	end

	return target.Player.Team ~= LocalPlayer.Team
end

function PAS:IsInsideDistance(target)
	if not target or not target.Root or not Camera then
		return false
	end

	local distance = (target.Root.Position - Camera.CFrame.Position).Magnitude
	target.Distance = distance
	return distance <= self.Config.MaxDistance
end

function PAS:GetScreenData(worldPosition)
	if not Camera then
		return nil
	end

	local viewport = Camera.ViewportSize
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local point, onScreen = Camera:WorldToViewportPoint(worldPosition)

	if point.Z <= 0 then
		return nil
	end

	local screen = Vector2.new(point.X, point.Y)
	local fovDistance = (screen - center).Magnitude

	return {
		Point = point,
		Screen = screen,
		Center = center,
		FOVDistance = fovDistance,
		OnScreen = onScreen,
		InsideFOV = fovDistance <= self.Config.FOVRadius,
	}
end

function PAS:RefreshTargetCache(force)
	local now = os.clock()
	if not force and now - self.Runtime.LastTargetScan < self.Runtime.TargetScanRate then
		return
	end

	self.Runtime.LastTargetScan = now

	local cache = {}

	if self.Config.TargetPlayers then
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and player.Character then
				local data = getCharacterData(player.Character)
				if data then
					data.Player = player
					data.Team = player.Team
					data.Type = "Player"
					data.Name = player.Name
					table.insert(cache, data)
				end
			end
		end
	end

	if self.Config.TargetNPCs then
		for _, item in ipairs(workspace:GetDescendants()) do
			if isNPCModel(item) then
				local data = getCharacterData(item)
				if data then
					data.Type = "NPC"
					data.Name = item.Name
					table.insert(cache, data)
				end
			end
		end
	end

	self.Runtime.TargetCache = cache
end

function PAS:GetBestTarget()
	self:RefreshTargetCache(false)

	local bestTarget = nil
	local bestScore = math.huge
	local bestAimPart = nil
	local bestVisibility = 0
	local bestScreen = nil

	local checked = 0

	for _, target in ipairs(self.Runtime.TargetCache) do
		if target.Model and target.Model.Parent and target.Humanoid and target.Humanoid.Health > 0 then
			if self:IsAllowedByTeam(target) and self:IsInsideDistance(target) then
				local aimPart = self:GetAimPart(target)

				if aimPart then
					local screenData = self:GetScreenData(aimPart.Position)

					if screenData and screenData.OnScreen and screenData.InsideFOV then
						checked += 1

						local visibility = self:GetVisibilityScore(target)
						local visibleParts = math.floor(visibility * #getBodyParts(target.Model) + 0.5)

						if self.Config.WallCheck then
							if visibleParts < self.Config.MinimumVisibleParts or visibility <= 0 then
								continue
							end
						end

						local fovDistance = screenData.FOVDistance
						local worldDistance = target.Distance or 0

						local score = 0

						if self.Config.PriorityMode == "Cercano" then
							score = worldDistance + (fovDistance * 0.35)
						elseif self.Config.PriorityMode == "CentroFOV" then
							score = fovDistance + (worldDistance * 0.025)
						else
							-- Visible: la visibilidad manda, pero sin ignorar FOV ni distancia.
							score = fovDistance + (worldDistance * 0.03)
							if self.Config.PrioritizeVisible then
								score -= visibility * 260
							end
						end

						if score < bestScore then
							bestScore = score
							bestTarget = target
							bestAimPart = aimPart
							bestVisibility = visibility
							bestScreen = screenData
						end
					end
				end
			end
		end
	end

	self.Runtime.DetectedTargets = checked
	return bestTarget, bestAimPart, bestVisibility, bestScreen
end

--//====================================================
--// PREDICTION ENGINE PROFESIONAL
--//====================================================

function PAS:IsVehicleOrHighSpeed(target, part)
	if not target or not target.Humanoid then
		return false
	end

	if target.Humanoid.SeatPart then
		return true
	end

	if part and part:IsA("BasePart") then
		local speed = part.AssemblyLinearVelocity.Magnitude
		if speed >= self.Config.HighSpeedThreshold then
			return true
		end
	end

	return false
end

function PAS:GetPredictionPoint(target, aimPart)
	if not target or not aimPart then
		return nil
	end

	local basePosition = aimPart.Position

	if not self.Config.PredictionEnabled then
		return basePosition
	end

	local velocity = Vector3.zero
	pcall(function()
		velocity = aimPart.AssemblyLinearVelocity
	end)

	if velocity.Magnitude <= 0.05 then
		return basePosition
	end

	local distance = (basePosition - Camera.CFrame.Position).Magnitude
	local predictionStrength = self.Config.PredictionStrength

	if self.Config.AdaptivePrediction then
		local distanceFactor = math.clamp(distance / 280, 0.35, 1.45)
		predictionStrength *= distanceFactor
	end

	if self.Config.VehiclePredictionBoost and self:IsVehicleOrHighSpeed(target, aimPart) then
		predictionStrength *= self.Config.VehiclePredictionMultiplier
	end

	local offset = velocity * predictionStrength

	local limit = math.max(self.Config.PredictionLimit, 0)
	if limit > 0 and offset.Magnitude > limit then
		offset = offset.Unit * limit
	end

	return basePosition + offset
end

--//====================================================
--// AIM ENGINE
--//====================================================

function PAS:ShouldAim()
	if not self.Config.SystemEnabled then
		return false
	end

	local device = self.Runtime.CurrentDevice

	if device == "Móvil" then
		return self.Config.MobileAlwaysAim
	end

	if device == "Consola" then
		return true
	end

	if self.Config.PCRequiresRightClick then
		return self.Runtime.IsRightMouseDown
	end

	return true
end

function PAS:AimAt(point, dt)
	if not point or not Camera then
		return
	end

	local camPos = Camera.CFrame.Position
	local desired = CFrame.lookAt(camPos, point)

	local strength = self.Config.AimStrength

	if self.Config.AimAcceleration then
		local targetStrength = math.clamp(strength, self.Config.AimMinStrength, self.Config.AimMaxStrength)
		local acceleration = math.clamp((dt or 0.016) * 8, 0, 1)
		self.Runtime.SmoothStrength = self.Runtime.SmoothStrength + ((targetStrength - self.Runtime.SmoothStrength) * acceleration)
		strength = self.Runtime.SmoothStrength
	else
		self.Runtime.SmoothStrength = strength
	end

	strength = math.clamp(strength, 0.01, 1)

	Camera.CFrame = Camera.CFrame:Lerp(desired, strength)
end

function PAS:UpdateAim(dt)
	if not self:ShouldAim() then
		self.Runtime.CurrentTarget = nil
		self.Runtime.CurrentAimPoint = nil

		if self.Config.AimAcceleration then
			self.Runtime.SmoothStrength = math.max(0, self.Runtime.SmoothStrength - (dt * 4))
		end

		return
	end

	local target, aimPart, visibility = self:GetBestTarget()

	if not target or not aimPart then
		self.Runtime.CurrentTarget = nil
		self.Runtime.CurrentAimPoint = nil
		return
	end

	local aimPoint = self:GetPredictionPoint(target, aimPart)

	self.Runtime.CurrentTarget = target
	self.Runtime.CurrentAimPoint = aimPoint
	self.Runtime.CurrentVisibility = visibility or 0

	self:AimAt(aimPoint, dt)
end

--//====================================================
--// UI ENGINE
--//====================================================

PAS.UI = {}

function PAS:MakeDraggable(frame, dragHandle)
	local handle = dragHandle or frame
	local dragging = false
	local dragStart = nil
	local startPosition = nil

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = frame.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if dragging and dragStart and startPosition then
				local delta = input.Position - dragStart
				frame.Position = UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
			end
		end
	end)
end

function PAS:CreateButton(parent, text, position, size, callback)
	local button = create("TextButton", {
		Name = text,
		Position = position,
		Size = size,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamSemibold,
		TextSize = 12,
		AutoButtonColor = true,
	}, parent)

	makeCorner(button, 8)
	makeStroke(button, Theme.Accent, 1, 0.65)

	button.MouseButton1Click:Connect(function()
		if callback then
			callback(button)
		end
		self:RefreshUI()
	end)

	return button
end

function PAS:CreateLabel(parent, text, position, size, textSize)
	local label = create("TextLabel", {
		Name = "Label",
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = textSize or 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)

	return label
end

function PAS:CreateTinyAdjust(parent, labelText, y, getValue, setValue, step, minValue, maxValue)
	self:CreateLabel(parent, labelText, UDim2.fromOffset(12, y), UDim2.fromOffset(132, 24), 11)

	local valueBox = create("TextBox", {
		Name = labelText .. "_Box",
		Position = UDim2.fromOffset(148, y),
		Size = UDim2.fromOffset(58, 24),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Text = tostring(getValue()),
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamSemibold,
		TextSize = 11,
		ClearTextOnFocus = false,
	}, parent)
	makeCorner(valueBox, 7)
	makeStroke(valueBox, Theme.Accent, 1, 0.7)

	local minus = self:CreateButton(parent, "-", UDim2.fromOffset(212, y), UDim2.fromOffset(28, 24), function()
		local v = clampNumber(getValue() - step, minValue, maxValue)
		setValue(v)
	end)

	local plus = self:CreateButton(parent, "+", UDim2.fromOffset(244, y), UDim2.fromOffset(28, 24), function()
		local v = clampNumber(getValue() + step, minValue, maxValue)
		setValue(v)
	end)

	valueBox.FocusLost:Connect(function()
		local v = clampNumber(valueBox.Text, minValue, maxValue)
		setValue(v)
		self:RefreshUI()
	end)

	table.insert(self.UI.ValueBoxes, {
		Box = valueBox,
		GetValue = getValue,
	})

	return valueBox, minus, plus
end

function PAS:BuildUI()
	local gui = create("ScreenGui", {
		Name = "PAS_V2_0_Profesional",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, LocalPlayer:WaitForChild("PlayerGui"))

	self.UI.Gui = gui
	self.UI.ValueBoxes = {}

	local main = create("Frame", {
		Name = "Main",
		Position = UDim2.fromOffset(72, 105),
		Size = UDim2.fromOffset(300, 420),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Visible = self.Config.MenuOpen,
	}, gui)
	makeCorner(main, 14)
	makeStroke(main, Theme.Accent, 1, 0.35)

	self.UI.Main = main

	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, main)
	makeCorner(header, 14)

	local title = create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.fromOffset(210, 22),
		BackgroundTransparency = 1,
		Text = "PAS V2.0 Profesional",
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)

	local subtitle = create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(14, 24),
		Size = UDim2.fromOffset(220, 18),
		BackgroundTransparency = 1,
		Text = "Precision Assist System",
		TextColor3 = Theme.MutedText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)

	local close = self:CreateButton(header, "—", UDim2.fromOffset(252, 10), UDim2.fromOffset(34, 28), function()
		self.Config.MenuOpen = false
		self.UI.Main.Visible = false
	end)
	close.TextSize = 18

	self:MakeDraggable(main, header)

	local status = create("TextLabel", {
		Name = "Status",
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.fromOffset(276, 26),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamSemibold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, main)
	makeCorner(status, 9)
	self.UI.Status = status

	self:CreateButton(main, "PAS: OFF", UDim2.fromOffset(12, 94), UDim2.fromOffset(132, 34), function()
		self.Config.SystemEnabled = not self.Config.SystemEnabled
	end)
	self.UI.ToggleButton = main:FindFirstChild("PAS: OFF")

	self:CreateButton(main, "FOV: ON", UDim2.fromOffset(156, 94), UDim2.fromOffset(132, 34), function()
		self.Config.ShowFOV = not self.Config.ShowFOV
	end)
	self.UI.FOVButton = main:FindFirstChild("FOV: ON")

	self:CreateButton(main, "Team: ON", UDim2.fromOffset(12, 136), UDim2.fromOffset(132, 30), function()
		self.Config.TeamCheck = not self.Config.TeamCheck
	end)
	self.UI.TeamButton = main:FindFirstChild("Team: ON")

	self:CreateButton(main, "Wall: ON", UDim2.fromOffset(156, 136), UDim2.fromOffset(132, 30), function()
		self.Config.WallCheck = not self.Config.WallCheck
	end)
	self.UI.WallButton = main:FindFirstChild("Wall: ON")

	self:CreateButton(main, "Parte: Auto", UDim2.fromOffset(12, 174), UDim2.fromOffset(132, 30), function()
		self.Config.TargetPartMode = cycleString(self.Config.TargetPartMode, { "Auto", "Cabeza", "Cuerpo", "Brazos", "Piernas" })
	end)
	self.UI.PartButton = main:FindFirstChild("Parte: Auto")

	self:CreateButton(main, "Prioridad: Visible", UDim2.fromOffset(156, 174), UDim2.fromOffset(132, 30), function()
		self.Config.PriorityMode = cycleString(self.Config.PriorityMode, { "Visible", "Cercano", "CentroFOV" })
	end)
	self.UI.PriorityButton = main:FindFirstChild("Prioridad: Visible")

	self:CreateButton(main, "Players: ON", UDim2.fromOffset(12, 212), UDim2.fromOffset(132, 30), function()
		self.Config.TargetPlayers = not self.Config.TargetPlayers
	end)
	self.UI.PlayersButton = main:FindFirstChild("Players: ON")

	self:CreateButton(main, "NPCs: OFF", UDim2.fromOffset(156, 212), UDim2.fromOffset(132, 30), function()
		self.Config.TargetNPCs = not self.Config.TargetNPCs
		self:RefreshTargetCache(true)
	end)
	self.UI.NPCButton = main:FindFirstChild("NPCs: OFF")

	self:CreateButton(main, "Predicción: ON", UDim2.fromOffset(12, 250), UDim2.fromOffset(132, 30), function()
		self.Config.PredictionEnabled = not self.Config.PredictionEnabled
	end)
	self.UI.PredictionButton = main:FindFirstChild("Predicción: ON")

	self:CreateButton(main, "Color FOV", UDim2.fromOffset(156, 250), UDim2.fromOffset(132, 30), function()
		self.Config.FOVColor = getNextColor(self.Config.FOVColor)
	end)

	self:CreateTinyAdjust(main, "FOV tamaño", 292, function()
		return self.Config.FOVRadius
	end, function(v)
		self.Config.FOVRadius = math.floor(v)
	end, 10, 40, 500)

	self:CreateTinyAdjust(main, "Fuerza apuntado", 324, function()
		return round(self.Config.AimStrength, 2)
	end, function(v)
		self.Config.AimStrength = v
	end, 0.02, 0.01, 1)

	self:CreateTinyAdjust(main, "Fuerza predicción", 356, function()
		return round(self.Config.PredictionStrength, 2)
	end, function(v)
		self.Config.PredictionStrength = v
	end, 0.05, 0, 2)

	self:CreateTinyAdjust(main, "Límite predicción", 388, function()
		return round(self.Config.PredictionLimit, 1)
	end, function(v)
		self.Config.PredictionLimit = v
	end, 1, 0, 50)

	-- Botón flotante
	local bubble = create("TextButton", {
		Name = "FloatingBubble",
		Position = UDim2.fromOffset(18, 260),
		Size = UDim2.fromOffset(58, 58),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Text = "PAS",
		TextColor3 = Theme.AccentLight,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		AutoButtonColor = true,
	}, gui)
	makeCorner(bubble, 999)
	makeStroke(bubble, Theme.AccentLight, 2, 0.1)
	self.UI.Bubble = bubble
	self:MakeDraggable(bubble, bubble)

	bubble.MouseButton1Click:Connect(function()
		self.Config.MenuOpen = not self.Config.MenuOpen
		self.UI.Main.Visible = self.Config.MenuOpen
	end)

	-- FOV Circle
	local fov = create("Frame", {
		Name = "FOVCircle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(self.Config.FOVRadius * 2, self.Config.FOVRadius * 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = self.Config.ShowFOV,
		ZIndex = 5,
	}, gui)
	makeCorner(fov, 999)
	local fovStroke = create("UIStroke", {
		Name = "FOVStroke",
		Color = self.Config.FOVColor,
		Thickness = self.Config.FOVThickness,
		Transparency = self.Config.FOVTransparency,
	}, fov)
	self.UI.FOV = fov
	self.UI.FOVStroke = fovStroke

	-- Debug
	local debugPanel = create("TextLabel", {
		Name = "DebugPanel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(260, 110),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = Theme.Text,
		Font = Enum.Font.Code,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = self.Config.ShowDebug,
		ZIndex = 50,
	}, gui)
	makeCorner(debugPanel, 10)
	makeStroke(debugPanel, Theme.Accent, 1, 0.45)
	self.UI.DebugPanel = debugPanel

	self:RefreshUI()
end

function PAS:RefreshUI()
	if not self.UI or not self.UI.Gui then
		return
	end

	if self.UI.ToggleButton then
		self.UI.ToggleButton.Text = self.Config.SystemEnabled and "PAS: ON" or "PAS: OFF"
		self.UI.ToggleButton.TextColor3 = self.Config.SystemEnabled and Theme.Green or Theme.Red
	end

	if self.UI.FOVButton then
		self.UI.FOVButton.Text = self.Config.ShowFOV and "FOV: ON" or "FOV: OFF"
	end

	if self.UI.TeamButton then
		self.UI.TeamButton.Text = self.Config.TeamCheck and "Team: ON" or "Team: OFF"
	end

	if self.UI.WallButton then
		self.UI.WallButton.Text = self.Config.WallCheck and "Wall: ON" or "Wall: OFF"
	end

	if self.UI.PartButton then
		self.UI.PartButton.Text = "Parte: " .. tostring(self.Config.TargetPartMode)
	end

	if self.UI.PriorityButton then
		self.UI.PriorityButton.Text = "Prioridad: " .. tostring(self.Config.PriorityMode)
	end

	if self.UI.PlayersButton then
		self.UI.PlayersButton.Text = self.Config.TargetPlayers and "Players: ON" or "Players: OFF"
	end

	if self.UI.NPCButton then
		self.UI.NPCButton.Text = self.Config.TargetNPCs and "NPCs: ON" or "NPCs: OFF"
	end

	if self.UI.PredictionButton then
		self.UI.PredictionButton.Text = self.Config.PredictionEnabled and "Predicción: ON" or "Predicción: OFF"
	end

	if self.UI.Status then
		local targetName = "Sin objetivo"
		if self.Runtime.CurrentTarget then
			targetName = self.Runtime.CurrentTarget.Name or "Objetivo"
		end

		self.UI.Status.Text = string.format(
			"%s | %s | %s",
			self.Runtime.CurrentDevice,
			self.Config.SystemEnabled and "Activo" or "Apagado",
			targetName
		)
	end

	if self.UI.ValueBoxes then
		for _, item in ipairs(self.UI.ValueBoxes) do
			if item.Box and not item.Box:IsFocused() then
				item.Box.Text = tostring(item.GetValue())
			end
		end
	end

	if self.UI.Bubble then
		self.UI.Bubble.TextColor3 = self.Config.SystemEnabled and Theme.Green or Theme.AccentLight
	end
end

function PAS:UpdateFOV()
	if not self.UI or not self.UI.FOV then
		return
	end

	local radius = self.Config.FOVRadius
	self.UI.FOV.Size = UDim2.fromOffset(radius * 2, radius * 2)
	self.UI.FOV.Position = UDim2.fromScale(0.5, 0.5)
	self.UI.FOV.Visible = self.Config.ShowFOV

	self.UI.FOVStroke.Color = self.Config.FOVColor
	self.UI.FOVStroke.Thickness = self.Config.FOVThickness
	self.UI.FOVStroke.Transparency = self.Config.FOVTransparency
end

function PAS:UpdateDebug(dt)
	if not self.UI or not self.UI.DebugPanel then
		return
	end

	self.UI.DebugPanel.Visible = self.Config.ShowDebug

	if not self.Config.ShowDebug then
		return
	end

	local targetText = "Ninguno"
	if self.Runtime.CurrentTarget then
		targetText = tostring(self.Runtime.CurrentTarget.Name)
	end

	local aimText = "No"
	if self:ShouldAim() then
		aimText = "Sí"
	end

	self.UI.DebugPanel.Text = table.concat({
		" PAS V2.0 Debug",
		" FPS: " .. tostring(self.Runtime.FPS),
		" Device: " .. tostring(self.Runtime.CurrentDevice),
		" Aim activo: " .. aimText,
		" Objetivos FOV: " .. tostring(self.Runtime.DetectedTargets),
		" Target: " .. targetText,
		" Visible: " .. tostring(math.floor((self.Runtime.CurrentVisibility or 0) * 100)) .. "%",
		" AimStrength: " .. tostring(round(self.Runtime.SmoothStrength, 3)),
		" Pred: " .. tostring(self.Config.PredictionEnabled) .. " / " .. tostring(round(self.Config.PredictionStrength, 2)),
		" FOV: " .. tostring(self.Config.FOVRadius) .. " / " .. colorName(self.Config.FOVColor),
	}, "\n")
end

--//====================================================
--// INPUT ENGINE
--//====================================================

function PAS:BindInput()
	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.Runtime.IsRightMouseDown = true
		end

		if input.KeyCode == self.Config.MenuKey then
			self.Config.MenuOpen = not self.Config.MenuOpen
			if self.UI.Main then
				self.UI.Main.Visible = self.Config.MenuOpen
			end
		elseif input.KeyCode == self.Config.ToggleKey then
			self.Config.SystemEnabled = not self.Config.SystemEnabled
			self:RefreshUI()
		elseif input.KeyCode == self.Config.DebugKey then
			self.Config.ShowDebug = not self.Config.ShowDebug
			self:RefreshUI()
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.Runtime.IsRightMouseDown = false
		end
	end)
end

--//====================================================
--// LOOP / INIT / DESTROY
--//====================================================

function PAS:UpdateFPS()
	self.Runtime.FrameCounter += 1

	local now = os.clock()
	if now - self.Runtime.LastFPSUpdate >= 1 then
		self.Runtime.FPS = self.Runtime.FrameCounter
		self.Runtime.FrameCounter = 0
		self.Runtime.LastFPSUpdate = now
	end
end

function PAS:StartLoop()
	connect(RunService.RenderStepped, function(dt)
		if self.Runtime.Destroyed then
			return
		end

		local start = os.clock()

		self.Runtime.CurrentDevice = getDeviceType()
		self:UpdateFPS()
		self:UpdateAim(dt)
		self:UpdateFOV()

		if os.clock() - (self.Runtime.LastUIRefresh or 0) > 0.15 then
			self.Runtime.LastUIRefresh = os.clock()
			self:RefreshUI()
			self:UpdateDebug(dt)
		end

		self.Runtime.LastFrameMs = round((os.clock() - start) * 1000, 3)
	end)
end

function PAS:Destroy()
	self.Runtime.Destroyed = true
	self.Config.SystemEnabled = false

	for _, c in ipairs(self.Runtime.Connections) do
		pcall(function()
			c:Disconnect()
		end)
	end

	table.clear(self.Runtime.Connections)

	if self.UI and self.UI.Gui then
		self.UI.Gui:Destroy()
	end
end

function PAS:Init()
	self.Runtime.CurrentDevice = getDeviceType()
	self:BuildUI()
	self:BindInput()
	self:StartLoop()

	print("[PAS V2.0 Profesional] Cargado correctamente. Proyecto 3/3.")
end

PAS:Init()

return PAS
