--[[
	Filename: SettingsHub.lua
	Compatibility rewrite for the Yeku legacy CoreGui runtime.

	Fixes:
	 * Preserves the existing NewRobloxGui tree and legacy page modules.
	 * Confirmation pages are forcibly hidden when they are no longer current.
	 * Delayed Hide/Display operations cannot leave Leave or Reset visible.
	 * L and R open Leave/Reset independently of bottom-bar visibility.
	 * Direct keyboard-input fallback for L/R when ContextActionService
	   does not deliver the key action.
	 * Bottom-bar actions retain their gamepad bindings.
	 * The bottom bar cannot reappear on Leave/Reset after Display or ShowBar.
	 * Tab header icon/text geometry follows one consistent reference layout.
	 * Tab header metrics are copied from the Players tab where possible.
	 * The original button hover styles are not overridden by fake outlines.
	 * Menu opening and closing animations are slower and smoother.
	 * Page switching, Escape, and visibility state are guarded.
	 * Page clipping uses MenuContainer-local geometry on every page.
	 * The shared page viewport cannot extend behind the bottom button frame.
	 * Desktop aspect-ratio sizing is height-driven to prevent overflow.
	 * Resizes and page switches recalculate the shared page viewport.
]]

local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local function getServiceSafely(name)
	local ok, service = pcall(function()
		return game:GetService(name)
	end)

	return ok and service or nil
end

local RobloxReplicatedStorage = getServiceSafely("RobloxReplicatedStorage")
local CorePackages = getServiceSafely("CorePackages")

local function findGuiRoot()
	local node = script

	while node do
		if node.Name == "NewRobloxGui" or node.Name == "RobloxGui" then
			return node
		end

		node = node.Parent
	end

	return CoreGui:FindFirstChild("NewRobloxGui")
		or CoreGui:FindFirstChild("RobloxGui")
		or CoreGui:WaitForChild("NewRobloxGui", 10)
		or CoreGui:WaitForChild("RobloxGui", 5)
end

local RobloxGui = findGuiRoot()

assert(
	RobloxGui,
	"SettingsHub: could not find the existing CoreGui.NewRobloxGui root"
)

local function findPath(root, path)
	local node = root

	for _, childName in ipairs(path) do
		if not node then
			return nil
		end

		node = node:FindFirstChild(childName)
	end

	return node
end

local function requireSafely(moduleInstance, label)
	if not moduleInstance or not moduleInstance:IsA("ModuleScript") then
		return nil
	end

	local ok, result = pcall(require, moduleInstance)

	if not ok then
		warn(
			"[SettingsHub] Could not require "
				.. tostring(label or moduleInstance:GetFullName())
				.. ": "
				.. tostring(result)
		)

		return nil
	end

	return result
end

local function fireSignal(signalObject, ...)
	if not signalObject then
		return false
	end

	local ok, fireMethod = pcall(function()
		return signalObject.fire or signalObject.Fire
	end)

	if not ok or type(fireMethod) ~= "function" then
		warn("[SettingsHub] SettingsShowSignal has no fire/Fire method")
		return false
	end

	local fired, err = pcall(fireMethod, signalObject, ...)

	if not fired then
		warn(
			"[SettingsHub] Could not fire SettingsShowSignal: "
				.. tostring(err)
		)
	end

	return fired
end

local Modules = RobloxGui:FindFirstChild("Modules")

assert(
	Modules,
	"SettingsHub: NewRobloxGui is missing its existing Modules folder"
)

local SettingsModules = Modules:FindFirstChild("Settings")

local UtilityModule =
	(SettingsModules and SettingsModules:FindFirstChild("Utility"))
	or Modules:FindFirstChild("Utility")
	or (script.Parent and script.Parent:FindFirstChild("Utility"))

local utility = requireSafely(UtilityModule, "Settings.Utility")

assert(
	utility,
	"SettingsHub: unable to load the existing Utility ModuleScript"
)

local function getFlag(name, defaultValue)
	local ok, settingsObject = pcall(function()
		return settings()
	end)

	if not ok or not settingsObject then
		return defaultValue
	end

	local success, value = pcall(function()
		return settingsObject:GetFFlag(name)
	end)

	if success and type(value) == "boolean" then
		return value
	end

	return defaultValue
end

local function getPlatform()
	local ok, platform = pcall(function()
		return UserInputService:GetPlatform()
	end)

	return ok and platform or nil
end

local platform = getPlatform()
local isTouchDevice = UserInputService.TouchEnabled

local function getTenFootInterfaceEnabled()
	local module = Modules:FindFirstChild("TenFootInterface")
	local tenFoot = requireSafely(module, "TenFootInterface")

	if tenFoot and type(tenFoot.IsEnabled) == "function" then
		local ok, value = pcall(tenFoot.IsEnabled, tenFoot)

		if ok then
			return value == true
		end
	end

	return false
end

local isTenFootInterface = getTenFootInterfaceEnabled()

local FFlagUseNotificationsLocalization =
	getFlag("UseNotificationsLocalization", false)

local FFlagSettingsHubBarsRefactor =
	getFlag("SettingsHubBarsRefactor4", false)

local FFlagEnableNewDevConsole =
	getFlag("EnableNewDevConsole", false)

local FFlagHelpMenuShowPlaceVersion =
	getFlag("HelpMenuShowPlaceVersion", false)

local FFlagSettingsHubPlayersHorizontalScroll =
	getFlag("SettingsHubPlayersHorizontalScroll", false)

local FFlagEnableResponsiveUIFix =
	getFlag("EnableResponsiveUIFix", false)

local CONTENT_BASE_URL = ""

pcall(function()
	CONTENT_BASE_URL = ContentProvider.BaseUrl
end)

local isTestEnvironment =
	CONTENT_BASE_URL ~= ""
	and not string.find(CONTENT_BASE_URL, "www.roblox.com", 1, true)

local function loadModule(path, fallbackPath)
	local instance = findPath(RobloxGui, path)

	if not instance and fallbackPath then
		instance = findPath(RobloxGui, fallbackPath)
	end

	return requireSafely(instance, table.concat(path, "."))
end

local VRHub = loadModule({"Modules", "VR", "VRHub"})
local DeveloperConsoleModule = loadModule({"Modules", "DeveloperConsoleModule"})
local DevConsoleMaster = loadModule({"Modules", "DevConsoleMaster"})
local ChatSelector = loadModule({"Modules", "ChatSelector"})
local PlayerlistModule = loadModule({"Modules", "PlayerlistModule"})
local BackpackScript = loadModule({"Modules", "BackpackScript"})

local FlagSettings = loadModule({
	"Modules",
	"Settings",
	"Pages",
	"ShareGame",
	"FlagSettings",
})

local shareGameEnabled = false

if FlagSettings
	and type(FlagSettings.IsShareGamePageEnabledByPlatform) == "function" then
	local ok, enabled = pcall(
		FlagSettings.IsShareGamePageEnabledByPlatform,
		platform
	)

	shareGameEnabled = ok and enabled == true
end

local function tryMethod(object, methodName, ...)
	if not object then
		return false, "missing object"
	end

	local okMethod, method = pcall(function()
		return object[methodName]
	end)

	if not okMethod or type(method) ~= "function" then
		return false, "missing method " .. tostring(methodName)
	end

	return pcall(method, object, ...)
end

local function getProperty(object, property, defaultValue)
	local ok, value = pcall(function()
		return object[property]
	end)

	if ok then
		return value
	end

	return defaultValue
end

local function getCurrentViewport()
	local camera = workspace.CurrentCamera

	if camera then
		local ok, viewport = pcall(function()
			return camera.ViewportSize
		end)

		if ok and viewport and viewport.X > 1 and viewport.Y > 1 then
			return viewport
		end
	end

	return Vector2.new(1280, 720)
end

local function getRootSize()
	local size = getProperty(RobloxGui, "AbsoluteSize", nil)

	if size and size.X > 1 and size.Y > 1 then
		return size
	end

	return getCurrentViewport()
end

local function setSelectedObject(object)
	pcall(function()
		GuiService.SelectedObject = object
	end)
end

local function getSelectedObject()
	return getProperty(GuiService, "SelectedObject", nil)
end

local function getLastInputType()
	local ok, inputType = pcall(function()
		return UserInputService:GetLastInputType()
	end)

	return ok and inputType or Enum.UserInputType.Keyboard
end

local function setMouseIconBehavior(behaviorName)
	pcall(function()
		local behaviorEnum = Enum.OverrideMouseIconBehavior

		if behaviorEnum then
			UserInputService.OverrideMouseIconBehavior =
				behaviorEnum[behaviorName]
		end
	end)
end

local function bindAction(actionName, callback, createTouchButton, ...)
	pcall(function()
		ContextActionService:UnbindAction(actionName)
	end)

	local inputs = {...}
	local priority = Enum.ContextActionPriority.High.Value

	local ok, err = pcall(function()
		ContextActionService:BindActionAtPriority(
			actionName,
			callback,
			createTouchButton == true,
			priority,
			table.unpack(inputs)
		)
	end)

	if not ok then
		warn(
			"[SettingsHub] Could not bind action "
				.. tostring(actionName)
				.. ": "
				.. tostring(err)
		)
	end

	return ok
end

local function unbindAction(actionName)
	pcall(function()
		ContextActionService:UnbindAction(actionName)
	end)
end

local function getServerVersion()
	if not RobloxReplicatedStorage then
		return "unavailable"
	end

	local remote =
		RobloxReplicatedStorage:FindFirstChild("GetServerVersion")

	if not remote then
		local ok, found = pcall(function()
			return RobloxReplicatedStorage:WaitForChild(
				"GetServerVersion",
				3
			)
		end)

		if ok then
			remote = found
		end
	end

	if not remote or not remote:IsA("RemoteFunction") then
		return "unavailable"
	end

	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)

	if ok and result ~= nil then
		return tostring(result)
	end

	return "unavailable"
end

local function getClientVersion()
	local ok, result = pcall(function()
		return version()
	end)

	if ok and result ~= nil then
		return tostring(result)
	end

	return "current client"
end

local function getPlaceVersionText()
	local ok, placeVersion = pcall(function()
		return game.PlaceVersion
	end)

	return ok and tostring(placeVersion) or "unavailable"
end

local SETTINGS_SHIELD_COLOR = Color3.fromRGB(41, 41, 41)
local SETTINGS_SHIELD_TRANSPARENCY = 0.2
local SETTINGS_SHIELD_VR_TRANSPARENCY = 1

local SETTINGS_SHIELD_INACTIVE_POSITION =
	UDim2.new(0, 0, -1, -36)

local SETTINGS_SHIELD_ACTIVE_POSITION =
	UDim2.new(0, 0, 0, 0)

local SETTINGS_BASE_ZINDEX = 2

local SETTINGS_OPEN_TWEEN_DURATION = 0.52
local SETTINGS_CLOSE_TWEEN_DURATION = 0.50

local DEV_CONSOLE_ACTION_NAME = "Open Dev Console"
local QUICK_PROFILER_ACTION_NAME = "Show Quick Profiler"
local CLOSE_MENU_ACTION_NAME = "RBXEscapeMainMenu"

local LEAVE_KEY_ACTION_NAME = "RbxSettingsHubLeaveKey"
local RESET_KEY_ACTION_NAME = "RbxSettingsHubResetKey"

local VERSION_BAR_HEIGHT =
	isTenFootInterface and 32
	or (utility:IsSmallTouchScreen() and 24 or 26)

local function isXboxPlatform()
	return tostring(platform):find("XBox", 1, true) ~= nil
end

local function createPage(path)
	return loadModule(path)
end

local function createLocalSignal(signalName)
	local listeners = {}
	local signal = {}

	function signal:Connect(callback)
		assert(
			type(callback) == "function",
			"Signal callback must be a function"
		)

		local entry = {
			Callback = callback,
			Connected = true,
		}

		local connection = {}

		function connection:Disconnect()
			entry.Connected = false
		end

		connection.disconnect = connection.Disconnect

		table.insert(listeners, entry)

		return connection
	end

	signal.connect = signal.Connect

	function signal:Fire(...)
		local args = table.pack(...)

		for _, entry in ipairs(listeners) do
			if entry.Connected then
				local ok, err = pcall(
					entry.Callback,
					table.unpack(args, 1, args.n)
				)

				if not ok then
					warn(
						"[SettingsHub] "
							.. tostring(signalName)
							.. " callback failed: "
							.. tostring(err)
					)
				end
			end
		end
	end

	signal.fire = signal.Fire

	return signal
end

local function createSettingsHub()
	local this = {
		Visible = false,
		Active = true,

		Pages = {
			CurrentPage = nil,
			PageTable = {},
		},

		MenuStack = {},
		TabHeaders = {},
		BottomBarButtons = {},

		ResizedConnection = nil,
		TabConnection = nil,
		SettingsShowSignal = utility:CreateSignal(),
		OpenStateChangedCount = 0,
	}

	local PoppedMenuEvent = createLocalSignal("SettingsHub.PoppedMenu")
	this.PoppedMenu = PoppedMenuEvent

	this.LeaveGamePage =
		createPage({"Modules", "Settings", "Pages", "LeaveGame"})

	this.ResetCharacterPage =
		createPage({"Modules", "Settings", "Pages", "ResetCharacter"})

	this.GameSettingsPage =
		createPage({"Modules", "Settings", "Pages", "GameSettings"})

	this.ReportAbusePage =
		createPage({"Modules", "Settings", "Pages", "ReportAbuseMenu"})

	this.HelpPage =
		createPage({"Modules", "Settings", "Pages", "Help"})

	this.PlayersPage =
		not isTenFootInterface
		and createPage({"Modules", "Settings", "Pages", "Players"})
		or nil

	this.RecordPage = nil

	if tostring(platform):find("Windows", 1, true) then
		this.RecordPage =
			createPage({"Modules", "Settings", "Pages", "Record"})
	end

	this.HomePage =
		createPage({"Modules", "Settings", "Pages", "Home"})

	local pageChangeConnection
	local viewportConnection
	local cameraChangedConnection

	-- Forward-declare this because viewport and page callbacks are created
	-- before the actual responsive layout function is assigned.
	local onScreenSizeChanged

	local bottomBarBound = false
	local resetEnabled = true

	local GetHeaderPosition
	local setVisibilityInternal

	local function isConfirmationPage(page)
		return page ~= nil
			and (
				page == this.LeaveGamePage
				or page == this.ResetCharacterPage
			)
	end

	local function forceHideConfirmationPage(page)
		if not isConfirmationPage(page) then
			return
		end

		local pageGui = page.Page

		if pageGui and pageGui:IsA("GuiObject") then
			pcall(function()
				pageGui.Visible = false
				pageGui.Active = false
			end)
		end
	end

	local function forceHideInactiveConfirmationPages(currentPage)
		for _, confirmationPage in ipairs({
			this.LeaveGamePage,
			this.ResetCharacterPage,
			}) do
			if confirmationPage and confirmationPage ~= currentPage then
				forceHideConfirmationPage(confirmationPage)
			end
		end
	end

	local function pageNeedsBottomBar(page)
		if not page then
			return false
		end

		if isConfirmationPage(page) then
			return false
		end

		if FFlagSettingsHubBarsRefactor then
			return page.ShouldShowBottomBar == true
		end

		return true
	end

	local function shouldShowBottomBar(page)
		page = page or this.Pages.CurrentPage

		if not page or isConfirmationPage(page) then
			return false
		end

		if utility:IsPortrait() or utility:IsSmallTouchScreen() then
			return false
		end

		return pageNeedsBottomBar(page)
	end

	local function shouldShowHubBar(page)
		page = page or this.Pages.CurrentPage

		if not page then
			return true
		end

		if isConfirmationPage(page) then
			return false
		end

		if FFlagSettingsHubBarsRefactor then
			return page.ShouldShowBottomBar == true
		end

		return true
	end

	local function hideTempPlayerList(hide)
		if PlayerlistModule then
			tryMethod(PlayerlistModule, "HideTemp", "SettingsMenu", hide)
		end
	end

	local function getChatVisible()
		if ChatSelector then
			local ok, value = tryMethod(ChatSelector, "GetVisibility")

			if ok then
				return value == true
			end
		end

		return false
	end

	local function toggleChatVisibility()
		if ChatSelector then
			local ok = tryMethod(ChatSelector, "ToggleVisibility")

			if not ok then
				tryMethod(ChatSelector, "SetVisibility", not getChatVisible())
			end
		end
	end

	local function setMenuOpenState(value)
		pcall(function()
			GuiService:SetMenuIsOpen(value)
		end)
	end

	local activeShieldTween = nil

	local function tweenShieldPosition(
		position,
		duration,
		easingDirection,
		easingStyle,
		onCompleted
	)
		local shield = this.Shield

		if not shield or not shield.Parent then
			if onCompleted then
				pcall(onCompleted)
			end

			return
		end

		if activeShieldTween then
			pcall(function()
				activeShieldTween:Cancel()
			end)

			activeShieldTween = nil
		end

		local ok, tween = pcall(function()
			return TweenService:Create(
				shield,
				TweenInfo.new(duration, easingStyle, easingDirection),
				{Position = position}
			)
		end)

		if not ok or not tween then
			shield.Position = position

			if onCompleted then
				pcall(onCompleted)
			end

			return
		end

		activeShieldTween = tween

		if onCompleted then
			local connection

			connection = tween.Completed:Connect(function(playbackState)
				if connection then
					connection:Disconnect()
				end

				if activeShieldTween == tween then
					activeShieldTween = nil
				end

				if playbackState == Enum.PlaybackState.Completed then
					pcall(onCompleted)
				end
			end)
		else
			tween.Completed:Connect(function()
				if activeShieldTween == tween then
					activeShieldTween = nil
				end
			end)
		end

		tween:Play()
	end

	local function addBottomBarButton(
		name,
		text,
		gamepadImage,
		keyboardImage,
		position,
		clickFunc,
		hotkeys
	)
		local buttonName = name .. "Button"
		local textName = name .. "Text"

		local size =
			isTenFootInterface
			and UDim2.new(0, 320, 0, 120)
			or UDim2.new(0, 260, 0, 70)

		local button, textLabel = utility:MakeStyledButton(
			buttonName,
			text,
			size,
			clickFunc,
			nil,
			this
		)

		if not button or not textLabel then
			warn(
				"[SettingsHub] Utility:MakeStyledButton did not return "
					.. "a button and label for "
					.. name
			)

			return
		end

		this[buttonName] = button
		this[textName] = textLabel

		button.Name = buttonName
		button.Position = position
		button.Parent = this.BottomButtonFrame

		if isTenFootInterface then
			pcall(function()
				button.ImageTransparency = 1
			end)
		end

		textLabel.TextSize = isTenFootInterface and 36 or 24
		textLabel.TextWrapped = true

		local hintLabel

		if not isTouchDevice then
			if FFlagUseNotificationsLocalization then
				textLabel.Size = UDim2.new(0.675, 0, 0.67, 0)
				textLabel.Position = UDim2.new(0.275, 0, 0.125, 0)
			else
				textLabel.Size = UDim2.new(0.75, 0, 0.9, 0)
				textLabel.Position = UDim2.new(0.25, 0, 0, 0)
			end

			local useGamepadIcon =
				UserInputService:GetGamepadConnected(
					Enum.UserInputType.Gamepad1
				)
				or isXboxPlatform()

			hintLabel = utility:Create("ImageLabel") {
				Name = name .. "Hint",
				ZIndex = this.Shield.ZIndex + 2,
				BackgroundTransparency = 1,

				Image = useGamepadIcon
					and (gamepadImage or "")
					or (keyboardImage or ""),

				Parent = button,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(0, 50, 0, 50),
				Position = UDim2.new(0.15, 0, 0.475, 0),
			}
		end

		local function updateHint(inputObject)
			if not hintLabel or not inputObject then
				return
			end

			if tostring(inputObject.UserInputType):find("Gamepad", 1, true) then
				hintLabel.Image = gamepadImage or ""
			elseif inputObject.UserInputType == Enum.UserInputType.Keyboard then
				hintLabel.Image = keyboardImage or ""
			end
		end

		UserInputService.InputBegan:Connect(updateHint)

		local function hotKeyFunc(_, inputState)
			if inputState == Enum.UserInputState.Begin and this.Visible then
				clickFunc()
			end

			return Enum.ContextActionResult.Sink
		end

		this.BottomBarButtons[#this.BottomBarButtons + 1] = {
			buttonName,
			{hotKeyFunc, hotkeys or {}},
		}
	end

	-- The footer is controlled by the CURRENT PAGE rather than by the last
	-- page that happened to bind its buttons.
	local function setBottomBarBindings()
		local shouldDisplay =
			this.Visible
			and shouldShowBottomBar(this.Pages.CurrentPage)

		if not shouldDisplay then
			if this.BottomButtonFrame then
				this.BottomButtonFrame.Visible = false
			end

			if bottomBarBound then
				for _, buttonInfo in ipairs(this.BottomBarButtons) do
					unbindAction(buttonInfo[1])
				end

				bottomBarBound = false
			end

			return
		end

		if not bottomBarBound then
			for _, buttonInfo in ipairs(this.BottomBarButtons) do
				local actionName = buttonInfo[1]
				local hotkeyInfo = buttonInfo[2]

				bindAction(
					actionName,
					hotkeyInfo[1],
					false,
					table.unpack(hotkeyInfo[2])
				)
			end

			bottomBarBound = true
		end

		if this.BottomButtonFrame then
			this.BottomButtonFrame.Visible = true
		end
	end

	local function removeBottomBarBindings(delayBeforeRemoving)
		for _, buttonInfo in ipairs(this.BottomBarButtons) do
			unbindAction(buttonInfo[1])
		end

		bottomBarBound = false

		local openStateAtRequest = this.OpenStateChangedCount

		local function hideFrame()
			if this.OpenStateChangedCount == openStateAtRequest
				and this.BottomButtonFrame then
				this.BottomButtonFrame.Visible = false
			end
		end

		if delayBeforeRemoving and delayBeforeRemoving > 0 then
			task.delay(delayBeforeRemoving, hideFrame)
		else
			hideFrame()
		end
	end

	-- Reapply the correct bars after page Display/Hide methods run.
	-- Legacy pages can call ShowBar themselves, so this must not assume that
	-- the visibility values set before Display are still correct afterwards.
	local function enforcePageChrome(page)
		page = page or this.Pages.CurrentPage

		if this.HubBar then
			this.HubBar.Visible = shouldShowHubBar(page)
		end

		if this.PageViewClipper then
			this.PageViewClipper.Visible = true
			this.PageViewClipper.ClipsDescendants = true
		end

		if this.BottomButtonFrame then
			this.BottomButtonFrame.Visible =
				this.Visible and shouldShowBottomBar(page)
		end

		if this.Visible and shouldShowBottomBar(page) then
			setBottomBarBindings()
		else
			removeBottomBarBindings()
		end
	end

	local function setResetEnabled(value)
		resetEnabled = value == true

		local button = this.ResetCharacterButton

		if not button then
			return
		end

		button.Selectable = resetEnabled
		button.Active = resetEnabled

		local enabledValue = button:FindFirstChild("Enabled")

		if enabledValue and enabledValue:IsA("BoolValue") then
			enabledValue.Value = resetEnabled
		end

		local hint = button:FindFirstChild("ResetCharacterHint")

		if hint then
			hint.ImageColor3 = resetEnabled
				and Color3.new(1, 1, 1)
				or Color3.fromRGB(100, 100, 100)
		end

		local label =
			button:FindFirstChild("ResetCharacterButtonTextLabel")

		if label and label:IsA("TextLabel") then
			label.TextColor3 = resetEnabled
				and Color3.new(1, 1, 1)
				or Color3.fromRGB(100, 100, 100)
		end
	end

	----------------------------------------------------------------------
	-- TAB HEADER LAYOUT
	----------------------------------------------------------------------

	local canonicalHeaderMetrics = nil

	local function findHeaderTextLabel(headerGui)
		local descendants = headerGui:GetDescendants()

		for _, descendant in ipairs(descendants) do
			if descendant:IsA("TextLabel") then
				local name = string.lower(descendant.Name)

				if string.find(name, "text", 1, true)
					or string.find(name, "label", 1, true)
					or string.find(name, "title", 1, true) then
					return descendant
				end
			end
		end

		for _, descendant in ipairs(descendants) do
			if descendant:IsA("TextLabel") then
				return descendant
			end
		end

		return nil
	end

	local function findHeaderIcon(headerGui)
		local descendants = headerGui:GetDescendants()

		for _, descendant in ipairs(descendants) do
			if descendant:IsA("ImageLabel")
				or descendant:IsA("ImageButton") then
				local name = string.lower(descendant.Name)

				if string.find(name, "icon", 1, true) then
					return descendant
				end
			end
		end

		for _, descendant in ipairs(descendants) do
			if descendant:IsA("ImageLabel") then
				return descendant
			end
		end

		return nil
	end

	local function captureHeaderPartMetrics(object, properties)
		if not object then
			return nil
		end

		local metrics = {}

		for _, propertyName in ipairs(properties) do
			local ok, value = pcall(function()
				return object[propertyName]
			end)

			if ok then
				metrics[propertyName] = value
			end
		end

		return metrics
	end

	local function applyHeaderPartMetrics(object, metrics)
		if not object or not metrics then
			return
		end

		for propertyName, value in pairs(metrics) do
			pcall(function()
				object[propertyName] = value
			end)
		end
	end

	local TEXT_HEADER_PROPERTIES = {
		"Position",
		"Size",
		"AnchorPoint",
		"TextSize",
		"Font",
		"TextXAlignment",
		"TextYAlignment",
		"TextWrapped",
		"TextScaled",
	}

	local ICON_HEADER_PROPERTIES = {
		"Position",
		"Size",
		"AnchorPoint",
	}

	local function alignTabHeaderMetrics(headerGui)
		if not headerGui or not headerGui:IsA("GuiObject") then
			return
		end

		local textLabel = findHeaderTextLabel(headerGui)
		local iconLabel = findHeaderIcon(headerGui)

		local directTextObject

		if not textLabel
			and (
				headerGui:IsA("TextButton")
					or headerGui:IsA("TextLabel")
			) then
			directTextObject = headerGui
		end

		local actualTextObject = textLabel or directTextObject

		if not canonicalHeaderMetrics then
			canonicalHeaderMetrics = {
				Text = captureHeaderPartMetrics(
					actualTextObject,
					TEXT_HEADER_PROPERTIES
				),

				Icon = captureHeaderPartMetrics(
					iconLabel,
					ICON_HEADER_PROPERTIES
				),
			}
		end

		if actualTextObject and canonicalHeaderMetrics.Text then
			applyHeaderPartMetrics(
				actualTextObject,
				canonicalHeaderMetrics.Text
			)
		elseif actualTextObject then
			actualTextObject.AnchorPoint = Vector2.new(0, 0.5)
			actualTextObject.Position = UDim2.new(0, 48, 0.5, 0)
			actualTextObject.Size = UDim2.new(1, -56, 1, 0)

			pcall(function()
				actualTextObject.TextXAlignment = Enum.TextXAlignment.Left
				actualTextObject.TextYAlignment = Enum.TextYAlignment.Center
				actualTextObject.TextScaled = false
				actualTextObject.TextSize =
					isTenFootInterface and 28
					or (utility:IsSmallTouchScreen() and 14 or 20)
			end)
		end

		if iconLabel and canonicalHeaderMetrics.Icon then
			applyHeaderPartMetrics(
				iconLabel,
				canonicalHeaderMetrics.Icon
			)
		elseif iconLabel then
			iconLabel.AnchorPoint = Vector2.new(0, 0.5)
			iconLabel.Position = UDim2.new(0, 12, 0.5, 0)

			local iconSize = isTenFootInterface and 44 or 28

			iconLabel.Size = UDim2.new(0, iconSize, 0, iconSize)
		end
	end

	this.AlignTabHeaderMetrics = alignTabHeaderMetrics

	local function makeGui()
		local oldShield =
			RobloxGui:FindFirstChild("SettingsClippingShield")

		if oldShield then
			local reusablePages = {
				this.PlayersPage,
				this.ResetCharacterPage,
				this.LeaveGamePage,
				this.GameSettingsPage,
				this.ReportAbusePage,
				this.HelpPage,
				this.RecordPage,
				this.HomePage,
			}

			for _, page in pairs(reusablePages) do
				if page then
					local header

					pcall(function()
						header = page:GetTabHeader()
					end)

					header = header or page.TabHeader

					for _, gui in pairs({header, page.Page}) do
						if gui then
							local ok, inside = pcall(function()
								return gui:IsDescendantOf(oldShield)
							end)

							if ok and inside then
								local detached, detachError = pcall(function()
									gui.Parent = nil
								end)

								if not detached then
									warn(
										"[SettingsHub] Could not preserve cached page GUI "
											.. tostring(gui.Name)
											.. ": "
											.. tostring(detachError)
									)
								end
							end
						end
					end
				end
			end

			oldShield:Destroy()
		end

		this.ClippingShield = utility:Create("Frame") {
			Name = "SettingsClippingShield",
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			BackgroundTransparency = 1,
			Visible = true,
			ZIndex = SETTINGS_BASE_ZINDEX,
			Parent = RobloxGui,
		}

		this.Shield = utility:Create("Frame") {
			Name = "SettingsShield",
			Size = UDim2.new(1, 0, 1, 0),
			Position = SETTINGS_SHIELD_INACTIVE_POSITION,
			BackgroundTransparency = SETTINGS_SHIELD_TRANSPARENCY,
			BackgroundColor3 = SETTINGS_SHIELD_COLOR,
			BorderSizePixel = 0,
			Visible = false,
			Active = true,
			ZIndex = SETTINGS_BASE_ZINDEX,
			Parent = this.ClippingShield,
		}

		this.VRShield = utility:Create("Frame") {
			Name = "VRBackground",
			Parent = this.Shield,
			BackgroundColor3 = SETTINGS_SHIELD_COLOR,
			BackgroundTransparency = SETTINGS_SHIELD_TRANSPARENCY,
			Position = UDim2.new(0, -4, 0, 24),
			Size = UDim2.new(1, 8, 1, -40),
			BorderSizePixel = 0,
			Visible = false,
		}

		this.VersionContainer = utility:Create("Frame") {
			Name = "VersionContainer",
			Parent = this.Shield,
			BackgroundColor3 = SETTINGS_SHIELD_COLOR,
			BackgroundTransparency = SETTINGS_SHIELD_TRANSPARENCY,
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, VERSION_BAR_HEIGHT),
			AnchorPoint = Vector2.new(0, 1),
			BorderSizePixel = 0,
			ZIndex = 5,
			Visible = false,
		}

		local placeLabelWidth =
			FFlagHelpMenuShowPlaceVersion and 0.333 or 0.5

		local clientLabelPosition =
			FFlagHelpMenuShowPlaceVersion and 0.333 or 0.5

		local clientTextAlignment =
			FFlagHelpMenuShowPlaceVersion
			and Enum.TextXAlignment.Center
			or Enum.TextXAlignment.Right

		local versionTextSize =
			isTenFootInterface and 28
			or (utility:IsSmallTouchScreen() and 14 or 20)

		this.ServerVersionLabel = utility:Create("TextLabel") {
			Name = "ServerVersionLabel",
			Parent = this.VersionContainer,
			Position = UDim2.new(0, 3, 0, 3),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = versionTextSize,
			Text = "Server Version: loading...",
			Size = UDim2.new(placeLabelWidth, -6, 1, -6),
			Font = Enum.Font.SourceSans,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}

		task.spawn(function()
			if this.ServerVersionLabel and this.ServerVersionLabel.Parent then
				this.ServerVersionLabel.Text =
					"Server Version: " .. getServerVersion()
			end
		end)

		this.ClientVersionLabel = utility:Create("TextLabel") {
			Name = "ClientVersionLabel",
			Parent = this.VersionContainer,
			Position = UDim2.new(clientLabelPosition, 3, 0, 3),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = versionTextSize,
			Text = "Client Version: " .. getClientVersion(),
			Size = UDim2.new(placeLabelWidth, -6, 1, -6),
			Font = Enum.Font.SourceSans,
			TextXAlignment = clientTextAlignment,
			ZIndex = 5,
		}

		if FFlagHelpMenuShowPlaceVersion then
			this.PlaceVersionLabel = utility:Create("TextLabel") {
				Name = "PlaceVersionLabel",
				Parent = this.VersionContainer,
				Position = UDim2.new(0.666, 3, 0, 3),
				BackgroundTransparency = 1,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = versionTextSize,
				Text = "Place Version: " .. getPlaceVersionText(),
				Size = UDim2.new(0.333, -6, 1, -6),
				Font = Enum.Font.SourceSans,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 5,
			}

			game:GetPropertyChangedSignal("PlaceVersion"):Connect(function()
				if this.PlaceVersionLabel and this.PlaceVersionLabel.Parent then
					this.PlaceVersionLabel.Text =
						"Place Version: " .. getPlaceVersionText()
				end
			end)
		end

		this.EnvironmentLabel = utility:Create("TextLabel") {
			Name = "EnvironmentLabel",
			Parent = this.VersionContainer,
			Position = UDim2.new(0.5, 0, 0, 3),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = versionTextSize,
			Text = CONTENT_BASE_URL,
			Size = UDim2.new(0.5, -6, 1, -6),
			Font = Enum.Font.SourceSans,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 5,
			Visible = isTestEnvironment,
		}

		this.Modal = utility:Create("TextButton") {
			Name = "Modal",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 1, 0),
			Modal = true,
			Text = "",
			Parent = this.Shield,
			Selectable = false,
			AutoButtonColor = false,
		}

		this.MenuContainer = utility:Create("Frame") {
			Name = "MenuContainer",
			ZIndex = this.Shield.ZIndex,
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0.95, 0, 0.95, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = this.Shield,
		}

		if FFlagEnableResponsiveUIFix then
			this.MenuListLayout = utility:Create("UIListLayout") {
				Name = "MenuListLayout",
				FillDirection = Enum.FillDirection.Vertical,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = this.MenuContainer,
			}
		end

		this.MenuAspectRatio = utility:Create("UIAspectRatioConstraint") {
			Name = "MenuAspectRatio",
			AspectRatio = 800 / 600,
			AspectType = Enum.AspectType.ScaleWithParentSize,
			-- Keep the menu's height inside the screen on desktop.
			-- The default width-dominant behavior can make it too tall.
			DominantAxis = Enum.DominantAxis.Height,
			Parent = this.MenuContainer,
		}

		this.HubBar = utility:Create("ImageLabel") {
			Name = "HubBar",
			ZIndex = this.Shield.ZIndex + 1,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(78, 84, 96),
			BackgroundTransparency = 1,
			Image = "rbxasset://textures/ui/Settings/MenuBarAssets/MenuBackground.png",
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(4, 4, 6, 6),
			AnchorPoint = Vector2.new(0.5, 0),
			LayoutOrder = 0,
			Parent = this.MenuContainer,
		}

		this.HubBarListLayout = utility:Create("UIListLayout") {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = this.HubBar,
		}

		if utility:IsSmallTouchScreen() then
			this.HubBar.Size = UDim2.new(1, -10, 0, 40)
			this.HubBar.Position = UDim2.new(0.5, 0, 0, 6)
		elseif isTenFootInterface then
			this.HubBar.Size = UDim2.new(0, 1200, 0, 100)
			this.HubBar.Position = UDim2.new(0.5, 0, 0.1, 0)
		else
			this.HubBar.Size = UDim2.new(0, 800, 0, 60)
			this.HubBar.Position = UDim2.new(0.5, 0, 0.1, 0)
		end

		this.PageViewClipper = utility:Create("Frame") {
			Name = "PageViewClipper",
			BackgroundTransparency = 1,
			Size = UDim2.new(
				this.HubBar.Size.X.Scale,
				this.HubBar.Size.X.Offset,
				1,
				-this.HubBar.Size.Y.Offset - this.HubBar.Position.Y.Offset
			),
			Position = UDim2.new(
				this.HubBar.Position.X.Scale,
				this.HubBar.Position.X.Offset,
				this.HubBar.Position.Y.Scale,
				this.HubBar.Position.Y.Offset
					+ this.HubBar.Size.Y.Offset
					+ 1
			),
			AnchorPoint = Vector2.new(0.5, 0),
			ClipsDescendants = true,
			LayoutOrder = 1,
			Parent = this.MenuContainer,
		}

		utility:Create("ImageButton") {
			Name = "InputCapture",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Image = "",
			Active = false,
			Selectable = false,
			Parent = this.PageViewClipper,
		}

		this.PageView = utility:Create("ScrollingFrame") {
			Name = "PageView",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = this.Shield.ZIndex,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Selectable = false,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollBarThickness = 8,
			Parent = this.PageViewClipper,
		}

		if FFlagSettingsHubPlayersHorizontalScroll then
			pcall(function()
				this.PageView.VerticalScrollBarInset =
					Enum.ScrollBarInset.ScrollBar
			end)
		end

		this.PageViewInnerFrame = utility:Create("Frame") {
			Name = "PageViewInnerFrame",
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = this.Shield.ZIndex,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Selectable = false,
			Parent = this.PageView,
		}

		this.BottomButtonFrame = utility:Create("Frame") {
			Name = "BottomButtonFrame",
			Size = this.HubBar.Size,
			-- Anchor the footer's bottom edge to the container's bottom edge.
			Position = UDim2.new(0.5, 0, 1, 0),
			AnchorPoint = Vector2.new(0.5, 1),
			ZIndex = this.Shield.ZIndex + 1,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Visible = false,
			Parent = this.MenuContainer,
		}

		this.BottomButtonFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if this.Visible
				and isConfirmationPage(this.Pages.CurrentPage)
				and this.BottomButtonFrame.Visible then
				this.BottomButtonFrame.Visible = false
				removeBottomBarBindings()
			end
		end)

		local leaveGameFunc = function()
			if not this.LeaveGamePage then
				setVisibilityInternal(false)
				return
			end

			if isConfirmationPage(this.Pages.CurrentPage) then
				return
			end

			this:AddToMenuStack(this.Pages.CurrentPage)
			this.HubBar.Visible = false
			removeBottomBarBindings()
			this:SwitchToPage(this.LeaveGamePage, true, 1, true)
		end

		this.OpenLeaveConfirmation = leaveGameFunc

		local inviteToGameFunc = function()
			if RunService:IsStudio() then
				return
			end

			local platformService = getServiceSafely("PlatformService")

			if platformService then
				tryMethod(platformService, "PopupGameInviteUI")
			end
		end

		local resumeFunc = function()
			setVisibilityInternal(false)
		end

		local buttonImageAppend = isTenFootInterface and "@2x" or ""

		if isXboxPlatform() then
			local function createInviteButton()
				addBottomBarButton(
					"InviteToGame",
					"Send Game Invites",
					"rbxasset://textures/ui/Settings/Help/XButtonLight"
						.. buttonImageAppend
						.. ".png",
					"",
					UDim2.new(
						0.5,
						isTenFootInterface and -160 or -130,
						0.5,
						-25
					),
					inviteToGameFunc,
					{Enum.KeyCode.ButtonX}
				)

				if RunService:IsStudio() then
					local button = this.InviteToGameButton

					if button then
						button.Selectable = false
						button.Active = false

						local enabled = button:FindFirstChild("Enabled")

						if enabled and enabled:IsA("BoolValue") then
							enabled.Value = false
						end
					end
				end
			end

			task.spawn(function()
				local platformService = getServiceSafely("PlatformService")

				if not platformService then
					return
				end

				local ok, creatorId = pcall(function()
					return platformService:BeginGetPMPCreatorId()
				end)

				if ok and creatorId == 0 then
					createInviteButton()
				end
			end)
		else
			addBottomBarButton(
				"LeaveGame",
				"Leave Game",
				"rbxasset://textures/ui/Settings/Help/XButtonLight"
					.. buttonImageAppend
					.. ".png",
				"rbxasset://textures/ui/Settings/Help/LeaveIcon.png",
				UDim2.new(
					0.5,
					isTenFootInterface and -160 or -130,
					0.5,
					-25
				),
				leaveGameFunc,
				{Enum.KeyCode.ButtonX}
			)
		end

		local resetCharFunc = function()
			if not resetEnabled or not this.ResetCharacterPage then
				return
			end

			if isConfirmationPage(this.Pages.CurrentPage) then
				return
			end

			this:AddToMenuStack(this.Pages.CurrentPage)
			this.HubBar.Visible = false
			removeBottomBarBindings()
			this:SwitchToPage(this.ResetCharacterPage, true, 1, true)
		end

		this.OpenResetConfirmation = resetCharFunc

		addBottomBarButton(
			"ResetCharacter",
			"Reset Character",
			"rbxasset://textures/ui/Settings/Help/YButtonLight"
				.. buttonImageAppend
				.. ".png",
			"rbxasset://textures/ui/Settings/Help/ResetIcon.png",
			UDim2.new(
				0.5,
				isTenFootInterface and -550 or -400,
				0.5,
				-25
			),
			resetCharFunc,
			{Enum.KeyCode.ButtonY}
		)

		addBottomBarButton(
			"Resume",
			"Resume Game",
			"rbxasset://textures/ui/Settings/Help/BButtonLight"
				.. buttonImageAppend
				.. ".png",
			"rbxasset://textures/ui/Settings/Help/EscapeIcon.png",
			UDim2.new(
				0.5,
				isTenFootInterface and 200 or 140,
				0.5,
				-25
			),
			resumeFunc,
			{Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonStart}
		)

		local function onViewportChanged()
			utility:FireOnResized()

			-- Reuse the same container-relative layout code as the regular
			-- resize signal. Viewport dimensions are not child-local pixels.
			task.defer(function()
				if not this.MenuContainer
					or not this.MenuContainer.Parent
					or not this.PageViewClipper then
					return
				end

				if onScreenSizeChanged then
					onScreenSizeChanged()
				end

				enforcePageChrome(this.Pages.CurrentPage)
			end)
		end

		local function connectCamera(camera)
			if viewportConnection then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end

			if camera then
				viewportConnection =
					camera:GetPropertyChangedSignal("ViewportSize")
					:Connect(onViewportChanged)
			end

			onViewportChanged()
		end

		connectCamera(workspace.CurrentCamera)

		if cameraChangedConnection then
			cameraChangedConnection:Disconnect()
		end

		cameraChangedConnection =
			workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				connectCamera(workspace.CurrentCamera)
			end)
	end

	local function setMenuAspectRatioEnabled(enabled)
		local constraint = this.MenuAspectRatio
		local container = this.MenuContainer

		if not constraint or not container then
			return
		end

		-- UIAspectRatioConstraint does not have an Enabled property.
		-- A height-dominant ratio prevents the 4:3 menu growing below the
		-- screen when the viewport is wide.
		pcall(function()
			constraint.DominantAxis = Enum.DominantAxis.Height
		end)

		local targetParent = enabled and container or nil

		if constraint.Parent == targetParent then
			return
		end

		local ok, err = pcall(function()
			constraint.Parent = targetParent
		end)

		if not ok then
			warn(
				"[SettingsHub] Could not update MenuAspectRatio parent: "
					.. tostring(err)
			)
		end
	end

	----------------------------------------------------------------------
	-- SHARED PAGE CLIPPER LAYOUT
	--
	-- All measurements below are relative to MenuContainer. RobloxGui's
	-- viewport height must never be used as the height of a child frame
	-- inside this aspect-ratio-constrained container.
	----------------------------------------------------------------------

	local function updatePageClipperLayout()
		local menu = this.MenuContainer
		local hubBar = this.HubBar
		local clipper = this.PageViewClipper
		local bottomBar = this.BottomButtonFrame
		local pageView = this.PageView

		if not menu
			or not menu.Parent
			or not hubBar
			or not clipper
			or not bottomBar
			or not pageView then
			return false
		end

		local menuSize = menu.AbsoluteSize
		local menuPosition = menu.AbsolutePosition

		if menuSize.X < 2 or menuSize.Y < 2 then
			return false
		end

		local pageTop = 12

		if hubBar.Visible then
			local hubTop =
				hubBar.AbsolutePosition.Y - menuPosition.Y

			local hubHeight = hubBar.AbsoluteSize.Y

			if hubHeight < 1 then
				hubHeight = hubBar.Size.Y.Offset
				hubTop =
					menuSize.Y * hubBar.Position.Y.Scale
					+ hubBar.Position.Y.Offset
			end

			pageTop = math.max(
				pageTop,
				hubTop + hubHeight + 8
			)
		end

		-- Leave a small bottom margin. If the footer is visible, use its
		-- measured top edge instead of guessing its height from the viewport.
		local pageBottom = menuSize.Y - 12

		if bottomBar.Visible then
			local footerTop =
				bottomBar.AbsolutePosition.Y - menuPosition.Y

			local footerHeight = bottomBar.AbsoluteSize.Y

			if footerHeight > 0 then
				pageBottom = math.min(
					pageBottom,
					footerTop - 8
				)
			end
		end

		-- If the window is unusually short, shrink the page area rather than
		-- allowing it to extend underneath the footer.
		if pageBottom <= pageTop then
			pageTop = math.max(
				8,
				math.min(pageTop, pageBottom - 1)
			)
		end

		local pageHeight = math.max(
			1,
			math.floor(pageBottom - pageTop)
		)

		local pageWidth = hubBar.AbsoluteSize.X

		if pageWidth < 1 then
			pageWidth =
				hubBar.Size.X.Scale * menuSize.X
				+ hubBar.Size.X.Offset
		end

		pageWidth = math.max(
			1,
			math.min(menuSize.X - 16, pageWidth)
		)

		clipper.AnchorPoint = Vector2.new(0.5, 0)
		clipper.Position = UDim2.new(
			0.5,
			0,
			0,
			math.floor(pageTop + 0.5)
		)
		clipper.Size = UDim2.new(
			0,
			math.floor(pageWidth + 0.5),
			0,
			pageHeight
		)
		clipper.ClipsDescendants = true

		-- Fill the entire clipped rectangle without leaving the old 10-pixel
		-- inset at the bottom of PageView.
		pageView.AnchorPoint = Vector2.new(0.5, 0.5)
		pageView.Position = UDim2.new(0.5, 0, 0.5, 0)
		pageView.Size = UDim2.new(1, 0, 1, 0)

		return true
	end

	onScreenSizeChanged = function()
		if not this.MenuContainer
			or not this.HubBar
			or not this.PageViewClipper
			or not this.PageView
			or not this.BottomButtonFrame then
			return
		end

		local viewport = getRootSize()
		local width = viewport.X

		local portrait = utility:IsPortrait()
		local smallTouch = utility:IsSmallTouchScreen()

		local hubHeight

		-- Keep the entire settings menu centered.
		this.MenuContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		this.MenuContainer.Position = UDim2.new(0.5, 0, 0.5, 0)

		if portrait then
			-- Portrait layout.
			this.MenuContainer.Size = UDim2.new(1, 0, 1, 0)
			setMenuAspectRatioEnabled(false)

			hubHeight = 40

			this.HubBar.Size = UDim2.new(1, -20, 0, hubHeight)
			this.HubBar.Position = UDim2.new(0.5, 0, 0, 10)

		elseif isTenFootInterface then
			-- TV / ten-foot layout.
			this.MenuContainer.Size = UDim2.new(0.95, 0, 0.95, 0)
			setMenuAspectRatioEnabled(true)

			hubHeight = 100

			this.HubBar.Size = UDim2.new(
				0,
				math.max(1, math.min(1200, width - 40)),
				0,
				hubHeight
			)

			this.HubBar.Position = UDim2.new(0.5, 0, 0.1, 0)

		elseif smallTouch then
			-- Small touchscreen layout.
			this.MenuContainer.Size = UDim2.new(1, 0, 0.99, 0)
			setMenuAspectRatioEnabled(false)

			hubHeight = 40

			this.HubBar.Size = UDim2.new(1, -10, 0, hubHeight)
			this.HubBar.Position = UDim2.new(0.5, 0, 0, 6)

		else
			-- PC: restore the original responsive height and 4:3 menu ratio.
			-- Do not use a fixed 800x600 container or a calculated pixel height.
			this.MenuContainer.Size = UDim2.new(0.95, 0, 0.95, 0)
			setMenuAspectRatioEnabled(true)

			hubHeight = 60

			this.HubBar.Size = UDim2.new(
				0,
				math.max(1, math.min(800, width - 40)),
				0,
				hubHeight
			)

			this.HubBar.Position = UDim2.new(0.5, 0, 0.1, 0)
		end

		-- Preserve the original footer geometry. Its bottom edge sits above
		-- the bottom of MenuContainer; don't move it to the container's edge.
		this.BottomButtonFrame.Size = this.HubBar.Size
		this.BottomButtonFrame.AnchorPoint = Vector2.new(0.5, 1)

		this.BottomButtonFrame.Position = UDim2.new(
			0.5,
			0,
			1,
			-hubHeight - (portrait and 5 or 0)
		)

		-- Apply visibility for the current page before measuring the space.
		-- Leave/Reset hide the header and footer; regular pages may show both.
		enforcePageChrome(this.Pages.CurrentPage)

		local function recalculate()
			if not this.MenuContainer
				or not this.MenuContainer.Parent
				or not this.PageViewClipper
				or not this.PageView then
				return
			end

			updatePageClipperLayout()
		end

		-- Immediate layout, followed by measurements after Roblox updates
		-- AbsoluteSize and AbsolutePosition for the container and footer.
		recalculate()

		task.defer(function()
			if not this.MenuContainer or not this.MenuContainer.Parent then
				return
			end

			enforcePageChrome(this.Pages.CurrentPage)
			recalculate()

			task.defer(function()
				if not this.MenuContainer or not this.MenuContainer.Parent then
					return
				end

				enforcePageChrome(this.Pages.CurrentPage)
				recalculate()
			end)
		end)
	end
	local function scrollPixels(pixels)
		local maxY = math.max(
			0,
			this.PageView.CanvasSize.Y.Offset
			- this.PageView.AbsoluteSize.Y
		)

		this.PageView.CanvasPosition = Vector2.new(
			0,
			math.clamp(
				this.PageView.CanvasPosition.Y + pixels,
				0,
				maxY
			)
		)
	end

	function this:ScrollPixels(pixels)
		scrollPixels(pixels)
	end

	function this:ScrollToFrame(frame, forced)
		if not frame or not frame:IsA("GuiObject") then
			return
		end

		local inputType = getLastInputType()
		local gamepadLast =
			tostring(inputType):find("Gamepad", 1, true) ~= nil

		if not (gamepadLast or forced) then
			return
		end

		local page = self.Pages.CurrentPage

		if not page or not page.Page then
			return
		end

		local top =
			frame.AbsolutePosition.Y - page.Page.AbsolutePosition.Y

		local bottom = top + frame.AbsoluteSize.Y
		local currentY = self.PageView.CanvasPosition.Y

		if top < currentY then
			self.PageView.CanvasPosition =
				Vector2.new(0, math.max(0, top))
		elseif bottom - currentY > self.PageViewClipper.AbsoluteSize.Y then
			self.PageView.CanvasPosition = Vector2.new(
				0,
				math.max(
					0,
					bottom - self.PageViewClipper.AbsoluteSize.Y
				)
			)
		end
	end

	GetHeaderPosition = function(page)
		if not page then
			return -1
		end

		local header

		pcall(function()
			header = page:GetTabHeader()
		end)

		header = header or page.TabHeader

		if not header then
			return -1
		end

		for index, tab in ipairs(this.TabHeaders) do
			if tab == header then
				return index
			end
		end

		return -1
	end

	local function setZIndex(zIndex, object)
		if not object or not object:IsA("GuiObject") then
			return
		end

		object.ZIndex = zIndex

		for _, child in ipairs(object:GetChildren()) do
			setZIndex(zIndex, child)
		end
	end

	local function addHeader(header, page)
		if not header or not header:IsA("GuiObject") then
			return
		end

		if table.find(this.TabHeaders, header) then
			return
		end

		local parented, parentError = pcall(function()
			header.Parent = this.HubBar
		end)

		if not parented then
			page.TabPosition = nil

			warn(
				"[SettingsHub] Skipping unusable tab header for "
					.. tostring(page.Page and page.Page.Name or "page")
					.. ": "
					.. tostring(parentError)
			)

			return
		end

		table.insert(this.TabHeaders, header)
		page.TabPosition = #this.TabHeaders

		local widthScale = 1 / #this.TabHeaders

		for index, tab in ipairs(this.TabHeaders) do
			tab.Size = UDim2.new(widthScale, 0, 1, 0)
			tab.LayoutOrder = index
		end

		alignTabHeaderMetrics(header)

		setZIndex(SETTINGS_BASE_ZINDEX + 1, header)
	end

	local function removeHeader(header)
		if not header then
			return
		end

		local removedIndex

		for index, tab in ipairs(this.TabHeaders) do
			if tab == header then
				removedIndex = index
				table.remove(this.TabHeaders, index)
				break
			end
		end

		if removedIndex then
			local newWidth =
				#this.TabHeaders > 0 and (1 / #this.TabHeaders) or 1

			for index, tab in ipairs(this.TabHeaders) do
				tab.Size = UDim2.new(newWidth, 0, 1, 0)
				tab.LayoutOrder = index
			end
		end

		pcall(function()
			header.Parent = nil
		end)
	end

	function this:AddPage(page)
		if not page then
			return false
		end

		self.Pages.PageTable[page] = true

		local ok, header = pcall(function()
			return page:GetTabHeader()
		end)

		if not ok or not header then
			header = page.TabHeader
		end

		addHeader(header, page)

		if page.Page and page.TabPosition then
			page.Page.Position =
				UDim2.new(page.TabPosition - 1, 0, 0, 0)
		end

		if type(page.SetHub) == "function" then
			tryMethod(page, "SetHub", self)
		end

		return true
	end

	function this:RemovePage(page)
		if not page then
			return
		end

		self.Pages.PageTable[page] = nil

		local header

		pcall(function()
			header = page:GetTabHeader()
		end)

		header = header or page.TabHeader

		removeHeader(header)

		if self.Pages.CurrentPage == page then
			self.Pages.CurrentPage = nil
		end
	end

	function this:HideBar()
		if this.HubBar then
			this.HubBar.Visible = false
		end

		if this.PageViewClipper then
			this.PageViewClipper.Visible = false
		end

		if this.BottomButtonFrame then
			this.BottomButtonFrame.Visible = false
		end

		removeBottomBarBindings()
	end

	function this:ShowBar()
		local currentPage = self.Pages.CurrentPage

		if this.HubBar then
			this.HubBar.Visible = shouldShowHubBar(currentPage)
		end

		if this.PageViewClipper then
			this.PageViewClipper.Visible = true
			this.PageViewClipper.ClipsDescendants = true
		end

		if this.Visible and shouldShowBottomBar(currentPage) then
			setBottomBarBindings()
		else
			removeBottomBarBindings()
		end

		if this.BottomButtonFrame then
			this.BottomButtonFrame.Visible =
				this.Visible and shouldShowBottomBar(currentPage)
		end

		if onScreenSizeChanged then
			task.defer(onScreenSizeChanged)
		end
	end

	local function getPageSize(page)
		local ok, size = tryMethod(page, "GetSize")

		if ok and typeof(size) == "Vector2" then
			return size
		end

		if page and page.Page then
			return Vector2.new(
				page.Page.AbsoluteSize.X,
				page.Page.AbsoluteSize.Y
			)
		end

		return Vector2.new(0, 0)
	end

	function this:SwitchToPage(
		pageToSwitchTo,
		ignoreStack,
		direction,
		skipAnimation
	)
		if not pageToSwitchTo
			or self.Pages.PageTable[pageToSwitchTo] == nil then
			return false
		end

		local oldPage = self.Pages.CurrentPage

		if oldPage == pageToSwitchTo then
			forceHideInactiveConfirmationPages(pageToSwitchTo)
			enforcePageChrome(pageToSwitchTo)

			if onScreenSizeChanged then
				task.defer(onScreenSizeChanged)
			end

			return true
		end

		if direction == nil then
			local oldHeader, newHeader

			if oldPage then
				pcall(function()
					oldHeader = oldPage:GetTabHeader()
				end)
			end

			pcall(function()
				newHeader = pageToSwitchTo:GetTabHeader()
			end)

			oldHeader = oldHeader or (oldPage and oldPage.TabHeader)
			newHeader = newHeader or pageToSwitchTo.TabHeader

			if oldHeader and newHeader then
				direction =
					oldHeader.AbsolutePosition.X
					< newHeader.AbsolutePosition.X
					and 1
					or -1
			else
				direction = 1
			end
		end

		if oldPage then
			if pageChangeConnection then
				pageChangeConnection:Disconnect()
				pageChangeConnection = nil
			end

			oldPage.Active = false

			if not ignoreStack
				and self.MenuStack[#self.MenuStack] ~= oldPage then
				table.insert(self.MenuStack, oldPage)
			end
		end

		for page in pairs(self.Pages.PageTable) do
			if page ~= pageToSwitchTo then
				tryMethod(
					page,
					"Hide",
					-direction,
					pageToSwitchTo.TabPosition or 1,
					skipAnimation
				)
			end
		end

		forceHideInactiveConfirmationPages(pageToSwitchTo)

		self.Pages.CurrentPage = pageToSwitchTo

		local isConfirmation = isConfirmationPage(pageToSwitchTo)

		if self.BottomButtonFrame then
			self.BottomButtonFrame.Visible =
				self.Visible and shouldShowBottomBar(pageToSwitchTo)
		end

		if not shouldShowBottomBar(pageToSwitchTo) then
			removeBottomBarBindings()
		elseif self.Visible then
			setBottomBarBindings()
		end

		local clipped =
			FFlagSettingsHubBarsRefactor
			and pageToSwitchTo.IsPageClipped == true

		if FFlagSettingsHubBarsRefactor then
			-- Keep the OUTER clipper enabled regardless of page flags.
			-- Individual pages may retain their inner clipping behavior, but
			-- must never render through the shared footer boundary.
			self.PageViewClipper.ClipsDescendants = true
			self.PageView.ClipsDescendants = clipped
			self.PageViewInnerFrame.ClipsDescendants = clipped
		else
			self.PageViewClipper.ClipsDescendants = true
		end

		self.HubBar.Visible = shouldShowHubBar(pageToSwitchTo)
		self.PageViewClipper.Visible = true
		self.PageView.Visible = true
		self.PageViewInnerFrame.Visible = true

		if isConfirmation then
			self.PageView.CanvasPosition = Vector2.new(0, 0)
			self.PageViewInnerFrame.Position = UDim2.new(0, 0, 0, 0)
		end

		local displayOk, displayError = tryMethod(
			pageToSwitchTo,
			"Display",
			self.PageViewInnerFrame,
			skipAnimation
		)

		if not displayOk then
			warn(
				"[SettingsHub] Display failed for "
					.. tostring(
						pageToSwitchTo.Page
						and pageToSwitchTo.Page.Name
						or "page"
					)
					.. ": "
					.. tostring(displayError)
			)
		end

		if isConfirmation
			and pageToSwitchTo.Page
			and pageToSwitchTo.Page:IsA("GuiObject") then
			local pageGui = pageToSwitchTo.Page

			if pageGui.Parent ~= self.PageViewInnerFrame then
				local parentOk, parentError = pcall(function()
					pageGui.Parent = self.PageViewInnerFrame
				end)

				if not parentOk then
					warn(
						"[SettingsHub] Could not attach confirmation page "
							.. pageGui.Name
							.. ": "
							.. tostring(parentError)
					)
				end
			end

			pcall(function()
				pageGui.Position = UDim2.new(0, 0, 0, 0)
				pageGui.Visible = true
				pageGui.Active = self.Active
			end)

			self.PageView.CanvasPosition = Vector2.new(0, 0)
		end

		forceHideInactiveConfirmationPages(pageToSwitchTo)

		pageToSwitchTo.Active = self.Active

		enforcePageChrome(pageToSwitchTo)

		-- Recalculate after Display has finished manipulating its page GUI.
		task.defer(function()
			if self.Pages.CurrentPage ~= pageToSwitchTo then
				return
			end

			forceHideInactiveConfirmationPages(pageToSwitchTo)
			enforcePageChrome(pageToSwitchTo)

			if onScreenSizeChanged then
				onScreenSizeChanged()
			else
				updatePageClipperLayout()
			end
		end)

		local size = getPageSize(pageToSwitchTo)

		if isConfirmation and pageToSwitchTo.Page then
			size = Vector2.new(
				math.max(
					size.X,
					pageToSwitchTo.Page.AbsoluteSize.X,
					pageToSwitchTo.Page.Size.X.Offset
				),
				math.max(
					size.Y,
					pageToSwitchTo.Page.AbsoluteSize.Y,
					pageToSwitchTo.Page.Size.Y.Offset
				)
			)
		end

		self.PageView.CanvasSize = UDim2.new(
			0,
			math.max(0, size.X),
			0,
			math.max(0, size.Y)
		)

		if not FFlagSettingsHubPlayersHorizontalScroll then
			if self.PageView.CanvasSize.Y.Offset
				> self.PageView.AbsoluteSize.Y then
				self.PageViewInnerFrame.Size =
					UDim2.new(1, -self.PageView.ScrollBarThickness, 1, 0)
			else
				self.PageViewInnerFrame.Size = UDim2.new(1, 0, 1, 0)
			end
		end

		if pageToSwitchTo.Page
			and pageToSwitchTo.Page:IsA("GuiObject") then
			pageChangeConnection =
				pageToSwitchTo.Page:GetPropertyChangedSignal("AbsoluteSize")
				:Connect(function()
					if self.Pages.CurrentPage ~= pageToSwitchTo then
						return
					end

					local newSize = getPageSize(pageToSwitchTo)

					self.PageView.CanvasSize = UDim2.new(
						0,
						math.max(0, newSize.X),
						0,
						math.max(0, newSize.Y)
					)
				end)
		end

		return true
	end

	function this:SetActive(active)
		self.Active = active == true

		if self.Pages.CurrentPage then
			self.Pages.CurrentPage.Active = self.Active
		end
	end

	function this:AddToMenuStack(item)
		if item and self.MenuStack[#self.MenuStack] ~= item then
			table.insert(self.MenuStack, item)
		end
	end

	function this:PopMenu(switchedFromGamepadInput, skipAnimation)
		if #self.MenuStack > 0 then
			local previous = table.remove(self.MenuStack)

			PoppedMenuEvent:Fire(previous)

			if previous and self.Pages.PageTable[previous] then
				self:SwitchToPage(previous, true, 1, skipAnimation)
			elseif #self.MenuStack > 0
				and self.Pages.PageTable[self.MenuStack[#self.MenuStack]] then
				self:SwitchToPage(
					self.MenuStack[#self.MenuStack],
					true,
					1,
					skipAnimation
				)
			else
				table.clear(self.MenuStack)
				self:SetVisibility(false, skipAnimation)
			end
		else
			PoppedMenuEvent:Fire()
			self:SetVisibility(false, skipAnimation)
		end
	end

	function this:ClearMenuStack()
		table.clear(self.MenuStack)
	end

	function this:ShowShield()
		self.Shield.BackgroundTransparency =
			VRService.VREnabled
			and SETTINGS_SHIELD_VR_TRANSPARENCY
			or SETTINGS_SHIELD_TRANSPARENCY
	end

	function this:HideShield()
		self.Shield.BackgroundTransparency = 1
	end

	local function switchTab(direction, cycle)
		local currentPosition =
			GetHeaderPosition(this.Pages.CurrentPage)

		if currentPosition < 1 or #this.TabHeaders == 0 then
			return
		end

		local newPosition = currentPosition + direction

		if cycle then
			if newPosition > #this.TabHeaders then
				newPosition = 1
			elseif newPosition < 1 then
				newPosition = #this.TabHeaders
			end
		end

		local header = this.TabHeaders[newPosition]

		if not header then
			return
		end

		for page in pairs(this.Pages.PageTable) do
			local pageHeader

			pcall(function()
				pageHeader = page:GetTabHeader()
			end)

			pageHeader = pageHeader or page.TabHeader

			if pageHeader == header then
				this:SwitchToPage(page, false, direction)
				return
			end
		end
	end

	local function switchTabFromBumpers(_, inputState, inputObject)
		if inputState ~= Enum.UserInputState.Begin or not inputObject then
			return Enum.ContextActionResult.Pass
		end

		if inputObject.KeyCode == Enum.KeyCode.ButtonR1 then
			switchTab(1, true)
		elseif inputObject.KeyCode == Enum.KeyCode.ButtonL1 then
			switchTab(-1, true)
		end

		return Enum.ContextActionResult.Sink
	end

	local function switchTabFromKeyboard(input)
		if not this.Visible or input.KeyCode ~= Enum.KeyCode.Tab then
			return
		end

		local shiftDown =
			UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

		switchTab(shiftDown and -1 or 1, true)
	end

	local function scrollHotkey(_, inputState, inputObject)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		if inputObject.KeyCode == Enum.KeyCode.PageUp then
			scrollPixels(-100)
		elseif inputObject.KeyCode == Enum.KeyCode.PageDown then
			scrollPixels(100)
		end

		return Enum.ContextActionResult.Sink
	end

	local function toggleQuickProfilerFromHotkey(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or not this.Visible then
			return Enum.ContextActionResult.Pass
		end

		local controlDown =
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if controlDown then
			pcall(function()
				local settingsObject = UserSettings()
				local gameSettings = settingsObject.GameSettings

				gameSettings.PerformanceStatsVisible =
					not gameSettings.PerformanceStatsVisible
			end)
		end

		return Enum.ContextActionResult.Sink
	end

	local function toggleDevConsole(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		if FFlagEnableNewDevConsole and DevConsoleMaster then
			tryMethod(DevConsoleMaster, "ToggleVisibility")
		elseif DeveloperConsoleModule then
			local ok, visible =
				tryMethod(DeveloperConsoleModule, "GetVisibility")

			if ok then
				tryMethod(
					DeveloperConsoleModule,
					"SetVisibility",
					not visible
				)
			end
		end

		return Enum.ContextActionResult.Sink
	end

	----------------------------------------------------------------------
	-- L/R CONFIRMATION HOTKEYS
	----------------------------------------------------------------------

	local function hasFocusedTextBox()
		local focusedTextBox

		pcall(function()
			focusedTextBox = UserInputService:GetFocusedTextBox()
		end)

		return focusedTextBox ~= nil
	end

	local function requestConfirmation(openMethodName)
		if not this.Visible or not this.Active then
			return false
		end

		if hasFocusedTextBox() then
			return false
		end

		if isConfirmationPage(this.Pages.CurrentPage) then
			return false
		end

		local callback = this[openMethodName]

		if type(callback) ~= "function" then
			return false
		end

		callback()
		return true
	end

	local function makeConfirmationHotkey(openMethodName)
		return function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			if not this.Visible or not this.Active then
				return Enum.ContextActionResult.Pass
			end

			if isConfirmationPage(this.Pages.CurrentPage) then
				return Enum.ContextActionResult.Sink
			end

			if hasFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end

			requestConfirmation(openMethodName)

			return Enum.ContextActionResult.Sink
		end
	end

	local function bindConfirmationHotkeys()
		bindAction(
			LEAVE_KEY_ACTION_NAME,
			makeConfirmationHotkey("OpenLeaveConfirmation"),
			false,
			Enum.KeyCode.L
		)

		bindAction(
			RESET_KEY_ACTION_NAME,
			makeConfirmationHotkey("OpenResetConfirmation"),
			false,
			Enum.KeyCode.R
		)
	end

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if input.KeyCode ~= Enum.KeyCode.L
			and input.KeyCode ~= Enum.KeyCode.R then
			return
		end

		if not this.Visible or not this.Active then
			return
		end

		if hasFocusedTextBox() then
			return
		end

		if isConfirmationPage(this.Pages.CurrentPage) then
			return
		end

		if input.KeyCode == Enum.KeyCode.L then
			requestConfirmation("OpenLeaveConfirmation")
		elseif input.KeyCode == Enum.KeyCode.R then
			requestConfirmation("OpenResetConfirmation")
		end
	end)

	local lastInputUsedToSelectGui = isTenFootInterface

	local inputUsedToSelectGui = {
		[Enum.UserInputType.Gamepad1] = true,
		[Enum.UserInputType.Gamepad2] = true,
		[Enum.UserInputType.Gamepad3] = true,
		[Enum.UserInputType.Gamepad4] = true,

		[Enum.KeyCode.Left] = true,
		[Enum.KeyCode.Right] = true,
		[Enum.KeyCode.Up] = true,
		[Enum.KeyCode.Down] = true,
		[Enum.KeyCode.Tab] = true,

		[Enum.UserInputType.Touch] = false,
		[Enum.UserInputType.MouseButton1] = false,
		[Enum.UserInputType.MouseButton2] = false,
		[Enum.UserInputType.MouseMovement] = false,
	}

	UserInputService.InputBegan:Connect(function(input)
		local typeValue = inputUsedToSelectGui[input.UserInputType]

		if typeValue ~= nil then
			lastInputUsedToSelectGui = typeValue
		elseif inputUsedToSelectGui[input.KeyCode] ~= nil then
			lastInputUsedToSelectGui =
				inputUsedToSelectGui[input.KeyCode]
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1
			or input.KeyCode == Enum.KeyCode.Thumbstick2 then
			if input.Position.Magnitude >= 0.25 then
				lastInputUsedToSelectGui = true
			end
		elseif input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseMovement then
			lastInputUsedToSelectGui = false
		end
	end)

	function this:SetVisibility(
		visible,
		noAnimation,
		customStartPage,
		switchedFromGamepadInput
	)
		if self.Visible == (visible == true) then
			forceHideInactiveConfirmationPages(self.Pages.CurrentPage)
			enforcePageChrome(self.Pages.CurrentPage)
			return
		end

		setVisibilityInternal(
			visible,
			noAnimation,
			customStartPage,
			switchedFromGamepadInput
		)
	end

	function this:GetVisibility()
		return self.Visible
	end

	function this:ToggleVisibility(switchedFromGamepadInput)
		setVisibilityInternal(
			not self.Visible,
			nil,
			nil,
			switchedFromGamepadInput
		)
	end

	setVisibilityInternal = function(
		visible,
		noAnimation,
		customStartPage,
		switchedFromGamepadInput
	)
		local self = this

		visible = visible == true

		if self.Visible == visible then
			return
		end

		self.OpenStateChangedCount += 1
		self.Visible = visible

		if self.ResizedConnection then
			self.ResizedConnection:Disconnect()
			self.ResizedConnection = nil
		end

		if self.TabConnection then
			self.TabConnection:Disconnect()
			self.TabConnection = nil
		end

		if self.Modal then
			self.Modal.Visible = visible
		end

		if visible then
			self.ResizedConnection =
				RobloxGui:GetPropertyChangedSignal("AbsoluteSize")
				:Connect(function()
					if onScreenSizeChanged then
						onScreenSizeChanged()
					end
				end)

			onScreenSizeChanged()

			fireSignal(self.SettingsShowSignal, true)
			setMenuOpenState(true)

			self.Shield.Visible = true

			if noAnimation then
				if activeShieldTween then
					pcall(function()
						activeShieldTween:Cancel()
					end)

					activeShieldTween = nil
				end

				self.Shield.Position = SETTINGS_SHIELD_ACTIVE_POSITION
			else
				tweenShieldPosition(
					SETTINGS_SHIELD_ACTIVE_POSITION,
					SETTINGS_OPEN_TWEEN_DURATION,
					Enum.EasingDirection.InOut,
					Enum.EasingStyle.Quart
				)
			end

			local function sinkCharacterActions()
				return Enum.ContextActionResult.Sink
			end

			bindAction(
				"RbxSettingsHubStopCharacter",
				sinkCharacterActions,
				false,
				Enum.KeyCode.W,
				Enum.KeyCode.A,
				Enum.KeyCode.S,
				Enum.KeyCode.D,
				Enum.KeyCode.Space,
				Enum.KeyCode.LeftShift,
				Enum.KeyCode.RightShift,
				Enum.KeyCode.Tab,
				Enum.UserInputType.Gamepad1,
				Enum.UserInputType.Gamepad2,
				Enum.UserInputType.Gamepad3,
				Enum.UserInputType.Gamepad4
			)

			bindAction(
				"RbxSettingsHubSwitchTab",
				switchTabFromBumpers,
				false,
				Enum.KeyCode.ButtonR1,
				Enum.KeyCode.ButtonL1
			)

			bindAction(
				"RbxSettingsScrollHotkey",
				scrollHotkey,
				false,
				Enum.KeyCode.PageUp,
				Enum.KeyCode.PageDown
			)

			bindAction(
				DEV_CONSOLE_ACTION_NAME,
				toggleDevConsole,
				false,
				Enum.KeyCode.F9
			)

			bindAction(
				QUICK_PROFILER_ACTION_NAME,
				toggleQuickProfilerFromHotkey,
				false,
				Enum.KeyCode.F7
			)

			local page = customStartPage

			if not page then
				if not isTenFootInterface and self.PlayersPage then
					page = self.PlayersPage
				elseif self.HomePage then
					page = self.HomePage
				else
					page = self.GameSettingsPage
				end
			end

			if page and self.Pages.PageTable[page] then
				self:SwitchToPage(page, true, 1, true)
			else
				warn(
					"[SettingsHub] No registered page is available "
						.. "for the requested open page"
				)
			end

			bindConfirmationHotkeys()

			enforcePageChrome(self.Pages.CurrentPage)

			hideTempPlayerList(true)

			if getChatVisible() then
				self.ChatWasVisible = true
				toggleChatVisibility()
			end

			if BackpackScript then
				local isOpen = getProperty(BackpackScript, "IsOpen", false)

				if isOpen then
					tryMethod(BackpackScript, "OpenClose")
				end
			end
		else
			forceHideConfirmationPage(self.LeaveGamePage)
			forceHideConfirmationPage(self.ResetCharacterPage)

			if self.LeaveGamePage then
				tryMethod(
					self.LeaveGamePage,
					"Hide",
					-1,
					self.LeaveGamePage.TabPosition or 1,
					true
				)

				forceHideConfirmationPage(self.LeaveGamePage)
			end

			if self.ResetCharacterPage then
				tryMethod(
					self.ResetCharacterPage,
					"Hide",
					-1,
					self.ResetCharacterPage.TabPosition or 1,
					true
				)

				forceHideConfirmationPage(self.ResetCharacterPage)
			end

			if self.BottomButtonFrame then
				self.BottomButtonFrame.Visible = false
			end

			fireSignal(self.SettingsShowSignal, false)

			if noAnimation then
				if activeShieldTween then
					pcall(function()
						activeShieldTween:Cancel()
					end)

					activeShieldTween = nil
				end

				self.Shield.Position = SETTINGS_SHIELD_INACTIVE_POSITION
				self.Shield.Visible = false

				setMenuOpenState(false)
			else
				tweenShieldPosition(
					SETTINGS_SHIELD_INACTIVE_POSITION,
					SETTINGS_CLOSE_TWEEN_DURATION,
					Enum.EasingDirection.In,
					Enum.EasingStyle.Quart,
					function()
						if not self.Visible
							and self.Shield
							and self.Shield.Parent then
							self.Shield.Visible = false
							setMenuOpenState(false)
						end
					end
				)
			end

			hideTempPlayerList(false)

			if self.ChatWasVisible then
				toggleChatVisibility()
				self.ChatWasVisible = false
			end

			if not VRService.VREnabled then
				setMouseIconBehavior("None")
			end

			table.clear(self.MenuStack)

			unbindAction(LEAVE_KEY_ACTION_NAME)
			unbindAction(RESET_KEY_ACTION_NAME)
			unbindAction("RbxSettingsHubSwitchTab")
			unbindAction("RbxSettingsHubStopCharacter")
			unbindAction("RbxSettingsScrollHotkey")
			unbindAction(DEV_CONSOLE_ACTION_NAME)
			unbindAction(QUICK_PROFILER_ACTION_NAME)

			removeBottomBarBindings(0.3)

			setSelectedObject(nil)
		end
	end

	local function onVREnabled()
		if VRService.VREnabled then
			local panelModule =
				findPath(RobloxGui, {"Modules", "VR", "Panel3D"})

			local Panel3D =
				requireSafely(panelModule, "VR.Panel3D")

			if Panel3D and type(Panel3D.Get) == "function" then
				local ok, panel = pcall(Panel3D.Get, "SettingsMenu")

				if ok and panel then
					tryMethod(panel, "ResizeStuds", 4, 4, 250)

					pcall(function()
						panel:SetType(Panel3D.Type.Standard)
					end)

					tryMethod(panel, "SetVisible", false)
					tryMethod(panel, "SetCanFade", false)

					pcall(function()
						this.ClippingShield.Parent = panel:GetGUI()
					end)

					this.VRShield.Visible = true
					this:HideShield()
					this.VRPanel = panel
				end
			end
		else
			if this.ClippingShield and this.ClippingShield.Parent then
				this.ClippingShield.Parent = RobloxGui
			end

			if this.VRShield then
				this.VRShield.Visible = false
			end

			if this.Shield then
				this:ShowShield()
			end

			if this.VRPanel then
				tryMethod(this.VRPanel, "SetVisible", false)
			end

			this.VRPanel = nil
		end
	end

	makeGui()

	onScreenSizeChanged()

	VRService:GetPropertyChangedSignal("VREnabled"):Connect(onVREnabled)

	onVREnabled()

	local function setHubForPage(page)
		if page then
			this:AddPage(page)
		end
	end

	setHubForPage(this.PlayersPage)
	setHubForPage(this.ResetCharacterPage)
	setHubForPage(this.LeaveGamePage)
	setHubForPage(this.GameSettingsPage)
	setHubForPage(this.ReportAbusePage)
	setHubForPage(this.HelpPage)
	setHubForPage(this.RecordPage)

	if not this.PlayersPage and this.HomePage then
		setHubForPage(this.HomePage)
	end

	for _, confirmationPage in ipairs({
		this.LeaveGamePage,
		this.ResetCharacterPage,
		}) do
		local confirmationGui =
			confirmationPage and confirmationPage.Page

		if confirmationGui and confirmationGui:IsA("GuiObject") then
			confirmationGui:GetPropertyChangedSignal("Visible"):Connect(function()
				if this.Pages.CurrentPage ~= confirmationPage
					and confirmationGui.Visible then
					forceHideConfirmationPage(confirmationPage)
				end
			end)
		end
	end

	if shareGameEnabled and CorePackages and SettingsModules then
		local function packagesLoaded()
			for _, name in ipairs({"Roact", "Rodux", "RoactRodux"}) do
				if not CorePackages:FindFirstChild(name) then
					return false
				end
			end

			return true
		end

		if packagesLoaded() then
			local shareGameMaster =
				loadModule({"Modules", "Settings", "ShareGameMaster"})

			if shareGameMaster
				and type(shareGameMaster.createApp) == "function" then
				local ok, app = pcall(
					shareGameMaster.createApp,
					this.PageViewClipper
				)

				if ok and app then
					this.ShareGameApp = app

					local placeholder =
						createPage({
							"Modules",
							"Settings",
							"Pages",
							"ShareGamePlaceholderPage",
						})

					if placeholder then
						tryMethod(
							placeholder,
							"ConnectHubToApp",
							this,
							app
						)

						setHubForPage(placeholder)

						this.ShareGamePage = placeholder
					end
				end
			end
		end
	end

	local StarterGui = getServiceSafely("StarterGui")

	if StarterGui then
		pcall(function()
			StarterGui:RegisterSetCore(
				"ResetButtonCallback",
				function(callback)
					local isBindableEvent =
						typeof(callback) == "Instance"
						and callback:IsA("BindableEvent")

					if isBindableEvent or type(callback) == "boolean" then
						if this.ResetCharacterPage then
							tryMethod(
								this.ResetCharacterPage,
								"SetResetCallback",
								callback
							)
						end
					else
						warn(
							"[SettingsHub] ResetButtonCallback must be "
								.. "a BindableEvent or a boolean"
						)
					end

					if callback == false then
						setResetEnabled(false)
					elseif not resetEnabled
						and (isBindableEvent or callback == true) then
						setResetEnabled(true)
					end
				end
			)
		end)
	end

	local function clearHubStack()
		table.clear(this.MenuStack)
	end

	pcall(function()
		ContextActionService:UnbindCoreAction(CLOSE_MENU_ACTION_NAME)
	end)

	local escapeBound, escapeBindError = pcall(function()
		ContextActionService:BindCoreAction(
			CLOSE_MENU_ACTION_NAME,
			function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Sink
				end

				local focusedTextBox

				pcall(function()
					focusedTextBox = UserInputService:GetFocusedTextBox()
				end)

				if focusedTextBox then
					pcall(function()
						focusedTextBox:ReleaseFocus(false)
					end)

					return Enum.ContextActionResult.Sink
				end

				if not this.Active then
					return Enum.ContextActionResult.Sink
				end

				if this.Visible then
					this:PopMenu(false, false)
				else
					clearHubStack()
					this:SetVisibility(true, false, nil, false)
				end

				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.KeyCode.Escape
		)
	end)

	if not escapeBound then
		warn(
			"[SettingsHub] Could not bind Escape as a core action: "
				.. tostring(escapeBindError)
		)

		local fallbackBound, fallbackError = pcall(function()
			ContextActionService:UnbindAction(CLOSE_MENU_ACTION_NAME)

			ContextActionService:BindActionAtPriority(
				CLOSE_MENU_ACTION_NAME,
				function(_, inputState)
					if inputState ~= Enum.UserInputState.Begin then
						return Enum.ContextActionResult.Sink
					end

					local focusedTextBox

					pcall(function()
						focusedTextBox = UserInputService:GetFocusedTextBox()
					end)

					if focusedTextBox then
						pcall(function()
							focusedTextBox:ReleaseFocus(false)
						end)

						return Enum.ContextActionResult.Sink
					end

					if not this.Active then
						return Enum.ContextActionResult.Sink
					end

					if this.Visible then
						this:PopMenu(false, false)
					else
						clearHubStack()
						this:SetVisibility(true, false, nil, false)
					end

					return Enum.ContextActionResult.Sink
				end,
				false,
				10000,
				Enum.KeyCode.Escape
			)
		end)

		if fallbackBound then
			print(
				"[SettingsHub] Escape is bound using the high-priority legacy fallback."
			)
		else
			warn(
				"[SettingsHub] Escape fallback binding failed: "
					.. tostring(fallbackError)
			)
		end
	else
		print(
			"[SettingsHub] Escape is bound to the legacy SettingsHub core action."
		)
	end

	UserInputService.InputBegan:Connect(function(input)
		if not this.Visible or not this.Active then
			return
		end

		local key = input.KeyCode

		if key == Enum.KeyCode.Left
			or key == Enum.KeyCode.Right
			or key == Enum.KeyCode.Up
			or key == Enum.KeyCode.Down then
			if not getSelectedObject() and this.Pages.CurrentPage then
				tryMethod(this.Pages.CurrentPage, "SelectARow")
			end
		end
	end)

	local showLeaveConfirmation =
		getProperty(GuiService, "ShowLeaveConfirmation", nil)

	if showLeaveConfirmation
		and typeof(showLeaveConfirmation) == "RBXScriptSignal" then
		showLeaveConfirmation:Connect(function()
			if #this.MenuStack == 0 then
				this:SetVisibility(true)

				local page = this.PlayersPage or this.GameSettingsPage

				if page then
					this:SwitchToPage(page, true, 1)
				end
			else
				this:PopMenu(false, false)
			end
		end)
	end

	if this.Pages.CurrentPage == nil then
		local firstPage =
			this.PlayersPage
			or this.HomePage
			or this.GameSettingsPage
			or this.HelpPage

		if firstPage then
			this:SwitchToPage(firstPage, true, 1, true)
		else
			warn(
				"[SettingsHub] No usable Settings page ModuleScripts were found "
					.. "under NewRobloxGui.Modules.Settings.Pages"
			)
		end
	end

	return this
end

local moduleApiTable = {
	ModuleName = "SettingsMenu",
	KeepVRTopbarOpen = true,
	VRIsExclusive = true,
	VRClosesNonExclusive = true,
}

local SettingsHubInstance = createSettingsHub()

function moduleApiTable:SetVisibility(
	visible,
	noAnimation,
	customStartPage,
	switchedFromGamepadInput
)
	SettingsHubInstance:SetVisibility(
		visible,
		noAnimation,
		customStartPage,
		switchedFromGamepadInput
	)
end

function moduleApiTable:ToggleVisibility(switchedFromGamepadInput)
	SettingsHubInstance:ToggleVisibility(switchedFromGamepadInput)
end

function moduleApiTable:SwitchToPage(pageToSwitchTo, ignoreStack)
	SettingsHubInstance:SwitchToPage(pageToSwitchTo, ignoreStack, 1)
end

function moduleApiTable:GetVisibility()
	return SettingsHubInstance.Visible
end

function moduleApiTable:ShowShield()
	SettingsHubInstance:ShowShield()
end

function moduleApiTable:HideShield()
	SettingsHubInstance:HideShield()
end

moduleApiTable.SettingsShowSignal =
	SettingsHubInstance.SettingsShowSignal

moduleApiTable.Instance = SettingsHubInstance

if VRHub then
	pcall(function()
		VRHub:RegisterModule(moduleApiTable)
	end)

	local moduleOpened =
		getProperty(VRHub, "ModuleOpened", nil)

	local openedSignal

	if moduleOpened
		and typeof(moduleOpened) == "Instance"
		and moduleOpened:IsA("BindableEvent") then
		openedSignal = moduleOpened.Event
	elseif typeof(moduleOpened) == "RBXScriptSignal" then
		openedSignal = moduleOpened
	end

	if openedSignal then
		openedSignal:Connect(function(moduleName)
			if moduleName == moduleApiTable.ModuleName then
				return
			end

			local ok, otherModule =
				tryMethod(VRHub, "GetModule", moduleName)

			if ok and otherModule and otherModule.VRIsExclusive then
				moduleApiTable:SetVisibility(false)
			end
		end)
	end
end

return moduleApiTable
