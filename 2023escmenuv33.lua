--[[
    YEKU LEGACY CORESCRIPTS LOADER
    RBXMSUITE PACKAGE DOWNLOAD - BUNDLED CORESCRIPTS SOURCES ONLY

    Package source is intentionally unchanged:
        Suite.download("letsafe/something@v1.0.0", "shovel.rbxm")

    Preserves:
      - Bundled CoreScripts from Main.Modules.<Year>.CoreScriptsRoot.
      - Sibling dependency merging without duplicate names.
      - StarterScript as the single startup coordinator.
      - Bundled-only module loading; no downloaded replacement modules.
      - Legacy chat <-> TextChatService bridge.
      - Conditional purchase interception only when the RBXM contains
        a bridge-aware purchase prompt.
      - Debug console with PLAYERS and GUISERVICE tabs.
      - Native CoreGui hiding, except while the native inspect menu is active.
      - Independent loading-screen watchdog and module-failure reporting.

    Does not modify bundled Script or ModuleScript Source properties.
]]--

--==============================================================
-- 01. ENVIRONMENT
--==============================================================

local Environment = type(getgenv) == "function" and getgenv() or _G
local NativeRequire = require

-- Existing CoreScripts loader config (Year / SafeChat), unrelated to the recording bridge.
local LoaderConfig = Environment.YekuSettings
    or Environment.LegacySettings
    or {
        Year = 2019,
        SafeChat = false,
    }

local Year = math.floor(tonumber(LoaderConfig.Year) or 2019)
local PREFIX = "[Yeku CoreScripts]"

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LogService = game:GetService("LogService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")
local ChatService = game:GetService("Chat")

assert(RunService:IsClient(), PREFIX .. " Client only.")
assert(Players.LocalPlayer, PREFIX .. " LocalPlayer unavailable.")

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Forward declarations used by callbacks created before section 03.
local OpenAvatarInspect
local HideNativeCoreUI

--==============================================================
-- 02. DEBUG CONSOLE
--==============================================================

local DebugLines = {
    PLAYERS = {},
    GUISERVICE = {},
}

local MAX_LINES = 2500
local DebugGui
local DebugTextBox
local DebugStatus
local PauseRefresh = false
local RefreshPending = false
local DebugCategory = "PLAYERS"

local function SetStatus(Message)
    if DebugStatus then
        pcall(function()
            DebugStatus.Text = tostring(Message)
        end)
    end
end

local function RefreshDebugText()
    if not DebugTextBox or PauseRefresh then
        return
    end

    pcall(function()
        DebugTextBox.Text = table.concat(
            DebugLines[DebugCategory] or {},
            "\n"
        )
    end)
end

local function AppendLine(Level, Message)
    local Output = os.date("%H:%M:%S")
        .. " [" .. tostring(Level) .. "] "
        .. tostring(Message)

    local Upper = string.upper(tostring(Message))
    local Category

    if Upper:find("[PLAYERS]", 1, true) then
        Category = "PLAYERS"
    elseif Upper:find("[GUISERVICE]", 1, true) then
        Category = "GUISERVICE"
    end

    if not Category then
        return
    end

    local Lines = DebugLines[Category]
    table.insert(Lines, Output)

    while #Lines > MAX_LINES do
        table.remove(Lines, 1)
    end

    if Category == DebugCategory
        and not RefreshPending
        and not PauseRefresh
        and DebugTextBox then

        RefreshPending = true

        task.defer(function()
            RefreshPending = false
            RefreshDebugText()
        end)
    end
end

local function Log(Message)
    local Output = PREFIX .. " " .. tostring(Message)
    AppendLine("INFO", Output)
    print(Output)
end

local function Warn(Message)
    local Output = PREFIX .. " " .. tostring(Message)
    AppendLine("WARNING", Output)
    warn(Output)
end

local function CreateObject(ClassName, Name, Parent, Properties)
    local Object = Instance.new(ClassName)
    Object.Name = Name

    for Property, Value in pairs(Properties or {}) do
        local Success, ErrorMessage = pcall(function()
            Object[Property] = Value
        end)

        if not Success then
            warn(PREFIX .. " Debug UI property " .. Property
                .. " failed: " .. tostring(ErrorMessage))
        end
    end

    Object.Parent = Parent
    return Object
end

local function CreateButton(Name, Caption, X, Width, Parent)
    return CreateObject("TextButton", Name, Parent, {
        Position = UDim2.new(0, X, 1, -40),
        Size = UDim2.new(0, Width, 0, 28),
        BackgroundColor3 = Color3.fromRGB(48, 54, 62),
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Text = Caption,
        TextColor3 = Color3.fromRGB(240, 244, 248),
        TextSize = 13,
    })
end

local function FindClipboard()
    local Names = {
        "setclipboard",
        "toclipboard",
        "set_clipboard",
        "writeclipboard",
    }

    for _, Scope in ipairs({Environment, _G}) do
        if type(Scope) == "table" then
            for _, Name in ipairs(Names) do
                local Success, Candidate = pcall(function()
                    return Scope[Name]
                end)

                if Success and type(Candidate) == "function" then
                    return Candidate, Name
                end
            end
        end
    end

    return nil
end

local function CreateDebugConsole()
    local Old = CoreGui:FindFirstChild("YekuDebugConsole")
    if Old then
        Old:Destroy()
    end

    DebugGui = CreateObject("ScreenGui", "YekuDebugConsole", CoreGui, {
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
        Enabled = true,
    })

    local Panel = CreateObject("Frame", "Panel", DebugGui, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 820, 0, 560),
        BackgroundColor3 = Color3.fromRGB(21, 24, 29),
        BorderSizePixel = 0,
        Active = true,
    })

    CreateObject("UICorner", "Corner", Panel, {
        CornerRadius = UDim.new(0, 6),
    })

    CreateObject("TextLabel", "Title", Panel, {
        Position = UDim2.new(0, 12, 0, 5),
        Size = UDim2.new(1, -24, 0, 30),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        Text = "YEKU DEBUG  |  PLAYERS / GUISERVICE  |  F8 TO HIDE / SHOW",
        TextColor3 = Color3.fromRGB(140, 225, 160),
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
    })

    DebugTextBox = CreateObject("TextBox", "Output", Panel, {
        Position = UDim2.new(0, 12, 0, 40),
        Size = UDim2.new(1, -24, 1, -88),
        BackgroundColor3 = Color3.fromRGB(11, 13, 16),
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        MultiLine = true,
        TextEditable = true,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(225, 231, 237),
        Text = "Collecting Players / GuiService diagnostics...",
    })

    CreateObject("UICorner", "OutputCorner", DebugTextBox, {
        CornerRadius = UDim.new(0, 4),
    })

    local PlayersButton = CreateButton("PlayersMode", "PLAYERS", 12, 88, Panel)
    local GuiServiceButton = CreateButton("GuiServiceMode", "GUISERVICE", 106, 110, Panel)
    local InspectButton = CreateButton("InspectTest", "TEST INSPECT", 222, 112, Panel)
    local CopyButton = CreateButton("CopyAll", "COPY VIEW", 340, 92, Panel)
    local RefreshButton = CreateButton("Refresh", "REFRESH", 438, 82, Panel)
    local ClearButton = CreateButton("Clear", "CLEAR", 526, 65, Panel)
    local HideButton = CreateButton("Hide", "HIDE", 597, 60, Panel)

    DebugStatus = CreateObject("TextLabel", "Status", Panel, {
        Position = UDim2.new(0, 12, 1, -68),
        Size = UDim2.new(1, -24, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        Text = "Ready",
        TextColor3 = Color3.fromRGB(190, 200, 210),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    })

    PlayersButton.MouseButton1Click:Connect(function()
        DebugCategory = "PLAYERS"
        PauseRefresh = false
        RefreshDebugText()
        SetStatus("Showing Players diagnostics only.")
    end)

    GuiServiceButton.MouseButton1Click:Connect(function()
        DebugCategory = "GUISERVICE"
        PauseRefresh = false
        RefreshDebugText()
        SetStatus("Showing GuiService diagnostics only.")
    end)

    InspectButton.MouseButton1Click:Connect(function()
        local Target

        for _, Player in ipairs(Players:GetPlayers()) do
            if Player ~= Players.LocalPlayer then
                Target = Player
                break
            end
        end

        if not Target then
            Log("[GUISERVICE] TEST INSPECT skipped: no other player is present.")
            SetStatus("Inspect test needs another player.")
            return
        end

        Log("[GUISERVICE] TEST INSPECT target="
            .. Target.Name .. " userId=" .. tostring(Target.UserId))

        if type(OpenAvatarInspect) ~= "function" then
            Warn("[GUISERVICE] Inspect handler has not initialized.")
            SetStatus("Inspect handler unavailable.")
            return
        end

        local Success, ErrorMessage = OpenAvatarInspect(Target.UserId)

        if Success then
            SetStatus("Inspect request sent; check GUI diagnostics.")
        else
            Warn("[GUISERVICE] Inspect test failed: " .. tostring(ErrorMessage))
            SetStatus("Inspect request failed; see GuiService tab.")
        end
    end)

    CopyButton.MouseButton1Click:Connect(function()
        local Content = table.concat(DebugLines[DebugCategory] or {}, "\n")
        local ClipboardFunction, ClipboardName = FindClipboard()

        if ClipboardFunction then
            local Success, ErrorMessage = pcall(ClipboardFunction, Content)

            if Success then
                SetStatus("Copied " .. tostring(#Content)
                    .. " chars using " .. ClipboardName)
                return
            end

            SetStatus("Clipboard failed: " .. tostring(ErrorMessage))
        end

        PauseRefresh = true

        pcall(function()
            DebugTextBox.Text = Content
            DebugTextBox:CaptureFocus()
            DebugTextBox.SelectionStart = 1
            DebugTextBox.CursorPosition = #Content
        end)

        SetStatus("Select all and press Ctrl+C or Cmd+C.")
    end)

    RefreshButton.MouseButton1Click:Connect(function()
        PauseRefresh = false
        RefreshDebugText()
        SetStatus("Refreshed.")
    end)

    ClearButton.MouseButton1Click:Connect(function()
        table.clear(DebugLines[DebugCategory])
        PauseRefresh = false
        RefreshDebugText()
        SetStatus("Cleared " .. DebugCategory .. " log.")
    end)

    HideButton.MouseButton1Click:Connect(function()
        DebugGui.Enabled = false
    end)

    UserInputService.InputBegan:Connect(function(Input, Processed)
        if not Processed and Input.KeyCode == Enum.KeyCode.F8 then
            DebugGui.Enabled = not DebugGui.Enabled
        end
    end)

    RefreshDebugText()
end

local UIOK, UIError = pcall(CreateDebugConsole)
if not UIOK then
    warn(PREFIX .. " Could not create debug console: " .. tostring(UIError))
end

pcall(function()
    LogService.MessageOut:Connect(function(Message, MessageType)
        local Output = tostring(Message)

        if Output:sub(1, #PREFIX) == PREFIX then
            return
        end

        local Lower = string.lower(Output)

        if Lower:find("guiservice", 1, true)
            or Lower:find("inspectplayerfromuserid", 1, true)
            or Lower:find("avatarinspect", 1, true) then

            AppendLine("ROBLOX " .. tostring(MessageType),
                "[GUISERVICE] " .. Output)

        elseif Lower:find("playerlist", 1, true)
            or Lower:find("players", 1, true) then

            AppendLine("ROBLOX " .. tostring(MessageType),
                "[PLAYERS] " .. Output)
        end
    end)
end)

--==============================================================
-- 03. DIAGNOSTICS AND NATIVE UI VISIBILITY
--==============================================================

local function Section(Name)
    Log("")
    Log(string.rep("=", 58))
    Log(Name)
    Log(string.rep("=", 58))
end

local function Traceback(Message)
    local Output = tostring(Message)

    if debug and type(debug.traceback) == "function" then
        local Success, Result = pcall(debug.traceback, Output, 2)

        if Success and type(Result) == "string" then
            return Result
        end
    end

    return Output
end

local function ProtectedCall(Label, Callback)
    Log("[BEGIN] " .. Label)

    local Success, Results = xpcall(function()
        return table.pack(Callback())
    end, Traceback)

    if not Success then
        Warn("[FAILED] " .. Label)
        Warn(tostring(Results))
        return false, nil
    end

    Log("[SUCCESS] " .. Label)
    return true, table.unpack(Results, 1, Results.n)
end

local function CountDescendants(Root)
    return Root and #Root:GetDescendants() or 0
end

local function DescribeChildren(Parent)
    if not Parent then
        return "<nil>"
    end

    local Names = {}

    for _, Child in ipairs(Parent:GetChildren()) do
        table.insert(Names, Child.Name .. " [" .. Child.ClassName .. "]")
    end

    table.sort(Names)

    return #Names == 0 and "<no children>" or table.concat(Names, ", ")
end

local function DumpTree(Root, MaxDepth, MaxEntries)
    if not Root then
        return
    end

    MaxDepth = MaxDepth or 4
    MaxEntries = MaxEntries or 120

    Log("TREE: " .. Root:GetFullName())

    local Count = 0
    local Truncated = false

    local function Walk(Parent, Depth)
        for _, Child in ipairs(Parent:GetChildren()) do
            if Count >= MaxEntries then
                Truncated = true
                return
            end

            Count = Count + 1

            Log(string.rep("  ", Depth + 1)
                .. Child.Name .. " [" .. Child.ClassName .. "]")

            if Depth < MaxDepth then
                Walk(Child, Depth + 1)
            end

            if Truncated then
                return
            end
        end
    end

    Walk(Root, 0)

    if Truncated then
        Log("Tree truncated at " .. tostring(MaxEntries) .. " entries.")
    end
end

local function DebugInstance(Label, Object)
    Log("---- " .. Label .. " ----")

    if not Object then
        Warn(Label .. " is nil.")
        return
    end

    Log("Name: " .. Object.Name)
    Log("Class: " .. Object.ClassName)
    Log("Path: " .. Object:GetFullName())
    Log("Descendants: " .. tostring(CountDescendants(Object)))
    Log("Children: " .. DescribeChildren(Object))
end

local function DebugModule(Module, Label)
    DebugInstance(Label, Module)

    if not Module or not Module:IsA("ModuleScript") then
        return
    end

    local Success, Source = pcall(function()
        return Module.Source
    end)

    if not Success then
        Warn("[SOURCE READ FAILED] " .. Module.Name .. ": " .. tostring(Source))
        return
    end

    Log("Source length: " .. tostring(#Source))
    Log("Source first line: " .. tostring(Source:match("([^\r\n]*)")))
end

local function NormalizeName(Name)
    return tostring(Name):gsub("%.lua$", "")
end

local function FindChild(Parent, Name)
    if not Parent then
        return nil
    end

    local Direct = Parent:FindFirstChild(Name)

    if Direct then
        return Direct
    end

    local Wanted = NormalizeName(Name)

    for _, Child in ipairs(Parent:GetChildren()) do
        if NormalizeName(Child.Name) == Wanted then
            return Child
        end
    end

    return nil
end

local function FindModuleRecursive(Root, Name)
    if not Root then
        return nil
    end

    local Wanted = NormalizeName(Name)

    if Root:IsA("ModuleScript") and NormalizeName(Root.Name) == Wanted then
        return Root
    end

    for _, Child in ipairs(Root:GetDescendants()) do
        if Child:IsA("ModuleScript") and NormalizeName(Child.Name) == Wanted then
            return Child
        end
    end

    return nil
end

-- Inspect state is deliberately separate from the other CoreGui visibility
-- handling. During inspection the native RobloxGui root cannot remain disabled.
local NativeHideLogged = setmetatable({}, {__mode = "k"})
local NativeInspectRequested = false
local InspectWatchRunning = false

-- Records visibility/enabled states while the inspect menu is being isolated.
local InspectSavedStates = setmetatable({}, {__mode = "k"})

local function SaveGuiState(Object)
    if InspectSavedStates[Object] then
        return
    end

    if Object:IsA("LayerCollector") then
        local Success, Value = pcall(function()
            return Object.Enabled
        end)

        if Success then
            InspectSavedStates[Object] = {
                Property = "Enabled",
                Value = Value,
            }
        end

    elseif Object:IsA("GuiObject") then
        local Success, Value = pcall(function()
            return Object.Visible
        end)

        if Success then
            InspectSavedStates[Object] = {
                Property = "Visible",
                Value = Value,
            }
        end
    end
end

local function RestoreInspectGuiStates()
    for Object, State in pairs(InspectSavedStates) do
        pcall(function()
            Object[State.Property] = State.Value
        end)

        InspectSavedStates[Object] = nil
    end
end

local function IsInspectNamed(Object)
    local Name = string.lower(tostring(Object.Name))

    return Name == "inspect"
        or Name:find("avatarinspect", 1, true) ~= nil
        or Name:find("inspectmenu", 1, true) ~= nil
        or Name:find("inspectgui", 1, true) ~= nil
        or Name:find("inspectplayer", 1, true) ~= nil
end

local function FindInspectSurface(Root)
    if not Root then
        return nil
    end

    for _, Object in ipairs(Root:GetDescendants()) do
        if IsInspectNamed(Object)
            and (Object:IsA("LayerCollector") or Object:IsA("GuiObject")) then

            return Object
        end
    end

    return nil
end

local function IsActuallyVisible(Object)
    local Current = Object

    while Current do
        if Current:IsA("GuiObject") then
            local Success, Visible = pcall(function()
                return Current.Visible
            end)

            if Success and not Visible then
                return false
            end

        elseif Current:IsA("LayerCollector") then
            local Success, Enabled = pcall(function()
                return Current.Enabled
            end)

            if Success and not Enabled then
                return false
            end
        end

        if Current == CoreGui then
            break
        end

        Current = Current.Parent
    end

    return true
end

local function RestrictNativeGuiToInspect(NativeRoot, InspectSurface)
    if not NativeRoot or not NativeRoot:IsA("LayerCollector") then
        return
    end

    pcall(function()
        NativeRoot.Enabled = true
    end)

    local Keep = {}

    if InspectSurface then
        local Current = InspectSurface

        while Current and Current ~= CoreGui do
            Keep[Current] = true

            if Current == NativeRoot then
                break
            end

            Current = Current.Parent
        end

        for _, Descendant in ipairs(InspectSurface:GetDescendants()) do
            Keep[Descendant] = true
        end
    end

    -- Do not hide the inspect surface or its ancestors. Hide unrelated native
    -- GuiObjects / ScreenGuis so enabling the host root does not expose all
    -- native UI at once. Previous states are restored after the menu closes.
    for _, Descendant in ipairs(NativeRoot:GetDescendants()) do
        if Keep[Descendant] then
            if Descendant:IsA("LayerCollector") then
                SaveGuiState(Descendant)
                pcall(function()
                    Descendant.Enabled = true
                end)

            elseif Descendant:IsA("GuiObject") then
                SaveGuiState(Descendant)
                pcall(function()
                    Descendant.Visible = true
                end)
            end

        elseif Descendant:IsA("LayerCollector") or Descendant:IsA("GuiObject") then
            SaveGuiState(Descendant)

            pcall(function()
                if Descendant:IsA("LayerCollector") then
                    Descendant.Enabled = false
                else
                    Descendant.Visible = false
                end
            end)
        end
    end
end

local function TryHideGuiObject(Object, Label)
    if not Object then
        return false
    end

    local Success = false

    if Object:IsA("LayerCollector") then
        Success = pcall(function()
            Object.Enabled = false
        end)

    elseif Object:IsA("GuiObject") then
        Success = pcall(function()
            Object.Visible = false
        end)

    else
        return false
    end

    if Success then
        if not NativeHideLogged[Object] then
            NativeHideLogged[Object] = true
            Log("Native GUI disabled: " .. Label .. " [" .. Object.ClassName .. "]")
        end

    elseif not NativeHideLogged[Object] then
        NativeHideLogged[Object] = true
        Warn("Could not disable native GUI: " .. Label .. " [" .. Object.ClassName .. "]")
    end

    return Success
end

HideNativeCoreUI = function()
    local OurRoot = CoreGui:FindFirstChild("NewRobloxGui")
    local UseNativePlayerList = OurRoot and OurRoot:GetAttribute("UseNativePlayerList") == true
    local NativeRobloxGui = CoreGui:FindFirstChild("RobloxGui")

    if NativeRobloxGui and NativeRobloxGui.Name ~= "NewRobloxGui" then
        if NativeInspectRequested then
            -- Keep the host root available until the inspect UI is created.
            if NativeRobloxGui:IsA("LayerCollector") then
                pcall(function()
                    NativeRobloxGui.Enabled = true
                end)
            end

            local Surface = FindInspectSurface(NativeRobloxGui)

            if Surface then
                RestrictNativeGuiToInspect(NativeRobloxGui, Surface)
            end
        elseif UseNativePlayerList then
            -- This one topbar variant deliberately uses the native PlayerList.
            -- Keep RobloxGui enabled only so that list can render, while hiding
            -- every unrelated native GUI object/screen.
            if NativeRobloxGui:IsA("LayerCollector") then
                pcall(function() NativeRobloxGui.Enabled = true end)
            end
            local function belongsToPlayerList(Object)
                local Current = Object
                while Current and Current ~= NativeRobloxGui do
                    if string.lower(Current.Name):find("playerlist", 1, true) then
                        return true
                    end
                    Current = Current.Parent
                end
                return false
            end
            local function containsPlayerList(Object)
                for _, Child in ipairs(Object:GetDescendants()) do
                    if string.lower(Child.Name):find("playerlist", 1, true) then
                        return true
                    end
                end
                return false
            end
            for _, Descendant in ipairs(NativeRobloxGui:GetDescendants()) do
                if Descendant:IsA("LayerCollector") or Descendant:IsA("GuiObject") then
                    if belongsToPlayerList(Descendant) or containsPlayerList(Descendant) then
                        -- Keep the PlayerList branch and the ancestors required to
                        -- render it; unrelated siblings are still hidden individually.
                        if Descendant:IsA("LayerCollector") then
                            pcall(function() Descendant.Enabled = true end)
                        else
                            pcall(function() Descendant.Visible = true end)
                        end
                    else
                        TryHideGuiObject(Descendant, "CoreGui.RobloxGui." .. Descendant.Name)
                    end
                end
            end
        else
            TryHideGuiObject(NativeRobloxGui, "CoreGui.RobloxGui")

            for _, Descendant in ipairs(NativeRobloxGui:GetDescendants()) do
                if Descendant:IsA("ScreenGui")
                    and Descendant.Name ~= "NewRobloxGui" then

                    TryHideGuiObject(
                        Descendant,
                        "CoreGui.RobloxGui." .. Descendant.Name
                    )
                end
            end
        end
    end

    local TopBarRoot = CoreGui:FindFirstChild("TopBarApp")

    if not TopBarRoot then
        TopBarRoot = CoreGui:FindFirstChild("TopBarApp", true)
    end

    if TopBarRoot then
        for _, Descendant in ipairs(TopBarRoot:GetDescendants()) do
            if Descendant:IsA("LayerCollector") then
                TryHideGuiObject(
                    Descendant,
                    "TopBarApp." .. Descendant:GetFullName()
                )

            elseif Descendant:IsA("GuiObject")
                and Descendant.Name == "TopBarApp" then

                TryHideGuiObject(
                    Descendant,
                    "TopBarApp." .. Descendant:GetFullName()
                )
            end
        end

        if TopBarRoot:IsA("LayerCollector") or TopBarRoot:IsA("GuiObject") then
            TryHideGuiObject(TopBarRoot, "TopBarApp")
        end
    end

    local RequestedNativeRoots = {
        experiencechat = true,
        playerlist = true,
    }

    for _, Descendant in ipairs(CoreGui:GetDescendants()) do
        if not (OurRoot and Descendant:IsDescendantOf(OurRoot))
            and (Descendant:IsA("LayerCollector") or Descendant:IsA("GuiObject")) then

            local DescendantName = string.lower(Descendant.Name)
            if RequestedNativeRoots[DescendantName] then
                if UseNativePlayerList and DescendantName == "playerlist" then
                    -- Undo an earlier hide if this Topbar starts after the loader.
                    if Descendant:IsA("LayerCollector") then
                        pcall(function() Descendant.Enabled = true end)
                    elseif Descendant:IsA("GuiObject") then
                        pcall(function() Descendant.Visible = true end)
                    end
                else
                    TryHideGuiObject(
                        Descendant,
                        "CoreGui." .. Descendant:GetFullName()
                    )
                end
            end
        end
    end
end

-- Opens native Avatar Inspect Menu while temporarily protecting its UI from
-- HideNativeCoreUI. The menu is located by inspecting actual GUI descendants;
-- a successful method call alone is not reported as proof it opened.
OpenAvatarInspect = function(UserId)
    UserId = tonumber(UserId)

    if not UserId or UserId <= 0 then
        Warn("[GUISERVICE] Invalid inspect userId: " .. tostring(UserId))
        return false, "Invalid user ID"
    end

    if NativeInspectRequested then
        Warn("[GUISERVICE] A previous inspect request is still active.")
        return false, "Previous inspect request still active"
    end

    NativeInspectRequested = true

    local NativeRobloxGui = CoreGui:FindFirstChild("RobloxGui")

    if NativeRobloxGui and NativeRobloxGui:IsA("LayerCollector") then
        local EnableSuccess, EnableError = pcall(function()
            NativeRobloxGui.Enabled = true
        end)

        Log("[GUISERVICE] Native RobloxGui enabled="
            .. tostring(EnableSuccess)
            .. (EnableSuccess and "" or " error=" .. tostring(EnableError)))
    else
        Log("[GUISERVICE] Native RobloxGui root not found as a LayerCollector.")
    end

    local EnableMenuSuccess, EnableMenuError = pcall(function()
        GuiService:SetInspectMenuEnabled(true)
    end)

    Log("[GUISERVICE] SetInspectMenuEnabled success="
        .. tostring(EnableMenuSuccess)
        .. (EnableMenuSuccess and "" or " error=" .. tostring(EnableMenuError)))

    local EnabledReadSuccess, InspectEnabled = pcall(function()
        return GuiService:GetInspectMenuEnabled()
    end)

    Log("[GUISERVICE] GetInspectMenuEnabled success="
        .. tostring(EnabledReadSuccess)
        .. " value=" .. tostring(InspectEnabled))

    -- Clear saved stale visibility state from any interrupted previous request.
    RestoreInspectGuiStates()

    local CallSuccess, CallError = pcall(function()
        GuiService:InspectPlayerFromUserId(UserId)
    end)

    Log("[GUISERVICE] InspectPlayerFromUserId userId="
        .. tostring(UserId)
        .. " callSuccess=" .. tostring(CallSuccess)
        .. (CallSuccess and "" or " error=" .. tostring(CallError)))

    if not CallSuccess then
        NativeInspectRequested = false
        RestoreInspectGuiStates()
        pcall(HideNativeCoreUI)
        return false, CallError
    end

    if not InspectWatchRunning then
        InspectWatchRunning = true

        task.spawn(function()
            local SurfaceFound = false
            local Surface
            local StartedAt = os.clock()
            local NotVisibleSince

            while NativeInspectRequested do
                local Root = CoreGui:FindFirstChild("RobloxGui")
                Surface = Root and FindInspectSurface(Root) or nil

                if Surface then
                    SurfaceFound = true

                    if Root then
                        RestrictNativeGuiToInspect(Root, Surface)
                    end

                    local Visible = IsActuallyVisible(Surface)

                    if Visible then
                        NotVisibleSince = nil
                    else
                        NotVisibleSince = NotVisibleSince or os.clock()

                        if os.clock() - NotVisibleSince >= 0.8 then
                            break
                        end
                    end

                elseif not SurfaceFound and os.clock() - StartedAt >= 5 then
                    Warn("[GUISERVICE] No inspect-named GUI appeared within 5 seconds.")
                    break
                end

                if SurfaceFound and os.clock() - StartedAt >= 30 then
                    Warn("[GUISERVICE] Inspect watchdog reached 30 seconds.")
                    break
                end

                task.wait(0.15)
            end

            RestoreInspectGuiStates()
            NativeInspectRequested = false
            InspectWatchRunning = false

            pcall(HideNativeCoreUI)

            if SurfaceFound then
                Log("[GUISERVICE] Inspect UI visibility monitoring ended.")
            else
                Warn("[GUISERVICE] Inspect method returned, but no visible inspect UI was detected.")
            end
        end)
    end

    return true
end

-- Initial hide and continuous retry. Inspect requests are treated specially
-- inside HideNativeCoreUI, so this loop no longer blindly hides the inspect UI.
HideNativeCoreUI()

CoreGui.ChildAdded:Connect(function(Child)
    local Name = string.lower(Child.Name)

    if Child.Name == "RobloxGui"
        or Child.Name == "TopBarApp"
        or Name == "experiencechat"
        or Name == "playerlist" then

        task.defer(HideNativeCoreUI)
    end
end)

CoreGui.DescendantAdded:Connect(function(Child)
    local Name = string.lower(Child.Name)

    if Child.Name == "TopBarApp"
        or Child.Name == "RobloxGui"
        or Name == "experiencechat"
        or Name == "playerlist"
        or Name:find("avatarinspect", 1, true)
        or Name:find("inspectmenu", 1, true) then

        task.defer(HideNativeCoreUI)
    end
end)

task.spawn(function()
    while true do
        pcall(HideNativeCoreUI)
        task.wait(1)
    end
end)

-- Initial diagnostics.
local function RunInitialPlayerDiagnostics()
    Log("[PLAYERS] LocalPlayer=" .. tostring(Players.LocalPlayer and Players.LocalPlayer.Name)
        .. " userId=" .. tostring(Players.LocalPlayer and Players.LocalPlayer.UserId))

    local CurrentPlayers = Players:GetPlayers()
    Log("[PLAYERS] GetPlayers count=" .. tostring(#CurrentPlayers))

    for Index, Player in ipairs(CurrentPlayers) do
        local Success, DisplayName = pcall(function()
            return Player.DisplayName
        end)

        Log("[PLAYERS] #" .. Index
            .. " name=" .. tostring(Player.Name)
            .. " userId=" .. tostring(Player.UserId)
            .. " displayName=" .. tostring(Success and DisplayName or "<read failed>")
            .. " parent=" .. tostring(Player.Parent))
    end

    Log("[PLAYERS] PlayerAdded/PlayerRemoving diagnostics connected.")
end

local function RunInitialGuiServiceDiagnostics()
    Log("[GUISERVICE] service=" .. tostring(GuiService)
        .. " class=" .. tostring(GuiService and GuiService.ClassName))

    for _, MethodName in ipairs({
        "InspectPlayerFromUserId",
        "SetInspectMenuEnabled",
        "GetInspectMenuEnabled",
        "CloseInspectMenu",
        "GetGuiInset",
        "GetScreenResolution",
    }) do
        local Success, Member = pcall(function()
            return GuiService[MethodName]
        end)

        Log("[GUISERVICE] method " .. MethodName
            .. " exists/readable="
            .. tostring(Success and type(Member) == "function")
            .. " memberType=" .. tostring(Success and type(Member) or "read-error")
            .. (Success and "" or (" error=" .. tostring(Member))))
    end

    local EnabledSuccess, EnabledValue = pcall(function()
        return GuiService:GetInspectMenuEnabled()
    end)

    Log("[GUISERVICE] inspect-menu enabled read success="
        .. tostring(EnabledSuccess)
        .. " value=" .. tostring(EnabledValue))

    local InsetSuccess, TopLeft, BottomRight = pcall(function()
        return GuiService:GetGuiInset()
    end)

    Log("[GUISERVICE] GetGuiInset success=" .. tostring(InsetSuccess)
        .. " topLeft=" .. tostring(TopLeft)
        .. " bottomRight=" .. tostring(BottomRight))

    local ResolutionSuccess, Resolution = pcall(function()
        return GuiService:GetScreenResolution()
    end)

    Log("[GUISERVICE] GetScreenResolution success="
        .. tostring(ResolutionSuccess)
        .. " value=" .. tostring(Resolution))

    Log("[GUISERVICE] Inspect menu is not called automatically; use TEST INSPECT.")
end

pcall(RunInitialPlayerDiagnostics)
pcall(RunInitialGuiServiceDiagnostics)

Players.PlayerAdded:Connect(function(Player)
    Log("[PLAYERS] PlayerAdded name=" .. tostring(Player.Name)
        .. " userId=" .. tostring(Player.UserId))
end)

Players.PlayerRemoving:Connect(function(Player)
    Log("[PLAYERS] PlayerRemoving name=" .. tostring(Player.Name)
        .. " userId=" .. tostring(Player.UserId))
end)

--==============================================================
-- 04. RECORDING / SCREENSHOT EVENTS
--==============================================================

do
    Section("RECORDING / SCREENSHOT EVENTS")

    -- UI contract: Topbar.lua and Record.lua send only local-executor command
    -- RemoteEvents: RecordSomething:FireServer("start" | "stop" | ...).
    -- The loader explicitly registers VideoRecording SetCore/GetCore adapters.
    -- SetCore does NOT call itself recursively: its adapter taps native F12 once,
    -- while GetCore returns the state observed from GameSettings' native signal.
    -- Status events are emitted only from an observed native state transition
    -- (or as a same-state acknowledgement when the actual state is already known).

    if type(Environment.__YekuRecordBridgeCleanup) == "function" then
        pcall(Environment.__YekuRecordBridgeCleanup)
    end

    local Connections = {}
    local RemoteActions = {}
    local BridgeAlive = true
    local PendingRequest = nil
    local RequestGeneration = 0
    local NativeSignalObservedAt = 0

    local Registry = Environment.__YekuVideoRecordingCore
    if type(Registry) ~= "table" then
        Registry = {}
        Environment.__YekuVideoRecordingCore = Registry
    end

    local OldRegistrationPresent = Registry.SetCoreRegistered == true
        or Registry.GetCoreRegistered == true
    local OldContract = Registry.Contract

    -- A prior Yeku revision used Registry.State as a pretend recording state.
    -- Do not trust it when upgrading that contract: only the current native
    -- signal (or a genuine pre-existing Core value read before registration)
    -- can establish the state.
    if OldRegistrationPresent and OldContract ~= "YekuVideoRecordingCore-F12Adapter-v3" then
        Registry.ObservedState = nil
        Registry.State = nil
        Warn("Upgrading an older VideoRecording Core adapter; previous cached state discarded until native state is observed.")
    end
    if type(Registry.ObservedState) ~= "boolean" then
        Registry.ObservedState = nil
    end
    Registry.State = Registry.ObservedState
    Registry.Contract = "YekuVideoRecordingCore-F12Adapter-v3"
    Registry.SetCoreDispatchSerial = tonumber(Registry.SetCoreDispatchSerial) or 0
    Registry.HeartbeatGeneration = tonumber(Registry.HeartbeatGeneration) or 0
    Registry.HeartbeatRunning = false
    Registry.SetRequest = nil
    Registry.GetRequest = nil

    local function FindOrReplaceRemoteEvent(Name)
        local Event = ReplicatedStorage:FindFirstChild(Name)
        if Event and not Event:IsA("RemoteEvent") then
            Warn("ReplicatedStorage." .. Name .. " was " .. Event.ClassName
                .. "; replacing it with the required client command RemoteEvent.")
            Event:Destroy()
            Event = nil
        end
        if not Event then
            Event = Instance.new("RemoteEvent")
            Event.Name = Name
            Event.Parent = ReplicatedStorage
        end
        return Event
    end

    local function FindOrReplaceStatusEvent(Name)
        local Event = ReplicatedStorage:FindFirstChild(Name)
        if Event and not Event:IsA("BindableEvent") then
            Warn("ReplicatedStorage." .. Name .. " was " .. Event.ClassName
                .. "; replacing it with a client-local BindableEvent status output.")
            Event:Destroy()
            Event = nil
        end
        if not Event then
            Event = Instance.new("BindableEvent")
            Event.Name = Name
            Event.Parent = ReplicatedStorage
        end
        return Event
    end

    local RecordSomething = FindOrReplaceRemoteEvent("RecordSomething")
    local ScreenshotEvent = FindOrReplaceRemoteEvent("ScreenshotEvent")
    local StatusEvents = {
        RecordingStart = FindOrReplaceStatusEvent("RecordingStart"),
        RecordingStop = FindOrReplaceStatusEvent("RecordingStop"),
        RecordingEnd = FindOrReplaceStatusEvent("RecordingEnd"),
        OnGoingRecording = FindOrReplaceStatusEvent("OnGoingRecording"),
        RecordingContinue = FindOrReplaceStatusEvent("RecordingContinue"),
        RecordingResume = FindOrReplaceStatusEvent("RecordingResume"),
        RecordingPause = FindOrReplaceStatusEvent("RecordingPause"),
        RecordingChanged = FindOrReplaceStatusEvent("RecordingChanged"),
    }

    local function FireStatus(Name, ...)
        local Event = StatusEvents[Name]
        if not Event or not Event.Parent or not Event:IsA("BindableEvent") then
            Event = FindOrReplaceStatusEvent(Name)
            StatusEvents[Name] = Event
        end
        local Arguments = table.pack(...)
        local OK, ErrorMessage = pcall(function()
            Event:Fire(table.unpack(Arguments, 1, Arguments.n))
        end)
        if not OK then
            Warn(Name .. ":Fire failed: " .. tostring(ErrorMessage))
            return false
        end
        return true
    end

    local function FireStateAcknowledgement(Value, Source, Action)
        if Value then
            FireStatus("RecordingStart", true, Source)
        else
            FireStatus("RecordingStop", false, Source)
            FireStatus("RecordingEnd", false, Source)
        end
        if Action == "continue" then
            FireStatus("RecordingContinue", Value)
        elseif Action == "resume" then
            FireStatus("RecordingResume", Value)
        elseif Action == "pause" then
            FireStatus("RecordingPause", Value)
        end
    end

    local function StartOngoingHeartbeat()
        if Registry.HeartbeatRunning then
            return
        end
        Registry.HeartbeatRunning = true
        Registry.HeartbeatGeneration += 1
        local Generation = Registry.HeartbeatGeneration
        task.spawn(function()
            while BridgeAlive
                and Registry.ObservedState == true
                and Registry.HeartbeatGeneration == Generation do
                FireStatus("OnGoingRecording", true, os.clock())
                task.wait(0.12)
            end
            if Registry.HeartbeatGeneration == Generation then
                Registry.HeartbeatRunning = false
            end
        end)
    end

    local function PublishObservedState(Value, Source)
        if type(Value) ~= "boolean" then
            return false
        end

        local PreviousValue = Registry.ObservedState
        Registry.ObservedState = Value
        Registry.State = Value
        NativeSignalObservedAt = os.clock()

        if PreviousValue ~= Value then
            FireStatus("RecordingChanged", Value, PreviousValue, Source)
            if Value then
                FireStatus("RecordingStart", true, Source)
            else
                -- The native event has confirmed a false state, even if this
                -- loader joined mid-session and did not observe the old true.
                FireStatus("RecordingStop", false, Source)
                FireStatus("RecordingEnd", false, Source)
            end
        end

        if Value then
            StartOngoingHeartbeat()
        else
            Registry.HeartbeatGeneration += 1
            Registry.HeartbeatRunning = false
        end

        local Request = PendingRequest
        if Request then
            if Request.Target == Value then
                PendingRequest = nil
                RequestGeneration += 1
                if PreviousValue == Value then
                    -- No actual transition occurred, but the desired state is
                    -- already observed; acknowledge that existing truth.
                    FireStateAcknowledgement(Value, "AlreadyObserved", Request.Action)
                elseif Request.Action == "continue" then
                    FireStatus("RecordingContinue", true)
                elseif Request.Action == "resume" then
                    FireStatus("RecordingResume", true)
                elseif Request.Action == "pause" then
                    FireStatus("RecordingPause", false)
                end
                Log("[RECORD BRIDGE] " .. tostring(Request.Action)
                    .. " confirmed by native state signal: " .. tostring(Value))
            else
                PendingRequest = nil
                RequestGeneration += 1
                Warn("[RECORD BRIDGE] Native state became " .. tostring(Value)
                    .. " but request wanted " .. tostring(Request.Target)
                    .. "; UI follows actual state and no second F12 tap was sent.")
            end
        end
        return true
    end

    -- GetCore is checked BEFORE Yeku registers its own callback. This can seed
    -- an already-running native recorder on clients that still expose the key.
    -- Never use a prior Yeku state-only callback as proof of real capture state.
    if not OldRegistrationPresent then
        local SeedOK, SeedValue = pcall(function()
            return StarterGui:GetCore("VideoRecording")
        end)
        if SeedOK and type(SeedValue) == "boolean" then
            Registry.ObservedState = SeedValue
            Registry.State = SeedValue
            Log("Seeded recording state from pre-registration GetCore('VideoRecording')="
                .. tostring(SeedValue))
        else
            Log("Pre-registration GetCore('VideoRecording') is unavailable; waiting for native state signal.")
        end
    end

    -- Current Roblox builds removed GameSettings.VideoRecording. Its
    -- VideoRecordingChangeRequest event remains the event signal used here.
    local GameSettingsService
    local GameSettingsOK, GameSettingsError = pcall(function()
        GameSettingsService = settings():GetService("GameSettings")
    end)
    if not GameSettingsOK or not GameSettingsService then
        local UserSettingsOK, UserSettingsObject = pcall(function()
            return UserSettings()
        end)
        if UserSettingsOK and UserSettingsObject then
            local FallbackOK, FallbackService = pcall(function()
                return UserSettingsObject.GameSettings
            end)
            if FallbackOK and FallbackService then
                GameSettingsService = FallbackService
                GameSettingsOK = true
                GameSettingsError = nil
            end
        end
    end

    local function FindKeytap()
        local DirectCandidate
        pcall(function() DirectCandidate = keytap end)
        if type(DirectCandidate) == "function" then
            return DirectCandidate
        end
        for _, Scope in ipairs({Environment, _G}) do
            if type(Scope) == "table" then
                local OK, Candidate = pcall(function()
                    return Scope.keytap
                end)
                if OK and type(Candidate) == "function" then
                    return Candidate
                end
            end
        end
        return nil
    end

    local function TapNativeF12()
        local Keytap = FindKeytap()
        if not Keytap then
            Warn("Executor keytap is unavailable; cannot request native F12. No recording status will be fabricated.")
            return false
        end

        local KeyCandidates = {Enum.KeyCode.F12, "F12", 0x7B}
        local LastError
        for _, Key in ipairs(KeyCandidates) do
            local OK, Result = pcall(Keytap, Key)
            if OK and Result ~= false then
                Log("[RECORD BRIDGE] Sent one native F12 keytap through executor.")
                return true
            end
            LastError = Result
        end

        Warn("Executor keytap could not send F12: " .. tostring(LastError))
        return false
    end

    local function RequestNativeRecording(TargetValue, Action, Source)
        if type(TargetValue) ~= "boolean" then
            error("VideoRecording expects a boolean", 2)
        end

        Action = string.lower(tostring(Action or (TargetValue and "start" or "stop")))
        Source = tostring(Source or "VideoRecording.SetCore")

        if Registry.ObservedState == TargetValue then
            FireStateAcknowledgement(TargetValue, "AlreadyObserved", Action)
            Log("[RECORD BRIDGE] " .. Action .. " already matches the observed native state.")
            return true
        end

        if PendingRequest then
            if PendingRequest.Target == TargetValue then
                Log("[RECORD BRIDGE] Coalesced duplicate " .. Action .. " request while awaiting native confirmation.")
                return true
            end
            Warn("[RECORD BRIDGE] Opposite recording request rejected while another native transition is pending.")
            return false
        end

        RequestGeneration += 1
        local Generation = RequestGeneration
        PendingRequest = {
            Target = TargetValue,
            Action = Action,
            Source = Source,
            Generation = Generation,
            StartedAt = os.clock(),
        }

        if not TapNativeF12() then
            if PendingRequest and PendingRequest.Generation == Generation then
                PendingRequest = nil
            end
            return false
        end

        task.spawn(function()
            local Deadline = os.clock() + 2.5
            while BridgeAlive and RequestGeneration == Generation
                and PendingRequest and PendingRequest.Generation == Generation
                and os.clock() < Deadline do
                task.wait(0.05)
            end

            if PendingRequest and PendingRequest.Generation == Generation then
                PendingRequest = nil
                RequestGeneration += 1
                Warn("[RECORD BRIDGE] Native F12 was sent, but no VideoRecordingChangeRequest confirmation arrived. No false RecordingStart/RecordingEnd event was fired.")
            end
        end)
        return true
    end

    Registry.NextSetCoreAction = nil
    Registry.LastSetCoreAccepted = false
    Registry.SetRequest = function(Value, Source)
        if type(Value) ~= "boolean" then
            error("VideoRecording SetCore expects a boolean", 2)
        end
        Registry.SetCoreDispatchSerial += 1
        local Action = Registry.NextSetCoreAction
        Registry.NextSetCoreAction = nil
        Action = Action or (Value and "start" or "stop")
        Registry.LastSetCoreAccepted = RequestNativeRecording(
            Value,
            Action,
            Source or "VideoRecording.SetCore"
        ) == true
        return Registry.LastSetCoreAccepted
    end

    Registry.GetRequest = function()
        -- Keep this a boolean for Core callers. It reflects the latest native
        -- state event, never the fact that a request or keytap was issued.
        return Registry.ObservedState == true
    end

    -- The registered closures intentionally dereference the current shared
    -- registry instead of capturing this injection's local state. That permits
    -- clean reinjection without installing chains of stale callbacks.
    Registry.Set = function(Value, Source)
        return Registry.SetRequest(Value, Source)
    end
    Registry.Get = function()
        return Registry.GetRequest()
    end

    local RegisteredSet, RegisterSetError = pcall(function()
        StarterGui:RegisterSetCore("VideoRecording", function(Value)
            local Current = Environment.__YekuVideoRecordingCore
            if type(Current) ~= "table" or type(Current.SetRequest) ~= "function" then
                error("VideoRecording SetCore adapter is not ready", 2)
            end
            return Current.SetRequest(Value, "RegisteredSetCore")
        end)
    end)
    if RegisteredSet then
        Registry.SetCoreRegistered = true
        Log("Registered StarterGui:RegisterSetCore('VideoRecording').")
    elseif Registry.SetCoreRegistered == true then
        Warn("RegisterSetCore('VideoRecording') could not be re-registered: "
            .. tostring(RegisterSetError) .. ". Keeping the existing Yeku registration, whose closure uses the refreshed shared registry.")
    else
        Registry.SetCoreRegistered = false
        Warn("RegisterSetCore('VideoRecording') failed: " .. tostring(RegisterSetError))
    end

    local RegisteredGet, RegisterGetError = pcall(function()
        StarterGui:RegisterGetCore("VideoRecording", function()
            local Current = Environment.__YekuVideoRecordingCore
            if type(Current) ~= "table" or type(Current.GetRequest) ~= "function" then
                error("VideoRecording GetCore adapter is not ready", 2)
            end
            return Current.GetRequest()
        end)
    end)
    if RegisteredGet then
        Registry.GetCoreRegistered = true
        Log("Registered StarterGui:RegisterGetCore('VideoRecording').")
    elseif Registry.GetCoreRegistered == true then
        Warn("RegisterGetCore('VideoRecording') could not be re-registered: "
            .. tostring(RegisterGetError) .. ". Keeping the existing Yeku registration, whose closure uses the refreshed shared registry.")
    else
        Registry.GetCoreRegistered = false
        Warn("RegisterGetCore('VideoRecording') failed: " .. tostring(RegisterGetError))
    end

    -- The RemoteEvent contract remains the only UI command surface. Routing via
    -- SetCore ensures the registered handler is used. If the callback was not
    -- invoked (for example the registration API is unavailable in this client),
    -- wait briefly for a genuine native signal/Core value before using the direct
    -- F12 fallback; this avoids double-toggling a native handler that did work.
    local function RequestThroughSetCore(TargetValue, Action)
        local DispatchBefore = Registry.SetCoreDispatchSerial
        local ObservedBefore = Registry.ObservedState
        Registry.NextSetCoreAction = Action
        local CoreOK, CoreError = pcall(function()
            StarterGui:SetCore("VideoRecording", TargetValue)
        end)

        if Registry.SetCoreDispatchSerial ~= DispatchBefore then
            Log("[RECORD BRIDGE] " .. Action .. " routed through registered VideoRecording SetCore.")
            return Registry.LastSetCoreAccepted == true
        end

        Registry.NextSetCoreAction = nil
        if not CoreOK then
            Warn("SetCore('VideoRecording', " .. tostring(TargetValue) .. ") failed: " .. tostring(CoreError))
        else
            Warn("SetCore('VideoRecording') returned without invoking the Yeku handler; waiting briefly before the F12 fallback.")
        end

        task.spawn(function()
            local Deadline = os.clock() + 0.45
            while BridgeAlive and os.clock() < Deadline do
                if Registry.ObservedState == TargetValue then
                    Log("[RECORD BRIDGE] " .. Action .. " was confirmed by a native event while waiting for SetCore routing.")
                    return
                end
                task.wait(0.05)
            end

            -- If no Yeku SetCore callback ran, a still-available preexisting
            -- Core handler may have processed the call. Consult GetCore only
            -- when Yeku's own getter was not registered successfully.
            if not Registry.GetCoreRegistered then
                local ReadOK, NativeValue = pcall(function()
                    return StarterGui:GetCore("VideoRecording")
                end)
                if ReadOK and type(NativeValue) == "boolean" and NativeValue == TargetValue then
                    PublishObservedState(NativeValue, "NativeGetCoreConfirmation")
                    Log("[RECORD BRIDGE] Native GetCore confirmed " .. tostring(NativeValue) .. "; skipped F12 fallback.")
                    return
                end
            end

            if not BridgeAlive or Registry.SetCoreDispatchSerial ~= DispatchBefore then
                return
            end
            if Registry.ObservedState ~= TargetValue then
                Registry.SetRequest(TargetValue, "RemoteEventFallback:" .. Action)
            elseif ObservedBefore ~= Registry.ObservedState then
                Log("[RECORD BRIDGE] State changed natively; skipped fallback keytap.")
            end
        end)
        return true
    end

    local function NormalizeCommand(Command)
        if Command == true then return "start" end
        if Command == false then return "stop" end
        local Action = string.lower(tostring(Command or ""))
        Action = Action:gsub("[%s_]+", "-")
        if Action == "on" or Action == "recording-start" then
            return "start"
        elseif Action == "off" or Action == "end" or Action == "recording-stop"
            or Action == "recording-end" then
            return "stop"
        elseif Action == "recording-toggle" then
            return "toggle"
        end
        return Action
    end

    local function HandleRecordSomething(Command)
        local Action = NormalizeCommand(Command)
        Log("[RECORD BRIDGE] intercepted RecordSomething:FireServer(" .. Action .. ")")

        if Action == "toggle" then
            local Current = Registry.ObservedState
            if type(Current) ~= "boolean" then
                Warn("Cannot resolve toggle because recording state is not observed yet; no action was taken.")
                return false
            end
            local TargetValue = not Current
            return RequestThroughSetCore(TargetValue, TargetValue and "start" or "stop")
        elseif Action == "start" then
            return RequestThroughSetCore(true, "start")
        elseif Action == "stop" then
            return RequestThroughSetCore(false, "stop")
        elseif Action == "continue" then
            return RequestThroughSetCore(true, "continue")
        elseif Action == "resume" then
            return RequestThroughSetCore(true, "resume")
        elseif Action == "pause" then
            return RequestThroughSetCore(false, "pause")
        end

        Warn("Unknown RecordSomething command: " .. Action
            .. "; expected start/stop/continue/resume/pause/toggle.")
        return false
    end

    local function HandleScreenshotRequest()
        task.spawn(function()
            for Attempt = 1, 10 do
                if not BridgeAlive then return end
                local OK, ErrorMessage = pcall(function()
                    StarterGui:SetCore("TakeScreenshot")
                end)
                if OK then
                    Log("Screenshot requested through SetCore('TakeScreenshot').")
                    return
                end
                Log("Screenshot attempt " .. Attempt .. " failed: " .. tostring(ErrorMessage))
                task.wait(0.25)
            end
            Warn("Screenshot request exhausted all attempts.")
        end)
    end

    local function Dispatch(Action, Argument)
        if Action == "record-something" then
            HandleRecordSomething(Argument)
        elseif Action == "screenshot" then
            HandleScreenshotRequest()
        end
    end

    local function MonitorEndpoint(Event, Action)
        if not Event or not Event:IsA("RemoteEvent") then
            Warn("A recording command endpoint is missing or not a RemoteEvent: " .. tostring(Event))
            return
        end
        RemoteActions[Event] = Action
        Log("Monitoring intercepted RemoteEvent:FireServer on " .. Event:GetFullName()
            .. " as " .. Action .. ".")
    end

    MonitorEndpoint(RecordSomething, "record-something")
    MonitorEndpoint(ScreenshotEvent, "screenshot")

    Connections[#Connections + 1] = ReplicatedStorage.ChildAdded:Connect(function(Child)
        if Child.Name == "RecordSomething" then
            RecordSomething = Child
            MonitorEndpoint(RecordSomething, "record-something")
        elseif Child.Name == "ScreenshotEvent" then
            ScreenshotEvent = Child
            MonitorEndpoint(ScreenshotEvent, "screenshot")
        end
    end)

    -- Persistent executor hook: reinjection updates its dispatch table rather
    -- than adding another __namecall hook layer.
    local HookState = Environment.__YekuRecordNamecallHook
    if type(HookState) ~= "table" then
        HookState = {Installed = false, Actions = {}, Dispatch = nil}
        Environment.__YekuRecordNamecallHook = HookState
    end
    HookState.Actions = RemoteActions
    HookState.Dispatch = Dispatch

    if not HookState.Installed then
        if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
            local OldNamecall
            local function Namecall(Self, ...)
                local Method
                pcall(function() Method = getnamecallmethod() end)
                local Current = Environment.__YekuRecordNamecallHook
                if Method == "FireServer" and type(Current) == "table" then
                    local ActionName = Current.Actions and Current.Actions[Self]
                    local Handler = Current.Dispatch
                    if ActionName and type(Handler) == "function" then
                        local Arguments = table.pack(...)
                        local OK, ErrorMessage = pcall(Handler, ActionName, Arguments[1])
                        if not OK then
                            Warn("Intercepted " .. tostring(ActionName) .. " failed: " .. tostring(ErrorMessage))
                        end
                        return nil
                    end
                end
                if type(OldNamecall) == "function" then
                    return OldNamecall(Self, ...)
                end
                return nil
            end
            local Wrapped = Namecall
            if type(newcclosure) == "function" then
                Wrapped = newcclosure(Namecall)
            end
            local HookOK, HookResult = pcall(function()
                OldNamecall = hookmetamethod(game, "__namecall", Wrapped)
            end)
            if HookOK and type(OldNamecall) == "function" then
                HookState.Installed = true
                Log("Persistent local RemoteEvent FireServer interception installed.")
            else
                HookState.Installed = false
                Warn("RemoteEvent FireServer interception failed: " .. tostring(HookResult))
            end
        else
            HookState.Installed = false
            Warn("Executor lacks hookmetamethod/getnamecallmethod; RemoteEvent commands cannot be intercepted locally.")
        end
    else
        Log("Reusing persistent RemoteEvent FireServer interception.")
    end

    -- Native F12/menu toggles are not replayed. Their actual transition is
    -- forwarded from the GameSettings signal and drives status events/GetCore.
    if GameSettingsOK and GameSettingsService then
        local SignalOK, SignalOrError = pcall(function()
            return GameSettingsService.VideoRecordingChangeRequest:Connect(function(Value)
                if type(Value) == "boolean" then
                    Log("[RECORD BRIDGE] native VideoRecordingChangeRequest=" .. tostring(Value))
                    PublishObservedState(Value, "GameSettings.VideoRecordingChangeRequest")
                end
            end)
        end)
        if SignalOK and SignalOrError then
            Connections[#Connections + 1] = SignalOrError
            Log("Connected GameSettings.VideoRecordingChangeRequest for F12/native menu state updates.")
        else
            Warn("Could not connect GameSettings.VideoRecordingChangeRequest: " .. tostring(SignalOrError))
        end
    else
        Warn("GameSettings service unavailable for recording notifications: " .. tostring(GameSettingsError))
    end

    -- Don't respond to native F12 input by issuing another F12 keytap. This
    -- listener only logs key observation; the GameSettings signal is authoritative.
    Connections[#Connections + 1] = UserInputService.InputBegan:Connect(function(Input)
        if Input.KeyCode == Enum.KeyCode.F12 then
            Log("[RECORD BRIDGE] physical F12 observed; waiting for native recording-change signal.")
        end
    end)

    Environment.__YekuRecordBridgeCleanup = function()
        BridgeAlive = false
        RequestGeneration += 1
        Registry.HeartbeatGeneration += 1
        Registry.HeartbeatRunning = false
        PendingRequest = nil
        for _, Connection in ipairs(Connections) do
            pcall(function()
                if typeof(Connection) == "RBXScriptConnection" then
                    Connection:Disconnect()
                end
            end)
        end
        table.clear(Connections)
        table.clear(RemoteActions)
        local Current = Environment.__YekuRecordNamecallHook
        if type(Current) == "table" and Current.Actions == RemoteActions then
            Current.Dispatch = nil
        end
    end

    if Registry.ObservedState == true then
        StartOngoingHeartbeat()
    end

    Log("VideoRecording adapters: RegisterSetCore=" .. tostring(Registry.SetCoreRegistered)
        .. ", RegisterGetCore=" .. tostring(Registry.GetCoreRegistered))
    Log("Command input: ReplicatedStorage.RecordSomething (RemoteEvent intercepted locally).")
    Log("Screenshot input: ReplicatedStorage.ScreenshotEvent (RemoteEvent intercepted locally).")
    Log("SetCore('VideoRecording') invokes the executor's native F12 adapter; GetCore('VideoRecording') returns the last observed native state.")
    Log("Status outputs: RecordingStart, RecordingStop, RecordingEnd, OnGoingRecording, "
        .. "RecordingContinue, RecordingResume, RecordingPause, RecordingChanged.")
end

--==============================================================
-- 05. RBXMSUITE
--==============================================================

Section("RBXMSUITE")

local Suite = Environment.Suite or Environment.rbxmSuite

if not Suite then
    assert(
        type(loadstring) == "function",
        PREFIX .. " loadstring unavailable; cannot initialize RBXMSuite."
    )

    local FetchSuccess, SuiteSource = ProtectedCall(
        "Download RBXMSuite library",
        function()
            return game:HttpGet(
                "https://raw.githubusercontent.com/yeku/forks/refs/heads/main/Scripts/RBXMSuite.luau"
            )
        end
    )

    assert(
        FetchSuccess and type(SuiteSource) == "string" and #SuiteSource > 0,
        PREFIX .. " Could not fetch RBXMSuite library: " .. tostring(SuiteSource)
    )

    local Compile, CompileError = loadstring(SuiteSource)

    assert(
        type(Compile) == "function",
        PREFIX .. " RBXMSuite compile failed: " .. tostring(CompileError)
    )

    local ExecuteSuccess, LoadedSuite = ProtectedCall(
        "Initialize RBXMSuite",
        function()
            return Compile()
        end
    )

    assert(
        ExecuteSuccess and type(LoadedSuite) == "table",
        PREFIX .. " RBXMSuite failed to initialize: " .. tostring(LoadedSuite)
    )

    Suite = LoadedSuite
    Environment.Suite = Suite

    Log("RBXMSuite initialized from its library source.")
else
    Log("Using executor-provided RBXMSuite API.")
end

assert(type(Suite) == "table", PREFIX .. " Suite is not a table.")
assert(type(Suite.download) == "function", PREFIX .. " Suite.download is missing.")
assert(type(Suite.launch) == "function", PREFIX .. " Suite.launch is missing.")
assert(type(Suite.require) == "function", PREFIX .. " Suite.require is missing.")

Log("RBXMSuite API validated.")

--==============================================================
-- 06. DOWNLOAD AND LAUNCH THE EXISTING RBXM
--==============================================================

Section("PACKAGE DOWNLOAD")

local PackagePath

-- KEEP USING shovel.rbxm AND THE EXISTING PACKAGE IDENTIFIER.
local DownloadSuccess, DownloadResult = ProtectedCall(
    "Suite.download(letsafe/something@v1.0.0, knifethingy.rbxm)",
    function()
        return Suite.download("letsafe/something@v1.0.0", "knifethingy.rbxm")
    end
)

assert(
    DownloadSuccess and DownloadResult,
    PREFIX .. " Suite.download failed for shovel.rbxm: " .. tostring(DownloadResult)
)

PackagePath = DownloadResult

Log("Suite.download returned package path: " .. tostring(PackagePath))

local LaunchSuccess, LaunchResult = ProtectedCall("Suite.launch", function()
    return table.pack(Suite.launch(PackagePath, {
        runscripts = false,
        debug = true,
        verbose = true,
        nocirculardeps = true,
    }))
end)

assert(
    LaunchSuccess and LaunchResult,
    PREFIX .. " Suite.launch failed: " .. tostring(LaunchResult)
)

local PackageRoots = {}

for Index = 1, LaunchResult.n do
    local Object = LaunchResult[Index]

    if typeof(Object) == "Instance" then
        table.insert(PackageRoots, Object)
        DebugInstance("Package root " .. Index, Object)
    end
end

assert(#PackageRoots > 0, PREFIX .. " Package returned no instances.")

--==============================================================
-- 07. FIND EXACT SOURCE
--==============================================================

Section("FIND SOURCE")

local MainScript

for _, Root in ipairs(PackageRoots) do
    MainScript = FindModuleRecursive(Root, "Main")

    if MainScript then
        break
    end
end

assert(MainScript, PREFIX .. " Main ModuleScript not found.")

local MainModules = FindChild(MainScript, "Modules")

assert(
    MainModules,
    PREFIX .. " Main.Modules missing. Children: " .. DescribeChildren(MainScript)
)

local YearFolder = FindChild(MainModules, tostring(Year))

assert(
    YearFolder,
    PREFIX .. " Main.Modules." .. tostring(Year)
        .. " missing. Children: " .. DescribeChildren(MainModules)
)

local CoreScriptsRoot = FindChild(YearFolder, "CoreScriptsRoot")

assert(
    CoreScriptsRoot,
    PREFIX .. " Exact source Main.Modules."
        .. tostring(Year) .. ".CoreScriptsRoot missing."
)

DebugInstance("CoreScriptsRoot", CoreScriptsRoot)
DumpTree(CoreScriptsRoot, 3, 120)

--==============================================================
-- 08. CLONE BUNDLED CORESCRIPTS AND MERGE DEPENDENCIES
--==============================================================

Section("COPY CORE SCRIPTS ROOT")

local PreviousRoot = CoreGui:FindFirstChild("NewRobloxGui")

if PreviousRoot then
    PreviousRoot:Destroy()
end

local RobloxGui = Instance.new("ScreenGui")
RobloxGui.Name = "NewRobloxGui"
RobloxGui.ResetOnSpawn = false
RobloxGui.Enabled = true

-- Purchase interception is configured only if a bridge-aware prompt source
-- exists in the RBXM. No source is modified to add bridge code.
local PurchaseRequestBridge
local CoreGuiPurchaseRequestBridge
local PurchasePromptBridgeConfigured = false

local function EnsureBridgeEvent(Parent, Name)
    if not Parent then
        return nil
    end

    local Event = Parent:FindFirstChild(Name)

    if Event then
        if Event:IsA("BindableEvent") then
            return Event
        end

        Warn("Bundled prompt bridge name exists as a non-BindableEvent: "
            .. Event:GetFullName())

        return nil
    end

    Event = Instance.new("BindableEvent")
    Event.Name = Name
    Event.Parent = Parent

    return Event
end

local function ConfigureBundledPurchasePromptBridge(Root)
    local BundledBridgeSourceFound = false
    local Objects = {Root}

    for _, Descendant in ipairs(Root:GetDescendants()) do
        table.insert(Objects, Descendant)
    end

    for _, Object in ipairs(Objects) do
        if Object:IsA("ModuleScript")
            or Object:IsA("LocalScript")
            or Object:IsA("Script") then

            local ReadOK, Source = pcall(function()
                return Object.Source
            end)

            if ReadOK
                and type(Source) == "string"
                and Source:find("YekuPurchasePromptRequest", 1, true) then

                BundledBridgeSourceFound = true

                Log("Bundled purchase bridge source detected: "
                    .. Object:GetFullName())
            end
        end
    end

    if not BundledBridgeSourceFound then
        PurchasePromptBridgeConfigured = false

        Log("No bridge-aware purchase prompt was supplied by the RBXM; "
            .. "native MarketplaceService prompts remain untouched.")

        return false
    end

    PurchaseRequestBridge = EnsureBridgeEvent(Root, "YekuPurchasePromptRequest")
    CoreGuiPurchaseRequestBridge = EnsureBridgeEvent(CoreGui, "YekuPurchasePromptRequest")

    PurchasePromptBridgeConfigured =
        PurchaseRequestBridge ~= nil
        and CoreGuiPurchaseRequestBridge ~= nil

    Log("Bundled purchase bridge configured: "
        .. tostring(PurchasePromptBridgeConfigured))

    return PurchasePromptBridgeConfigured
end

local OriginalArchivable = {}

local function SetTreeArchivable(Root)
    local Objects = {Root}

    for _, Descendant in ipairs(Root:GetDescendants()) do
        table.insert(Objects, Descendant)
    end

    for _, Object in ipairs(Objects) do
        local Success, Value = pcall(function()
            return Object.Archivable
        end)

        if Success then
            OriginalArchivable[Object] = Value

            pcall(function()
                Object.Archivable = true
            end)
        end
    end
end
local function getExecutorEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env
        end
    end

    return _G
end

local ExecutorEnvironment = getExecutorEnvironment()
local OpiumHTTP = ExecutorEnvironment.http

assert(
    type(OpiumHTTP) == "table"
        and type(OpiumHTTP.request) == "function",
    "[YekuFollowBackend] Opiumware http.request is unavailable"
)

local function executorRequest(options)
    return OpiumHTTP.request(options)
end
local function RestoreSourceArchivable()
    for Object, Value in pairs(OriginalArchivable) do
        pcall(function()
            Object.Archivable = Value
        end)
    end
end

local function RestoreCloneArchivable(Source, Clone)
    local Original = OriginalArchivable[Source]

    if Original ~= nil then
        pcall(function()
            Clone.Archivable = Original
        end)
    end

    local SourceChildren = Source:GetChildren()
    local CloneChildren = Clone:GetChildren()
    local Used = {}

    for _, SourceChild in ipairs(SourceChildren) do
        for Index, CloneChild in ipairs(CloneChildren) do
            if not Used[Index]
                and SourceChild.Name == CloneChild.Name
                and SourceChild.ClassName == CloneChild.ClassName then

                Used[Index] = true
                RestoreCloneArchivable(SourceChild, CloneChild)
                break
            end
        end
    end
end

SetTreeArchivable(CoreScriptsRoot)

local SourceChildren = CoreScriptsRoot:GetChildren()
local CopyCount = 0

local CopySuccess, CopyError = ProtectedCall(
    "Clone direct children of CoreScriptsRoot",
    function()
        for Index, SourceChild in ipairs(SourceChildren) do
            local CloneSuccess, Copy = pcall(function()
                return SourceChild:Clone()
            end)

            assert(
                CloneSuccess and Copy,
                "Clone failed for " .. SourceChild:GetFullName()
                    .. ": " .. tostring(Copy)
            )

            Copy.Name = SourceChild.Name
            RestoreCloneArchivable(SourceChild, Copy)
            Copy.Parent = RobloxGui
            CopyCount = CopyCount + 1

            Log("[COPIED " .. Index .. "/" .. #SourceChildren .. "] "
                .. Copy.Name .. " descendants=" .. CountDescendants(Copy))
        end

        return true
    end
)

RestoreSourceArchivable()

assert(CopySuccess, PREFIX .. " Failed to copy the source hierarchy.")

Log("Source direct children: " .. #SourceChildren)
Log("Copied direct children: " .. CopyCount)
Log("Copied descendants: " .. CountDescendants(RobloxGui))

assert(
    CopyCount == #SourceChildren,
    PREFIX .. " Source/copy child counts differ."
)

-- Merge sibling dependencies from Main.Modules.<Year>, preserving the original
-- CoreScriptsRoot copy when a name already exists.
local function MergeYearTree(SourceObject, DestinationParent, SourcePath)
    if SourceObject == CoreScriptsRoot then
        return 0
    end

    local Existing = DestinationParent:FindFirstChild(SourceObject.Name)

    if SourceObject:IsA("Folder")
        and Existing
        and Existing:IsA("Folder") then

        local Added = 0

        for _, Child in ipairs(SourceObject:GetChildren()) do
            Added = Added + MergeYearTree(
                Child,
                Existing,
                SourcePath .. "." .. Child.Name
            )
        end

        return Added
    end

    if Existing then
        if Existing.ClassName ~= SourceObject.ClassName then
            Warn("Year-folder merge conflict at " .. SourcePath
                .. ": keeping existing " .. Existing.ClassName
                .. ", source is " .. SourceObject.ClassName)
        end

        return 0
    end

    SetTreeArchivable(SourceObject)

    local CloneSuccess, Copy = pcall(function()
        return SourceObject:Clone()
    end)

    if not CloneSuccess or not Copy then
        RestoreSourceArchivable()

        Warn("Could not clone year-folder dependency "
            .. SourcePath .. ": " .. tostring(Copy))

        return 0
    end

    Copy.Name = SourceObject.Name
    RestoreCloneArchivable(SourceObject, Copy)
    RestoreSourceArchivable()
    Copy.Parent = DestinationParent

    Log("[MERGED YEAR DEPENDENCY] " .. SourcePath
        .. " -> " .. Copy:GetFullName())

    return 1 + CountDescendants(Copy)
end

local MergedYearEntries = 0

for _, YearChild in ipairs(YearFolder:GetChildren()) do
    if YearChild ~= CoreScriptsRoot then
        MergedYearEntries = MergedYearEntries + MergeYearTree(
            YearChild,
            RobloxGui,
            "Main.Modules." .. tostring(Year) .. "." .. YearChild.Name
        )
    end
end

Log("Merged sibling dependency instances/descendants: "
    .. tostring(MergedYearEntries))

if not FindChild(RobloxGui, "Libraries")
    and FindChild(RobloxGui, "Libaries") then

    Warn("RBXM contains 'Libaries' but not 'Libraries'. "
        .. "Preserving the bundled hierarchy unchanged.")
end

RobloxGui.Parent = CoreGui

assert(RobloxGui.Parent == CoreGui, PREFIX .. " Could not install NewRobloxGui.")

Log("Installed root: " .. RobloxGui:GetFullName())
Log("Installed children: " .. DescribeChildren(RobloxGui))

local InstalledModules = FindChild(RobloxGui, "Modules")

for _, DependencyName in ipairs({
    "ChatUtil",
    "StyleWidgets",
    "TopbarConstants",
    "ChatSelector",
    "NewChat",
    "BackpackScript",
    "PlayerlistModule",
    "ContextMenuGui",
    "ContextMenuUtil",
    "ContextMenuItems",
    "PlayerCarousel",
    "SelectedCharacterIndicator",
}) do
    local Dependency = InstalledModules
        and FindModuleRecursive(InstalledModules, DependencyName)

    Log("Dependency check " .. DependencyName .. ": "
        .. (Dependency and Dependency:GetFullName() or "MISSING"))
end

local function KeepOurRoot()
    if RobloxGui.Name ~= "NewRobloxGui" then
        RobloxGui.Name = "NewRobloxGui"
    end

    if RobloxGui.Parent ~= CoreGui then
        pcall(function()
            RobloxGui.Parent = CoreGui
        end)
    end

    pcall(HideNativeCoreUI)
end

KeepOurRoot()
ConfigureBundledPurchasePromptBridge(RobloxGui)

--==============================================================
-- 09. LEGACY CHAT <-> TEXTCHATSERVICE BRIDGE
--==============================================================

Section("LEGACY CHAT BRIDGE")

local BridgeFolderName = "YekuLegacyChatBridge"
local BridgeFolder = ReplicatedStorage:FindFirstChild(BridgeFolderName)

if BridgeFolder and not BridgeFolder:IsA("Folder") then
    error(PREFIX .. " ReplicatedStorage." .. BridgeFolderName
        .. " exists but is not a Folder.")
end

if not BridgeFolder then
    BridgeFolder = Instance.new("Folder")
    BridgeFolder.Name = BridgeFolderName
    BridgeFolder.Parent = ReplicatedStorage
end

local BridgeAlreadyRunning =
    BridgeFolder:GetAttribute("YekuBridgeRunning") == true

BridgeFolder:SetAttribute("YekuTextChatBridge", true)
BridgeFolder:SetAttribute("YekuBridgeVersion", "2.1.0")

local function GetOrCreateBridgeObject(ClassName, ObjectName)
    local Object = BridgeFolder:FindFirstChild(ObjectName)

    if Object then
        if not Object:IsA(ClassName) then
            error(PREFIX .. " Bridge object " .. ObjectName
                .. " must be " .. ClassName
                .. ", got " .. Object.ClassName .. ".")
        end

        return Object
    end

    Object = Instance.new(ClassName)
    Object.Name = ObjectName
    Object.Parent = BridgeFolder

    return Object
end

local OnNewMessage = GetOrCreateBridgeObject("BindableEvent", "OnNewMessage")
local OnMessageDoneFiltering = GetOrCreateBridgeObject("BindableEvent", "OnMessageDoneFiltering")
local OnNewSystemMessage = GetOrCreateBridgeObject("BindableEvent", "OnNewSystemMessage")
local OnChannelJoined = GetOrCreateBridgeObject("BindableEvent", "OnChannelJoined")
local OnChannelLeft = GetOrCreateBridgeObject("BindableEvent", "OnChannelLeft")
local OnMuted = GetOrCreateBridgeObject("BindableEvent", "OnMuted")
local OnUnmuted = GetOrCreateBridgeObject("BindableEvent", "OnUnmuted")
local OnMainChannelSet = GetOrCreateBridgeObject("BindableEvent", "OnMainChannelSet")
local SayMessageRequest = GetOrCreateBridgeObject("BindableEvent", "SayMessageRequest")
local GetInitDataRequest = GetOrCreateBridgeObject("BindableFunction", "GetInitDataRequest")

local function TryRequireNamedModule(Root, Name)
    if not Root then
        return nil
    end

    local Candidate = FindModuleRecursive(Root, Name)

    if not Candidate then
        Candidate = Root:FindFirstChild(Name, true)
    end

    if not Candidate or not Candidate:IsA("ModuleScript") then
        return nil
    end

    local Success, Result = pcall(NativeRequire, Candidate)

    if Success and type(Result) == "table" then
        return Result
    end

    return nil
end

local BridgeChatSettings
local BridgeChatConstants
local InstalledGui = CoreGui:FindFirstChild("NewRobloxGui")
local InstalledModulesRoot = InstalledGui and InstalledGui:FindFirstChild("Modules")

if InstalledModulesRoot then
    BridgeChatSettings = TryRequireNamedModule(InstalledModulesRoot, "ChatSettings")
    BridgeChatConstants = TryRequireNamedModule(InstalledModulesRoot, "ChatConstants")
end

if not BridgeChatSettings or not BridgeChatConstants then
    local NativeClientChatModules = ChatService:FindFirstChild("ClientChatModules")

    if NativeClientChatModules then
        BridgeChatSettings = BridgeChatSettings
            or TryRequireNamedModule(NativeClientChatModules, "ChatSettings")

        BridgeChatConstants = BridgeChatConstants
            or TryRequireNamedModule(NativeClientChatModules, "ChatConstants")
    end
end

local BridgeGeneralName =
    (BridgeChatSettings and BridgeChatSettings.GeneralChannelName) or "All"

local BridgeMessageTypeDefault =
    (BridgeChatConstants
        and (BridgeChatConstants.MessageTypeDefault or BridgeChatConstants.MessageTypeSay))
    or "Message"

local BridgeMessageTypeSystem =
    (BridgeChatConstants and BridgeChatConstants.MessageTypeSystem) or "System"

local BridgeKnownChannels = {}
local BridgeNextMessageId = 0

local function GetBridgeChannelsFolder()
    local Folder = TextChatService:FindFirstChild("TextChannels")

    if Folder and Folder:IsA("Folder") then
        return Folder
    end

    return nil
end

local function ListBridgeTextChannels()
    local Result = {}
    local Seen = {}

    local function Add(Item)
        if Item:IsA("TextChannel") and not Seen[Item] then
            Seen[Item] = true
            table.insert(Result, Item)
        end
    end

    local Folder = GetBridgeChannelsFolder()

    if Folder then
        for _, Item in ipairs(Folder:GetChildren()) do
            Add(Item)
        end
    end

    for _, Item in ipairs(TextChatService:GetChildren()) do
        Add(Item)
    end

    table.sort(Result, function(A, B)
        return A.Name < B.Name
    end)

    return Result
end

local function GetBridgeDisplayChannelName(Channel)
    if not Channel then
        return BridgeGeneralName
    end

    if Channel.Name == "RBXGeneral" then
        return BridgeGeneralName
    end

    if Channel.Name == "RBXSystem" then
        return "System"
    end

    local WhisperUserId = Channel.Name:match("^RBXWhisper:(%d+)$")

    if WhisperUserId then
        local WhisperPlayer = Players:GetPlayerByUserId(tonumber(WhisperUserId))

        if WhisperPlayer then
            return "To " .. WhisperPlayer.Name
        end
    end

    return Channel.Name
end

local function FindBridgeGeneralChannel()
    local Channels = ListBridgeTextChannels()

    for _, Channel in ipairs(Channels) do
        if Channel.Name == "RBXGeneral" then
            return Channel
        end
    end

    for _, Channel in ipairs(Channels) do
        if Channel.Name ~= "RBXSystem" then
            return Channel
        end
    end

    return nil
end

local function FindBridgeTextChannel(DisplayName)
    local Channels = ListBridgeTextChannels()

    if not DisplayName
        or DisplayName == ""
        or DisplayName == BridgeGeneralName
        or DisplayName == "All" then

        return FindBridgeGeneralChannel()
    end

    if DisplayName == "System" then
        return FindBridgeGeneralChannel()
    end

    local WhisperTarget = tostring(DisplayName):match("^[Tt]o%s+(.+)$")

    if WhisperTarget then
        for _, Channel in ipairs(Channels) do
            if string.lower(GetBridgeDisplayChannelName(Channel))
                == string.lower(DisplayName) then

                return Channel
            end
        end

        return FindBridgeGeneralChannel(), WhisperTarget
    end

    for _, Channel in ipairs(Channels) do
        if Channel.Name == DisplayName
            or GetBridgeDisplayChannelName(Channel) == DisplayName then

            return Channel
        end
    end

    return FindBridgeGeneralChannel()
end

local function MakeBridgeInitData()
    local Rows = {}
    local Included = {}

    local function AddChannel(Name)
        if Name and Name ~= "" and not Included[string.lower(Name)] then
            Included[string.lower(Name)] = true
            table.insert(Rows, {Name, "", {}, nil})
        end
    end

    AddChannel(BridgeGeneralName)

    for _, Channel in ipairs(ListBridgeTextChannels()) do
        AddChannel(GetBridgeDisplayChannelName(Channel))
    end

    return {
        Channels = Rows,
    }
end

local function EnsureBridgeChannelAnnounced(Channel)
    local DisplayName = GetBridgeDisplayChannelName(Channel)
    local Key = string.lower(DisplayName)

    if not BridgeKnownChannels[Key] then
        BridgeKnownChannels[Key] = true
        OnChannelJoined:Fire(DisplayName, "", {}, nil)
    end

    return DisplayName
end

local function InitialiseBridgeChannels()
    BridgeKnownChannels = {}

    for _, Channel in ipairs(ListBridgeTextChannels()) do
        BridgeKnownChannels[
            string.lower(GetBridgeDisplayChannelName(Channel))
        ] = true
    end

    if not BridgeKnownChannels[string.lower(BridgeGeneralName)] then
        BridgeKnownChannels[string.lower(BridgeGeneralName)] = true
        OnChannelJoined:Fire(BridgeGeneralName, "", {}, nil)
    end

    local Main = FindBridgeGeneralChannel()

    if Main then
        OnMainChannelSet:Fire(GetBridgeDisplayChannelName(Main))
    end
end

GetInitDataRequest.OnInvoke = function()
    return MakeBridgeInitData()
end

local function ConnectBridgeChannelLifecycle()
    local Folder = GetBridgeChannelsFolder()

    if not Folder then
        return
    end

    Folder.ChildAdded:Connect(function(Child)
        if not Child:IsA("TextChannel") then
            return
        end

        task.defer(function()
            local Name = GetBridgeDisplayChannelName(Child)
            local Key = string.lower(Name)

            if not BridgeKnownChannels[Key] then
                BridgeKnownChannels[Key] = true
                OnChannelJoined:Fire(Name, "", {}, nil)
            end
        end)
    end)

    Folder.ChildRemoved:Connect(function(Child)
        if not Child:IsA("TextChannel") then
            return
        end

        local Name = GetBridgeDisplayChannelName(Child)
        local Key = string.lower(Name)

        if Name ~= BridgeGeneralName and BridgeKnownChannels[Key] then
            BridgeKnownChannels[Key] = nil
            OnChannelLeft:Fire(Name)
        end
    end)
end

local function HandleBridgeIncomingMessage(TextChatMessage)
    if not TextChatMessage then
        return
    end

    if TextChatMessage.Status
        and TextChatMessage.Status ~= Enum.TextChatMessageStatus.Success then

        return
    end

    local MessageText = TextChatMessage.Text

    if type(MessageText) ~= "string" or MessageText == "" then
        return
    end

    local TextSource = TextChatMessage.TextSource
    local TextChannel = TextChatMessage.TextChannel
    local ChannelName = EnsureBridgeChannelAnnounced(TextChannel)
    local UserId = TextSource and TextSource.UserId or 0
    local SpeakerName

    if UserId > 0 then
        local Speaker = Players:GetPlayerByUserId(UserId)
        SpeakerName = Speaker and Speaker.Name or nil
    end

    BridgeNextMessageId = BridgeNextMessageId + 1

    local Payload = {
        ID = BridgeNextMessageId,
        FromSpeaker = SpeakerName,
        SpeakerUserId = UserId,
        OriginalChannel = ChannelName,
        IsFiltered = true,
        MessageLength = #MessageText,
        Message = MessageText,
        MessageType = TextSource and BridgeMessageTypeDefault or BridgeMessageTypeSystem,
        Time = os.time(),
        ExtraData = nil,
    }

    if TextSource then
        OnNewMessage:Fire(Payload, ChannelName)
    else
        OnNewSystemMessage:Fire(Payload, ChannelName)
    end
end

if not BridgeAlreadyRunning then
    SayMessageRequest.Event:Connect(function(Message, TargetChannel)
        if type(Message) ~= "string" or Message == "" then
            return
        end

        local Channel, WhisperTarget = FindBridgeTextChannel(TargetChannel)

        if not Channel then
            Warn("[Yeku Chat Bridge] No TextChannel available; legacy message not sent.")
            return
        end

        local OutgoingText = Message

        if WhisperTarget then
            if not OutgoingText:match("^%s*/w%f[%W]")
                and not OutgoingText:match("^%s*/whisper%f[%W]") then

                OutgoingText = "/w " .. WhisperTarget .. " " .. OutgoingText
            end
        end

        local SendOK, SendResult = pcall(function()
            return Channel:SendAsync(OutgoingText)
        end)

        if not SendOK then
            Warn("[Yeku Chat Bridge] TextChannel:SendAsync failed: "
                .. tostring(SendResult))

        elseif SendResult
            and SendResult.Status
            and SendResult.Status ~= Enum.TextChatMessageStatus.Success then

            Warn("[Yeku Chat Bridge] Roblox rejected the message: "
                .. tostring(SendResult.Status))
        end
    end)

    local IncomingOK, IncomingResult = pcall(function()
        return TextChatService.MessageReceived:Connect(HandleBridgeIncomingMessage)
    end)

    if not IncomingOK then
        Warn("[Yeku Chat Bridge] MessageReceived connection failed: "
            .. tostring(IncomingResult))
    end

    InitialiseBridgeChannels()
    ConnectBridgeChannelLifecycle()

    TextChatService.ChildAdded:Connect(function(Child)
        if Child.Name == "TextChannels" and Child:IsA("Folder") then
            ConnectBridgeChannelLifecycle()
            task.defer(InitialiseBridgeChannels)
        end
    end)

    BridgeFolder:SetAttribute("YekuBridgeRunning", true)

    Log("Yeku Legacy Chat <-> TextChatService bridge installed: "
        .. BridgeFolder:GetFullName())

else
    Log("Yeku Legacy Chat <-> TextChatService bridge already running; "
        .. "not duplicating connections.")
end

--==============================================================
-- 10. CONDITIONAL PURCHASE INTERCEPTION
--==============================================================

local function InstallPurchasePromptInterception()
    if type(hookmetamethod) ~= "function"
        or type(getnamecallmethod) ~= "function" then

        Warn("Purchase interception unavailable: hookmetamethod/getnamecallmethod not found.")
        return false
    end

    if not PurchaseRequestBridge
        or not PurchaseRequestBridge:IsA("BindableEvent")
        or not PurchasePromptBridgeConfigured then

        Log("No bundled purchase bridge; purchase calls will pass through.")
        return false
    end

    local OldNamecall

    local function Namecall(Self, ...)
        local Method

        pcall(function()
            Method = getnamecallmethod()
        end)

        if Self == MarketplaceService then
            local Args = table.pack(...)

            if Args[1] == Players.LocalPlayer then
                local Request

                if Method == "PromptPurchase" and Args[2] ~= nil then
                    Request = {
                        Type = "Asset",
                        PromptType = "Purchase",
                        Method = "PromptPurchase",
                        PurchaseType = "Asset",
                        Player = Args[1],
                        AssetId = Args[2],
                        EquipIfPurchased = Args[3] == true,
                        CurrencyType = Args[4],
                    }

                elseif Method == "PromptProductPurchase" and Args[2] ~= nil then
                    Request = {
                        Type = "Product",
                        PromptType = "ProductPurchase",
                        Method = "PromptProductPurchase",
                        PurchaseType = "Product",
                        Player = Args[1],
                        ProductId = Args[2],
                        EquipIfPurchased = Args[3] == true,
                        CurrencyType = Enum.CurrencyType.Robux,
                    }

                elseif Method == "PromptGamePassPurchase" and Args[2] ~= nil then
                    Request = {
                        Type = "GamePass",
                        PromptType = "GamePassPurchase",
                        Method = "PromptGamePassPurchase",
                        PurchaseType = "GamePass",
                        Player = Args[1],
                        GamePassId = Args[2],
                        EquipIfPurchased = false,
                        CurrencyType = Enum.CurrencyType.Default,
                    }
                end

                if Request then
                    local Fired, FireError = pcall(function()
                        PurchaseRequestBridge:Fire(Request)

                        if CoreGuiPurchaseRequestBridge
                            and CoreGuiPurchaseRequestBridge ~= PurchaseRequestBridge then

                            CoreGuiPurchaseRequestBridge:Fire(Request)

                            local AssetId = Request.AssetId
                            local ProductId = Request.ProductId
                            local GamePassId = Request.GamePassId
                            local Equip = Request.EquipIfPurchased == true
                            local Currency = Request.CurrencyType

                            if ProductId ~= nil then
                                CoreGuiPurchaseRequestBridge:Fire(
                                    Request.Player,
                                    nil,
                                    Equip,
                                    Currency,
                                    ProductId,
                                    nil
                                )

                            elseif GamePassId ~= nil then
                                CoreGuiPurchaseRequestBridge:Fire(
                                    Request.Player,
                                    nil,
                                    false,
                                    Currency,
                                    nil,
                                    GamePassId
                                )

                            else
                                CoreGuiPurchaseRequestBridge:Fire(
                                    Request.Player,
                                    AssetId,
                                    Equip,
                                    Currency,
                                    nil,
                                    nil
                                )
                            end
                        end
                    end)

                    if Fired then
                        Log("Intercepted " .. tostring(Method)
                            .. " and forwarded to the legacy purchase bridge.")
                        return nil
                    end

                    Warn("Purchase bridge forwarding failed: " .. tostring(FireError))
                end
            end
        end

        return OldNamecall(Self, ...)
    end

    local Handler = Namecall

    if type(newcclosure) == "function" then
        Handler = newcclosure(Namecall)
    end

    local Success, Result = pcall(function()
        OldNamecall = hookmetamethod(game, "__namecall", Handler)
    end)

    if Success and type(OldNamecall) == "function" then
        Log("MarketplaceService purchase interception installed.")
        return true
    end

    Warn("Failed to install MarketplaceService purchase interception: "
        .. tostring(Result))

    return false
end

--==============================================================
-- 11. GUIINSPECTANDBUY EVENT
--==============================================================
-- The event name/path matches the event this loader creates in ReplicatedStorage.
-- Both the debug button and this event route through OpenAvatarInspect.

local GuiInspectAndBuy = ReplicatedStorage:FindFirstChild("GuiInspectAndBuy")

if GuiInspectAndBuy and not GuiInspectAndBuy:IsA("BindableEvent") then
    Warn("ReplicatedStorage.GuiInspectAndBuy existed with the wrong class; replacing it.")
    GuiInspectAndBuy:Destroy()
    GuiInspectAndBuy = nil
end

if not GuiInspectAndBuy then
    GuiInspectAndBuy = Instance.new("BindableEvent")
    GuiInspectAndBuy.Name = "GuiInspectAndBuy"
    GuiInspectAndBuy.Parent = ReplicatedStorage
end

GuiInspectAndBuy.Event:Connect(function(UserId)
    UserId = tonumber(UserId)

    if not UserId or UserId <= 0 then
        Warn("[GUISERVICE] GuiInspectAndBuy received an invalid user ID.")
        return
    end

    Log("[GUISERVICE] GuiInspectAndBuy received userId=" .. tostring(UserId))

    local Success, ErrorMessage = OpenAvatarInspect(UserId)

    if not Success then
        Warn("[GUISERVICE] GuiInspectAndBuy request failed: "
            .. tostring(ErrorMessage))
    end
end)

Log("[GUISERVICE] ReplicatedStorage.GuiInspectAndBuy ready before StarterScript startup.")

--==============================================================
-- 12. CUSTOM BUNDLED MODULE LOADER
--==============================================================

Section("SINGLE STARTUP PATH")

Log("Skipping Main.Start; copied StarterScript is the sole CoreScripts coordinator.")
KeepOurRoot()

Section("CUSTOM MODULE LOADER")

local NIL_RETURN = {}
local ModuleCache = {}
local ModuleStack = {}
local ModuleFailures = {}
local LoadModule

local function RecordModuleFailure(Path, Message)
    ModuleFailures[Path] = tostring(Message)
end

local function CountModuleFailures()
    local Count = 0

    for _ in pairs(ModuleFailures) do
        Count = Count + 1
    end

    return Count
end

local function ModulePath(Module)
    local Success, Path = pcall(function()
        return Module:GetFullName()
    end)

    return Success and Path or Module.Name
end
--==============================================================
-- YEKU: SUPPRESS MODERN COREGUI NPC BUBBLES
-- Preserve the custom legacy BubbleChat.lua renderer.
--==============================================================

local YekuTextChatService = game:GetService("TextChatService")
local YekuBubbleConfig =
    YekuTextChatService:WaitForChild("BubbleChatConfiguration")

local function SuppressModernBubbles()
    if YekuBubbleConfig.MaxBubbles ~= 0 then
        YekuBubbleConfig.MaxBubbles = 0
    end
end

SuppressModernBubbles()

-- Keep the setting applied if another script changes it.
YekuBubbleConfig:GetPropertyChangedSignal("MaxBubbles"):Connect(
    SuppressModernBubbles
)

print("[Yeku] Modern CoreGui bubble suppression installed")
--==============================================================
-- YEKU: HIDE MODERN TEXTCHAT NPC BUBBLES
-- Keeps the legacy BubbleChat.lua untouched.
--==============================================================

local YekuBubbleTextChat = game:GetService("TextChatService")
local YekuBubblePlayers = game:GetService("Players")

YekuBubbleTextChat.OnBubbleAdded = function(message, adornee)
    -- Ordinary player bubbles have a TextSource; leave them alone.
    if message.TextSource ~= nil then
        return nil
    end

    -- NPC bubbles displayed through TextChatService have an adornee.
    if not adornee then
        return nil
    end

    local model

    if adornee:IsA("Model") then
        model = adornee
    else
        model = adornee:FindFirstAncestorOfClass("Model")
    end

    if not model then
        return nil
    end

    -- Do not treat a player character as an NPC.
    if YekuBubblePlayers:GetPlayerFromCharacter(model) then
        return nil
    end

    local properties = Instance.new("BubbleChatMessageProperties")
    properties.BackgroundTransparency = 1
    properties.TextSize = 0
    properties.TailVisible = false

    return properties
end

print("[Yeku] Modern NPC bubble callback installed")
local function RemoveRBXMSuitePrefix(Source)
    local Prefixes = {
        'local script, require = unpack((...)[',
        'local script, require = unpack(globalMap[',
    }

    local Suffix = '"]);'

    for _, Prefix in ipairs(Prefixes) do
        if Source:sub(1, #Prefix) == Prefix then
            local Ending = Source:find(Suffix, #Prefix + 1, true)

            if not Ending then
                error("Malformed RBXMSuite wrapper.")
            end

            Log("[WRAPPER STRIPPED IN MEMORY]")

            return Source:sub(Ending + #Suffix)
        end
    end

    return Source
end

local function CustomRequire(Target)
    if typeof(Target) == "Instance" and Target:IsA("ModuleScript") then
        return LoadModule(Target)
    end

    return NativeRequire(Target)
end

LoadModule = function(Module)
    assert(
        typeof(Module) == "Instance" and Module:IsA("ModuleScript"),
        "Custom require expected a ModuleScript, got " .. tostring(Module)
    )

    local Cached = ModuleCache[Module]

    if Cached then
        if Cached.State == "loading" then
            local Chain = {}

            for _, StackModule in ipairs(ModuleStack) do
                table.insert(Chain, ModulePath(StackModule))
            end

            table.insert(Chain, ModulePath(Module))

            error(
                "Circular module dependency:\n"
                    .. table.concat(Chain, "\n -> "),
                2
            )
        end

        if Cached.Value == NIL_RETURN then
            return nil
        end

        return Cached.Value
    end

    local Path = ModulePath(Module)
    Log("[MODULE BEGIN] " .. Path)

    local SourceSuccess, Source = pcall(function()
        return Module.Source
    end)

    if not SourceSuccess or type(Source) ~= "string" then
        local UnderNewRoot = false

        pcall(function()
            UnderNewRoot = Module:IsDescendantOf(RobloxGui)
        end)

        if not UnderNewRoot then
            local SuiteSuccess, SuiteResult = pcall(function()
                return Suite.require(Module)
            end)

            if SuiteSuccess then
                ModuleCache[Module] = {
                    State = "loaded",
                    Value = SuiteResult == nil and NIL_RETURN or SuiteResult,
                }

                Log("[MODULE LOADED THROUGH SUITE] " .. Path)
                return SuiteResult
            end
        end

        local ErrorMessage = "Cannot read ModuleScript.Source for " .. Path
            .. "\nSource error: " .. tostring(Source)

        RecordModuleFailure(Path, ErrorMessage)
        error(ErrorMessage, 2)
    end

    local CleanSource = RemoveRBXMSuitePrefix(Source)

    if type(loadstring) ~= "function" then
        RecordModuleFailure(Path, "loadstring unavailable")
        error("loadstring unavailable while loading " .. Path, 2)
    end

    local Executable = "local script, require = ...\n" .. CleanSource
    local CompileSuccess, Chunk, CompileError = pcall(function()
        return loadstring(Executable)
    end)

    if not CompileSuccess or type(Chunk) ~= "function" then
        local ActualCompileError = CompileSuccess and CompileError or Chunk

        Warn("Bundled module compilation failed without modification: "
            .. Path .. ": " .. tostring(ActualCompileError))

        local SuiteFallbackSuccess, SuiteFallbackResult = pcall(function()
            return Suite.require(Module)
        end)

        if SuiteFallbackSuccess then
            ModuleCache[Module] = {
                State = "loaded",
                Value = SuiteFallbackResult == nil and NIL_RETURN or SuiteFallbackResult,
            }

            Log("[MODULE LOADED THROUGH RBXMSUITE FALLBACK] " .. Path)
            return SuiteFallbackResult
        end

        local FailureText = "Compilation failed: " .. tostring(ActualCompileError)
            .. " | RBXMSuite fallback failed: " .. tostring(SuiteFallbackResult)

        RecordModuleFailure(Path, FailureText)
        error("Source compilation failed for " .. Path .. ":\n" .. FailureText, 2)
    end

    ModuleCache[Module] = {
        State = "loading",
        Value = nil,
    }

    table.insert(ModuleStack, Module)

    local ExecutionSuccess, Results = xpcall(function()
        return table.pack(Chunk(Module, CustomRequire))
    end, Traceback)

    table.remove(ModuleStack, #ModuleStack)

    if not ExecutionSuccess then
        ModuleCache[Module] = nil
        RecordModuleFailure(Path, Results)

        Warn("[MODULE EXECUTION FAILED] " .. Path)
        Warn(tostring(Results))

        error("Execution failed for " .. Path .. ":\n" .. tostring(Results), 2)
    end

    local Result = Results[1]

    ModuleCache[Module] = {
        State = "loaded",
        Value = Result == nil and NIL_RETURN or Result,
    }

    Log("[MODULE SUCCESS] " .. Path)

    return Result
end
-- Recording SetCore/GetCore bridge is registered in section 04.

--==============================================================
-- 13. BUNDLED DEPENDENCY VALIDATION
--==============================================================

Section("BUNDLED DEPENDENCY VALIDATION")

local DependencyRoot = FindChild(RobloxGui, "Modules")

for _, DependencyName in ipairs({
    "ChatUtil",
    "StyleWidgets",
    "TopbarConstants",
    "ChatSelector",
    "NewChat",
    "BackpackScript",
    "PlayerlistModule",
    "ContextMenuGui",
    "ContextMenuUtil",
    "ContextMenuItems",
    "PlayerCarousel",
    "SelectedCharacterIndicator",
}) do
    local Dependency = DependencyRoot
        and FindModuleRecursive(DependencyRoot, DependencyName)

    if Dependency then
        Log("Bundled dependency present: " .. DependencyName
            .. " -> " .. Dependency:GetFullName())
    else
        Warn("Bundled dependency missing: " .. DependencyName
            .. " (loader will not fetch or create it)")
    end
end

--==============================================================
-- 14. STARTUP PREFLIGHT
--==============================================================

Section("CUSTOM LOADER PREFLIGHT")

assert(type(LoadModule) == "function", PREFIX .. " Custom loader unavailable.")
assert(type(CustomRequire) == "function", PREFIX .. " Custom require unavailable.")

Log("Custom loader preflight passed. No module source was written.")

--==============================================================
-- 15. VERIFY AND LOAD STARTUP MODULES
--==============================================================

Section("VERIFY STARTUP MODULES")

local CoreScriptsFolder = FindChild(RobloxGui, "CoreScripts")
local ModulesFolder = FindChild(RobloxGui, "Modules")
local LoadingScript = FindChild(RobloxGui, "LoadingScript")
local StarterScript = FindChild(RobloxGui, "StarterScript")

assert(CoreScriptsFolder and CoreScriptsFolder:IsA("Folder"),
    PREFIX .. " CoreScripts folder missing.")

assert(ModulesFolder and ModulesFolder:IsA("Folder"),
    PREFIX .. " Modules folder missing.")

assert(LoadingScript and LoadingScript:IsA("ModuleScript"),
    PREFIX .. " Direct-child LoadingScript ModuleScript missing.")

assert(StarterScript and StarterScript:IsA("ModuleScript"),
    PREFIX .. " Direct-child StarterScript ModuleScript missing.")

assert(LoadingScript.Parent == RobloxGui and StarterScript.Parent == RobloxGui,
    PREFIX .. " Startup modules must remain direct children.")

DebugModule(LoadingScript, "LoadingScript")
DebugModule(StarterScript, "StarterScript")

Section("LOAD LOADING SCRIPT")

local LoadSuccess, LoadResult = ProtectedCall(
    "LoadModule(LoadingScript)",
    function()
        return LoadModule(LoadingScript)
    end
)

local LoadingScriptSucceeded = LoadSuccess
local ActiveLoadingScreen = LoadResult

Log("LoadingScript result: "
    .. (LoadingScriptSucceeded and "SUCCESS" or "FAILED"))

Log("LoadingScript return type: " .. typeof(LoadResult))

KeepOurRoot()

-- Loading-screen cleanup runs independently of StarterScript returning.
local LoadingScreenStopped = false

local function StopActiveLoadingScreen(IsError, Cause)
    if LoadingScreenStopped then
        return true
    end

    if type(ActiveLoadingScreen) ~= "table"
        or type(ActiveLoadingScreen.Stop) ~= "function" then

        Log("Loading screen stop API unavailable; "
            .. "no callable ActiveLoadingScreen.Stop().")

        LoadingScreenStopped = true
        return false
    end

    if Cause then
        Warn("Stopping loading screen independently of startup completion: "
            .. tostring(Cause))
    end

    LoadingScreenStopped = true

    local Success = ProtectedCall("ActiveLoadingScreen:Stop()", function()
        return ActiveLoadingScreen:Stop(IsError == true)
    end)

    return Success
end

if LoadingScriptSucceeded then
    task.delay(15, function()
        if not LoadingScreenStopped then
            StopActiveLoadingScreen(
                true,
                "StarterScript has not returned within 15 seconds; "
                    .. "check for a missing WaitForChild dependency"
            )
        end
    end)
end

Section("LOAD STARTER SCRIPT")

assert(RobloxGui.Parent == CoreGui and RobloxGui:IsA("ScreenGui"),
    PREFIX .. " NewRobloxGui is not a ScreenGui under CoreGui.")

assert(StarterScript.Parent == RobloxGui,
    PREFIX .. " StarterScript is not a direct child.")

local StarterLoadSuccess, StarterLoadResult = ProtectedCall(
    "LoadModule(StarterScript)",
    function()
        return LoadModule(StarterScript)
    end
)

local StarterSucceeded = StarterLoadSuccess
local StarterResult = StarterLoadResult

Log("StarterScript result: "
    .. (StarterSucceeded and "SUCCESS" or "FAILED"))

Log("StarterScript return type: " .. typeof(StarterResult))

if StarterSucceeded and type(StarterResult) == "table" then
    Log("Returned GUI matches: "
        .. tostring(StarterResult.RobloxGui == RobloxGui))

    Log("Returned Modules matches: "
        .. tostring(StarterResult.Modules == FindChild(RobloxGui, "Modules")))

    Log("Disconnect method type: " .. typeof(StarterResult.Disconnect))
end

if not StarterSucceeded then
    Warn("StarterScript failed; inspect MODULE EXECUTION FAILED and its traceback.")
    DumpTree(RobloxGui, 4, 120)
end

KeepOurRoot()

Section("STOP LOADING SCREEN")

if not LoadingScriptSucceeded then
    Log("LoadingScript failed; Stop() skipped.")
else
    StopActiveLoadingScreen(not StarterSucceeded)
end

--==============================================================
-- 16. VERIFY PURCHASE PROMPT SOURCE
--==============================================================

Section("VERIFY PURCHASE PROMPT SCRIPT")

local PurchasePromptModule = FindModuleRecursive(RobloxGui, "PurchasePromptScript2")

if PurchasePromptModule then
    Log("Found legacy purchase prompt module: " .. PurchasePromptModule:GetFullName())

    if not ModuleCache[PurchasePromptModule] then
        local PromptModuleSuccess = ProtectedCall(
            "LoadModule(PurchasePromptScript2)",
            function()
                return LoadModule(PurchasePromptModule)
            end
        )

        if not PromptModuleSuccess then
            Warn("PurchasePromptScript2 module failed to initialize.")
        end
    else
        Log("PurchasePromptScript2 was already loaded by legacy startup.")
    end

else
    local FoundRunnablePurchaseScript = false

    for _, Descendant in ipairs(RobloxGui:GetDescendants()) do
        if (Descendant:IsA("LocalScript") or Descendant:IsA("Script"))
            and string.lower(Descendant.Name):find("purchasepromptscript2", 1, true) then

            FoundRunnablePurchaseScript = true

            Log("Found runnable purchase prompt script: "
                .. Descendant:GetFullName())
        end
    end

    if not FoundRunnablePurchaseScript then
        Warn("No PurchasePromptScript2 instance was found inside NewRobloxGui.")
    end
end

--==============================================================
-- 17. FINAL VERIFICATION
--==============================================================

Section("FINAL VERIFICATION")

KeepOurRoot()

local PurchasePromptHookInstalled = InstallPurchasePromptInterception()

Log("PurchasePrompt bridge configured: "
    .. tostring(PurchasePromptBridgeConfigured))

Log("PurchasePrompt hook installed: "
    .. tostring(PurchasePromptHookInstalled))

if not PurchasePromptBridgeConfigured then
    Log("No bundled purchase bridge was enabled; "
        .. "native MarketplaceService prompt calls remain untouched.")
end

if not PurchasePromptHookInstalled then
    Log("Purchase interception unavailable; original purchase calls remain untouched.")
end

Log("Final root: " .. RobloxGui:GetFullName())
Log("Final class: " .. RobloxGui.ClassName)
Log("Final direct children: " .. DescribeChildren(RobloxGui))
Log("Final descendants: " .. CountDescendants(RobloxGui))

Log("LoadingScript: "
    .. (LoadingScriptSucceeded and "SUCCESS" or "FAILED"))

Log("StarterScript: "
    .. (StarterSucceeded and "SUCCESS" or "FAILED"))

local RecordedModuleFailures = CountModuleFailures()

Log("Recorded module compilation/execution failures: "
    .. tostring(RecordedModuleFailures))

if RecordedModuleFailures > 0 then
    for Path, Reason in pairs(ModuleFailures) do
        Warn("[FAILED MODULE SUMMARY] " .. Path .. " :: " .. tostring(Reason))
    end
end

local OverallSuccess =
    LoadingScriptSucceeded
    and StarterSucceeded
    and RecordedModuleFailures == 0

Log("OVERALL RESULT: "
    .. (
        OverallSuccess
        and "SUCCESS"
        or (
            StarterSucceeded
            and "PARTIAL - REQUIRED OR OPTIONAL MODULES FAILED"
            or "FAILED"
        )
    ))

Log("Yeku Legacy CoreScripts loader finished.")
SetStatus("Finished. Click COPY VIEW to export the selected diagnostic log.")
