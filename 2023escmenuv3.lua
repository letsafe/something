CoreGui = game:GetService("CoreGui")
ContextActionService = game:GetService("ContextActionService")
UserInputService = game:GetService("UserInputService")
GuiService = game:GetService("GuiService")
StarterGui = game:GetService("StarterGui")
HttpRbxApiService = nil
pcall(function()
	HttpRbxApiService = game:GetService("HttpRbxApiService")
end)

SoundService = game:GetService("SoundService")
Players = game:GetService("Players")
SocialService = game:GetService("SocialService")
VoiceChatService = game:GetService("VoiceChatService")
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

	pcall(function()
		local Preferred = GuiService.PreferredTextSize
		if Preferred == Enum.PreferredTextSize.Large then
			Scale *= 1.08
		elseif Preferred == Enum.PreferredTextSize.Larger then
			Scale *= 1.16
		elseif Preferred == Enum.PreferredTextSize.Largest then
			Scale *= 1.25
		end
	end)

	return Clamp(Scale, 0.95, 1.65)
end
