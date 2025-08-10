for k, v in pairs(getgc(true)) do
	if pcall(function()
		return rawget(v, "indexInstance")
	end) and type(rawget(v, "indexInstance")) == "table" and (rawget(v, "indexInstance"))[1] == "kick" then
		setreadonly(v, false)
		v.tvk = {
			"kick",
			function()
				return game.Workspace:WaitForChild("")
			end
		}
	end
end
if not game:IsLoaded() then 
    game.Loaded:Wait()
end

if not syn or not protectgui then
    getgenv().protectgui = function() end
end

local SilentAimSettings = {
    Enabled = false,
    
    ClassName = "Universal Silent Aim - Averiias, Stefanuk12, xaxa",
    ToggleKey = "RightAlt",
    
    TeamCheck = false,
    VisibleCheck = false, 
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    
    FOVRadius = 130,
    FOVVisible = false,
    ShowSilentAimTarget = false, 
    
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100
}

-- variables
getgenv().SilentAimSettings = SilentAimSettings
local MainFileName = "UniversalSilentAim"
local SelectedFile, FileToSave = ""

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local GetChildren = game.GetChildren
local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.Heartbeat
local GuiInset = GuiService.GetGuiInset
local GetMouseLocation = UserInputService.GetMouseLocation

local resume = coroutine.resume 
local create = coroutine.create

local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = 0.165

local mouse_box = Drawing.new("Square")
mouse_box.Visible = true 
mouse_box.ZIndex = 999 
mouse_box.Color = Color3.fromRGB(54, 57, 241)
mouse_box.Thickness = 20 
mouse_box.Size = Vector2.new(20, 20)
mouse_box.Filled = true 

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = 180
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Color3.fromRGB(54, 57, 241)

local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Ray", "table", "boolean", "boolean"
        }
    },
    FindPartOnRayWithWhitelist = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Ray", "table", "boolean"
        }
    },
    FindPartOnRay = {
        ArgCountRequired = 2,
        Args = {
            "Instance", "Ray", "Instance", "boolean", "boolean"
        }
    },
    Raycast = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Vector3", "Vector3", "RaycastParams"
        }
    }
}

-- Cache for closest player
local closestPlayerCache = {
    Part = nil,
    LastUpdate = 0,
    Cooldown = 0.1 -- Update every 0.1 seconds
}

function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100
    return chance <= Percentage / 100
end

-- File handling
if not isfolder(MainFileName) then 
    makefolder(MainFileName)
end

if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then 
    makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
end

local Files = listfiles(string.format("%s/%s", "UniversalSilentAim", tostring(game.PlaceId)))

local function GetFiles()
    local out = {}
    for i = 1, #Files do
        local file = Files[i]
        if file:sub(-4) == '.lua' then
            local pos = file:find('.lua', 1, true)
            local start = pos
            local char = file:sub(pos, pos)
            
            while char ~= '/' and char ~= '\\' and char ~= '' do
                pos = pos - 1
                char = file:sub(pos, pos)
            end

            if char == '/' or char == '\\' then
                table.insert(out, file:sub(pos + 1, start - 1))
            end
        end
    end
    return out
end

local function UpdateFile(FileName)
    assert(type(FileName) == "string", "FileName must be a string")
    writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
end

local function LoadFile(FileName)
    assert(type(FileName) == "string", "FileName must be a string")
    local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
    local ConfigData = HttpService:JSONDecode(readfile(File))
    for Index, Value in next, ConfigData do
        SilentAimSettings[Index] = Value
    end
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then
        return false
    end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then
            Matches = Matches + 1
        end
    end
    return Matches >= RayMethod.ArgCountRequired
end

local function getDirection(Origin, Position)
    return (Position - Origin).Unit * 1000
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function IsPlayerVisible(Player)
    local PlayerCharacter = Player.Character
    local LocalPlayerCharacter = LocalPlayer.Character
    
    if not (PlayerCharacter or LocalPlayerCharacter) then return end 
    
    local PlayerRoot = FindFirstChild(PlayerCharacter, SilentAimSettings.TargetPart) or FindFirstChild(PlayerCharacter, "HumanoidRootPart")
    
    if not PlayerRoot then return end 
    
    local CastPoints = {PlayerRoot.Position}
    local IgnoreList = {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    
    return ObscuringObjects == 0
end

local function UpdateClosestPlayer()
    local now = tick()
    if now - closestPlayerCache.LastUpdate < closestPlayerCache.Cooldown then
        return
    end
    
    closestPlayerCache.LastUpdate = now
    closestPlayerCache.Part = nil
    
    if not SilentAimSettings.TargetPart then return end
    
    local Closest
    local DistanceToMouse
    local MousePos = getMousePosition()
    
    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
        if SilentAimSettings.TeamCheck and Player.Team == LocalPlayer.Team then continue end

        local Character = Player.Character
        if not Character then continue end
        
        if SilentAimSettings.VisibleCheck and not IsPlayerVisible(Player) then continue end

        local HumanoidRootPart = FindFirstChild(Character, "HumanoidRootPart")
        local Humanoid = FindFirstChild(Character, "Humanoid")
        if not HumanoidRootPart or not Humanoid or Humanoid.Health <= 0 then continue end

        local ScreenPosition, OnScreen = getPositionOnScreen(HumanoidRootPart.Position)
        if not OnScreen then continue end

        local Distance = (MousePos - ScreenPosition).Magnitude
        if Distance <= (DistanceToMouse or SilentAimSettings.FOVRadius or 2000) then
            Closest = ((SilentAimSettings.TargetPart == "Random" and Character[ValidTargetParts[math.random(1, #ValidTargetParts)]]) or Character[SilentAimSettings.TargetPart])
            DistanceToMouse = Distance
        end
    end
    
    closestPlayerCache.Part = Closest
end

local function getClosestPlayer()
    UpdateClosestPlayer()
    return closestPlayerCache.Part
end

-- UI Library
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local Window = Library:CreateWindow({Title = 'Universal Silent Aim', Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2})
local GeneralTab = Window:AddTab("General")

local MainBOX = GeneralTab:AddLeftTabbox("Main")
local Main = MainBOX:AddTab("Main")

Main:AddToggle("aim_Enabled", {Text = "Enabled"}):AddKeyPicker("aim_Enabled_KeyPicker", {
    Default = "RightAlt", 
    SyncToggleState = true, 
    Mode = "Toggle", 
    Text = "Enabled", 
    NoUI = false
})

Options.aim_Enabled_KeyPicker:OnClick(function()
    SilentAimSettings.Enabled = not SilentAimSettings.Enabled
    Toggles.aim_Enabled.Value = SilentAimSettings.Enabled
    Toggles.aim_Enabled:SetValue(SilentAimSettings.Enabled)
    mouse_box.Visible = SilentAimSettings.Enabled
end)

Main:AddToggle("TeamCheck", {Text = "Team Check", Default = SilentAimSettings.TeamCheck}):OnChanged(function()
    SilentAimSettings.TeamCheck = Toggles.TeamCheck.Value
end)

Main:AddToggle("VisibleCheck", {Text = "Visible Check", Default = SilentAimSettings.VisibleCheck}):OnChanged(function()
    SilentAimSettings.VisibleCheck = Toggles.VisibleCheck.Value
end)

Main:AddDropdown("TargetPart", {
    AllowNull = true, 
    Text = "Target Part", 
    Default = SilentAimSettings.TargetPart, 
    Values = {"Head", "HumanoidRootPart", "Random"}
}):OnChanged(function()
    SilentAimSettings.TargetPart = Options.TargetPart.Value
end)

Main:AddDropdown("Method", {
    AllowNull = true, 
    Text = "Silent Aim Method", 
    Default = SilentAimSettings.SilentAimMethod, 
    Values = {
        "Raycast",
        "FindPartOnRay",
        "FindPartOnRayWithWhitelist",
        "FindPartOnRayWithIgnoreList",
        "Mouse.Hit/Target"
    }
}):OnChanged(function()
    SilentAimSettings.SilentAimMethod = Options.Method.Value 
end)

Main:AddSlider('HitChance', {
    Text = 'Hit chance',
    Default = 100,
    Min = 0,
    Max = 100,
    Rounding = 1,
    Compact = false,
}):OnChanged(function()
    SilentAimSettings.HitChance = Options.HitChance.Value
end)

local FieldOfViewBOX = GeneralTab:AddLeftTabbox("Field Of View")
local FOVMain = FieldOfViewBOX:AddTab("Visuals")

FOVMain:AddToggle("Visible", {Text = "Show FOV Circle"}):AddColorPicker("Color", {
    Default = Color3.fromRGB(54, 57, 241)
}):OnChanged(function()
    fov_circle.Visible = Toggles.Visible.Value
    SilentAimSettings.FOVVisible = Toggles.Visible.Value
    fov_circle.Color = Options.Color.Value
end)

FOVMain:AddSlider("Radius", {
    Text = "FOV Circle Radius", 
    Min = 0, 
    Max = 360, 
    Default = 130, 
    Rounding = 0
}):OnChanged(function()
    fov_circle.Radius = Options.Radius.Value
    SilentAimSettings.FOVRadius = Options.Radius.Value
end)

FOVMain:AddToggle("MousePosition", {
    Text = "Show Silent Aim Target"
}):AddColorPicker("MouseVisualizeColor", {
    Default = Color3.fromRGB(54, 57, 241)
}):OnChanged(function()
    mouse_box.Visible = Toggles.MousePosition.Value 
    SilentAimSettings.ShowSilentAimTarget = Toggles.MousePosition.Value 
    mouse_box.Color = Options.MouseVisualizeColor.Value
end)

local MiscellaneousBOX = GeneralTab:AddLeftTabbox("Miscellaneous")
local PredictionTab = MiscellaneousBOX:AddTab("Prediction")

PredictionTab:AddToggle("Prediction", {
    Text = "Mouse.Hit/Target Prediction"
}):OnChanged(function()
    SilentAimSettings.MouseHitPrediction = Toggles.Prediction.Value
end)

PredictionTab:AddSlider("Amount", {
    Text = "Prediction Amount", 
    Min = 0.165, 
    Max = 1, 
    Default = 0.165, 
    Rounding = 3
}):OnChanged(function()
    PredictionAmount = Options.Amount.Value
    SilentAimSettings.MouseHitPredictionAmount = Options.Amount.Value
end)

local CreateConfigurationBOX = GeneralTab:AddRightTabbox("Create Configuration")
local CreateConfigTab = CreateConfigurationBOX:AddTab("Create Configuration")

CreateConfigTab:AddInput("CreateConfigTextBox", {
    Default = "", 
    Numeric = false, 
    Finished = false, 
    Text = "Create Configuration to Create", 
    Tooltip = "Creates a configuration file containing settings you can save and load", 
    Placeholder = "File Name here"
}):OnChanged(function()
    if Options.CreateConfigTextBox.Value and string.len(Options.CreateConfigTextBox.Value) ~= 0 then 
        FileToSave = Options.CreateConfigTextBox.Value
    end
end)

CreateConfigTab:AddButton("Create Configuration File", function()
    if FileToSave ~= "" and FileToSave ~= nil then 
        UpdateFile(FileToSave)
    end
end)

local SaveConfigurationBOX = GeneralTab:AddRightTabbox("Save Configuration")
local SaveConfigTab = SaveConfigurationBOX:AddTab("Save Configuration")

SaveConfigTab:AddDropdown("SaveConfigurationDropdown", {
    AllowNull = true, 
    Values = GetFiles(), 
    Text = "Choose Configuration to Save"
})

SaveConfigTab:AddButton("Save Configuration", function()
    if Options.SaveConfigurationDropdown.Value then 
        UpdateFile(Options.SaveConfigurationDropdown.Value)
    end
end)

local LoadConfigurationBOX = GeneralTab:AddRightTabbox("Load Configuration")
local LoadConfigTab = LoadConfigurationBOX:AddTab("Load Configuration")

LoadConfigTab:AddDropdown("LoadConfigurationDropdown", {
    AllowNull = true, 
    Values = GetFiles(), 
    Text = "Choose Configuration to Load"
})

LoadConfigTab:AddButton("Load Configuration", function()
    if table.find(GetFiles(), Options.LoadConfigurationDropdown.Value) then
        LoadFile(Options.LoadConfigurationDropdown.Value)
        
        Toggles.TeamCheck:SetValue(SilentAimSettings.TeamCheck)
        Toggles.VisibleCheck:SetValue(SilentAimSettings.VisibleCheck)
        Options.TargetPart:SetValue(SilentAimSettings.TargetPart)
        Options.Method:SetValue(SilentAimSettings.SilentAimMethod)
        Toggles.Visible:SetValue(SilentAimSettings.FOVVisible)
        Options.Radius:SetValue(SilentAimSettings.FOVRadius)
        Toggles.MousePosition:SetValue(SilentAimSettings.ShowSilentAimTarget)
        Toggles.Prediction:SetValue(SilentAimSettings.MouseHitPrediction)
        Options.Amount:SetValue(SilentAimSettings.MouseHitPredictionAmount)
        Options.HitChance:SetValue(SilentAimSettings.HitChance)
    end
end)

-- Main loop
task.spawn(function()
    while true do
        if Toggles.aim_Enabled.Value then
            if Toggles.MousePosition.Value then
                local target = getClosestPlayer()
                if target then 
                    local Root = target.Parent.PrimaryPart or target
                    local RootToViewportPoint, IsOnScreen = WorldToViewportPoint(Camera, Root.Position)
                    
                    mouse_box.Visible = IsOnScreen
                    mouse_box.Position = Vector2.new(RootToViewportPoint.X, RootToViewportPoint.Y)
                else 
                    mouse_box.Visible = false 
                    mouse_box.Position = Vector2.new()
                end
            end
            
            if Toggles.Visible.Value then 
                fov_circle.Visible = true
                fov_circle.Position = getMousePosition()
            end
        else
            mouse_box.Visible = false
        end
        
        task.wait(0.03)
    end
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    
    if Toggles.aim_Enabled.Value and self == workspace and not checkcaller() and CalculateChance(SilentAimSettings.HitChance) then
        local HitPart = getClosestPlayer()
        
        if HitPart then
            if Method == "FindPartOnRayWithIgnoreList" and Options.Method.Value == Method then
                if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithIgnoreList) then
                    local A_Ray = Arguments[2]
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)
                    return oldNamecall(unpack(Arguments))
                end
            elseif Method == "FindPartOnRayWithWhitelist" and Options.Method.Value == Method then
                if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithWhitelist) then
                    local A_Ray = Arguments[2]
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)
                    return oldNamecall(unpack(Arguments))
                end
            elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and Options.Method.Value:lower() == Method:lower() then
                if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRay) then
                    local A_Ray = Arguments[2]
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)
                    return oldNamecall(unpack(Arguments))
                end
            elseif Method == "Raycast" and Options.Method.Value == Method then
                if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                    local A_Origin = Arguments[2]
                    Arguments[3] = getDirection(A_Origin, HitPart.Position)
                    return oldNamecall(unpack(Arguments))
                end
            end
        end
    end
    
    return oldNamecall(...)
end))

local oldIndex = nil 
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if Toggles.aim_Enabled.Value and self == Mouse and not checkcaller() and Options.Method.Value == "Mouse.Hit/Target" then
        local HitPart = getClosestPlayer()
        if HitPart then
            if Index == "Target" or Index == "target" then 
                return HitPart
            elseif Index == "Hit" or Index == "hit" then 
                return ((Toggles.Prediction.Value and (HitPart.CFrame + (HitPart.Velocity * PredictionAmount))) or HitPart.CFrame)
            elseif Index == "X" or Index == "x" then 
                return self.X 
            elseif Index == "Y" or Index == "y" then 
                return self.Y 
            elseif Index == "UnitRay" then 
                return Ray.new(self.Origin, (self.Hit - self.Origin).Unit)
            end
        end
    end

    return oldIndex(self, Index)
end))
