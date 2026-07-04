--//====================================================
--// PAS - Precision Assist System V1.2 Base
--// Sistema de Puntería Asistida para tus propios juegos de Roblox Studio
--// LocalScript en StarterPlayer > StarterPlayerScripts
--// Proyecto 3/3 - Base inicial portable
--//====================================================

--[[
	PAS V1.2 Base

	Objetivo:
	- Crear una puntería asistida legítima para juegos propios en Roblox Studio.
	- Mantener estilo visual tipo SVT.
	- Compatible con PC y móvil.
	- Usar FOV circular configurable.
	- Elegir parte objetivo: Cabeza, Cuerpo, Brazo, Pierna o Automático.
	- Priorizar objetivos visibles dentro del FOV.
	- Wall Check opcional:
		* ON  = solo apunta a objetivos visibles.
		* OFF = puede aceptar objetivos no visibles, pero prioriza el más visible.
	- PC: puede trabajar solo mientras se mantiene clic derecho.
	- Móvil: puede mantenerse activo mientras PAS esté encendido.

	Notas:
	- Este script mueve la cámara del jugador local hacia objetivos válidos.
	- No crea daño, no dispara, no modifica armas ni hitboxes.
	- Pensado para recompensas, habilidades o modos especiales dentro de tu propio juego.
]]

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
	MenuOpen = false,

	-- Plataforma
	AutoDetectPlatform = true,
	PlatformMode = "Auto", -- "Auto", "PC", "Movil"

	-- Activación
	RequireRightClickPC = true,
	MobileAlwaysAssist = true,
	ToggleKey = Enum.KeyCode.P,
	MenuKey = Enum.KeyCode.RightShift,

	-- FOV
	ShowFOV = true,
	FOVRadius = 145,
	FOVColor = Color3.fromRGB(0, 220, 255),
	FOVTransparency = 0.35,
	FOVThickness = 2,

	-- Puntería
	AimPart = "Cuerpo", -- "Cabeza", "Cuerpo", "Brazo", "Pierna", "Automatico"
	Smoothness = 0.18,
	MaxDistance = 650,
	MaxTargets = 45,

	-- Filtros
	ShowPlayers = true,
	ShowNPCs = false,
	TeamCheck = true,
	WallCheck = true,
	PrioritizeVisible = true,

	-- Visibilidad
	VisibilityMode = "Partes", -- "Basico" o "Partes"
	VisibilityUpdateRate = 0.12,

	-- Rendimiento
	UpdateRate = 0.03,
	NPCCacheRate = 1.5,
	DebugUpdateRate = 0.4,

	-- UI
	ShowDebugPanel = true,
}

PAS.Runtime = {
	CurrentPage = "Inicio",
	Connections = {},
	NPCs = {},
	LastNPCCache = 0,
	LastUpdate = 0,
	LastDebugUpdate = 0,
	VisibilityCache = {},
	DetectedTargets = 0,
	CurrentTarget = nil,
	CurrentTargetName = "Ninguno",
	CurrentPlatform = "PC",
	IsRightClickDown = false,
	Destroyed = false,

	FPS = 0,
	FrameCounter = 0,
	LastFPSUpdate = 0,
}

local Themes = {
	Default = {
		Background = Color3.fromRGB(12, 14, 18),
		Panel = Color3.fromRGB(20, 24, 31),
		PanelLight = Color3.fromRGB(30, 36, 46),
		Accent = Color3.fromRGB(0, 145, 255),
		AccentLight = Color3.fromRGB(0, 220, 255),
		Text = Color3.fromRGB(240, 245, 255),
		MutedText = Color3.fromRGB(165, 175, 190),
		Green = Color3.fromRGB(90, 255, 150),
		Red = Color3.fromRGB(255, 90, 90),
		DarkDot = Color3.fromRGB(8, 9, 12),
	}
}

local Theme = Themes.Default

local ColorPalette = {
	{ Name = "Celeste", Value = Color3.fromRGB(0, 220, 255) },
	{ Name = "Azul", Value = Color3.fromRGB(0, 145, 255) },
	{ Name = "Verde", Value = Color3.fromRGB(90, 255, 150) },
	{ Name = "Rojo", Value = Color3.fromRGB(255, 90, 90) },
	{ Name = "Morado", Value = Color3.fromRGB(180, 120, 255) },
	{ Name = "Naranja", Value = Color3.fromRGB(255, 170, 0) },
	{ Name = "Blanco", Value = Color3.fromRGB(245, 245, 245) },
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
	local connection = signal:Connect(fn)
	table.insert(PAS.Runtime.Connections, connection)
	return connection
end

local function clampNumber(value, minValue, maxValue)
	local number = tonumber(value)
	if not number then
		return minValue
	end
	return math.clamp(number, minValue, maxValue)
end

local function getDeviceType()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Movil"
	end

	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Consola"
	end

	return "PC"
end

local function getPlatformMode()
	if PAS.Config.AutoDetectPlatform or PAS.Config.PlatformMode == "Auto" then
		local device = getDeviceType()
		if device == "Movil" then
			return "Movil"
		end
		return "PC"
	end

	return PAS.Config.PlatformMode
end

local function getNextPaletteColor(currentColor)
	local bestIndex = 1
	local bestDistance = math.huge

	for index, entry in ipairs(ColorPalette) do
		local c = entry.Value
		local distance = math.abs(c.R - currentColor.R) + math.abs(c.G - currentColor.G) + math.abs(c.B - currentColor.B)

		if distance < bestDistance then
			bestDistance = distance
			bestIndex = index
		end
	end

	local nextIndex = bestIndex + 1
	if nextIndex > #ColorPalette then
		nextIndex = 1
	end

	return ColorPalette[nextIndex].Value
end

local function getCharacterData(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")

	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end

	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Head = head or root,
		Name = model.Name,
		Type = "NPC",
		Player = nil,
		Team = nil,
	}
end

local function hasTagSafe(instance, tagName)
	local ok, result = pcall(function()
		return CollectionService:HasTag(instance, tagName)
	end)

	return ok and result
end

local function getTargetType(model, player)
	local explicitType = model:GetAttribute("PAS_TargetType") or model:GetAttribute("SVT_TargetType") or model:GetAttribute("THS_TargetType")
	if explicitType then
		return tostring(explicitType)
	end

	if hasTagSafe(model, "Boss") or hasTagSafe(model, "PAS_Boss") then
		return "Boss"
	end

	if hasTagSafe(model, "Dummy") or hasTagSafe(model, "PAS_Dummy") then
		return "Dummy"
	end

	if player then
		if LocalPlayer.Team and player.Team == LocalPlayer.Team then
			return "Ally"
		end
		return "Enemy"
	end

	return "NPC"
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

local function getAimPart(target)
	local model = target.Model
	local mode = PAS.Config.AimPart

	if mode == "Cabeza" then
		return findFirstPart(model, { "Head" }) or target.Root
	end

	if mode == "Cuerpo" then
		return findFirstPart(model, { "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart" }) or target.Root
	end

	if mode == "Brazo" then
		return findFirstPart(model, {
			"RightUpperArm", "RightLowerArm", "RightHand",
			"LeftUpperArm", "LeftLowerArm", "LeftHand",
			"Right Arm", "Left Arm",
		}) or target.Root
	end

	if mode == "Pierna" then
		return findFirstPart(model, {
			"RightUpperLeg", "RightLowerLeg", "RightFoot",
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"Right Leg", "Left Leg",
		}) or target.Root
	end

	-- Automatico: prioriza cuerpo, luego cabeza, luego root.
	return findFirstPart(model, { "UpperTorso", "Torso", "LowerTorso", "Head", "HumanoidRootPart" }) or target.Root
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

--//====================================================
--// TARGET ENGINE
--//====================================================

function PAS:RefreshNPCCache()
	local now = os.clock()

	if now - self.Runtime.LastNPCCache < self.Config.NPCCacheRate then
		return
	end

	self.Runtime.LastNPCCache = now
	table.clear(self.Runtime.NPCs)

	if not self.Config.ShowNPCs then
		return
	end

	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("Model") and not Players:GetPlayerFromCharacter(item) then
			local data = getCharacterData(item)
			if data then
				table.insert(self.Runtime.NPCs, data)
			end
		end
	end
end

function PAS:GetLocalRoot()
	if LocalPlayer.Character then
		return LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	end

	return nil
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
	local cached = self.Runtime.VisibilityCache[target.Model]
	local now = os.clock()

	if cached and now - cached.Time < self.Config.VisibilityUpdateRate then
		return cached.Score, cached.AnyVisible
	end

	local score = 0
	local checked = 0
	local anyVisible = false

	if self.Config.VisibilityMode == "Basico" then
		checked = 1
		if self:IsPartVisible(target.Root, target.Model) then
			score = 1
			anyVisible = true
		end
	else
		local parts = getBodyParts(target.Model)
		checked = math.max(#parts, 1)

		for _, part in ipairs(parts) do
			if self:IsPartVisible(part, target.Model) then
				score += 1
				anyVisible = true
			end
		end
	end

	local finalScore = score / checked

	self.Runtime.VisibilityCache[target.Model] = {
		Time = now,
		Score = finalScore,
		AnyVisible = anyVisible,
	}

	return finalScore, anyVisible
end

function PAS:IsInsideFOV(worldPosition)
	if not Camera then
		return false, math.huge, nil
	end

	local screenPoint, onScreen = Camera:WorldToViewportPoint(worldPosition)
	if not onScreen or screenPoint.Z <= 0 then
		return false, math.huge, nil
	end

	local center = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5)
	local point = Vector2.new(screenPoint.X, screenPoint.Y)
	local distanceFromCenter = (point - center).Magnitude

	return distanceFromCenter <= self.Config.FOVRadius, distanceFromCenter, screenPoint
end

function PAS:GetTargets()
	local targets = {}
	local localRoot = self:GetLocalRoot()

	if self.Config.ShowPlayers then
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and player.Character then
				local data = getCharacterData(player.Character)

				if data then
					data.Type = "Player"
					data.Player = player
					data.Team = player.Team
					data.TargetType = getTargetType(player.Character, player)
					data.Name = player.Name

					if not self.Config.TeamCheck or not LocalPlayer.Team or player.Team ~= LocalPlayer.Team then
						table.insert(targets, data)
					end
				end
			end
		end
	end

	if self.Config.ShowNPCs then
		self:RefreshNPCCache()

		for _, data in ipairs(self.Runtime.NPCs) do
			if data.Model and data.Model.Parent and data.Humanoid and data.Humanoid.Health > 0 then
				data.TargetType = getTargetType(data.Model, nil)
				table.insert(targets, data)
			end
		end
	end

	local filtered = {}

	for _, target in ipairs(targets) do
		local aimPart = getAimPart(target)
		if aimPart then
			local insideFOV, fovDistance = self:IsInsideFOV(aimPart.Position)

			if insideFOV then
				local distance = math.huge
				if localRoot and target.Root then
					distance = (target.Root.Position - localRoot.Position).Magnitude
				elseif Camera and target.Root then
					distance = (Camera.CFrame.Position - target.Root.Position).Magnitude
				end

				if distance <= self.Config.MaxDistance then
					local visibilityScore, anyVisible = self:GetVisibilityScore(target)

					if not self.Config.WallCheck or anyVisible then
						target.AimPart = aimPart
						target.Distance = distance
						target.FOVDistance = fovDistance
						target.VisibilityScore = visibilityScore
						target.AnyVisible = anyVisible
						table.insert(filtered, target)
					end
				end
			end
		end
	end

	table.sort(filtered, function(a, b)
		local visibleA = a.VisibilityScore or 0
		local visibleB = b.VisibilityScore or 0

		if self.Config.PrioritizeVisible and math.abs(visibleA - visibleB) > 0.05 then
			return visibleA > visibleB
		end

		local fovA = a.FOVDistance or math.huge
		local fovB = b.FOVDistance or math.huge

		if math.abs(fovA - fovB) > 6 then
			return fovA < fovB
		end

		return (a.Distance or math.huge) < (b.Distance or math.huge)
	end)

	if #filtered > self.Config.MaxTargets then
		local limited = {}
		for i = 1, self.Config.MaxTargets do
			limited[i] = filtered[i]
		end
		filtered = limited
	end

	self.Runtime.DetectedTargets = #filtered
	return filtered
end

function PAS:GetBestTarget()
	local targets = self:GetTargets()
	return targets[1]
end

--//====================================================
--// AIM ENGINE
--//====================================================

function PAS:ShouldAssist()
	if not self.Config.SystemEnabled then
		return false
	end

	local platform = self.Runtime.CurrentPlatform

	if platform == "Movil" then
		return self.Config.MobileAlwaysAssist
	end

	if self.Config.RequireRightClickPC then
		return self.Runtime.IsRightClickDown
	end

	return true
end

function PAS:UpdateAim()
	if not self:ShouldAssist() then
		self.Runtime.CurrentTarget = nil
		self.Runtime.CurrentTargetName = "Ninguno"
		return
	end

	local target = self:GetBestTarget()

	if not target or not target.AimPart then
		self.Runtime.CurrentTarget = nil
		self.Runtime.CurrentTargetName = "Ninguno"
		return
	end

	self.Runtime.CurrentTarget = target.Model
	self.Runtime.CurrentTargetName = target.Name or target.Model.Name

	local cameraPosition = Camera.CFrame.Position
	local targetPosition = target.AimPart.Position
	local wantedCFrame = CFrame.new(cameraPosition, targetPosition)

	local alpha = clampNumber(self.Config.Smoothness, 0.01, 1)
	Camera.CFrame = Camera.CFrame:Lerp(wantedCFrame, alpha)
end

--//====================================================
--// UI ENGINE
--//====================================================

function PAS:CreateUI()
	local gui = create("ScreenGui", {
		Name = "PAS_UI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, LocalPlayer:WaitForChild("PlayerGui"))

	local fovCircle = create("Frame", {
		Name = "PAS_FOV_Circle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(self.Config.FOVRadius * 2, self.Config.FOVRadius * 2),
		BackgroundTransparency = 1,
		Visible = self.Config.ShowFOV,
		ZIndex = 5,
	}, gui)

	create("UICorner", {
		CornerRadius = UDim.new(1, 0),
	}, fovCircle)

	create("UIStroke", {
		Name = "Stroke",
		Color = self.Config.FOVColor,
		Thickness = self.Config.FOVThickness,
		Transparency = self.Config.FOVTransparency,
	}, fovCircle)

	local openButton = create("TextButton", {
		Name = "PAS_OpenButton",
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(0, 18, 0.5, -27),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Text = "PAS",
		TextColor3 = Theme.Text,
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = true,
		ZIndex = 20,
	}, gui)

	create("UICorner", {
		CornerRadius = UDim.new(0, 14),
	}, openButton)

	create("UIStroke", {
		Color = Theme.Accent,
		Thickness = 2,
		Transparency = 0.15,
	}, openButton)

	local main = create("Frame", {
		Name = "PAS_Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(410, 470),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
	}, gui)

	create("UICorner", {
		CornerRadius = UDim.new(0, 18),
	}, main)

	create("UIStroke", {
		Color = Theme.Accent,
		Thickness = 2,
		Transparency = 0.25,
	}, main)

	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -20, 0, 42),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Text = "PAS V1.2  |  Precision Assist System",
		TextColor3 = Theme.Text,
		TextSize = 17,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
	}, main)

	local closeButton = create("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, -44, 0, 12),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Text = "X",
		TextColor3 = Theme.Text,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		ZIndex = 32,
	}, main)

	create("UICorner", {
		CornerRadius = UDim.new(0, 10),
	}, closeButton)

	local content = create("ScrollingFrame", {
		Name = "Content",
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 54),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.fromOffset(0, 720),
		ZIndex = 31,
	}, main)

	create("UICorner", {
		CornerRadius = UDim.new(0, 14),
	}, content)

	local layout = create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, content)

	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	}, content)

	local function makeLabel(text)
		return create("TextLabel", {
			Size = UDim2.new(1, -4, 0, 26),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = Theme.MutedText,
			TextSize = 13,
			Font = Enum.Font.GothamSemibold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 32,
		}, content)
	end

	local function makeButton(text, callback)
		local button = create("TextButton", {
			Size = UDim2.new(1, -4, 0, 38),
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Text = text,
			TextColor3 = Theme.Text,
			TextSize = 13,
			Font = Enum.Font.GothamSemibold,
			AutoButtonColor = true,
			ZIndex = 32,
		}, content)

		create("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}, button)

		button.MouseButton1Click:Connect(callback)
		return button
	end

	local function makeToggle(label, key)
		local button
		button = makeButton("", function()
			self.Config[key] = not self.Config[key]
			button.Text = label .. ": " .. (self.Config[key] and "ON" or "OFF")
			self:RefreshUI()
		end)

		button.Text = label .. ": " .. (self.Config[key] and "ON" or "OFF")
		return button
	end

	local function makeCycle(label, key, values)
		local button
		button = makeButton("", function()
			local current = self.Config[key]
			local index = table.find(values, current) or 1
			index += 1
			if index > #values then
				index = 1
			end

			self.Config[key] = values[index]
			button.Text = label .. ": " .. tostring(self.Config[key])
			self:RefreshUI()
		end)

		button.Text = label .. ": " .. tostring(self.Config[key])
		return button
	end

	local function makeNumberControl(label, key, step, minValue, maxValue)
		local row = create("Frame", {
			Size = UDim2.new(1, -4, 0, 38),
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			ZIndex = 32,
		}, content)

		create("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}, row)

		local minus = create("TextButton", {
			Size = UDim2.fromOffset(38, 30),
			Position = UDim2.fromOffset(5, 4),
			BackgroundColor3 = Theme.Background,
			BorderSizePixel = 0,
			Text = "-",
			TextColor3 = Theme.Text,
			TextSize = 18,
			Font = Enum.Font.GothamBold,
			ZIndex = 33,
		}, row)

		create("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}, minus)

		local valueLabel = create("TextLabel", {
			Size = UDim2.new(1, -92, 1, 0),
			Position = UDim2.fromOffset(46, 0),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = Theme.Text,
			TextSize = 13,
			Font = Enum.Font.GothamSemibold,
			ZIndex = 33,
		}, row)

		local plus = create("TextButton", {
			Size = UDim2.fromOffset(38, 30),
			Position = UDim2.new(1, -43, 0, 4),
			BackgroundColor3 = Theme.Background,
			BorderSizePixel = 0,
			Text = "+",
			TextColor3 = Theme.Text,
			TextSize = 18,
			Font = Enum.Font.GothamBold,
			ZIndex = 33,
		}, row)

		create("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}, plus)

		local function refresh()
			local value = self.Config[key]
			if typeof(value) == "number" then
				if value < 1 then
					valueLabel.Text = label .. ": " .. string.format("%.2f", value)
				else
					valueLabel.Text = label .. ": " .. tostring(math.floor(value * 100) / 100)
				end
			else
				valueLabel.Text = label .. ": " .. tostring(value)
			end
		end

		minus.MouseButton1Click:Connect(function()
			self.Config[key] = clampNumber(self.Config[key] - step, minValue, maxValue)
			refresh()
			self:RefreshUI()
		end)

		plus.MouseButton1Click:Connect(function()
			self.Config[key] = clampNumber(self.Config[key] + step, minValue, maxValue)
			refresh()
			self:RefreshUI()
		end)

		refresh()
		return row
	end

	makeLabel("Estado")
	makeToggle("PAS activo", "SystemEnabled")
	makeToggle("Mostrar FOV", "ShowFOV")
	makeCycle("Plataforma", "PlatformMode", { "Auto", "PC", "Movil" })
	makeToggle("Auto detectar plataforma", "AutoDetectPlatform")

	makeLabel("Puntería")
	makeCycle("Parte objetivo", "AimPart", { "Cabeza", "Cuerpo", "Brazo", "Pierna", "Automatico" })
	makeNumberControl("Suavidad", "Smoothness", 0.03, 0.01, 1)
	makeNumberControl("Distancia máxima", "MaxDistance", 50, 50, 2000)

	makeLabel("FOV")
	makeNumberControl("Radio FOV", "FOVRadius", 10, 35, 450)
	makeNumberControl("Grosor FOV", "FOVThickness", 1, 1, 8)
	makeButton("Cambiar color FOV", function()
		self.Config.FOVColor = getNextPaletteColor(self.Config.FOVColor)
		self:RefreshUI()
	end)

	makeLabel("Filtros")
	makeToggle("Jugadores", "ShowPlayers")
	makeToggle("NPCs", "ShowNPCs")
	makeToggle("Team Check", "TeamCheck")
	makeToggle("Wall Check", "WallCheck")
	makeToggle("Priorizar visibles", "PrioritizeVisible")

	makeLabel("Activación")
	makeToggle("PC requiere clic derecho", "RequireRightClickPC")
	makeToggle("Móvil siempre activo", "MobileAlwaysAssist")

	makeLabel("Debug")
	local debugLabel = create("TextLabel", {
		Name = "DebugLabel",
		Size = UDim2.new(1, -4, 0, 92),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = Theme.MutedText,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 32,
	}, content)

	create("UICorner", {
		CornerRadius = UDim.new(0, 10),
	}, debugLabel)

	makeButton("Cerrar totalmente PAS", function()
		self:Destroy()
	end)

	openButton.MouseButton1Click:Connect(function()
		self.Config.MenuOpen = not self.Config.MenuOpen
		main.Visible = self.Config.MenuOpen
		self:RefreshUI()
	end)

	closeButton.MouseButton1Click:Connect(function()
		self.Config.MenuOpen = false
		main.Visible = false
	end)

	self.UI = {
		Gui = gui,
		FOVCircle = fovCircle,
		FOVStroke = fovCircle:FindFirstChild("Stroke"),
		OpenButton = openButton,
		Main = main,
		DebugLabel = debugLabel,
	}
end

function PAS:RefreshUI()
	if not self.UI then
		return
	end

	self.Runtime.CurrentPlatform = getPlatformMode()

	if self.UI.FOVCircle then
		self.UI.FOVCircle.Visible = self.Config.ShowFOV
		self.UI.FOVCircle.Size = UDim2.fromOffset(self.Config.FOVRadius * 2, self.Config.FOVRadius * 2)
	end

	if self.UI.FOVStroke then
		self.UI.FOVStroke.Color = self.Config.FOVColor
		self.UI.FOVStroke.Thickness = self.Config.FOVThickness
		self.UI.FOVStroke.Transparency = self.Config.FOVTransparency
	end

	if self.UI.OpenButton then
		self.UI.OpenButton.BackgroundColor3 = self.Config.SystemEnabled and Theme.Accent or Theme.Panel
	end
end

function PAS:RefreshDebug(force)
	if not self.UI or not self.UI.DebugLabel then
		return
	end

	local now = os.clock()
	if not force and now - self.Runtime.LastDebugUpdate < self.Config.DebugUpdateRate then
		return
	end

	self.Runtime.LastDebugUpdate = now

	self.UI.DebugLabel.Text =
		" Plataforma: " .. tostring(self.Runtime.CurrentPlatform) ..
		"\n Objetivos dentro FOV: " .. tostring(self.Runtime.DetectedTargets) ..
		"\n Objetivo actual: " .. tostring(self.Runtime.CurrentTargetName) ..
		"\n Clic derecho PC: " .. tostring(self.Runtime.IsRightClickDown) ..
		"\n Wall Check: " .. tostring(self.Config.WallCheck) ..
		"\n FPS aprox: " .. tostring(self.Runtime.FPS)
end

--//====================================================
--// INPUT / LOOP / INIT
--//====================================================

function PAS:BindInputs()
	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == self.Config.MenuKey then
			self.Config.MenuOpen = not self.Config.MenuOpen
			if self.UI and self.UI.Main then
				self.UI.Main.Visible = self.Config.MenuOpen
			end
		end

		if input.KeyCode == self.Config.ToggleKey then
			self.Config.SystemEnabled = not self.Config.SystemEnabled
			self:RefreshUI()
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.Runtime.IsRightClickDown = true
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.Runtime.IsRightClickDown = false
		end
	end)
end

function PAS:UpdateFPS(dt)
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

		self:UpdateFPS(dt)
		self.Runtime.CurrentPlatform = getPlatformMode()

		local now = os.clock()
		if now - self.Runtime.LastUpdate >= self.Config.UpdateRate then
			self.Runtime.LastUpdate = now
			self:UpdateAim()
			self:RefreshUI()
		end

		self:RefreshDebug(false)
	end)
end

function PAS:Destroy()
	self.Runtime.Destroyed = true
	self.Config.SystemEnabled = false

	for _, connection in ipairs(self.Runtime.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	table.clear(self.Runtime.Connections)
	table.clear(self.Runtime.NPCs)
	table.clear(self.Runtime.VisibilityCache)

	if self.UI and self.UI.Gui then
		self.UI.Gui:Destroy()
	end
end

function PAS:Init()
	self.Runtime.CurrentPlatform = getPlatformMode()
	self:CreateUI()
	self:BindInputs()
	self:StartLoop()
	self:RefreshUI()
	self:RefreshDebug(true)

	print("[PAS] Precision Assist System V1.2 Base cargado correctamente.")
end

PAS:Init()

return PAS
