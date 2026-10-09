-- Normal build: MicLight icons + native Roblox MuteSelfButton integration.
-- Verbose microphone diagnostics are intentionally disabled to avoid console spam.
CoreGui = game:GetService("CoreGui")
-- Remove a debug panel left behind by an earlier copy of this script.
pcall(function()
	local OldDebugWindow = CoreGui:FindFirstChild("Settings2016VoiceMuteDebugWindow")
	if OldDebugWindow then OldDebugWindow:Destroy() end
end)
ContextActionService = game:GetService("ContextActionService")
UserInputService = game:GetService("UserInputService")
GuiService = game:GetService("GuiService")
StarterGui = game:GetService("StarterGui")
TextChatService = game:GetService("TextChatService")
HttpService = game:GetService("HttpService")
HttpRbxApiService = nil
pcall(function()
	HttpRbxApiService = game:GetService("HttpRbxApiService")
end)

SoundService = game:GetService("SoundService")
Players = game:GetService("Players")
SocialService = game:GetService("SocialService")
VoiceChatService = game:GetService("VoiceChatService")

-- The voice probe confirmed this service is exposed by this client. The
-- earlier Settings2016 branch never assigned VoiceChatInternal, so every
-- mute/unmute path saw nil even though game:GetService succeeds.
VoiceChatInternal = nil
pcall(function()
	VoiceChatInternal = game:GetService("VoiceChatInternal")
end)
if not VoiceChatInternal then
	pcall(function()
		VoiceChatInternal = game:FindService("VoiceChatInternal")
	end)
end
VirtualInputManager = nil
RunService = game:GetService("RunService")

pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

maxSteps = 10
LocalPlayer = Players.LocalPlayer
GameSettings = UserSettings().GameSettings
RenderingSettings = settings().Rendering

Spawn = task.spawn
Wait = task.wait
Insert = table.insert
Clamp = math.clamp
Floor = math.floor

-- ============================================================
-- MOBILE UI SCALE
-- ============================================================
GetMobileUiScale = function()
	if not IsMobile then
		return 1
	end

	local Viewport = Vector2.new(720, 1280)
	Protect = Protect or function(Callback)
		local Success = pcall(Callback)
		return Success
	end

	pcall(function()
		local Camera = workspace.CurrentCamera
		if Camera and Camera.ViewportSize.X > 0 and Camera.ViewportSize.Y > 0 then
			Viewport = Camera.ViewportSize
		end
	end)

	local ShortSide = math.min(Viewport.X, Viewport.Y)
	local LongSide = math.max(Viewport.X, Viewport.Y)
	local IsTabletViewport =
		ShortSide >= 760
		and LongSide > 0
		and (LongSide / ShortSide) <= 1.85

	if IsTabletViewport then
		-- Tablets are scaled once by the menu-wide UIScale below.
		return 1
	end

	local DisplayScale = 1

	-- Roblox's ViewportDisplaySize is a device/display-class signal, not a
	-- raw pixel-density value. Combine it with viewport size so high-density
	-- tablets such as iPads get larger legacy-style UI instead of looking tiny.
	pcall(function()
		if GuiService.ViewportDisplaySize == Enum.DisplaySize.Large then
			DisplayScale = 1.22
		elseif GuiService.ViewportDisplaySize == Enum.DisplaySize.Medium then
			DisplayScale = 1.10
		else
			DisplayScale = 1
		end
	end)

	local ViewportScale = ShortSide / 720
	local Scale = Clamp(ViewportScale * DisplayScale, 0.95, 1.55)


	return Clamp(Scale, 0.95, 1.65)
end

-- ============================================================
-- CONSTANTS
-- ============================================================

SETTINGS_SHIELD_COLOR =
	Color3.new(
		41 / 255,
		41 / 255,
		41 / 255
	)

SETTINGS_SHIELD_TRANSPARENCY = 0.2
SETTINGS_BASE_ZINDEX = 200
HIDE_SELECTOR_ARROWS = false

SETTINGS_INACTIVE_POSITION =
	UDim2.new(
		0,
		0,
		-1,
		-36
	)

SETTINGS_ACTIVE_POSITION =
	UDim2.new(
		0,
		0,
		0,
		0
	)

BUTTON_IMAGE =
	"rbxasset://textures/ui/Settings/MenuBarAssets/MenuButton.png"

BUTTON_SELECTED_IMAGE =
	"rbxasset://textures/ui/Settings/MenuBarAssets/MenuButtonSelected.png"

TAB_BAR_IMAGE =
	"rbxasset://textures/ui/Settings/MenuBarAssets/MenuBackground.png"

TAB_SELECTION_IMAGE =
	"rbxasset://textures/ui/Settings/MenuBarAssets/MenuSelection.png"

DROP_DOWN_IMAGE =
	"rbxasset://textures/ui/Settings/DropDown/DropDown.png"

SLIDER_SELECTED_LEFT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/SelectedBarLeft.png"

SLIDER_SELECTED_RIGHT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/SelectedBarRight.png"

SLIDER_LEFT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/Less.png"

SLIDER_RIGHT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/More.png"

SLIDER_BAR_LEFT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/BarLeft.png"

SLIDER_BAR_RIGHT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/BarRight.png"

PLAYER_LIST_OFFSET = 20
DESCRIPTION_PLACEHOLDER = "Short Description (Optional)"
REPORT_DESCRIPTION_FALLBACK = "Report Reason"
PAGE_TOP_PADDING = 0

KEY_F12 = 0x7B
KEY_PRINT_SCREEN = 0x2C

ABUSE_TYPES_PLAYER = {
	"Swearing",
	"Inappropriate Username",
	"Bullying",
	"Scamming",
	"Dating",
	"Cheating/Exploiting",
	"Personal Question",
	"Offsite Links",
}

ABUSE_TYPES_GAME = {
	"Inappropriate Content",
	"Bad Model or Script",
	"Offsite Link",
}

-- ============================================================
-- PLATFORM
-- ============================================================

IsTouchClient = UserInputService.TouchEnabled
IsMobile = false
IsTablet = false
IsPhone = false

UpdateTabletPlatform = function(Viewport)
	Viewport = Viewport
		or (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize)
		or Vector2.new(1280, 720)

	local Platform = nil
	local PlatformRead = pcall(function()
		Platform = UserInputService:GetPlatform()
	end)

	local PlatformMobile =
		Platform == Enum.Platform.Android
		or Platform == Enum.Platform.IOS

	local PlatformKnown =
		PlatformRead
		and Platform ~= nil
		and not tostring(Platform):lower():find("unknown", 1, true)

	local ShortSide = math.min(Viewport.X, Viewport.Y)
	local LongSide = math.max(Viewport.X, Viewport.Y)
	local TabletViewport =
		ShortSide >= 760
		and LongSide > 0
		and (LongSide / ShortSide) <= 1.85

	-- Touch fallback is used only when Roblox did not provide a usable platform.
	-- This prevents touch-capable desktop clients from entering the phone branch.
	local TouchMobileFallback =
		(not PlatformKnown)
		and UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.MouseEnabled

	IsMobile = PlatformMobile or TouchMobileFallback
	IsTablet = IsMobile and TabletViewport
	-- Full-screen layout changes are phone-only. Tablets keep a capped,
	-- PC-like menu width instead of being expanded edge-to-edge.
	IsPhone = IsMobile and not IsTablet
	return IsTablet
end

-- Resolve this before any mobile/tablet-only page code is constructed.
do
	local InitialViewport = ScreenGui and ScreenGui.AbsoluteSize
	if not InitialViewport or InitialViewport.X <= 0 or InitialViewport.Y <= 0 then
		local Camera = workspace.CurrentCamera
		InitialViewport = (Camera and Camera.ViewportSize) or Vector2.new(1280, 720)
	end
	UpdateTabletPlatform(InitialViewport)
end

-- ============================================================
-- CONFIGURATION
-- ============================================================

HomeButtonEnabled = true
DisplayNameSupport = true
InviteFriends = true
VoiceChatEnabled = false

TOTAL_HUB_WIDTH = 800
PC_SCROLLBAR_RESERVE = 6
PC_RIGHT_EXTENSION = 8
PC_HUBBAR_LEFT_REDUCTION = 0
PC_HOME_EXTRA_GAP = 0
PC_SCROLLBAR_THICKNESS = 12

-- Home button uses the live HubBar height so its geometry cannot drift.
HOME_HEIGHT = 60

-- Slightly wider than its height.
HOME_WIDTH = 60

HUBBAR_HEIGHT = 60
-- The 2016-style phone tab bar is compact; tablet and desktop keep their
-- own heights below.
MOBILE_HUBBAR_HEIGHT = 32
TABLET_HUBBAR_HEIGHT = 48

-- Custom SystemMenuButton offsets.
SYSTEM_MENU_OFFSET_X = 16
SYSTEM_MENU_OFFSET_Y = 4

-- Recorder overlay position relative to SystemMenuButton.
-- X: horizontal offset from the calculated left-of-button position.
-- Y: vertical offset from the SystemMenuButton top.
RECORDER_OFFSET_X = 165
RECORDER_OFFSET_Y = -19

SYSTEM_MENU_ICON = "rbxassetid://136616213304711"
SYSTEM_MENU_ICON_RECT_OFFSET = Vector2.new(135, 86)
SYSTEM_MENU_ICON_RECT_SIZE = Vector2.new(36, 36)
SYSTEM_MENU_SIZE = Vector2.new(32, 32)

-- Mobile ESC menu:
-- 32px SystemMenuButton + 8px gap = Y 40.
MOBILE_MENU_GAP = 8

MOBILE_LAYOUT_GAP = 6

MOBILE_BOTTOM_MARGIN = 12

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================
-- These names are assigned later in the same chunk. They are intentionally
-- not declared as extra locals here because this script already approaches
-- Luau's 200-local-register limit. Runtime closures resolve these names after
-- the later assignments have executed.

-- ============================================================
-- CLEAN OLD INSTANCE
-- ============================================================

if getgenv().Settings2016Data then
	for _, Connection in next,
		(getgenv().Settings2016Data.Connections or {})
	do
		pcall(function()
			Connection:Disconnect()
		end)
	end

	for _, Object in next,
		(getgenv().Settings2016Data.Objects or {})
	do
		pcall(function()
			Object:Destroy()
		end)
	end
end

Data = {
	Connections = {},
	Objects = {},
}

getgenv().Settings2016Data = Data

for _, Object in next, CoreGui:GetChildren() do
	if
		Object.Name == "Settings2016Gui"
		or Object.Name == "Core2016SettingsGui"
	then
		Object:Destroy()
	end
end

-- ============================================================
-- BASIC HELPERS
-- ============================================================

Connect = function(Signal, Callback)
	local Connection = Signal:Connect(Callback)
	Insert(Data.Connections, Connection)
	return Connection
end

Create = function(
	Class: string,
	Properties: {[string]: any}
)
	local Object = Instance.new(Class)

	for Property, Value in next,
		(Properties or {})
	do
		Object[Property] = Value
	end

	return Object
end

Protect = function(Callback)
	local Success = pcall(Callback)
	return Success
end

FadeText = function(
	Label,
	Transparency
)
	Spawn(function()
		local Start = Label.TextTransparency

		for Index = 1, 6 do
			if not Label.Parent then
				return
			end

			Label.TextTransparency =
				Start
				+ (
					(Transparency - Start)
					* (Index / 6)
				)

			Wait()
		end
	end)
end

LerpUDim = function(
	Start,
	Goal,
	Alpha
)
	return UDim.new(
		Start.Scale
			+ (
				(Goal.Scale - Start.Scale)
				* Alpha
			),

		Start.Offset
			+ (
				(Goal.Offset - Start.Offset)
				* Alpha
			)
	)
end

LerpUDim2 = function(
	Start,
	Goal,
	Alpha
)
	return UDim2.new(
		LerpUDim(
			Start.X,
			Goal.X,
			Alpha
		),

		LerpUDim(
			Start.Y,
			Goal.Y,
			Alpha
		)
	)
end

LerpColor = function(
	Start,
	Goal,
	Alpha
)
	return Color3.new(
		Start.R
			+ (
				(Goal.R - Start.R)
				* Alpha
			),

		Start.G
			+ (
				(Goal.G - Start.G)
				* Alpha
			),

		Start.B
			+ (
				(Goal.B - Start.B)
				* Alpha
			)
	)
end

MoveTweens = {}

MoveTo = function(
	Object,
	Position,
	Callback,
	Frames
)
	MoveTweens[Object] =
		(MoveTweens[Object] or 0)
		+ 1

	local Id =
		MoveTweens[Object]

	Spawn(function()

		local Start =
			Object.Position

		Frames =
			Frames
			or 8

		for Index = 1, Frames do

			if
				not Object.Parent
				or MoveTweens[Object] ~= Id
			then
				return
			end

			local Alpha =
				Index / Frames

			Alpha =
				1
				- (
					(1 - Alpha)
					* (1 - Alpha)
				)

			Object.Position =
				LerpUDim2(
					Start,
					Position,
					Alpha
				)

			Wait()
		end

		Object.Position =
			Position

		if
			Callback
			and MoveTweens[Object] == Id
		then
			Callback()
		end

	end)
end

TweenTo = function(
	Object,
	Position,
	Direction,
	Style,
	Time,
	Callback
)
	MoveTweens[Object] =
		(MoveTweens[Object] or 0)
		+ 1

	local Id =
		MoveTweens[Object]

	local Success =
		Protect(function()

			Object:TweenPosition(
				Position,
				Direction,
				Style,
				Time,
				true,
				function()

					if
						MoveTweens[Object] ~= Id
					then
						return
					end

					Object.Position =
						Position

					if Callback then
						Callback()
					end

				end
			)

		end)

	if not Success then
		MoveTo(
			Object,
			Position,
			Callback,
			math.max(
				1,
				Floor(
					(Time or 0.1)
					* 60
				)
			)
		)
	end
end

ColorTweens = {}

ColorTo = function(
	Object,
	Color
)
	ColorTweens[Object] =
		(ColorTweens[Object] or 0)
		+ 1

	local Id =
		ColorTweens[Object]

	Spawn(function()

		local Start =
			Object.BackgroundColor3

		for Index = 1, 5 do

			if
				not Object.Parent
				or ColorTweens[Object] ~= Id
			then
				return
			end

			Object.BackgroundColor3 =
				LerpColor(
					Start,
					Color,
					Index / 5
				)

			Wait()
		end

	end)
end

-- ============================================================
-- SETTINGS HELPERS
-- ============================================================

SetMouseSensitivity = function(Value)

	Protect(function()
		UserSettings().GameSettings.MouseSensitivity =
			Value
	end)

	Protect(function()
		UserInputService.MouseDeltaSensitivity =
			Value
	end)

end

SetMasterVolume = function(Value)

	Protect(function()
		UserSettings().GameSettings.MasterVolume =
			Value
	end)

	Protect(function()
		SoundService.Volume =
			Value
	end)

end

GetSetting = function(
	Object,
	Property,
	Default
)
	local Success, Value =
		pcall(function()
			return Object[Property]
		end)

	if
		Success
		and Value ~= nil
	then
		return Value
	end

	return Default
end

SetSetting = function(
	Object,
	Property,
	Value
)
	local Success = Protect(function()
		Object[Property] = Value
		return true
	end)
	if not Success and sethiddenproperty then
		pcall(function()
			sethiddenproperty(Object, Property, Value)
		end)
	end
	return Success == true
end

GetHiddenOrSetting = function(Object, Property, Default)
	local Value = nil
	if gethiddenproperty then
		Protect(function() Value = gethiddenproperty(Object, Property) end)
	end
	if Value == nil then Value = GetSetting(Object, Property, Default) end
	if Value == nil then return Default end
	return Value
end


-- ============================================================
-- AUDIO OUTPUT / BACKGROUND TRANSPARENCY HELPERS
-- ============================================================

GetOutputDeviceInfo = function()
	local Name = nil
	local Guid = nil

	Protect(function()
		local Returned = {SoundService:GetOutputDevice()}

		local ReadDevice = function(Device)
			if type(Device) ~= "table" then
				return
			end

			Name = Name
				or Device.Name
				or Device.name
				or Device.DisplayName
				or Device.displayName
				or Device.DeviceName
				or Device.deviceName
				or Name

			Guid = Guid
				or Device.Guid
				or Device.guid
				or Device.Id
				or Device.id
				or Device.DeviceGuid
				or Device.deviceGuid
				or Guid
		end

		for _, Value in next, Returned do
			if type(Value) == "table" then
				ReadDevice(Value)
			elseif type(Value) == "string" then
				if not Name then
					Name = Value
				elseif not Guid then
					Guid = Value
				end
			end
		end
	end)

	return Name, Guid
end

GetOutputDeviceOptions = function()
	local Names = {}
	local OutputDeviceMap = {}
	local Seen = {}

	local AddDevice = function(Name, Guid)
		if not Name then
			return
		end

		Name = tostring(Name)
		Guid = tostring(Guid or "")

		if Name == "" then
			return
		end

		local Key = Guid ~= "" and ("guid:" .. Guid) or ("name:" .. Name)
		if Seen[Key] then
			return
		end

		Seen[Key] = true
		Insert(Names, Name)
		OutputDeviceMap[Name] = {
			Name = Name,
			Guid = Guid,
		}
	end

	local ParseDevice = function(Device)
		if type(Device) ~= "table" then
			return
		end

		local Name =
			Device.Name
			or Device.name
			or Device.DisplayName
			or Device.displayName
				or Device.DeviceName
				or Device.deviceName

		local Guid =
			Device.Guid
				or Device.guid
				or Device.Id
				or Device.id
				or Device.DeviceGuid
				or Device.deviceGuid

		if Name then
			AddDevice(Name, Guid)
		end

		for _, Child in next, Device do
			if type(Child) == "table" then
				ParseDevice(Child)
			end
		end
	end

	Protect(function()
		local Returned = {SoundService:GetOutputDevices()}
		local PendingName = nil

		for _, Value in next, Returned do
			if type(Value) == "table" then
				ParseDevice(Value)
			elseif type(Value) == "string" then
				if not PendingName then
					PendingName = Value
				else
					AddDevice(PendingName, Value)
					PendingName = nil
				end
			end
		end

		if PendingName then
			AddDevice(PendingName, "")
		end
	end)

	local CurrentName, CurrentGuid = GetOutputDeviceInfo()
	if CurrentName and CurrentName ~= "" then
		AddDevice(CurrentName, CurrentGuid)
	end

	return Names, OutputDeviceMap, CurrentName, CurrentGuid
end

SetRealOutputDevice = function(Name, Guid)
	local Success = false

	Protect(function()
		SoundService:SetOutputDevice(
			tostring(Name or ""),
			tostring(Guid or "")
		)
		Success = true
	end)

	if not Success then
		return false
	end

	local NewName, NewGuid = GetOutputDeviceInfo()
	if NewGuid and Guid and tostring(NewGuid) == tostring(Guid) then
		return true
	end
	if NewName and Name and tostring(NewName) == tostring(Name) then
		return true
	end

	return false
end

GetPreferredTransparency = function()
	local Value = nil

	Protect(function()
		Value = tonumber(GuiService.PreferredTransparency)
	end)

	if Value == nil then
		Protect(function()
			Value = tonumber(GameSettings.PreferredTransparency)
		end)
	end

	return Clamp(Value or 1, 0, 1)
end

SetPreferredTransparency = function(Value)
	Value = Clamp(tonumber(Value) or 1, 0, 1)

	Protect(function() GuiService.PreferredTransparency = Value end)
	Protect(function() GameSettings.PreferredTransparency = Value end)

	if sethiddenproperty then
		pcall(function() sethiddenproperty(GuiService, "PreferredTransparency", Value) end)
		pcall(function() sethiddenproperty(GameSettings, "PreferredTransparency", Value) end)
	end

	if ApplyPreferredBackgroundTransparency then
		ApplyPreferredBackgroundTransparency(Value)
	end

	-- The transparency preference is for Roblox's own UI. Keep our custom settings shell opaque/stable.
	if Hub then
		Protect(function()
			if Hub.HubBar then Hub.HubBar.BackgroundTransparency = 1 end
			if Hub.HubBarContainer then Hub.HubBarContainer.BackgroundTransparency = 1 end
			if Hub.BottomButtonFrame then Hub.BottomButtonFrame.BackgroundTransparency = 1 end
			if Hub.Shield then Hub.Shield.BackgroundTransparency = SETTINGS_SHIELD_TRANSPARENCY end
		end)
	end

	local ReadBack = GetPreferredTransparency()
	return math.abs(ReadBack - Value) <= 0.001
end

ApplyPreferredBackgroundTransparency = function(Value)
	-- Update Roblox's preference through SetPreferredTransparency, but never modify
	-- the custom 2016 menu shell; this slider must not visually affect the menu.
	return
end

-- ============================================================
-- GUI ROOT
-- ============================================================

ScreenGui =
	Create(
		"ScreenGui",
		{
			Name =
				"Settings2016Gui",

			Parent =
				CoreGui,

			IgnoreGuiInset =
				true,

			ZIndexBehavior =
				Enum.ZIndexBehavior.Sibling,

			DisplayOrder =
				9000,

			Enabled =
				true,
		}
	)

Insert(
	Data.Objects,
	ScreenGui
)

VolumeChangeSound =
	Create(
		"Sound",
		{
			Name =
				"VolumeChangeSound",

			Parent =
				SoundService,

			SoundId =
				"rbxasset://sounds/uuhhh.mp3",

			Volume =
				1,
		}
	)

Insert(
	Data.Objects,
	VolumeChangeSound
)

PlayVolumeChangeSound =
	function()

		Protect(function()

			VolumeChangeSound:Stop()
			VolumeChangeSound:Play()

		end)

	end

-- ============================================================
-- TEXT / BUTTONS
-- ============================================================

MakeText = function(
	Parent,
	Text,
	Size,
	Position
)
	return Create(
		"TextLabel",
		{
			Parent =
				Parent,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			Size =
				Size,

			Position =
				Position
				or UDim2.new(),

			Font =
				Enum.Font.SourceSansBold,

			TextSize =
				20,

			TextColor3 =
				Color3.new(
					1,
					1,
					1
				),

			Text =
				Text,

			TextWrapped =
				true,

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 2,
		}
	)
end

MakeStyledButton = function(
	Name,
	Text,
	Size,
	Clicked,
	SelectedByDefault
)

	local Button =
		Create(
			"ImageButton",
			{
				Name =
					Name,

				Image =
					SelectedByDefault
					and BUTTON_SELECTED_IMAGE
					or BUTTON_IMAGE,

				ScaleType =
					Enum.ScaleType.Slice,

				SliceCenter =
					Rect.new(
						8,
						6,
						46,
						44
					),

				AutoButtonColor =
					false,

				BackgroundTransparency =
					1,

				Size =
					Size,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	local Label =
		Create(
			"TextLabel",
			{
				Name =
					Name
					.. "TextLabel",

				Parent =
					Button,

				BackgroundTransparency =
					1,

				BorderSizePixel =
					0,

				Size =
					UDim2.new(
						1,
						0,
						1,
						-8
					),

				Position =
					UDim2.new(
						0,
						0,
						0,
						0
					),

				Font =
					Enum.Font.SourceSansBold,

				TextSize =
					24,

				TextColor3 =
					Color3.new(
						1,
						1,
						1
					),

				TextXAlignment =
					Enum.TextXAlignment.Center,

				TextYAlignment =
					Enum.TextYAlignment.Center,

				Text =
					Text,

				TextWrapped =
					true,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	Connect(
		Button.MouseEnter,
		function()
			if Button.Active ~= false then
				Button.Image =
					BUTTON_SELECTED_IMAGE
			end
		end
	)

	Connect(
		Button.MouseLeave,
		function()

			if Button.ImageTransparency >= 1 then
				return
			end

			Button.Image =
				SelectedByDefault
				and BUTTON_SELECTED_IMAGE
				or BUTTON_IMAGE

		end
	)

	if Clicked then

		Connect(
			Button.MouseButton1Click,
			Clicked
		)

	end

	return Button, Label
end

-- ============================================================
-- PAGE SYSTEM
-- ============================================================

MakePage = function(Name)

	local Page = {
		Name =
			Name,

		Rows =
			{},

		NextY =
			0,

		Frame =
			Create(
				"Frame",
				{
					Name =
						Name
						.. "Page",

					BackgroundTransparency =
						1,

					BorderSizePixel =
						0,

					Size =
						UDim2.new(
							1,
							0,
							0,
							0
						),

					Visible =
						false,

					ZIndex =
						SETTINGS_BASE_ZINDEX
						+ 1
				})
	}

	function Page:AddRow(Row)

		Row.Parent =
			self.Frame

		Row.Position =
			UDim2.new(
				0,
				0,
				0,
				self.NextY
			)

		Insert(
			self.Rows,
			Row
		)

		self.NextY = self.NextY + math.max(1, Row.Size.Y.Offset)

		self.Frame.Size =
			UDim2.new(
				1,
				0,
				0,
				PAGE_TOP_PADDING
				+ self.NextY
			)

	end

	return Page
end

-- ============================================================
-- HUB
-- ============================================================

Hub = {
	Visible =
		false,

	Pages =
		{},

	MenuStack =
		{},

	CurrentPage =
		nil,

	NativeMenuTarget =
		nil,

	SuppressNativeOpenUntil =
		0,

	PreviousMenuPage =
		nil,

	InInviteMenu =
		false,

	InConfirmation =
		false,
}

ClippingShield =
	Create(
		"Frame",
		{
			Name =
				"SettingsShield",

			Parent =
				ScreenGui,

			Size =
				UDim2.new(
					1,
					0,
					1,
					0
				),

			Position =
				SETTINGS_ACTIVE_POSITION,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			ClipsDescendants =
				true,

			ZIndex =
				SETTINGS_BASE_ZINDEX,
		}
	)

Hub.Shield =
	Create(
		"Frame",
		{
			Name =
				"SettingsShield",

			Parent =
				ClippingShield,

			Size =
				UDim2.new(
					1,
					0,
					1,
					0
				),

			Position =
				SETTINGS_INACTIVE_POSITION,

			BackgroundColor3 =
				SETTINGS_SHIELD_COLOR,

			BackgroundTransparency =
				SETTINGS_SHIELD_TRANSPARENCY,

			BorderSizePixel =
				0,

			Visible =
				false,

			Active =
				true,

			ZIndex =
				SETTINGS_BASE_ZINDEX,
		}
	)


-- ============================================================
-- TABLET-WIDE RESPONSIVE SCALE
-- ============================================================
TabletUiScale = nil
TabletUiScaleObject = nil

GetTabletResponsiveScale = function(Viewport)
	if IsTablet then return 1 end
	if not IsMobile then return 1 end
	Viewport = Viewport or Vector2.new(720, 1280)
	local ShortSide = math.min(Viewport.X, Viewport.Y)
	local LongSide = math.max(Viewport.X, Viewport.Y)
	if ShortSide >= 760 and LongSide > 0 and (LongSide / ShortSide) <= 1.85 then
		return Clamp(ShortSide / 640, 1, 1.45)
	end
	return 1
end

ApplyTabletResponsiveScale = function(Viewport)
	local Scale = GetTabletResponsiveScale(Viewport)
	if not Hub or not Hub.Shield then return Scale end
	if IsMobile and Scale > 1 then
		if not TabletUiScaleObject or not TabletUiScaleObject.Parent then
			TabletUiScaleObject = Create("UIScale", {
				Name = "TabletResponsiveScale",
				Parent = Hub.Shield,
				Scale = Scale,
			})
		else
			TabletUiScaleObject.Scale = Scale
		end
	else
		if TabletUiScaleObject then
			Protect(function() TabletUiScaleObject:Destroy() end)
			TabletUiScaleObject = nil
		end
	end
	TabletUiScale = Scale
	return Scale
end

Hub.Modal =
	Create(
		"TextButton",
		{
			Name =
				"Modal",

			Parent =
				Hub.Shield,

			BackgroundTransparency =
				1,

			Position =
				UDim2.new(
					0,
					0,
					0,
					0
				),

			Size =
				UDim2.new(
					1,
					0,
					1,
					0
				),

			Text =
				"",

			Active =
				true,

			AutoButtonColor =
				false,

			Modal =
				true,

			ZIndex =
				SETTINGS_BASE_ZINDEX,
		}
	)

Hub.MenuContainer = Create("Frame", {
	Name="MenuContainer", Parent=Hub.Shield, BackgroundTransparency=1,
	Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0.95,0,0.95,0),
	AnchorPoint=Vector2.new(0.5,0.5), ZIndex=SETTINGS_BASE_ZINDEX,
})
Hub.MenuAspectRatio = Create("UIAspectRatioConstraint", {Name="MenuAspectRatio", AspectRatio=800/600, AspectType=Enum.AspectType.ScaleWithParentSize, DominantAxis=Enum.DominantAxis.Width, Parent=Hub.MenuContainer})
Hub.MenuListLayout = Create("UIListLayout", {Name="MenuListLayout", FillDirection=Enum.FillDirection.Vertical, VerticalAlignment=Enum.VerticalAlignment.Center, HorizontalAlignment=Enum.HorizontalAlignment.Center, SortOrder=Enum.SortOrder.LayoutOrder, Parent=nil})

Hub.HubBar =
	Create(
		"ImageLabel",
		{
			Name =
				"HubBar",

			Parent =
				Hub.MenuContainer,

			Image =
				TAB_BAR_IMAGE,

			ScaleType =
				Enum.ScaleType.Slice,

			SliceCenter =
				Rect.new(
					4,
					4,
					6,
					6
				),

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			Size =
				UDim2.new(
					0,
					TOTAL_HUB_WIDTH,
					0,
					HUBBAR_HEIGHT
				),

			Position =
				UDim2.new(
					0.5,
					-TOTAL_HUB_WIDTH / 2,
					0.1,
					0
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 1,
		}
	)

Hub.HubBarContainer = Create("ImageLabel", {Name="HubBarContainer", Parent=Hub.HubBar, BackgroundTransparency=1, Image=TAB_BAR_IMAGE, ScaleType=Enum.ScaleType.Slice, SliceCenter=Rect.new(4,4,6,6), Size=UDim2.new(1,-70,1,0), Position=UDim2.new(0,70,0,0), ZIndex=SETTINGS_BASE_ZINDEX+2})
Hub.HubBarContainerLayout = Create("UIListLayout", {Name="UIListLayout", FillDirection=Enum.FillDirection.Horizontal, HorizontalAlignment=Enum.HorizontalAlignment.Center, VerticalAlignment=Enum.VerticalAlignment.Center, SortOrder=Enum.SortOrder.LayoutOrder, Wraps=false, Padding=UDim.new(0,0), Parent=Hub.HubBarContainer})

Hub.PageClipper =
	Create(
		"Frame",
		{
			Name =
				"PageViewClipper",

			Parent =
				Hub.MenuContainer,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			ClipsDescendants =
				true,

			Size =
				UDim2.new(
					0,
					TOTAL_HUB_WIDTH,
					0,
					420
				),

			Position =
				UDim2.new(
					0.5,
					-TOTAL_HUB_WIDTH / 2,
					0.1,
					61
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 1,
		}
	)

Hub.PageView =
	Create(
		"ScrollingFrame",
		{
			Name =
				"PageView",

			Parent =
				Hub.PageClipper,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			Size =
				UDim2.new(
					1,
					0,
					1,
					0
				),

			CanvasSize =
				UDim2.new(
					0,
					0,
					0,
					0
				),

			ScrollBarThickness =
				0,

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 1,
		}
	)

Hub.BottomButtonFrame =
	Create(
		"Frame",
		{
			Name =
				"BottomButtonFrame",

			Parent =
				Hub.MenuContainer,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			Size =
				UDim2.new(
					0,
					TOTAL_HUB_WIDTH,
					0,
					60
				),

			Position =
				UDim2.new(
					0.5,
					-TOTAL_HUB_WIDTH / 2,
					0.9,
					-60
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 1,
		}
	)

-- ============================================================
-- HOME BUTTON
-- ============================================================

CreateHomeButton = function()
	if not HomeButtonEnabled or HomeButton then return end
	HomeButton = Create("ImageButton", {Name="HubBarHomeButton", Parent=Hub.HubBar, BackgroundTransparency=1, Image=TAB_BAR_IMAGE, ScaleType=Enum.ScaleType.Slice, SliceCenter=Rect.new(4,4,6,6), AutoButtonColor=true, Size=UDim2.new(0,60,0,60), Position=UDim2.new(0,0,0,0), ZIndex=SETTINGS_BASE_ZINDEX+4})
	Create("UIAspectRatioConstraint", {Parent=HomeButton, AspectRatio=1, AspectType=Enum.AspectType.FitWithinMaxSize, DominantAxis=Enum.DominantAxis.Height})
	Create("ImageLabel", {Name="HubBarHomeButtonIcon", Parent=HomeButton, BackgroundTransparency=1, Image="rbxasset://textures/ui/Settings/MenuBarIcons/HomeTab.png", ScaleType=Enum.ScaleType.Stretch, Size=UDim2.new(0.7,0,0.7,0), Position=UDim2.new(0.16,0,0.18,0), ZIndex=SETTINGS_BASE_ZINDEX+5})
	Connect(HomeButton.MouseEnter, function() HomeButton.Image="rbxasset://textures/ui/Settings/MenuBarAssets/MenuSelection@2x.png" end)
	Connect(HomeButton.MouseLeave, function() HomeButton.Image=TAB_BAR_IMAGE end)
	Connect(HomeButton.MouseButton1Click, function() if HomeButtonEnabled and LeavePage and Hub.Visible then PushPage(LeavePage) end end)
end

CreateHomeButton()
ApplyPreferredBackgroundTransparency(GetPreferredTransparency())

PositionHomeButton = function()
	if not HomeButtonEnabled or not HomeButton then return end
	HomeButton.Parent=Hub.HubBar
	HomeButton.Size=UDim2.new(0,Hub.HubBar.Size.Y.Offset,0,Hub.HubBar.Size.Y.Offset)
	HomeButton.Position=UDim2.new(0,0,0,0)
end

-- ============================================================
-- RESIZE
-- ============================================================

ResizeHub = nil

ResizeHub = function()

	local Viewport =
		ScreenGui.AbsoluteSize

	if
		Viewport.X <= 0
		or Viewport.Y <= 0
	then

		local Camera =
			workspace.CurrentCamera

		Viewport =
			(Camera and Camera.ViewportSize)
			or Vector2.new(
				1280,
				720
			)

	end

	local Height
	UpdateTabletPlatform(Viewport)

	-- On phones, Roblox normally maps IgnoreGuiInset=true to DeviceSafeInsets.
	-- That leaves edge strips outside the ScreenGui's coordinate/clipping area,
	-- so any GUI content extending into them becomes invisible. Use the actual
	-- fullscreen rectangle on phones only; leave tablet and desktop behavior as-is.
	if IsPhone then
		pcall(function()
			ScreenGui.ScreenInsets = Enum.ScreenInsets.None
		end)
		pcall(function()
			ScreenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		end)
	else
		-- The prior setup used IgnoreGuiInset=true (DeviceSafeInsets). Preserve
		-- that behavior on tablet and PC; do not apply phone fullscreen settings.
		pcall(function()
			if ScreenGui.ScreenInsets == Enum.ScreenInsets.None then
				ScreenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
			end
		end)
		pcall(function()
			ScreenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
		end)
	end

	-- UIAspectRatioConstraint has no Enabled property. Detach it on phones
	-- so the menu can use the full portrait viewport; reattach it on tablets
	-- and desktop to preserve their original 4:3 layout.
	if Hub.MenuAspectRatio then
		if IsPhone then
			if Hub.MenuAspectRatio.Parent then
				Hub.MenuAspectRatio.Parent = nil
			end
		elseif Hub.MenuAspectRatio.Parent ~= Hub.MenuContainer then
			Hub.MenuAspectRatio.Parent = Hub.MenuContainer
		end
	end
	local TabletScale = ApplyTabletResponsiveScale(Viewport)
	local LayoutViewport = Viewport
	local TabletXOffset = 0
	if IsMobile and not IsTablet and TabletScale > 1 then
		LayoutViewport = Vector2.new(Viewport.X / TabletScale, Viewport.Y / TabletScale)
	end

	-- ========================================================
	-- INVITE PAGE
	-- ========================================================

	if
		Hub.InInviteMenu
		and InvitePage
	then

		-- The invite page is a SUBPAGE of the 2016 ESC menu.
		-- It must never expand to the whole viewport.
		-- Only InviteList is allowed to scroll.

		local Width
		local PageHeight

		if IsPhone then

			-- Phone invite page is intentionally larger than the
			-- normal ESC menu. Tablets keep a capped, PC-like width.

			Width =
				math.max(
					280,
					LayoutViewport.X - 8
				)

			local PageTop =
				36

			PageHeight =
				math.max(
					220,
					LayoutViewport.Y - PageTop - 8
				)

			Hub.PageClipper.AnchorPoint =
				Vector2.new(
					0,
					0
				)

			Hub.PageClipper.Size =
				UDim2.new(
					0,
					Width,
					0,
					PageHeight
				)

			Hub.PageClipper.Position =
				UDim2.new(
					0.5,
					-Width / 2 + TabletXOffset,
					0,
					PageTop
				)

		elseif IsTablet then

			Width = math.min(TOTAL_HUB_WIDTH, math.max(280, math.floor(LayoutViewport.X - 40 + 0.5)))
			PageHeight = Clamp(LayoutViewport.Y - 90, 150, 600)
			Hub.PageClipper.AnchorPoint = Vector2.new(0, 0)
			Hub.PageClipper.Size = UDim2.new(0, Width, 0, PageHeight)
			Hub.PageClipper.Position = UDim2.new(0.5, -Width / 2, 0.5, -PageHeight / 2)

		else

			local BufferSize =
				0.05 * Viewport.Y

			Width =
				math.max(280, math.floor(Viewport.X * 0.94))

			local ExtraSpace =
				(BufferSize * 2)
				+ (HUBBAR_HEIGHT * 2)

			PageHeight =
				Clamp(
					Viewport.Y - ExtraSpace,
					150,
					600
				)

			Hub.PageClipper.AnchorPoint =
				Vector2.new(
					0,
					0
				)

			Hub.PageClipper.Size =
				UDim2.new(
					0,
					Width,
					0,
					PageHeight
				)

			Hub.PageClipper.Position =
				UDim2.new(
					0.5,
					-Width / 2,
					0.5,
					-PageHeight / 2
				)

		end

		Hub.HubBar.Visible =
			false

		Hub.BottomButtonFrame.Visible =
			false

		if HomeButton then
			HomeButton.Visible =
				false
		end

		Hub.PageView.Size =
			UDim2.new(
				1,
				0,
				1,
				0
			)

		-- Disable the OUTER scrollbar.
		-- InviteList is the only scrolling container.
		Hub.PageView.ScrollBarThickness =
			0

		Hub.PageView.CanvasPosition =
			Vector2.new(
				0,
				0
			)

		if InviteList then
			InviteList.Size =
				UDim2.new(
					1,
					-12,
					1,
					-75
				)

			InviteList.Position =
				UDim2.new(
					0,
					6,
					0,
					65
				)

		end

		InvitePage.Frame.Size =
			UDim2.new(
				1,
				0,
				0,
				PageHeight
			)

		Hub.PageView.CanvasSize =
			UDim2.new(
				0,
				0,
				0,
				PageHeight
			)

	elseif Hub.InConfirmation then

		-- ====================================================
		-- MOBILE / DESKTOP CONFIRMATION PAGE
		-- ====================================================

		local Width = IsPhone
			and math.min(800, math.max(280, LayoutViewport.X - 16))
			or (IsTablet and math.min(TOTAL_HUB_WIDTH, math.max(280, LayoutViewport.X - 48)))
			or math.max(280, math.floor(Viewport.X * 0.94))

		local ConfirmationHeight = IsPhone and 240 or 280

		Hub.HubBar.Visible = false
		Hub.BottomButtonFrame.Visible = false
		if HomeButton then HomeButton.Visible = false end

		Hub.PageClipper.AnchorPoint = Vector2.new(0, 0)
		Hub.PageClipper.Size = UDim2.new(0, Width, 0, ConfirmationHeight)
		Hub.PageClipper.Position =
			IsPhone
			and UDim2.new(0.5, -Width / 2 + TabletXOffset, 0.5, -ConfirmationHeight / 2)
			or UDim2.new(0.5, -Width / 2, 0.5, -ConfirmationHeight / 2 + 75)

		Hub.PageView.AnchorPoint = Vector2.new(0, 0)
		Hub.PageView.Position = UDim2.new(0, 0, 0, 0)
		Hub.PageView.Size = UDim2.new(1, 0, 0, ConfirmationHeight)
		Hub.PageView.CanvasPosition = Vector2.new(0, 0)
		Hub.PageView.CanvasSize = UDim2.new(0, 0, 0, ConfirmationHeight)
		Hub.PageView.ScrollBarThickness = 0

		if IsPhone then
			PositionMobileConfirmationButtons()
		else
			PositionDesktopConfirmationButtons()
			local Page = Hub.CurrentPage
			if Page == ResetPage then
				ApplyResetButtonAvailability()
			end
			if Page == ResetPage or Page == LeavePage then
				Page.Frame.Parent = Hub.PageView
				Page.Frame.Position = UDim2.new(0, 0, 0, 0)
				Page.Frame.Size = UDim2.fromOffset(Width, ConfirmationHeight)
				Page.Frame.Visible = true
				local First = Page == ResetPage and ResetButton or LeaveButton
				local Second = Page == ResetPage and DontResetButton or DontLeaveButton
				First.Parent = Page.Frame
				Second.Parent = Page.Frame
				First.Visible = true
				Second.Visible = true
				local ResetAllowed = Page ~= ResetPage or GetResetButtonAllowed()
				First.Active = ResetAllowed
				First.Selectable = ResetAllowed
				if Page == ResetPage then
					First.ImageColor3 = ResetAllowed and Color3.new(1, 1, 1) or Color3.fromRGB(135, 135, 135)
					if ResetButtonLabel then
						ResetButtonLabel.TextColor3 = ResetAllowed and Color3.new(1, 1, 1) or Color3.fromRGB(150, 150, 150)
					end
				end
				Second.Active = true
				PositionDesktopConfirmationButtons()
				First.ZIndex = SETTINGS_BASE_ZINDEX + 10
				Second.ZIndex = SETTINGS_BASE_ZINDEX + 10
			end
		end

	elseif IsMobile and IsTablet then

		-- ====================================================
		-- TABLET LAYOUT
		-- PC-LIKE PAGE, MOBILE-STYLE HUBBAR/BOTTOM BUTTONS
		-- ====================================================

		Hub.PageClipper.AnchorPoint = Vector2.new(0, 0)
		Hub.PageView.AnchorPoint = Vector2.new(0, 0)
		Hub.PageView.Position = UDim2.new(0, 0, 0, 0)
		Hub.PageView.Size = UDim2.new(1, 0, 1, -20)
		Hub.PageView.CanvasPosition = Vector2.new(0, 0)
		Hub.PageView.ScrollBarThickness = 12
		Hub.PageView.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar

		local Width = math.min(TOTAL_HUB_WIDTH, math.max(720, math.floor(LayoutViewport.X - 20 + 0.5)))
		local HubHeight = TABLET_HUBBAR_HEIGHT
		local BottomHeight = 62
		local TabletGroupTop = SYSTEM_MENU_SIZE.Y + MOBILE_MENU_GAP
		local Top = 3
		local BottomGap = 6
		local PageHeight = math.max(300, math.floor(LayoutViewport.Y - HubHeight - BottomHeight - Top - BottomGap - 10 + 0.5))

		Hub.MenuContainer.Size = UDim2.new(0, Width, 0, math.min(LayoutViewport.Y - 10, HubHeight + PageHeight + BottomHeight + Top + BottomGap))
		Hub.MenuContainer.Position = UDim2.new(0.5, TabletXOffset, 0.5, 0)
		Hub.MenuContainer.AnchorPoint = Vector2.new(0.5, 0.5)

		Hub.HubBar.Visible = true
		Hub.HubBar.Size = UDim2.new(1, 0, 0, HubHeight)
		Hub.HubBar.Position = UDim2.new(0, 0, 0, TabletGroupTop)
		Hub.HubBar.Image = TAB_BAR_IMAGE
		Hub.HubBar.ImageTransparency = 0
		Hub.HubBarContainer.Size = UDim2.new(1, 0, 1, 0)
		Hub.HubBarContainer.Position = UDim2.new(0, 0, 0, 0)
		if Hub.HubBarContainerLayout then Hub.HubBarContainerLayout.Parent = Hub.HubBarContainer end

		if HomeButton then
			HomeButton.Visible = false
		end

		Hub.PageClipper.Parent = Hub.MenuContainer
		Hub.PageClipper.Size = UDim2.new(1, 0, 0, PageHeight)
		Hub.PageClipper.Position = UDim2.new(0, 0, 0, TabletGroupTop + HubHeight)

		Hub.BottomButtonFrame.Parent = Hub.MenuContainer
		Hub.BottomButtonFrame.Visible = Hub.Visible and not Hub.InInviteMenu and not Hub.InConfirmation
		Hub.BottomButtonFrame.Size = UDim2.new(1, 0, 0, BottomHeight)
		Hub.BottomButtonFrame.Position = UDim2.new(0, 0, 1, -BottomHeight)
		Hub.BottomButtonFrame.ZIndex = SETTINGS_BASE_ZINDEX + 6
		Hub.BottomButtonFrame.ClipsDescendants = false

		if PlayersPage and PlayersPage.Frame then
			PlayersPage.Frame.Size = UDim2.new(1, 0, 0, math.max(240, PlayersPage.Frame.Size.Y.Offset))
		end

	elseif IsPhone then

		if Hub.InInviteMenu and ConfigureInviteMobileHeader then
			ConfigureInviteMobileHeader()
		end

		-- ====================================================
		-- NORMAL MOBILE ESC MENU
		-- ====================================================

		Hub.PageClipper.AnchorPoint =
			Vector2.new(0, 0)

		Hub.PageView.AnchorPoint =
			Vector2.new(0, 0)

		Hub.PageView.Position =
			UDim2.new(0, 0, 0, 0)

		Hub.PageView.Size =
			UDim2.new(1, 0, 1, 0)

		Hub.PageView.CanvasPosition =
			Vector2.new(0, 0)

		Hub.PageView.ScrollBarThickness = 0

		-- Phone-only edge-to-edge layout.  Tablets and desktop use their own
		-- branches above/below and are deliberately left unchanged.
		Hub.MenuContainer.Size = UDim2.new(1, 0, 1, 0)
		Hub.MenuContainer.Position = UDim2.new(0, 0, 0, 0)
		Hub.MenuContainer.AnchorPoint = Vector2.new(0, 0)
		-- HubBar is sized against this full-screen phone container; content below
		-- keeps its separate 8px side inset. Do not use Width to resize the hub.
		local Width = math.max(1, math.floor(LayoutViewport.X - 16 + 0.5))

		local GroupTop = SYSTEM_MENU_SIZE.Y + MOBILE_MENU_GAP
		local MobileBarHeight = MOBILE_HUBBAR_HEIGHT

		local PageHeight =
			math.max(
				100,
				math.floor((LayoutViewport.Y * 0.95) - 45 + 0.5)
			)

		local PageCenterYOffset =
			(-PageHeight / 2) + 60

		Height =
			PageHeight

		Hub.HubBar.AnchorPoint = Vector2.new(0, 0)
		Hub.HubBar.Size = UDim2.new(1, 0, 0, MobileBarHeight)
		Hub.HubBar.Position = UDim2.new(0, 0, 0, GroupTop)

		Hub.HubBarContainer.Size = UDim2.new(1, 0, 1, 0)
		Hub.HubBarContainer.Position = UDim2.new(0, 0, 0, 0)
		if Hub.HubBarContainerLayout then Hub.HubBarContainerLayout.Parent = Hub.HubBarContainer end

		Hub.PageClipper.Size = UDim2.new(1, -16, 0, PageHeight)
		Hub.PageClipper.Position = UDim2.new(0, 8, 0.5, PageCenterYOffset)

		-- The fixed PC button frame is NEVER used on mobile.
		Hub.BottomButtonFrame.Visible = false
		Hub.BottomButtonFrame.Size = UDim2.new(1, -10, 0, MOBILE_HUBBAR_HEIGHT)
		Hub.BottomButtonFrame.Position = UDim2.new(0.5, 5, 1, -43)

		-- The mobile action buttons belong to a ButtonsContainer inside Players.
		if PlayersPage and PlayersPage.Frame then

			local UiScale = GetMobileUiScale()
			local ActionHeight = 62
			local ActionWidth = 1 / 3

			if not MobileButtonsContainer or not MobileButtonsContainer.Parent then
				MobileButtonsContainer = Create("Frame", {
					Name = "ButtonsContainer",
					Parent = PlayersPage.Frame,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 62),
					Position = UDim2.new(0, 0, 0, 0),
					ZIndex = SETTINGS_BASE_ZINDEX + 1,
				})
			end
			MobileButtonsContainer.Size = UDim2.new(1, 0, 0, 62)
			MobileButtonsContainer.Position = UDim2.new(0, 0, 0, 0)

			for Index, Button in ipairs({
				MobileActionButtons.Leave,
				MobileActionButtons.Reset,
				MobileActionButtons.Resume,
			}) do

				if Button then

					Button.Parent = MobileButtonsContainer

					Button.AnchorPoint = Vector2.new(
						Index == 2 and 0.5 or (Index == 3 and 1 or 0),
						0
					)
					Button.Size = UDim2.new(ActionWidth, -5, 0, ActionHeight)
					Button.Position = UDim2.new(
						Index == 2 and 0.5 or (Index == 3 and 1 or 0),
						Index == 2 and 0 or (Index == 3 and 0 or 0),
						0,
						0
					)

					Button.Visible = true
					Button.ZIndex = SETTINGS_BASE_ZINDEX + 4

					local Label =
						Button:FindFirstChild(
							Button.Name .. "TextLabel"
						)

					if Label then
						Label.Position = UDim2.new(0, 0, 0, 0)
						Label.Size = UDim2.new(1, 0, 1, -6)
						Label.ZIndex = SETTINGS_BASE_ZINDEX + 5
					end

					for _, Child in ipairs(Button:GetChildren()) do
						if Child:IsA("ImageLabel") then
							Child.Visible = false
						end
					end

				end

			end

			local PlayerRows = {}
			for _, Child in ipairs(PlayersPage.Frame:GetChildren()) do
				if Child.Name:sub(1, 11) == "PlayerLabel" then
					Insert(PlayerRows, Child)
				end
			end
			table.sort(PlayerRows, function(A, B) return A.Name < B.Name end)

			local PlayerStartY =
				(LayoutPhonePlayerActionRows and LayoutPhonePlayerActionRows(PlayersPage.Frame, 72))
				or 72
			for Index, Row in ipairs(PlayerRows) do
				Row.Position = UDim2.new(0, 0, 0, PlayerStartY + ((Index - 1) * 72))
			end

			local ContentHeight = PlayerStartY + (#PlayerRows * 72)
			PlayersPage.Frame.Size = UDim2.new(1, 0, 0, math.max(240, ContentHeight, PageHeight))
			Hub.PageView.CanvasSize = UDim2.new(0, 0, 0, math.max(ContentHeight, PageHeight))

		else

			Hub.PageView.CanvasSize =
				UDim2.new(0, 0, 0, PageHeight)

		end

		if HomeButton then
			HomeButton.Visible = false
		end

	else
		-- ====================================================
		-- PC / 2023 DESKTOP LAYOUT
		-- HubBar spans the viewport; content rows use nearly the full width.
		-- ====================================================
		Hub.MenuContainer.Size = UDim2.new(1, 0, 0.95, 0)
		Hub.MenuContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
		Hub.MenuContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		local ContentWidth = math.max(280, math.floor(Viewport.X * 0.94 + 0.5))
		local FullScreenHeight = Viewport.Y
		local BufferSize = (1 - 0.95) * FullScreenHeight
		local BarSize = 60
		local ExtraSpace = BufferSize * 2 + BarSize * 2
		local UsableScreenHeight = FullScreenHeight - ExtraSpace
		local LargestPageSize = 600
		local MinimumPageSize = 150
		local UsePageSize

		Hub.HubBar.Parent = Hub.MenuContainer
		Hub.HubBar.AnchorPoint = Vector2.new(0, 0)
		Hub.HubBar.Size = UDim2.new(1, 0, 0, 60)
		if LargestPageSize < UsableScreenHeight then
			UsePageSize = LargestPageSize
			Hub.HubBar.Position = UDim2.new(0, 0, 0.5, -LargestPageSize / 2 - BarSize)
			Hub.BottomButtonFrame.Position = UDim2.new(0.5, -ContentWidth / 2, 0.5, LargestPageSize / 2)
		elseif UsableScreenHeight < MinimumPageSize then
			UsePageSize = MinimumPageSize
			Hub.HubBar.Position = UDim2.new(0, 0, 0.5, -MinimumPageSize / 2 - BarSize)
			Hub.BottomButtonFrame.Position = UDim2.new(0.5, -ContentWidth / 2, 0.5, MinimumPageSize / 2)
		else
			UsePageSize = UsableScreenHeight
			Hub.HubBar.Position = UDim2.new(0, 0, 0, BufferSize)
			Hub.BottomButtonFrame.Position = UDim2.new(0.5, -ContentWidth / 2, 1, -(BufferSize + BarSize))
		end
		Hub.HubBar.Image = TAB_BAR_IMAGE
		Hub.HubBar.ImageTransparency = HomeButtonEnabled and 1 or 0
		Hub.HubBarContainer.Size = UDim2.new(1, HomeButtonEnabled and -70 or 0, 1, 0)
		Hub.HubBarContainer.Position = UDim2.new(0, HomeButtonEnabled and 70 or 0, 0, 0)
		if Hub.HubBarContainerLayout then Hub.HubBarContainerLayout.Parent = nil end
		if HomeButton then
			HomeButton.Visible = HomeButtonEnabled
			HomeButton.Size = UDim2.new(0, 60, 0, 60)
			HomeButton.Position = UDim2.new(0, 0, 0, 0)
		end

		Hub.PageClipper.Parent = Hub.MenuContainer
		Hub.PageClipper.AnchorPoint = Vector2.new(0.5, 0)
		Hub.PageClipper.Size = UDim2.new(0, ContentWidth, 0, UsePageSize)
		Hub.PageClipper.Position = UDim2.new(0.5, 0, 0.5, -UsePageSize / 2)
		Hub.PageView.AnchorPoint = Vector2.new(0.5, 0.5)
		Hub.PageView.Position = UDim2.new(0.5, 0, 0.5, 0)
		Hub.PageView.Size = UDim2.new(1, 0, 1, -20)
		Hub.PageView.CanvasPosition = Vector2.new(0, 0)
		Hub.BottomButtonFrame.Parent = Hub.MenuContainer
		Hub.BottomButtonFrame.Size = UDim2.new(0, ContentWidth, 0, 70)
		if Hub.CurrentPage and Hub.CurrentPage.Frame then
			Hub.CurrentPage.Frame.Position = UDim2.new(0, 0, 0, 0)
			local PageContentHeight = math.max(0, Hub.CurrentPage.Frame.Position.Y.Offset + Hub.CurrentPage.Frame.Size.Y.Offset)
			local PageViewHeight = math.max(0, UsePageSize - 20)
			local NeedsPlayerScrollbar = Hub.CurrentPage == PlayersPage and PageContentHeight > PageViewHeight + 1
			if Hub.CurrentPage == PlayersPage then
				Hub.PageView.ScrollBarThickness = NeedsPlayerScrollbar and 12 or 0
				Hub.PageView.VerticalScrollBarInset = NeedsPlayerScrollbar and Enum.ScrollBarInset.ScrollBar or Enum.ScrollBarInset.None
			else
				Hub.PageView.ScrollBarThickness = 12
				Hub.PageView.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
			end
			Hub.PageView.CanvasSize = UDim2.new(0, 0, 0, math.max(PageContentHeight, PageViewHeight))
		else
			Hub.PageView.ScrollBarThickness = 12
			Hub.PageView.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		end
	end

	if LayoutTabs then
		LayoutTabs()
	end

	if IsMobile then
		ApplyTabletResponsiveScale(Viewport)
	end
	if ApplyMobileTextSizing then ApplyMobileTextSizing(ScreenGui) end

end

Connect(
	ScreenGui:GetPropertyChangedSignal(
		"AbsoluteSize"
	),
	ResizeHub
)

Connect(
	workspace:GetPropertyChangedSignal(
		"CurrentCamera"
	),
	ResizeHub
)

if workspace.CurrentCamera then

	Connect(
		workspace.CurrentCamera:GetPropertyChangedSignal(
			"ViewportSize"
		),
		ResizeHub
	)

end

-- ============================================================
-- TABS
-- ============================================================

MakeTab = function(
	Page,
	Title,
	Icon,
	Width
)

	local Tab =
		Create(
			"TextButton",
			{
				Name =
					Page.Name
					.. "Tab",

				Parent =
					Hub.HubBarContainer,

				BackgroundTransparency =
					1,

				Text =
					"",

				Size =
					UDim2.new(
						0,
						Width
						or 160,
						1,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	local IconLabel =
		Create(
			"ImageLabel",
			{
				Name =
					"Icon",

				Parent =
					Tab,

				BackgroundTransparency =
					1,

				Image =
					Icon,

				ImageTransparency =
					0.5,

				Size = UDim2.new(0,36,0,36),

				Position = UDim2.new(0,12,0.5,-18),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)
	Create(
		"UIAspectRatioConstraint",
		{
			Parent = IconLabel,
			AspectRatio = 1,
			AspectType = Enum.AspectType.FitWithinMaxSize,
			DominantAxis = Enum.DominantAxis.Width,
		}
	)

	local TitleLabel =
		Create(
			"TextLabel",
			{
				Name =
					"Title",

				Parent =
				IconLabel,

			BackgroundTransparency =
				1,

			Font =
				Enum.Font.SourceSansBold,

			TextSize =
				24,

			TextColor3 =
				Color3.new(
					1,
					1,
					1
				),

			TextXAlignment =
				Enum.TextXAlignment.Left,

			TextTransparency =
				0.5,

			Text =
				Title,

			Size =
				UDim2.new(
					1,
					-60,
					1,
					0
				),

			Position = UDim2.new(0,72,0,0),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 3,
		}
	)

	local Selection =
		Create(
			"ImageLabel",
			{
				Name =
					"TabSelection",

				Parent =
					Tab,

				Image =
					TAB_SELECTION_IMAGE,

				ScaleType =
					Enum.ScaleType.Slice,

				SliceCenter =
					Rect.new(
						3,
						1,
						4,
						5
					),

				Visible =
					false,

				BackgroundTransparency =
					1,

				Size =
					UDim2.new(
						1,
						0,
						0,
						6
					),

				Position =
					UDim2.new(
						0,
						0,
						1,
						-6
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	Page.Tab =
		Tab

	Page.Icon =
		IconLabel

	Page.Selection =
		Selection

	Connect(
		Tab.MouseButton1Click,
		function()
			SwitchToPage(
				Page
			)
		end
	)

end

LayoutTabs = function()
	local Order = IsMobile
		and { PlayersPage, GamePage, ReportPage, HelpPage }
		or { PlayersPage, GamePage, ReportPage, HelpPage, RecordPage }

	local Wanted = {}
	for _, Page in ipairs(Order) do
		if Page then
			Wanted[Page] = true
		end
	end

	-- Hide tabs that do not exist on the current platform. In particular,
	-- Captures/Record is not present on phone or tablet.
	for _, Page in ipairs(Hub.Pages) do
		if Page and Page.Tab then
			Page.Tab.Visible = Wanted[Page] == true
			if not Wanted[Page] and Page.Selection then
				Page.Selection.Visible = false
			end
		end
	end

	local Count = #Order
	if Count == 0 then return end

	if IsMobile then
		if Hub.HubBarContainerLayout then
			Hub.HubBarContainerLayout.Parent = Hub.HubBarContainer
			Hub.HubBarContainerLayout.FillDirection = Enum.FillDirection.Horizontal
			Hub.HubBarContainerLayout.HorizontalAlignment = IsPhone and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center
			Hub.HubBarContainerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			Hub.HubBarContainerLayout.SortOrder = Enum.SortOrder.LayoutOrder
			Hub.HubBarContainerLayout.Padding = UDim.new(0, 0)
		end
	else
		if Hub.HubBarContainerLayout then Hub.HubBarContainerLayout.Parent = nil end
	end

	for Index, Page in ipairs(Order) do
		if Page and Page.Tab then
			local Tab = Page.Tab
			local Fraction = 1 / Count
			Tab.AutomaticSize = Enum.AutomaticSize.None
			Tab.ClipsDescendants = false
			-- Equal-width tab hitboxes always fill the HubBar container on phones;
			-- the UIListLayout then packs them edge-to-edge with zero padding.
			Tab.Size = UDim2.new(Fraction, 0, 1, 0)
			if not IsMobile then
				Tab.Position = UDim2.new((Index - 1) * Fraction, 0, 0, 0)
			end
			Tab.LayoutOrder = Index

			local Selected = Hub.CurrentPage == Page
			if Page.Selection then
				Page.Selection.Visible = Selected
			end

			if Page.Icon then
				Page.Icon.ImageTransparency = Selected and 0 or 0.5
				if IsMobile then
					Page.Icon.Size = UDim2.new(0, 34, 0, 28)
					Page.Icon.Position = UDim2.new(0, 10, 0.5, -14)
				end
				local Title = Page.Icon:FindFirstChild("Title")
				if Title then
					Title.TextColor3 = Color3.new(1, 1, 1)
					Title.TextTransparency = Selected and 0 or 0.5
					if IsMobile then
						Title.TextSize = 20
						Title.Size = UDim2.new(0, 140, 1, 0)
						Title.Position = UDim2.new(1.2, 0, 0, 0)
						Title.ClipsDescendants = false
					else
						Title.TextSize = 24
						Title.Size = UDim2.new(0, 190, 1, 0)
						Title.Position = UDim2.new(0, 48, 0, 0)
						Title.ClipsDescendants = false
					end
				end
			end
		end
	end
end

-- ============================================================
-- SWITCH PAGE
-- ============================================================

GetPageIndex = function(Page)

	for Index, Other in next,
		Hub.Pages
	do

		if Other == Page then
			return Index
		end

	end

	return 1
end

SwitchToPage = function(
	Page,
	NoStack,
	NoAnimation
)

	if not Page then
		return
	end

	local OldPage =
		Hub.CurrentPage

	local OldFrame =
		OldPage
		and OldPage.Frame

	local IsConfirmationPage =
		Page == ResetPage
		or Page == LeavePage
		or OldPage == ResetPage
		or OldPage == LeavePage

	local Direction =
		(
			GetPageIndex(Page)
			>= GetPageIndex(OldPage)
		)
		and 1
		or -1

	for _, Other in next,
		Hub.Pages
	do

		if
			Other.Frame
			and Other ~= Page
			and Other ~= OldPage
		then

			Other.Frame.Visible =
				false

		end

		if Other.Selection then

			local Title =
				Other.Icon
				and Other.Tab:FindFirstChild(
					"Title"
				)

			Other.Selection.Visible =
				false

			Other.Icon.ImageTransparency =
				0.5

			if Title then
				Title.TextTransparency =
					0.5
			end

		end

	end

	Page.Frame.Parent =
		Hub.PageView

	Page.Frame.Visible =
		true

	if IsConfirmationPage then
		Page.Frame.Position = UDim2.new(0, 0, 0, 0)
		if OldFrame and OldFrame ~= Page.Frame then
			OldFrame.Visible = false
		end
	end

	if
		OldFrame
		and OldFrame ~= Page.Frame
		and OldFrame.Parent == Hub.PageView
		and OldFrame.Visible
		and not NoAnimation
		and not IsConfirmationPage
	then

		local PageWidth =
			math.max(
				Hub.PageClipper.AbsoluteSize.X,
				800
			)

		local PageFrameTop =
			0

		Page.Frame.Position =
			UDim2.new(
				0,
				Direction * PageWidth,
				0,
				PageFrameTop
			)

		TweenTo(
			Page.Frame,
			UDim2.new(
				0,
				0,
				0,
				PageFrameTop
			),
			Enum.EasingDirection.In,
			Enum.EasingStyle.Quad,
			0.1
		)

		TweenTo(
			OldFrame,
			UDim2.new(
				0,
				-Direction * PageWidth,
				0,
				0
			),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Quad,
			0.1
		)

		task.delay(
			0.12,
			function()

				if
					Hub.CurrentPage ~= OldPage
					and OldFrame
				then

					OldFrame.Visible =
						false

				end

			end
		)

	else

		Page.Frame.Position =
			UDim2.new(
				0,
				0,
				0,
				0
			)

		if
			OldFrame
			and OldFrame ~= Page.Frame
		then

			OldFrame.Visible =
				false

		end

	end

	Hub.PageView.CanvasPosition =
		Vector2.new(
			0,
			0
		)

	local SwitchPageContentHeight =
		math.max(0, Page.Frame.Position.Y.Offset + Page.Frame.Size.Y.Offset)
	local SwitchPageViewHeight =
		math.max(
			0,
			Hub.PageClipper.AbsoluteSize.Y
				- (IsMobile and 0 or 20)
		)

	Hub.PageView.CanvasSize =
		UDim2.new(
			0,
			0,
			0,
			math.max(
				SwitchPageContentHeight,
				SwitchPageViewHeight
			)
		)

	if not IsMobile and Page == PlayersPage then
		local NeedsPlayerScrollbar =
			SwitchPageContentHeight > SwitchPageViewHeight + 1
		Hub.PageView.ScrollBarThickness =
			NeedsPlayerScrollbar and 12 or 0
		Hub.PageView.VerticalScrollBarInset =
			NeedsPlayerScrollbar
			and Enum.ScrollBarInset.ScrollBar
			or Enum.ScrollBarInset.None
	elseif not IsMobile then
		Hub.PageView.ScrollBarThickness = 12
		Hub.PageView.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	end

	Hub.CurrentPage =
		Page

	if LayoutTabs then
		LayoutTabs()
	end

	if Page.Selection then

		local Title =
			Page.Icon
			and Page.Icon:FindFirstChild(
				"Title"
			)

		Page.Selection.Visible =
			true

		Page.Icon.ImageTransparency =
			0

		if Title then
			Title.TextTransparency =
				0
		end

	end

	if
		not NoStack
		and Hub.MenuStack[#Hub.MenuStack] ~= Page
	then

		Insert(
			Hub.MenuStack,
			Page
		)

	end

	if IsMobile then
		if BuildMobileHelpPage then BuildMobileHelpPage() end
		if ApplyMobileReportLayout then ApplyMobileReportLayout() end
	end

end

AddPage = function(
	Page,
	Title,
	Icon,
	Width
)

	Insert(
		Hub.Pages,
		Page
	)

	if Title then
		MakeTab(
			Page,
			Title,
			Icon,
			Width
		)
	end

	LayoutTabs()

end

-- ============================================================
-- ROW SYSTEM
-- ============================================================

MakeRow = function(
	Page,
	Name,
	Height
)

	local Row =
		Create(
			"ImageButton",
			{
				Name =
					Name
					.. "Frame",

				BackgroundTransparency =
					1,

				BorderSizePixel =
					0,

				Image =
					"",

				Active =
					false,

				AutoButtonColor =
					false,

				Selectable =
					false,

				Size =
					UDim2.new(
						1,
						0,
						0,
						Height
						or 50
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	Create(
		"TextLabel",
		{
			Name =
				Name
				.. "Label",

			Parent =
				Row,

			BackgroundTransparency =
				1,

			Font =
				Enum.Font.SourceSansBold,

			TextSize =
				24,

			TextColor3 =
				Color3.new(
					1,
					1,
					1
				),

			TextXAlignment =
				Enum.TextXAlignment.Left,

			Text =
				Name,

			Size =
				UDim2.new(
					0,
					200,
					1,
					0
				),

			Position =
				UDim2.new(
					0,
					10,
					0,
					0
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 3,
		}
	)

	Page:AddRow(
		Row
	)

	return Row
end

-- ============================================================
-- VOICE CHAT
-- ============================================================

VoiceEnabledCache = {}
VoiceCheckBusy = {}
VoiceCheckError = {}
-- Failed remote eligibility lookups are rate-limited per user. Roblox rejects
-- client-side queries for other users, so retrying every refresh only causes lag.
VoiceEligibilityQueryStamp = {}
VOICE_REMOTE_ELIGIBILITY_RETRY_SECONDS = 60
VoiceMutedPlayers = {}
VoiceSavedVolumes = {}
VoiceSavedMuted = {}
VoiceMuteAllActive = false
VoiceCheckNext = {}
SavedVoiceGroupId = nil
VoiceConnectionAttempting = false
VoiceChatDesiredOn = false

VOICE_ICON_ROOT = "rbxasset://textures/ui/VoiceChat/"
VOICE_MISC_ROOT = VOICE_ICON_ROOT .. "Misc/"
VOICE_MIC_ROOT = VOICE_ICON_ROOT .. "MicLight/"
VOICE_SPEAKER_ROOT = VOICE_ICON_ROOT .. "SpeakerLight/"

GetAudioDeviceInputCache = {}
VoiceActivityPeak = {}
VoiceActivityStamp = {}
VoiceActivityPeakMeasured = {}
VoiceActivityActive = {}
NativeVoiceIconObjects = {}
NativeVoiceIconImages = {}
-- Preserve the last observed native icon for remote players when Roblox removes
-- their transient VoiceBubble UI while they are quiet/off-camera. This is a
-- last-observed value, not proof of a live state when no native UI is present.
NativeVoiceIconLastImages = {}
NativeVoiceIconLastSeenAt = {}
NativeVoiceIconConnections = {}
NativeVoiceIconConnectedObjects = {}
NativeVoiceScanStamp = 0
NativeVoiceScanScheduled = false

-- Index real Roblox-created voice inputs once. Earlier builds scanned every
-- CoreGui/SoundService descendant on every icon refresh, which caused severe UI lag.
VoiceAudioInputIndexInitialized = false
IndexExistingVoiceAudioInputs = function()
	if VoiceAudioInputIndexInitialized then return end
	VoiceAudioInputIndexInitialized = true
	local function Index(Candidate)
		if not Candidate then return end
		local IsInput = false
		local Name = ""
		local Owner = nil
		pcall(function()
			IsInput = Candidate:IsA("AudioDeviceInput")
			Name = tostring(Candidate.Name or "")
			Owner = Candidate.Player
		end)
		if not IsInput or Name == "Settings2016LocalAudioDeviceInput" or not Owner then return end
		local Existing = GetAudioDeviceInputCache[Owner]
		local ExistingReady = false
		local CandidateReady = false
		if Existing and Existing.Parent then pcall(function() ExistingReady = Existing.IsReady == true or Existing.Active == true end) end
		pcall(function() CandidateReady = Candidate.IsReady == true or Candidate.Active == true end)
		if not Existing or not Existing.Parent or (CandidateReady and not ExistingReady) then
			GetAudioDeviceInputCache[Owner] = Candidate
		end
	end
	pcall(function()
		for _, Player in ipairs(Players:GetPlayers()) do
			for _, Child in ipairs(Player:GetChildren()) do Index(Child) end
		end
	end)
	pcall(function() for _, Descendant in ipairs(SoundService:GetDescendants()) do Index(Descendant) end end)
end

GetAudioDeviceInput = function(Player)
	if not Player then return nil end
	local Cached = GetAudioDeviceInputCache[Player]
	if Cached and Cached.Parent then
		local Matches = false
		pcall(function()
			Matches = Cached:IsA("AudioDeviceInput")
				and Cached.Player == Player
				and Cached.Name ~= "Settings2016LocalAudioDeviceInput"
		end)
		if Matches then return Cached end
	end
	GetAudioDeviceInputCache[Player] = nil

	-- Remove only the known fake object left by old script copies; never create a fake input.
	if Player == LocalPlayer then
		pcall(function()
			for _, Child in ipairs(Player:GetChildren()) do
				if Child:IsA("AudioDeviceInput") and Child.Name == "Settings2016LocalAudioDeviceInput" then Child:Destroy() end
			end
		end)
	end

	local Best = nil
	local BestScore = -1
	local function Consider(Candidate)
		if not Candidate then return end
		local IsInput, Name, Owner = false, "", nil
		pcall(function()
			IsInput = Candidate:IsA("AudioDeviceInput")
			Name = tostring(Candidate.Name or "")
			Owner = Candidate.Player
		end)
		if not IsInput or Name == "Settings2016LocalAudioDeviceInput" or Owner ~= Player then return end
		local Score = 0
		pcall(function() if Candidate.IsReady == true then Score += 2 end end)
		pcall(function() if Candidate.Active == true then Score += 1 end end)
		if not Best or Score > BestScore then Best = Candidate; BestScore = Score end
	end
	pcall(function() for _, Child in ipairs(Player:GetChildren()) do Consider(Child) end end)
	if not Best and not VoiceAudioInputIndexInitialized then
		IndexExistingVoiceAudioInputs()
		Cached = GetAudioDeviceInputCache[Player]
		if Cached and Cached.Parent then
			local Matches = false
			pcall(function() Matches = Cached:IsA("AudioDeviceInput") and Cached.Player == Player and Cached.Name ~= "Settings2016LocalAudioDeviceInput" end)
			if Matches then return Cached end
		end
	end
	if Best then GetAudioDeviceInputCache[Player] = Best end
	return Best
end

VoiceAnalyzers = {}
VoiceAnalyzerWires = {}
LastVoicePeak = 0

EnsureVoiceAnalyzer = function(Player)
	if not Player then return nil end

	local Input = GetAudioDeviceInput(Player)
	if not Input then return nil end

	local Analyzer = VoiceAnalyzers[Player]
	if Analyzer and Analyzer.Parent and Analyzer:IsA("AudioAnalyzer") then
		local Wire = VoiceAnalyzerWires[Player]
		local WireMatchesInput = false
		if Wire and Wire.Parent and Wire:IsA("Wire") then
			pcall(function()
				WireMatchesInput = Wire.SourceInstance == Input
					and Wire.TargetInstance == Analyzer
					and Wire.SourceName == "Output"
					and Wire.TargetName == "Input"
			end)
		end
		if WireMatchesInput then return Analyzer end
	end

	Analyzer = nil
	Protect(function()
		Analyzer = SoundService:FindFirstChild("Settings2016VoiceAnalyzer_" .. tostring(Player.UserId))
	end)
	if not Analyzer then
		Protect(function()
			Analyzer = Instance.new("AudioAnalyzer")
			Analyzer.Name = "Settings2016VoiceAnalyzer_" .. tostring(Player.UserId)
			Analyzer.SpectrumEnabled = false
			Analyzer.Parent = SoundService
		end)
	end
	if not Analyzer then return nil end

	local Wire = nil
	Protect(function()
		for _, Child in next, Analyzer:GetChildren() do
			if Child:IsA("Wire") then
				Wire = Child
				break
			end
		end
	end)

	if not Wire then
		Protect(function()
			Wire = Instance.new("Wire")
			Wire.Name = "Settings2016VoiceAnalyzerWire"
			Wire.SourceInstance = Input
			Wire.SourceName = "Output"
			Wire.TargetInstance = Analyzer
			Wire.TargetName = "Input"
			Wire.Parent = Analyzer
		end)
	else
		Protect(function()
			Wire.SourceInstance = Input
			Wire.SourceName = "Output"
			Wire.TargetInstance = Analyzer
			Wire.TargetName = "Input"
		end)
	end

	if Wire then
		VoiceAnalyzers[Player] = Analyzer
		VoiceAnalyzerWires[Player] = Wire
		return Analyzer
	end

	return nil
end

GetVoiceAnalyzer = function(Player)
	local Analyzer = EnsureVoiceAnalyzer(Player)
	if Analyzer then return Analyzer end

	Protect(function()
		Analyzer = SoundService:FindFirstChild("Settings2016VoiceAnalyzer_" .. tostring(Player.UserId))
	end)
	if Analyzer then return Analyzer end

	Protect(function()
		Analyzer = Player:FindFirstChildWhichIsA("AudioAnalyzer", true)
	end)
	if Analyzer then return Analyzer end

	Protect(function()
		local Character = Player.Character
		if Character then
			Analyzer = Character:FindFirstChildWhichIsA("AudioAnalyzer", true)
		end
	end)

	return Analyzer
end

GetVoiceLevel = function(Player)
	if not Player then return 0 end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	local Stamp = tonumber(VoiceActivityStamp[UserId]) or 0
	local ActivityIsRecent = Stamp > 0 and (os.clock() - Stamp) <= 0.65
	local ActivityPeak = tonumber(VoiceActivityPeak[UserId]) or 0

	-- When Roblox sends numeric mic peaks, use those directly. An AudioAnalyzer
	-- can exist while remaining pinned at zero if that client cannot tap the
	-- remote stream; that zero must not hide a live peak event.
	if ActivityIsRecent and VoiceActivityPeakMeasured[UserId] == true then
		return Clamp(ActivityPeak, 0, 1)
	end

	local Peak = 0
	local Input = GetAudioDeviceInput(Player)
	local Analyzer = Input and GetVoiceAnalyzer(Player) or nil
	if Input and Analyzer then
		local Ok, Value = pcall(function() return tonumber(Analyzer.PeakLevel) end)
		if Ok and Value ~= nil then
			Peak = Clamp(Value, 0, 1)
		end
	end

	-- If only a coarse speaking boolean is exposed, show a modest speaking
	-- indication instead of forcing the meter to 100% on every event.
	if ActivityIsRecent and VoiceActivityPeakMeasured[UserId] ~= true then
		Peak = math.max(Peak, Clamp(ActivityPeak, 0, 0.45))
	end
	return Clamp(Peak, 0, 1)
end

VoiceUnmutedIcon = function(Level, UseSpeaker)
	-- Remote player rows use speaker sprites; only the local self-mic uses mic sprites.
	local Root = UseSpeaker and VOICE_SPEAKER_ROOT or VOICE_MIC_ROOT
	if Level <= 0.00001 then return Root .. "Unmuted0@3x.png" end
	if Level < 0.2 then return Root .. "Unmuted20@3x.png" end
	if Level < 0.4 then return Root .. "Unmuted40@3x.png" end
	if Level < 0.6 then return Root .. "Unmuted60@3x.png" end
	if Level < 0.8 then return Root .. "Unmuted80@3x.png" end
	return Root .. "Unmuted100@3x.png"
end

-- Resolve Roblox's actual per-player bubble-chat microphone image when it
-- exists. The image may be transient, so the mirror refresh caches its last state.
-- This lookup runs only from RefreshNativeVoiceMirrorCache, not every icon frame.
FindNativeVoiceBubbleIconObject = function(Player)
	if not Player then return nil end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	if UserId <= 1 then return nil end
	local ExperienceChat = nil
	local BubbleChatRoot = nil
	pcall(function() ExperienceChat = CoreGui:FindFirstChild("ExperienceChat") end)
	if not ExperienceChat then
		pcall(function()
			local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
			ExperienceChat = RobloxGui and RobloxGui:FindFirstChild("ExperienceChat")
		end)
	end
	if not ExperienceChat then return nil end
	pcall(function() BubbleChatRoot = ExperienceChat:FindFirstChild("bubbleChat", true) end)
	if not BubbleChatRoot then return nil end

	local Bubble = nil
	pcall(function()
		Bubble = BubbleChatRoot:FindFirstChild("BubbleChat_" .. tostring(UserId))
			or BubbleChatRoot:FindFirstChild(tostring(UserId))
	end)
	if not Bubble then
		local Ok, Children = pcall(function() return BubbleChatRoot:GetChildren() end)
		if Ok then
			for _, Candidate in ipairs(Children) do
				local Name = string.lower(tostring(Candidate.Name or ""))
				if Name:find(tostring(UserId), 1, true) then
					local HasVoiceBubble = false
					pcall(function() HasVoiceBubble = Candidate:FindFirstChild("VoiceBubble", true) ~= nil end)
					if HasVoiceBubble then Bubble = Candidate; break end
				end
			end
		end
	end
	if not Bubble then return nil end

	local VoiceBubble = nil
	pcall(function() VoiceBubble = Bubble:FindFirstChild("VoiceBubble", true) end)
	if not VoiceBubble then return nil end
	local function IsVoiceImage(Object)
		if not Object then return false end
		local IsImage, Image = false, ""
		pcall(function()
			IsImage = Object:IsA("ImageLabel") or Object:IsA("ImageButton")
			Image = tostring(Object.Image or "")
		end)
		return IsImage and Image:find("VoiceChat", 1, true) ~= nil
			and (Image:find("Muted", 1, true) ~= nil
				or Image:find("Unmuted", 1, true) ~= nil
				or Image:find("Connecting", 1, true) ~= nil
				or Image:find("Error", 1, true) ~= nil)
	end
	local Insert = nil
	pcall(function() Insert = VoiceBubble:FindFirstChild("Insert", true) end)
	if IsVoiceImage(Insert) then return Insert end
	local Ok, Descendants = pcall(function() return VoiceBubble:GetDescendants() end)
	if Ok then
		local Best, BestScore = nil, -1
		for _, Object in ipairs(Descendants) do
			if IsVoiceImage(Object) then
				local Score = 0
				if string.lower(tostring(Object.Name or "")) == "insert" then Score += 100 end
				if Object.Visible then Score += 10 end
				if Score > BestScore then Best = Object; BestScore = Score end
			end
		end
		return Best
	end
	return nil
end

-- Cache Roblox's native voice icons for participant detection and fallback.
-- Search only small relevant UI roots, not all of CoreGui on the render path.
RefreshNativeVoiceMirrorCache = function(Force)
	local Now = os.clock()
	local MinimumInterval = Force and 1.0 or 4.0
	if NativeVoiceScanStamp > 0 and (Now - NativeVoiceScanStamp) < MinimumInterval then return end
	NativeVoiceScanStamp = Now

	local Found = {}
	local RobloxGui = CoreGui:FindFirstChild("RobloxGui")

	-- Self microphone: search only the native MuteSelfButton subtree.
	if RobloxGui then
		local SettingsShield = RobloxGui:FindFirstChild("SettingsClippingShield")
		local NativeMuteButton = SettingsShield and SettingsShield:FindFirstChild("MuteSelfButton", true)
		if NativeMuteButton then
			local Candidates = {NativeMuteButton}
			pcall(function()
				for _, Descendant in ipairs(NativeMuteButton:GetDescendants()) do
					table.insert(Candidates, Descendant)
				end
			end)
			for _, Candidate in ipairs(Candidates) do
				local IsImage, Image = false, ""
				pcall(function()
					IsImage = Candidate:IsA("ImageLabel") or Candidate:IsA("ImageButton")
					Image = tostring(Candidate.Image or "")
				end)
				if IsImage and Image:find("VoiceChat", 1, true)
					and (Image:find("Muted", 1, true) or Image:find("Unmuted", 1, true)
						or Image:find("Connecting", 1, true) or Image:find("Error", 1, true)) then
					Found[LocalPlayer.UserId] = Candidate
					break
				end
			end
		end
	end

	-- Remote speaker icons are mapped only through each user's actual bubbleChat
	-- node (BubbleChat_<UserId>/VoiceBubble), never through fuzzy ancestor names.
	for _, Player in ipairs(Players:GetPlayers()) do
		local UserId = tonumber(Player.UserId or Player.userId) or 0
		if UserId > 1 and Player ~= LocalPlayer then
			local DirectObject = FindNativeVoiceBubbleIconObject(Player)
			if DirectObject then Found[UserId] = DirectObject end
		end
	end

	for UserId, Connection in pairs(NativeVoiceIconConnections) do
		local NewObject = Found[UserId]
		if not NewObject or NewObject ~= NativeVoiceIconConnectedObjects[UserId] then
			pcall(function() Connection:Disconnect() end)
			NativeVoiceIconConnections[UserId] = nil
			NativeVoiceIconConnectedObjects[UserId] = nil
		end
	end

	NativeVoiceIconObjects = Found
	NativeVoiceIconImages = {}
	for UserId, Obj in pairs(Found) do
		local Image = nil
		pcall(function() Image = tostring(Obj.Image or "") end)
		NativeVoiceIconImages[UserId] = Image
		if Image and Image ~= "" then
			NativeVoiceIconLastImages[UserId] = Image
			NativeVoiceIconLastSeenAt[UserId] = Now
		end
		if NativeVoiceIconConnectedObjects[UserId] ~= Obj then
			NativeVoiceIconConnectedObjects[UserId] = Obj
			pcall(function()
				NativeVoiceIconConnections[UserId] = Connect(Obj:GetPropertyChangedSignal("Image"), function()
					if NativeVoiceIconObjects[UserId] == Obj then
						local UpdatedImage = tostring(Obj.Image or "")
						NativeVoiceIconImages[UserId] = UpdatedImage
						if UpdatedImage ~= "" then
							NativeVoiceIconLastImages[UserId] = UpdatedImage
							NativeVoiceIconLastSeenAt[UserId] = os.clock()
						end
					end
				end)
			end)
		end
	end
end

ScheduleNativeVoiceMirrorRefresh = function()
	if NativeVoiceScanScheduled then return end
	NativeVoiceScanScheduled = true
	Spawn(function()
		while NativeVoiceScanStamp > 0 and (os.clock() - NativeVoiceScanStamp) < 1.05 do Wait(0.1) end
		NativeVoiceScanScheduled = false
		RefreshNativeVoiceMirrorCache(true)
	end)
end

Protect(function()
	Connect(CoreGui.DescendantAdded, function(Descendant)
		local Name = string.lower(tostring(Descendant.Name or ""))
		if Name:find("voice", 1, true) or Name:find("bubblechat", 1, true) or Name == "insert" or Name:find("speaker", 1, true) then
			ScheduleNativeVoiceMirrorRefresh()
		end
	end)
end)

FindNativeVoiceIcon = function(Player)
	if not Player then return nil end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	local Obj = NativeVoiceIconObjects[UserId]
	if Obj and Obj.Parent then
		local Image = NativeVoiceIconImages[UserId]
		if Image and Image ~= "" then return Image end
	end
	if Player == LocalPlayer then
		local Now = os.clock()
		if not NativeSelfIconProbeStamp or (Now - NativeSelfIconProbeStamp) >= 0.4 then
			NativeSelfIconProbeStamp = Now
			local RobloxGui = CoreGui and CoreGui:FindFirstChild("RobloxGui")
			local Shield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")
			local Button = Shield and Shield:FindFirstChild("MuteSelfButton", true)
			if Button then
				local Candidates = {Button}
				pcall(function() for _, Descendant in ipairs(Button:GetDescendants()) do table.insert(Candidates, Descendant) end end)
				for _, Candidate in ipairs(Candidates) do
					local IsImage, Image = false, ""
					pcall(function() IsImage = Candidate:IsA("ImageLabel") or Candidate:IsA("ImageButton"); Image = tostring(Candidate.Image or "") end)
					if IsImage and Image:find("VoiceChat", 1, true) and (Image:find("Muted", 1, true) or Image:find("Unmuted", 1, true)) then
						NativeVoiceIconLastImages[UserId] = Image
						NativeVoiceIconLastSeenAt[UserId] = Now
						return Image
					end
				end
			end
		end
	end
	if Player ~= LocalPlayer then
		local Last = NativeVoiceIconLastImages[UserId]
		local LastAt = tonumber(NativeVoiceIconLastSeenAt[UserId]) or 0
		if type(Last) == "string" and Last ~= "" and LastAt > 0 and (os.clock() - LastAt) <= 3 then return Last end
	end
	return nil
end

-- Roblox's native voice bubble can keep the same Image asset while changing
-- ImageRectOffset to show the current speech-meter frame. Read the offset live;
-- caching Image alone makes every speaker look like the idle Unmuted0 frame.
GetNativeVoiceMeterLevel = function(Player, NativeImage)
	if not Player or type(NativeImage) ~= "string" then return nil end
	if not NativeImage:find("Unmuted", 1, true) then return nil end

	local UserId = tonumber(Player.UserId or Player.userId) or 0
	local Object = NativeVoiceIconObjects[UserId]
	if not (Object and Object.Parent) and Player ~= LocalPlayer then
		Object = FindNativeVoiceBubbleIconObject(Player)
	end
	if not Object then return nil end

	local Offset, RectSize, AbsoluteSize
	local ReadOk = pcall(function()
		Offset = Object.ImageRectOffset
		RectSize = Object.ImageRectSize
		AbsoluteSize = Object.AbsoluteSize
	end)
	if not ReadOk or not Offset or not RectSize then return nil end

	local FrameX, FrameY = 0, 0
	if Offset.X > 0 then
		local Cell = RectSize.X
		if Cell <= 0 then Cell = math.max(1, (AbsoluteSize and AbsoluteSize.X or 16) * 3) end
		FrameX = math.floor((Offset.X / Cell) + 0.5)
	end
	if Offset.Y > 0 then
		local Cell = RectSize.Y
		if Cell <= 0 then Cell = math.max(1, (AbsoluteSize and AbsoluteSize.Y or 16) * 3) end
		FrameY = math.floor((Offset.Y / Cell) + 0.5)
	end

	-- Voice meter frames are arranged along one axis in the spritesheet. Use
	-- whichever axis has the larger displacement, then map frames 0..5 to 0..100%.
	local FrameIndex = math.max(FrameX, FrameY)
	if FrameIndex <= 0 then return 0 end
	return Clamp(FrameIndex / 5, 0, 1)
end

FindNativePlayerVoice = function(Player)
	local Image = FindNativeVoiceIcon(Player)
	if not Image then return false end
	return Image:find("Unmuted", 1, true) ~= nil or Image:find("Muted", 1, true) ~= nil
end

VoiceContrastIcon = function(Image)
	if Image == nil then return nil end
	Image = tostring(Image)
	Image = Image:gsub("/MicDark/", "/MicLight/")
	Image = Image:gsub("/SpeakerDark/", "/SpeakerLight/")
	if Image == VOICE_ICON_ROOT .. "Muted@3x.png" then return VOICE_MIC_ROOT .. "Muted@3x.png"
	elseif Image == VOICE_ICON_ROOT .. "Connecting@3x.png" then return VOICE_MIC_ROOT .. "Connecting@3x.png"
	elseif Image == VOICE_ICON_ROOT .. "Error@3x.png" then return VOICE_MIC_ROOT .. "Error@3x.png" end
	return Image
end

HasConfirmedPlayerVoice = function(Player)
	if not Player or Player == LocalPlayer or not VoiceGameSupported then return false end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	if UserId <= 1 then return false end
	-- Participant-state evidence is persistent for this join session; speaking
	-- activity itself is time-limited separately so the level meter can return to idle.
	if VoiceEnabledCache[UserId] == true then return true end
	local ActivityStamp = tonumber(VoiceActivityStamp[UserId]) or 0
	if ActivityStamp > 0 and (os.clock() - ActivityStamp) <= 1.25 then return true end
	if GetAudioDeviceInput(Player) then
		VoiceEnabledCache[UserId] = true
		return true
	end
	if FindNativePlayerVoice(Player) then
		VoiceEnabledCache[UserId] = true
		return true
	end
	return false
end

GetVoiceIcon = function(Player, ForcedMuted)
	local UserId = tonumber(Player and (Player.UserId or Player.userId)) or 0
	local IsLocal = Player == LocalPlayer
	local Native = FindNativeVoiceIcon(Player)

	-- A local receive-side mute is displayed as a muted SPEAKER for this row.
	if not IsLocal and (ForcedMuted == true or VoiceMutedPlayers[UserId] == true) then
		return VOICE_SPEAKER_ROOT .. "Muted@3x.png"
	end

	if IsLocal then
		local StateOk, Muted = pcall(function() return GetLocalVoiceMuted() end)
		if StateOk and Muted then return VOICE_MIC_ROOT .. "Muted@3x.png" end
		if not StateOk and type(Native) == "string" and Native:find("Muted", 1, true) then
			return VoiceContrastIcon(Native)
		end
		local Analyzer = GetVoiceAnalyzer(Player)
		if Analyzer then
			local Ok, Level = pcall(function() return tonumber(Analyzer.PeakLevel) end)
			if Ok and Level and Level > 0.00001 then return VoiceUnmutedIcon(Clamp(Level, 0, 1), false) end
		end
		return VOICE_MIC_ROOT .. "Unmuted0@3x.png"
	end

	-- Do not trust VoiceActivityActive by itself: older clients can emit one
	-- positive activity event and never send its matching inactive event.
	local Now = os.clock()
	local ActivityStamp = tonumber(VoiceActivityStamp[UserId]) or 0
	local ActivityAge = ActivityStamp > 0 and (Now - ActivityStamp) or math.huge
	local HasRecentActivity = ActivityAge >= 0 and ActivityAge <= 0.65
	if not HasRecentActivity and VoiceActivityActive[UserId] == true then
		VoiceActivityActive[UserId] = false
		VoiceActivityPeak[UserId] = 0
		VoiceActivityPeakMeasured[UserId] = false
	end

	local Input = GetAudioDeviceInput(Player)
	if Input then
		local InputOk, InputMuted = pcall(function() return Input.Muted == true end)
		if InputOk and InputMuted then return VOICE_SPEAKER_ROOT .. "Muted@3x.png" end
	end

	if HasRecentActivity then
		local Level = GetVoiceLevel(Player)
		if Level <= 0.00001 and VoiceActivityActive[UserId] == true
			and VoiceActivityPeakMeasured[UserId] ~= true then
			Level = 0.35
		end
		return VoiceUnmutedIcon(Level, true)
	end

	local Analyzer = Input and GetVoiceAnalyzer(Player) or nil
	if Analyzer then
		local Ok, Level = pcall(function() return tonumber(Analyzer.PeakLevel) end)
		if Ok and Level and Level > 0.00001 then
			return VoiceUnmutedIcon(Clamp(Level, 0, 1), true)
		end
	end

	-- Preserve the native bubble's actual meter frame (Unmuted20/40/60/80/100)
	-- while switching it to the speaker sprite family for this local listener.
	if type(Native) == "string" and Native ~= "" then
		if Native:find("Muted", 1, true) then return VOICE_SPEAKER_ROOT .. "Muted@3x.png" end
		if Native:find("Connecting", 1, true) then return VOICE_SPEAKER_ROOT .. "Connecting@3x.png" end
		if Native:find("Error", 1, true) then return VOICE_SPEAKER_ROOT .. "Muted@3x.png" end
		if Native:find("Unmuted", 1, true) then
			local NativeLevel = GetNativeVoiceMeterLevel(Player, Native)
			if NativeLevel and NativeLevel > 0.00001 then
				return VoiceUnmutedIcon(NativeLevel, true)
			end
			local Percent = Native:match("Unmuted(%d+)@3x%.png")
			if Percent and (Percent == "0" or Percent == "20" or Percent == "40" or Percent == "60" or Percent == "80" or Percent == "100") then
				return VOICE_SPEAKER_ROOT .. "Unmuted" .. Percent .. "@3x.png"
			end
			return VOICE_SPEAKER_ROOT .. "Unmuted0@3x.png"
		end
	end

	-- A quiet but positively confirmed voice participant gets the idle frame.
	return VOICE_SPEAKER_ROOT .. "Unmuted0@3x.png"
end

VoiceProcessActivityInfo = function(ActivityInfo)
	if type(ActivityInfo) ~= "table" then return end
	local Nested = ActivityInfo.activityInfo or ActivityInfo.ActivityInfo or ActivityInfo.activity or ActivityInfo.Activity
	if type(Nested) == "table" then
		local Merged = {}
		for Key, Value in next, ActivityInfo do Merged[Key] = Value end
		for Key, Value in next, Nested do if Merged[Key] == nil then Merged[Key] = Value end end
		ActivityInfo = Merged
	end

	local UserId = tonumber(
		ActivityInfo.userId
		or ActivityInfo.UserId
		or ActivityInfo.playerUserId
		or ActivityInfo.PlayerUserId
		or ActivityInfo.participantUserId
		or ActivityInfo.ParticipantUserId
		or ActivityInfo.participantId
		or ActivityInfo.ParticipantId
		or ActivityInfo.playerId
		or ActivityInfo.PlayerId
		or ActivityInfo.speakerUserId
		or ActivityInfo.SpeakerUserId
		or ActivityInfo.user_id
		or ActivityInfo.player_user_id
		or ActivityInfo.UserID
		or ActivityInfo.userID
		or ActivityInfo.id
		or ActivityInfo.Id
	)
	if not UserId then
		local PlayerValue = ActivityInfo.player or ActivityInfo.Player
		if typeof(PlayerValue) == "Instance" then
			Protect(function() UserId = PlayerValue.UserId end)
		elseif type(PlayerValue) == "number" then
			UserId = PlayerValue
		elseif type(PlayerValue) == "string" then
			UserId = tonumber(PlayerValue)
		end
	end
	if not UserId then return end

	local ActivityPlayer = nil
	pcall(function() ActivityPlayer = Players:GetPlayerByUserId(UserId) end)
	if ActivityPlayer then
		local WasKnown = VoiceEnabledCache[UserId] == true
		VoiceEnabledCache[UserId] = true
		VoiceCheckError[UserId] = nil
		if not WasKnown and RebuildPlayersPage then RebuildPlayersPage() end
	end

	local Speaking = ActivityInfo.active
	if Speaking == nil then Speaking = ActivityInfo.Active end
	if Speaking == nil then Speaking = ActivityInfo.isSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.IsSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.is_speaking end
	if Speaking == nil then Speaking = ActivityInfo.speaking end
	if Speaking == nil then Speaking = ActivityInfo.Speaking end
	if Speaking == nil then Speaking = ActivityInfo.isActive end
	if Speaking == nil then Speaking = ActivityInfo.IsActive end
	if Speaking == nil then Speaking = ActivityInfo.isMicActive end
	if Speaking == nil then Speaking = ActivityInfo.IsMicActive end
	if Speaking == nil then Speaking = ActivityInfo.isVoiceActive end
	if Speaking == nil then Speaking = ActivityInfo.IsVoiceActive end
	if Speaking == nil then Speaking = ActivityInfo.isTalking end
	if Speaking == nil then Speaking = ActivityInfo.IsTalking end
	if Speaking == nil then Speaking = ActivityInfo.talking end
	if Speaking == nil then Speaking = ActivityInfo.isSpeakingNow end
	if Speaking == nil then Speaking = ActivityInfo.SpeakingNow end

	if Speaking == false then
		VoiceActivityPeak[UserId] = 0
		VoiceActivityStamp[UserId] = 0
		VoiceActivityActive[UserId] = false
		VoiceActivityPeakMeasured[UserId] = false
		return
	end

	local Peak = nil
	for _, Key in ipairs({
		"peakLevel", "PeakLevel", "peak", "Peak", "level", "Level",
		"loudness", "Loudness", "volume", "Volume", "micLevel", "MicLevel",
		"peak_level", "micPeak", "MicPeak", "voiceLevel", "VoiceLevel",
		"rmsLevel", "RmsLevel", "rms", "Rms", "activityLevel", "ActivityLevel",
		"audioLevel", "AudioLevel", "amplitude", "Amplitude"
	}) do
		local Value = tonumber(ActivityInfo[Key])
		if Value ~= nil then Peak = Value; break end
	end

	if Peak ~= nil then
		if Peak > 1 and Peak <= 100 then Peak = Peak / 100 end
		Peak = Clamp(Peak, 0, 1)
		if Peak > 0.00001 then
			-- Keep the latest real peak and timestamp. The row refresh loop reads
			-- this value at 5 Hz and maps it to the 20/40/60/80/100 speaker frames.
			VoiceActivityPeak[UserId] = Peak
			VoiceActivityStamp[UserId] = os.clock()
			VoiceActivityActive[UserId] = true
			VoiceActivityPeakMeasured[UserId] = true
			return
		elseif Speaking == true then
			-- Some legacy clients report active=true while peak is zero. Give the
			-- speaker a modest level rather than pinning it to Unmuted0.
			VoiceActivityPeak[UserId] = 0.35
			VoiceActivityStamp[UserId] = os.clock()
			VoiceActivityActive[UserId] = true
			VoiceActivityPeakMeasured[UserId] = false
			return
		elseif Speaking == false then
			VoiceActivityPeak[UserId] = 0
			VoiceActivityStamp[UserId] = 0
			VoiceActivityActive[UserId] = false
			VoiceActivityPeakMeasured[UserId] = false
			return
		else
			-- Activity feeds can send zero-level samples between positive peaks.
			-- Do not erase a just-received real peak immediately; hold it briefly
			-- so the UI can display the current frame. Zero does NOT refresh time.
			local PreviousStamp = tonumber(VoiceActivityStamp[UserId]) or 0
			local PreviousPeak = tonumber(VoiceActivityPeak[UserId]) or 0
			if PreviousStamp > 0 and PreviousPeak > 0
				and (os.clock() - PreviousStamp) <= 0.65 then
				return
			end
			VoiceActivityPeak[UserId] = 0
			VoiceActivityStamp[UserId] = 0
			VoiceActivityActive[UserId] = false
			VoiceActivityPeakMeasured[UserId] = false
			return
		end
	end

	if Speaking == true then
		VoiceActivityPeak[UserId] = 0.35
		VoiceActivityStamp[UserId] = os.clock()
		VoiceActivityActive[UserId] = true
		VoiceActivityPeakMeasured[UserId] = false
	elseif Speaking == false then
		VoiceActivityPeak[UserId] = 0
		VoiceActivityStamp[UserId] = 0
		VoiceActivityActive[UserId] = false
		VoiceActivityPeakMeasured[UserId] = false
	end
end

RefreshVoiceParticipants = function()
	-- Keep participant discovery active when the local client is disconnected.
	if not VoiceGameSupported then return false end
	local PlayerList = Players:GetPlayers()
	local Changed = false

	-- GetChatGroupsAsync is server-only. Discover active participants from the
	-- client through actual AudioDeviceInput/native UI/internal participant data.

	for _, Player in next, PlayerList do
		if Player ~= LocalPlayer and GetAudioDeviceInput(Player) then
			local Id = tonumber(Player.UserId or Player.userId) or 0
			if Id > 1 and VoiceEnabledCache[Id] ~= true then
				VoiceEnabledCache[Id] = true
				VoiceCheckError[Id] = nil
				Changed = true
			end
		end
	end

	if VoiceChatInternal then
		Protect(function()
			local Participants = VoiceChatInternal:GetParticipants()
			if type(Participants) == "table" then
				for Key, Participant in next, Participants do
					local Id = nil
					local KeyId = tonumber(Key)
					if KeyId and KeyId > 1000 then Id = KeyId end
					if not Id and type(Participant) == "number" then
						Id = Participant
					elseif not Id and type(Participant) == "string" then
						Id = tonumber(Participant)
					elseif not Id and type(Participant) == "table" then
						Id = tonumber(Participant.UserId or Participant.userId or Participant.PlayerUserId or Participant.playerUserId or Participant.Id or Participant.id)
						if not Id and Participant.Player then
							Id = tonumber(Participant.Player.UserId or Participant.Player.userId)
						end
					end
					if Id and Id > 1 and Id ~= LocalPlayer.UserId and VoiceEnabledCache[Id] ~= true then
						VoiceEnabledCache[Id] = true
						VoiceCheckError[Id] = nil
						Changed = true
					end
				end
			end
		end)
	end

	-- Native Roblox player voice icons are a high-confidence signal, but the
	-- expensive CoreGui scan is performed only when the page is rebuilt/opened.
	for _, Player in next, PlayerList do
		if Player ~= LocalPlayer then
			local Id = tonumber(Player.UserId or Player.userId) or 0
			if Id > 1 and VoiceEnabledCache[Id] ~= true and FindNativePlayerVoice(Player) then
				VoiceEnabledCache[Id] = true
				VoiceCheckError[Id] = nil
				Changed = true
			end
		end
	end

	return Changed
end

GetPlayerVoiceStatus = function(Player)
	if not Player then return nil end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	if UserId <= 1 then return false end
	if not VoiceGameSupported then
		if Player == LocalPlayer then return false end
		return nil
	end

	if Player == LocalPlayer then
		local Ok, Enabled = pcall(function()
			return VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId) == true
		end)
		if Ok then return Enabled end
		if VoiceChatInternal then
			local InternalOk, InternalEnabled = pcall(function()
				return VoiceChatInternal:IsContextVoiceEnabled() == true
			end)
			if InternalOk then return InternalEnabled end
		end
		return nil
	end

	-- Client builds reject eligibility queries for other users. Treat missing
	-- evidence as unknown, not as "no voice"; keep the player-row control visible
	-- until an input/native bubble/activity event confirms voice participation.
	if VoiceEnabledCache[UserId] == true then return true end
	if GetAudioDeviceInput(Player) then return true end
	if FindNativePlayerVoice(Player) then
		VoiceEnabledCache[UserId] = true
		return true
	end
	if VoiceEnabledCache[UserId] == false then return false end
	return nil
end

CheckVoiceForPlayer = function(Player, Callback)
	local UserId = tonumber(Player and (Player.UserId or Player.userId)) or 0
	if UserId <= 1 or not VoiceGameSupported then
		if Callback then Callback(false, false) end
		return
	end

	local Status = GetPlayerVoiceStatus(Player)
	if Status == true then
		local Was = VoiceEnabledCache[UserId] == true
		VoiceEnabledCache[UserId] = true
		VoiceCheckError[UserId] = nil
		if Callback then Callback(true, false, not Was) end
		return
	end

	if Status == false then
		local Was = VoiceEnabledCache[UserId] == true
		local HasNative = FindNativePlayerVoice(Player)
		local HasInput = GetAudioDeviceInput(Player) ~= nil
		if HasNative or HasInput then
			VoiceEnabledCache[UserId] = true
			VoiceCheckError[UserId] = nil
			if Callback then Callback(true, false, not Was) end
		else
			-- A successful false result is an eligibility answer, not a warning.
			VoiceEnabledCache[UserId] = false
			VoiceCheckError[UserId] = nil
			if Callback then Callback(false, false, Was) end
		end
		return
	end

	-- If status cannot be queried on this client, do not label the player as
	-- having an error. Keep them hidden until native voice evidence appears.
	VoiceCheckError[UserId] = nil
	if Callback then Callback(VoiceEnabledCache[UserId] == true, true) end
end

-- Voice-mute diagnostic panel and verbose logging removed.

GetLocalVoiceMuted = function()
	-- When Roblox supplies its real AudioDeviceInput, that is the authoritative
	-- mute state for the Audio API path. Do not let a stale legacy pause flag
	-- override a confirmed Input.Muted = false (that made Unmute appear broken).
	local Input = GetAudioDeviceInput(LocalPlayer)
	if Input then
		local Ok, Muted = pcall(function()
			return Input.Muted == true
		end)
		if Ok then return Muted end
	end

	-- Only rely on the legacy voice publisher if no readable real input exists.
	if VoiceChatInternal then
		local Ok, Muted = pcall(function()
			return VoiceChatInternal:IsPublishPaused() == true
		end)
		if Ok then return Muted end
	end
	return LocalVoiceMuted == true
end

FindNativeMuteSelfButton = function()
	local RobloxGui = nil
	pcall(function()
		RobloxGui = CoreGui and CoreGui:FindFirstChild("RobloxGui")
	end)
	if not RobloxGui then
		return nil, "CoreGui.RobloxGui not found"
	end

	-- Prefer the exact native Settings page path reported by the user.
	local PathParts = {
		"SettingsClippingShield", "SettingsShield", "MenuContainer", "Page",
		"PageViewClipper", "PageView", "PageViewInnerFrame", "Players",
		"Holder", "MuteSelfButton",
	}
	local Object = RobloxGui
	for _, Name in ipairs(PathParts) do
		if not Object then break end
		local Ok, Child = pcall(function() return Object:FindFirstChild(Name) end)
		Object = (Ok and Child) or nil
	end
	if Object then
		local IsButtonOk, IsButton = pcall(function() return Object:IsA("GuiButton") end)
		if IsButtonOk and IsButton then
			return Object, "exact SettingsClippingShield path"
		end
	end

	-- CoreGui's menu hierarchy can differ slightly between client builds.
	-- Search the Settings shield first, then RobloxGui, using the exact button name.
	local SearchRoots = {}
	local SettingsRoot = RobloxGui:FindFirstChild("SettingsClippingShield")
	if SettingsRoot then table.insert(SearchRoots, SettingsRoot) end
	table.insert(SearchRoots, RobloxGui)
	-- Some client builds host/reparent the Settings shield outside RobloxGui.
	-- Search CoreGui once as a final fallback, but only on a manual mic click.
	if CoreGui then table.insert(SearchRoots, CoreGui) end
	for _, Root in ipairs(SearchRoots) do
		local Ok, Descendants = pcall(function() return Root:GetDescendants() end)
		if Ok and type(Descendants) == "table" then
			for _, Descendant in ipairs(Descendants) do
				if Descendant.Name == "MuteSelfButton" then
					local IsButtonOk, IsButton = pcall(function() return Descendant:IsA("GuiButton") end)
					if IsButtonOk and IsButton then
						return Descendant, "recursive fallback from " .. tostring(Root.Name)
					end
				end
			end
		end
	end
	return nil, "MuteSelfButton not present in RobloxGui Settings tree"
end

NativeMuteSelfButtonMatchesTarget = function(TargetMuted, Stage, Button)
	Wait(0.20)
	local StateOk, StateMuted = pcall(function() return GetLocalVoiceMuted() end)
	local PauseOk, Paused = false, "unavailable"
	if VoiceChatInternal then
		PauseOk, Paused = pcall(function() return VoiceChatInternal:IsPublishPaused() == true end)
	end
	local NativeIcon = nil
	pcall(function() NativeIcon = FindNativeVoiceIcon(LocalPlayer) end)
	local IconMuted = nil
	if type(NativeIcon) == "string" then
		if NativeIcon:find("Unmuted", 1, true) then
			IconMuted = false
		elseif NativeIcon:find("Muted", 1, true) then
			IconMuted = true
		end
	end
	local Input = nil
	pcall(function() Input = GetAudioDeviceInput(LocalPlayer) end)
	local InputReadOk, InputMuted = false, nil
	if Input then
		InputReadOk, InputMuted = pcall(function() return Input.Muted == true end)
	end
	local StateMatches = StateOk and StateMuted == TargetMuted
	local NativeEvidenceMatches = (IconMuted ~= nil and IconMuted == TargetMuted)
		or (InputReadOk and InputMuted == TargetMuted)
	local Verified = StateMatches and NativeEvidenceMatches
	if Verified then
		LocalVoiceMuted = TargetMuted
		return true
	end
	if StateMatches and not NativeEvidenceMatches then
	end
	return false
end

TryRealNativeMuteButtonClick = function(Button, TargetMuted)
	-- Deliberately disabled: synthesizing clicks against a closed CoreGui menu
	-- caused ESC state corruption and never verified the native voice change.
	return false
end

InvokeNativeMuteSelfButton = function(TargetMuted)
	TargetMuted = TargetMuted == true
	local MenuReadOk, MenuIsOpen = pcall(function() return GuiService.MenuIsOpen end)
	local Button, FoundBy = FindNativeMuteSelfButton()

	local function Refuse(Reason)
		return false
	end

	if not MenuReadOk or MenuIsOpen ~= true then
		return Refuse("native CoreGui menu is not already open; do not open/close it from the mic callback")
	end
	if not Button then
		return Refuse("MuteSelfButton was not found while native menu is open")
	end

	local VisibleOk, Visible = pcall(function() return Button.Visible end)
	local ActiveOk, Active = pcall(function() return Button.Active end)
	local InteractableOk, Interactable = pcall(function() return Button.Interactable end)
	local AncestorsReady = true
	local Cursor = Button.Parent
	while Cursor and Cursor ~= CoreGui do
		local IsGuiOk, IsGui = pcall(function() return Cursor:IsA("GuiObject") end)
		if IsGuiOk and IsGui then
			local ReadOk, IsVisible = pcall(function() return Cursor.Visible end)
			if not ReadOk or not IsVisible then AncestorsReady = false; break end
		end
		local ParentOk, Parent = pcall(function() return Cursor.Parent end)
		if not ParentOk then AncestorsReady = false; break end
		Cursor = Parent
	end

	local PosOk, Pos = pcall(function() return Button.AbsolutePosition end)
	local SizeOk, Size = pcall(function() return Button.AbsoluteSize end)
	local Camera = nil
	pcall(function() Camera = workspace.CurrentCamera end)
	local Viewport = Vector2.new(0, 0)
	pcall(function() if Camera then Viewport = Camera.ViewportSize end end)
	local X, Y, OnScreen = -1, -1, false
	if PosOk and SizeOk then
		X = math.floor(Pos.X + Size.X / 2)
		Y = math.floor(Pos.Y + Size.Y / 2)
		OnScreen = Size.X > 2 and Size.Y > 2 and X >= 0 and Y >= 0 and X < Viewport.X and Y < Viewport.Y
	end

	if not (VisibleOk and Visible and ActiveOk and Active and AncestorsReady and OnScreen) then
		return Refuse("native button is not naturally visible, active, and on-screen")
	end
	if InteractableOk and Interactable == false then
		return Refuse("native button Interactable=false")
	end

	local VIM = nil
	pcall(function() VIM = game:GetService("VirtualInputManager") end)
	if not VIM then return Refuse("VirtualInputManager unavailable; no verified input route") end

	local ClickOk, ClickErr = pcall(function()
		VIM:SendMouseMoveEvent(X, Y, game)
		Wait(0.04)
		VIM:SendMouseButtonEvent(X, Y, 0, true, game, 0)
		Wait(0.05)
		VIM:SendMouseButtonEvent(X, Y, 0, false, game, 0)
	end)
	if not ClickOk then return Refuse("VirtualInputManager click failed: " .. tostring(ClickErr)) end

	local Verified = NativeMuteSelfButtonMatchesTarget(TargetMuted, "native-menu-direct-click-no-transaction", Button)
	if Verified then
		if Hub then Hub.NativeMuteTransactionFailedThisClick = false end
		return true
	end
	return Refuse("input call returned but native mute state did not verify; no additional synthetic click or PublishPause fallback")
end

SetLocalVoiceMuted = function(Muted)
	Muted = Muted == true
	local InputFindOk, Input = pcall(function() return GetAudioDeviceInput(LocalPlayer) end)

	-- Preferred path for the enabled Audio API: change the real Roblox input.
	if Input then
		local WriteOk, ReadBack = pcall(function()
			Input.Muted = Muted
			return Input.Muted == true
		end)
		if WriteOk and ReadBack == Muted then
			LocalVoiceMuted = Muted
			if VoiceChatInternal then pcall(function() VoiceChatInternal:PublishPause(Muted) end) end
			return true
		end
	end

	-- If the user already has the real Roblox menu open, try its actual button.
	-- Never synthesize Escape/open-close cycles from this callback: they broke ESC.
	local MenuReadOk, MenuIsOpen = pcall(function() return GuiService.MenuIsOpen end)
	if MenuReadOk and MenuIsOpen == true then
		local NativeCallOk, NativeApplied = pcall(function() return InvokeNativeMuteSelfButton(Muted) end)
		if NativeCallOk and NativeApplied then
			LocalVoiceMuted = Muted
			return true
		end
	end

	-- This client reports UseAudioApi=Automatic, which currently uses Roblox's
	-- legacy internal voice system. PublishPause is its actual publishing-pause
	-- control; it changes the native internal state without needing a GUI click.
	-- We log the state match honestly, but do not claim that remote listeners heard
	-- audio: this client exposes no AudioDeviceInput/audio peak for that verification.
	if VoiceChatInternal then
		local CallOk, CallResult = pcall(function() return VoiceChatInternal:PublishPause(Muted) end)
		Wait(0.1)
		local ReadOk, PauseAfter = pcall(function() return VoiceChatInternal:IsPublishPaused() == true end)
		if ReadOk and PauseAfter == Muted then
			LocalVoiceMuted = Muted
			return true
		end
	end
	return false
end

RefreshLocalVoiceState = function()
	local Entitled = false
	local Success = false
	Success = Protect(function()
		Entitled = VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId) == true
		return true
	end)
	if not Success and VoiceChatInternal then
		Success = Protect(function()
			Entitled = VoiceChatInternal:IsContextVoiceEnabled() == true
			return true
		end)
	end
	LocalVoiceEnabled = VoiceChatEnabled and Entitled
	VoiceEnabledCache[LocalPlayer.UserId] = Entitled
	VoiceCheckError[LocalPlayer.UserId] = not Success
	if LocalVoiceEnabled then
		EnsureVoiceAnalyzer(LocalPlayer)
		LocalVoiceMuted = GetLocalVoiceMuted()
	else
		LocalVoiceMuted = false
	end
	return LocalVoiceEnabled
end

GetLocalVoiceGroupId = function()
	-- This is only a group identifier, NOT proof that a voice session has joined.
	local GroupId = ""
	if VoiceChatInternal then
		pcall(function() GroupId = tostring(VoiceChatInternal:GetGroupId() or "") end)
	end
	return GroupId
end

VoiceInternalConnectionState = nil
VoiceInternalStateConnection = nil
GetVoiceInternalStateText = function()
	-- Read the live state first; use the last StateChanged event only as fallback.
	if VoiceChatInternal then
		local Ok, State = pcall(function() return VoiceChatInternal.VoiceChatState end)
		if Ok and State ~= nil then return tostring(State) end
	end
	if VoiceInternalConnectionState ~= nil and tostring(VoiceInternalConnectionState) ~= "" then
		return tostring(VoiceInternalConnectionState)
	end
	return "unavailable"
end
if VoiceChatInternal then
	pcall(function()
		local State = VoiceChatInternal.VoiceChatState
		if State ~= nil then VoiceInternalConnectionState = tostring(State) end
	end)
	pcall(function()
		VoiceInternalStateConnection = VoiceChatInternal.StateChanged:Connect(function(OldState, NewState)
			VoiceInternalConnectionState = tostring(NewState)
		end)
	end)
end

IsLocalVoiceConnectionReady = function()
	-- A non-empty GetGroupId (especially the literal "default") is NOT enough
	-- to prove a real session exists. Use the actual legacy session state, or
	-- the real AudioDeviceInput when the Audio API is enabled.
	local Input = GetAudioDeviceInput(LocalPlayer)
	if Input then
		local Ok, Ready = pcall(function() return Input.IsReady == true end)
		if Ok and Ready then return true end
		local ActiveOk, Active = pcall(function() return Input.Active == true end)
		if ActiveOk and Active then return true end
	end

	local StateText = GetVoiceInternalStateText()
	local StateLower = string.lower(StateText)
	if StateLower:find("joined", 1, true) or StateLower:find("connected", 1, true) then
		return true
	end

	-- Conservative fallback: real participants imply an active legacy session.
	if VoiceChatInternal then
		local Ok, Participants = pcall(function() return VoiceChatInternal:GetParticipants() end)
		if Ok and type(Participants) == "table" and #Participants > 0 then return true end
	end

	-- States like Idle, Joining, Failed, Leaving and Ended are not connected.
	return false
end

VoiceMuteBeforeDisconnect = nil

SetVoiceChatPreference = function(Enabled)
	if not VoiceOptionAvailable then return false end
	Enabled = Enabled == true
	VoiceCheckNext = {}
	VoiceChatDesiredOn = Enabled

	if not Enabled then
		VoiceConnectionAttempting = false
		VoiceChatEnabled = false
		LocalVoiceEnabled = false
		if VoiceChatInternal then
			local GroupId = GetLocalVoiceGroupId()
			if GroupId ~= "" then SavedVoiceGroupId = GroupId end
			pcall(function() VoiceChatInternal:Leave() end)
		end
		if VoiceChatSelector then
			pcall(function() VoiceChatSelector:SetSelectionIndex(2, false) end)
		end
		if RebuildPlayersPage then RebuildPlayersPage() end
		if ConfigureMobileActionButtons then ConfigureMobileActionButtons() end
		return true
	end

	-- Show the voice controls immediately after On is selected. The connected
	-- state probe is not consistently readable in every Roblox client revision.
	VoiceChatEnabled = true
	LocalVoiceEnabled = VoiceOptionAvailable == true
	VoiceConnectionAttempting = true
	RefreshLocalVoiceState()
	if VoiceChatSelector then
		pcall(function() VoiceChatSelector:SetSelectionIndex(1, false) end)
	end
	if RebuildPlayersPage then RebuildPlayersPage() end
	if ConfigureMobileActionButtons then ConfigureMobileActionButtons() end

	local GroupId = SavedVoiceGroupId or GetLocalVoiceGroupId()
	local JoinRequested = false
	if VoiceChatInternal then
		if GroupId ~= "" then
			local JoinOk, JoinResult = pcall(function()
				return VoiceChatInternal:JoinByGroupId(GroupId, false)
			end)
			JoinRequested = JoinOk and JoinResult == true
			if JoinRequested then SavedVoiceGroupId = GroupId end
		end
		if not JoinRequested then
			local JoinOk, JoinResult = pcall(function()
				if type(VoiceChatInternal.Join) == "function" then
					return VoiceChatInternal:Join()
				end
				return false
			end)
			JoinRequested = JoinOk and JoinResult == true
		end
	end

	Spawn(function()
		local Connected = false
		for _ = 1, 20 do
			if not VoiceChatDesiredOn then
				VoiceConnectionAttempting = false
				return
			end
			if IsLocalVoiceConnectionReady() then
				Connected = true
				break
			end
			Wait(0.5)
		end

		VoiceConnectionAttempting = false
		-- Keep controls available if Roblox temporarily fails to establish a native session;
		-- connection state never hides the voice controls.
		VoiceChatEnabled = VoiceChatDesiredOn
		if Connected then RefreshLocalVoiceState() end
		if VoiceChatSelector then
			pcall(function() VoiceChatSelector:SetSelectionIndex(VoiceChatDesiredOn and 1 or 2, false) end)
		end
		if RebuildPlayersPage then RebuildPlayersPage() end
		if ConfigureMobileActionButtons then ConfigureMobileActionButtons() end
	end)

	return true
end

GetRemoteVoiceMuted = function(Player)
	if not Player or Player == LocalPlayer then return false end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	if UserId <= 1 then return false end
	-- Store BOTH true and false as explicit local-listener choices. Clearing the
	-- false value made an Unmute click fall back to stale native state and flip
	-- the icon back to Muted.
	if VoiceMutedPlayers[UserId] ~= nil then
		return VoiceMutedPlayers[UserId] == true
	end
	if VoiceChatInternal then
		local Ok, Value = pcall(function()
			return VoiceChatInternal:IsSubscribePaused(UserId) == true
		end)
		if Ok then
			VoiceMutedPlayers[UserId] = Value
			return Value
		end
	end
	return false
end

SetRemoteVoiceMuted = function(Player, Muted)
	if not Player then return false end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	if UserId <= 1 or Player == LocalPlayer then return false end
	Muted = Muted == true

	local Changed = false
	if VoiceChatInternal then
		local CallOk, CallResult = pcall(function()
			return VoiceChatInternal:SubscribePause(UserId, Muted)
		end)
		local ReadOk, ReadBack = pcall(function()
			return VoiceChatInternal:IsSubscribePaused(UserId) == true
		end)
		if ReadOk then
			Changed = ReadBack == Muted or CallResult == true
		elseif CallOk then
			Changed = CallResult ~= false
		end
	end

	-- This is a receive-side choice for this client, not a mute of the remote
	-- player's microphone. Preserve the user's chosen UI state even when this
	-- client build doesn't expose a readable SubscribePause acknowledgement.
	VoiceMutedPlayers[UserId] = Muted
	VoiceSavedMuted[UserId] = nil
	return Changed
end

SetMuteAll = function(Muted)
	Muted = Muted == true
	VoiceMuteAllActive = Muted

	-- Ask Roblox's receive controller to mute/unmute all remote subscriptions.
	-- Then also set per-player state so the individual icons and buttons mirror
	-- the same choice and can subsequently override one player independently.
	local BulkApplied = false
	if VoiceChatInternal then
		local CallOk, CallResult = pcall(function()
			return VoiceChatInternal:SubscribePauseAll(Muted)
		end)
		BulkApplied = CallOk
	end

	for _, Player in next, Players:GetPlayers() do
		if Player ~= LocalPlayer then
			local UserId = tonumber(Player.UserId or Player.userId) or 0
			if UserId > 1 then
				local Applied = SetRemoteVoiceMuted(Player, Muted)
				if not Applied and BulkApplied then
					-- The aggregate controller succeeded even if a per-player state
					-- readback is unavailable in this client build.
					VoiceMutedPlayers[UserId] = Muted
					VoiceSavedMuted[UserId] = nil
				end
			end
		end
	end

	-- Refresh currently visible remote-mic icons immediately.
	if PlayersPage and PlayersPage.Frame then
		for _, Player in next, Players:GetPlayers() do
			if Player ~= LocalPlayer then
				local Row = PlayersPage.Frame:FindFirstChild("PlayerLabel" .. Player.Name)
				local VoiceButton = Row and Row:FindFirstChild(Player.Name .. "VoiceButton")
				local VoiceIcon = VoiceButton and VoiceButton:FindFirstChild("VoiceIcon")
				if VoiceIcon then
					VoiceIcon.Image = VoiceContrastIcon(GetVoiceIcon(Player, GetRemoteVoiceMuted(Player)))
				end
			end
		end
	end
end

LocalVoiceEnabled = false
LocalVoiceMuted = false
RefreshLocalVoiceState()

LocalVoiceInput = GetAudioDeviceInput(LocalPlayer)
if LocalVoiceInput then
	Protect(function()
		LocalVoiceMuted = LocalVoiceInput.Muted == true
	end)
	EnsureVoiceAnalyzer(LocalPlayer)
end

-- ============================================================
-- PLAYER LIST
-- ============================================================

GetHeadshot = function(Player)

	return "rbxthumb://type=Avatar&id="
		.. tostring(
			math.max(
				1,
				Player.UserId
				or Player.userId
				or 1
			)
		)
		.. "&w=100&h=100"

end

RebuildPlayersPage = nil

MakePlayerRow = function(
	Page,
	Player,
	Index
)

	local Row =
		Create(
			"ImageLabel",
			{
				Name =
					"PlayerLabel"
					.. Player.Name,

				Parent =
					Page.Frame,

				BackgroundTransparency =
					1,

				Image =
					"rbxasset://textures/ui/dialog_white.png",

				ImageTransparency =
					0.85,

				ScaleType =
					Enum.ScaleType.Slice,

				SliceCenter =
					Rect.new(
						10,
						10,
						10,
						10
					),

				Size =
					UDim2.new(1, 0, 0, 62),

				Position =
					UDim2.new(
						0,
						0,
						0,
						PLAYER_LIST_OFFSET
						+ (
							(Index - 1)
							* 80
						)
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	Connect(
		Row.MouseEnter,
		function()
			Row.ImageTransparency =
				0.65
		end
	)

	Connect(
		Row.MouseLeave,
		function()
			Row.ImageTransparency =
				0.85
		end
	)

	Create(
		"ImageLabel",
		{
			Name =
				"Icon",

			Parent =
				Row,

			BackgroundTransparency =
				1,

			Image =
				GetHeadshot(
					Player
				),

			Size =
				UDim2.new(
					0,
					36,
					0,
					36
				),

			Position =
				UDim2.new(
					0,
					12,
					0.5,
					-18
				),

			ScaleType =
				Enum.ScaleType.Fit,

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 3,
		}
	)

	if DisplayNameSupport then

		Create(
			"TextLabel",
			{
				Name =
					"DisplayNameLabel",

				Parent =
					Row,

				BackgroundTransparency =
					1,

				Font =
					Enum.Font.SourceSans,

				TextSize =
					36,

				TextColor3 =
					Color3.new(
						1,
						1,
						1
					),

				TextXAlignment =
					Enum.TextXAlignment.Left,

				Text =
					Player.DisplayName
					or Player.Name,

				Size =
					UDim2.new(0, 0, 0, 0),

Position =
					UDim2.new(0, IsMobile and 80 or 60, 0.5, -10),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

		Create(
			"TextLabel",
			{
				Name =
					"NameLabel",

				Parent =
					Row,

				BackgroundTransparency =
					1,

				Font =
					Enum.Font.SourceSans,

				TextSize =
					24,

				TextColor3 = Color3.fromRGB(162, 162, 162),

				TextXAlignment =
					Enum.TextXAlignment.Left,

				Text =
					"@"
					.. Player.Name,

				Size =
					UDim2.new(0, 0, 0, 0),

Position =
					UDim2.new(0, IsMobile and 80 or 60, 0.5, 12),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	else

		Create(
			"TextLabel",
			{
				Name =
					"NameLabel",

				Parent =
					Row,

				BackgroundTransparency =
					1,

				Font =
					Enum.Font.SourceSans,

				TextSize =
					24,

				TextColor3 =
					Color3.new(
						1,
						1,
						1
					),

				TextXAlignment =
					Enum.TextXAlignment.Left,

				Text =
					Player.Name,

				Size =
					UDim2.new(
						1,
						-330,
						1,
						0
					),

				Position =
					UDim2.new(
						0,
						60,
						0,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	end

	local UserId =
		tonumber(
			Player.UserId
			or Player.userId
		)
		or 0

	local IsSelf =
		Player == LocalPlayer

	local CanTargetPlayer =
		(not IsSelf)
		and UserId > 1

	local BUTTON_WIDTH = 46
	local BUTTON_HEIGHT = 46
	local GAP = 12
	local FRIEND_WIDTH = 156
	local ACTION_RIGHT_PAD = 14
	local SELF_VIEW_RIGHT_PAD = 14

	local VoiceButton
	local ViewButton
	local ReportButton
	local BlockButton
	local FriendButton
	local FriendLabel

	local PositionPlayerActionButtons = function(HasVoice)
		if not CanTargetPlayer then return end
		local Right = 0
		local Step = BUTTON_WIDTH + GAP
		if FriendButton then
			FriendButton.Size = UDim2.fromOffset(FRIEND_WIDTH, BUTTON_HEIGHT)
			FriendButton.Position = UDim2.new(1, -(FRIEND_WIDTH + ACTION_RIGHT_PAD), 0.5, -BUTTON_HEIGHT / 2)
			Right = FRIEND_WIDTH + GAP
		end
		local function Place(Button)
			if not Button then return end
			Button.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
			Button.Position = UDim2.new(1, -(Right + BUTTON_WIDTH + ACTION_RIGHT_PAD), 0.5, -BUTTON_HEIGHT / 2)
			Right += Step
		end
		Place(BlockButton)
		Place(ReportButton)
		Place(ViewButton)
		if HasVoice then Place(VoiceButton) end
	end

	if UserId > 1 then

		ViewButton =
			MakeStyledButton(
				Player.Name
					.. "ViewButton",
				"",
				UDim2.new(
					0,
					BUTTON_WIDTH,
					0,
					BUTTON_HEIGHT
				),
				function()

					local TargetUserId =
						tonumber(
							Player.UserId
							or Player.userId
						)
						or 0

					if TargetUserId <= 0 then
						return
					end

					if OpenReportPlayer then
						-- no-op
					end

					local Success =
						Protect(
							function()

								GuiService:
									InspectPlayerFromUserId(
										TargetUserId
									)

							end
						)

					if not Success then

						Protect(
							function()

								StarterGui:SetCore(
									"InspectPlayerFromUserId",
									TargetUserId
								)

							end
						)

					end

				end
			)

		ViewButton.Parent =
			Row

		if IsSelf then

			ViewButton.Position =
				UDim2.new(
					1,
					-(BUTTON_WIDTH + SELF_VIEW_RIGHT_PAD),
					0.5,
					-BUTTON_HEIGHT / 2
				)

		else

			ViewButton.Position =
				UDim2.new(
					1,
					-(
						FRIEND_WIDTH
						+ ACTION_RIGHT_PAD
						+ GAP
						+ BUTTON_WIDTH
						+ GAP
						+ BUTTON_WIDTH
						+ GAP
						+ BUTTON_WIDTH
						+ GAP
						+ BUTTON_WIDTH
					),
					0.5,
					-BUTTON_HEIGHT / 2
				)

		end

		Create(
			"ImageLabel",
			{
				Name =
					"Icon",

				Parent =
					ViewButton,

				BackgroundTransparency =
					1,

				Image =
					"rbxasset://textures/ui/InspectMenu/ico_inspect.png",

				Size =
					UDim2.new(
						0,
						28,
						0,
						28
					),

				Position =
					UDim2.new(
						0.5,
						-14,
						0.5,
						-14
					),

				ScaleType =
					Enum.ScaleType.Fit,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 4,
			}
		)

	end


	if Player ~= LocalPlayer and VoiceEnabledCache[UserId] == false then
		-- Client-side eligibility checks for other players are unavailable; discard
		-- stale negative state left by older script runs.
		VoiceEnabledCache[UserId] = nil
	end
	local PlayerVoiceStatus = GetPlayerVoiceStatus(Player)
	if PlayerVoiceStatus == true then
		VoiceEnabledCache[UserId] = true
	end

	-- Keep a per-player control visible as soon as Voice Chat is requested On.
	-- Unknown/unsupported player status is reflected by the icon (Connecting/Error),
	-- rather than suppressing the button entirely.
	local HasVoiceEvidence = HasConfirmedPlayerVoice(Player)
	if CanTargetPlayer and VoiceGameSupported and HasVoiceEvidence then
		VoiceButton = MakeStyledButton(
			Player.Name .. "VoiceButton",
			"",
			UDim2.new(0, BUTTON_WIDTH, 0, BUTTON_HEIGHT),
			function()
				local Muted = not GetRemoteVoiceMuted(Player)
				local Applied = SetRemoteVoiceMuted(Player, Muted)
				local CurrentVoiceButton = Row and Row:FindFirstChild(Player.Name .. "VoiceButton")
				local CurrentVoiceIcon = CurrentVoiceButton and CurrentVoiceButton:FindFirstChild("VoiceIcon")
				if CurrentVoiceIcon then CurrentVoiceIcon.Image = VoiceContrastIcon(GetVoiceIcon(Player, GetRemoteVoiceMuted(Player))) end
			end
		)
		VoiceButton.Parent = Row
		-- Remote eligibility queries are rejected by this client build. Keep the
		-- button visible unless Roblox explicitly confirmed this player has no VC.
		-- Unknown players use a neutral zero-peak mic icon, never Error/Connecting.
		VoiceButton.Visible = HasConfirmedPlayerVoice(Player)
		VoiceButton.Active = true
		VoiceButton.Position = UDim2.new(1, -(FRIEND_WIDTH + ACTION_RIGHT_PAD + GAP + BUTTON_WIDTH + GAP + BUTTON_WIDTH + GAP + BUTTON_WIDTH + GAP + BUTTON_WIDTH), 0.5, -BUTTON_HEIGHT / 2)
		local VoiceIcon = Create("ImageLabel", {
			Name = "VoiceIcon",
			Parent = VoiceButton,
			BackgroundTransparency = 1,
			Image = VoiceContrastIcon(GetVoiceIcon(Player, GetRemoteVoiceMuted(Player))),
			Visible = true,
			ImageTransparency = 0,
			Size = UDim2.new(0, BUTTON_HEIGHT - 8, 0, BUTTON_HEIGHT - 8),
			Position = UDim2.new(0.5, -(BUTTON_HEIGHT - 8) / 2, 0.5, -(BUTTON_HEIGHT - 8) / 2),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = SETTINGS_BASE_ZINDEX + 4,
		})
		if VoiceEnabledCache[UserId] ~= true then
			CheckVoiceForPlayer(Player, function(Enabled)
				if Enabled then VoiceEnabledCache[UserId] = true end
				if VoiceButton and VoiceButton.Parent then
					VoiceButton.Visible = HasConfirmedPlayerVoice(Player)
				end
				if VoiceIcon.Parent then VoiceIcon.Image = VoiceContrastIcon(GetVoiceIcon(Player, GetRemoteVoiceMuted(Player))) end
			end)
		end
	end

	if CanTargetPlayer then

		ReportButton =
			MakeStyledButton(
				Player.Name
					.. "ReportButton",
				"",
				UDim2.new(
					0,
					BUTTON_WIDTH,
					0,
					BUTTON_HEIGHT
				),
				function()

					if OpenReportPlayer then
						OpenReportPlayer(
							Player
						)
					end

				end
			)

		ReportButton.Parent =
			Row

		ReportButton.Position =
			UDim2.new(
				1,
				-(
					FRIEND_WIDTH
					+ ACTION_RIGHT_PAD
					+ GAP
					+ BUTTON_WIDTH
					+ GAP
					+ BUTTON_WIDTH
				),
				0.5,
				-BUTTON_HEIGHT / 2
			)

		local ReportIcon =
			Create(
				"ImageLabel",
				{
					Name =
						"Icon",

					Parent =
						ReportButton,

					BackgroundTransparency =
						1,

					Image =
						"rbxasset://textures/ui/Settings/MenuBarIcons/ReportAbuseTab.png",

					-- Keep the original compact height; widen only slightly.

					Size = UDim2.new(0, 26, 0, 28),

					Position = UDim2.new(0.5, -13, 0.5, -14),

					ScaleType = Enum.ScaleType.Stretch,

					ZIndex = SETTINGS_BASE_ZINDEX + 4,
				}
			)

		BlockButton =
			MakeStyledButton(
				Player.Name
					.. "BlockButton",
				"",
				UDim2.new(
					0,
					BUTTON_WIDTH,
					0,
					BUTTON_HEIGHT
				),
				function()

					RunAfterMenuCloses(
						function()

							Protect(
								function()

									StarterGui:SetCore(
										"PromptBlockPlayer",
										Player
									)

								end
							)

						end
					)

				end
			)

		BlockButton.Parent =
			Row

		BlockButton.Position =
			UDim2.new(
				1,
				-(
					FRIEND_WIDTH
					+ ACTION_RIGHT_PAD
					+ GAP
					+ BUTTON_WIDTH
				),
				0.5,
				-BUTTON_HEIGHT / 2
			)

		Create(
			"ImageLabel",
			{
				Name =
					"Icon",

				Parent =
					BlockButton,

				BackgroundTransparency =
					1,

				Image =
					"rbxasset://textures/ui/Settings/Players/BlockIcon.png",

				Size =
					UDim2.new(
						0,
						28,
						0,
						28
					),

				Position =
					UDim2.new(
						0.5,
						-14,
						0.5,
						-14
					),

				ScaleType =
					Enum.ScaleType.Fit,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 4,
			}
		)

		local Status

		Protect(
			function()
				Status =
					LocalPlayer:GetFriendStatus(
						Player
					)
			end
		)

		if
			Status
			== Enum.FriendStatus.Friend
		then

			FriendButton =
				Create(
					"TextButton",
					{
						Name =
							"FriendStatus",

						Parent =
							Row,

						Text =
							"Friend",

						BackgroundTransparency =
							1,

						Font =
							Enum.Font.SourceSans,

						TextSize =
							24,

						TextColor3 =
							Color3.new(
								1,
								1,
								1
							),

						Size =
							UDim2.new(
								0,
								FRIEND_WIDTH,
								0,
								BUTTON_HEIGHT
							),

						Position =
							UDim2.new(
								1,
								-FRIEND_WIDTH,
								0.5,
								-BUTTON_HEIGHT / 2
							),

						ZIndex =
							SETTINGS_BASE_ZINDEX
							+ 3,
					}
				)

		elseif
			Status
			== Enum.FriendStatus.FriendRequestSent
		then

			FriendButton =
				Create(
					"TextButton",
					{
						Name =
							"FriendStatus",

						Parent =
							Row,

						Text =
							"Request Sent",

						BackgroundTransparency =
							1,

						Font =
							Enum.Font.SourceSans,

						TextSize =
							24,

						TextColor3 =
							Color3.new(
								1,
								1,
								1
							),

						Size =
							UDim2.new(
								0,
								FRIEND_WIDTH,
								0,
								BUTTON_HEIGHT
							),

						Position =
							UDim2.new(
								1,
								-FRIEND_WIDTH,
								0.5,
								-BUTTON_HEIGHT / 2
							),

						ZIndex =
							SETTINGS_BASE_ZINDEX
							+ 3,
					}
				)

		else

			FriendButton, FriendLabel =
				MakeStyledButton(
					"FriendStatus",
					"Add Friend",
					UDim2.new(
						0,
						FRIEND_WIDTH,
						0,
						BUTTON_HEIGHT
					),
					function()

						if
							FriendLabel
							and FriendLabel.Text ~= ""
						then

							FriendButton.ImageTransparency =
								1

							FriendLabel.Text =
								""

							Protect(
								function()

									StarterGui:SetCore(
										"PromptSendFriendRequest",
										Player
									)

								end
							)

							Protect(
								function()

									LocalPlayer:
										RequestFriendship(
											Player
										)

								end
							)

						end

					end
				)

			FriendButton.Name =
				"FriendStatus"

			if FriendLabel then
				FriendLabel.TextSize = 26
			end

			FriendButton.Parent =
				Row

			FriendButton.Position =
				UDim2.new(
					1,
					-FRIEND_WIDTH,
					0.5,
					-BUTTON_HEIGHT / 2
				)

			if FriendLabel then
				FriendLabel.ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3
			end

		end

	end

	PositionPlayerActionButtons(VoiceButton ~= nil)

	for _, Button in next,
		{
			ViewButton,
			ReportButton,
			BlockButton,
			FriendButton,
		}
	do

		if Button then

			Connect(
				Button.MouseEnter,
				function()
					Row.ImageTransparency =
						0.65
				end
			)

			Connect(
				Button.MouseLeave,
				function()
					Row.ImageTransparency =
						0.85
				end
			)

		end

	end

	PositionPlayerActionButtons(VoiceButton ~= nil)

	return Row
end

-- ============================================================
-- POST MENU CALLBACK
-- ============================================================

RunAfterMenuCloses = function(
	Callback
)

	SetVisibility(
		false
	)

	Spawn(function()

		Wait(
			0.45
		)

		if Callback then
			Callback()
		end

	end)

end

-- ============================================================
-- SELECTOR
-- ============================================================

MakeSelector = function(
	Page,
	Name,
	Values,
	Index,
	Changed
)

	local CurrentIndex =
		Index
		or 1

	local Row =
		MakeRow(
			Page,
			Name
		)

	local SelectorFrame =
		Create(
			"ImageButton",
			{
				Name =
					Name
					.. "Selector",

				Parent =
					Row,

				BackgroundTransparency =
					1,

				Image =
					"",

				AutoButtonColor =
					false,

				Size =
					UDim2.new(
						0,
						502,
						0,
						50
					),

				Position =
					UDim2.new(
						1,
						-502,
						0.5,
						-25
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	local Left =
		Create(
			"ImageButton",
			{
				Parent =
					SelectorFrame,

				Name =
					"LeftButton",

				BackgroundTransparency =
					1,

				Image =
					"",

				Size =
					UDim2.new(
						0,
						60,
						0,
						50
					),

				Position =
					UDim2.new(
						0,
						-10,
						0.5,
						-25
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	Create(
		"ImageLabel",
		{
			Parent =
				Left,

			BackgroundTransparency =
				1,

			Image =
				"rbxasset://textures/ui/Settings/Slider/Left.png",

			ScaleType =
				Enum.ScaleType.Fit,

			Size =
				UDim2.new(
					0,
					30,
					0,
					30
				),

			Position =
				UDim2.new(
					0.5,
					-15,
					0.5,
					-15
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 4,
		}
	)

	local Right =
		Create(
			"ImageButton",
			{
				Parent =
					SelectorFrame,

				Name =
					"RightButton",

				BackgroundTransparency =
					1,

				Image =
					"",

				Size =
					UDim2.new(
						0,
						50,
						0,
						50
					),

				Position =
					UDim2.new(
						1,
						-50,
						0,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	Create(
		"ImageLabel",
		{
			Parent =
				Right,

			BackgroundTransparency =
				1,

			Image =
				"rbxasset://textures/ui/Settings/Slider/Right.png",

			ScaleType =
				Enum.ScaleType.Fit,

			Size =
				UDim2.new(
					0,
					30,
					0,
					30
				),

			Position =
				UDim2.new(
					0.5,
					-15,
					0.5,
					-15
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 4,
		}
	)

	if HIDE_SELECTOR_ARROWS then
		for _, ArrowObject in next, {Left, Right} do
			for _, Descendant in next, ArrowObject:GetDescendants() do
				if Descendant:IsA("ImageLabel") then
					Descendant.Visible = false
				end
			end
		end
	end

	local Label =
		Create(
			"TextLabel",
			{
				Parent =
					SelectorFrame,

				Name =
					"Selection",

				BackgroundTransparency =
					1,

				BorderSizePixel =
					0,

				Size =
					UDim2.new(
						1,
						-120,
						1,
						0
					),

				Position =
					UDim2.new(
						0,
						60,
						0,
						0
					),

				TextColor3 =
					Color3.new(
						1,
						1,
						1
					),

				TextTransparency =
					0.2,

				TextYAlignment =
					Enum.TextYAlignment.Center,

				Font =
					Enum.Font.SourceSans,

				TextSize =
					24,

				Text =
					Values[CurrentIndex],

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	local SelectorApi = {
		CurrentIndex =
			CurrentIndex,

		SelectorFrame =
			SelectorFrame,

		Selection =
			SelectorFrame,

		RowFrame =
			Row,

		TextLabel =
			Label,

		Interactable =
			true,
	}

	local SetText = function(
		Text,
		Direction
	)

		Label.Text =
			Text

		Label.Position =
			UDim2.new(
				0,
				60
				+ (
					(Direction or 0)
					* 16
				),
				0,
				0
			)

		Label.TextTransparency =
			0.75

		MoveTo(
			Label,
			UDim2.new(
				0,
				60,
				0,
				0
			)
		)

		FadeText(
			Label,
			0.2
		)

	end

	local Apply = function(
		Delta
	)

		if not SelectorApi.Interactable then
			return
		end

		CurrentIndex =
			CurrentIndex
			+ Delta

		if
			CurrentIndex
			> #Values
		then

			CurrentIndex =
				1

		elseif
			CurrentIndex
			< 1
		then

			CurrentIndex =
				#Values

		end

		SelectorApi.CurrentIndex =
			CurrentIndex

		SetText(
			Values[CurrentIndex],
			Delta
		)

		if Changed then
			Changed(
				CurrentIndex,
				Values[CurrentIndex]
			)
		end

	end

	Connect(
		Left.MouseButton1Click,
		function()
			Apply(-1)
		end
	)

	Connect(
		Right.MouseButton1Click,
		function()
			Apply(1)
		end
	)

	Connect(
		SelectorFrame.MouseButton1Click,
		function()
			Apply(1)
		end
	)

	function SelectorApi:SetSelectionIndex(
		NewIndex,
		FireChanged
	)

		if not NewIndex
			or #Values == 0
		then
			return
		end

		CurrentIndex =
			Clamp(
				NewIndex,
				1,
				#Values
			)

		SelectorApi.CurrentIndex =
			CurrentIndex

		SetText(
			Values[CurrentIndex],
			0
		)

		if Changed
			and FireChanged
		then

			Changed(
				CurrentIndex,
				Values[CurrentIndex]
			)

		end

	end

	function SelectorApi:SetPosition(
		Position
	)

		SelectorFrame.Position =
			Position

	end

	function SelectorApi:SetSize(
		Size
	)

		SelectorFrame.Size =
			Size

	end

	function SelectorApi:SetInteractable(
		Interactable
	)

		SelectorApi.Interactable =
			Interactable

		SelectorFrame.ImageTransparency =
			Interactable
			and 0
			or 0.65

		Label.TextTransparency =
			Interactable
			and 0.2
			or 0.65

		Left.Visible =
			Interactable

		Right.Visible =
			Interactable

	end

	function SelectorApi:GetSelectedIndex()
		return CurrentIndex
	end

	function SelectorApi:GetSelectedValue()
		return Values[CurrentIndex]
	end

	return SelectorApi
end

-- ============================================================
-- SLIDER
-- ============================================================

MakeSlider = function(
	Page,
	Name,
	Steps,
	Index,
	Changed,
	MinStep,
	Instant
)

	MinStep =
		MinStep
		or 0

	local CurrentIndex =
		Clamp(
			Index
			or 1,
			MinStep,
			Steps
		)

	local Row =
		MakeRow(
			Page,
			Name
		)

	local Holder =
		Create(
			"Frame",
			{
				Parent =
					Row,

				BackgroundTransparency =
					1,

				Size =
					UDim2.new(
						0,
						502,
						0,
						50
					),

				Position =
					UDim2.new(
						1,
						-502,
						0.5,
						-25
					),

				Active =
					true,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	local Left =
		Create(
			"ImageButton",
			{
				Parent =
					Holder,

				BackgroundTransparency =
					1,

				Image =
					"",

				Size =
					UDim2.new(
						0,
						50,
						0,
						50
					),

				Position =
					UDim2.new(
						0,
						0,
						0,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	Create(
		"ImageLabel",
		{
			Parent =
				Left,

			BackgroundTransparency =
				1,

			Image =
				SLIDER_LEFT_IMAGE,

			ScaleType =
				Enum.ScaleType.Fit,

			Size =
				UDim2.new(
					0,
					30,
					0,
					30
				),

			Position =
				UDim2.new(
					0.5,
					-15,
					0.5,
					-15
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 4,
		}
	)

	local Right =
		Create(
			"ImageButton",
			{
				Parent =
					Holder,

				BackgroundTransparency =
					1,

				Image =
					"",

				Size =
					UDim2.new(
						0,
						50,
						0,
						50
					),

				Position =
					UDim2.new(
						1,
						-50,
						0.5,
						-25
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

	Create(
		"ImageLabel",
		{
			Parent =
				Right,

			BackgroundTransparency =
				1,

			Image =
				SLIDER_RIGHT_IMAGE,

			ScaleType =
				Enum.ScaleType.Fit,

			Size =
				UDim2.new(
					0,
					30,
					0,
					30
				),

			Position =
				UDim2.new(
					0.5,
					-15,
					0.5,
					-15
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 4,
		}
	)

	local Segments =
		{}

	local Dragging =
		false

	local SliderApi = {
		SliderFrame =
			Holder,

		Selection =
			Holder,

		RowFrame =
			Row,

		Interactable =
			true,
	}

	local Refresh = function(
		Immediate
	)

		for Index2, Segment in next,
			Segments
		do

			local Selected =
				SliderApi.Interactable
				and Index2 <= CurrentIndex

			local Color =
				(
					Selected
					and Color3.fromRGB(
						0,
						162,
						255
					)
					or Color3.fromRGB(
						78,
						84,
						96
					)
				)

			if
				Index2 == 1
				or Index2 == Steps
			then

				if Selected then

					if Index2 == 1 then

						Segment.Image =
							SLIDER_SELECTED_LEFT_IMAGE

					else

						Segment.Image =
							SLIDER_SELECTED_RIGHT_IMAGE

					end

				else

					if Index2 == 1 then

						Segment.Image =
							SLIDER_BAR_LEFT_IMAGE

					else

						Segment.Image =
							SLIDER_BAR_RIGHT_IMAGE

					end

				end

				Segment.ImageTransparency =
					0.36

				Segment.BackgroundTransparency =
					1

			else

				-- Slider segment colors must snap immediately.
				-- Do not tween transparency/color when choosing a new level.
				Segment.BackgroundColor3 =
					Color

			end

		end

		Left.Visible =
			SliderApi.Interactable
			and CurrentIndex > MinStep

		Right.Visible =
			SliderApi.Interactable
			and CurrentIndex < Steps

	end

	local SetSliderValue = function(
		NewIndex
	)

		NewIndex =
			Clamp(
				NewIndex,
				MinStep,
				Steps
			)

		if
			CurrentIndex
			== NewIndex
		then
			return
		end

		CurrentIndex =
			NewIndex

		Refresh(Instant == true)

		if Changed then
			Changed(
				CurrentIndex
			)
		end

	end

	local SetSliderFromX =
		function(X)

			if
				not SliderApi.Interactable
			then
				return
			end

			local FirstSegment =
				Segments[1]

			local LastSegment =
				Segments[Steps]

			if
				not FirstSegment
				or not LastSegment
			then
				return
			end

			local StartX =
				FirstSegment.AbsolutePosition.X

			local EndX =
				LastSegment.AbsolutePosition.X
				+ LastSegment.AbsoluteSize.X

			local Alpha =
				Clamp(
					(
						X - StartX
					)
					/ (
						EndX - StartX
					),
					0,
					1
				)

			if MinStep > 0 then

				SetSliderValue(
					Clamp(
						Floor(
							(
								Alpha
								* Steps
							)
							+ 1
						),
						MinStep,
						Steps
					)
				)

			else

				SetSliderValue(
					Clamp(
						Floor(
							Alpha
							* (
								Steps
								+ 1
							)
						),
						0,
						Steps
					)
				)

			end

		end

	for Index2 = 1, Steps do

		local Segment =
			Create(
				"ImageButton",
				{
					Parent =
						Holder,

					BackgroundColor3 =
						Color3.fromRGB(
							78,
							84,
							96
						),

					BackgroundTransparency =
						0.36,

					BorderSizePixel =
						0,

					AutoButtonColor =
						false,

					Image =
						"",

					ImageTransparency =
						0.36,

					Size =
						UDim2.new(
							0,
							35,
							0,
							25
						),

					Position =
						UDim2.new(
							0,
							60
							+ (
								(Index2 - 1)
								* 39
							),
							0.5,
							-12
						),

					ZIndex =
						SETTINGS_BASE_ZINDEX
						+ 3,
				}
			)

		if
			Index2 == 1
			or Index2 == Steps
		then

			Segment.BackgroundTransparency =
				1

			Segment.ScaleType =
				Enum.ScaleType.Slice

			Segment.SliceCenter =
				Rect.new(
					3,
					3,
					32,
					21
				)

		end

		Segments[Index2] =
			Segment

		Connect(
			Segment.MouseButton1Click,
			function()

				if SliderApi.Interactable then
					SetSliderValue(
						Index2
					)
				end

			end
		)

	end

	local Capture =
		Create(
			"TextButton",
			{
				Parent =
					Holder,

				BackgroundTransparency =
					1,

				BorderSizePixel =
					0,

				Text =
					"",

				AutoButtonColor =
					false,

				Active =
					true,

				Size =
					UDim2.new(
						0,
						400,
						1,
						0
					),

				Position =
					UDim2.new(
						0,
						52,
						0,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 5,
			}
		)

	Connect(
		Capture.InputBegan,
		function(Input)

			if
				Input.UserInputType
					== Enum.UserInputType.MouseButton1
				or Input.UserInputType
					== Enum.UserInputType.Touch
			then

				Dragging =
					true

				SetSliderFromX(
					Input.Position.X
				)

			end

		end
	)

	Connect(
		Capture.InputChanged,
		function(Input)

			if
				Dragging
				and (
					Input.UserInputType
						== Enum.UserInputType.MouseMovement
					or Input.UserInputType
						== Enum.UserInputType.Touch
				)
			then

				SetSliderFromX(
					Input.Position.X
				)

			end

		end
	)

	Connect(
		UserInputService.InputChanged,
		function(Input)

			if
				Dragging
				and (
					Input.UserInputType
						== Enum.UserInputType.MouseMovement
					or Input.UserInputType
						== Enum.UserInputType.Touch
				)
			then

				SetSliderFromX(
					Input.Position.X
				)

			end

		end
	)

	Connect(
		UserInputService.InputEnded,
		function(Input)

			if
				Input.UserInputType
					== Enum.UserInputType.MouseButton1
				or Input.UserInputType
					== Enum.UserInputType.Touch
			then

				Dragging =
					false

			end

		end
	)

	Connect(
		Left.MouseButton1Click,
		function()

			if SliderApi.Interactable then

				SetSliderValue(
					CurrentIndex - 1
				)

			end

		end
	)

	Connect(
		Right.MouseButton1Click,
		function()

			if SliderApi.Interactable then

				SetSliderValue(
					CurrentIndex + 1
				)

			end

		end
	)

	Refresh(true)

	function SliderApi:SetValue(
		NewValue
	)

		CurrentIndex =
			Clamp(
				NewValue,
				MinStep,
				Steps
			)

		Refresh(true)

	end

	function SliderApi:GetValue()
		return CurrentIndex
	end

	function SliderApi:SetInteractable(
		Interactable
	)

		SliderApi.Interactable =
			Interactable

		Holder.Active =
			Interactable

		Holder.ZIndex =
			SETTINGS_BASE_ZINDEX
			+ (
				Interactable
				and 2
				or 1
			)

		for _, Segment in next,
			Segments
		do

			Segment.Active =
				Interactable

			Segment.Selectable =
				Interactable

			Segment.ZIndex =
				SETTINGS_BASE_ZINDEX
				+ (
					Interactable
					and 3
					or 1
				)

		end

		Refresh(true)

	end

	function SliderApi:SetZIndex(
		NewZIndex
	)

		Holder.ZIndex =
			NewZIndex

		Left.ZIndex =
			NewZIndex + 1

		Right.ZIndex =
			NewZIndex + 1

		for _, Segment in next,
			Segments
		do

			Segment.ZIndex =
				NewZIndex + 1

		end

	end

	function SliderApi:SetMinStep(
		NewMinStep
	)

		MinStep =
			Clamp(
				NewMinStep or 0,
				0,
				Steps
			)

		CurrentIndex =
			Clamp(
				CurrentIndex,
				MinStep,
				Steps
			)

		Refresh(true)

	end

	return SliderApi
end

-- ============================================================
-- DROPDOWN
-- ============================================================

MakeDropDown = function(
	Page,
	Name,
	Values,
	Index,
	Changed
)

	local CurrentIndex =
		Index

	local Row =
		MakeRow(
			Page,
			Name
		)

	local Button =
		MakeStyledButton(
			Name
				.. "DropDown",
			Values[CurrentIndex]
			or "Choose One",
			UDim2.new(
				0,
				300,
				0,
				44
			)
		)

	Button.Parent =
		Row

	Button.Position =
		UDim2.new(
			1,
			-350,
			0.5,
			-22
		)

	local Arrow =
		Create(
			"ImageLabel",
			{
				Parent =
					Button,

				BackgroundTransparency =
					1,

				Image =
					DROP_DOWN_IMAGE,

				Size =
					UDim2.new(
						0,
						15,
						0,
						10
					),

				Position =
					UDim2.new(
						1,
						-40,
						0.5,
						-7
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 4,
			}
		)

	local Label =
		Button:FindFirstChild(
			Name
				.. "DropDownTextLabel"
		)

	local DropDownApi = {
		CurrentIndex =
			CurrentIndex,

		DropDownFrame =
			Button,

		Selection =
			Button,

		Interactable =
			true,
	}

	local Overlay =
		Create(
			"TextButton",
			{
				Parent =
					ScreenGui,

				Name =
					Name
					.. "DropDownFullscreenFrame",

				Visible =
					false,

				BackgroundColor3 =
					Color3.new(
						0,
						0,
						0
					),

				BackgroundTransparency =
					0.2,

				BorderSizePixel =
					0,

				Text =
					"",

				Size =
					UDim2.new(
						1,
						0,
						1,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 20,
			}
		)

	local Panel =
		Create(
			"ImageLabel",
			{
				Parent =
					Overlay,

				Image =
					BUTTON_IMAGE,

				ScaleType =
					Enum.ScaleType.Slice,

				SliceCenter =
					Rect.new(
						8,
						6,
						46,
						44
					),

				BackgroundTransparency =
					1,

				Size =
					UDim2.new(
						0,
						400,
						0.9,
						0
					),

				Position =
					UDim2.new(
						0.5,
						-200,
						0.05,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 21,
			}
		)

	local List =
		Create(
			"ScrollingFrame",
			{
				Parent =
					Panel,

				BackgroundTransparency =
					1,

				BorderSizePixel =
					0,

				Size =
					UDim2.new(
						1,
						-20,
						1,
						-25
					),

				Position =
					UDim2.new(
						0,
						10,
						0,
						10
					),

				CanvasSize =
					UDim2.new(
						0,
						0,
						0,
						#Values * 51
					),

				ScrollBarThickness =
					6,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 21,
			}
		)

	local SetSelection = function(
		NewIndex,
		FireChanged
	)

		CurrentIndex =
			NewIndex

		DropDownApi.CurrentIndex =
			CurrentIndex

		local Value =
			CurrentIndex
			and Values[CurrentIndex]
			or nil

		Label.Text =
			Value
			or "Choose One"

		if
			Changed
			and FireChanged
		then

			Changed(
				CurrentIndex,
				Value
			)

		end

	end

	local Rebuild = function(
		NewValues
	)

		Values =
			NewValues
			or Values

		if
			CurrentIndex
			and CurrentIndex > #Values
		then

			CurrentIndex =
				nil

			DropDownApi.CurrentIndex =
				nil

		end

		for _, Child in next,
			List:GetChildren()
		do

			if Child:IsA("TextButton") then
				Child:Destroy()
			end

		end

		for Index2, Value in next,
			Values
		do

			local Option =
				Create(
					"TextButton",
					{
						Parent =
							List,

						Name =
							"Selection"
							.. tostring(
								Index2
							),

						BackgroundTransparency =
							1,

						BorderSizePixel =
							0,

						AutoButtonColor =
							false,

						Size =
							UDim2.new(
								1,
								-28,
								0,
								50
							),

						Position =
							UDim2.new(
								0,
								14,
								0,
								(
									Index2 - 1
								)
								* 51
							),

						TextColor3 =
							(
								Index2
								== CurrentIndex
							)
							and Color3.new(
								1,
								1,
								1
							)
							or Color3.new(
								0.7,
								0.7,
								0.7
							),

						Font =
							Enum.Font.SourceSans,

						TextSize =
							24,

						Text =
							Value,

						ZIndex =
							SETTINGS_BASE_ZINDEX
							+ 22,
					}
				)

			Connect(
				Option.MouseButton1Click,
				function()

					SetSelection(
						Index2,
						true
					)

					Overlay.Visible =
						false

				end
			)

		end

		List.CanvasSize =
			UDim2.new(
				0,
				0,
				0,
				#Values * 51
			)

		SetSelection(
			CurrentIndex,
			false
		)

	end

	Connect(
		Button.MouseButton1Click,
		function()

			if DropDownApi.Interactable then

				Overlay.Visible =
					true

			end

		end
	)

	Connect(
		Overlay.MouseButton1Click,
		function()
			Overlay.Visible =
				false
		end
	)

	Rebuild(
		Values
	)

	function DropDownApi:UpdateDropDownList(
		NewValues
	)
		Rebuild(
			NewValues
		)
	end

	function DropDownApi:SetSelectionIndex(
		NewIndex,
		FireChanged
	)

		if
			not NewIndex
			or NewIndex < 1
			or NewIndex > #Values
		then

			SetSelection(
				nil,
				FireChanged
			)

			return false

		end

		SetSelection(
			NewIndex,
			FireChanged
		)

		return true
	end

	function DropDownApi:SetSelectionByValue(
		Value,
		FireChanged
	)

		for Index2, Item in next,
			Values
		do

			if Item == Value then

				SetSelection(
					Index2,
					FireChanged
				)

				return true

			end

		end

		return false
	end

	function DropDownApi:ResetSelectionIndex(
		FireChanged
	)

		SetSelection(
			nil,
			FireChanged
		)

	end

	function DropDownApi:GetSelectedIndex()
		return CurrentIndex
	end

	function DropDownApi:GetSelectedValue()

		return CurrentIndex
			and Values[CurrentIndex]
			or nil

	end

	function DropDownApi:SetInteractable(
		Interactable
	)

		DropDownApi.Interactable =
			Interactable

		Button.ImageTransparency =
			Interactable
			and 0
			or 0.65

		Button.Active =
			Interactable

		Button.Selectable =
			Interactable

		if Label then

			Label.TextTransparency =
				Interactable
				and 0
				or 0.65

		end

		if Arrow then

			Arrow.ImageTransparency =
				Interactable
				and 0
				or 0.65

		end

	end

	return DropDownApi
end

-- ============================================================
-- PAGES
-- ============================================================

PlayersPage =
	MakePage(
		"People"
	)

AddPage(
	PlayersPage,
	"People",
	"rbxasset://textures/ui/Settings/MenuBarIcons/PlayersTabIcon.png",
	150
)

if PlayersPage.Icon then

	PlayersPage.Icon.Size =
		UDim2.new(
			0,
			36,
			0,
			36
		)

	PlayersPage.Icon.Position =
		UDim2.new(
			0,
			15,
			0.5,
			-18
		)

end

-- ============================================================
-- INVITE FRIENDS ROW ON NORMAL PLAYER PAGE
-- ============================================================

INVITE_BUTTON_WIDTH =
	70

INVITE_BUTTON_HEIGHT =
	46

INVITE_MOBILE_SEARCH_EXPANDED = false
INVITE_MOBILE_SEARCH_WIDTH = 260
INVITE_MOBILE_SEARCH_COLLAPSED = 38
INVITE_MOBILE_HEADER_DIVIDER = nil

MakeInviteFriendsRow = function(Page)
	local VoiceActive = VoiceGameSupported == true and VoiceAccountAllowed == true
	local PhoneLayout = IsPhone == true
	local RowHeight = PhoneLayout and 54 or 62
	local SideBySide = VoiceActive and InviteFriends and not PhoneLayout
	local FullRowSize = UDim2.new(1, 0, 0, RowHeight)
	local HalfRowSize = UDim2.new(0.5, -4, 0, 62)
	local function BaseRow(Name, Pos, Size)
		return Create("ImageButton", {
			Name = Name,
			Parent = Page.Frame,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = "rbxasset://textures/ui/dialog_white.png",
			ImageTransparency = 0.85,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(10, 10, 10, 10),
			Size = Size or FullRowSize,
			Position = Pos,
			AutoButtonColor = false,
			ZIndex = SETTINGS_BASE_ZINDEX + 2,
		})
	end

	local Row
	if InviteFriends then
		Row = BaseRow("InviteFriendsToJoin", UDim2.new(0, 0, 0, 0), SideBySide and HalfRowSize or FullRowSize)
		Create("ImageLabel", {
			Name = "Icon", Parent = Row, BackgroundTransparency = 1,
			Image = "rbxassetid://80022950003290", Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(0, 14, 0.5, -12), ScaleType = Enum.ScaleType.Fit,
			ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})
		Create("TextLabel", {
			Name = "NameLabel", Parent = Row, BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans, TextSize = PhoneLayout and 24 or 22,
			TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Invite friends to join", TextWrapped = false, TextScaled = false,
			Size = UDim2.new(1, PhoneLayout and -64 or -78, 1, 0),
			Position = UDim2.new(0, 50, 0, 0), ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})
	end

	local MuteRow
	if VoiceActive then
		local MutePosition = SideBySide and UDim2.new(0.5, 4, 0, 0) or UDim2.new(0, 0, 0, 0)
		local MuteSize = SideBySide and HalfRowSize or FullRowSize
		MuteRow = BaseRow("MuteAllVoiceRow", MutePosition, MuteSize)
		local Icon = Create("ImageLabel", {
			Name = "Icon", Parent = MuteRow, BackgroundTransparency = 1,
			Image = VOICE_MISC_ROOT .. (VoiceMuteAllActive and "UnmuteAll@3x.png" or "MuteAll@3x.png"),
			Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 14, 0.5, -15),
			ScaleType = Enum.ScaleType.Fit, ZIndex = SETTINGS_BASE_ZINDEX + 4,
		})
		local Label = Create("TextLabel", {
			Name = "MuteAllLabel", Parent = MuteRow, BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans, TextSize = PhoneLayout and 24 or 22,
			TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Mute All", TextWrapped = false, TextScaled = false,
			Size = UDim2.new(1, PhoneLayout and -66 or -56, 1, 0),
			Position = UDim2.new(0, 52, 0, 0), ZIndex = SETTINGS_BASE_ZINDEX + 4,
		})
		local State = VoiceMuteAllActive == true
		Label.Text = State and "Unmute All" or "Mute All"
		Icon.Image = VOICE_MISC_ROOT .. (State and "UnmuteAll@3x.png" or "MuteAll@3x.png")
		Connect(MuteRow.MouseEnter, function() MuteRow.ImageTransparency = 0.65 end)
		Connect(MuteRow.MouseLeave, function() MuteRow.ImageTransparency = 0.85 end)
		Connect(MuteRow.MouseButton1Click, function()
			State = not State
			SetMuteAll(State)
			Label.Text = State and "Unmute All" or "Mute All"
			Icon.Image = VOICE_MISC_ROOT .. (State and "UnmuteAll@3x.png" or "MuteAll@3x.png")
		end)
	end

	if Row then
		Connect(Row.MouseEnter, function() Row.ImageTransparency = 0.65 end)
		Connect(Row.MouseLeave, function() Row.ImageTransparency = 0.85 end)
		Connect(Row.MouseButton1Click, function() if OpenInviteFriends then OpenInviteFriends() end end)
	end
	return Row, MuteRow
end


-- Phone-only layout for the Invite Friends and Mute All rows.
-- Returns the Y offset where player rows should begin.
LayoutPhonePlayerActionRows = function(Frame, StartY)
	if not IsPhone or not Frame then return nil end
	local InviteRow = Frame:FindFirstChild("InviteFriendsToJoin")
	local MuteRow = Frame:FindFirstChild("MuteAllVoiceRow")
	local RowHeight = 54
	local RowGap = 6
	local Cursor = StartY or 72

	if InviteRow then
		InviteRow.Size = UDim2.new(1, 0, 0, RowHeight)
		InviteRow.Position = UDim2.new(0, 0, 0, Cursor)
		Cursor = Cursor + RowHeight + (MuteRow and RowGap or 10)
	end

	if MuteRow then
		MuteRow.Size = UDim2.new(1, 0, 0, RowHeight)
		MuteRow.Position = UDim2.new(0, 0, 0, Cursor)
		Cursor = Cursor + RowHeight + 10
	end

	return Cursor
end

RebuildPlayersPage = function()

	-- Queue one throttled native-icon refresh away from the menu's layout frame.
	ScheduleNativeVoiceMirrorRefresh()

	for _, Child in next,
		PlayersPage.Frame:GetChildren()
	do

		if
			Child.Name:sub(
				1,
				11
			)
			== "PlayerLabel"

			or Child.Name == "InviteFriendsToJoin"
			or Child.Name == "MuteAllVoiceRow"
		then
			Child:Destroy()
		end

	end

	local SortedPlayers =
		Players:GetPlayers()

	-- Mobile-only offset. PC keeps the original player-row positions.
	local MobileUiScale = GetMobileUiScale()
	local MobileActionOffset =
		(IsMobile and not IsTablet)
		and 72
		or 0

	table.sort(
		SortedPlayers,
		function(
			PlayerA,
			PlayerB
		)

			return
				PlayerA.Name
				<
				PlayerB.Name

		end
	)

	local Count =
		0

	local InviteOffset =
		0

	local VoiceActive = VoiceGameSupported == true and VoiceAccountAllowed == true
	if InviteFriends or VoiceActive then
		local InviteRow, MuteRow = MakeInviteFriendsRow(PlayersPage)
		if IsPhone then
			local PlayerRowsStart = LayoutPhonePlayerActionRows(PlayersPage.Frame, 72) or 144
			InviteOffset = math.max(0, PlayerRowsStart - MobileActionOffset)
		else
			local RowY = 0
			if InviteRow then
				InviteRow.Position = UDim2.new(0, 0, 0, RowY)
				InviteRow.Size = (VoiceActive and InviteFriends) and UDim2.new(0.5, -4, 0, 62) or UDim2.new(1, 0, 0, 62)
			end
			if MuteRow then
				MuteRow.Position = (InviteFriends and VoiceActive) and UDim2.new(0.5, 4, 0, RowY) or UDim2.new(0, 0, 0, RowY)
				MuteRow.Size = (InviteFriends and VoiceActive) and UDim2.new(0.5, -4, 0, 62) or UDim2.new(1, 0, 0, 62)
			end
			InviteOffset = 72
		end
	end

	for _, Player in next,
		SortedPlayers
	do

		Count +=
			1

		local Row =
			MakePlayerRow(
				PlayersPage,
				Player,
				Count
			)

		if Row then

			Row.Position =
				UDim2.new(
					0,
					0,
					0,
					MobileActionOffset
					+ InviteOffset
					+ (
						(Count - 1)
						* 72
					)
				)

		end

	end

	PlayersPage.Frame.Size =
		UDim2.new(
			1,
			0,
			0,
			MobileActionOffset + InviteOffset + (Count * 72)
		)

	if not IsMobile and Hub and Hub.PageView and Hub.CurrentPage == PlayersPage then
		local PageViewHeight = Hub.PageView.AbsoluteSize.Y
		if PageViewHeight <= 0 and Hub.PageClipper then
			PageViewHeight = math.max(0, Hub.PageClipper.AbsoluteSize.Y - 20)
		end
		local PageContentHeight = math.max(0, PlayersPage.Frame.Position.Y.Offset + PlayersPage.Frame.Size.Y.Offset)
		local NeedsPlayerScrollbar = PageContentHeight > PageViewHeight + 1
		Hub.PageView.ScrollBarThickness = NeedsPlayerScrollbar and 12 or 0
		Hub.PageView.VerticalScrollBarInset = NeedsPlayerScrollbar and Enum.ScrollBarInset.ScrollBar or Enum.ScrollBarInset.None
		Hub.PageView.CanvasSize = UDim2.new(0, 0, 0, math.max(PageContentHeight, PageViewHeight))
	elseif IsPhone and Hub and Hub.PageView and Hub.CurrentPage == PlayersPage then
		local PageViewHeight = Hub.PageView.AbsoluteSize.Y
		local PageContentHeight = math.max(0, PlayersPage.Frame.Position.Y.Offset + PlayersPage.Frame.Size.Y.Offset)
		Hub.PageView.ScrollBarThickness = 0
		Hub.PageView.CanvasSize = UDim2.new(0, 0, 0, math.max(PageContentHeight, PageViewHeight))
	end

end

RebuildPlayersPage()

-- Voice entitlements can become available after the player list is first
-- rendered. Recheck everyone shortly after the first render so VC buttons do
-- not depend on the exact timing of the initial row creation.
Spawn(function()
	for Pass = 1, 4 do
		Wait(Pass == 1 and 0.25 or 0.75)
		if VoiceChatEnabled then
			local Changed = false
			for _, Player in next, Players:GetPlayers() do
				if Player ~= LocalPlayer then
					local Id = tonumber(Player.UserId or Player.userId) or 0
					local Before = VoiceEnabledCache[Id] == true
					CheckVoiceForPlayer(Player)
					if Before ~= (VoiceEnabledCache[Id] == true) then Changed = true end
				end
			end
			if RefreshVoiceParticipants() then Changed = true end
			if Changed then
				RebuildPlayersPage()
			end
		end
	end
end)

Protect(function()
	Connect(SoundService.DescendantAdded, function(Descendant)
		if Descendant:IsA("AudioDeviceInput") then
			local Owner = nil
			Protect(function() Owner = Descendant.Player end)
			if Owner == LocalPlayer then
				GetAudioDeviceInputCache[LocalPlayer] = Descendant
				EnsureVoiceAnalyzer(LocalPlayer)
			end
		end
	end)
end)

Connect(
	Players.PlayerAdded,
	function(Player)

		RebuildPlayersPage()

		Spawn(function()
			Wait(0.5)
			CheckVoiceForPlayer(Player, function(Enabled)
				if Enabled and VoiceChatEnabled then
					RebuildPlayersPage()
				end
			end)
		end)

	end
)

PendingPlayerListRefresh = false

Connect(
	Players.PlayerRemoving,
	function()
		PendingPlayerListRefresh = true
	end
)

Protect(function()

	Connect(
		LocalPlayer.FriendStatusChanged,
		function()
			RebuildPlayersPage()
		end
	)

end)

-- ============================================================
-- INVITE FRIENDS PAGE
-- ============================================================

SearchBox = nil
InviteList = nil
SearchIcon = nil
SearchPlaceholder = nil

InvitePage =
	MakePage(
		"InviteFriends"
	)

AddPage(
	InvitePage
)

InviteHeader =
	Create(
		"Frame",
		{
			Name =
				"InviteHeader",

			Parent =
				InvitePage.Frame,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			Size =
				UDim2.new(
					1,
					0,
					0,
					60
				),

			Position =
				UDim2.new(
					0,
					0,
					0,
					0
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 10,
		}
	)

InviteBackButton, InviteBackLabel =
	MakeStyledButton(
		"InviteBackButton",
		"Back",
		UDim2.new(
			0,
			132,
			0,
			56
		),
		function()

			local Previous =
				Hub.PreviousMenuPage
				or Hub.MenuStack[#Hub.MenuStack]
				or PlayersPage

			Hub.PreviousMenuPage = nil
			if Hub.MenuStack[#Hub.MenuStack] == Previous then
				table.remove(Hub.MenuStack, #Hub.MenuStack)
			end

			Hub.InInviteMenu =
				false

			Protect(function() GuiService.SelectedObject = nil end)
			Protect(function() GuiService.SelectedCoreObject = nil end)
			HideInviteSelection()

			if SearchBox then
				Protect(function()
					SearchBox:ReleaseFocus()
				end)
			end

			SearchBox.Text =
				""

			InviteHeader.Visible =
				false

			InviteList.Visible =
				false

			Hub.PageView.ScrollBarThickness =
				IsMobile and 0 or 12


			Hub.HubBar.Visible =
				true

			Hub.PageClipper.Visible =
				true

			Hub.BottomButtonFrame.Visible =
				true

			if HomeButton then

				HomeButton.Visible =
					HomeButtonEnabled
					and not IsMobile

			end

			SwitchToPage(
				Previous,
				true,
				true
			)

			ResizeHub()

		end
	)

InviteBackButton.Parent =
	InviteHeader
InviteBackButton.Active = true
InviteBackButton.Selectable = true
InviteBackButton.AutoButtonColor = false
InviteBackButton.ZIndex = SETTINGS_BASE_ZINDEX + 12

InviteBackButton.Position =
	UDim2.new(
		0,
		8,
		0,
		0
	)

InviteBackLabel.ZIndex =
	SETTINGS_BASE_ZINDEX
	+ 12

Create(
	"TextLabel",
	{
		Name =
			"InviteFriendsTitle",

		Parent =
			InviteHeader,

		BackgroundTransparency =
			1,

		Font =
			Enum.Font.SourceSansBold,

		TextSize =
			27,

		TextColor3 =
			Color3.new(
				1,
				1,
				1
			),

		Text =
			"Invite Friends",

		TextXAlignment =
			Enum.TextXAlignment.Center,

		TextYAlignment =
			Enum.TextYAlignment.Center,

		Size =
			UDim2.new(
				0,
				240,
				0,
				44
			),

		Position =
			UDim2.new(
				0.5,
				-132,
				0,
				8
			),

		ZIndex =
			SETTINGS_BASE_ZINDEX
			+ 11,
	}
)

-- ============================================================
-- SEARCH BOX
-- ============================================================

SearchFrame =
	Create(
		"Frame",
		{
			Name =
				"SearchFrame",

			Parent =
				InviteHeader,

			BackgroundTransparency = 1,

			BorderSizePixel = 1,

			BorderColor3 = Color3.fromRGB(170, 170, 170),

			Size = UDim2.new(0, 220, 0, 34),

			Position = UDim2.new(1, -228, 0, 15),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 10,
		}
	)

Create(
	"UICorner",
	{
		Parent =
			SearchFrame,

		CornerRadius =
			UDim.new(
				0,
				2
			),
	}
)

-- Hollow search-box outline: transparent inside, visible border only.
Create(
	"UIStroke",
	{
		Name = "SearchBorder",
		Parent = SearchFrame,
		Color = Color3.fromRGB(170, 170, 170),
		Thickness = 1,
		Transparency = 0,
	})

SearchIcon =
	Create(
		"ImageLabel",
		{
			Name = "SearchIcon",
			Parent = SearchFrame,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = "rbxassetid://124148806944890",
			ImageTransparency = 0,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(0, 8, 0.5, -10),
			ZIndex = SETTINGS_BASE_ZINDEX + 15,
		}
	)

SearchPlaceholder =
	Create(
		"TextLabel",
		{
			Name =
				"SearchPlaceholder",

			Parent =
				SearchFrame,

			BackgroundTransparency =
				1,

			Font =
				Enum.Font.SourceSans,

			TextSize =
				18,

			TextColor3 =
				Color3.fromRGB(
					190,
					190,
					190
				),

			Text =
				"Search for friends",

			TextXAlignment =
				Enum.TextXAlignment.Left,

			TextYAlignment =
				Enum.TextYAlignment.Center,


			Size = UDim2.new(1, -42, 1, 0),

			Position = UDim2.new(0, 34, 0, 0),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 11,
		}
	)

SearchBox =
	Create(
		"TextBox",
		{
			Name =
				"SearchBox",

			Parent =
				SearchFrame,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			ClearTextOnFocus =
				false,

			Font =
				Enum.Font.SourceSans,

			TextSize =
				18,

			TextColor3 =
				Color3.new(
					1,
					1,
					1
				),

			Text =
				"",

			PlaceholderText =
				"",

			TextXAlignment =
				Enum.TextXAlignment.Left,

			TextYAlignment =
				Enum.TextYAlignment.Center,

			BackgroundTransparency = 1,

			Size = UDim2.new(1, -42, 1, 0),

			Position = UDim2.new(0, 34, 0, 0),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 13,
		}
	)

Connect(
	SearchBox.Focused,
	function()

		SearchIcon.Visible =
			true

		SearchPlaceholder.Visible =
			false

	end
)

Connect(
	SearchBox.FocusLost,
	function()

		SearchIcon.Visible = IsMobile or SearchBox.Text == ""

		SearchPlaceholder.Visible =
			(not IsMobile) and SearchBox.Text == ""

	end
)

Connect(
	SearchBox:GetPropertyChangedSignal(
		"Text"
	),
	function()

		if RebuildInviteList then
			RebuildInviteList()
		end

		if IsMobile then
			SearchIcon.Visible = true
			SearchPlaceholder.Visible = false

		elseif
			SearchBox.Text ~= ""
			or SearchBox:IsFocused()
		then

			SearchIcon.Visible =
				false

			SearchPlaceholder.Visible =
				false

		else

			SearchIcon.Visible =
				true

			SearchPlaceholder.Visible =
				true

		end

	end
)

-- ============================================================
-- MOBILE INVITE SEARCH / HEADER BEHAVIOR
-- ============================================================
ConfigureInviteMobileHeader = function()
	if not InviteHeader or not SearchFrame or not SearchBox or not SearchIcon then return end
	if not IsMobile then
		InviteBackLabel.Text = "Back"
		InviteBackLabel.TextSize = 24
		SearchFrame.Size = UDim2.new(0, 220, 0, 34)
		SearchFrame.Position = UDim2.new(1, -228, 0, 15)
		SearchBox.Visible = true
		SearchPlaceholder.Visible = SearchBox.Text == ""
		SearchIcon.Visible = SearchBox.Text == "" or SearchBox:IsFocused()
		return
	end

	InviteBackLabel.Text = "<"
	InviteBackLabel.TextSize = 30
	InviteBackLabel.TextXAlignment = Enum.TextXAlignment.Center
	InviteBackLabel.TextYAlignment = Enum.TextYAlignment.Center
	InviteBackButton.Size = UDim2.fromOffset(44, 48)
	InviteBackButton.Position = UDim2.fromOffset(4, 4)
	InviteBackButton.Image = ""

	local Expanded = INVITE_MOBILE_SEARCH_EXPANDED
	local Width = Expanded and INVITE_MOBILE_SEARCH_WIDTH or INVITE_MOBILE_SEARCH_COLLAPSED
	SearchFrame.Size = UDim2.fromOffset(Width, 36)
	SearchFrame.Position = UDim2.new(1, -(Width + 6), 0, 10)
	SearchFrame.BackgroundTransparency = 1
	SearchFrame.BorderSizePixel = 0
	local SearchStroke = SearchFrame:FindFirstChildOfClass("UIStroke")
	if SearchStroke then
		SearchStroke.Transparency = Expanded and 0 or 1
	end
	SearchBox.Visible = Expanded
	SearchPlaceholder.Visible = false
	SearchIcon.Visible = true
	SearchIcon.Position = UDim2.fromOffset(8, 8)
	SearchIcon.Size = UDim2.fromOffset(20, 20)
	SearchBox.Position = UDim2.new(0, 34, 0, 0)
	SearchBox.Size = UDim2.new(1, -42, 1, 0)
end

Connect(SearchFrame.InputBegan, function(Input)
	if not IsMobile or not InviteList.Visible then return end
	if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
		INVITE_MOBILE_SEARCH_EXPANDED = true
		ConfigureInviteMobileHeader()
		Protect(function() SearchBox:CaptureFocus() end)
	end
end)

-- Invite-player selection: one exact-size SelectionImageObject per row.
-- Each selection image belongs to its own row and is destroyed with that row,
-- so there is never a second shared selection overlay left behind.
InviteSelectionButtons = {}
InviteSelectionFriends = {}
InviteSelectionInviteButtons = {}
InviteSelectionInviteLabels = {}
InviteSelectionImages = {}
InviteSelectedIndex = 0
InviteSelectedFriendId = nil

SetInviteGuiSelection = function(Button)
	if not Button or not Button.Parent then return end
	Protect(function()
		if GuiService.SelectedObject ~= Button then
			GuiService.SelectedObject = Button
		end
	end)
end

UpdateInviteSelectionVisual = function(PreviousIndex, Index)
	if PreviousIndex and PreviousIndex ~= 0 and PreviousIndex ~= Index then
		local PreviousImage = InviteSelectionImages[PreviousIndex]
		if PreviousImage then PreviousImage.Visible = false end
	end
	local Image = InviteSelectionImages[Index]
	if Image then Image.Visible = true end
end

HideInviteSelection = function()
	local Image = InviteSelectionImages[InviteSelectedIndex]
	if Image then Image.Visible = false end
	Protect(function() GuiService.SelectedObject = nil end)
	Protect(function() GuiService.SelectedCoreObject = nil end)
	InviteSelectedIndex = 0
	InviteSelectedFriendId = nil
end

KeepInviteSelectionVisible = function(Row)
	if not Row or not InviteList then return end
	local Top = Row.Position.Y.Offset
	local Bottom = Top + Row.AbsoluteSize.Y
	local Current = InviteList.CanvasPosition.Y
	local Window = InviteList.AbsoluteWindowSize.Y
	local Target = Current
	if Top < Current then
		Target = Top
	elseif Bottom > Current + Window then
		Target = Bottom - Window
	end
	local MaxY = math.max(0, InviteList.AbsoluteCanvasSize.Y - InviteList.AbsoluteWindowSize.Y)
	Target = math.clamp(Target, 0, MaxY)
	if math.abs(Target - Current) > 0.5 then
		InviteList.CanvasPosition = Vector2.new(0, Target)
	end
end

SetInviteSelection = function(Index, PreserveScroll)
	if #InviteSelectionButtons == 0 then
		InviteSelectedIndex = 0
		InviteSelectedFriendId = nil
		return
	end
	Index = math.clamp(tonumber(Index) or 1, 1, #InviteSelectionButtons)
	local Button = InviteSelectionButtons[Index]
	local Row = Button and Button.Parent
	if not Button or not Row then return end
	local OldIndex = InviteSelectedIndex
	InviteSelectedIndex = Index
	local Friend = InviteSelectionFriends[Index]
	InviteSelectedFriendId = Friend and tostring(Friend.Id) or nil
	if not PreserveScroll then KeepInviteSelectionVisible(Row) end
	UpdateInviteSelectionVisual(OldIndex, Index)
	if OldIndex ~= Index or GuiService.SelectedObject ~= Button then
		SetInviteGuiSelection(Button)
	end
end

Connect(UserInputService.InputBegan, function(Input, Processed)
	if not Hub.InInviteMenu or not InviteList.Visible or Processed then return end
	if SearchBox and SearchBox:IsFocused() then return end

	if Input.KeyCode == Enum.KeyCode.W or Input.KeyCode == Enum.KeyCode.Up then
		if InviteSelectedIndex > 1 then
			SetInviteSelection(InviteSelectedIndex - 1)
		end
		return
	end

	if Input.KeyCode == Enum.KeyCode.S or Input.KeyCode == Enum.KeyCode.Down then
		if InviteSelectedIndex < #InviteSelectionButtons then
			SetInviteSelection(InviteSelectedIndex + 1)
		end
		return
	end

	if IsMobile and Input.KeyCode == Enum.KeyCode.Left then
		INVITE_MOBILE_SEARCH_EXPANDED = false
		ConfigureInviteMobileHeader()
	end
end)

-- ============================================================
-- INVITE LIST
-- ============================================================

InviteList =
	Create(
		"ScrollingFrame",
		{
			Name =
				"InviteList",

			Parent =
				InvitePage.Frame,

			BackgroundTransparency =
				1,

			BorderSizePixel =
				0,

			Size =
				UDim2.new(
					1,
					-20,
					1,
					-70
				),

			Position =
				UDim2.new(
					0,
					10,
					0,
					65
				),

			CanvasSize =
				UDim2.new(
					0,
					0,
					0,
					0
				),

			ScrollBarThickness =
				0,

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 5,
		}
	)

INVITE_MOBILE_HEADER_DIVIDER = Create("Frame", {
	Name = "InviteHeaderDivider",
	Parent = InvitePage.Frame,
	BackgroundColor3 = Color3.fromRGB(120, 120, 120),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -20, 0, 1),
	Position = UDim2.new(0, 10, 0, 62),
	ZIndex = SETTINGS_BASE_ZINDEX + 14,
})

Connect(InviteList:GetPropertyChangedSignal("CanvasPosition"), function()
	if INVITE_MOBILE_HEADER_DIVIDER and InviteList.Parent then
		INVITE_MOBILE_HEADER_DIVIDER.Visible = InviteList.CanvasPosition.Y <= 0
	end
end)

InviteHeader.Visible =
	false

InviteList.Visible =
	false

InviteFriendsCache =
	{}

InviteSelectionButtons = InviteSelectionButtons or {}
InviteSelectionFriends = InviteSelectionFriends or {}
InviteSelectedIndex = InviteSelectedIndex or 0
InviteSelectedFriendId = InviteSelectedFriendId or nil

-- Persist invite state in getgenv so rebuilding the invite list,
-- leaving/reopening the ESC menu, or rerunning this script does not
-- forget which friends have already received an accepted invite.
InviteState =
	getgenv().Settings2016InviteState

if type(InviteState) ~= "table" then
	InviteState = {}
	getgenv().Settings2016InviteState = InviteState
end

CurrentInviteJobId = tostring(game.JobId or "")

if InviteState.JobId ~= CurrentInviteJobId then
	InviteState = {
		JobId = CurrentInviteJobId,
		InvitedFriendIds = {},
	}
	getgenv().Settings2016InviteState = InviteState
end

InvitedFriendIds =
	InviteState.InvitedFriendIds

if type(InvitedFriendIds) ~= "table" then
	InvitedFriendIds = {}
	InviteState.InvitedFriendIds = InvitedFriendIds
end

PendingInviteFriendIds =
	{}

ActiveInviteTargetId =
	nil

ActiveInviteFriend =
	nil

ActiveInviteButton =
	nil

ActiveInviteLabel =
	nil

InviteRows =
	{}

-- Legacy Roblox-style presence palette:
-- Online = cyan       #00A2FF
-- In Experience = green #00FF00
-- In Studio = orange  #FFB000
ONLINE_COLOR =
	Color3.fromRGB(
		0,
		162,
		255
	)

IN_EXPERIENCE_COLOR = Color3.fromRGB(2, 183, 90)

IN_STUDIO_COLOR = Color3.fromRGB(246, 136, 2)

OFFLINE_COLOR = Color3.fromRGB(128, 128, 128)

-- ============================================================
-- FRIEND STATUS
-- ============================================================

GetInviteStatus =
	function(
		Friend
	)

		if not Friend or not Friend.IsOnline then
			return
				"Offline",
				OFFLINE_COLOR
		end

		local LocationType =
			Friend.LocationType

		local NumericLocationType =
			type(LocationType) == "number"
			and LocationType
			or tonumber(LocationType)

		-- Roblox LocationType values:
		-- 0 = Mobile Website
		-- 1 = Mobile In-Experience
		-- 2 = Computer Website
		-- 3 = Computer Studio
		-- 4 = Computer In-Experience
		-- 5 = Xbox Website/App
		-- 6 = Studio / Team Create
		if NumericLocationType == 1
			or NumericLocationType == 4
		then
			return
				"In Experience",
				IN_EXPERIENCE_COLOR
		end

		if NumericLocationType == 3
			or NumericLocationType == 6
		then
			return
				"In Studio",
				IN_STUDIO_COLOR
		end

		return
			"Online",
			ONLINE_COLOR

	end

-- ============================================================
-- FETCH FRIENDS
-- ============================================================

FetchFriends =
	function()

		local Result =
			{}

		local Success, Pages =
			pcall(
				function()

					return
						Players:GetFriendsAsync(
							LocalPlayer.UserId
						)

				end
			)

		if
			Success
			and Pages
		then

			while true do

				for _, Friend in ipairs(
					Pages:GetCurrentPage()
				) do

					Insert(
						Result,
						{
							Id =
								Friend.Id,

							Username =
								Friend.Username
								or "",

							DisplayName =
								Friend.DisplayName
								or Friend.Username
								or "",

							IsOnline =
								Friend.IsOnline
								== true,

							LocationType =
								nil,

							Invited =
								InvitedFriendIds[
									tostring(Friend.Id)
								]
								== true,
						}
					)

				end

				if Pages.IsFinished then
					break
				end

				local Advanced =
					pcall(
						function()

							Pages:
								AdvanceToNextPageAsync()

						end
					)

				if not Advanced then
					break
				end

			end

		end

		local SuccessOnline,
			OnlineFriends =
			pcall(
				function()
					return
						LocalPlayer:
							GetFriendsOnlineAsync(
								200
							)
				end
			)

		-- Older clients expose GetFriendsOnline instead of the Async form.
		if not SuccessOnline or not OnlineFriends then
			SuccessOnline, OnlineFriends =
				pcall(
					function()
						return
							LocalPlayer:
								GetFriendsOnline(
									200
								)
					end
				)
		end

		if
			SuccessOnline
			and type(OnlineFriends) == "table"
		then

			local OnlineMap =
				{}

			for _, Online in ipairs(
				OnlineFriends
			) do

				local FriendId =
					Online.VisitorId
					or Online.UserId
					or Online.Id

				if FriendId then
					OnlineMap[tostring(FriendId)] = Online
				end

			end

			for _, Friend in ipairs(
				Result
			) do

				local Online =
					OnlineMap[tostring(Friend.Id)]

				if Online then
					Friend.IsOnline =
						Online.IsOnline ~= false
					Friend.LocationType =
						Online.LocationType
					Friend.PlaceId = Online.PlaceId
					Friend.GameId = Online.GameId
					Friend.LastLocation = Online.LastLocation
				end

			end

		end

		table.sort(
			Result,
			function(A, B)
				local function StatusRank(Friend)
					local Status = GetInviteStatus(Friend)
					if Status == "In Experience" then
						return 1
					elseif Status == "Online" then
						return 2
					elseif Status == "In Studio" then
						return 3
					end
					return 4
				end

				local ARank = StatusRank(A)
				local BRank = StatusRank(B)
				if ARank ~= BRank then
					return ARank < BRank
				end

				local AName = DisplayNameSupport and (A.DisplayName or A.Username) or A.Username
				local BName = DisplayNameSupport and (B.DisplayName or B.Username) or B.Username
				return string.lower(AName or "") < string.lower(BName or "")
			end
		)

		return Result

	end

FriendMatchesSearch =
	function(
		Friend,
		Query
	)

		Query =
			string.lower(
				Query
				or ""
			)

		if Query == "" then
			return true
		end

		if string.find(
			string.lower(
				Friend.Username
				or ""
			),
			Query,
			1,
			true
		) then

			return true

		end

		if
			DisplayNameSupport
			and string.find(
				string.lower(
					Friend.DisplayName
					or ""
				),
				Query,
				1,
				true
			)
		then

			return true

		end

		return false

	end

-- ============================================================
-- INVITE FUNCTION
-- ============================================================

ActiveInviteOptions =
	nil

InviteFriend =
	function(
		Friend,
		Button,
		Label
	)

		if
			not Friend
			or not Friend.Id
			or Friend.Invited
			or InvitedFriendIds[tostring(Friend.Id)] == true
		then
			return
		end

		local FriendId =
			tonumber(Friend.Id)

		if not FriendId then
			return
		end

		local FriendKey =
			tostring(FriendId)

		-- This is the invite path used by the older working Settings2016
		-- builds: open the targeted native prompt first, with a generic
		-- native-prompt fallback for clients that reject ExperienceInviteOptions.
		if ActiveInviteOptions then
			pcall(function()
				ActiveInviteOptions:Destroy()
			end)
			ActiveInviteOptions = nil
			ActiveInviteTargetId = nil
			ActiveInviteFriend = nil
			ActiveInviteButton = nil
			ActiveInviteLabel = nil
		end

		local Options = nil
		pcall(function()
			Options = Instance.new("ExperienceInviteOptions")
		end)

		local OptionsReady = false

		if Options then
			OptionsReady =
				pcall(function()
					Options.InviteUser = FriendId
				end)

			pcall(function()
				Options.PromptMessage =
					"Invite "
					.. (Friend.DisplayName or Friend.Username or "friend")
					.. " to join?"
				end)
		end

		local Success = false

		if Options and OptionsReady then
			ActiveInviteOptions = Options
			ActiveInviteTargetId = FriendId
			ActiveInviteFriend = Friend
			ActiveInviteButton = Button
			ActiveInviteLabel = Label

			Success =
				pcall(function()
					SocialService:PromptGameInvite(
						LocalPlayer,
						Options
					)
				end)
		end

		if not Success then
			if ActiveInviteOptions == Options then
				ActiveInviteOptions = nil
				ActiveInviteTargetId = nil
				ActiveInviteFriend = nil
				ActiveInviteButton = nil
				ActiveInviteLabel = nil
			end

			pcall(function()
				if Options then
					Options:Destroy()
				end
			end)

			Success =
				pcall(function()
					SocialService:PromptGameInvite(
						LocalPlayer
					)
				end)
		end

		if not Success then
			if Button then
				Button.ImageTransparency = 0
				Button.BackgroundTransparency = 1
				Button.Active = true
				Button.Selectable = false
			end

			if Label then
				Label.Text = "Invite"
				Label.TextColor3 = Color3.new(1, 1, 1)
				Label.TextTransparency = 0
			end
			return
		end

		-- Persist the invited target only after the native invite prompt
		-- successfully opened, exactly like the older working build.
		InvitedFriendIds[FriendKey] = true
		InviteState.InvitedFriendIds = InvitedFriendIds
		Friend.Invited = true
		PendingInviteFriendIds[FriendKey] = true

		if Button then
			Button.Image = ""
			Button.ImageTransparency = 1
			Button.BackgroundTransparency = 1
			Button.AutoButtonColor = false
			Button.Active = false
			Button.Selectable = false
		end

		if Label then
			Label.Text = "Invited..."
			Label.TextColor3 = INVITED_COLOR
			Label.TextTransparency = 0
		end
	end

-- ============================================================
-- ROBLOX NATIVE INVITE RESULT MONITOR
-- ============================================================

local InstallInvitePromptMonitor = function()
	local Existing = getgenv().Settings2016InvitePromptMonitorConnection
	if Existing then
		pcall(function()
			Existing:Disconnect()
		end)
	end

	local Success, Connection =
		pcall(function()
			return SocialService.GameInvitePromptClosed:Connect(
				function(Player, RecipientIds)
					if Player and LocalPlayer and Player ~= LocalPlayer then
						return
					end

					local TargetId = ActiveInviteTargetId
					local Friend = ActiveInviteFriend
					local Button = ActiveInviteButton
					local Label = ActiveInviteLabel
					local Options = ActiveInviteOptions

					if not TargetId then
						return
					end

					local FriendKey = tostring(TargetId)
					local WasActuallySent = InvitedFriendIds[FriendKey] == true

					if type(RecipientIds) == "table" then
						-- Roblox documents recipientIds as an array, but be defensive
						-- here because some client versions have returned table-like
						-- values with non-array keys.
						for _, RecipientId in pairs(RecipientIds) do
							if tonumber(RecipientId) == TargetId then
								WasActuallySent = true
								break
							end
						end
					end

					-- For a targeted InviteUser prompt, some Roblox client versions
					-- have been observed to close with an empty recipientIds table
					-- even after the native Invite button was used. The native prompt
					-- is still what performs the actual invite; this fallback only
					-- prevents the local UI from getting stuck on "Sending..." when
					-- Roblox fails to report the recipient.
					if not WasActuallySent and Options then
						local OptionInviteUser = nil
						pcall(function()
							OptionInviteUser = tonumber(Options.InviteUser)
						end)
						if OptionInviteUser == TargetId then
							WasActuallySent = true
						end
					end

					PendingInviteFriendIds[FriendKey] = nil

					if WasActuallySent then
						InvitedFriendIds[FriendKey] = true
						InviteState.InvitedFriendIds = InvitedFriendIds

						if Friend then
							Friend.Invited = true
						end

						-- The actual invite was sent by Roblox's native prompt.
						-- Hide the Invite button and leave the status as Invited....
						if Button then
							Button.ImageTransparency = 1
							Button.BackgroundTransparency = 1
							Button.AutoButtonColor = false
							Button.Active = false
							Button.Selectable = false
					end

						if Label then
							Label.Text = "Invited..."
							Label.TextColor3 = INVITED_COLOR
							Label.TextTransparency = 0
						end
					else
						-- The native prompt was closed without sending the selected
						-- friend. Restore the normal Invite action.
						if Button then
							Button.ImageTransparency = 0
							Button.BackgroundTransparency = 1
							Button.AutoButtonColor = false
							Button.Active = true
							Button.Selectable = false
					end

						if Label then
							Label.Text = "Invite"
							Label.TextColor3 = Color3.new(1, 1, 1)
							Label.TextTransparency = 0
						end
					end

					if ActiveInviteOptions == Options then
						ActiveInviteOptions = nil
						ActiveInviteTargetId = nil
						ActiveInviteFriend = nil
						ActiveInviteButton = nil
						ActiveInviteLabel = nil
					end

					pcall(function()
						if Options then
							Options:Destroy()
						end
					end)
				end
			)
		end)

	if Success and Connection then
		getgenv().Settings2016InvitePromptMonitorConnection = Connection
	end
end

InstallInvitePromptMonitor()

-- ============================================================
-- BUILD INVITE ROW
-- ============================================================

INVITE_ROW_HEIGHT =
	62

INVITE_ROW_GAP =
	10


INVITED_COLOR =
	Color3.fromRGB(
		190,
		190,
		190
	)

BuildInviteRow =
	function(
		Friend,
		Index
	)

		Friend.Invited =
			InvitedFriendIds[
				tostring(Friend.Id)
			]
			== true

		local Row =
			Create(
				"ImageLabel",
				{
					Name =
						"InviteFriend_"
						.. tostring(Friend.Id),

					Parent =
						InviteList,

					BackgroundTransparency =
						1,

					Image =
						"rbxasset://textures/ui/dialog_white.png",

					ImageTransparency =
						0.85,

					ScaleType =
						Enum.ScaleType.Slice,

					SliceCenter =
						Rect.new(
							10,
							10,
							10,
							10
						),

					Size =
						UDim2.new(
							1,
							0,
							0,
							62
						),

					ClipsDescendants = true,

					Position =
						UDim2.new(
							0,
							0,
							0,
							PLAYER_LIST_OFFSET
							+ ((Index - 1) * (INVITE_ROW_HEIGHT + INVITE_ROW_GAP))
						),

					ZIndex =
						SETTINGS_BASE_ZINDEX + 2,
				}
			)

		local SelectionButton =
			Create(
				"TextButton",
				{
					Name = "InviteSelectionButton",
					Parent = Row,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = "",
					TextTransparency = 1,
					AutoButtonColor = false,
					Active = true,
					Selectable = true,
					Size = UDim2.new(1, 0, 1, 0),
					Position = UDim2.new(0, 0, 0, 0),
					ClipsDescendants = true,
					ZIndex = SETTINGS_BASE_ZINDEX + 2,
				}
			)

		local SelectionAdorner =
			Create(
				"ImageLabel",
				{
					Name = "InviteSelectionImageObject",
					Parent = SelectionButton,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = "rbxasset://textures/ui/SelectionBox@2x.png",
					ImageTransparency = 1,
					ScaleType = Enum.ScaleType.Slice,
					SliceScale = 0.5,
					SliceCenter = Rect.new(36, 36, 88, 88),
					AnchorPoint = Vector2.new(0, 0),
					Position = UDim2.new(0, 0, 0, 0),
					Size = UDim2.new(1, 0, 1, 0),
					Visible = true,
					Active = false,
					Selectable = false,
					ZIndex = SETTINGS_BASE_ZINDEX + 7,
				}
			)

		local SelectionImage =
			Create(
				"ImageLabel",
				{
					Name = "InviteSelectionVisual",
					Parent = SelectionButton,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = "rbxasset://textures/ui/SelectionBox@2x.png",
					ScaleType = Enum.ScaleType.Slice,
					SliceScale = 0.5,
					SliceCenter = Rect.new(36, 36, 88, 88),
					AnchorPoint = Vector2.new(0, 0),
					Position = UDim2.new(0, -10, 0, -10),
					Size = UDim2.new(1, 20, 1, 20),
					ClipsDescendants = false,
					Visible = false,
					Active = false,
					Selectable = false,
					ZIndex = SETTINGS_BASE_ZINDEX + 8,
				}
			)

		SelectionButton.SelectionImageObject = SelectionAdorner

		Insert(InviteSelectionButtons, SelectionButton)
		Insert(InviteSelectionFriends, Friend)
		Insert(InviteSelectionImages, SelectionImage)
		local SelectionIndex = #InviteSelectionButtons

		Connect(
			SelectionButton.Activated,
			function()
				for i, Candidate in ipairs(InviteSelectionButtons) do
					if Candidate == SelectionButton then
						SetInviteSelection(i)
						return
					end
				end
			end
		)

		Connect(
			SelectionButton.SelectionGained,
			function()
				for i, Candidate in ipairs(InviteSelectionButtons) do
					if Candidate == SelectionButton then
						SetInviteSelection(i, true)
						return
					end
				end
			end
		)

		Connect(
			Row.InputBegan,
			function(Input)
				if Input.UserInputType == Enum.UserInputType.Touch
					or Input.UserInputType == Enum.UserInputType.MouseButton1
				then
					for i, Candidate in ipairs(InviteSelectionButtons) do
						if Candidate == SelectionButton then
							SetInviteSelection(i, true)
							return
						end
					end
				end
			end
		)

		Connect(
			Row.MouseEnter,
			function()
				Row.ImageTransparency =
					0.65
			end
		)

		Connect(
			Row.MouseLeave,
			function()
				Row.ImageTransparency =
					0.85
			end
		)

		local AvatarBackground =
			Create(
				"Frame",
				{
					Name = "AvatarBackground",
					Parent = Row,
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 0,
					BorderSizePixel = 2,
					BorderColor3 = Color3.fromRGB(205, 205, 205),
					Size = UDim2.new(0, 36, 0, 36),
					Position = UDim2.new(0, 12, 0.5, -18),
					ZIndex = SETTINGS_BASE_ZINDEX + 2,
				})


		local Avatar =
			Create(
				"ImageLabel",
				{
					Name = "Icon",
					Parent = Row,
					BackgroundTransparency = 1,
					Image =
						"rbxthumb://type=AvatarBust&id="
						.. tostring(tonumber(Friend.Id) or 1)
						.. "&w=100&h=100",
					Size = UDim2.new(0, 32, 0, 32),
					Position = UDim2.new(0, 14, 0.5, -16),
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = SETTINGS_BASE_ZINDEX + 3,
				}
			)

		local DisplayText =
			DisplayNameSupport
			and (Friend.DisplayName or Friend.Username)
			or Friend.Username

		Create(
			"TextLabel",
			{
				Name = "DisplayName",
				Parent = Row,
				BackgroundTransparency = 1,
				Font = Enum.Font.SourceSans,
				TextSize = 24,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = DisplayText,
				Size = UDim2.new(1, -330, 0, 30),
				Position = UDim2.new(0, 60, 0, 5),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			}
		)

		Create(
			"TextLabel",
			{
				Name = "Username",
				Parent = Row,
				BackgroundTransparency = 1,
				Font = Enum.Font.SourceSans,
				TextSize = 17,
				TextColor3 = Color3.fromRGB(190, 190, 190),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "@" .. (Friend.Username or ""),
				Size = UDim2.new(1, -330, 0, 22),
				Position = UDim2.new(0, 60, 0, 27),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			}
		)

		local StatusText, StatusColor =
			GetInviteStatus(Friend)

		Create(
			"TextLabel",
			{
				Name = "Status",
				Parent = Row,
				BackgroundTransparency = 1,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				TextColor3 = StatusColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = StatusText,
				Size = UDim2.new(1, -330, 0, 18),
				Position = UDim2.new(0, 60, 0, 40),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			}
		)

		-- ========================================================
		-- INVITE STATE DISPLAY
		-- ========================================================

		if Friend.Invited then

			local InviteButton, InviteLabel =
				MakeStyledButton(
					"InviteButton",
					"Invited...",
					UDim2.new(0, INVITE_BUTTON_WIDTH, 0, INVITE_BUTTON_HEIGHT)
				)

			InviteButton.Active = false
			InviteButton.Selectable = false
			InviteButton.AutoButtonColor = false
			InviteButton.ImageTransparency = 1
			InviteButton.BackgroundTransparency = 1
			InviteLabel.TextColor3 = INVITED_COLOR
			InviteLabel.TextWrapped = false
			InviteLabel.TextScaled = false
			InviteLabel.TextSize = 18
			InviteButton.Parent = Row
			InviteButton.ZIndex = SETTINGS_BASE_ZINDEX + 6
			InviteLabel.ZIndex = SETTINGS_BASE_ZINDEX + 7
			InviteButton.Position =
				UDim2.new(
					1,
					-(INVITE_BUTTON_WIDTH + 12),
					0.5,
					-(INVITE_BUTTON_HEIGHT / 2)
				)

			InviteSelectionInviteButtons[SelectionIndex] = InviteButton
			InviteSelectionInviteLabels[SelectionIndex] = InviteLabel

		else

			local InviteButton, InviteLabel =
				MakeStyledButton(
					"InviteButton",
					"Invite",
					UDim2.new(0, INVITE_BUTTON_WIDTH, 0, INVITE_BUTTON_HEIGHT)
				)

			InviteButton.Active = true
			InviteButton.Selectable = false
			InviteLabel.TextWrapped = false
			InviteLabel.TextScaled = false
			InviteLabel.TextSize = 18

			Connect(
				InviteButton.Activated,
				function()
					InviteFriend(
						Friend,
						InviteButton,
						InviteLabel
					)
				end
			)

			InviteButton.Parent = Row

			InviteSelectionInviteButtons[SelectionIndex] = InviteButton
			InviteSelectionInviteLabels[SelectionIndex] = InviteLabel

			InviteButton.ZIndex = SETTINGS_BASE_ZINDEX + 6
			local InviteButtonText = InviteButton:FindFirstChild("InviteButtonTextLabel")
			if InviteButtonText then
				InviteButtonText.ZIndex = SETTINGS_BASE_ZINDEX + 7
			end

			InviteButton.Position =
				UDim2.new(
					1,
					-(INVITE_BUTTON_WIDTH + 12),
					0.5,
					-(INVITE_BUTTON_HEIGHT / 2)
				)

		end

		return Row

	end

-- ============================================================
-- REBUILD INVITE LIST
-- ============================================================

UpdateInviteListScrollbar = function()
	if not InviteList then return end

	local ContentHeight = InviteList.CanvasSize.Y.Offset
	local WindowHeight = InviteList.AbsoluteWindowSize.Y
	if WindowHeight <= 0 then
		WindowHeight = InviteList.AbsoluteSize.Y
	end

	local NeedsScrollbar = ContentHeight > WindowHeight + 1
	InviteList.ScrollBarThickness = NeedsScrollbar and 6 or 0
	InviteList.VerticalScrollBarInset =
		NeedsScrollbar
		and Enum.ScrollBarInset.ScrollBar
		or Enum.ScrollBarInset.None
end

RebuildInviteList =
	function()

		local PreviousFriendId = InviteSelectedFriendId

		pcall(function()
			HideInviteSelection()
		end)

		for _, Row in next,
			InviteRows
		do

			pcall(
				function()
					Row:Destroy()
				end
			)

		end

		InviteRows =
			{}

		InviteSelectionButtons = {}
		InviteSelectionFriends = {}
		InviteSelectionInviteButtons = {}
		InviteSelectionInviteLabels = {}
		InviteSelectionImages = {}
		InviteSelectedIndex = 0

		local Count =
			0

		local Query =
			SearchBox.Text

		for _, Friend in ipairs(
			InviteFriendsCache
		) do

			if FriendMatchesSearch(
				Friend,
				Query
			) then

				Count +=
					1

				Insert(
					InviteRows,
					BuildInviteRow(
						Friend,
						Count
					)
				)

			end

		end

		for i, SelectionButton in ipairs(InviteSelectionButtons) do
			SelectionButton.NextSelectionUp = InviteSelectionButtons[math.max(1, i - 1)]
			SelectionButton.NextSelectionDown = InviteSelectionButtons[math.min(#InviteSelectionButtons, i + 1)]
			SelectionButton.NextSelectionLeft = SelectionButton
			SelectionButton.NextSelectionRight = SelectionButton
		end

		InviteList.CanvasSize =
			UDim2.new(
				0,
				0,
				0,
				math.max(
					0,
					Count * (INVITE_ROW_HEIGHT + INVITE_ROW_GAP)
					- INVITE_ROW_GAP
				)
			)

		UpdateInviteListScrollbar()
		Spawn(function()
			Wait()
			UpdateInviteListScrollbar()
		end)

		if Count > 0 then
			local NewIndex = 1
			if PreviousFriendId then
				for i, Friend in ipairs(InviteSelectionFriends) do
					if tostring(Friend.Id) == tostring(PreviousFriendId) then
						NewIndex = i
						break
					end
				end
			end
			SetInviteSelection(NewIndex, true)
		else
			InviteSelectedIndex = 0
			InviteSelectedFriendId = nil
		end

	end

RefreshInviteFriends =
	function()

		InviteFriendsCache =
			FetchFriends()

		RebuildInviteList()

	end

OpenInviteFriends =
	function()

		Hub.PreviousMenuPage =
			Hub.CurrentPage
			or PlayersPage

		Hub.InInviteMenu =
			true

		Hub.InConfirmation =
			false

		Hub.HubBar.Visible =
			false

		Hub.PageClipper.Visible =
			true

		Hub.BottomButtonFrame.Visible =
			false

		if HomeButton then
			HomeButton.Visible =
				false
		end

		InviteHeader.Visible =
			true

		InviteList.Visible =
			true

		if INVITE_MOBILE_HEADER_DIVIDER then INVITE_MOBILE_HEADER_DIVIDER.Visible = true end

		SearchBox.Text =
			""

		INVITE_MOBILE_SEARCH_EXPANDED = false
		if ConfigureInviteMobileHeader then ConfigureInviteMobileHeader() end

		SearchIcon.Visible =
			true

		SearchPlaceholder.Visible =
			true

		Hub.PageView.ScrollBarThickness =
			0

		SwitchToPage(
			InvitePage,
			true,
			true
		)

		InviteSelectedFriendId = nil
		RefreshInviteFriends()
		if #InviteSelectionButtons > 0 then
			SetInviteSelection(1)
		end

		ResizeHub()
		if InviteSelectedIndex > 0 then
			SetInviteSelection(InviteSelectedIndex, true)
		end
		if ConfigureInviteMobileHeader then ConfigureInviteMobileHeader() end

	end

-- ============================================================
-- GAME PAGE
-- ============================================================

GamePage =
	MakePage(
		"GameSettings"
	)

AddPage(
	GamePage,
	"Settings",
	"rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png",
	170
)

SavedCoreGuiState =
	{}

CoreGuiStateCaptured =
	false

TOPBAR_CORE_GUI_TYPES = {
	"Chat",
	"PlayerList",
	"Backpack",
	"Health",
	"EmotesMenu",
	"SelfView",
	"Captures",
}

SetTopbarCoreGuiEnabled =
	function(Enabled)

		if Enabled then

			if
				not CoreGuiStateCaptured
			then
				return
			end

			for Name, WasEnabled in next,
				SavedCoreGuiState
			do

				Protect(
					function()

						StarterGui:SetCoreGuiEnabled(
							Enum.CoreGuiType[Name],
							WasEnabled
						)

					end
				)

			end

			SavedCoreGuiState =
				{}

			CoreGuiStateCaptured =
				false

			return

		end

		if CoreGuiStateCaptured then
			return
		end

		SavedCoreGuiState =
			{}

		for _, Name in next,
			TOPBAR_CORE_GUI_TYPES
		do

			Protect(
				function()

					local CoreType =
						Enum.CoreGuiType[Name]

					if CoreType then

						SavedCoreGuiState[Name] =
							StarterGui:GetCoreGuiEnabled(
								CoreType
							)

						StarterGui:SetCoreGuiEnabled(
							CoreType,
							false
						)

					end

				end
			)

		end

		CoreGuiStateCaptured =
			true

	end

-- Directly enable/disable the live Roblox TopBarApp container.
-- In the current CoreGui hierarchy this is:
-- CoreGui.TopBarApp.TopBarApp
-- The custom ESC menu owns the top-left menu while this is disabled.
SetTopBarAppEnabled =
	function(Enabled)
		local Root = CoreGui:FindFirstChild("TopBarApp")
		local App = Root and Root:FindFirstChild("TopBarApp")
		if not App then return false end
		local Success = pcall(function()
			App.Enabled = Enabled
		end)
		return Success
	end

-- TopBarApp must stay hidden for the entire lifetime of the custom menu,
-- including the closing tween.  It may only reappear after the menu is
-- completely closed.
SyncTopBarAppVisibility =
	function()
		if Hub and Hub.Visible then
			SetTopBarAppEnabled(false)
		elseif SystemMenuButtonClosing == true then
			SetTopBarAppEnabled(false)
		else
			SetTopBarAppEnabled(true)
		end
	end

CameraDefaultString =
	IsTouchClient
	and "Default (Follow)"
	or "Default (Classic)"

MovementDefaultString =
	IsTouchClient
	and "Default (Thumbstick)"
	or "Default (Keyboard)"

ClickToMoveString =
	IsTouchClient
	and "Tap to Move"
	or "Click to Move"

MakeSectionHeader =
	function(
		Page,
		Title
	)

		local Row =
			MakeRow(
				Page,
				Title,
				64
			)

		local Label =
			Row:FindFirstChild(
				Title
				.. "Label"
			)

		if Label then

			Label.TextSize =
				28

			Label.TextColor3 =
				Color3.fromRGB(
					190,
					210,
					255
				)

			Label.Size =
				UDim2.new(
					1,
					-20,
					1,
					-10
				)

			Label.Position =
				UDim2.new(
					0,
					10,
					0,
					10
				)

		end

		return Row

	end

MakeButtonRow =
	function(
		Page,
		Name,
		Text,
		Clicked
	)

		local Row =
			MakeRow(
				Page,
				Name
			)

		local Button =
			MakeStyledButton(
				Name
					.. "Action",
				Text,
				UDim2.new(
					0,
					300,
					0,
					44
				),
				Clicked
			)

		Button.Parent =
			Row

		Button.Position =
			UDim2.new(
				1,
				-400,
				0.5,
				-22
			)

		return Button, Row

	end

MakeBooleanSelector =
	function(
		Page,
		Name,
		Object,
		Property,
		OnFirst,
		OffSecond
	)

		local Current =
			GetHiddenOrSetting(
				Object,
				Property,
				false
			)

		local Start =
			(
				(
					Current == true
					or Current == 1
				)
				and 1
			)
			or 2

		return MakeSelector(
			Page,
			Name,
			{
				OnFirst
					or "On",
				OffSecond
				or "Off",
			},
			Start,
			function(Index)

				local Value = Index == 1
				SetSetting(Object, Property, Value)
				if sethiddenproperty then
					pcall(function() sethiddenproperty(Object, Property, Value) end)
				end

			end
		)

	end

MakeSectionHeader(
	GamePage,
	"View & Controls"
)

MakeOverrideText =
	function(Row)

	return Create(
		"TextLabel",
		{
			Name = "DevOverrideLabel",
			Parent = Row,
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans,
			TextSize = 24,
			TextColor3 = Color3.new(1, 1, 1),
			Text = "Set by Developer",
			Visible = false,
			Size = UDim2.new(0, 200, 1, 0),
			Position = UDim2.new(1, -350, 0, 0),
			ZIndex = SETTINGS_BASE_ZINDEX + 3,
		}
	)

	end

SetChangerVisible =
	function(
		Changer,
		OverrideText,
		Visible
	)

	if Changer then
		Changer:SetInteractable(Visible)
		Changer.SelectorFrame.Visible = Visible
	end

	if OverrideText then
		OverrideText.Visible = not Visible
	end

	end

ShiftLockMode, ShiftLockOverride = nil, nil

if UserInputService.MouseEnabled and UserInputService.KeyboardEnabled then

	ShiftLockMode =
		MakeSelector(
			GamePage,
			"Shift Lock Switch",
			{"On", "Off"},
			(
				GameSettings.ControlMode
				== Enum.ControlMode.MouseLockSwitch
				and 1
			)
			or 2,
			function(Index)
				Protect(function()
					GameSettings.ControlMode =
						(
							Index == 1
							and Enum.ControlMode.MouseLockSwitch
						)
						or Enum.ControlMode.Classic
				end)
			end
		)

	ShiftLockOverride = MakeOverrideText(ShiftLockMode.RowFrame)

end

CameraItems =
	(
		IsTouchClient
		and Enum.TouchCameraMovementMode
		or Enum.ComputerCameraMovementMode
	):GetEnumItems()

CameraNames, CameraMap, CameraStart = {}, {}, 1

for Index, Item in next, CameraItems do
	local Name =
		(
			Item.Name == "Default"
			and CameraDefaultString
		)
		or Item.Name

	CameraNames[Index] = Name
	CameraMap[Name] = Item

	if
		(
			IsTouchClient
			and GameSettings.TouchCameraMovementMode == Item
		)
		or (
			not IsTouchClient
			and GameSettings.ComputerCameraMovementMode == Item
		)
	then
		CameraStart = Index
	end
end

CameraMode =
	MakeSelector(
		GamePage,
		"Camera Mode",
		CameraNames,
		CameraStart,
		function(_, Value)
			Protect(function()
				if IsTouchClient then
					GameSettings.TouchCameraMovementMode = CameraMap[Value]
				else
					GameSettings.ComputerCameraMovementMode = CameraMap[Value]
				end
			end)
		end
	)

CameraOverride = MakeOverrideText(CameraMode.RowFrame)

MoveItems =
	(
		IsTouchClient
		and Enum.TouchMovementMode
		or Enum.ComputerMovementMode
	):GetEnumItems()

MoveNames, MoveMap, MoveStart = {}, {}, 1

for Index, Item in next, MoveItems do
	local Name = Item.Name
	if Name == "Default" then
		Name = MovementDefaultString
	elseif Name == "KeyboardMouse" then
		Name = "Keyboard + Mouse"
	elseif Name == "ClickToMove" then
		Name = ClickToMoveString
	end

	MoveNames[Index] = Name
	MoveMap[Name] = Item

	if
		(
			IsTouchClient
			and GameSettings.TouchMovementMode == Item
		)
		or (
			not IsTouchClient
			and GameSettings.ComputerMovementMode == Item
		)
	then
		MoveStart = Index
	end
end

MovementMode =
	MakeSelector(
		GamePage,
		"Movement Mode",
		MoveNames,
		MoveStart,
		function(_, Value)
			Protect(function()
				if IsTouchClient then
					GameSettings.TouchMovementMode = MoveMap[Value]
				else
					GameSettings.ComputerMovementMode = MoveMap[Value]
				end
			end)
		end
	)

MovementOverride = MakeOverrideText(MovementMode.RowFrame)

UpdateDevChoiceSettings =
	function(Property)

		if ShiftLockMode and (not Property or Property == "DevEnableMouseLock") then
			local CanUseShiftLock = true
			Protect(function()
				CanUseShiftLock = LocalPlayer.DevEnableMouseLock
			end)
			SetChangerVisible(ShiftLockMode, ShiftLockOverride, CanUseShiftLock)
		end

		if not Property or Property == "DevComputerCameraMode" or Property == "DevTouchCameraMode" then
			local CanUseCamera = true
			Protect(function()
				CanUseCamera =
					(
						IsTouchClient
						and LocalPlayer.DevTouchCameraMode == Enum.DevTouchCameraMovementMode.UserChoice
					)
					or (
						not IsTouchClient
						and LocalPlayer.DevComputerCameraMode == Enum.DevComputerCameraMovementMode.UserChoice
					)
			end)
			SetChangerVisible(CameraMode, CameraOverride, CanUseCamera)
		end

		if not Property or Property == "DevComputerMovementMode" or Property == "DevTouchMovementMode" then
			local CanUseMovement = true
			Protect(function()
				CanUseMovement =
					(
						IsTouchClient
						and LocalPlayer.DevTouchMovementMode == Enum.DevTouchMovementMode.UserChoice
					)
					or (
						not IsTouchClient
						and LocalPlayer.DevComputerMovementMode == Enum.DevComputerMovementMode.UserChoice
					)
			end)
			SetChangerVisible(MovementMode, MovementOverride, CanUseMovement)
		end

	end

UpdateDevChoiceSettings()
Connect(LocalPlayer.Changed, UpdateDevChoiceSettings)

-- ============================================================
-- SETTING DESCRIPTIONS / SPECIAL SLIDERS
-- ============================================================

AddSettingDescription = function(Page, Row, Description)
	if not Page or not Row or not Description then return end

	local BaseName = Row.Name:gsub("Frame$", "")
	local MainLabel = Row:FindFirstChild(BaseName .. "Label")
	if MainLabel then
		MainLabel.Size = UDim2.new(0, 285, 0, 40)
		MainLabel.Position = UDim2.new(0, 10, 0, 0)
		MainLabel.TextYAlignment = Enum.TextYAlignment.Center
	end

	Page.DescriptionRows = Page.DescriptionRows or {}
	Page.DescriptionRows[Row] = true

	local Preferred = GuiService.PreferredTextSize
	local Height = 98
	if Preferred == Enum.PreferredTextSize.Large then
		Height = 104
	elseif Preferred == Enum.PreferredTextSize.Larger then
		Height = 110
	elseif Preferred == Enum.PreferredTextSize.Largest then
		Height = 116
	end
	Row.Size = UDim2.new(1, 0, 0, Height)

	for _, Child in ipairs(Row:GetChildren()) do
		if Child ~= MainLabel and Child:IsA("GuiObject") and Child.Name ~= "SettingDescription" then
			local XScale, XOffset = Child.Position.X.Scale, Child.Position.X.Offset
			local ChildHeight = Child.Size.Y.Offset
			local Y = (ChildHeight > 0 and ChildHeight <= 46) and 3 or 0
			Child.Position = UDim2.new(XScale, XOffset, 0, Y)
		end
	end

	local Desc = Row:FindFirstChild("SettingDescription")
	if not Desc then
		Desc = Create("TextLabel", {
			Name = "SettingDescription",
			Parent = Row,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.SourceSans,
			TextSize = 18,
			TextColor3 = Color3.fromRGB(158, 158, 158),
			TextTransparency = 0.05,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Text = Description,
			Size = UDim2.new(0, 430, 0, Height - 43),
			Position = UDim2.new(0, 10, 0, 43),
			ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})
	else
		Desc.Text = Description
		Desc.TextSize = 18
		Desc.Size = UDim2.new(0, 430, 0, Height - 43)
		Desc.Position = UDim2.new(0, 10, 0, 43)
	end

	if not Page.ReflowRows then
		Page.ReflowRows = function(Self)
			local Y = 0
			for _, Item in ipairs(Self.Rows) do
				Item.Position = UDim2.new(0, 0, 0, Y)
				Y += math.max(1, Item.Size.Y.Offset)
			end
			Self.NextY = Y
			Self.Frame.Size = UDim2.new(1, 0, 0, Self.NextY + PAGE_TOP_PADDING)
		end
	end
	Page:ReflowRows()
end

StretchSliderBars = function(Slider, StartX, EndX, BarWidth, RightHitWidth, RequestedGap)
	if not Slider or not Slider.SliderFrame then return end
	local Holder = Slider.SliderFrame
	local Segments = {}
	local Left = nil
	local Right = nil
	local Capture = nil

	for _, Child in ipairs(Holder:GetChildren()) do
		if Child:IsA("ImageButton") then
			local IsLeft, IsRight = false, false
			for _, Descendant in ipairs(Child:GetChildren()) do
				if Descendant:IsA("ImageLabel") then
					if Descendant.Image == SLIDER_LEFT_IMAGE then IsLeft = true end
					if Descendant.Image == SLIDER_RIGHT_IMAGE then IsRight = true end
				end
			end
			if IsLeft then
				Left = Child
			elseif IsRight then
				Right = Child
			else
				Insert(Segments, Child)
			end
		elseif Child:IsA("TextButton") then
			Capture = Child
		end
	end

	table.sort(Segments, function(A, B)
		return A.Position.X.Offset < B.Position.X.Offset
	end)
	if #Segments == 0 then return end

	local HolderWidth = Holder.Size.X.Offset
	local RightWidth = RightHitWidth or 42
	local Start = math.max(0, StartX or 60)
	local MaxFinish = math.max(Start + 1, HolderWidth - RightWidth - 2)
	local Finish = math.min(MaxFinish, EndX or MaxFinish)
	if Finish <= Start then Finish = MaxFinish end

	-- Match the normal Roblox slider look: a small, consistent gap between
	-- neighboring segments rather than having them touch or melt together.
	local TrackWidth = Finish - Start
	local SegmentGap = RequestedGap or 4
	local SegmentWidth =
		(TrackWidth - (SegmentGap * (#Segments - 1))) / #Segments
	local Width = math.max(1, math.floor(math.min(BarWidth or SegmentWidth, SegmentWidth) + 0.5))

	for Index, Segment in ipairs(Segments) do
		local X =
			Start
			+ ((Index - 1) * (SegmentWidth + SegmentGap))
		Segment.Size = UDim2.new(0, Width, 0, 25)
		Segment.Position = UDim2.new(0, math.floor(X + 0.5), 0.5, -12)
		Segment.AutoButtonColor = false
	end

	if Left then
		Left.AnchorPoint = Vector2.new(1, 0.5)
		Left.Position = UDim2.new(0, math.floor(Start + 0.5), 0.5, 0)
		Left.Size = UDim2.new(0, RightWidth, 0, 50)
	end

	if Right then
		Right.AnchorPoint = Vector2.new(0, 0.5)
		Right.Position = UDim2.new(0, math.floor(Finish + 2 + 0.5), 0.5, 0)
		Right.Size = UDim2.new(0, RightWidth, 0, 50)
	end

	if Capture then
		Capture.Position = UDim2.new(0, Start, 0, 0)
		Capture.Size = UDim2.new(0, math.max(0, Finish - Start), 0, 48)
		Capture.ZIndex = SETTINGS_BASE_ZINDEX + 5
	end
end

FixedTextSizeRoots = {}
FixedTextSizeObjects = {}
FixedTextSizeConnections = {}

IsFixedTextSizeObject = function(Object)
	if not Object then return false end
	if not (Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("TextBox")) then
		return false
	end
	for _, Root in ipairs(FixedTextSizeRoots) do
		if Root and (Object == Root or Object:IsDescendantOf(Root)) then
			return true
		end
	end
	return false
end

RegisterFixedTextSizeObject = function(Object)
	if not IsFixedTextSizeObject(Object) or Object.TextScaled == true then return end
	if FixedTextSizeObjects[Object] == nil then
		FixedTextSizeObjects[Object] = Object.TextSize
	end
end

RegisterFixedTextSizeObjects = function()
	FixedTextSizeRoots = {}
	FixedTextSizeObjects = {}
	if Hub and Hub.HubBar then table.insert(FixedTextSizeRoots, Hub.HubBar) end
	if Hub and Hub.BottomButtonFrame then table.insert(FixedTextSizeRoots, Hub.BottomButtonFrame) end
	for _, Root in ipairs(FixedTextSizeRoots) do
		for _, Object in ipairs(Root:GetDescendants()) do
			RegisterFixedTextSizeObject(Object)
		end
		if FixedTextSizeConnections[Root] then
			Protect(function() FixedTextSizeConnections[Root]:Disconnect() end)
		end
		FixedTextSizeConnections[Root] = Connect(Root.DescendantAdded, function(Object)
			RegisterFixedTextSizeObject(Object)
		end)
	end
end

RestoreFixedTextSizes = function()
	-- Capture any newly-created excluded text before restoring it.
	for _, Root in ipairs(FixedTextSizeRoots) do
		if Root and Root.Parent then
			for _, Object in ipairs(Root:GetDescendants()) do
				RegisterFixedTextSizeObject(Object)
			end
		end
	end
	for Object, BaseSize in next, FixedTextSizeObjects do
		if Object and Object.Parent and IsFixedTextSizeObject(Object) then
			Object.TextSize = BaseSize
		end
	end
end

SetPreferredTextSize = function(Value)
	local Written = false
	if sethiddenproperty then
		local Ok = pcall(function()
			sethiddenproperty(GuiService, "PreferredTextSize", Value)
		end)
		Written = Ok or Written
		Ok = pcall(function()
			sethiddenproperty(GameSettings, "PreferredTextSize", Value)
		end)
		Written = Ok or Written
	end
	if not Written then
		Written = Protect(function()
			GuiService.PreferredTextSize = Value
			return true
		end) or false
	end
	RestoreFixedTextSizes()
	return Written
end

-- ============================================================
-- CAMERA SENSITIVITY (0.2 = zero bars)
-- ============================================================

CameraSensitivityValues = {0.36, 0.52, 0.68, 0.84, 1, 1.6, 2.2, 2.8, 3.4, 4}
FormatCameraSensitivity = function(Value)
	local Text = string.format("%.2f", tonumber(Value) or 0.2)
	Text = Text:gsub("0+$", ""):gsub("%.$", "")
	return Text
end
CameraSensitivityCurrent = Clamp(tonumber(GetSetting(GameSettings, "MouseSensitivity", 0.2)) or 0.2, 0.2, 4)

GetCameraSensitivityIndex = function(Value)
	Value = Clamp(tonumber(Value) or 0.2, 0.2, 4)
	if Value <= 0.28 then return 0 end
	local BestIndex, BestDistance = 1, math.huge
	for Index, Preset in ipairs(CameraSensitivityValues) do
		local Distance = math.abs(Preset - Value)
		if Distance < BestDistance then
			BestDistance = Distance
			BestIndex = Index
		end
	end
	return BestIndex
end

CameraSensitivitySlider = MakeSlider(
	GamePage,
	"Camera Sensitivity",
	10,
	GetCameraSensitivityIndex(CameraSensitivityCurrent),
	function(Index)
		local Value = (Index == 0 and 0.2) or CameraSensitivityValues[Clamp(Index, 1, 10)]
		CameraSensitivityCurrent = Value
		SetMouseSensitivity(Value)
		if CameraSensitivityNumber then
			CameraSensitivityNumber.Text = FormatCameraSensitivity(Value)
		end
	end,
	0,
	true
)

CameraSensitivitySlider.SliderFrame.Size = UDim2.new(0, 500, 0, 50)
CameraSensitivitySlider.SliderFrame.Position = UDim2.new(1, -502, 0.5, -25)
StretchSliderBars(CameraSensitivitySlider, 54, 414, nil, 24)

CameraSensitivityNumberFrame = Create("Frame", {
	Name = "CameraSensitivityNumberFrame",
	Parent = CameraSensitivitySlider.RowFrame,
	BackgroundColor3 = Color3.fromRGB(58, 58, 58),
	BackgroundTransparency = 0,
	BorderSizePixel = 2,
	BorderColor3 = Color3.fromRGB(205, 205, 205),
	Size = UDim2.new(0, 50, 0, 38),
	Position = UDim2.new(1, -52, 0.5, -19),
	ZIndex = SETTINGS_BASE_ZINDEX + 6,
})

CameraSensitivityNumber = Create("TextBox", {
	Name = "Value",
	Parent = CameraSensitivityNumberFrame,
	BackgroundColor3 = Color3.fromRGB(58, 58, 58),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.SourceSans,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	Text = FormatCameraSensitivity(CameraSensitivityCurrent),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Size = UDim2.new(1, -4, 1, -4),
	Position = UDim2.new(0, 2, 0, 2),
	ZIndex = SETTINGS_BASE_ZINDEX + 7,
})

Connect(CameraSensitivityNumber.FocusLost, function()
	local Value = tonumber(CameraSensitivityNumber.Text)
	if not Value then
		CameraSensitivityNumber.Text = FormatCameraSensitivity(CameraSensitivityCurrent)
		return
	end
	Value = Clamp(Value, 0.2, 4)
	CameraSensitivityCurrent = Value
	SetMouseSensitivity(Value)
	CameraSensitivitySlider:SetValue(GetCameraSensitivityIndex(Value))
	CameraSensitivityNumber.Text = FormatCameraSensitivity(Value)
end)

Protect(function()
	Connect(GameSettings:GetPropertyChangedSignal("MouseSensitivity"), function()
		local Value = Clamp(tonumber(GameSettings.MouseSensitivity) or 0.2, 0.2, 4)
		CameraSensitivityCurrent = Value
		CameraSensitivitySlider:SetValue(GetCameraSensitivityIndex(Value))
		if not CameraSensitivityNumber:IsFocused() then
			CameraSensitivityNumber.Text = FormatCameraSensitivity(Value)
		end
	end)
end)

-- This is the real Roblox output-device selector.  It is intentionally
-- independent of Voice Chat: it controls the destination for experience audio.
OutputDeviceNames, OutputDeviceMap, CurrentOutputName, CurrentOutputGuid =
	GetOutputDeviceOptions()

if #OutputDeviceNames > 0 then
	local CurrentOutputIndex = 1

	for Index, Name in ipairs(OutputDeviceNames) do
		local Info = OutputDeviceMap[Name]
		if Info
			and CurrentOutputName
			and CurrentOutputName == Info.Name
			and (not CurrentOutputGuid or CurrentOutputGuid == "" or CurrentOutputGuid == Info.Guid)
		then
			CurrentOutputIndex = Index
			break
		end
	end

	AudioOutputSelector = MakeSelector(
		GamePage,
		"Output Device",
		OutputDeviceNames,
		CurrentOutputIndex,
		function(Index, Value)
			local Info = OutputDeviceMap[Value]
			if not Info then
				return
			end

			if not SetRealOutputDevice(Info.Name, Info.Guid) then
				local ActualName, ActualGuid = GetOutputDeviceInfo()
				for DeviceIndex, DeviceName in ipairs(OutputDeviceNames) do
					local ActualInfo = OutputDeviceMap[DeviceName]
					if ActualInfo
						and ActualName == ActualInfo.Name
						and (not ActualGuid or ActualGuid == "" or ActualGuid == ActualInfo.Guid)
					then
						AudioOutputSelector:SetSelectionIndex(DeviceIndex, false)
						break
					end
				end
			end
		end
	)
end

MakeSlider(
	GamePage,
	"Volume",
	10,
	Floor((GameSettings.MasterVolume or 1) * 10),
	function(Value)
		SetMasterVolume(Value / 10)
		PlayVolumeChangeSound()
	end
)

-- Only expose voice controls when this experience supports default voice and
-- the local account is voice-enabled. Never create a synthetic AudioDeviceInput.
GetGameVoiceSupport = function()
	local ReadOk, Enabled = pcall(function()
		return VoiceChatService.EnableDefaultVoice
	end)
	if ReadOk and Enabled == true then return true end

	-- A protected property read may be denied in the client. Check evidence from
	-- actual Roblox-created voice objects and live voice state before deciding
	-- that the experience has no voice support.
	local HasEvidence = false
	for _, Player in ipairs(Players:GetPlayers()) do
		if GetAudioDeviceInput(Player) then
			HasEvidence = true
			break
		end
	end

	if not HasEvidence and VoiceChatInternal then
		pcall(function()
			local GroupId = tostring(VoiceChatInternal:GetGroupId() or "")
			if GroupId ~= "" then HasEvidence = true end
		end)
		if not HasEvidence then
			pcall(function()
				local Participants = VoiceChatInternal:GetParticipants()
				HasEvidence = type(Participants) == "table" and next(Participants) ~= nil
			end)
		end
		if not HasEvidence then
			pcall(function()
				HasEvidence = VoiceChatInternal:IsContextVoiceEnabled() == true
			end)
		end
	end

	if not HasEvidence then
		pcall(function() RefreshNativeVoiceMirrorCache(true) end)
		for _, Icon in pairs(NativeVoiceIconObjects) do
			if Icon and Icon.Parent then HasEvidence = true break end
		end
	end

	if HasEvidence then return true end
	-- Some clients/games expose the legacy VoiceChatInternal controller while
	-- EnableDefaultVoice is false or reports the modern path only. Do not hide
	-- every voice control before the first participant/input has been created.
	if ReadOk and Enabled == false then
		return HasVoiceConnectionControls == true or HasMicDeviceControls == true
	end
	return HasVoiceConnectionControls == true or HasMicDeviceControls == true
end

GetAccountVoiceAllowed = function()
	local Allowed = false
	local Success = pcall(function()
		Allowed = VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId) == true
	end)
	if Success then return Allowed end
	-- Fall back only when the public local-entitlement query is unavailable,
	-- not when Roblox explicitly says the account is ineligible.
	if VoiceChatInternal then
		local Ok, Value = pcall(function() return VoiceChatInternal:IsContextVoiceEnabled() == true end)
		if Ok then return Value end
	end
	if GetAudioDeviceInput(LocalPlayer) then return true end
	return FindNativeVoiceIcon(LocalPlayer) ~= nil
end

HasVoiceConnectionControls = false
HasMicDeviceControls = false
if VoiceChatInternal then
	local Ok, Available = pcall(function()
		return type(VoiceChatInternal.GetGroupId) == "function"
			and type(VoiceChatInternal.JoinByGroupId) == "function"
			and type(VoiceChatInternal.Leave) == "function"
	end)
	HasVoiceConnectionControls = Ok and Available == true
	local MicOk, MicAvailable = pcall(function()
		return type(VoiceChatInternal.GetMicDevices) == "function"
			and type(VoiceChatInternal.SetMicDevice) == "function"
	end)
	HasMicDeviceControls = MicOk and MicAvailable == true
end

VoiceGameSupported = GetGameVoiceSupport()
VoiceAccountAllowed = GetAccountVoiceAllowed()
VoiceOptionAvailable = VoiceGameSupported and VoiceAccountAllowed

-- Do not change VoiceChatService.UseAudioApi from the client. Roblox owns the
-- Audio API rollout and creates the real AudioDeviceInput when that path is active.
VoiceInitiallyConnected = VoiceOptionAvailable and IsLocalVoiceConnectionReady()
-- Do not expose an On/Off connection selector: voice is auto-requested whenever
-- the experience supports voice and Roblox confirms that this local account is eligible.
VoiceChatEnabled = VoiceOptionAvailable == true
VoiceChatDesiredOn = VoiceOptionAvailable == true
RefreshLocalVoiceState()
VoiceChatSelector = nil

AudioInputSelector = nil
if VoiceOptionAvailable and HasMicDeviceControls then
	-- Device switching is available only when this client exposes the real controller.
	GetMicDeviceOptions = function()
		local Names = {"Default"}
		MicDeviceMap = {Default = {Name = "", Guid = ""}}
		local Seen = {Default = true}

		local function AddDevice(Name, Guid)
			if Name == nil then return end
			Name = tostring(Name)
			if Name == "" or Seen[Name] then return end
			Guid = tostring(Guid or "")
			Seen[Name] = true
			table.insert(Names, Name)
			MicDeviceMap[Name] = {Name = Name, Guid = Guid}
		end

		local function ParseDevice(Device, Depth)
			if type(Device) ~= "table" or (Depth or 0) > 5 then return end
			local Name = Device.Name or Device.name or Device.DisplayName or Device.displayName or Device.DeviceName or Device.deviceName
			local Guid = Device.Guid or Device.guid or Device.Id or Device.id or Device.DeviceGuid or Device.deviceGuid
			if Name then AddDevice(Name, Guid) end
			for Key, Child in next, Device do
				if type(Child) == "table" then
					ParseDevice(Child, (Depth or 0) + 1)
				elseif type(Key) == "number" and type(Child) == "string" then
					AddDevice(Child, "")
				end
			end
		end

		if VoiceChatInternal then
			pcall(function()
				local Returned = {VoiceChatInternal:GetMicDevices()}
				for _, Value in next, Returned do
					if type(Value) == "table" then ParseDevice(Value, 0) end
				end
			end)
		end
		return Names
	end

	MicDeviceNames = GetMicDeviceOptions()
	AudioInputSelector = MakeSelector(GamePage, "Audio Input Device", MicDeviceNames, 1, function(Index, Value)
		local Info = MicDeviceMap and MicDeviceMap[Value]
		if not Info or not VoiceChatInternal then return end
		pcall(function() VoiceChatInternal:SetMicDevice(Info.Name, Info.Guid) end)
	end)
end

RemoveVoiceFeatureRows = function()
	local function RemoveRow(Selector)
		local Row = Selector and Selector.RowFrame
		if not Row then return end
		if GamePage and GamePage.Rows then
			for Index = #GamePage.Rows, 1, -1 do
				if GamePage.Rows[Index] == Row then table.remove(GamePage.Rows, Index) end
			end
		end
		pcall(function() Row:Destroy() end)
	end
	RemoveRow(VoiceChatSelector)
	RemoveRow(AudioInputSelector)
	VoiceChatSelector = nil
	AudioInputSelector = nil
	if GamePage and GamePage.ReflowRows then pcall(function() GamePage:ReflowRows() end) end
end

-- Rebuild now that VoiceGameSupported is initialized. The very first player-list
-- build occurs earlier in startup, before this eligibility check has a value.
if RebuildPlayersPage then RebuildPlayersPage() end

Spawn(function()
	while ScreenGui and ScreenGui.Parent do
		Wait(VoiceOptionAvailable and 8 or 1.5)
		local NewGameSupport = GetGameVoiceSupport()
		local NewAccountAllowed = GetAccountVoiceAllowed()
		if VoiceChatDesiredOn then
			NewGameSupport = NewGameSupport or VoiceGameSupported
			NewAccountAllowed = NewAccountAllowed or VoiceAccountAllowed
		end
		local NewOptionAvailable = NewGameSupport and NewAccountAllowed
		local Changed = NewGameSupport ~= VoiceGameSupported
			 or NewAccountAllowed ~= VoiceAccountAllowed
			 or NewOptionAvailable ~= VoiceOptionAvailable
		local SupportBecameAvailable = NewGameSupport == true and VoiceGameSupported ~= true
		VoiceGameSupported = NewGameSupport
		VoiceAccountAllowed = NewAccountAllowed
		VoiceOptionAvailable = NewOptionAvailable
		if SupportBecameAvailable then
			for _, Player in ipairs(Players:GetPlayers()) do
				if Player ~= LocalPlayer then
					local Id = tonumber(Player.UserId) or 0
					if VoiceEnabledCache[Id] == false then VoiceEnabledCache[Id] = nil end
				end
			end
		end
		if VoiceOptionAvailable and not VoiceChatDesiredOn then
			SetVoiceChatPreference(true)
		elseif not VoiceOptionAvailable then
			VoiceChatDesiredOn = false
			VoiceChatEnabled = false
			LocalVoiceEnabled = false
		end
		if Changed then
			if RebuildPlayersPage then RebuildPlayersPage() end
			if ConfigureMobileActionButtons then ConfigureMobileActionButtons() end
		end
	end
end)

-- Voice auto-connection is requested after the custom UI and player list are initialized.

MakeSectionHeader(GamePage, "Chat & Language")

MakeButtonRow(
	GamePage,
	"Give Translation Feedback",
	"Give Feedback",
	function()
		RunAfterMenuCloses(function()
			pcall(function()
				SocialService:PromptFeedbackSubmissionAsync()
			end)
		end)
	end
)

AutomaticChatTranslationSelector = MakeBooleanSelector(GamePage, "Automatic Chat Translation", TextChatService, "ChatTranslationEnabled", "On", "Off")

ChatTranslationLanguageMap = {
	{"Arabic", "ar"},
	{"Chinese (Simplified)", "zh-cn"},
	{"Chinese (Traditional)", "zh-tw"},
	{"English", "en-us"},
	{"French", "fr-fr"},
	{"German", "de-de"},
	{"Hindi", "hi-in"},
	{"Indonesian", "id-id"},
	{"Italian", "it-it"},
	{"Japanese", "ja-jp"},
	{"Korean", "ko-kr"},
	{"Polish", "pl-pl"},
	{"Portuguese", "pt-br"},
	{"Russian", "ru-ru"},
	{"Spanish", "es-es"},
	{"Thai", "th-th"},
	{"Turkish", "tr-tr"},
	{"Vietnamese", "vi-vn"},
}

-- The endpoint is the Roblox language service for automatic-translation target languages.
-- When HTTP is unavailable, keep the same current Roblox-supported list above.
FetchChatTranslationLanguages = function()
	local Result = {}
	local Seen = {}
	local function AddLocale(Locale)
		Locale = tostring(Locale or ""):lower()
		for _, Item in ipairs(ChatTranslationLanguageMap) do
			if Item[2] == Locale and not Seen[Locale] then
				Seen[Locale] = true
				table.insert(Result, Item)
				return
			end
		end
	end

	local ResponseBody = nil
	local Url = "https://gameinternationalization.roblox.com/v1/automatic-translation/languages/en/target-languages"
	Protect(function()
		if game.HttpGet then
			ResponseBody = game:HttpGet(Url)
		end
	end)
	if ResponseBody then
		Protect(function()
			local Decoded = HttpService:JSONDecode(ResponseBody)
			local List = Decoded
			if type(Decoded) == "table" then
				List = Decoded.target_languages or Decoded.languages or Decoded.data or Decoded
			end
			if type(List) == "table" then
				for _, Item in ipairs(List) do
					if type(Item) == "string" then
						AddLocale(Item)
					elseif type(Item) == "table" then
						AddLocale(Item.language_code or Item.locale or Item.code or Item.target_language_code)
					end
				end
			end
		end)
	end

	if #Result == 0 then
		for _, Item in ipairs(ChatTranslationLanguageMap) do
			table.insert(Result, Item)
		end
	end
	return Result
end

ChatTranslationLanguageEntries = FetchChatTranslationLanguages()
ChatTranslationLanguageNames = {}
ChatTranslationLanguageCodes = {}
for Index, Item in ipairs(ChatTranslationLanguageEntries) do
	ChatTranslationLanguageNames[Index] = Item[1]
	ChatTranslationLanguageCodes[Item[1]] = Item[2]
end

NormalizeChatTranslationLocale = function(Locale)
	Locale = tostring(Locale or ""):lower():gsub("_", "-")
	return Locale
end

ChatTranslationLocaleForUserGameSettings = function(Locale)
	return NormalizeChatTranslationLocale(Locale):gsub("-", "_")
end

CurrentChatTranslationLocale = NormalizeChatTranslationLocale(
	GetHiddenOrSetting(GameSettings, "ChatTranslationLocale", "en_us")
)
if CurrentChatTranslationLocale == "" then
	CurrentChatTranslationLocale = "en-us"
end

local CurrentChatTranslationLanguageIndex = nil
for Index, Item in ipairs(ChatTranslationLanguageEntries) do
	if NormalizeChatTranslationLocale(Item[2]) == CurrentChatTranslationLocale then
		CurrentChatTranslationLanguageIndex = Index
		break
	end
end

-- A missing/unknown locale must never silently become the first item (Arabic).
-- English is the safe/default UI selection when Roblox has no usable saved locale.
if not CurrentChatTranslationLanguageIndex then
	for Index, Item in ipairs(ChatTranslationLanguageEntries) do
		if NormalizeChatTranslationLocale(Item[2]) == "en-us" then
			CurrentChatTranslationLanguageIndex = Index
			break
		end
	end
end
CurrentChatTranslationLanguageIndex = CurrentChatTranslationLanguageIndex or 1

ChatTranslationLanguageSelector = MakeDropDown(
	GamePage,
	"Chat Translation Language",
	ChatTranslationLanguageNames,
	CurrentChatTranslationLanguageIndex,
	function(Index, Value)
		local Locale = ChatTranslationLanguageCodes[Value]
		if not Locale then return end

		-- Update our UI state immediately; the hidden engine property may be delayed.
		CurrentChatTranslationLocale = NormalizeChatTranslationLocale(Locale)
		local EngineLocale = ChatTranslationLocaleForUserGameSettings(Locale)

		if sethiddenproperty then
			pcall(function()
				sethiddenproperty(GameSettings, "ChatTranslationLocale", EngineLocale)
			end)
		end
		Protect(function() GameSettings.ChatTranslationLocale = EngineLocale end)
	end
)

-- The language row needs a little more left room than the generic dropdown layout.
ChatTranslationLanguageSelector.DropDownFrame.Position =
	UDim2.new(
		1,
		-410,
		0.5,
		-22
	)

Protect(function()
	Connect(GameSettings:GetPropertyChangedSignal("ChatTranslationLocale"), function()
		local Locale = NormalizeChatTranslationLocale(GetHiddenOrSetting(GameSettings, "ChatTranslationLocale", CurrentChatTranslationLocale))
		CurrentChatTranslationLocale = Locale
		for Index, Item in ipairs(ChatTranslationLanguageEntries) do
			if NormalizeChatTranslationLocale(Item[2]) == Locale and ChatTranslationLanguageSelector:GetSelectedValue() ~= Item[1] then
				ChatTranslationLanguageSelector:SetSelectionByValue(Item[1], false)
				break
			end
		end
	end)
end)

ViewUntranslatedMessagesSelector = MakeBooleanSelector(GamePage, "View Untranslated Messages", GameSettings, "ChatTranslationFTUXShown", "On", "Off")


MakeSectionHeader(GamePage, "Display & Graphics")

MakeSelector(
	GamePage,
	"Fullscreen",
	{"On", "Off"},
	(GameSettings:InFullScreen() and 1) or 2,
	function()
		Protect(function()
			local Success = pcall(function()
				GuiService:ToggleFullscreen()
			end)
			if not Success and keypress and keyrelease then
				keypress(0x7A)
				keyrelease(0x7A)
			end
		end)
	end
)

QualityLevels = {}
SavedQualityLevels = {}

-- ============================================================
-- DYNAMIC ENUM DISCOVERY
-- ============================================================

Protect(
	function()
		for _, Item in ipairs(Enum.QualityLevel:GetEnumItems()) do

			local LevelNumber =
				tonumber(
					Item.Name:match("Level(%d+)$")
				)

			if LevelNumber then
				QualityLevels[LevelNumber] = Item
			end

		end
	end
)

Protect(
	function()
		for _, Item in ipairs(Enum.SavedQualitySetting:GetEnumItems()) do

			local LevelNumber =
				tonumber(
					Item.Name:match("QualityLevel(%d+)$")
				)

			if LevelNumber then
				SavedQualityLevels[LevelNumber] = Item
			end

		end
	end
)

GetAvailableSavedQualityLevels =
	function()

		local Available = {}

		for Index, Item in pairs(SavedQualityLevels) do
			if Item then
				Insert(
					Available,
					{
						Index = Index,
						Item = Item,
					}
				)
			end
		end

		table.sort(
			Available,
			function(A, B)
				return A.Index < B.Index
			end
		)

		return Available

	end

GetSavedQualityForValue =
	function(Value)

		Value = tonumber(Value) or 1

		if SavedQualityLevels[Value] then
			return SavedQualityLevels[Value]
		end

		local Available =
			GetAvailableSavedQualityLevels()

		if #Available == 0 then
			return nil
		end

		local Alpha =
			(Value - 1)
			/
			math.max(maxSteps - 1, 1)

		local Mapped =
			1 + (Alpha * (#Available - 1))

		local Selected =
			Clamp(
				math.floor(Mapped + 0.5),
				1,
				#Available
			)

		return Available[Selected].Item

	end

GetGraphicsSliderStart =
	function()

		if maxSteps == 21 then

			local CurrentRenderQuality = nil

			Protect(function()
				CurrentRenderQuality = RenderingSettings.QualityLevel
			end)

			if CurrentRenderQuality == Enum.QualityLevel.Automatic then
				return 11
			end

			if type(CurrentRenderQuality) == "number" then
				return Clamp(CurrentRenderQuality, 1, 21)
			end

			for Index, Quality in pairs(QualityLevels) do
				if CurrentRenderQuality == Quality then
					return Clamp(Index, 1, 21)
				end
			end

			local SavedValue = nil
			Protect(function()
				SavedValue = GameSettings.SavedQualityLevel
			end)

			if type(SavedValue) == "number" then
				if SavedValue <= 0 then
					return 11
				end
				return Clamp(SavedValue, 1, 21)
			end

			local SavedIndex =
				type(SavedValue) == "EnumItem"
				and tonumber(tostring(SavedValue):match("QualityLevel(%d+)$"))
				or tonumber(tostring(SavedValue):match("QualityLevel(%d+)$"))

			return Clamp(SavedIndex or 11, 1, 21)

		end

		if type(GameSettings.SavedQualityLevel) == "number" then
			if GameSettings.SavedQualityLevel <= 0 then
				return 5
			end
			return Clamp(GameSettings.SavedQualityLevel, 1, 10)
		end

		if GameSettings.SavedQualityLevel == Enum.SavedQualitySetting.Automatic
			or RenderingSettings.QualityLevel == Enum.QualityLevel.Automatic
		then
			return 5
		end

		for Index, Quality in pairs(QualityLevels) do
			if RenderingSettings.QualityLevel == Quality then
				return Clamp(Index, 1, 10)
			end
		end

		local SavedIndex =
			tonumber(tostring(GameSettings.SavedQualityLevel):match("QualityLevel(%d+)$"))

		return Clamp(SavedIndex or 5, 1, 10)

	end

GraphicsSlider = nil
GraphicsMode = nil

Protect(function()
	RenderingSettings.EnableFRM = true
end)

GetEnumItemByValue =
	function(EnumType, Value)

		local Items = {}

		Protect(function()
			Items = EnumType:GetEnumItems()
		end)

		for _, Item in ipairs(Items) do
			if Item.Value == Value then
				return Item
			end
		end

		return nil

	end

SetGraphicsQuality =
	function(NewValue, AutomaticSettingAllowed)

		NewValue = tonumber(NewValue) or 0

		local MaxQualityLevel = 21

		Protect(function()
			MaxQualityLevel = RenderingSettings:GetMaxQualityLevel()
		end)

		local NewQualityLevel = 0

		if NewValue > 0 or not AutomaticSettingAllowed then

			if maxSteps == 21 then

				NewQualityLevel =
					Clamp(
						NewValue,
						1,
						21
					)

			else

				local Percentage = NewValue / 10

				NewQualityLevel =
					Floor(
						(MaxQualityLevel - 1)
						* Percentage
					)

				if NewQualityLevel == 20 then
					NewQualityLevel = 21
				elseif NewValue == 1 then
					NewQualityLevel = 1
				elseif NewValue < 1 and not AutomaticSettingAllowed then
					NewValue = 1
					NewQualityLevel = 1
				elseif NewQualityLevel > MaxQualityLevel then
					NewQualityLevel = MaxQualityLevel - 1
				end

			end

		end

		local SavedQuality = nil

		if NewValue <= 0 and AutomaticSettingAllowed then
			SavedQuality = Enum.SavedQualitySetting.Automatic
		else
			SavedQuality = GetSavedQualityForValue(NewValue)
		end

		local RenderQuality =
			(
				NewValue <= 0
				and AutomaticSettingAllowed
				and Enum.QualityLevel.Automatic
			)
			or GetEnumItemByValue(
				Enum.QualityLevel,
				NewQualityLevel
			)
			or QualityLevels[NewValue]

		Protect(function()
			GameSettings.SavedQualityLevel = SavedQuality
		end)

		if RenderQuality then
			Protect(function()
				RenderingSettings.QualityLevel = RenderQuality
			end)
			Protect(function()
				RenderingSettings.EditQualityLevel = RenderQuality
			end)
		end

		Protect(function()
			RenderingSettings.AutoFRMLevel = NewQualityLevel
		end)

	end

SetGraphicsToAuto =
	function()
		if GraphicsSlider then
			GraphicsSlider:SetInteractable(false)
		end
		SetGraphicsQuality(0, true)
	end

SetGraphicsToManual =
	function(Value)
		Value = Clamp(
			Value or GetGraphicsSliderStart(),
			1,
			maxSteps
		)

		if GraphicsSlider then
			GraphicsSlider:SetInteractable(true)
			GraphicsSlider:SetValue(Value)
		end

		SetGraphicsQuality(Value, false)
	end

GraphicsIsAutomatic = false
Protect(function()
	GraphicsIsAutomatic = GameSettings.SavedQualityLevel == Enum.SavedQualitySetting.Automatic
		or RenderingSettings.QualityLevel == Enum.QualityLevel.Automatic
		or GameSettings.SavedQualityLevel == 0
		or RenderingSettings.QualityLevel == 0
end)

GraphicsMode =
	MakeSelector(
		GamePage,
		"Graphics Mode",
		{"Automatic", "Manual"},
		(GraphicsIsAutomatic and 1 or 2),
		function(Index)
			if Index == 1 then
				SetGraphicsToAuto()
			else
				SetGraphicsToManual(
					(GraphicsSlider and GraphicsSlider:GetValue())
					or GetGraphicsSliderStart()
				)
			end
		end
	)

GraphicsSlider =
	MakeSlider(
		GamePage,
		"Graphics Quality",
		maxSteps,
		GetGraphicsSliderStart(),
		function(Value)
			Value = Clamp(Value, 1, maxSteps)
			GraphicsMode:SetSelectionIndex(2, false)
			GraphicsSlider:SetInteractable(true)
			SetGraphicsQuality(Value, false)
		end,
		1
	)

-- ============================================================
-- 21-BAR COMPRESSION
-- ============================================================

if
	maxSteps == 21
	and GraphicsSlider
	and GraphicsSlider.SliderFrame
then
	StretchSliderBars(GraphicsSlider, 60, 411, nil, 42)
end

if GraphicsIsAutomatic then
	SetGraphicsToAuto()
else
	SetGraphicsToManual(GetGraphicsSliderStart())
end

FpsValues = {"60", "120", "144", "160", "165", "180", "200", "240"}
FpsStart = 1
CurrentFps = tostring(GetSetting(GameSettings, "FramerateCap", 60))
for Index, Value in next, FpsValues do
	if Value == CurrentFps then
		FpsStart = Index
		break
	end
end

MaximumFrameRateSelector = MakeSelector(
	GamePage,
	"Maximum Frame Rate",
	FpsValues,
	FpsStart,
	function(_, Value)
		local Cap = tonumber(Value) or 60
		SetSetting(GameSettings, "FramerateCap", Cap)
		if setfpscap then
			Protect(function() setfpscap(Cap) end)
		end
	end
)

GetReducedMotionValue = function()
	local Value = nil
	Protect(function() Value = GuiService.ReducedMotionEnabled end)
	if Value == nil then
		Value = GetSetting(GameSettings, "ReducedMotion", false)
	end
	return Value == true
end

SetReducedMotionValue = function(Value)
	Value = Value == true
	Protect(function() GuiService.ReducedMotionEnabled = Value end)
	SetSetting(GameSettings, "ReducedMotion", Value)
	if sethiddenproperty then
		pcall(function() sethiddenproperty(GuiService, "ReducedMotionEnabled", Value) end)
		pcall(function() sethiddenproperty(GameSettings, "ReducedMotion", Value) end)
	end
end

ReduceMotionSelector = MakeSelector(
	GamePage,
	"Reduce Motion",
	{"On", "Off"},
	GetReducedMotionValue() and 1 or 2,
	function(Index) SetReducedMotionValue(Index == 1) end
)
AddSettingDescription(GamePage, ReduceMotionSelector.RowFrame, "Stop or reduce motion effects")

PreferredTransparencyCurrent = GetPreferredTransparency()
BackgroundTransparencySelector = MakeSlider(
	GamePage,
	"Background Transparency",
	10,
	Clamp(math.floor(((1 - PreferredTransparencyCurrent) * 9) + 0.5) + 1, 1, 10),
	function(Index)
		local Value = 1 - ((Index - 1) / 9)
		SetPreferredTransparency(Value)
	end,
	1,
	true
)
AddSettingDescription(GamePage, BackgroundTransparencySelector.RowFrame, "Improve contrast by adjusting\ntransparency on some backgrounds.")
StretchSliderBars(BackgroundTransparencySelector, 60, 414, nil, 42)

BackgroundHolder = BackgroundTransparencySelector.SliderFrame
Create("TextLabel", {
	Name = "TransparentLabel",
	Parent = BackgroundHolder,
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(150, 150, 150),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Transparent",
	Size = UDim2.new(0, 95, 0, 18),
	Position = UDim2.new(0, 60, 0, 54),
	ZIndex = SETTINGS_BASE_ZINDEX + 4,
})
Create("TextLabel", {
	Name = "OpaqueLabel",
	Parent = BackgroundHolder,
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(150, 150, 150),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "Opaque",
	Size = UDim2.new(0, 70, 0, 18),
	Position = UDim2.new(0, 381, 0, 54),
	ZIndex = SETTINGS_BASE_ZINDEX + 4,
})

Protect(function()
	Connect(GuiService:GetPropertyChangedSignal("PreferredTransparency"), function()
		local Value = GetPreferredTransparency()
		BackgroundTransparencySelector:SetValue(Clamp(math.floor(((1 - Value) * 9) + 0.5) + 1, 1, 10))
	end)
end)

TextSizeEnumValues = {
	[1] = Enum.PreferredTextSize.Medium,
	[2] = Enum.PreferredTextSize.Large,
	[3] = Enum.PreferredTextSize.Largest,
}
TextSizeStart = 1
Protect(function()
	local Current = GuiService.PreferredTextSize
	for Index, Value in ipairs(TextSizeEnumValues) do
		if Current == Value then
			TextSizeStart = Index
			break
		end
	end
end)

TextSizeSelector = MakeSlider(
	GamePage,
	"Text Size",
	3,
	TextSizeStart,
	function(Index)
		if TextSizeEnumValues[Index] then
			SetPreferredTextSize(TextSizeEnumValues[Index])
			ApplyGamePageTextSize(Index)
		end
	end,
	1,
	true
)
StretchSliderBars(TextSizeSelector, 60, 414, nil, 42)
TextSizeHolder = TextSizeSelector.SliderFrame
Create("TextLabel", {
	Name = "DefaultLabel",
	Parent = TextSizeHolder,
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(150, 150, 150),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Default",
	Size = UDim2.new(0, 70, 0, 18),
	Position = UDim2.new(0, 60, 0, 54),
	ZIndex = SETTINGS_BASE_ZINDEX + 4,
})
Create("TextLabel", {
	Name = "LargestLabel",
	Parent = TextSizeHolder,
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(150, 150, 150),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "Largest",
	Size = UDim2.new(0, 70, 0, 18),
	Position = UDim2.new(0, 360, 0, 54),
	ZIndex = SETTINGS_BASE_ZINDEX + 4,
})


GetUINavigationPreference = function()
	local Value = GetSetting(GuiService, "GuiNavigationEnabled", nil)
	if Value ~= nil then
		return Value == true
	end
	Value = GetHiddenOrSetting(GameSettings, "UiNavigationKeyBindEnabled", nil)
	if Value ~= nil then
		return Value == true
	end
	return false
end

SetUINavigationPreference = function(Enabled)
	Enabled = Enabled == true
	local Written = false
	Written = Protect(function()
		GuiService.GuiNavigationEnabled = Enabled
		return true
	end) or false
	Protect(function() GuiService.AutoSelectGuiEnabled = Enabled end)
	if sethiddenproperty then
		local Ok = pcall(function() sethiddenproperty(GameSettings, "UiNavigationKeyBindEnabled", Enabled) end)
		Written = Ok or Written
	end
	if not Written then
		Written = SetSetting(GameSettings, "UiNavigationKeyBindEnabled", Enabled)
	end
	return Written
end

local UiNavigationInitial = false
Protect(function() SetUINavigationPreference(false) end)

UINavigationSelector = MakeSelector(
	GamePage,
	"UI Navigation",
	{"On", "Off"},
	UiNavigationInitial and 1 or 2,
	function(Index)
		SetUINavigationPreference(Index == 1)
	end
)
AddSettingDescription(GamePage, UINavigationSelector.RowFrame, "Use the \\ key to enter and exit UI Navigation mode")

PerformanceSelector = MakeBooleanSelector(GamePage, "Performance Stats", GameSettings, "PerformanceStatsVisible", "On", "Off")

BindBooleanSettingRefresh = function(Selector, Object, Property)
	if not Selector or not Object then return end
	local function RefreshBoolean()
		local Current = GetHiddenOrSetting(Object, Property, false) == true
		local Index = Current and 1 or 2
		if Selector:GetSelectedIndex() ~= Index then
			Selector:SetSelectionIndex(Index, false)
		end
	end
	Protect(function() Connect(Object:GetPropertyChangedSignal(Property), RefreshBoolean) end)
	Spawn(function()
		while Selector and Selector.RowFrame and Selector.RowFrame.Parent do
			RefreshBoolean()
			Wait(0.25)
		end
	end)
end


GetMicroProfilerEnabled = function()
	return GetHiddenOrSetting(GameSettings, "OnScreenProfilerEnabled", false) == true
end

MicroProfilerState = GetMicroProfilerEnabled()

SetMicroProfilerEnabled = function(Enabled)
	Enabled = Enabled == true
	local ChangedState = false
	if sethiddenproperty then
		ChangedState = pcall(function() sethiddenproperty(GameSettings, "OnScreenProfilerEnabled", Enabled) end) or ChangedState
	end
	if not ChangedState then
		ChangedState = SetSetting(GameSettings, "OnScreenProfilerEnabled", Enabled)
	end
	return ChangedState
end

ToggleMicroProfilerHotkey = function()
	if not keypress or not keyrelease then return false end
	local Success = pcall(function()
		keypress(0x11) -- Ctrl
		keypress(0x12) -- Alt
		keypress(0x75) -- F6
		keyrelease(0x75)
		keyrelease(0x12)
		keyrelease(0x11)
	end)
	return Success
end

MicroProfilerButton, MicroProfilerRow = MakeButtonRow(
	GamePage,
	"MicroProfiler",
	MicroProfilerState and "Close" or "Open",
	function()
		MicroProfilerState = not MicroProfilerState
		SetMicroProfilerEnabled(MicroProfilerState)
		ToggleMicroProfilerHotkey()
		local ActionLabel = MicroProfilerButton and MicroProfilerButton:FindFirstChild("MicroProfilerActionTextLabel")
		if ActionLabel then ActionLabel.Text = MicroProfilerState and "Close" or "Open" end
	end
)

Protect(function()
	Connect(GameSettings:GetPropertyChangedSignal("OnScreenProfilerEnabled"), function()
		local Enabled = GetMicroProfilerEnabled()
		if keypress and keyrelease then
			-- When the engine exposes the profiler property, use it as the authoritative state.
			MicroProfilerState = Enabled
		end
		local ActionLabel = MicroProfilerButton and MicroProfilerButton:FindFirstChild("MicroProfilerActionTextLabel")
		if ActionLabel then ActionLabel.Text = MicroProfilerState and "Close" or "Open" end
	end)
end)

CameraInvertedGetter = function()
	local Value = GetHiddenOrSetting(GameSettings, "CameraYInverted", nil)
	if Value ~= nil then return Value == true end
	local Legacy = nil
	Protect(function() Legacy = tonumber(GameSettings:GetCameraYInvertValue()) end)
	return Legacy ~= nil and Legacy < 0
end

CameraInvertedSelector = MakeSelector(
	GamePage,
	"Camera Inverted",
	{"On", "Off"},
	CameraInvertedGetter() and 1 or 2,
	function(Index)
		local Desired = Index == 1
		if sethiddenproperty then
			pcall(function() sethiddenproperty(GameSettings, "CameraYInverted", Desired) end)
		end
		Protect(function() GameSettings.CameraYInverted = Desired end)
	end
)


PeopleNamesSelector = MakeBooleanSelector(GamePage, "People's Names", GameSettings, "PlayerNamesEnabled", "Show", "Hide")
AddSettingDescription(GamePage, PeopleNamesSelector.RowFrame, "Show or hide names above people in games. Some games may have custom settings that override your preference.")
BindBooleanSettingRefresh(PeopleNamesSelector, GameSettings, "PlayerNamesEnabled")

MyBadgesSelector = MakeBooleanSelector(GamePage, "My Badges", GameSettings, "BadgeVisible", "Show", "Hide")
AddSettingDescription(GamePage, MyBadgesSelector.RowFrame, "Show or hide your badges from other people in games")
BindBooleanSettingRefresh(MyBadgesSelector, GameSettings, "BadgeVisible")
BindBooleanSettingRefresh(PerformanceSelector, GameSettings, "PerformanceStatsVisible")
Protect(function()
	Connect(GuiService:GetPropertyChangedSignal("GuiNavigationEnabled"), function()
		if UINavigationSelector then
			UINavigationSelector:SetSelectionIndex(GetUINavigationPreference() and 1 or 2, false)
		end
	end)
end)
Spawn(function()
	while UINavigationSelector and UINavigationSelector.RowFrame and UINavigationSelector.RowFrame.Parent do
		local Index = GetUINavigationPreference() and 1 or 2
		if UINavigationSelector:GetSelectedIndex() ~= Index then
			UINavigationSelector:SetSelectionIndex(Index, false)
		end
		Wait(0.25)
	end
end)

GamePageTextTargets = {}
GetGamePageTextScaleIndex = function()
	local Preferred = GuiService.PreferredTextSize
	if Preferred == Enum.PreferredTextSize.Large then return 2 end
	if Preferred == Enum.PreferredTextSize.Larger then return 2 end
	if Preferred == Enum.PreferredTextSize.Largest then return 3 end
	return 1
end

RegisterGamePageTextTargets = function()
	GamePageTextTargets = {}
	if not GamePage or not GamePage.Frame then return end
	for _, Object in ipairs(GamePage.Frame:GetDescendants()) do
		if (Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("TextBox"))
			and Object.TextScaled ~= true then
			GamePageTextTargets[Object] = Object.TextSize
		end
	end
end

ApplyGamePageTextSize = function(Index)
	local Scale = ({[1] = 1, [2] = 1.14, [3] = 1.28})[Index or 1] or 1
	for Object, BaseSize in next, GamePageTextTargets do
		if Object and Object.Parent then
			Object.TextSize = math.floor((BaseSize * Scale) + 0.5)
		end
	end
	-- Do not resize description rows when Text Size changes. Their compact
	-- geometry is fixed so changing text size cannot create huge vertical gaps.
	RestoreFixedTextSizes()
end

RegisterFixedTextSizeObjects()
RegisterGamePageTextTargets()
ApplyGamePageTextSize(GetGamePageTextScaleIndex())
Protect(function()
	Connect(GuiService:GetPropertyChangedSignal("PreferredTextSize"), function()
		local Index = GetGamePageTextScaleIndex()
		if TextSizeSelector and TextSizeSelector:GetValue() ~= Index then
			TextSizeSelector:SetValue(Index)
		end
		ApplyGamePageTextSize(Index)
	end)
end)

-- ============================================================
-- REPORT PAGE
-- ============================================================

ReportPage = MakePage("ReportAbuse")
AddPage(ReportPage, "Report", "rbxasset://textures/ui/Settings/MenuBarIcons/ReportAbuseTab.png", 150)

TypeOfAbuse = nil
WhichPlayer = nil
NameToPlayer = {}
PlayerNames = {}
Submit = nil
SubmitLabel = nil
Description = nil
ReportMode = nil

SetSubmitActive =
	function(Active)
		if not Submit or not SubmitLabel then
			return
		end
		Submit.Selectable = Active
		Submit.ImageTransparency = Active and 0 or 0.65
		Submit.ZIndex = SETTINGS_BASE_ZINDEX + (Active and 3 or 1)
		SubmitLabel.ZIndex = Submit.ZIndex + 1
		SubmitLabel.TextTransparency = Active and 0 or 0.55
	end

GetReportDescription =
	function()
		local Text = Description and Description.Text or ""
		if Text == "" or Text == DESCRIPTION_PLACEHOLDER then
			return REPORT_DESCRIPTION_FALLBACK
		end
		return Text
	end

CanSubmitReport =
	function(Mode)
		if not TypeOfAbuse or not Mode then return false end
		if not TypeOfAbuse:GetSelectedIndex() then return false end
		if Mode:GetSelectedIndex() == 2 and (not WhichPlayer or not WhichPlayer:GetSelectedValue()) then
			return false
		end
		return true
	end

RefreshSubmitState = function(Mode)
	SetSubmitActive(CanSubmitReport(Mode))
end

ReportMode =
	MakeSelector(
		ReportPage,
		"Game or Player?",
		{"Game", "Player"},
		1,
		function()
			if not TypeOfAbuse or not WhichPlayer then return end
			WhichPlayer:ResetSelectionIndex()
			TypeOfAbuse:ResetSelectionIndex()
			if ReportMode:GetSelectedIndex() == 1 then
				TypeOfAbuse:UpdateDropDownList(ABUSE_TYPES_GAME)
				WhichPlayer:SetInteractable(false)
			else
				TypeOfAbuse:UpdateDropDownList(ABUSE_TYPES_PLAYER)
				WhichPlayer:SetInteractable(#PlayerNames > 0)
			end
			RefreshSubmitState(ReportMode)
		end
	)

ReportMode:SetSize(UDim2.new(0, 400, 0, 50))
ReportMode:SetPosition(UDim2.new(1, -400, 0.5, -25))

WhichPlayer =
	MakeDropDown(
		ReportPage,
		"Which Player?",
		PlayerNames,
		nil,
		function() RefreshSubmitState(ReportMode) end
	)

WhichPlayer:SetInteractable(false)

RefreshReportPlayers =
	function()
		PlayerNames = {}
		NameToPlayer = {}
		for _, Player in next, Players:GetPlayers() do
			if Player ~= LocalPlayer and (Player.UserId or Player.userId or 0) > 0 then
				Insert(PlayerNames, Player.Name)
				NameToPlayer[Player.Name] = Player
			end
		end
		if WhichPlayer then
			WhichPlayer:UpdateDropDownList(PlayerNames)
			WhichPlayer:SetInteractable(ReportMode:GetSelectedIndex() == 2 and #PlayerNames > 0)
		end
		if #PlayerNames == 0 and ReportMode:GetSelectedIndex() == 2 then
			ReportMode:SetSelectionIndex(1, true)
		end
		RefreshSubmitState(ReportMode)
	end

OpenReportPlayer =
	function(Player)
		if not Player or Player == LocalPlayer then return end
		RefreshReportPlayers()
		ReportMode:SetSelectionIndex(2, true)
		WhichPlayer:SetSelectionByValue(Player.Name, true)
		if Hub.Visible then
			SwitchToPage(ReportPage)
		else
			SetVisibility(true, false, ReportPage)
		end
	end

TypeOfAbuse =
	MakeDropDown(
		ReportPage,
		"Type Of Abuse",
		ABUSE_TYPES_GAME,
		nil,
		function() RefreshSubmitState(ReportMode) end
	)

DescriptionRow = MakeRow(ReportPage, "")
Description = Create(
	"TextBox",
	{
		Parent = DescriptionRow,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.SourceSans,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(49, 49, 49),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = DESCRIPTION_PLACEHOLDER,
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.new(0, 10, 0, 0),
		ZIndex = SETTINGS_BASE_ZINDEX + 3,
	}
)

Connect(Description.Focused, function()
	if Description.Text == DESCRIPTION_PLACEHOLDER then
		Description.Text = ""
	end
end)

Connect(Description.FocusLost, function()
	if Description.Text == "" then
		Description.Text = DESCRIPTION_PLACEHOLDER
	end
end)

DescriptionRow.Size = UDim2.new(1, 0, 0, 110)
ReportPage.Frame.Size = UDim2.new(1, 0, 0, ReportPage.Frame.Size.Y.Offset + 60)

Submit, SubmitLabel =
	MakeStyledButton(
		"SubmitButton",
		"Submit",
		UDim2.new(0, 198, 0, 50),
		function()
			if not CanSubmitReport(ReportMode) then return end

			local IsPlayerReport = ReportMode:GetSelectedIndex() == 2
			local Reason = ((IsPlayerReport and ABUSE_TYPES_PLAYER) or ABUSE_TYPES_GAME)[TypeOfAbuse:GetSelectedIndex()]
			local TargetPlayer = IsPlayerReport and NameToPlayer[WhichPlayer:GetSelectedValue()] or nil
			local DescriptionText = GetReportDescription()

			local Success = Protect(function()
				Players.ReportAbuse(LocalPlayer, TargetPlayer, Reason, DescriptionText)
			end)

			if not Success then
				Success = Protect(function()
					Players:ReportAbuse(TargetPlayer, Reason, DescriptionText)
				end)
			end

			local AlertText = "Thanks for your report! Our moderators will review the chat logs and evaluate what happened."
			if Reason == "Cheating/Exploiting" then
				AlertText = "Thanks for your report! We've recorded your report for evaluation."
			elseif Reason == "Inappropriate Username" then
				AlertText = "Thanks for your report! Our moderators will evaluate the username."
			elseif Reason == "Bad Model or Script" or Reason == "Inappropriate Content" or Reason == "Offsite Link" or Reason == "Offsite Links" then
				AlertText = "Thanks for your report! Our moderators will review the place and make a determination."
			end
			if not Success then
				AlertText = "Report could not be submitted in this environment."
			end

			ShowAlert(AlertText, "Ok", function()
				ReportMode:SetSelectionIndex(1, true)
				WhichPlayer:ResetSelectionIndex()
				TypeOfAbuse:ResetSelectionIndex()
				Description.Text = DESCRIPTION_PLACEHOLDER
				SetVisibility(false)
			end)
		end
	)

Submit.Parent = ReportPage.Frame
Submit.Position = UDim2.new(0.5, -99, 0, ReportPage.Frame.Size.Y.Offset + 10)
ReportPage.Frame.Size = UDim2.new(1, 0, 0, ReportPage.Frame.Size.Y.Offset + 70)
SetSubmitActive(false)
RefreshReportPlayers()
Connect(Players.PlayerAdded, RefreshReportPlayers)
Connect(Players.PlayerRemoving, function() task.defer(RefreshReportPlayers) end)

-- ============================================================
-- HELP PAGE
-- ============================================================

HelpPage = MakePage("Help")
AddPage(HelpPage, "Help", "rbxasset://textures/ui/Settings/MenuBarIcons/HelpTab.png", 130)

CreateHelpGroup =
	function(Title, Bindings, Position)
		local Group = Create(
			"Frame",
			{
				Parent = HelpPage.Frame,
				Name = "PCGroupFrame" .. Title,
				BackgroundTransparency = 1,
				Position = Position,
				Size = UDim2.new(1 / 3, -4, 0, 0),
				ZIndex = SETTINGS_BASE_ZINDEX + 2,
			}
		)

		Create("TextLabel", {
			Parent = Group,
			BackgroundTransparency = 1,
			Text = Title,
			Font = Enum.Font.SourceSansBold,
			TextSize = 18,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -9, 0, 30),
			Position = UDim2.new(0, 9, 0, 0),
			ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})

		for Index, Binding in ipairs(Bindings) do
			local Row = Create("Frame", {
				Parent = Group,
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.65,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 42),
				Position = UDim2.new(0, 0, 0, 30 + ((Index - 1) * 44)),
				ZIndex = SETTINGS_BASE_ZINDEX + 2,
			})
			Create("TextLabel", {
				Parent = Row,
				BackgroundTransparency = 1,
				Text = Binding[1],
				Font = Enum.Font.SourceSansBold,
				TextSize = 18,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.45, -9, 1, 0),
				Position = UDim2.new(0, 9, 0, 0),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			})
			Create("TextLabel", {
				Parent = Row,
				BackgroundTransparency = 1,
				Text = Binding[2],
				Font = Enum.Font.SourceSans,
				TextSize = 18,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.55, 0, 1, 0),
				Position = UDim2.new(0.5, -4, 0, 0),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			})
		end

		Group.Size = UDim2.new(Group.Size.X.Scale, Group.Size.X.Offset, 0, 30 + (#Bindings * 44))
		return Group
	end

IsOSX = UserInputService:GetPlatform() == Enum.Platform.OSX

CharMoveFrame = CreateHelpGroup("Character Movement", {
	{"Move Forward", "W/Up Arrow"},
	{"Move Backward", "S/Down Arrow"},
	{"Move Left", "A/Left Arrow"},
	{"Move Right", "D/Right Arrow"},
	{"Jump", "Space"},
}, UDim2.new(0, 0, 0, 0))

CreateHelpGroup("Accessories", {
	{"Equip Tools", "1,2,3..."},
	{"Unequip Tools", "1,2,3..."},
	{"Drop Tool", "Backspace"},
	{"Use Tool", "Left Mouse Button"},
	{"Drop Hats", "+"},
}, UDim2.new(1 / 3, 4, 0, 0))

CreateHelpGroup("Misc", {
	{"Screenshot", "Print Screen"},
	{"Record Video", IsOSX and "F12/fn + F12" or "F12"},
	{"Dev Console", IsOSX and "F9/fn + F9" or "F9"},
	{"Mouselock", "Shift"},
	{"Graphics Level", IsOSX and "F10/fn + F10" or "F10"},
	{"Fullscreen", IsOSX and "F11/fn + F11" or "F11"},
}, UDim2.new(2 / 3, 8, 0, 0))

CreateHelpGroup("Camera Movement", {
	{"Rotate", "Right Mouse Button"},
	{"Zoom In/Out", "Mouse Wheel"},
	{"Zoom In", "I"},
	{"Zoom Out", "O"},
}, UDim2.new(0, 0, 0, CharMoveFrame.Size.Y.Offset + 50))

MenuFrame = CreateHelpGroup("Menu Items", {
	{"ROBLOX Menu", "ESC"},
	{"Backpack", "~"},
	{"Playerlist", "TAB"},
	{"Chat", "/"},
}, UDim2.new(1 / 3, 4, 0, CharMoveFrame.Size.Y.Offset + 50))

HelpPage.Frame.Size = UDim2.new(1, 0, 0, MenuFrame.Position.Y.Offset + MenuFrame.Size.Y.Offset)

-- ============================================================
-- MOBILE HELP / REPORT LAYOUT
-- ============================================================

ApplyMobileReportLayout = function()
	if not IsMobile or not ReportPage then return end
	ReportPage.Frame.Size = UDim2.new(1, 0, 0, 269)
	local Layout = ReportPage.Frame:FindFirstChild("RowListLayout")
	if Layout then Layout.Parent = nil end
	local Rows = {
		{ReportMode and ReportMode.RowFrame, 0},
		{WhichPlayer and WhichPlayer.RowFrame, 50},
		{TypeOfAbuse and TypeOfAbuse.RowFrame, 100},
		{DescriptionRow, 155},
	}
	for _, Info in ipairs(Rows) do
		local Row = Info[1]
		if Row then
			Row.Position = UDim2.new(0, 0, 0, Info[2])
			Row.Size = UDim2.new(1, 0, 0, 50)
			Row.LayoutOrder = Info[2]
		end
	end
	for _, Selector in ipairs({ReportMode, WhichPlayer, TypeOfAbuse}) do
		if Selector and Selector.SelectorFrame then
			Selector.SelectorFrame.Size = UDim2.new(0.6, 0, 0, 50)
			Selector.SelectorFrame.Position = UDim2.new(1, 0, 0.5, 0)
			Selector.SelectorFrame.AnchorPoint = Vector2.new(1, 0.5)
		end
	end
	if DescriptionRow and Description then
		DescriptionRow.Position = UDim2.new(0, 0, 0, 155)
		DescriptionRow.Size = UDim2.new(1, 0, 0, 50)
		Description.Position = UDim2.new(1, 0, 0.5, 5)
		Description.Size = UDim2.new(0.6, 0, 1, 0)
		Description.AnchorPoint = Vector2.new(1, 0.5)
		Description.TextSize = 24
	end
	if Submit then
		Submit.Position = UDim2.new(0.5, 0, 0, 214)
		Submit.Size = UDim2.new(0, 198, 0, 50)
		Submit.AnchorPoint = Vector2.new(0.5, 0)
	end
end

BuildMobileHelpPage = function()
	if not IsMobile or not HelpPage or HelpPage.Frame:FindFirstChild("HelpFrameTouch") then return end
	for _, Child in ipairs(HelpPage.Frame:GetChildren()) do
		if Child.Name:sub(1, 12) == "PCGroupFrame" then Child.Visible = false end
	end
	local HelpFrame = Create("Frame", {
		Name = "HelpFrameTouch", Parent = HelpPage.Frame, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 238), Position = UDim2.new(0, 0, 0, 0), ZIndex = SETTINGS_BASE_ZINDEX + 1,
	})
	local function MakeTouchHint(Name, Text, Position, Size, Image, ImagePosition, ImageSize)
		local Frame = Create("TextLabel", {
			Name = Name .. "Frame", Parent = HelpFrame, BackgroundTransparency = 1, BorderSizePixel = 0,
			Text = "Label", TextSize = 8, TextColor3 = Color3.fromRGB(27, 42, 53), Font = Enum.Font.Legacy,
			Size = Size, Position = Position, ZIndex = SETTINGS_BASE_ZINDEX + 1,
		})
		Create("ImageLabel", {
			Name = Name .. "BackgroundImage", Parent = Frame, BackgroundTransparency = 1,
			Image = "rbxasset://textures/ui/Settings/Radial/RadialLabel.png", Size = UDim2.new(1.25, 0, 1.25, 0),
			Position = UDim2.new(-0.125, 0, -0.065, 0), ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(12, 2, 65, 21), ZIndex = SETTINGS_BASE_ZINDEX + 2,
		})
		if Image then
			Create("ImageLabel", {Name = Name .. "Image", Parent = Frame, BackgroundTransparency = 1, Image = Image,
				Size = ImageSize or UDim2.fromOffset(38, 52), Position = ImagePosition or UDim2.new(0.5, -19, 1, 3),
				ScaleType = Enum.ScaleType.Stretch, ZIndex = SETTINGS_BASE_ZINDEX + 2})
		end
		local Label = Create("TextLabel", {Name = Name .. "Label", Parent = Frame, BackgroundTransparency = 1, Text = Text,
			Font = Enum.Font.SourceSansBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), TextWrapped = true, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0), ZIndex = SETTINGS_BASE_ZINDEX + 3})
		Create("UITextSizeConstraint", {Parent = Label, MinTextSize = 10, MaxTextSize = 18})
	end
	MakeTouchHint("Zoom In/Out", "Zoom In/Out", UDim2.new(0.15, -60, 0.02, 0), UDim2.fromOffset(120, 25),
		"rbxasset://textures/ui/Settings/Help/ZoomGesture.png", UDim2.new(0.5, -26, 1, 3), UDim2.fromOffset(53, 59))
	MakeTouchHint("Rotate Camera", "Rotate Camera", UDim2.new(0.85, -60, 0.02, 0), UDim2.fromOffset(120, 25),
		"rbxasset://textures/ui/Settings/Help/RotateCameraGesture.png", UDim2.new(0.5, -32, 1, 3), UDim2.fromOffset(65, 48))
	MakeTouchHint("Use Tool", "Use Tool", UDim2.new(0.5, -60, 0.5, -60), UDim2.fromOffset(120, 25),
		"rbxasset://textures/ui/Settings/Help/UseToolGesture.png")
	MakeTouchHint("Move", "Move", UDim2.new(0.15, -38, 0.85, -25), UDim2.fromOffset(77, 25),
		"rbxasset://textures/ui/Settings/Help/RotateCameraGesture.png", UDim2.new(0.5, -32, 1, 3), UDim2.fromOffset(65, 48))
	MakeTouchHint("Jump", "Jump", UDim2.new(0.85, -60, 0.85, -25), UDim2.fromOffset(77, 25),
		"rbxasset://textures/ui/Settings/Help/UseToolGesture.png")
	MakeTouchHint("Equip/Unequip Tools", "Equip/Unequip Tools", UDim2.new(0.5, -60, 0.64, 0), UDim2.fromOffset(120, 25), nil)
	HelpPage.Frame.Size = UDim2.new(1, 0, 0, 238)
end

-- ============================================================
-- RBXM SUITE CUSTOM RECORDER OVERLAY (PC ONLY)
-- ============================================================

RecorderGui = getgenv().Settings2016RecorderGui
RecorderActualButton = nil
RecorderTimeLabel = nil
RecorderRunning = false
RecorderStartedAt = 0
RecorderThread = nil
IgnoreRecorderF12Until = 0
RecorderPageButton = nil
RecorderPageButtonLabel = nil
PositionRecorderGui = nil

UpdateRecorderPageButton =
	function()
		if not RecorderPageButton or not RecorderPageButtonLabel then
			return
		end
		RecorderPageButtonLabel.Text =
			RecorderRunning
			and "Stop Recording"
			or "Record Video"
	end

LoadRecorderGui =
	function()

		if IsMobile then
			return nil
		end

		if RecorderGui and RecorderGui.Parent then
			RecorderGui.Enabled = false
			return RecorderGui
		end

		local Suite = getgenv().Suite

		if not Suite then
			local Success, Result =
				pcall(function()
					return
						loadstring(
							game:HttpGet(
								"https://raw.githubusercontent.com/yeku/forks/refs/heads/main/Scripts/RBXMSuite.luau"
							)
						)()
				end)

			if not Success then
				warn(
						"Settings2016: failed to load RBXM Suite:",
						Result
					)
				return nil
			end

			Suite = Result
			getgenv().Suite = Suite
		end

		local Success, Result =
			pcall(function()
				return
					Suite.launch(
						"rbxassetid://140196633617691",
						{
							runscripts = false,
							deferred = true,
							nocache = false,
							nocirculardeps = true,
							debug = false,
							verbose = false,
						}
					)
			end)

		if not Success then
			warn(
					"Settings2016: failed to load recorder RBXM:",
					Result
				)
			return nil
		end

		RecorderGui = Result

		if not RecorderGui then
			warn("Settings2016: RBXM Suite returned no recorder instance.")
			return nil
		end

		local ParentSuccess =
			pcall(function()
				RecorderGui.Parent = CoreGui
			end)

		if not ParentSuccess then
			warn("Settings2016: failed to parent recorder ScreenGui to CoreGui.")
			return nil
		end

		if not RecorderGui:IsA("ScreenGui") then
			warn("Settings2016: recorder asset is not a ScreenGui.")
			return nil
		end

		RecorderGui.Enabled = false
		RecorderGui.DisplayOrder = 10001
		getgenv().Settings2016RecorderGui = RecorderGui

		return RecorderGui

	end

FindRecorderControls =
	function()

		local Gui = LoadRecorderGui()

		if not Gui then
			return false
		end

		local Button =
			Gui:FindFirstChild(
				"Button",
				true
			)

		local ActualButton =
			Button
			and Button:FindFirstChild(
				"ActualButton",
				true
			)

		if
			not ActualButton
			or not ActualButton:IsA("GuiButton")
		then
			ActualButton =
				Gui:FindFirstChild(
					"ActualButton",
					true
				)
		end

		local TextLabel =
			ActualButton
			and ActualButton:FindFirstChild(
				"TextLabel",
				true
			)

		if
			not TextLabel
			or not TextLabel:IsA("TextLabel")
		then
			TextLabel =
				Gui:FindFirstChild(
					"TextLabel",
					true
				)
		end

		RecorderActualButton = ActualButton
		RecorderTimeLabel = TextLabel

		-- Do not position the recorder from inside control discovery.
		-- PositionRecorderGui is declared/assigned separately and all callers
		-- invoke it only after this function has returned.

		if RecorderTimeLabel then
			RecorderTimeLabel.Text = "0:00"
		end

		return
			RecorderActualButton ~= nil
			and RecorderTimeLabel ~= nil

	end

PositionRecorderGui =
	function()

		if IsMobile or not RecorderGui or not RecorderGui.Parent then
			return
		end

		if not SystemMenuButton or not SystemMenuButton.Parent then
			return
		end

		local Button =
			RecorderGui:FindFirstChild(
				"Button",
				true
			)

		if not Button or not Button:IsA("GuiObject") then
			return
		end

		local Width = Button.AbsoluteSize.X
		if Width <= 0 then Width = 1 end

		local SystemPosition = SystemMenuButton.AbsolutePosition
		local Parent = Button.Parent
		local ParentPosition =
			(Parent and Parent:IsA("GuiObject") and Parent.AbsolutePosition)
			or Vector2.new(0, 0)

		local TargetX =
			SystemPosition.X
			- Width
			+ RECORDER_OFFSET_X

		local TargetY =
			SystemPosition.Y
			+ RECORDER_OFFSET_Y

		-- The visual SystemMenuButton remains fixed at 30x30 in the same
		-- screen coordinates whether the ESC menu is open or closed.
		-- Do not apply the old +4/+4 closed-state compensation here;
		-- that compensation belonged to the previous 40x40 button layout.

		Button.Position =
			UDim2.fromOffset(
				TargetX - ParentPosition.X,
				TargetY - ParentPosition.Y
			)

	end

-- Recorder display follows the ESC menu state, but RecorderRunning is never
-- changed here. The native/custom recording may continue while the overlay is
-- hidden behind the ESC menu.
SetRecorderOverlayVisibility =
	function(Visible)
		if not RecorderGui then
			return
		end
		if not RecorderRunning then
			RecorderGui.Enabled = false
			return
		end
		RecorderGui.Enabled = Visible == true
		if Visible and PositionRecorderGui then
			PositionRecorderGui()
		end
	end

ToggleNativeRecording =
	function()

		IgnoreRecorderF12Until =
			tick() + 0.5

		local Success =
			Protect(function()
				StarterGui:SetCore(
					"ToggleRecording"
				)
			end)

		if Success then
			return true
		end

		if keypress and keyrelease then
			return Protect(function()
				keypress(KEY_F12)
				keyrelease(KEY_F12)
			end)
		end

		return false

	end

FormatRecorderTime =
	function(Seconds)

		Seconds =
			math.max(
				0,
				Floor(Seconds or 0)
			)

		local Minutes =
			Floor(Seconds / 60)

		local Remaining =
			Seconds
			- (Minutes * 60)

		return
			tostring(Minutes)
			.. ":"
			.. string.format("%02d", Remaining)

	end

StopCustomRecording =
	function(ToggleNative)

		if not RecorderRunning then
			if RecorderGui then
				RecorderGui.Enabled = false
			end
			return
		end

		RecorderRunning = false
		RecorderThread = nil

		if RecorderGui then
			RecorderGui.Enabled = false
		end

		if RecorderTimeLabel then
			RecorderTimeLabel.Text = "0:00"
		end

		UpdateRecorderPageButton()

		if ToggleNative then
			ToggleNativeRecording()
		end

	end

StartCustomRecording =
	function(ToggleNative)

		if IsMobile then
			return false
		end

		if RecorderRunning then
			return true
		end

		if not FindRecorderControls() then
			warn(
				"Settings2016: recorder requires ScreenGui -> Button -> ActualButton -> TextLabel."
			)
			return false
		end

		if not RecorderGui or not RecorderTimeLabel then
			warn("Settings2016: recorder controls became unavailable.")
			return false
		end

		-- The custom RBXM recorder UI must not depend on the legacy/native
		-- Roblox recording API existing. The overlay is our recording state UI.
		if ToggleNative then
			ToggleNativeRecording()
		end

		RecorderRunning = true
		RecorderStartedAt = tick()
		PositionRecorderGui()
		RecorderGui.Enabled = not (Hub and Hub.Visible)
		RecorderTimeLabel.Text = "0:00"
		UpdateRecorderPageButton()

		RecorderThread =
			Spawn(function()

				-- Original Roblox F12 recorder limit: 14 minutes.
				-- Roblox stops the native recorder automatically at this point.
				-- Therefore we only clear our overlay/state here; NEVER toggle
				-- the native recorder when the time limit is reached.
				local RecorderTimeLimit = 14 * 60

				while
					RecorderRunning
					and RecorderGui
					and RecorderGui.Parent
				do

					local Elapsed = tick() - RecorderStartedAt

					if Elapsed >= RecorderTimeLimit then
						-- Native F12 recording has reached its hard 14-minute limit.
						-- It has already stopped itself, so do not call ToggleRecording.
						StopCustomRecording(false)
						break
					end

					if RecorderTimeLabel then
						RecorderTimeLabel.Text =
							FormatRecorderTime(Elapsed)
					end

					Wait(0.25)

				end

			end)
		return true

	end

ToggleCustomRecording =
	function()

		if RecorderRunning then
			StopCustomRecording(true)
		else
			StartCustomRecording(true)
		end

	end

if not IsMobile then

	FindRecorderControls()

	if RecorderActualButton then

		Connect(
			RecorderActualButton.MouseButton1Click,
			function()
				if RecorderRunning then
					StopCustomRecording(true)
				end
			end
		)

		Connect(
			RecorderActualButton.Activated,
			function()
				if RecorderRunning then
					StopCustomRecording(true)
				end
			end
		)

	end

end

-- ============================================================
-- END RBXM SUITE CUSTOM RECORDER OVERLAY
-- ============================================================

-- ============================================================
-- RECORD PAGE
-- ============================================================

Protect(function()
	local Platform = UserInputService:GetPlatform()
	if Platform == Enum.Platform.Windows or Platform == Enum.Platform.OSX then
		RecordPage = MakePage("Record")
		AddPage(RecordPage, "Record", "rbxasset://textures/ui/Settings/MenuBarIcons/RecordTab.png", 130)

		local ScreenshotTitle = MakeText(
			RecordPage.Frame,
			"Screenshot",
			UDim2.new(1, 0, 0, 36),
			UDim2.new(0, 10, 0.05, 0)
		)
		ScreenshotTitle.TextSize = 36
		ScreenshotTitle.TextXAlignment = Enum.TextXAlignment.Left

		local ScreenshotBody = MakeText(
			ScreenshotTitle,
			"By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer.",
			UDim2.new(1, -10, 0, 70),
			UDim2.new(0, 0, 1, 0)
		)
		ScreenshotBody.Font = Enum.Font.SourceSans
		ScreenshotBody.TextSize = 24
		ScreenshotBody.TextXAlignment = Enum.TextXAlignment.Left
		ScreenshotBody.TextYAlignment = Enum.TextYAlignment.Top

		local ScreenshotButton = MakeStyledButton(
			"ScreenshotButton",
			"Take Screenshot",
			UDim2.new(0, 300, 0, 44),
			function()
				RunAfterMenuCloses(function()
					pcall(function()
						if keypress and keyrelease then
							keypress(KEY_PRINT_SCREEN)
							keyrelease(KEY_PRINT_SCREEN)
						else
							StarterGui:SetCore("TakeScreenshot")
						end
					end)
				end)
			end
		)
		ScreenshotButton.Parent = ScreenshotBody
		ScreenshotButton.Position = UDim2.new(0, 400, 1, 0)

		local VideoTitle = MakeText(
			RecordPage.Frame,
			"Video",
			UDim2.new(1, 0, 0, 36),
			UDim2.new(0, 10, 0.5, 0)
		)
		VideoTitle.TextSize = 36
		VideoTitle.TextXAlignment = Enum.TextXAlignment.Left

		local VideoBody = MakeText(
			VideoTitle,
			"Click the 'Record Video' button to start recording. Click it again to stop recording.",
			UDim2.new(1, -10, 0, 70),
			UDim2.new(0, 0, 1, 0)
		)
		VideoBody.Font = Enum.Font.SourceSans
		VideoBody.TextSize = 24
		VideoBody.TextXAlignment = Enum.TextXAlignment.Left
		VideoBody.TextYAlignment = Enum.TextYAlignment.Top

		local LastRow = RecordPage.Rows[#RecordPage.Rows]
		if LastRow then
			LastRow.Position = UDim2.new(0, 0, 0, 270)
		end

		local RecordButton, RecordButtonLabel = MakeStyledButton(
			"RecordButton",
			RecorderRunning and "Stop Recording" or "Record Video",
			UDim2.new(0, 300, 0, 44),
			function()
				if RecorderRunning then
					StopCustomRecording(true)
					return
				end

				RunAfterMenuCloses(function()
					StartCustomRecording(true)
				end)
			end
		)

		RecorderPageButton = RecordButton
		RecorderPageButtonLabel = RecordButtonLabel
		UpdateRecorderPageButton()

		RecordButton.Parent = LastRow or RecordPage.Frame
		RecordButton.Position =
			LastRow
			and UDim2.new(0, 410, 1, 10)
			or UDim2.new(0, 410, 0, 330)

		RecordPage.Frame.Size = UDim2.new(1, 0, 0, 400)
	end
end)

-- ============================================================
-- CONFIRMATION PAGES
-- ============================================================

ResetPage = MakePage("ResetCharacter")
AddPage(ResetPage)

ResetMessage = MakeText(
	ResetPage.Frame,
	"Are you sure you want to reset your character?",
	UDim2.new(1, -20, 0, 100),
	UDim2.new(0, 10, 0, 108)
)
ResetMessage.TextSize = 36

LeaveMessage = nil

GetResetButtonAllowed = function()
	local Allowed = true
	Protect(function()
		if StarterGui:GetCore("ResetButtonCallback") == false then
			Allowed = false
		end
	end)
	return Allowed
end

ApplyResetButtonAvailability = function()
	local Allowed = GetResetButtonAllowed()
	local NormalColor = Color3.new(1, 1, 1)
	local DisabledColor = Color3.fromRGB(135, 135, 135)

	if ResetButton then
		ResetButton.Active = Allowed
		ResetButton.Selectable = Allowed
		ResetButton.AutoButtonColor = false
		ResetButton.ImageColor3 = Allowed and NormalColor or DisabledColor
		if ResetButtonLabel then
			ResetButtonLabel.TextColor3 = Allowed and NormalColor or DisabledColor
		end
	end

	if MobileActionButtons and MobileActionButtons.Reset then
		local Button = MobileActionButtons.Reset
		Button.Active = Allowed
		Button.Selectable = Allowed
		Button.AutoButtonColor = false
		Button.ImageColor3 = Allowed and NormalColor or DisabledColor
		for _, Child in next, Button:GetDescendants() do
			if Child:IsA("ImageLabel") or Child:IsA("ImageButton") then
				Child.ImageColor3 = Allowed and NormalColor or DisabledColor
			elseif Child:IsA("TextLabel") or Child:IsA("TextButton") then
				Child.TextColor3 = Allowed and NormalColor or DisabledColor
			end
		end
	end

	return Allowed
end

ResetCharacter =
	function()
		if not GetResetButtonAllowed() then
			ApplyResetButtonAvailability()
			return
		end
		local Character = LocalPlayer.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			Humanoid.Health = 0
		end
		SetVisibility(false, true)
	end

LeaveGame =
	function()
		game:shutdown()
	end

ResetButton, ResetButtonLabel =
	MakeStyledButton(
		"ResetCharacter",
		"Reset",
		UDim2.new(0, 200, 0, 50),
		ResetCharacter,
		true
	)
ResetButton.Parent = ResetPage.Frame
ApplyResetButtonAvailability()

DontResetButton =
	MakeStyledButton(
		"DontResetCharacter",
		"Don't Reset",
		UDim2.new(0, 200, 0, 50),
		function()
			Hub.InConfirmation = false
			Hub.HubBar.Visible = true
			Hub.PageClipper.Visible = true
			Hub.BottomButtonFrame.Visible = true
			if HomeButton then
				HomeButton.Visible = HomeButtonEnabled and not IsMobile
			end
			SwitchToPage(Hub.MenuStack[#Hub.MenuStack] or GamePage, true, true)
			ResizeHub()
		end
	)
DontResetButton.Parent = ResetPage.Frame
ResetPage.Frame.Size = UDim2.new(1, 0, 0, 280)

LeavePage = MakePage("LeaveGame")
AddPage(LeavePage)
LeaveMessage = MakeText(
	LeavePage.Frame,
	"Are you sure you want to leave the game?",
	UDim2.new(1, -20, 0, 100),
	UDim2.new(0, 10, 0, 108)
)
LeaveMessage.TextSize = 36

LeaveButton = MakeStyledButton("LeaveGame", "Leave", UDim2.new(0, 200, 0, 50), LeaveGame, true)
LeaveButton.Parent = LeavePage.Frame

DontLeaveButton = MakeStyledButton(
	"DontLeaveGame",
	"Don't Leave",
	UDim2.new(0, 200, 0, 50),
	function()
		Hub.InConfirmation = false
		Hub.HubBar.Visible = true
		Hub.PageClipper.Visible = true
		Hub.BottomButtonFrame.Visible = true
		if HomeButton then HomeButton.Visible = HomeButtonEnabled and not IsMobile end
		SwitchToPage(Hub.MenuStack[#Hub.MenuStack] or GamePage, true, true)
		ResizeHub()
	end
)
DontLeaveButton.Parent = LeavePage.Frame
LeavePage.Frame.Size = UDim2.new(1, 0, 0, 280)

PositionDesktopConfirmationButtons =
	function()
		if IsMobile then
			return
		end

		for _, Info in next,
			{
				{
					ResetPage.Frame,
					ResetButton,
					DontResetButton,
				},
				{
					LeavePage.Frame,
					LeaveButton,
					DontLeaveButton,
				},
			}
		do

			local LeftButton = Info[2]
			local RightButton = Info[3]

			local ButtonWidth = 200

			LeftButton.Size = UDim2.new(0, ButtonWidth, 0, 50)
			RightButton.Size = UDim2.new(0, ButtonWidth, 0, 50)
			LeftButton.Visible = true
			RightButton.Visible = true
			LeftButton.Active = true
			RightButton.Active = true
			LeftButton.Selectable = true
			RightButton.Selectable = true
			LeftButton.ZIndex = SETTINGS_BASE_ZINDEX + 3
			RightButton.ZIndex = SETTINGS_BASE_ZINDEX + 3

			LeftButton.Position = UDim2.new(0.5, -206, 0, 268)

			RightButton.Position = UDim2.new(0.5, 6, 0, 268)

		end

	end

PositionMobileConfirmationButtons =
	function()
		if not IsMobile then return end
		local Viewport = ScreenGui.AbsoluteSize
		if Viewport.X <= 0 or Viewport.Y <= 0 then
			local Camera = workspace.CurrentCamera
			Viewport = (Camera and Camera.ViewportSize) or Vector2.new(1280, 720)
		end
		local AvailableWidth = math.max(250, Viewport.X - 24)
		local ButtonWidth = math.min(168, math.max(108, (AvailableWidth - 12) / 2))
		for _, Info in next, {
			{ResetPage.Frame, ResetButton, DontResetButton},
			{LeavePage.Frame, LeaveButton, DontLeaveButton},
		} do
			local Frame, LeftButton, RightButton = Info[1], Info[2], Info[3]
			Frame.Size = UDim2.new(1, 0, 0, 240)
			local Message = Frame:FindFirstChildWhichIsA("TextLabel")
			if Message then
				Message.Size = UDim2.new(1, -24, 0, 88)
				Message.Position = UDim2.new(0, 12, 0, 20)
				Message.TextWrapped = true
				Message.TextSize = 22
			end
			LeftButton.Size = UDim2.new(0, ButtonWidth, 0, 48)
			RightButton.Size = UDim2.new(0, ButtonWidth, 0, 48)
			LeftButton.Position = UDim2.new(0.5, -(ButtonWidth + 6), 0, 150)
			RightButton.Position = UDim2.new(0.5, 6, 0, 150)
			for _, Button in ipairs({LeftButton, RightButton}) do
				local Label = Button:FindFirstChildWhichIsA("TextLabel", true)
				if Label then
					Label.TextSize = 18
					Label.TextWrapped = true
				end
			end
		end
	end

-- ============================================================
-- ALERT
-- ============================================================

ActiveAlert = nil

ShowAlert =
	function(AlertMessage, OkButtonText, Cleanup)
		if ActiveAlert then
			ActiveAlert:Destroy()
			ActiveAlert = nil
		end

		Hub.HubBar.Visible = false
		Hub.PageClipper.Visible = false
		Hub.BottomButtonFrame.Visible = false

		local AlertWidth = IsPhone and math.max(250, math.min(380, ScreenGui.AbsoluteSize.X - 24)) or 400
		local AlertHeight = IsPhone and 240 or 350
		local Alert = Create(
			"ImageLabel",
			{
				Name = "AlertViewBacking",
				Parent = Hub.Shield,
				Image = BUTTON_IMAGE,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(8, 6, 46, 44),
				BackgroundTransparency = 1,
				Size = UDim2.new(0, AlertWidth, 0, AlertHeight),
				Position = UDim2.new(0.5, -AlertWidth / 2, 0.5, -AlertHeight / 2),
				ZIndex = SETTINGS_BASE_ZINDEX + 30,
			}
		)
		ActiveAlert = Alert

		Create("TextLabel", {
			Name = "AlertViewText",
			Parent = Alert,
			BackgroundTransparency = 1,
			Size = UDim2.new(0.95, 0, 0.6, 0),
			Position = UDim2.new(0.025, 0, 0.05, 0),
			Font = Enum.Font.SourceSansBold,
			TextSize = IsPhone and 20 or 36,
			Text = AlertMessage,
			TextWrapped = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = SETTINGS_BASE_ZINDEX + 31,
		})

		local Button, ButtonText = MakeStyledButton(
			"AlertViewButton",
			OkButtonText or "Ok",
			UDim2.new(0, IsPhone and math.min(170, AlertWidth - 32) or 200, 0, IsPhone and 42 or 50),
			function()
				if ActiveAlert then
					ActiveAlert:Destroy()
					ActiveAlert = nil
				end
				if Cleanup then
					Cleanup()
				else
					Hub.HubBar.Visible = true
					Hub.PageClipper.Visible = true
					Hub.BottomButtonFrame.Visible = true
				end
			end
		)
		Button.Parent = Alert
		local AlertButtonWidth = IsPhone and math.min(170, AlertWidth - 32) or 200
		Button.Position = UDim2.new(0.5, -AlertButtonWidth / 2, 0.68, 0)
		if ButtonText then ButtonText.TextSize = IsPhone and 16 or ButtonText.TextSize end
		Button.ZIndex = SETTINGS_BASE_ZINDEX + 31
		ButtonText.ZIndex = SETTINGS_BASE_ZINDEX + 32
	end

-- ============================================================
-- CONFIRMATION PAGE NAVIGATION
-- ============================================================

PushPage =
	function(Page)
		if not Page then return end
		Insert(Hub.MenuStack, Hub.CurrentPage)
		Hub.InConfirmation = Page == ResetPage or Page == LeavePage
		Hub.InInviteMenu = false
		Hub.HubBar.Visible = false
		Hub.BottomButtonFrame.Visible = false
		if HomeButton then HomeButton.Visible = false end
		Hub.PageClipper.Visible = true
		Hub.PageView.ScrollBarThickness = 0
		SwitchToPage(Page, true, true)
		if Hub.InConfirmation then
			if IsPhone then
				PositionMobileConfirmationButtons()
			else
				PositionDesktopConfirmationButtons()
			end
		end
	end

-- ============================================================
-- MOBILE BOTTOM BUTTONS
-- ============================================================

MakeBottomButton =
	function(Name, Text, Icon, Position, Clicked, Size)
		local Button=MakeStyledButton(Name.."Button",Text,Size or UDim2.new(0,260,0,70),Clicked)
		Button.Parent=Hub.BottomButtonFrame
		Button.Position=Position
		local Hint=Create("ImageLabel",{Name=Name.."Hint",ZIndex=SETTINGS_BASE_ZINDEX+2,BackgroundTransparency=1,Image=Icon,Parent=Button})
		Hint.AnchorPoint=Vector2.new(0.5,0.5)
		Hint.Size=UDim2.new(0,50,0,50)
		Hint.Position=UDim2.new(0.15,0,0.475,0)
		local Label=Button:FindFirstChild(Name.."ButtonTextLabel")
		if Label then
			Label.TextSize=24
			Label.TextWrapped=false
			Label.TextScaled=false
			Label.TextXAlignment=Enum.TextXAlignment.Center
			Label.TextYAlignment=Enum.TextYAlignment.Center
			Label.Size=UDim2.new(0.75,0,0.9,0)
			Label.Position=UDim2.new(0.25,0,0,0)
		end
		return Button
	end

MobileButtonsContainer = nil
MobileActionButtons = {}
BottomButtonSize = UDim2.new(0,260,0,70)

MobileActionButtons.Reset = MakeBottomButton(
	"ResetCharacter",
	"Reset Character",
	"rbxasset://textures/ui/Settings/Help/ResetIcon.png",
	UDim2.new(0, 4, 0.5, -32),
	function()
			if GetResetButtonAllowed() then
				PushPage(ResetPage)
			else
				ApplyResetButtonAvailability()
			end
		end,
	BottomButtonSize
)

MobileActionButtons.Leave = MakeBottomButton(
	"LeaveGame",
	"Leave",
	"rbxasset://textures/ui/Settings/Help/LeaveIcon.png",
	UDim2.new(0, 270, 0.5, -32),
	function() PushPage(LeavePage) end,
	BottomButtonSize
)

MobileActionButtons.Resume = MakeBottomButton(
	"Resume",
	"Resume",
	"rbxasset://textures/ui/Settings/Help/EscapeIcon.png",
	UDim2.new(0, 536, 0.5, -32),
	function() SetVisibility(false) end,
	BottomButtonSize
)

-- ============================================================
-- LEGACY RED CONNECTION-ERROR BANNER (MIC ACTION FALLBACK)
-- Matches the old LoadingScript ErrorFrame appearance without changing
-- GuiService's real connection-error state.
-- ============================================================
local VoiceMuteErrorOverlay = nil
local VoiceMuteErrorFrame = nil
local VoiceMuteErrorLabel = nil
local VoiceMuteErrorGeneration = 0

local function EnsureVoiceMuteErrorBanner()
	if VoiceMuteErrorOverlay and VoiceMuteErrorOverlay.Parent and VoiceMuteErrorFrame and VoiceMuteErrorFrame.Parent then
		return VoiceMuteErrorFrame, VoiceMuteErrorLabel
	end

	local Existing = nil
	pcall(function()
		Existing = CoreGui:FindFirstChild("Settings2016VoiceMuteErrorOverlay")
	end)

	if Existing and Existing:IsA("ScreenGui") then
		VoiceMuteErrorOverlay = Existing
	else
		local Screen = Instance.new("ScreenGui")
		Screen.Name = "Settings2016VoiceMuteErrorOverlay"
		Screen.IgnoreGuiInset = true
		Screen.ResetOnSpawn = false
		Screen.DisplayOrder = 100000
		Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		Screen.Parent = CoreGui
		VoiceMuteErrorOverlay = Screen
	end

	local Frame = VoiceMuteErrorOverlay:FindFirstChild("ErrorFrame")
	if not (Frame and Frame:IsA("Frame")) then
		Frame = Instance.new("Frame")
		Frame.Name = "ErrorFrame"
		Frame.Parent = VoiceMuteErrorOverlay
	end
	Frame.BackgroundColor3 = Color3.fromRGB(253, 68, 72)
	Frame.BackgroundTransparency = 0
	Frame.BorderSizePixel = 0
	Frame.Position = UDim2.new(0.25, 0, 0, 0)
	Frame.Size = UDim2.new(0.5, 0, 0, 80)
	Frame.ZIndex = 8
	Frame.Visible = false

	local Label = Frame:FindFirstChild("ErrorText")
	if not (Label and Label:IsA("TextLabel")) then
		Label = Instance.new("TextLabel")
		Label.Name = "ErrorText"
		Label.Parent = Frame
	end
	Label.BackgroundTransparency = 1
	Label.Size = UDim2.new(1, 0, 1, 0)
	Label.Position = UDim2.new(0, 0, 0, 0)
	Label.Font = Enum.Font.SourceSansBold
	Label.TextSize = 14
	Label.TextWrapped = true
	Label.TextColor3 = Color3.fromRGB(255, 255, 255)
	Label.Text = ""
	Label.ZIndex = 9

	VoiceMuteErrorFrame = Frame
	VoiceMuteErrorLabel = Label
	return Frame, Label
end

local function ShowVoiceMuteError(TargetMuted)
	local Action = TargetMuted and "mute" or "unmute"
	local Message = "An error occurred while trying to " .. Action .. ". Please try the voice chat bubble to " .. Action .. "."

	local Ok = pcall(function()
		local Frame, Label = EnsureVoiceMuteErrorBanner()
		Label.Text = Message
		Frame.Visible = true
	end)
	if not Ok then return false end

	VoiceMuteErrorGeneration = VoiceMuteErrorGeneration + 1
	local ThisGeneration = VoiceMuteErrorGeneration
	task.spawn(function()
		task.wait(4)
		if ThisGeneration == VoiceMuteErrorGeneration and VoiceMuteErrorFrame then
			pcall(function() VoiceMuteErrorFrame.Visible = false end)
		end
	end)
	return true
end

VoiceChatButton = MakeBottomButton(
	"VoiceChat",
	"",
	VOICE_MIC_ROOT .. "Unmuted0@3x.png",
	UDim2.new(0, 716, 0.5, -32),
	function()
		if not VoiceOptionAvailable then
			return
		end
		-- Bottom microphone is exclusively mute/unmute. Connection is managed
		-- separately by the voice runtime; this button never acts as a Connect UI.
		-- Use the live publishing pause state for the action label. The native
		-- CoreGui icon may be stale while the legacy voice controller has changed.
		local CurrentOk, CurrentMuted = pcall(function() return GetLocalVoiceMuted() end)
		if not CurrentOk then
			return
		end
		local TargetMuted = not (CurrentMuted == true)
		-- This build intentionally reports the old red-banner error and leaves
		-- the real mute state untouched. Use Roblox's voice bubble to change it.
		ShowVoiceMuteError(TargetMuted)
		return

	end,
	UDim2.new(0, 64, 0, 64)
)
VoiceChatButton.Visible = VoiceOptionAvailable == true and not IsMobile

VoiceChatIcon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
if VoiceChatIcon then
	VoiceChatIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	VoiceChatIcon.Size = UDim2.fromOffset(50, 50)
	VoiceChatIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
end

ConfigureMobileActionButtons = function()
	-- Show a mute/unmute button whenever voice is available for this account/place.
	-- It is not a separate Voice Chat Connected toggle and does not initiate joins.
	local VoiceActive = VoiceOptionAvailable == true and not IsMobile
	local UiScale = GetMobileUiScale()
	local ActionHeight = 62
	local Gap = math.max(4, math.floor(MOBILE_LAYOUT_GAP * UiScale + 0.5))

	local UseFourColumnLayout = VoiceActive and not IsMobile

	if IsMobile then
		if IsTablet then
			Hub.BottomButtonFrame.Parent = Hub.MenuContainer
			Hub.BottomButtonFrame.Visible = Hub.Visible and not Hub.InInviteMenu and not Hub.InConfirmation
			Hub.BottomButtonFrame.ZIndex = SETTINGS_BASE_ZINDEX + 6
			MobileActionButtons.Reset.Parent = Hub.BottomButtonFrame
			MobileActionButtons.Leave.Parent = Hub.BottomButtonFrame
			MobileActionButtons.Resume.Parent = Hub.BottomButtonFrame
			VoiceChatButton.Parent = Hub.BottomButtonFrame
		elseif PlayersPage and PlayersPage.Frame then
			if not MobileButtonsContainer or not MobileButtonsContainer.Parent then
				MobileButtonsContainer = Create("Frame", {
					Name = "ButtonsContainer", Parent = PlayersPage.Frame,
					BackgroundTransparency = 1, BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 62), Position = UDim2.new(0, 0, 0, 0),
					ZIndex = SETTINGS_BASE_ZINDEX + 1,
				})
			end
			MobileButtonsContainer.Size = UDim2.new(1, 0, 0, 62)
			MobileButtonsContainer.Position = UDim2.new(0, 0, 0, 0)
			MobileActionButtons.Reset.Parent = MobileButtonsContainer
			MobileActionButtons.Leave.Parent = MobileButtonsContainer
			MobileActionButtons.Resume.Parent = MobileButtonsContainer
			VoiceChatButton.Parent = PlayersPage.Frame
		end
	end

	if IsMobile then
		local ButtonCount = UseFourColumnLayout and 4 or 3
		local Fraction = 1 / ButtonCount
		local ButtonWidthOffset = -Gap
		MobileActionButtons.Leave.Size = UDim2.new(Fraction, ButtonWidthOffset, 0, ActionHeight)
		MobileActionButtons.Reset.Size = UDim2.new(Fraction, ButtonWidthOffset, 0, ActionHeight)
		MobileActionButtons.Resume.Size = UDim2.new(Fraction, ButtonWidthOffset, 0, ActionHeight)
		MobileActionButtons.Leave.AnchorPoint = Vector2.new(0, 0)
		MobileActionButtons.Reset.AnchorPoint = Vector2.new(0.5, 0)
		MobileActionButtons.Resume.AnchorPoint = Vector2.new(1, 0)
		MobileActionButtons.Leave.Position = UDim2.new(0, 0, 0, 0)
		MobileActionButtons.Reset.Position = UDim2.new(0.5, 0, 0, 0)
		MobileActionButtons.Resume.Position = UDim2.new(1, 0, 0, 0)
		if IsTablet then
			Hub.BottomButtonFrame.Parent = Hub.MenuContainer
			Hub.BottomButtonFrame.Visible = Hub.Visible and not Hub.InInviteMenu and not Hub.InConfirmation
			Hub.BottomButtonFrame.Size = UDim2.new(1, 0, 0, ActionHeight)
			Hub.BottomButtonFrame.Position = UDim2.new(0, 0, 1, -ActionHeight)
			Hub.BottomButtonFrame.ZIndex = SETTINGS_BASE_ZINDEX + 6
			Hub.BottomButtonFrame.ClipsDescendants = false
		end

		for _, Button in next, {MobileActionButtons.Reset, MobileActionButtons.Leave, MobileActionButtons.Resume} do
			Button.Visible = true
			Button.ZIndex = SETTINGS_BASE_ZINDEX + 4
			for _, Child in next, Button:GetChildren() do
				if Child:IsA("ImageLabel") then Child.Visible = false end
			end
			local Label = Button:FindFirstChild(Button.Name .. "TextLabel")
			if Label then
				Label.TextSize = 20
				Label.TextWrapped = false
				Label.TextScaled = false
				Label.TextXAlignment = Enum.TextXAlignment.Center
				Label.TextYAlignment = Enum.TextYAlignment.Center
				Label.Position = UDim2.new(0, 0, 0, 0)
				Label.Size = UDim2.new(1, 0, 1, 0)
			end
		end
		VoiceChatButton.Visible = false
	else
		-- PC desktop: reserve space for the mic and resize all three action buttons to match.
		local FrameWidth = tonumber(Hub.BottomButtonFrame.AbsoluteSize.X) or 0
		if FrameWidth <= 0 then FrameWidth = Hub.BottomButtonFrame.Size.X.Offset end
		if FrameWidth <= 0 then FrameWidth = 800 end
		local FrameHeight = 70
		-- The original frame was only 60px tall while its three action buttons were
		-- 70px tall. Match the frame to the buttons so the mic is not clipped/squashed.
		Hub.BottomButtonFrame.Size = UDim2.new(0, FrameWidth, 0, FrameHeight)
		local ActionGap = VoiceActive and 8 or 10
		local VoiceButtonWidth = VoiceActive and FrameHeight or 0
		local ActionWidth = 260
		if VoiceActive then
			ActionWidth = math.max(120, math.floor((FrameWidth - VoiceButtonWidth - (ActionGap * 3) - 2) / 3))
		end
		MobileActionButtons.Reset.Size = UDim2.new(0, ActionWidth, 0, FrameHeight)
		MobileActionButtons.Leave.Size = UDim2.new(0, ActionWidth, 0, FrameHeight)
		MobileActionButtons.Resume.Size = UDim2.new(0, ActionWidth, 0, FrameHeight)
		MobileActionButtons.Reset.Position = UDim2.new(0, 0, 0.5, -FrameHeight / 2)
		MobileActionButtons.Leave.Position = UDim2.new(0, ActionWidth + ActionGap, 0.5, -FrameHeight / 2)
		MobileActionButtons.Resume.Position = UDim2.new(0, (ActionWidth + ActionGap) * 2, 0.5, -FrameHeight / 2)
		MobileActionButtons.Reset.Visible = true
		MobileActionButtons.Leave.Visible = true
		MobileActionButtons.Resume.Visible = true
		VoiceChatButton.Parent = Hub.BottomButtonFrame
		VoiceChatButton.AnchorPoint = Vector2.new(1, 0.5)
		local ActualVoiceWidth = VoiceActive and VoiceButtonWidth or FrameHeight
		VoiceChatButton.Size = UDim2.new(0, ActualVoiceWidth, 0, FrameHeight)
		VoiceChatButton.Position = UDim2.new(1, -2, 0.5, 0)
		VoiceChatButton.Visible = VoiceActive
		VoiceChatButton.ClipsDescendants = false
		if VoiceChatIcon and VoiceChatIcon.Parent then
			VoiceChatIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			VoiceChatIcon.Size = UDim2.fromOffset(50, 50)
			VoiceChatIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		end
	end
end

-- ============================================================
-- RESET BUTTON AVAILABILITY WATCH
-- ============================================================
Spawn(function()
	while ScreenGui and ScreenGui.Parent do
		ApplyResetButtonAvailability()
		Wait(0.25)
	end
end)

-- ============================================================
-- VOICE CHAT UI UPDATES
-- ============================================================

VoiceAutoReconnectStamp = 0

-- PeakLevel changes much faster than the GUI refresh loop. Keep the bottom
-- microphone icon on a fast sampling loop so it follows live microphone peaks.
Spawn(function()
	while ScreenGui and ScreenGui.Parent do
		if VoiceChatEnabled and LocalVoiceEnabled and VoiceChatButton and VoiceChatButton.Parent then
			LocalVoiceMuted = GetLocalVoiceMuted()
			local Icon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
			if Icon then
				local Image = VoiceContrastIcon(GetVoiceIcon(LocalPlayer))
				if Icon.Image ~= Image then Icon.Image = Image end
			end
		end
		Wait(0.033)
	end
end)

Spawn(function()
	while ScreenGui and ScreenGui.Parent do
		if VoiceOptionAvailable then
			local ConnectedNow = IsLocalVoiceConnectionReady()
			if not VoiceChatDesiredOn then
				SetVoiceChatPreference(true)
			elseif ConnectedNow then
				VoiceConnectionAttempting = false
				VoiceChatEnabled = true
				RefreshLocalVoiceState()
			elseif not VoiceConnectionAttempting and (os.clock() - VoiceAutoReconnectStamp) >= 12 then
				-- Retry quietly if the local voice session drops back to idle. Eligibility
				-- gates this path; this does not grant voice to an ineligible account.
				VoiceAutoReconnectStamp = os.clock()
				SetVoiceChatPreference(true)
			end
		end
		if VoiceGameSupported and NativeVoiceScanStamp == 0 then
			ScheduleNativeVoiceMirrorRefresh()
		end
		local Changed = RefreshVoiceParticipants()
		if Changed and RebuildPlayersPage then RebuildPlayersPage() end

		if VoiceChatButton and VoiceChatButton.Parent then
			local VoiceActive = VoiceOptionAvailable == true and not IsMobile
			VoiceChatButton.Visible = VoiceActive
			local Icon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
			if Icon then
				local Image = VoiceContrastIcon(GetVoiceIcon(LocalPlayer))
				if Icon.Image ~= Image then Icon.Image = Image end
			end
		end

		if VoiceGameSupported then
			for _, Player in next, Players:GetPlayers() do
				if Player ~= LocalPlayer then
					local UserId = tonumber(Player.UserId or Player.userId) or 0
					local Row = PlayersPage.Frame:FindFirstChild("PlayerLabel" .. Player.Name)
					local VoiceButton = Row and Row:FindFirstChild(Player.Name .. "VoiceButton")
					local BeforeVoice = VoiceEnabledCache[UserId] == true
					CheckVoiceForPlayer(Player)
					local HasVoice = VoiceEnabledCache[UserId] == true
					if BeforeVoice ~= HasVoice then
						if RebuildPlayersPage then RebuildPlayersPage() end
						break
					elseif VoiceButton then
						-- Remote eligibility cannot be queried client-side, so keep the button
						-- visible and update its activity/mute image even before a native bubble exists.
						VoiceButton.Visible = HasConfirmedPlayerVoice(Player)
						local VoiceIcon = VoiceButton:FindFirstChild("VoiceIcon")
						if VoiceIcon then
							local Image = VoiceContrastIcon(GetVoiceIcon(Player, GetRemoteVoiceMuted(Player)))
							if VoiceIcon.Image ~= Image then VoiceIcon.Image = Image end
						end
					end
				end
			end
		end

			Wait(1.0)
		end
	end)

-- Refresh visible player-row mic meters frequently; eligibility checks remain on the slower loop below.
Spawn(function()
	while ScreenGui and ScreenGui.Parent do
		if VoiceGameSupported and Hub and Hub.Visible and PlayersPage and PlayersPage.Frame then
			for _, Player in next, Players:GetPlayers() do
				if Player ~= LocalPlayer then
					local UserId = tonumber(Player.UserId or Player.userId) or 0
					local Row = PlayersPage.Frame:FindFirstChild("PlayerLabel" .. Player.Name)
					local VoiceButton = Row and Row:FindFirstChild(Player.Name .. "VoiceButton")
					local VoiceIcon = VoiceButton and VoiceButton:FindFirstChild("VoiceIcon")
					if VoiceIcon then
						local Image = VoiceContrastIcon(GetVoiceIcon(Player, GetRemoteVoiceMuted(Player)))
						if VoiceIcon.Image ~= Image then VoiceIcon.Image = Image end
					end
				end
			end
		end
		Wait(0.2)
	end
end)

Connect(LocalPlayer.ChildAdded, function(Child)
	if Child:IsA("AudioDeviceInput") then
		GetAudioDeviceInputCache[LocalPlayer] = Child
		EnsureVoiceAnalyzer(LocalPlayer)
		if VoiceChatDesiredOn and IsLocalVoiceConnectionReady() then
			VoiceChatEnabled = true
			RefreshLocalVoiceState()
		end
		if ConfigureMobileActionButtons then ConfigureMobileActionButtons() end
	end
end)

Connect(SoundService.DescendantAdded, function(Descendant)
	if not Descendant:IsA("AudioDeviceInput") then return end
	local Owner = nil
	pcall(function() Owner = Descendant.Player end)
	if not Owner then return end
	GetAudioDeviceInputCache[Owner] = Descendant
	if Owner == LocalPlayer then
		if VoiceChatDesiredOn and IsLocalVoiceConnectionReady() then
			VoiceChatEnabled = true
			RefreshLocalVoiceState()
		end
	else
		local UserId = tonumber(Owner.UserId or Owner.userId) or 0
		VoiceEnabledCache[UserId] = true
		VoiceCheckError[UserId] = nil
		local Override = VoiceMutedPlayers[UserId]
		if Override ~= nil then
			SetRemoteVoiceMuted(Owner, Override)
		elseif VoiceMuteAllActive then
			SetRemoteVoiceMuted(Owner, true)
		end
	end
	EnsureVoiceAnalyzer(Owner)
	if RebuildPlayersPage then RebuildPlayersPage() end
	if ConfigureMobileActionButtons then ConfigureMobileActionButtons() end
end)

VoicePlayerAudioHooks = VoicePlayerAudioHooks or setmetatable({}, {__mode = "k"})

local function WatchVoicePlayerAudio(Player)
	if not Player or Player == LocalPlayer or VoicePlayerAudioHooks[Player] then return end
	VoicePlayerAudioHooks[Player] = true
	Connect(Player.ChildAdded, function(Child)
		if not Child:IsA("AudioDeviceInput") then return end
		GetAudioDeviceInputCache[Player] = Child
		VoiceEnabledCache[Player.UserId] = true
		VoiceEligibilityQueryStamp[Player.UserId] = nil
		local Override = VoiceMutedPlayers[Player.UserId]
		if Override ~= nil then SetRemoteVoiceMuted(Player, Override)
		elseif VoiceMuteAllActive then SetRemoteVoiceMuted(Player, true) end
		EnsureVoiceAnalyzer(Player)
		if RebuildPlayersPage then RebuildPlayersPage() end
	end)
end

for _, Player in ipairs(Players:GetPlayers()) do
	WatchVoicePlayerAudio(Player)
end

Connect(Players.PlayerAdded, function(Player)
	local UserId = tonumber(Player.UserId) or 0
	VoiceEnabledCache[UserId] = nil
	VoiceCheckError[UserId] = nil
	VoiceEligibilityQueryStamp[UserId] = nil
	VoiceActivityPeak[UserId] = nil
	VoiceActivityStamp[UserId] = nil
	VoiceActivityPeakMeasured[UserId] = nil
	VoiceActivityActive[UserId] = nil
	WatchVoicePlayerAudio(Player)
	ScheduleNativeVoiceMirrorRefresh()
	-- Build the row immediately instead of waiting for this player to create an input.
	if RebuildPlayersPage then task.defer(function() if Player.Parent then RebuildPlayersPage() end end) end
	task.defer(function()
		if not Player.Parent then return end
		CheckVoiceForPlayer(Player, function(Enabled, IsUnknown)
			if Enabled then VoiceEnabledCache[UserId] = true
			elseif not IsUnknown then VoiceEnabledCache[UserId] = nil end
			if RebuildPlayersPage then RebuildPlayersPage() end
		end)
	end)
end)

Connect(Players.PlayerRemoving, function(Player)
	local UserId = tonumber(Player.UserId) or 0
	GetAudioDeviceInputCache[Player] = nil
	VoiceEnabledCache[UserId] = nil
	VoiceEligibilityQueryStamp[UserId] = nil
	VoiceActivityPeak[UserId] = nil
	VoiceActivityStamp[UserId] = nil
	VoiceActivityPeakMeasured[UserId] = nil
	VoiceActivityActive[UserId] = nil
	NativeVoiceIconObjects[UserId] = nil
	NativeVoiceIconImages[UserId] = nil
	NativeVoiceIconLastImages[UserId] = nil
	local Connection = NativeVoiceIconConnections[UserId]
	if Connection then pcall(function() Connection:Disconnect() end) end
	NativeVoiceIconConnections[UserId] = nil
	NativeVoiceIconConnectedObjects[UserId] = nil
	if RebuildPlayersPage then task.defer(RebuildPlayersPage) end
end)

if VoiceChatInternal then
	Protect(function()
		Connect(VoiceChatInternal.ParticipantsStateChanged, function()
			if not VoiceGameSupported then return end
			RefreshVoiceParticipants()
			if RebuildPlayersPage then RebuildPlayersPage() end
		end)
	end)
	Protect(function()
		Connect(VoiceChatInternal.PlayerMicActivitySignalChange, function(ActivityInfo, SpeakingOrInfo, PeakValue)
			if not VoiceGameSupported then return end
			local Payload = {}
			if type(ActivityInfo) == "table" then
				for Key, Value in next, ActivityInfo do Payload[Key] = Value end
			elseif typeof(ActivityInfo) == "Instance" then
				local UserId = nil
				pcall(function() if ActivityInfo:IsA("Player") then UserId = ActivityInfo.UserId end end)
				if not UserId then pcall(function() UserId = tonumber(ActivityInfo.UserId or ActivityInfo.userId) end) end
				if not UserId then return end
				Payload.userId = UserId
			else
				local UserId = tonumber(ActivityInfo)
				if not UserId then return end
				Payload.userId = UserId
			end
			local HasSpeakingField = Payload.active ~= nil or Payload.Active ~= nil
				or Payload.isSpeaking ~= nil or Payload.IsSpeaking ~= nil or Payload.is_speaking ~= nil
				or Payload.speaking ~= nil or Payload.Speaking ~= nil or Payload.isActive ~= nil
				or Payload.IsActive ~= nil or Payload.isMicActive ~= nil or Payload.IsMicActive ~= nil
				or Payload.isVoiceActive ~= nil or Payload.IsVoiceActive ~= nil or Payload.isTalking ~= nil
				or Payload.IsTalking ~= nil or Payload.talking ~= nil or Payload.isSpeakingNow ~= nil
				or Payload.SpeakingNow ~= nil
			local HasPeakField = Payload.peakLevel ~= nil or Payload.PeakLevel ~= nil or Payload.peak ~= nil
				or Payload.Peak ~= nil or Payload.level ~= nil or Payload.Level ~= nil
			if type(SpeakingOrInfo) == "boolean" and not HasSpeakingField then
				Payload.isSpeaking = SpeakingOrInfo
			elseif type(SpeakingOrInfo) == "number" then
				-- If this client splits level out as argument 2, it is fresher than
				-- any stale/default level value contained in the activity dictionary.
				Payload.peakLevel = SpeakingOrInfo
			elseif type(SpeakingOrInfo) == "table" then
				for Key, Value in next, SpeakingOrInfo do if Payload[Key] == nil then Payload[Key] = Value end end
			end
			if type(PeakValue) == "number" then Payload.peakLevel = PeakValue end
			VoiceProcessActivityInfo(Payload)
		end)
	end)
end

Connect(CoreGui.DescendantAdded, function(Descendant)
	if not VoiceGameSupported then return end
	if Descendant:IsA("ImageLabel") or Descendant:IsA("ImageButton") then
		local Image = tostring(Descendant.Image or "")
		if Image:find("VoiceChat", 1, true) then
			ScheduleNativeVoiceMirrorRefresh()
		end
	end
end)

-- ============================================================
-- NATIVE SETTINGS HIDING
-- ============================================================

NativeSettingsSuppressionSnapshots = NativeSettingsSuppressionSnapshots or setmetatable({}, {__mode = "k"})

CaptureNativeSettingsSuppressionSnapshot = function(Shield, AddedObject)
	if not Shield then return end
	local Snapshot = NativeSettingsSuppressionSnapshots[Shield]
	if not Snapshot then
		Snapshot = {Objects = {}, ByObject = {}, Initialized = false}
		NativeSettingsSuppressionSnapshots[Shield] = Snapshot
	end
	local Properties = {"Visible", "Active", "Selectable", "AutoButtonColor", "BackgroundTransparency", "ImageTransparency", "TextTransparency"}
	local function SaveObject(Object)
		if not Object then return end
		local IsGuiOk, IsGui = pcall(function() return Object:IsA("GuiObject") end)
		if not IsGuiOk or not IsGui then return end
		local SavedProps = Snapshot.ByObject[Object]
		if not SavedProps then
			SavedProps = {}
			Snapshot.ByObject[Object] = SavedProps
			table.insert(Snapshot.Objects, Object)
		end
		for _, Property in ipairs(Properties) do
			if SavedProps[Property] == nil then
				local ReadOk, Value = pcall(function() return Object[Property] end)
				if ReadOk then SavedProps[Property] = Value end
			end
		end
	end
	if not Snapshot.Initialized then
		SaveObject(Shield)
		local Ok, Descendants = pcall(function() return Shield:GetDescendants() end)
		if Ok then for _, Object in ipairs(Descendants) do SaveObject(Object) end end
		Snapshot.Initialized = true
	elseif AddedObject then
		SaveObject(AddedObject)
	end
end

SuppressNativeSettingsObject = function(Object)
	if not Object then return end
	local IsGuiOk, IsGui = pcall(function() return Object:IsA("GuiObject") end)
	if not IsGuiOk or not IsGui then return end
	pcall(function() Object.Visible = false end)
	pcall(function() Object.Active = false end)
	pcall(function() Object.Selectable = false end)
	pcall(function() Object.AutoButtonColor = false end)
	pcall(function() Object.BackgroundTransparency = 1 end)
	pcall(function() Object.ImageTransparency = 1 end)
	pcall(function() Object.TextTransparency = 1 end)
end

RestoreNativeSettingsSuppressionSnapshot = function(Shield)
	local Snapshot = Shield and NativeSettingsSuppressionSnapshots[Shield]
	if not Snapshot then return false end
	local Properties = {"Active", "Selectable", "AutoButtonColor", "BackgroundTransparency", "ImageTransparency", "TextTransparency", "Visible"}
	for _, Object in ipairs(Snapshot.Objects) do
		local SavedProps = Snapshot.ByObject[Object]
		if SavedProps then
			for _, Property in ipairs(Properties) do
				local Value = SavedProps[Property]
				if Value ~= nil then pcall(function() Object[Property] = Value end) end
			end
		end
	end
	return true
end

HideNativeSettingsMenu =
	function()
		if Hub and Hub.NativeMuteTransaction then return end
		local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
		local Shield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")
		if not Shield then return end
		CaptureNativeSettingsSuppressionSnapshot(Shield)
		local Snapshot = NativeSettingsSuppressionSnapshots[Shield]
		if not Snapshot then return end
		for _, Object in ipairs(Snapshot.Objects) do
			if Object and Object.Parent then SuppressNativeSettingsObject(Object) end
		end
	end

-- ============================================================
-- INPUT LOCK
-- ============================================================

INPUT_LOCK_ACTION = "Settings2016InputLock"
InputLockBound = false
InputLockInputs = {}
InputLockActions = {}
SavedMouseBehavior = nil
WasRightMouseDownOnLock = false

AddInputLock =
	function(EnumName, Name)
		Protect(function()
			local EnumType = Enum[EnumName]
			local Item = EnumType and EnumType[Name]
			if Item then Insert(InputLockInputs, Item) end
		end)
	end

AddInputLock("PlayerActions", "CharacterForward")
AddInputLock("PlayerActions", "CharacterBackward")
AddInputLock("PlayerActions", "CharacterLeft")
AddInputLock("PlayerActions", "CharacterRight")
AddInputLock("PlayerActions", "CharacterJump")
AddInputLock("KeyCode", "W")
AddInputLock("KeyCode", "A")
AddInputLock("KeyCode", "S")
AddInputLock("KeyCode", "D")
AddInputLock("KeyCode", "Space")
AddInputLock("KeyCode", "LeftShift")
AddInputLock("KeyCode", "RightShift")
AddInputLock("KeyCode", "Thumbstick1")
AddInputLock("KeyCode", "Thumbstick2")
AddInputLock("UserInputType", "MouseButton2")

IsRightMouseDown =
	function()
		local IsDown = false
		Protect(function()
			IsDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		end)
		return IsDown
	end

ReleaseRightMouseCapture =
	function()
		Protect(function()
			if mouse2release then mouse2release() end
		end)
		Protect(function()
			if VirtualInputManager then
				local MouseLocation = UserInputService:GetMouseLocation()
				VirtualInputManager:SendMouseButtonEvent(MouseLocation.X, MouseLocation.Y, 1, false, game, 0)
			end
		end)
	end

SinkGameplayInput =
	function()
		local FocusedTextBox
		Protect(function() FocusedTextBox = UserInputService:GetFocusedTextBox() end)
		if FocusedTextBox then return Enum.ContextActionResult.Pass end
		return Enum.ContextActionResult.Sink
	end

SetGameplayInputLocked =
	function(Locked)
		if InputLockBound == Locked then return end
		InputLockBound = Locked
		if Locked then
			Protect(function()
				WasRightMouseDownOnLock = IsRightMouseDown()
				SavedMouseBehavior = UserInputService.MouseBehavior
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
			ReleaseRightMouseCapture()
			InputLockActions = {}
			for Index, Input in next, InputLockInputs do
				local ActionName = INPUT_LOCK_ACTION .. tostring(Index)
				local Bound = Protect(function()
					ContextActionService:BindCoreActionAtPriority(ActionName, SinkGameplayInput, false, 10000, Input)
				end)
				if not Bound then
					Bound = Protect(function()
						ContextActionService:BindCoreAction(ActionName, SinkGameplayInput, false, Input)
					end)
				end
				if not Bound then
					Bound = Protect(function()
						ContextActionService:BindActionAtPriority(ActionName, SinkGameplayInput, false, 10000, Input)
					end)
				end
				if Bound then Insert(InputLockActions, ActionName) end
			end
		else
			for _, ActionName in next, InputLockActions do
				Protect(function() ContextActionService:UnbindCoreAction(ActionName) end)
				Protect(function() ContextActionService:UnbindAction(ActionName) end)
			end
			InputLockActions = {}
			Protect(function()
				if SavedMouseBehavior and not (WasRightMouseDownOnLock and SavedMouseBehavior == Enum.MouseBehavior.LockCurrentPosition) then
					UserInputService.MouseBehavior = SavedMouseBehavior
				else
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
				SavedMouseBehavior = nil
				WasRightMouseDownOnLock = false
			end)
		end
	end

-- ============================================================
-- SET VISIBILITY
-- ============================================================

SetVisibility =
	function(Visible, NoAnimation, CustomPage)
		if Hub.Visible == Visible and not CustomPage then return end

		Hub.Visible = Visible
		Hub.Modal.Visible = Visible

		if not Visible then
			Hub.InInviteMenu = false
			InviteSelectedIndex = 0
			InviteSelectedFriendId = nil
			HideInviteSelection()
			Protect(function() GuiService.SelectedObject = nil end)
			Protect(function() GuiService.SelectedCoreObject = nil end)
			Hub.InConfirmation = false
			if InviteHeader then InviteHeader.Visible = false end
			if InviteList then InviteList.Visible = false end
			if SearchBox then
				pcall(function() SearchBox:ReleaseFocus() end)
			end
		end

		SetGameplayInputLocked(Visible)

		if Visible then
			SystemMenuButtonClosing = false
			-- ESC menu is open: hide the recorder overlay, but keep its timer
			-- and recording state running.
			SetRecorderOverlayVisibility(false)
			if SystemMenuHitbox then
				SystemMenuHitbox.Visible = true
				SystemMenuHitbox.Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X - 4, SYSTEM_MENU_OFFSET_Y - 4)
				SystemMenuHitbox.Size = UDim2.fromOffset(40, 40)
			end
			HideNativeSettingsMenu()
			SetTopBarAppEnabled(false)
			SetTopbarCoreGuiEnabled(false)
			Hub.Shield.Visible = true
			Hub.HubBar.Visible = not Hub.InInviteMenu and not Hub.InConfirmation
			Hub.PageClipper.Visible = true
			Hub.BottomButtonFrame.Visible = ((not IsMobile) or IsTablet) and not Hub.InInviteMenu and not Hub.InConfirmation
			if HomeButton then
				HomeButton.Visible = HomeButtonEnabled and not IsMobile and not Hub.InInviteMenu and not Hub.InConfirmation
			end
			if SystemMenuButton then
				SystemMenuButton.Visible = true
				SystemMenuButton.Size = UDim2.fromOffset(30, 30)
			end

			if NoAnimation then
				Hub.Shield.Position = SETTINGS_ACTIVE_POSITION
			else
				Hub.Shield.Position = SETTINGS_INACTIVE_POSITION
				TweenTo(Hub.Shield, SETTINGS_ACTIVE_POSITION, Enum.EasingDirection.InOut, Enum.EasingStyle.Quart, 0.5)
			end

			-- Native voice icons are refreshed asynchronously by CoreGui events and the
			-- throttled voice cache loop; don't scan GUI descendants in the opening frame.
			SwitchToPage(CustomPage or PlayersPage, true)
			if PendingPlayerListRefresh and PlayersPage then
				RebuildPlayersPage()
				LayoutTabs()
				PendingPlayerListRefresh = false
			end
			ConfigureMobileActionButtons()
			ResizeHub()
			if IsMobile and not IsTablet then
				task.defer(function()
					if not Hub.Visible or not PlayersPage or not PlayersPage.Frame then return end
					MobileActionButtons.Reset.Parent = PlayersPage.Frame
					MobileActionButtons.Leave.Parent = PlayersPage.Frame
					MobileActionButtons.Resume.Parent = PlayersPage.Frame
					ConfigureMobileActionButtons()
					ResizeHub()
				end)
			end
		else
			-- Keep the native TopBarApp disabled while the custom menu is closing.
			-- It is re-enabled only after the closing tween has actually finished.
			SetTopBarAppEnabled(false)
			SetTopbarCoreGuiEnabled(true)
			if SystemMenuButton then
				-- Keep the visible 30x30 SystemMenuButton unchanged for the entire
				-- closing tween. Only hide it in the tween completion callback below.
				SystemMenuButton.Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X, SYSTEM_MENU_OFFSET_Y)
				SystemMenuButton.Size = UDim2.fromOffset(30, 30)
				SystemMenuButton.Active = true
				SystemMenuButton.Selectable = true
				pcall(function()
					SystemMenuButton.ImageTransparency = 0
				end)
			end
			if NoAnimation then
				-- Mobile and explicitly instant closes hide content immediately.
				Hub.HubBar.Visible = false
				Hub.BottomButtonFrame.Visible = false
				Hub.PageClipper.Visible = false
				if HomeButton then HomeButton.Visible = false end
				SystemMenuButtonClosing = false
				SyncTopBarAppVisibility()
				SetRecorderOverlayVisibility(true)
				if SystemMenuHitbox then SystemMenuHitbox.Visible = true end
				if SystemMenuButton then SystemMenuButton.Visible = false end
				Hub.Shield.Position = SETTINGS_INACTIVE_POSITION
				Hub.Shield.Visible = false
			else
				SystemMenuButtonClosing = true
				if SystemMenuHitbox then
					SystemMenuHitbox.Visible = true
					SystemMenuHitbox.Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X - 4, SYSTEM_MENU_OFFSET_Y - 4)
					SystemMenuHitbox.Size = UDim2.fromOffset(40, 40)
				end
				if SystemMenuButton then SystemMenuButton.Visible = true end
				TweenTo(Hub.Shield, SETTINGS_INACTIVE_POSITION, Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.4, function()
					if not Hub.Visible then
						-- Hide the Leave/Resume footer and page only after the desktop slide ends.
						Hub.HubBar.Visible = false
						Hub.BottomButtonFrame.Visible = false
						Hub.PageClipper.Visible = false
						if HomeButton then HomeButton.Visible = false end
						Hub.Shield.Visible = false
						SystemMenuButtonClosing = false
						SyncTopBarAppVisibility()
						SetRecorderOverlayVisibility(true)
						-- Keep the invisible 40x40 shield permanently over the native top-left button.
						if SystemMenuHitbox then
							SystemMenuHitbox.Visible = true
							SystemMenuHitbox.Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X - 4, SYSTEM_MENU_OFFSET_Y - 4)
							SystemMenuHitbox.Size = UDim2.fromOffset(40, 40)
						end
						if SystemMenuButton then SystemMenuButton.Visible = false end
					end
				end)
			end
		end
	end

-- ============================================================
-- SYSTEM MENU BUTTON
-- ============================================================

SystemMenuButtonClosing = false
SystemMenuHitbox = nil

SystemMenuButton =
	Create(
		"ImageButton",
		{
			Name = "SystemMenuButton",
			Parent = ScreenGui,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = SYSTEM_MENU_ICON,

			-- Original visual SystemMenuButton: 30x30.
			-- The separate 40x40 SystemMenuHitbox provides the larger click area.
			ImageTransparency = 0,
			ScaleType = Enum.ScaleType.Fit,
			ImageRectOffset = SYSTEM_MENU_ICON_RECT_OFFSET,
			ImageRectSize = SYSTEM_MENU_ICON_RECT_SIZE,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X, SYSTEM_MENU_OFFSET_Y),
			AutoButtonColor = false,
			Visible = false,
			Active = true,
			Selectable = true,
			ZIndex = SETTINGS_BASE_ZINDEX + 100,
		}
	)

Insert(Data.Objects, SystemMenuButton)
Create("UICorner", {Parent = SystemMenuButton, CornerRadius = UDim.new(0, 8)})

-- Original SystemMenuButton image is rendered directly by the 30x30 ImageButton.

SystemMenuSelection = Create(
	"ImageLabel",
	{
		Name = "SelectionImageObject",
		Parent = SystemMenuButton,
		BackgroundTransparency = 1,
		ImageTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = SETTINGS_BASE_ZINDEX + 101,
	}
)
Create("UICorner", {Parent = SystemMenuSelection, CornerRadius = UDim.new(0, 8)})
SystemMenuButton.SelectionImageObject = SystemMenuSelection

-- 40x40 transparent custom hitbox. The visible SystemMenuButton stays 30x30,
-- while this larger shield sits over the same native top-left click area.
SystemMenuHitbox = Create(
	"ImageButton",
	{
		Name = "SystemMenuButtonHitbox",
		Parent = ScreenGui,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = "",
		ImageTransparency = 1,
		AutoButtonColor = false,
		Active = true,
		Selectable = false,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X - 4, SYSTEM_MENU_OFFSET_Y - 4),
		Visible = false,
		ZIndex = SETTINGS_BASE_ZINDEX + 102,
	}
)
Insert(Data.Objects, SystemMenuHitbox)

NativeSystemMenuButtonCache = NativeSystemMenuButtonCache or {}
NativeSystemMenuButtonCacheInitialized = NativeSystemMenuButtonCacheInitialized or false

HideNativeSystemMenuButtons =
	function()
		-- CoreGui is walked once, not on every 0.25s button-alignment pass.
		if not NativeSystemMenuButtonCacheInitialized then
			NativeSystemMenuButtonCacheInitialized = true
			pcall(function()
				for _, Object in ipairs(CoreGui:GetDescendants()) do
					if Object ~= SystemMenuButton and Object.Name == "SystemMenuButton" and Object:IsA("GuiObject") then
						table.insert(NativeSystemMenuButtonCache, Object)
					end
				end
			end)
		end
		for Index = #NativeSystemMenuButtonCache, 1, -1 do
			local Object = NativeSystemMenuButtonCache[Index]
			if not Object or not Object.Parent then
				table.remove(NativeSystemMenuButtonCache, Index)
			elseif Object ~= SystemMenuButton then
				pcall(function() Object.Visible = false end)
				pcall(function() Object.Active = false end)
				pcall(function() Object.Selectable = false end)
			end
		end
	end

AlignSystemMenuButton =
	function()
		if not SystemMenuButton then return end
		if Hub and Hub.NativeMuteTransaction then
			-- Do not let the 0.25s alignment loop put the custom transparent hitbox
			-- back over the native topbar button while we're opening it for a mic click.
			pcall(function() SystemMenuButton.Visible = false; SystemMenuButton.Active = false end)
			if SystemMenuHitbox then pcall(function() SystemMenuHitbox.Visible = false; SystemMenuHitbox.Active = false end) end
			HideNativeSystemMenuButtons()
			return
		end

		SystemMenuButton.Visible = true
		SystemMenuButton.Size = UDim2.fromOffset(30, 30)
		if SystemMenuHitbox then
			SystemMenuHitbox.Visible = true
			SystemMenuHitbox.Position = UDim2.fromOffset(SYSTEM_MENU_OFFSET_X - 4, SYSTEM_MENU_OFFSET_Y - 4)
			SystemMenuHitbox.Size = UDim2.fromOffset(40, 40)
		end

		if Hub.Visible then
			SystemMenuButton.Position =
				UDim2.fromOffset(
					SYSTEM_MENU_OFFSET_X,
					SYSTEM_MENU_OFFSET_Y
				)
			SystemMenuButton.Size = UDim2.fromOffset(30, 30)
			pcall(function()
				SystemMenuButton.ImageTransparency = 0
			end)
		else
			-- While closing, preserve the normal visible 30x30 button. After the
			-- tween completes, SetVisibility hides the visual button permanently.
			if SystemMenuButtonClosing then
				SystemMenuButton.Position =
					UDim2.fromOffset(
						SYSTEM_MENU_OFFSET_X,
						SYSTEM_MENU_OFFSET_Y
					)
				SystemMenuButton.Size = UDim2.fromOffset(30, 30)
				pcall(function()
					SystemMenuButton.ImageTransparency = 0
				end)
				SystemMenuButton.Visible = true
			else
				SystemMenuButton.Position =
					UDim2.fromOffset(
						SYSTEM_MENU_OFFSET_X,
						SYSTEM_MENU_OFFSET_Y
					)
				SystemMenuButton.Size = UDim2.fromOffset(30, 30)
				pcall(function()
					SystemMenuButton.ImageTransparency = 0
				end)
				SystemMenuButton.Visible = false
			end
		end

		-- Keep the real/native button hidden on every platform.
		HideNativeSystemMenuButtons()
		if PositionRecorderGui then
			PositionRecorderGui()
		end
	end

local ActivateCustomSystemMenu = function()
	if Hub and Hub.NativeMuteTransaction then return end
	Hub.SuppressNativeOpenUntil = tick() + 1.0
	HideNativeSettingsMenu()
	HideNativeSystemMenuButtons()
	SetVisibility(not Hub.Visible)
	AlignSystemMenuButton()
end

Connect(SystemMenuButton.MouseButton1Click, ActivateCustomSystemMenu)
Connect(SystemMenuHitbox.MouseButton1Click, ActivateCustomSystemMenu)
AlignSystemMenuButton()
Connect(CoreGui.ChildAdded, function()
	task.defer(function()
		SyncTopBarAppVisibility()
		HideNativeSystemMenuButtons()
		AlignSystemMenuButton()
		PositionRecorderGui()
	end)
end)

Connect(CoreGui.DescendantAdded, function(Descendant)
	if Descendant.Name == "TopBarApp" then
		task.defer(function()
			SyncTopBarAppVisibility()
		end)
	end
end)
Connect(CoreGui.DescendantAdded, function(Descendant)
	if Descendant.Name == "SystemMenuButton" and Descendant ~= SystemMenuButton then
		if NativeSystemMenuButtonCacheInitialized then
			local Found = false
			for _, Cached in ipairs(NativeSystemMenuButtonCache) do
				if Cached == Descendant then Found = true; break end
			end
			if not Found then table.insert(NativeSystemMenuButtonCache, Descendant) end
		end
		task.defer(function()
			pcall(function() Descendant.Visible = false end)
			pcall(function() Descendant.Active = false end)
			pcall(function() Descendant.Selectable = false end)
		end)
	end
end)
Spawn(function()
	while SystemMenuButton and SystemMenuButton.Parent do
		AlignSystemMenuButton()
		PositionRecorderGui()
		Wait(0.25)
	end
end)

-- ============================================================
-- ESCAPE ACTION
-- ============================================================

LastEscapeAction = 0

CloseInvitePage =
	function()
		local Previous = Hub.PreviousMenuPage or PlayersPage
		Hub.PreviousMenuPage = nil
		Hub.InInviteMenu = false
		Protect(function() GuiService.SelectedObject = nil end)
		Protect(function() GuiService.SelectedCoreObject = nil end)
		HideInviteSelection()
		if SearchBox then
			pcall(function() SearchBox:ReleaseFocus() end)
		end
		if SearchIcon then SearchIcon.Visible = true end
		if SearchPlaceholder then SearchPlaceholder.Visible = true end
		if InviteHeader then InviteHeader.Visible = false end
		if InviteList then InviteList.Visible = false end
		Hub.HubBar.Visible = true
		Hub.PageClipper.Visible = true
		Hub.BottomButtonFrame.Visible = not IsMobile
		Hub.PageView.ScrollBarThickness = IsMobile and 0 or 12
		if HomeButton then HomeButton.Visible = HomeButtonEnabled and not IsMobile end
		SwitchToPage(Previous, true, true)
		ResizeHub()
	end

EscapeAction =
	function(_, State)
		if State ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
		local CurrentTime = tick()
		if CurrentTime - LastEscapeAction < 0.18 then return Enum.ContextActionResult.Sink end
		LastEscapeAction = CurrentTime
		HideNativeSystemMenuButtons()

		if Hub.Visible and Hub.InInviteMenu then
			CloseInvitePage()
			return Enum.ContextActionResult.Sink
		end

		if Hub.Visible and Hub.InConfirmation and (Hub.CurrentPage == ResetPage or Hub.CurrentPage == LeavePage) then
			Hub.InConfirmation = false
			Hub.HubBar.Visible = true
			Hub.PageClipper.Visible = true
			Hub.BottomButtonFrame.Visible = not IsMobile
			if HomeButton then HomeButton.Visible = HomeButtonEnabled and not IsMobile end
			local Previous = Hub.MenuStack[#Hub.MenuStack] or PlayersPage
			SwitchToPage(Previous, true, true)
			Hub.PageView.ScrollBarThickness = IsMobile and 0 or 12
			ResizeHub()
			return Enum.ContextActionResult.Sink
		end

		local Target = not Hub.Visible
		-- ESC directly controls the custom panel and suppresses native callbacks
		-- that would otherwise reopen it while Roblox is processing the same key.
		Hub.NativeMenuTarget = nil
		Hub.SuppressNativeOpenUntil = CurrentTime + 1.5
		SetVisibility(Target, IsMobile)
		AlignSystemMenuButton()
		task.defer(function()
			-- SetVisibility owns the closing animation and hides Hub.Shield in its
			-- tween completion callback. Do not hide it here or the slide is cut off.
			HideNativeSystemMenuButtons()
		end)
		return Enum.ContextActionResult.Sink
	end

Protect(function()
	-- Give our custom ESC handler a higher input priority on desktop so the
	-- Roblox/native menu cannot swallow the Escape key before we see it.
	if not IsMobile then
		pcall(function() ContextActionService:UnbindAction("Settings2016Escape") end)
		pcall(function() ContextActionService:UnbindCoreAction("Settings2016Escape") end)
		local EscapeCallback = function(_, State)
			if State == Enum.UserInputState.Begin then
				return EscapeAction(nil, State)
			end
			return Enum.ContextActionResult.Sink
		end
		local CoreBound = pcall(function()
			ContextActionService:BindCoreActionAtPriority("Settings2016Escape", EscapeCallback, false, 20000, Enum.KeyCode.Escape)
		end)
		if not CoreBound then
			pcall(function()
				ContextActionService:BindActionAtPriority("Settings2016Escape", EscapeCallback, false, 20000, Enum.KeyCode.Escape)
			end)
		end
	end

	-- Do not overwrite Roblox's reserved RBXEscapeMainMenu action. The single
	-- high-priority Settings2016Escape action above owns ordinary ESC input.
end)

Connect(UserInputService.InputBegan, function(Input, Processed)
	-- Fallback for client builds where ContextActionService doesn't deliver Escape.
	-- EscapeAction's shared debounce prevents this and the high-priority binding
	-- from toggling the menu twice for the same keypress.
	if not IsMobile and Input.KeyCode == Enum.KeyCode.Escape then
		if Hub.Visible or not Processed then
			EscapeAction("InputBeganFallback", Enum.UserInputState.Begin)
		end
		return
	end
	local InviteEnter =
		Hub.Visible
		and Hub.InInviteMenu
		and not (SearchBox and SearchBox:IsFocused())
		and (Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.KeypadEnter)
	if Processed and not InviteEnter then return end
	-- Escape is handled only by the ContextActionService binding above. Handling
	-- it again here toggled the custom menu twice and sometimes exposed CoreGui.
	if not IsMobile and Input.KeyCode == Enum.KeyCode.F12 then
		if tick() >= IgnoreRecorderF12Until then
			ToggleCustomRecording()
		end
	elseif Hub.Visible and Input.KeyCode == Enum.KeyCode.R and not Hub.InInviteMenu and not Hub.InConfirmation then
		if GetResetButtonAllowed() then
			PushPage(ResetPage)
		else
			ApplyResetButtonAvailability()
		end
	elseif Hub.Visible and Input.KeyCode == Enum.KeyCode.L and not Hub.InInviteMenu and not Hub.InConfirmation then
		PushPage(LeavePage)
	elseif Hub.Visible and Hub.InInviteMenu and (Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.KeypadEnter) then
		local Friend = InviteSelectionFriends[InviteSelectedIndex]
		local InviteButton = InviteSelectionInviteButtons[InviteSelectedIndex]
		local InviteLabel = InviteSelectionInviteLabels[InviteSelectedIndex]
		if Friend and InviteFriend then
			InviteFriend(Friend, InviteButton, InviteLabel)
		end
	elseif Hub.Visible and (Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.KeypadEnter) then
		if Hub.CurrentPage == ResetPage then
			ResetCharacter()
		elseif Hub.CurrentPage == LeavePage then
			LeaveGame()
		end
	end
end)

-- ============================================================
-- NATIVE MENU HOOK
-- ============================================================

HookNativeMenu =
	function()
		local HookedRoots = setmetatable({}, {__mode = "k"})
		local NativeMenuOpenQueued = false
		local LastNativeMenuOpenHandled = 0
		local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
		local Shield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")

		local function NativeMenuOpened()
			if Hub and Hub.NativeMuteTransaction then return end
			local CurrentTime = tick()
			if CurrentTime < (Hub.SuppressNativeOpenUntil or 0) then return end
			if NativeMenuOpenQueued or (CurrentTime - LastNativeMenuOpenHandled) < 0.35 then return end
			NativeMenuOpenQueued = true
			LastNativeMenuOpenHandled = CurrentTime
			task.defer(function()
				NativeMenuOpenQueued = false
				if not Hub or tick() < (Hub.SuppressNativeOpenUntil or 0) then return end
				HideNativeSettingsMenu()
				HideNativeSystemMenuButtons()
				local Target = Hub.NativeMenuTarget
				Hub.NativeMenuTarget = nil
				if Target == nil then Target = true end
				if Hub.Visible ~= Target then SetVisibility(Target, IsMobile) end
			end)
		end

		local function HookRoot(Object)
			if not Object or HookedRoots[Object] then return end
			local IsGuiOk, IsGui = pcall(function() return Object:IsA("GuiObject") end)
			if not IsGuiOk or not IsGui then return end
			HookedRoots[Object] = true
			Connect(Object:GetPropertyChangedSignal("Visible"), function()
				if Object.Visible then NativeMenuOpened() end
			end)
			if Object.Visible then NativeMenuOpened() end
		end

		local function HookShield(NewShield)
			if not NewShield then return end
			Shield = NewShield
			CaptureNativeSettingsSuppressionSnapshot(Shield)
			HideNativeSettingsMenu()
			local SettingsShield = Shield:FindFirstChild("SettingsShield")
			local MenuContainer = SettingsShield and SettingsShield:FindFirstChild("MenuContainer")
			HookRoot(SettingsShield)
			HookRoot(MenuContainer)
		end

		HookShield(Shield)
		if RobloxGui then
			Connect(RobloxGui.DescendantAdded, function(Descendant)
				if Descendant.Name == "SettingsClippingShield" and Descendant.Parent == RobloxGui then
					HookShield(Descendant)
				elseif Shield then
					local IsInside = false
					pcall(function() IsInside = Descendant:IsDescendantOf(Shield) end)
					if IsInside then
						CaptureNativeSettingsSuppressionSnapshot(Shield, Descendant)
						SuppressNativeSettingsObject(Descendant)
						if Descendant.Name == "SettingsShield" or Descendant.Name == "MenuContainer" then HookRoot(Descendant) end
					end
				end
			end)
		end

		-- On some client builds MenuIsOpen changes before a Settings root becomes visible.
		pcall(function()
			Connect(GuiService:GetPropertyChangedSignal("MenuIsOpen"), function()
				local Open = false
				pcall(function() Open = GuiService.MenuIsOpen == true end)
				if Open then NativeMenuOpened() end
			end)
		end)

		local TopBarApp = CoreGui:FindFirstChild("TopBarApp")
		TopBarApp = TopBarApp and TopBarApp:FindFirstChild("TopBarApp")
		if TopBarApp then SyncTopBarAppVisibility() end
		local Holder = TopBarApp and TopBarApp:FindFirstChild("MenuIconHolder")
		local Trigger = Holder and Holder:FindFirstChild("TriggerPoint")
		local Hit = Trigger and Trigger:FindFirstChild("IconHitArea")
		if Hit and Hit:IsA("GuiButton") then
			Connect(Hit.MouseButton1Down, function()
				if Hub and Hub.NativeMuteTransaction then return end
				Hub.SuppressNativeOpenUntil = tick() + 1.0
				HideNativeSystemMenuButtons()
			end)
			Connect(Hit.MouseButton1Click, function()
				if Hub and Hub.NativeMuteTransaction then return end
				Hub.SuppressNativeOpenUntil = tick() + 1.0
				local Target = not Hub.Visible
				Hub.NativeMenuTarget = Target
				task.defer(function()
					SetVisibility(Target, IsMobile)
					if Hub.NativeMenuTarget == Target then Hub.NativeMenuTarget = nil end
				end)
			end)
		end
	end

if IsMobile then
	BuildMobileHelpPage()
	ApplyMobileReportLayout()
end

-- ============================================================
-- TEXT SIZE PRESERVATION
-- Intentionally do not apply a global mobile font scale. Only phone
-- confirmation layouts are sized explicitly by PositionMobileConfirmationButtons.
-- Keep this compatibility function for the existing ResizeHub call sites.
ApplyMobileTextSizing = function(Root)
	return
end

-- ============================================================
-- INITIAL STATE
-- ============================================================

SetTopBarAppEnabled(true)
SwitchToPage(GamePage, true, true)
ConfigureMobileActionButtons()
ResizeHub()
ConfigureMobileActionButtons()
ApplyMobileTextSizing(ScreenGui)
if VoiceOptionAvailable and SetVoiceChatPreference then
	SetVoiceChatPreference(true)
end
AlignSystemMenuButton()
if not IsMobile then
	FindRecorderControls()
	PositionRecorderGui()
end
HideNativeSystemMenuButtons()
Spawn(HookNativeMenu)

-- ============================================================
-- API
-- ============================================================

Api = {}

function Api:SetVisibility(Visible, NoAnimation, CustomPage)
	SetVisibility(Visible, NoAnimation, CustomPage)
	AlignSystemMenuButton()
	if HomeButton then
		HomeButton.Visible = Hub.Visible and HomeButtonEnabled and not IsMobile and not Hub.InInviteMenu and not Hub.InConfirmation
	end
	HideNativeSystemMenuButtons()
end

function Api:ToggleVisibility()
	SetVisibility(not Hub.Visible)
end

function Api:GetVisibility()
	return Hub.Visible
end

function Api:ReportPlayer(Player)
	if OpenReportPlayer then OpenReportPlayer(Player) end
end

Api.Instance = Hub
getgenv().Settings2016 = Api
return Api
