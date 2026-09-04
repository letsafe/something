local CoreGui = game:GetService("CoreGui")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local HttpRbxApiService = nil
pcall(function()
	HttpRbxApiService = game:GetService("HttpRbxApiService")
end)

local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local VirtualInputManager = nil

pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

local maxSteps = 10
local LocalPlayer = Players.LocalPlayer
local GameSettings = UserSettings().GameSettings
local RenderingSettings = settings().Rendering

local Spawn = task.spawn
local Wait = task.wait
local Insert = table.insert
local Clamp = math.clamp
local Floor = math.floor

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
	"rbxasset://textures/ui/Settings/Slider/BarLeft.png"

SLIDER_RIGHT_IMAGE =
	"rbxasset://textures/ui/Settings/Slider/BarRight.png"

PLAYER_LIST_OFFSET = 20
DESCRIPTION_PLACEHOLDER = "Short Description (Optional)"
REPORT_DESCRIPTION_FALLBACK = "Report Reason"
PAGE_TOP_PADDING = 12

local KEY_F12 = 0x7B
local KEY_PRINT_SCREEN = 0x2C

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

pcall(function()
	local Platform = UserInputService:GetPlatform()

	IsMobile =
		Platform == Enum.Platform.Android
		or Platform == Enum.Platform.IOS
end)

-- ============================================================
-- CONFIGURATION
-- ============================================================

HomeButtonEnabled = true
DisplayNameSupport = true
InviteFriends = true

TOTAL_HUB_WIDTH = 800

-- Home button is exactly the same height as the hub bar.
HOME_HEIGHT = 67

-- Slightly wider than its height.
HOME_WIDTH = 65

HUBBAR_HEIGHT = 60

-- Custom SystemMenuButton offsets.
SYSTEM_MENU_OFFSET_X = 16
SYSTEM_MENU_OFFSET_Y = 4

-- Recorder overlay position relative to SystemMenuButton.
-- X: horizontal offset from the calculated left-of-button position.
-- Y: vertical offset from the SystemMenuButton top.
RECORDER_OFFSET_X = 165
RECORDER_OFFSET_Y = -17

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

local SetMouseSensitivity = function(Value)

	Protect(function()
		UserSettings().GameSettings.MouseSensitivity =
			Value
	end)

	Protect(function()
		UserInputService.MouseDeltaSensitivity =
			Value
	end)

end

local SetMasterVolume = function(Value)

	Protect(function()
		UserSettings().GameSettings.MasterVolume =
			Value
	end)

	Protect(function()
		SoundService.Volume =
			Value
	end)

end

local GetSetting = function(
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

local SetSetting = function(
	Object,
	Property,
	Value
)
	Protect(function()
		Object[Property] = Value
	end)
end

-- ============================================================
-- GUI ROOT
-- ============================================================

local ScreenGui =
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

local VolumeChangeSound =
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

local PlayVolumeChangeSound =
	function()

		Protect(function()

			VolumeChangeSound:Stop()
			VolumeChangeSound:Play()

		end)

	end

-- ============================================================
-- TEXT / BUTTONS
-- ============================================================

local MakeText = function(
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
				24,

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

local MakeStyledButton = function(
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

local MakePage = function(Name)

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

local Hub = {
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

local ClippingShield =
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

Hub.HubBar =
	Create(
		"ImageLabel",
		{
			Name =
				"HubBar",

			Parent =
				Hub.Shield,

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

Hub.PageClipper =
	Create(
		"Frame",
		{
			Name =
				"PageViewClipper",

			Parent =
				Hub.Shield,

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
				6,

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
				Hub.Shield,

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

local CreateHomeButton = function()

	if
		not HomeButtonEnabled
		or HomeButton
	then
		return
	end

	HomeButton =
		Create(
			"ImageButton",
			{
				Name =
					"HomeButton",

				BackgroundTransparency =
					1,

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

				AutoButtonColor =
					false,

				Size =
					UDim2.new(
						0,
						HOME_WIDTH,
						0,
						HOME_HEIGHT
					),

				AnchorPoint =
					Vector2.new(
						0,
						0
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 4,
			}
		)

	Create(
		"ImageLabel",
		{
			Name =
				"Icon",

			Parent =
				HomeButton,

			BackgroundTransparency =
				1,

			Image =
				"rbxasset://textures/ui/Settings/MenuBarIcons/HomeTab.png",

			ScaleType =
				Enum.ScaleType.Fit,

			Size =
				UDim2.new(
					0,
					44,
					0,
					44
				),

			Position =
				UDim2.new(
					0.5,
					-22,
					0.5,
					-22
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 5,
		}
	)

	Connect(
		HomeButton.MouseEnter,
		function()
			HomeButton.Image =
				BUTTON_SELECTED_IMAGE
		end
	)

	Connect(
		HomeButton.MouseLeave,
		function()
			HomeButton.Image =
				BUTTON_IMAGE
		end
	)

	Connect(
		HomeButton.MouseButton1Click,
		function()

			if
				HomeButtonEnabled
				and LeavePage
				and Hub.Visible
			then

				PushPage(
					LeavePage
				)

			end

		end
	)

end

CreateHomeButton()

local PositionHomeButton = function()

	if
		not HomeButtonEnabled
		or not HomeButton
	then
		return
	end

	HomeButton.Parent =
		Hub.HubBar.Parent

	HomeButton.Size =
		UDim2.new(
			0,
			HOME_WIDTH,
			0,
			HOME_HEIGHT
		)

	HomeButton.AnchorPoint =
		Vector2.new(
			0,
			0
		)

	local HubPosition =
		Hub.HubBar.Position

	HomeButton.Position =
		UDim2.new(
			HubPosition.X.Scale,
			HubPosition.X.Offset - HOME_WIDTH,
			HubPosition.Y.Scale,
			HubPosition.Y.Offset - 3
		)

end

-- ============================================================
-- RESIZE
-- ============================================================

local ResizeHub

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

		if IsMobile then

			-- Mobile invite page is intentionally larger than the
			-- normal ESC menu. Keep only a tiny outer margin so the
			-- invite list gets almost the entire available screen.

			Width =
				math.max(
					280,
					Viewport.X - 8
				)

			local PageTop =
				36

			PageHeight =
				math.max(
					220,
					Viewport.Y - PageTop - 8
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
					0,
					PageTop
				)

		else

			local BufferSize =
				0.05 * Viewport.Y

			Width =
				TOTAL_HUB_WIDTH

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

		local Width =
			math.max(
				280,
				Viewport.X - 16
			)

		local ConfirmationHeight =
			IsMobile
			and 240
			or math.min(240, math.max(210, Viewport.Y - 40))

		Hub.HubBar.Visible = false
		Hub.BottomButtonFrame.Visible = false
		if HomeButton then HomeButton.Visible = false end

		Hub.PageClipper.Size = UDim2.new(0, Width, 0, ConfirmationHeight)
		Hub.PageClipper.Position =
			IsMobile
			and UDim2.new(0.5, -Width / 2, 0, math.max(70, math.floor((Viewport.Y - ConfirmationHeight) * 0.58)))
			or UDim2.new(0.5, -Width / 2, 0.5, -ConfirmationHeight / 2 - 18)

		Hub.PageView.Size = UDim2.new(1, 0, 0, ConfirmationHeight)
		Hub.PageView.CanvasPosition = Vector2.new(0, 0)
		Hub.PageView.CanvasSize = UDim2.new(0, 0, 0, ConfirmationHeight)
		Hub.PageView.ScrollBarThickness = 0

		if IsMobile then
			PositionMobileConfirmationButtons()
		else
			PositionDesktopConfirmationButtons()
		end

	elseif IsMobile then

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

		local Width =
			math.max(
				240,
				Viewport.X - 16
			)

		local GroupTop =
			32
			+ MOBILE_MENU_GAP

		local PageTop =
			GroupTop
			+ HUBBAR_HEIGHT
			+ MOBILE_LAYOUT_GAP

		local PageHeight =
			math.max(
				100,
				Viewport.Y
				- PageTop
				- MOBILE_LAYOUT_GAP
			)

		Height =
			PageHeight

		Hub.HubBar.Size =
			UDim2.new(
				0,
				Width,
				0,
				HUBBAR_HEIGHT
			)

		Hub.HubBar.Position =
			UDim2.new(
				0.5,
				-Width / 2,
				0,
				GroupTop
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
				0,
				PageTop
			)

		-- The fixed PC button frame is NEVER used on mobile.
		Hub.BottomButtonFrame.Visible = false

		-- The mobile action buttons belong to PlayersPage.Frame,
		-- so they scroll with the player list.
		if PlayersPage and PlayersPage.Frame then

			local ActionHeight = 72
			local ActionWidth = 1 / 3

			for Index, Button in ipairs({
				MobileActionButtons.Leave,
				MobileActionButtons.Reset,
				MobileActionButtons.Resume,
			}) do

				if Button then

					Button.Parent =
						PlayersPage.Frame

					Button.Size =
						UDim2.new(
							ActionWidth,
							-6,
							0,
							ActionHeight
						)

					Button.Position =
						UDim2.new(
							(Index - 1) * ActionWidth,
							3,
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
						Label.Size = UDim2.new(1, 0, 1, 0)
						Label.ZIndex = SETTINGS_BASE_ZINDEX + 5
					end

					for _, Child in ipairs(Button:GetChildren()) do
						if Child:IsA("ImageLabel") then
							Child.Visible = false
						end
					end

				end

			end

			local ActionHeight = 72
			local ActionListGap = MOBILE_LAYOUT_GAP
			local InviteOffset = InviteFriends and 80 or 0

			local InviteRow =
				PlayersPage.Frame:FindFirstChild(
					"InviteFriendsToJoin"
				)

			if InviteRow then

				-- Mobile only: move Invite Friends slightly closer
				-- to the Leave / Reset / Resume action row.
				InviteRow.Position =
					UDim2.new(
						0,
						0,
						0,
						ActionHeight
						+ MOBILE_LAYOUT_GAP
					)

			end

			local PlayerRows = {}

			for _, Child in ipairs(PlayersPage.Frame:GetChildren()) do

				if
					Child.Name:sub(1, 11) == "PlayerLabel"
				then

					Insert(PlayerRows, Child)

				end

			end

			table.sort(
				PlayerRows,
				function(A, B)
					return A.Name < B.Name
				end
			)

			-- Do not touch the PC RebuildPlayersPage positions.
			-- Mobile gets its own visual offset here.
			for Index, Row in ipairs(PlayerRows) do

				Row.Position =
					UDim2.new(
						0,
						0,
						0,
						ActionHeight
						+ ActionListGap
						+ InviteOffset
						+ ((Index - 1) * 80)
					)

			end

			local ContentHeight =
				ActionHeight
				+ ActionListGap
				+ InviteOffset
				+ (#PlayerRows * 80)
				+ PAGE_TOP_PADDING

			PlayersPage.Frame.Size =
				UDim2.new(
					1,
					0,
					0,
					math.max(
						ContentHeight,
						PageHeight
					)
				)

			Hub.PageView.CanvasSize =
				UDim2.new(
					0,
					0,
					0,
					math.max(
						ContentHeight,
						PageHeight
					)
				)

		else

			Hub.PageView.CanvasSize =
				UDim2.new(0, 0, 0, PageHeight)

		end

		if HomeButton then
			HomeButton.Visible = false
		end

	else

		-- ====================================================
		-- PC
		-- ====================================================

		-- Reset every viewport property changed by Invite/Confirmation.
		-- This is important when returning with Back without closing the menu.
		Hub.PageClipper.AnchorPoint = Vector2.new(0, 0)
		Hub.PageClipper.ClipsDescendants = true
		Hub.PageView.AnchorPoint = Vector2.new(0, 0)
		Hub.PageView.Position = UDim2.new(0, 0, 0, 0)
		Hub.PageView.Size = UDim2.new(1, 0, 1, 0)
		Hub.PageView.CanvasPosition = Vector2.new(0, 0)
		Hub.PageView.ScrollBarThickness = 6

		local BufferSize =
			0.05 * Viewport.Y

		local Width =
			TOTAL_HUB_WIDTH

		local ExtraSpace =
			(BufferSize * 2)
			+ (HUBBAR_HEIGHT * 2)

		Height =
			Clamp(
				Viewport.Y - ExtraSpace,
				150,
				600
			)

		Hub.HubBar.Size =
			UDim2.new(
				0,
				HomeButtonEnabled
					and (
						TOTAL_HUB_WIDTH
						- HOME_WIDTH
					)
					or TOTAL_HUB_WIDTH,
				0,
				HUBBAR_HEIGHT
			)

		Hub.HubBar.Position =
			UDim2.new(
				0.5,
				-(
					TOTAL_HUB_WIDTH / 2
				)
				+ (
					HomeButtonEnabled
					and HOME_WIDTH
					or 0
				),
				0.5,
				-Height / 2
				- HUBBAR_HEIGHT
			)

		Hub.PageClipper.Size =
			UDim2.new(
				0,
				Width,
				0,
				Height
			)

		Hub.PageClipper.Position =
			UDim2.new(
				0.5,
				-Width / 2,
				0.5,
				-Height / 2
			)

		Hub.BottomButtonFrame.Size =
			UDim2.new(
				0,
				Width,
				0,
				HUBBAR_HEIGHT
			)

		Hub.BottomButtonFrame.Position =
			UDim2.new(
				0.5,
				-Width / 2,
				0.5,
				Height / 2
			)

		Hub.PageView.CanvasPosition =
			Vector2.new(0, 0)

		Hub.PageView.ScrollBarThickness =
			6

		if Hub.CurrentPage and Hub.CurrentPage.Frame then
			Hub.CurrentPage.Frame.Position =
				UDim2.new(0, 0, 0, PAGE_TOP_PADDING)

			Hub.PageView.CanvasSize =
				UDim2.new(
					0,
					0,
					0,
					math.max(
						Hub.CurrentPage.Frame.Size.Y.Offset
						+ PAGE_TOP_PADDING,
						Height
					)
				)
		end

		if HomeButton then

			HomeButton.Visible =
				HomeButtonEnabled

			HomeButton.Size =
				UDim2.new(
					0,
					HOME_WIDTH,
					0,
					HOME_HEIGHT
				)

			if HomeButtonEnabled then
				PositionHomeButton()
			end

		end

	end

	if LayoutTabs then
		LayoutTabs()
	end

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

local MakeTab = function(
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
					Hub.HubBar,

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

				Size =
					UDim2.new(
						0,
						44,
						0,
						44
					),

				Position =
					UDim2.new(
						0,
						12,
						0.5,
						-22
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

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
					1.05,
					0,
					1,
					0
				),

			Position =
				UDim2.new(
					1.2,
					0,
					0,
					0
				),

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

	local VisiblePages =
		{}

	for _, Page in next,
		Hub.Pages
	do

		if Page.Tab then

			local Show =
				true

			if IsMobile then

				Show =
					(
						PlayersPage
						and Page == PlayersPage
					)

					or (
						GamePage
						and Page == GamePage
					)

					or (
						ReportPage
						and Page == ReportPage
					)

					or (
						HelpPage
						and Page == HelpPage
					)

					or (
						RecordPage
						and Page == RecordPage
					)

			end

			Page.Tab.Visible =
				Show

			if Show then
				Insert(
					VisiblePages,
					Page
				)
			end

		end

	end

	local Count =
		#VisiblePages

	if Count == 0 then
		return
	end

	for Index, Page in next,
		VisiblePages
	do

		local Tab =
			Page.Tab

		if IsMobile then

			Tab.Size =
				UDim2.new(
					1 / Count,
					0,
					1,
					0
				)

			Tab.Position =
				UDim2.new(
					(Index - 1) / Count,
					0,
					0,
					0
				)

		else

			local TabWidth =
				TOTAL_HUB_WIDTH / Count

			Tab.Size =
				UDim2.new(
					0,
					TabWidth,
					1,
					0
				)

			Tab.Position =
				UDim2.new(
					(Index - 1) / Count,
					0,
					0,
					0
				)

		end

	end

end

-- ============================================================
-- SWITCH PAGE
-- ============================================================

local GetPageIndex = function(Page)

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
				and Other.Icon:FindFirstChild(
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

	if
		OldFrame
		and OldFrame ~= Page.Frame
		and OldFrame.Parent == Hub.PageView
		and OldFrame.Visible
		and not NoAnimation
	then

		local PageWidth =
			math.max(
				Hub.PageClipper.AbsoluteSize.X,
				800
			)

		Page.Frame.Position =
			UDim2.new(
				0,
				Direction * PageWidth,
				0,
				PAGE_TOP_PADDING
			)

		TweenTo(
			Page.Frame,
			UDim2.new(
				0,
				0,
				0,
				PAGE_TOP_PADDING
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
				PAGE_TOP_PADDING
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
				PAGE_TOP_PADDING
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

	Hub.PageView.CanvasSize =
		UDim2.new(
			0,
			0,
			0,
			math.max(
				Page.Frame.Size.Y.Offset
				+ PAGE_TOP_PADDING,
				Hub.PageClipper.AbsoluteSize.Y
			)
		)

	Hub.CurrentPage =
		Page

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

end

local AddPage = function(
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

local MakeRow = function(
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
-- PLAYER LIST
-- ============================================================

local GetHeadshot = function(Player)

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

local MakePlayerRow = function(
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
					Player.DisplayName
					or Player.Name,

				Size =
					UDim2.new(
						1,
						-330,
						0,
						30
					),

				Position =
					UDim2.new(
						0,
						60,
						0,
						5
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 3,
			}
		)

		Create(
			"TextLabel",
			{
				Name =
					"UsernameLabel",

				Parent =
					Row,

				BackgroundTransparency =
					1,

				Font =
					Enum.Font.SourceSans,

				TextSize =
					17,

				TextColor3 =
					Color3.fromRGB(
						190,
						190,
						190
					),

				TextXAlignment =
					Enum.TextXAlignment.Left,

				Text =
					"@"
					.. Player.Name,

				Size =
					UDim2.new(
						1,
						-330,
						0,
						22
					),

				Position =
					UDim2.new(
						0,
						60,
						0,
						34
					),

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

	local BUTTON_WIDTH = 44
	local BUTTON_HEIGHT = 40
	local GAP = 8
	local FRIEND_WIDTH = 156

	local ViewButton
	local ReportButton
	local BlockButton
	local FriendButton
	local FriendLabel

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
					-BUTTON_WIDTH - GAP,
					0.5,
					-BUTTON_HEIGHT / 2
				)

		else

			ViewButton.Position =
				UDim2.new(
					1,
					-(
						FRIEND_WIDTH
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
						24,
						0,
						25
					),

				Position =
					UDim2.new(
						0.5,
						-12,
						0.5,
						-12.5
					),

				ScaleType =
					Enum.ScaleType.Fit,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 4,
			}
		)

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
					+ GAP
					+ BUTTON_WIDTH
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
					ReportButton,

				BackgroundTransparency =
					1,

				Image =
					"rbxasset://textures/ui/Settings/MenuBarIcons/ReportAbuseTab.png",

				Size =
					UDim2.new(
						0,
						24,
						0,
						24
					),

				Position =
					UDim2.new(
						0.5,
						-12,
						0.5,
						-12
					),

				ScaleType =
					Enum.ScaleType.Fit,

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 4,
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
						24,
						0,
						24
					),

				Position =
					UDim2.new(
						0.5,
						-12,
						0.5,
						-12
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

	return Row
end

-- ============================================================
-- POST MENU CALLBACK
-- ============================================================

local RunAfterMenuCloses = function(
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

local MakeSelector = function(
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

			Size =
				UDim2.new(
					0,
					18,
					0,
					30
				),

			Position =
				UDim2.new(
					1,
					-24,
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
				"rbxasset://textures/ui/Settings/Slider/Right.png",

			Size =
				UDim2.new(
					0,
					18,
					0,
					30
				),

			Position =
				UDim2.new(
					0,
					6,
					0.5,
					-15
				),

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 4,
		}
	)

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

local MakeSlider = function(
	Page,
	Name,
	Steps,
	Index,
	Changed,
	MinStep
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

			Size =
				UDim2.new(
					0,
					18,
					0,
					30
				),

			Position =
				UDim2.new(
					1,
					-24,
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
				"rbxasset://textures/ui/Settings/Slider/Right.png",

			Size =
				UDim2.new(
					0,
					18,
					0,
					30
				),

			Position =
				UDim2.new(
					0,
					6,
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
							SLIDER_LEFT_IMAGE

					else

						Segment.Image =
							SLIDER_RIGHT_IMAGE

					end

				end

				Segment.ImageTransparency =
					0.36

				Segment.BackgroundTransparency =
					1

			else

				if Immediate then

					Segment.BackgroundColor3 =
						Color

				else

					ColorTo(
						Segment,
						Color
					)

				end

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

		Refresh()

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

local MakeDropDown = function(
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
		"Players"
	)

AddPage(
	PlayersPage,
	"Players",
	"rbxasset://textures/ui/Settings/MenuBarIcons/PlayersTabIcon.png",
	150
)

if PlayersPage.Icon then

	PlayersPage.Icon.Size =
		UDim2.new(
			0,
			44,
			0,
			37
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

local MakeInviteFriendsRow = function(
	Page
)

	local Row =
		Create(
			"ImageButton",
			{
				Name =
					"InviteFriendsToJoin",

				Parent =
					Page.Frame,

				BackgroundTransparency =
					1,

				BorderSizePixel =
					0,

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
						60
					),

				Position =
					UDim2.new(
						0,
						0,
						0,
						PLAYER_LIST_OFFSET
					),

				ZIndex =
					SETTINGS_BASE_ZINDEX
					+ 2,
			}
		)

	local Icon =
		Create(
			"ImageLabel",
			{
				Name = "Icon",
				Parent = Row,
				BackgroundTransparency = 1,
				Image = "rbxassetid://80022950003290",
				Size = UDim2.fromOffset(24, 24),
				Position = UDim2.new(0, 18, 0.5, -12),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
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

			TextColor3 =
				Color3.new(
					1,
					1,
					1
				),

			TextXAlignment =
				Enum.TextXAlignment.Left,

			Text =
				"Invite friends to join",

			Size =
				UDim2.new(
					1,
					-80,
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

	Connect(
		Row.MouseButton1Click,
		function()

			if OpenInviteFriends then
				OpenInviteFriends()
			end

		end
	)

	return Row
end

local RebuildPlayersPage = function()

	for _, Child in next,
		PlayersPage.Frame:GetChildren()
	do

		if
			Child.Name:sub(
				1,
				11
			)
			== "PlayerLabel"

			or Child.Name
			== "InviteFriendsToJoin"
		then
			Child:Destroy()
		end

	end

	local SortedPlayers =
		Players:GetPlayers()

	-- Mobile-only offset. PC keeps the original player-row positions.
	local MobileActionOffset =
		IsMobile
		and (72 + MOBILE_LAYOUT_GAP)
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

	if InviteFriends then

		local InviteRow =
			MakeInviteFriendsRow(
				PlayersPage
			)

		InviteRow.Position =
			UDim2.new(
				0,
				0,
				0,
				IsMobile
				and (
					MobileActionOffset
					+ PLAYER_LIST_OFFSET
				)
				or 0
			)

		InviteOffset =
			80

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
						* 80
					)
				)

		end

	end

	PlayersPage.Frame.Size =
		UDim2.new(
			1,
			0,
			0,
			MobileActionOffset
			+ InviteOffset
			+ (
				Count * 80
			)
			- 5
		)

end

RebuildPlayersPage()

Connect(
	Players.PlayerAdded,
	function()

		RebuildPlayersPage()

	end
)

Connect(
	Players.PlayerRemoving,
	function()

		task.defer(
			RebuildPlayersPage
		)

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

local SearchBox
local InviteList
local SearchIcon
local SearchPlaceholder

InvitePage =
	MakePage(
		"InviteFriends"
	)

AddPage(
	InvitePage
)

local InviteHeader =
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

local InviteBackButton,
	InviteBackLabel =
	MakeStyledButton(
		"InviteBackButton",
		"Back",
		UDim2.new(
			0,
			90,
			0,
			44
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
				IsMobile and 0 or 6


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
		8
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

local SearchFrame =
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

		SearchIcon.Visible =
			SearchBox.Text == ""

		SearchPlaceholder.Visible =
			SearchBox.Text == ""

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

		if
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
				6,

			ZIndex =
				SETTINGS_BASE_ZINDEX
				+ 5,
		}
	)

InviteHeader.Visible =
	false

InviteList.Visible =
	false

local InviteFriendsCache =
	{}

-- Persist invite state in getgenv so rebuilding the invite list,
-- leaving/reopening the ESC menu, or rerunning this script does not
-- forget which friends have already received an accepted invite.
local InviteState =
	getgenv().Settings2016InviteState

if type(InviteState) ~= "table" then
	InviteState = {}
	getgenv().Settings2016InviteState = InviteState
end

local CurrentInviteJobId = tostring(game.JobId or "")

if InviteState.JobId ~= CurrentInviteJobId then
	InviteState = {
		JobId = CurrentInviteJobId,
		InvitedFriendIds = {},
	}
	getgenv().Settings2016InviteState = InviteState
end

local InvitedFriendIds =
	InviteState.InvitedFriendIds

if type(InvitedFriendIds) ~= "table" then
	InvitedFriendIds = {}
	InviteState.InvitedFriendIds = InvitedFriendIds
end

local PendingInviteFriendIds =
	{}

local InviteRows =
	{}

local INVITE_ROW_HEIGHT =
	80

local INVITE_ROW_GAP =
	6

local INVITE_BUTTON_WIDTH =
	100

local INVITE_BUTTON_HEIGHT =
	42

local INVITED_COLOR =
	Color3.fromRGB(
		190,
		190,
		190
	)

-- Legacy Roblox-style presence palette:
-- Online = cyan       #00A2FF
-- In Experience = green #00FF00
-- In Studio = orange  #FFB000
local ONLINE_COLOR =
	Color3.fromRGB(
		0,
		162,
		255
	)

local IN_EXPERIENCE_COLOR = Color3.fromRGB(2, 183, 90)

local IN_STUDIO_COLOR = Color3.fromRGB(246, 136, 2)

local OFFLINE_COLOR = Color3.fromRGB(128, 128, 128)

-- ============================================================
-- FRIEND STATUS
-- ============================================================

local GetInviteStatus =
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

local FetchFriends =
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
			function(
				A,
				B
			)

				local AName =
					DisplayNameSupport
					and (
						A.DisplayName
						or A.Username
					)
					or A.Username

				local BName =
					DisplayNameSupport
					and (
						B.DisplayName
						or B.Username
					)
					or B.Username

				return
					string.lower(
						AName
					)
					<
					string.lower(
						BName
					)

			end
		)

		return Result

	end

local FriendMatchesSearch =
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

local ActiveInviteOptions =
		nil

local InviteFriend =
	function(
		Friend,
		Button,
		Label
	)

		if
			not Friend
			or not Friend.Id
			or Friend.Invited
		then
			return
		end

		local FriendId =
			tonumber(Friend.Id)

		if not FriendId then
			return
		end

		if ActiveInviteOptions then
			pcall(function()
				ActiveInviteOptions:Destroy()
			end)
			ActiveInviteOptions = nil
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

			Success =
				Protect(function()
					SocialService:PromptGameInvite(
						LocalPlayer,
						Options
					)
				end)

		end

		if not Success then

			if ActiveInviteOptions == Options then
				ActiveInviteOptions = nil
			end

			pcall(function()
				if Options then
					Options:Destroy()
				end
			end)

			if Button then
				Button.ImageTransparency = 0
				Button.BackgroundTransparency = 1
				Button.Active = true
				Button.Selectable = true
			end

			if Label then
				Label.Text = "Invite"
				Label.TextColor3 = Color3.new(1, 1, 1)
			end

			return
		end

		-- ========================================================
		-- IMMEDIATELY PERSIST INVITED STATE
		-- ========================================================
		-- Once Roblox accepts the prompt call, this session treats the
		-- selected friend as invited. Do not depend on recipient data
		-- from GameInvitePromptClosed, because some clients return nil
		-- or an empty recipient list even after the targeted prompt was used.

		local FriendKey =
			tostring(FriendId)

		InvitedFriendIds[FriendKey] = true
		InviteState.InvitedFriendIds = InvitedFriendIds
		Friend.Invited = true

		PendingInviteFriendIds[FriendKey] = nil

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

		if ActiveInviteOptions == Options then
			ActiveInviteOptions = nil
		end

		pcall(function()
			if Options then
				Options:Destroy()
			end
		end)

		if RebuildInviteList then
			RebuildInviteList()
		end
	end

-- ============================================================
-- BUILD INVITE ROW
-- ============================================================

local BuildInviteRow =
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
							60
						),

					Position =
						UDim2.new(
							0,
							0,
							0,
							PLAYER_LIST_OFFSET
							+ ((Index - 1) * 80)
						),

					ZIndex =
						SETTINGS_BASE_ZINDEX + 2,
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

		local AvatarBackground =
			Create(
				"Frame",
				{
					Name = "AvatarBackground",
					Parent = Row,
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 0,
					BorderSizePixel = 0,
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
					Size = UDim2.new(0, 36, 0, 36),
					Position = UDim2.new(0, 12, 0.5, -18),
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

			Create(
				"TextLabel",
				{
					Name = "InvitedLabel",
					Parent = Row,
					BackgroundTransparency = 1,
					Font = Enum.Font.SourceSans,
					TextSize = 24,
					TextColor3 = INVITED_COLOR,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					Text = "Invited...",
					Size = UDim2.new(0, INVITE_BUTTON_WIDTH, 0, INVITE_BUTTON_HEIGHT),
					Position = UDim2.new(1, -(INVITE_BUTTON_WIDTH + 12), 0.5, -(INVITE_BUTTON_HEIGHT / 2)),
					ZIndex = SETTINGS_BASE_ZINDEX + 3,
				}
			)

		else

			local InviteButton, InviteLabel =
				MakeStyledButton(
					"InviteButton",
					"Invite",
					UDim2.new(0, INVITE_BUTTON_WIDTH, 0, INVITE_BUTTON_HEIGHT)
				)

			InviteButton.Active = true
			InviteButton.Selectable = true

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

RebuildInviteList =
	function()

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

		InviteList.CanvasSize =
			UDim2.new(
				0,
				0,
				0,
				math.max(
					0,
					Count
					* (
						INVITE_ROW_HEIGHT
						+ INVITE_ROW_GAP
					)
				)
			)

	end

local RefreshInviteFriends =
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

		SearchBox.Text =
			""

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

		RefreshInviteFriends()

		ResizeHub()

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

local SavedCoreGuiState =
	{}

local CoreGuiStateCaptured =
	false

local TOPBAR_CORE_GUI_TYPES = {
	"Chat",
	"PlayerList",
	"Backpack",
	"Health",
	"EmotesMenu",
	"SelfView",
	"Captures",
}

local SetTopbarCoreGuiEnabled =
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

local CameraDefaultString =
	IsTouchClient
	and "Default (Follow)"
	or "Default (Classic)"

local MovementDefaultString =
	IsTouchClient
	and "Default (Thumbstick)"
	or "Default (Keyboard)"

local ClickToMoveString =
	IsTouchClient
	and "Tap to Move"
	or "Click to Move"

local MakeSectionHeader =
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

local MakeButtonRow =
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

local MakeBooleanSelector =
	function(
		Page,
		Name,
		Object,
		Property,
		OnFirst,
		OffSecond
	)

		local Current =
			GetSetting(
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

				SetSetting(
					Object,
					Property,
					Index == 1
				)

			end
		)

	end

MakeSectionHeader(
	GamePage,
	"View & Controls"
)

local MakeOverrideText =
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

local SetChangerVisible =
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

local ShiftLockMode, ShiftLockOverride = nil, nil

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

local CameraItems =
	(
		IsTouchClient
		and Enum.TouchCameraMovementMode
		or Enum.ComputerCameraMovementMode
	):GetEnumItems()

local CameraNames, CameraMap, CameraStart = {}, {}, 1

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

local CameraMode =
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

local CameraOverride = MakeOverrideText(CameraMode.RowFrame)

local MoveItems =
	(
		IsTouchClient
		and Enum.TouchMovementMode
		or Enum.ComputerMovementMode
	):GetEnumItems()

local MoveNames, MoveMap, MoveStart = {}, {}, 1

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

local MovementMode =
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

local MovementOverride = MakeOverrideText(MovementMode.RowFrame)

local UpdateDevChoiceSettings =
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

local MouseStart =
	Clamp(
		Floor(
			(
				2 / 3
			)
			* (
				math.sqrt(
					(
						75 * (GameSettings.MouseSensitivity or 1)
					)
					- 11
				)
				- 2
			)
		),
		1,
		10
	)

MakeSlider(
	GamePage,
	"Mouse Sensitivity",
	10,
	MouseStart,
	function(Value)
		Value = Clamp(Value, 1, 10)
		SetMouseSensitivity(
			(0.03 * (Value ^ 2))
			+ (0.08 * Value)
			+ 0.2
		)
	end,
	1
)

MakeBooleanSelector(GamePage, "UI Navigation Toggle", GameSettings, "UiNavigationKeyBindEnabled")
MakeBooleanSelector(GamePage, "People's Names", GameSettings, "PlayerNamesEnabled", "Show", "Hide")
MakeBooleanSelector(GamePage, "My Badges", GameSettings, "BadgeVisible", "Show", "Hide")

MakeSectionHeader(GamePage, "Audio")

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

MakeBooleanSelector(GamePage, "Automatic Chat Translation", GameSettings, "ChatTranslationEnabled")
MakeBooleanSelector(GamePage, "Chat Translation Language", GameSettings, "ChatTranslationToggleEnabled")
MakeBooleanSelector(GamePage, "View Untranslated Messages", GameSettings, "ChatTranslationFTUXShown")

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

MakeBooleanSelector(GamePage, "Performance Stats", GameSettings, "PerformanceStatsVisible")

MakeButtonRow(
	GamePage,
	"MicroProfiler",
	"Open",
	function()
		RunAfterMenuCloses(function()
			SetSetting(GameSettings, "OnScreenProfilerEnabled", true)
			if keypress and keyrelease then
				keypress(0x75)
				keyrelease(0x75)
			end
		end)
	end
)

local QualityLevels = {}
local SavedQualityLevels = {}

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

local GetAvailableSavedQualityLevels =
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

local GetSavedQualityForValue =
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

local GetGraphicsSliderStart =
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

local GraphicsSlider
local GraphicsMode

Protect(function()
	RenderingSettings.EnableFRM = true
end)

local GetEnumItemByValue =
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

local SetGraphicsQuality =
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

local SetGraphicsToAuto =
	function()
		if GraphicsSlider then
			GraphicsSlider:SetInteractable(false)
		end
		SetGraphicsQuality(0, true)
	end

local SetGraphicsToManual =
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

GraphicsMode =
	MakeSelector(
		GamePage,
		"Graphics Mode",
		{"Automatic", "Manual"},
		1,
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

	local Holder =
		GraphicsSlider.SliderFrame

	local Segments = {}
	local LeftButton = nil
	local RightButton = nil
	local Capture = nil

	for _, Child in ipairs(Holder:GetChildren()) do

		if Child:IsA("ImageButton") then

			local HasLeftImage = false
			local HasRightImage = false

			for _, SubChild in ipairs(Child:GetChildren()) do

				if SubChild:IsA("ImageLabel") then

					if SubChild.Image == "rbxasset://textures/ui/Settings/Slider/Left.png" then
						HasLeftImage = true
					elseif SubChild.Image == "rbxasset://textures/ui/Settings/Slider/Right.png" then
						HasRightImage = true
					end

				end

			end

			if HasLeftImage then
				LeftButton = Child
			elseif HasRightImage then
				RightButton = Child
			else
				Insert(Segments, Child)
			end

		elseif Child:IsA("TextButton") then

			Capture = Child

		end

	end

	table.sort(
		Segments,
		function(A, B)
			return A.Position.X.Offset < B.Position.X.Offset
		end
	)

	local SliderStartX = 60
	local SliderEndX = 411
	local SliderRange = SliderEndX - SliderStartX
	local StepSpacing = SliderRange / 20
	local BarWidth = math.max(12, math.floor(StepSpacing - 2))

	for Index, Segment in ipairs(Segments) do

		if Index <= 21 then

			local X =
				SliderStartX
				+ ((Index - 1) * StepSpacing)

			Segment.Size =
				UDim2.new(
					0,
					BarWidth,
					0,
					25
				)

			Segment.Position =
				UDim2.new(
					0,
					math.floor(X + 0.5),
					0.5,
					-12
				)

		end

	end

	if LeftButton then

		LeftButton.AnchorPoint =
			Vector2.new(1, 0.5)

		LeftButton.Position =
			UDim2.new(
				0,
				SliderStartX - 8,
				0.5,
				0
			)

	end

	if RightButton then

		RightButton.AnchorPoint =
			Vector2.new(0, 0.5)

		RightButton.Position =
			UDim2.new(
				0,
				SliderEndX + BarWidth + 8,
				0.5,
				0
			)

	end

	if Capture then

		Capture.Position =
			UDim2.new(
				0,
				SliderStartX - 8,
				0,
				0
			)

		Capture.Size =
			UDim2.new(
				0,
				SliderRange + BarWidth + 16,
				1,
				0
			)

		Capture.ZIndex =
			SETTINGS_BASE_ZINDEX + 5

	end

end

if
	GameSettings.SavedQualityLevel == Enum.SavedQualitySetting.Automatic
	or RenderingSettings.QualityLevel == Enum.QualityLevel.Automatic
	or GameSettings.SavedQualityLevel == 0
	or RenderingSettings.QualityLevel == 0
then
	SetGraphicsToAuto()
else
	SetGraphicsToManual(GetGraphicsSliderStart())
end

MakeSelector(
	GamePage,
	"Haptics",
	{"On", "Off"},
	(
		(
			GetSetting(GameSettings, "HapticStrength", 1) or 0
		)
		> 0
		and 1
	)
	or 2,
	function(Index)
		SetSetting(GameSettings, "HapticStrength", Index == 1 and 1 or 0)
	end
)

MakeBooleanSelector(GamePage, "Reduce Motion", GameSettings, "ReducedMotion")

local FpsValues = {"60", "120", "144", "160", "165", "180", "200", "240"}
local FpsStart = 1
local CurrentFps = tostring(GetSetting(GameSettings, "FramerateCap", 60))

for Index, Value in next, FpsValues do
	if Value == CurrentFps then
		FpsStart = Index
	end
end

MakeSelector(
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

MakeBooleanSelector(GamePage, "VR", GameSettings, "VREnabled")

-- ============================================================
-- REPORT PAGE
-- ============================================================

ReportPage = MakePage("ReportAbuse")
AddPage(ReportPage, "Report", "rbxasset://textures/ui/Settings/MenuBarIcons/ReportAbuseTab.png", 150)

local TypeOfAbuse
local WhichPlayer
local NameToPlayer = {}
local PlayerNames = {}
local Submit
local SubmitLabel
local Description
local ReportMode

local SetSubmitActive =
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

local GetReportDescription =
	function()
		local Text = Description and Description.Text or ""
		if Text == "" or Text == DESCRIPTION_PLACEHOLDER then
			return REPORT_DESCRIPTION_FALLBACK
		end
		return Text
	end

local CanSubmitReport =
	function(Mode)
		if not TypeOfAbuse or not Mode then return false end
		if not TypeOfAbuse:GetSelectedIndex() then return false end
		if Mode:GetSelectedIndex() == 2 and (not WhichPlayer or not WhichPlayer:GetSelectedValue()) then
			return false
		end
		return true
	end

local RefreshSubmitState = function(Mode)
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

local RefreshReportPlayers =
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

local DescriptionRow = MakeRow(ReportPage, "")
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

local CreateHelpGroup =
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

local IsOSX = UserInputService:GetPlatform() == Enum.Platform.OSX

local CharMoveFrame = CreateHelpGroup("Character Movement", {
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

local MenuFrame = CreateHelpGroup("Menu Items", {
	{"ROBLOX Menu", "ESC"},
	{"Backpack", "~"},
	{"Playerlist", "TAB"},
	{"Chat", "/"},
}, UDim2.new(1 / 3, 4, 0, CharMoveFrame.Size.Y.Offset + 50))

HelpPage.Frame.Size = UDim2.new(1, 0, 0, MenuFrame.Position.Y.Offset + MenuFrame.Size.Y.Offset)

-- ============================================================
-- RBXM SUITE CUSTOM RECORDER OVERLAY (PC ONLY)
-- ============================================================

local RecorderGui = getgenv().Settings2016RecorderGui
local RecorderActualButton = nil
local RecorderTimeLabel = nil
local RecorderRunning = false
local RecorderStartedAt = 0
local RecorderThread = nil
local IgnoreRecorderF12Until = 0
local RecorderPageButton = nil
local RecorderPageButtonLabel = nil
local PositionRecorderGui

local UpdateRecorderPageButton =
	function()
		if not RecorderPageButton or not RecorderPageButtonLabel then
			return
		end
		RecorderPageButtonLabel.Text =
			RecorderRunning
			and "Stop Recording"
			or "Record Video"
	end

local LoadRecorderGui =
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

local FindRecorderControls =
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

		-- When the custom ESC menu is closed, the 40x40
		-- SystemMenuButton itself moves 4 px left/up.
		-- Compensate the recorder by 4 px right/down so
		-- the recorder stays in the same screen position.
		if not Hub.Visible then
			TargetX = TargetX + 4
			TargetY = TargetY + 4
		end

		Button.Position =
			UDim2.fromOffset(
				TargetX - ParentPosition.X,
				TargetY - ParentPosition.Y
			)

	end

local ToggleNativeRecording =
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

local FormatRecorderTime =
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

local StopCustomRecording =
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

local StartCustomRecording =
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
		RecorderGui.Enabled = true
		RecorderTimeLabel.Text = "0:00"
		UpdateRecorderPageButton()

		RecorderThread =
			Spawn(function()

				while
					RecorderRunning
					and RecorderGui
					and RecorderGui.Parent
				do

					if RecorderTimeLabel then
						RecorderTimeLabel.Text =
							FormatRecorderTime(
								tick()
								- RecorderStartedAt
							)
					end

					Wait(1)

				end

			end)

		return true

	end

local ToggleCustomRecording =
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

local ResetMessage = MakeText(
	ResetPage.Frame,
	"Are you sure you want to reset your character?",
	UDim2.new(1, -20, 0, 100),
	UDim2.new(0, 10, 0, 20)
)
ResetMessage.TextSize = 36

local LeaveMessage

local ResetCharacter =
	function()
		local Character = LocalPlayer.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			Humanoid.Health = 0
		end
		SetVisibility(false, true)
	end

local LeaveGame =
	function()
		local Success = Protect(function() LocalPlayer:Kick() end)
		if not Success then
			Protect(function() game:Shutdown() end)
		end
	end

local ResetButton, ResetButtonLabel =
	MakeStyledButton(
		"ResetCharacter",
		"Reset",
		UDim2.new(0, 200, 0, 50),
		ResetCharacter,
		true
	)
ResetButton.Parent = ResetPage.Frame

local DontResetButton =
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
ResetPage.Frame.Size = UDim2.new(1, 0, 0, 240)

LeavePage = MakePage("LeaveGame")
AddPage(LeavePage)
LeaveMessage = MakeText(
	LeavePage.Frame,
	"Are you sure you want to leave the game?",
	UDim2.new(1, -20, 0, 100),
	UDim2.new(0, 10, 0, 20)
)
LeaveMessage.TextSize = 36

local LeaveButton = MakeStyledButton("LeaveGame", "Leave", UDim2.new(0, 200, 0, 50), LeaveGame, true)
LeaveButton.Parent = LeavePage.Frame

local DontLeaveButton = MakeStyledButton(
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
LeavePage.Frame.Size = UDim2.new(1, 0, 0, 240)

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

			LeftButton.Size = UDim2.new(0, 200, 0, 50)
			RightButton.Size = UDim2.new(0, 200, 0, 50)
			LeftButton.Visible = true
			RightButton.Visible = true
			LeftButton.Active = true
			RightButton.Active = true
			LeftButton.Selectable = true
			RightButton.Selectable = true
			LeftButton.ZIndex = SETTINGS_BASE_ZINDEX + 3
			RightButton.ZIndex = SETTINGS_BASE_ZINDEX + 3

			LeftButton.Position =
				UDim2.new(0.5, -206, 0, 132)

			RightButton.Position =
				UDim2.new(0.5, 6, 0, 132)

		end

	end

local PositionMobileConfirmationButtons =
	function()
		if not IsMobile then return end
		local Viewport = ScreenGui.AbsoluteSize
		if Viewport.X <= 0 or Viewport.Y <= 0 then
			local Camera = workspace.CurrentCamera
			Viewport = (Camera and Camera.ViewportSize) or Vector2.new(1280, 720)
		end
		local AvailableWidth = math.max(280, Viewport.X - 20)
		local ButtonWidth = Clamp((AvailableWidth - 12) / 2, 130, 200)
		for _, Info in next, {
			{ResetPage.Frame, ResetButton, DontResetButton},
			{LeavePage.Frame, LeaveButton, DontLeaveButton},
		} do
			local Frame, LeftButton, RightButton = Info[1], Info[2], Info[3]
			local Message = Frame:FindFirstChildWhichIsA("TextLabel")
			if Message then
				Message.Size = UDim2.new(1, -20, 0, 88)
				Message.Position = UDim2.new(0, 10, 0, 12)
			end
			LeftButton.Size = UDim2.new(0, ButtonWidth, 0, 50)
			RightButton.Size = UDim2.new(0, ButtonWidth, 0, 50)
			LeftButton.Position = UDim2.new(0.5, -(ButtonWidth + 6), 0, 158)
			RightButton.Position = UDim2.new(0.5, 6, 0, 158)
		end
	end

-- ============================================================
-- ALERT
-- ============================================================

local ActiveAlert

local ShowAlert =
	function(AlertMessage, OkButtonText, Cleanup)
		if ActiveAlert then
			ActiveAlert:Destroy()
			ActiveAlert = nil
		end

		Hub.HubBar.Visible = false
		Hub.PageClipper.Visible = false
		Hub.BottomButtonFrame.Visible = false

		local Alert = Create(
			"ImageLabel",
			{
				Name = "AlertViewBacking",
				Parent = Hub.Shield,
				Image = BUTTON_IMAGE,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(8, 6, 46, 44),
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 400, 0, 350),
				Position = UDim2.new(0.5, -200, 0.5, -175),
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
			TextSize = 36,
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
			UDim2.new(0, 200, 0, 50),
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
		Button.Position = UDim2.new(0.5, -100, 0.65, 0)
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
			PositionMobileConfirmationButtons()
			ResizeHub()
		end
	end

-- ============================================================
-- MOBILE BOTTOM BUTTONS
-- ============================================================

local MakeBottomButton =
	function(Name, Text, Icon, Position, Clicked, Size)
		local Button = MakeStyledButton(Name .. "Button", Text, Size or UDim2.new(0, 260, 0, 70), Clicked)
		Button.Parent = Hub.BottomButtonFrame
		Button.Position = Position
		Create("ImageLabel", {
			Parent = Button,
			BackgroundTransparency = 1,
			Image = Icon,
			Size = UDim2.new(0, 48, 0, 48),
			Position = UDim2.new(0, 10, 0, 8),
			ZIndex = SETTINGS_BASE_ZINDEX + 4,
		})
		local Label = Button:FindFirstChild(Name .. "ButtonTextLabel")
		if Label then
			Label.Position = UDim2.new(0, 10, 0, -4)
			Label.Size = UDim2.new(1, 0, 1, 0)
		end
		return Button
	end

MobileActionButtons = {}
local BottomButtonSize = UDim2.new(0, 260, 0, 72)

MobileActionButtons.Reset = MakeBottomButton(
	"ResetCharacter",
	"    Reset Character",
	"rbxasset://textures/ui/Settings/Help/ResetIcon.png",
	UDim2.new(0, 4, 0.5, -32),
	function() PushPage(ResetPage) end,
	BottomButtonSize
)

MobileActionButtons.Leave = MakeBottomButton(
	"LeaveGame",
	"Leave Game",
	"rbxasset://textures/ui/Settings/Help/LeaveIcon.png",
	UDim2.new(0, 270, 0.5, -32),
	function() PushPage(LeavePage) end,
	BottomButtonSize
)

MobileActionButtons.Resume = MakeBottomButton(
	"Resume",
	"Resume Game",
	"rbxasset://textures/ui/Settings/Help/EscapeIcon.png",
	UDim2.new(0, 540, 0.5, -32),
	function() SetVisibility(false) end,
	BottomButtonSize
)

local ConfigureMobileActionButtons =
	function()
		local Ordered = {
			{
				Button = MobileActionButtons.Leave,
				Text = "Leave Game",
				PCPosition = UDim2.new(0, 270, 0.5, -32),
				MobileIndex = 1,
			},
			{
				Button = MobileActionButtons.Reset,
				Text = "Reset Character",
				PCPosition = UDim2.new(0, 4, 0.5, -32),
				MobileIndex = 2,
			},
			{
				Button = MobileActionButtons.Resume,
				Text = "Resume Game",
				PCPosition = UDim2.new(0, 540, 0.5, -32),
				MobileIndex = 3,
			},
		}

		for _, Entry in ipairs(Ordered) do

			local Button = Entry.Button

			if Button then

				if IsMobile and PlayersPage and PlayersPage.Frame then

					Button.Parent =
						PlayersPage.Frame

					Button.Size =
						UDim2.new(
							1 / 3,
							-6,
							0,
							72
						)

					Button.Position =
						UDim2.new(
							(Entry.MobileIndex - 1) / 3,
							3,
							0,
							0
						)

					Button.Visible =
						true

					-- Mobile uses text-only action buttons.
					for _, Child in ipairs(Button:GetChildren()) do
						if Child:IsA("ImageLabel") then
							Child.Visible = false
						end
					end

				else

					Button.Parent =
						Hub.BottomButtonFrame

					Button.Size =
						UDim2.new(
							0,
							260,
							0,
							64
						)

					Button.Position =
						Entry.PCPosition

					Button.Visible =
						true

					-- IMPORTANT: PC keeps the original action icons.
					for _, Child in ipairs(Button:GetChildren()) do
						if Child:IsA("ImageLabel") then
							Child.Visible = true
						end
					end

				end

				local Label =
					Button:FindFirstChild(
						Button.Name .. "TextLabel"
					)

				if Label then
					Label.Text = Entry.Text

					if IsMobile then
						Label.TextSize =
							20

						Label.Position =
							UDim2.new(
								0,
								0,
								0,
								0
							)

						Label.Size =
							UDim2.new(
								1,
								0,
								1,
								0
							)
					else
						Label.Position =
							UDim2.new(
								0,
								10,
								0,
								-4
							)

						Label.Size =
							UDim2.new(
								1,
								0,
								1,
								0
							)
					end

				end

			end

		end
	end

-- ============================================================
-- NATIVE SETTINGS HIDING
-- ============================================================

local HideNativeSettingsMenu =
	function()
		local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
		local Shield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")
		if Shield then
			local HideGuiObject = function(Object)
				if not Object:IsA("GuiObject") then return end
				pcall(function() Object.Visible = false end)
				pcall(function() Object.Active = false end)
				pcall(function() Object.Selectable = false end)
				pcall(function() Object.AutoButtonColor = false end)
				pcall(function() Object.BackgroundTransparency = 1 end)
				pcall(function() Object.ImageTransparency = 1 end)
				pcall(function() Object.TextTransparency = 1 end)
			end
			HideGuiObject(Shield)
			for _, Child in next, Shield:GetDescendants() do
				HideGuiObject(Child)
			end
		end
	end

-- ============================================================
-- INPUT LOCK
-- ============================================================

local INPUT_LOCK_ACTION = "Settings2016InputLock"
local InputLockBound = false
local InputLockInputs = {}
local InputLockActions = {}
local SavedMouseBehavior = nil
local WasRightMouseDownOnLock = false

local AddInputLock =
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

local IsRightMouseDown =
	function()
		local IsDown = false
		Protect(function()
			IsDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		end)
		return IsDown
	end

local ReleaseRightMouseCapture =
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

local SinkGameplayInput =
	function()
		local FocusedTextBox
		Protect(function() FocusedTextBox = UserInputService:GetFocusedTextBox() end)
		if FocusedTextBox then return Enum.ContextActionResult.Pass end
		return Enum.ContextActionResult.Sink
	end

local SetGameplayInputLocked =
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
			Hub.InConfirmation = false
			if InviteHeader then InviteHeader.Visible = false end
			if InviteList then InviteList.Visible = false end
			if SearchBox then
				pcall(function() SearchBox:ReleaseFocus() end)
			end
		end

		SetGameplayInputLocked(Visible)

		if Visible then
			HideNativeSettingsMenu()
			SetTopbarCoreGuiEnabled(false)
			Hub.Shield.Visible = true
			Hub.HubBar.Visible = not Hub.InInviteMenu and not Hub.InConfirmation
			Hub.PageClipper.Visible = true
			Hub.BottomButtonFrame.Visible = (not IsMobile) and not Hub.InInviteMenu and not Hub.InConfirmation
			if HomeButton then
				HomeButton.Visible = HomeButtonEnabled and not IsMobile and not Hub.InInviteMenu and not Hub.InConfirmation
			end
			if SystemMenuButton then
				SystemMenuButton.Visible = true
				SystemMenuButton.Size = UDim2.fromOffset(32, 32)
			end

			if NoAnimation then
				Hub.Shield.Position = SETTINGS_ACTIVE_POSITION
			else
				Hub.Shield.Position = SETTINGS_INACTIVE_POSITION
				TweenTo(Hub.Shield, SETTINGS_ACTIVE_POSITION, Enum.EasingDirection.InOut, Enum.EasingStyle.Quart, 0.5)
			end

			SwitchToPage(CustomPage or PlayersPage, true)
			ConfigureMobileActionButtons()
			ResizeHub()
		else
			SetTopbarCoreGuiEnabled(true)
			Hub.HubBar.Visible = false
			Hub.BottomButtonFrame.Visible = false
			Hub.PageClipper.Visible = false
			if HomeButton then HomeButton.Visible = false end
			if SystemMenuButton then
				SystemMenuButton.Visible = true
				SystemMenuButton.Size = UDim2.fromOffset(40, 40)
				pcall(function()
					SystemMenuButton.ImageTransparency = 1
				end)
			end
			if NoAnimation then
				Hub.Shield.Position = SETTINGS_INACTIVE_POSITION
				Hub.Shield.Visible = false
			else
				TweenTo(Hub.Shield, SETTINGS_INACTIVE_POSITION, Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.4, function()
					if not Hub.Visible then Hub.Shield.Visible = false end
				end)
			end
		end
	end

-- ============================================================
-- SYSTEM MENU BUTTON
-- ============================================================

SystemMenuButton =
	Create(
		"ImageButton",
		{
			Name = "SystemMenuButton",
			Parent = ScreenGui,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image =
				"rbxasset://LuaPackages/Packages/_Index/FoundationImages/FoundationImages/SpriteSheets/img_set_1x_6.png",

			ImageRectOffset =
				Vector2.new(
					474,
					38
				),

			ImageRectSize =
				Vector2.new(
					36,
					36
				),

			ImageTransparency = 0,
			ScaleType = Enum.ScaleType.Fit,
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

local SystemMenuSelection = Create(
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

local HideNativeSystemMenuButtons =
	function()
		for _, Object in next, CoreGui:GetDescendants() do
			if Object ~= SystemMenuButton and Object.Name == "SystemMenuButton" and Object:IsA("GuiObject") then
				pcall(function() Object.Visible = false end)
				pcall(function() Object.Active = false end)
				pcall(function() Object.Selectable = false end)
			end
		end
	end

local AlignSystemMenuButton =
	function()
		if not SystemMenuButton then return end

		SystemMenuButton.Visible = true

		if Hub.Visible then
			SystemMenuButton.Position =
				UDim2.fromOffset(
					SYSTEM_MENU_OFFSET_X,
					SYSTEM_MENU_OFFSET_Y
				)
			SystemMenuButton.Size = UDim2.fromOffset(32, 32)
			pcall(function()
				SystemMenuButton.ImageTransparency = 0
			end)
		else
			-- Closed state: keep the larger 40x40 clickable hitbox 4px left and 4px up,
			-- but make the image itself invisible.
			SystemMenuButton.Position =
				UDim2.fromOffset(
					SYSTEM_MENU_OFFSET_X - 4,
					SYSTEM_MENU_OFFSET_Y - 4
				)
			SystemMenuButton.Size = UDim2.fromOffset(40, 40)
			pcall(function()
				SystemMenuButton.ImageTransparency = 1
			end)
		end

		-- Keep the real/native button hidden on every platform.
		HideNativeSystemMenuButtons()
		if PositionRecorderGui then
			PositionRecorderGui()
		end
	end

Connect(SystemMenuButton.MouseButton1Click, function()
	SetVisibility(not Hub.Visible)
	AlignSystemMenuButton()
end)
AlignSystemMenuButton()
Connect(CoreGui.ChildAdded, function()
	task.defer(function()
		HideNativeSystemMenuButtons()
		AlignSystemMenuButton()
		PositionRecorderGui()
	end)
end)
Connect(CoreGui.DescendantAdded, function(Descendant)
	if Descendant.Name == "SystemMenuButton" and Descendant ~= SystemMenuButton then
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

local LastEscapeAction = 0

local CloseInvitePage =
	function()
		local Previous = Hub.PreviousMenuPage or PlayersPage
		Hub.PreviousMenuPage = nil
		Hub.InInviteMenu = false
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
		Hub.PageView.ScrollBarThickness = IsMobile and 0 or 6
		if HomeButton then HomeButton.Visible = HomeButtonEnabled and not IsMobile end
		SwitchToPage(Previous, true, true)
		ResizeHub()
	end

local EscapeAction =
	function(_, State)
		if State ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
		local Now = tick()
		if Now - LastEscapeAction < 0.15 then return Enum.ContextActionResult.Sink end
		LastEscapeAction = Now
		HideNativeSettingsMenu()
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
			Hub.PageView.ScrollBarThickness = IsMobile and 0 or 6
			ResizeHub()
			return Enum.ContextActionResult.Sink
		end

		if Hub.Visible then Hub.SuppressNativeOpenUntil = Now + 0.8 end
		SetVisibility(not Hub.Visible)
		AlignSystemMenuButton()
		Spawn(function()
			Wait()
			HideNativeSettingsMenu()
			HideNativeSystemMenuButtons()
		end)
		return Enum.ContextActionResult.Sink
	end

Protect(function()
	local BoundAtPriority = pcall(function()
		ContextActionService:BindCoreActionAtPriority("RBXEscapeMainMenu", EscapeAction, false, 10000, Enum.KeyCode.Escape, Enum.KeyCode.ButtonStart)
	end)
	if not BoundAtPriority then
		ContextActionService:BindCoreAction("RBXEscapeMainMenu", EscapeAction, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonStart)
	end
end)

Connect(UserInputService.InputBegan, function(Input, Processed)
	if Processed and Input.KeyCode ~= Enum.KeyCode.Escape then return end
	if Input.KeyCode == Enum.KeyCode.Escape then
		EscapeAction(nil, Enum.UserInputState.Begin)
	elseif not IsMobile and Input.KeyCode == Enum.KeyCode.F12 then
		if tick() >= IgnoreRecorderF12Until then
			ToggleCustomRecording()
		end
	elseif Hub.Visible and Input.KeyCode == Enum.KeyCode.R and not Hub.InInviteMenu and not Hub.InConfirmation then
		PushPage(ResetPage)
	elseif Hub.Visible and Input.KeyCode == Enum.KeyCode.L and not Hub.InInviteMenu and not Hub.InConfirmation then
		PushPage(LeavePage)
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

local HookNativeMenu =
	function()
		local HookedNative = {}
		local GetNativeMenuTarget = function()
			if Hub.NativeMenuTarget == nil then return true end
			return Hub.NativeMenuTarget
		end
		local NativeMenuOpened = function()
			HideNativeSettingsMenu()
			HideNativeSystemMenuButtons()
			if tick() < Hub.SuppressNativeOpenUntil then return end
			SetVisibility(GetNativeMenuTarget())
			Hub.NativeMenuTarget = nil
		end
		local HookNativeObject = function(Object)
			if not Object or HookedNative[Object] or not Object:IsA("GuiObject") then return end
			HookedNative[Object] = true
			Connect(Object:GetPropertyChangedSignal("Visible"), function()
				if Object.Visible then NativeMenuOpened() end
			end)
			if Object.Visible then NativeMenuOpened() end
		end
		local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
		local Shield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")
		local HookNativeContainer = function(NewShield)
			if not NewShield then return end
			Shield = NewShield
			HideNativeSettingsMenu()
			for _, Object in next, NewShield:GetDescendants() do HookNativeObject(Object) end
		end
		HookNativeContainer(Shield)
		if RobloxGui then
			Connect(RobloxGui.DescendantAdded, function(Descendant)
				if Descendant.Name == "SettingsClippingShield" and Descendant.Parent == RobloxGui then
					HookNativeContainer(Descendant)
				elseif Shield and Descendant:IsDescendantOf(Shield) then
					HookNativeObject(Descendant)
					if Descendant:IsA("GuiObject") and Descendant.Visible then NativeMenuOpened() end
				end
			end)
		end
		local TopBarApp = CoreGui:FindFirstChild("TopBarApp")
		TopBarApp = TopBarApp and TopBarApp:FindFirstChild("TopBarApp")
		local Holder = TopBarApp and TopBarApp:FindFirstChild("MenuIconHolder")
		local Trigger = Holder and Holder:FindFirstChild("TriggerPoint")
		local Hit = Trigger and Trigger:FindFirstChild("IconHitArea")
		if Hit and Hit:IsA("GuiButton") then
			Connect(Hit.MouseButton1Click, function()
				local Target = not Hub.Visible
				Hub.NativeMenuTarget = Target
				Spawn(function()
					Wait()
					SetVisibility(Target)
					if Hub.NativeMenuTarget == Target then Hub.NativeMenuTarget = nil end
				end)
			end)
		end
	end

-- ============================================================
-- INITIAL STATE
-- ============================================================

SwitchToPage(GamePage, true, true)
ConfigureMobileActionButtons()
ResizeHub()
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
