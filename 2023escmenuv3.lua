-- Normal build: MicLight icons + native Roblox MuteSelfButton integration.
-- Verbose microphone diagnostics are intentionally disabled to avoid console spam.
-- VOICE CHAT CONFIGURATION:
--   "NORMAL" = use the script's usual Roblox voice support / eligibility checks.
--   "NEVER"  = never show or enable this script's VC controls; leave the local voice session.
VOICE_CHAT_MODE = "NORMAL"
VOICE_CHAT_MODE = string.upper(tostring(VOICE_CHAT_MODE or "NORMAL"))
if VOICE_CHAT_MODE ~= "NORMAL" and VOICE_CHAT_MODE ~= "NEVER" then
    VOICE_CHAT_MODE = "NORMAL"
end
VOICE_CHAT_FORCE_OFF = VOICE_CHAT_MODE == "NEVER"

-- INVITE FRIENDS ROW TEXT SIZE (applies on every device)
-- Adjust these values to tune how small/large "Invite friends to join" can render.
INVITE_FRIENDS_TEXT_MIN_SIZE = 14
INVITE_FRIENDS_TEXT_MAX_SIZE = 18

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
LocalizationService = game:GetService("LocalizationService")
TextService = nil
pcall(function() TextService = game:GetService("TextService") end)
VRService = nil
pcall(function() VRService = game:GetService("VRService") end)
HttpService = game:GetService("HttpService")
HttpRbxApiService = nil
pcall(function()
	HttpRbxApiService = game:GetService("HttpRbxApiService")
end)

SoundService = game:GetService("SoundService")
Players = game:GetService("Players")
MarketplaceService = game:GetService("MarketplaceService")
SocialService = game:GetService("SocialService")
VoiceChatService = game:GetService("VoiceChatService")

-- ============================================================
-- INVITE-MENU FAST-FLAG COMPATIBILITY
-- Keep the existing/old invite menu untouched only when ALL three flags
-- can be read and are explicitly False. True or unknown selects our redesign.
-- Executor getfflag is preferred; CoreScript settings():GetFFlag is fallback.
-- ============================================================
local function NormalizeInviteFlag(Value)
    if type(Value) == "boolean" then return Value end
    if type(Value) == "string" then
        local Lower = string.lower(Value)
        if Lower == "true" then return true end
        if Lower == "false" then return false end
    end
    return nil
end

local function ReadInviteFlag(Name)
    local BareName = string.gsub(Name, "^FFlag", "")
    local NamesToTry = {BareName, Name}
    local Getter = nil
    pcall(function() Getter = getfflag end)
    if type(Getter) ~= "function" then
        pcall(function()
            local Env = getgenv and getgenv() or nil
            Getter = Env and Env.getfflag or nil
        end)
    end

    if type(Getter) == "function" then
        for _, Candidate in ipairs(NamesToTry) do
            local Ok, Value = pcall(Getter, Candidate)
            local Parsed = Ok and NormalizeInviteFlag(Value) or nil
            if Parsed ~= nil then return Parsed, true end
        end
    end

    for _, Candidate in ipairs(NamesToTry) do
        local Ok, Value = pcall(function()
            return settings():GetFFlag(Candidate)
        end)
        local Parsed = Ok and NormalizeInviteFlag(Value) or nil
        if Parsed ~= nil then return Parsed, true end
    end
    return nil, false
end

local InviteFlagNewMenu, InviteFlagNewMenuReadable = ReadInviteFlag("FFlagEnableNewInviteMenuIXP2")
local InviteFlagGameInviteUnification, InviteFlagGameInviteUnificationReadable = ReadInviteFlag("FFlagLuaInExperienceCoreScriptsGameInviteUnificationV3")
local InviteFlagUniversalUnification, InviteFlagUniversalUnificationReadable = ReadInviteFlag("FFlagEnableUniversalAppGameInviteUnification")
local UseOriginalInviteMenu =
    InviteFlagNewMenuReadable and InviteFlagNewMenu == false
    and InviteFlagGameInviteUnificationReadable and InviteFlagGameInviteUnification == false
    and InviteFlagUniversalUnificationReadable and InviteFlagUniversalUnification == false
USE_NEW_INVITE_MENU = not UseOriginalInviteMenu

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
DESCRIPTION_PLACEHOLDER = "In your own words, help us understand what went wrong."
REPORT_DESCRIPTION_FALLBACK = ""
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

-- The new invite menu puts the share control inside InviteList so it scrolls
-- away with the friends instead of remaining pinned over the list.
INVITE_SHARE_ROW_HEIGHT = 50
INVITE_SHARE_ROW_GAP = 8

-- The 2016-style phone tab bar is compact; tablet and desktop keep their
-- own heights below.
MOBILE_HUBBAR_HEIGHT = 48
TABLET_HUBBAR_HEIGHT = 48

-- Custom SystemMenuButton offsets.
SYSTEM_MENU_OFFSET_X = 16
SYSTEM_MENU_OFFSET_Y = 4
MOBILE_SYSTEM_MENU_OFFSET_X = 16
GetSystemMenuButtonOffsetX = function()
    return IsPhone and MOBILE_SYSTEM_MENU_OFFSET_X or SYSTEM_MENU_OFFSET_X
end

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

-- Remove every old Settings2016 menu root before constructing this copy.
-- Search descendants as well as CoreGui's direct children so a previously
-- reparented/nested copy cannot survive and compete with the new menu.
local OldMenuRoots = {}
local function IsOldSettings2016Root(Object)
	local Name = tostring(Object and Object.Name or "")
	return Name == "Settings2016Gui"
		or Name == "Core2016SettingsGui"
		or Name == "Settings2016VoiceMuteErrorOverlay"
end
pcall(function()
	for _, Object in ipairs(CoreGui:GetDescendants()) do
		if IsOldSettings2016Root(Object) then
			table.insert(OldMenuRoots, Object)
		end
	end
end)
for _, Object in ipairs(CoreGui:GetChildren()) do
	if IsOldSettings2016Root(Object) then
		table.insert(OldMenuRoots, Object)
	end
end
local DestroyedRoots = {}
for _, Object in ipairs(OldMenuRoots) do
	if Object and not DestroyedRoots[Object] then
		DestroyedRoots[Object] = true
		pcall(function() Object:Destroy() end)
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

-- ============================================================
-- MENU LOCALIZATION
-- Match the same GetCurrentExperienceLocale() helper used by the Experience
-- Language selector. Before that later-declared helper exists during startup,
-- use Player.LocaleId, then CoreGui/system locales as safe fallbacks.
-- Prefer installed CoreScript translations, then bundled custom-menu strings.
-- ============================================================
MenuLocalizationLocale = "en-us"
-- A user choice in this custom menu is kept locally when the client blocks
-- Roblox's native experience-language setter. A real native locale change
-- clears this override and becomes authoritative again.
MenuLocalizationOverrideLocale = nil
MenuLastObservedExperienceLocale = nil
MenuLocalizationSources = setmetatable({}, {__mode = "k"})
MenuLocalizationRendered = setmetatable({}, {__mode = "k"})
MenuCoreTranslationsBySource = {}

NormalizeMenuLocale = function(Locale)
	return (tostring(Locale or "en-us"):lower():gsub("_", "-"))
end

GetMenuExperienceLocale = function()
	-- The custom Experience Language setting defines the locale the user wants
	-- inside this experience. Its helper is declared later with the settings UI,
	-- so use it when available and a safe player/CoreGui fallback during startup.
	local ExperienceLocale = nil
	if type(GetCurrentExperienceLocale) == "function" then
		pcall(function() ExperienceLocale = GetCurrentExperienceLocale() end)
	end
	if type(ExperienceLocale) == "string" and ExperienceLocale ~= "" then
		return NormalizeMenuLocale(ExperienceLocale)
	end

	local Player = LocalPlayer
	if not Player then
		pcall(function() Player = Players.LocalPlayer end)
	end

	local Locale = nil
	if Player then
		pcall(function() Locale = Player.LocaleId end)

		-- LocaleId is hidden in Roblox's public API. Executors that expose a
		-- hidden-property getter can still read the exact player locale.
		if type(Locale) ~= "string" or Locale == "" then
			local HiddenGetter = nil
			pcall(function() HiddenGetter = gethiddenproperty end)
			if type(HiddenGetter) ~= "function" then
				pcall(function()
					local Env = getgenv and getgenv() or nil
					HiddenGetter = Env and Env.gethiddenproperty or nil
				end)
			end
			if type(HiddenGetter) == "function" then
				local Ok, Value = pcall(HiddenGetter, Player, "LocaleId")
				if Ok and type(Value) == "string" and Value ~= "" then
					Locale = Value
				end
			end
		end
	end

	if type(Locale) == "string" and Locale ~= "" then
		return NormalizeMenuLocale(Locale)
	end

	-- These describe CoreGui and the operating system, respectively; use them
	-- only when the actual in-experience player locale is unavailable.
	Locale = nil
	pcall(function() Locale = LocalizationService.RobloxLocaleId end)
	if type(Locale) == "string" and Locale ~= "" then
		return NormalizeMenuLocale(Locale)
	end
	Locale = nil
	pcall(function() Locale = LocalizationService.SystemLocaleId end)
	if type(Locale) == "string" and Locale ~= "" then
		return NormalizeMenuLocale(Locale)
	end
	return "en-us"
end

-- These are fallback strings for custom/reworked wording. The installed
-- CoreScript localization tables are checked first for matching stock text.
MenuFallbackTranslations = {
	ru = {
		["Settings"]="Настройки", ["People"]="Игроки", ["Help"]="Справка", ["Report"]="Пожаловаться",
		["Invite friends to join"]="Пригласить друзей", ["Invite"]="Пригласить", ["Invited..."]="Приглашено...",
		["Mute All"]="Отключить звук всем", ["Unmute All"]="Включить звук всем", ["Share Invite Link"]="Поделиться ссылкой-приглашением",
		["Share"]="Поделиться", ["Search for friends"]="Поиск друзей", ["Back"]="Назад",
		["Reset"]="Сбросить", ["Don't Reset"]="Не сбрасывать", ["Reset Character"]="Сбросить персонажа",
		["Leave"]="Выйти", ["Don't Leave"]="Остаться", ["Leave Game"]="Выйти из игры", ["Resume Game"]="Продолжить игру",
		["Are you sure you want to reset your character?"]="Вы уверены, что хотите сбросить персонажа?",
		["Are you sure you want to leave the game?"]="Вы уверены, что хотите выйти из игры?",
		["Game or Player?"]="Игра или игрок?", ["Which Player?"]="Какой игрок?", ["Type Of Abuse"]="Тип нарушения",
		["In your own words, help us understand what went wrong."]="Опишите своими словами, что произошло.",
		["Submit"]="Отправить", ["Game"]="Игра", ["Player"]="Игрок", ["Shift Lock"]="Фиксация камеры",
		["Camera Mode"]="Режим камеры", ["Movement Mode"]="Режим движения", ["Experience Language"]="Язык игры",
		["Camera Sensitivity"]="Чувствительность камеры", ["Volume"]="Громкость", ["Input Device"]="Устройство ввода",
		["Output Device"]="Устройство вывода", ["Fullscreen"]="Полный экран", ["Graphics Mode"]="Режим графики",
		["Graphics Quality"]="Качество графики", ["Performance Stats"]="Статистика производительности",
		["Camera Inverted"]="Инверсия камеры", ["Video Camera"]="Видеокамера", ["On"]="Вкл.", ["Off"]="Выкл.",
		["Show"]="Показать", ["Hide"]="Скрыть", ["Tap to Move"]="Перемещение касанием", ["Click to Move"]="Перемещение нажатием",
		["Experience Invite could not be sent. Please try again later."]="Не удалось отправить приглашение в игру. Повторите попытку позже.",
		["Set by Developer"]="Задано разработчиком", ["Automatic Chat Translation"]="Автоматический перевод чата",
		["Give Feedback"]="Оставить отзыв", ["Give Translation Feedback"]="Оставить отзыв о переводе",
		["View Untranslated Messages"]="Показывать непереведённые сообщения", ["Transparent"]="Прозрачность", ["Opaque"]="Непрозрачность",
		["Largest"]="Самый крупный", ["Learn More"]="Подробнее",
	},
	uk = {
		["Settings"]="Налаштування", ["People"]="Гравці", ["Help"]="Довідка", ["Report"]="Поскаржитися",
		["Invite friends to join"]="Запросити друзів", ["Invite"]="Запросити", ["Invited..."]="Запрошено...",
		["Mute All"]="Вимкнути звук усім", ["Unmute All"]="Увімкнути звук усім", ["Share Invite Link"]="Поділитися посиланням-запрошенням",
		["Share"]="Поділитися", ["Search for friends"]="Пошук друзів", ["Back"]="Назад",
		["Reset"]="Скинути", ["Don't Reset"]="Не скидати", ["Reset Character"]="Скинути персонажа",
		["Leave"]="Вийти", ["Don't Leave"]="Залишитися", ["Leave Game"]="Вийти з гри", ["Resume Game"]="Продовжити гру",
		["Are you sure you want to reset your character?"]="Ви впевнені, що хочете скинути персонажа?",
		["Are you sure you want to leave the game?"]="Ви впевнені, що хочете вийти з гри?",
		["Game or Player?"]="Гра чи гравець?", ["Which Player?"]="Який гравець?", ["Type Of Abuse"]="Тип порушення",
		["In your own words, help us understand what went wrong."]="Опишіть своїми словами, що сталося.",
		["Submit"]="Надіслати", ["Game"]="Гра", ["Player"]="Гравець", ["Shift Lock"]="Фіксація камери",
		["Camera Mode"]="Режим камери", ["Movement Mode"]="Режим руху", ["Experience Language"]="Мова гри",
		["Camera Sensitivity"]="Чутливість камери", ["Volume"]="Гучність", ["Input Device"]="Пристрій введення",
		["Output Device"]="Пристрій виведення", ["Fullscreen"]="На весь екран", ["Graphics Mode"]="Режим графіки",
		["Graphics Quality"]="Якість графіки", ["Performance Stats"]="Статистика продуктивності",
		["Camera Inverted"]="Інверсія камери", ["Video Camera"]="Відеокамера", ["On"]="Увімкнено", ["Off"]="Вимкнено",
		["Show"]="Показати", ["Hide"]="Приховати", ["Tap to Move"]="Рух дотиком", ["Click to Move"]="Рух натисканням",
		["Experience Invite could not be sent. Please try again later."]="Не вдалося надіслати запрошення до гри. Спробуйте пізніше.",
		["Set by Developer"]="Установлено розробником", ["Automatic Chat Translation"]="Автоматичний переклад чату",
		["Give Feedback"]="Залишити відгук", ["Give Translation Feedback"]="Відгук про переклад",
		["View Untranslated Messages"]="Показувати неперекладені повідомлення", ["Transparent"]="Прозорість", ["Opaque"]="Непрозорість",
		["Largest"]="Найбільший", ["Learn More"]="Докладніше",
	},
	es = {
		["Settings"]="Configuración", ["People"]="Personas", ["Help"]="Ayuda", ["Report"]="Denunciar",
		["Invite friends to join"]="Invitar amigos", ["Invite"]="Invitar", ["Invited..."]="Invitado...",
		["Mute All"]="Silenciar a todos", ["Unmute All"]="Activar el sonido de todos", ["Share Invite Link"]="Compartir enlace de invitación",
		["Share"]="Compartir", ["Search for friends"]="Buscar amigos", ["Back"]="Atrás",
		["Reset"]="Restablecer", ["Don't Reset"]="No restablecer", ["Reset Character"]="Restablecer personaje",
		["Leave"]="Salir", ["Don't Leave"]="Quedarse", ["Leave Game"]="Salir del juego", ["Resume Game"]="Reanudar juego",
		["Are you sure you want to reset your character?"]="¿Seguro que quieres restablecer tu personaje?",
		["Are you sure you want to leave the game?"]="¿Seguro que quieres salir del juego?",
		["Game or Player?"]="¿Juego o jugador?", ["Which Player?"]="¿Qué jugador?", ["Type Of Abuse"]="Tipo de abuso",
		["In your own words, help us understand what went wrong."]="Con tus propias palabras, ayúdanos a entender qué ocurrió.",
		["Submit"]="Enviar", ["Game"]="Juego", ["Player"]="Jugador", ["Shift Lock"]="Bloqueo de cámara",
		["Camera Mode"]="Modo de cámara", ["Movement Mode"]="Modo de movimiento", ["Experience Language"]="Idioma de la experiencia",
		["Camera Sensitivity"]="Sensibilidad de cámara", ["Volume"]="Volumen", ["Input Device"]="Dispositivo de entrada",
		["Output Device"]="Dispositivo de salida", ["Fullscreen"]="Pantalla completa", ["Graphics Mode"]="Modo de gráficos",
		["Graphics Quality"]="Calidad gráfica", ["Performance Stats"]="Estadísticas de rendimiento",
		["Camera Inverted"]="Cámara invertida", ["Video Camera"]="Cámara de video", ["On"]="Activado", ["Off"]="Desactivado",
		["Show"]="Mostrar", ["Hide"]="Ocultar", ["Tap to Move"]="Tocar para moverse", ["Click to Move"]="Clic para moverse",
		["Experience Invite could not be sent. Please try again later."]="No se pudo enviar la invitación a la experiencia. Inténtalo de nuevo más tarde.",
		["Set by Developer"]="Configurado por el desarrollador", ["Automatic Chat Translation"]="Traducción automática del chat",
		["Give Feedback"]="Enviar comentarios", ["Give Translation Feedback"]="Enviar comentarios sobre la traducción",
		["View Untranslated Messages"]="Ver mensajes sin traducir", ["Transparent"]="Transparente", ["Opaque"]="Opaco",
		["Largest"]="El más grande", ["Learn More"]="Más información",
	},
	pt = {
		["Settings"]="Configurações", ["People"]="Pessoas", ["Help"]="Ajuda", ["Report"]="Denunciar",
		["Invite friends to join"]="Convidar amigos", ["Invite"]="Convidar", ["Invited..."]="Convidado...",
		["Mute All"]="Silenciar todos", ["Unmute All"]="Ativar som de todos", ["Share Invite Link"]="Compartilhar link de convite",
		["Share"]="Compartilhar", ["Search for friends"]="Buscar amigos", ["Back"]="Voltar",
		["Reset"]="Redefinir", ["Don't Reset"]="Não redefinir", ["Reset Character"]="Redefinir personagem",
		["Leave"]="Sair", ["Don't Leave"]="Ficar", ["Leave Game"]="Sair do jogo", ["Resume Game"]="Retomar jogo",
		["Are you sure you want to reset your character?"]="Tem certeza de que deseja redefinir seu personagem?",
		["Are you sure you want to leave the game?"]="Tem certeza de que deseja sair do jogo?",
		["Game or Player?"]="Jogo ou jogador?", ["Which Player?"]="Qual jogador?", ["Type Of Abuse"]="Tipo de abuso",
		["In your own words, help us understand what went wrong."]="Com suas próprias palavras, ajude-nos a entender o que aconteceu.",
		["Submit"]="Enviar", ["Game"]="Jogo", ["Player"]="Jogador", ["Shift Lock"]="Travar câmera",
		["Camera Mode"]="Modo da câmera", ["Movement Mode"]="Modo de movimento", ["Experience Language"]="Idioma da experiência",
		["Camera Sensitivity"]="Sensibilidade da câmera", ["Volume"]="Volume", ["Input Device"]="Dispositivo de entrada",
		["Output Device"]="Dispositivo de saída", ["Fullscreen"]="Tela cheia", ["Graphics Mode"]="Modo gráfico",
		["Graphics Quality"]="Qualidade gráfica", ["Performance Stats"]="Estatísticas de desempenho",
		["Camera Inverted"]="Câmera invertida", ["Video Camera"]="Câmera de vídeo", ["On"]="Ativado", ["Off"]="Desativado",
		["Show"]="Mostrar", ["Hide"]="Ocultar", ["Tap to Move"]="Toque para mover", ["Click to Move"]="Clique para mover",
		["Experience Invite could not be sent. Please try again later."]="Não foi possível enviar o convite para a experiência. Tente novamente mais tarde.",
		["Set by Developer"]="Definido pelo desenvolvedor", ["Automatic Chat Translation"]="Tradução automática do chat",
		["Give Feedback"]="Enviar feedback", ["Give Translation Feedback"]="Enviar feedback sobre a tradução",
		["View Untranslated Messages"]="Ver mensagens não traduzidas", ["Transparent"]="Transparente", ["Opaque"]="Opaco",
		["Largest"]="Maior", ["Learn More"]="Saiba mais",
	},
	["zh-cn"] = {
		["Settings"]="设置", ["People"]="玩家", ["Help"]="帮助", ["Report"]="举报",
		["Invite friends to join"]="邀请好友加入", ["Invite"]="邀请", ["Invited..."]="已邀请...",
		["Mute All"]="全部静音", ["Unmute All"]="取消全部静音", ["Share Invite Link"]="分享邀请链接",
		["Share"]="分享", ["Search for friends"]="搜索好友", ["Back"]="返回",
		["Reset"]="重置", ["Don't Reset"]="不重置", ["Reset Character"]="重置角色",
		["Leave"]="离开", ["Don't Leave"]="不离开", ["Leave Game"]="离开游戏", ["Resume Game"]="继续游戏",
		["Are you sure you want to reset your character?"]="确定要重置角色吗？",
		["Are you sure you want to leave the game?"]="确定要离开游戏吗？",
		["Game or Player?"]="游戏还是玩家？", ["Which Player?"]="选择玩家", ["Type Of Abuse"]="违规类型",
		["In your own words, help us understand what went wrong."]="请用自己的话描述发生的问题。",
		["Submit"]="提交", ["Game"]="游戏", ["Player"]="玩家", ["Shift Lock"]="锁定视角",
		["Camera Mode"]="镜头模式", ["Movement Mode"]="移动模式", ["Experience Language"]="体验语言",
		["Camera Sensitivity"]="镜头灵敏度", ["Volume"]="音量", ["Input Device"]="输入设备",
		["Output Device"]="输出设备", ["Fullscreen"]="全屏", ["Graphics Mode"]="图形模式",
		["Graphics Quality"]="画质", ["Performance Stats"]="性能统计",
		["Camera Inverted"]="反转镜头", ["Video Camera"]="摄像头", ["On"]="开启", ["Off"]="关闭",
		["Show"]="显示", ["Hide"]="隐藏", ["Tap to Move"]="点击移动", ["Click to Move"]="单击移动",
		["Experience Invite could not be sent. Please try again later."]="无法发送体验邀请。请稍后重试。",
		["Set by Developer"]="由开发者设置", ["Automatic Chat Translation"]="自动聊天翻译",
		["Give Feedback"]="提交反馈", ["Give Translation Feedback"]="提交翻译反馈",
		["View Untranslated Messages"]="显示未翻译的消息", ["Transparent"]="透明", ["Opaque"]="不透明",
		["Largest"]="最大", ["Learn More"]="了解更多",
	},
	["zh-tw"] = {
		["Settings"]="設定", ["People"]="玩家", ["Help"]="說明", ["Report"]="檢舉",
		["Invite friends to join"]="邀請好友加入", ["Invite"]="邀請", ["Invited..."]="已邀請...",
		["Mute All"]="全部靜音", ["Unmute All"]="取消全部靜音", ["Share Invite Link"]="分享邀請連結",
		["Share"]="分享", ["Search for friends"]="搜尋好友", ["Back"]="返回",
		["Reset"]="重設", ["Don't Reset"]="不要重設", ["Reset Character"]="重設角色",
		["Leave"]="離開", ["Don't Leave"]="不要離開", ["Leave Game"]="離開遊戲", ["Resume Game"]="繼續遊戲",
		["Are you sure you want to reset your character?"]="確定要重設角色嗎？",
		["Are you sure you want to leave the game?"]="確定要離開遊戲嗎？",
		["Game or Player?"]="遊戲還是玩家？", ["Which Player?"]="選擇玩家", ["Type Of Abuse"]="違規類型",
		["In your own words, help us understand what went wrong."]="請用自己的話描述發生的問題。",
		["Submit"]="提交", ["Game"]="遊戲", ["Player"]="玩家", ["Shift Lock"]="鎖定視角",
		["Camera Mode"]="鏡頭模式", ["Movement Mode"]="移動模式", ["Experience Language"]="體驗語言",
		["Camera Sensitivity"]="鏡頭靈敏度", ["Volume"]="音量", ["Input Device"]="輸入裝置",
		["Output Device"]="輸出裝置", ["Fullscreen"]="全螢幕", ["Graphics Mode"]="圖形模式",
		["Graphics Quality"]="畫質", ["Performance Stats"]="效能統計",
		["Camera Inverted"]="反轉鏡頭", ["Video Camera"]="攝影機", ["On"]="開啟", ["Off"]="關閉",
		["Show"]="顯示", ["Hide"]="隱藏", ["Tap to Move"]="點擊移動", ["Click to Move"]="按一下移動",
		["Experience Invite could not be sent. Please try again later."]="無法傳送體驗邀請。請稍後再試。",
		["Set by Developer"]="由開發者設定", ["Automatic Chat Translation"]="自動聊天翻譯",
		["Give Feedback"]="提供意見", ["Give Translation Feedback"]="提供翻譯意見",
		["View Untranslated Messages"]="顯示未翻譯的訊息", ["Transparent"]="透明", ["Opaque"]="不透明",
		["Largest"]="最大", ["Learn More"]="瞭解更多",
	},
	hi = {
		["Settings"]="सेटिंग्स", ["People"]="लोग", ["Help"]="मदद", ["Report"]="रिपोर्ट करें",
		["Invite friends to join"]="दोस्तों को आमंत्रित करें", ["Invite"]="आमंत्रित करें", ["Invited..."]="आमंत्रित किया गया...",
		["Mute All"]="सभी को म्यूट करें", ["Unmute All"]="सभी का म्यूट हटाएँ", ["Share Invite Link"]="आमंत्रण लिंक साझा करें",
		["Share"]="साझा करें", ["Search for friends"]="दोस्तों को खोजें", ["Back"]="वापस",
		["Reset"]="रीसेट करें", ["Don't Reset"]="रीसेट न करें", ["Reset Character"]="कैरेक्टर रीसेट करें",
		["Leave"]="बाहर जाएँ", ["Don't Leave"]="बाहर न जाएँ", ["Leave Game"]="गेम छोड़ें", ["Resume Game"]="गेम जारी रखें",
		["Are you sure you want to reset your character?"]="क्या आप वाकई अपना कैरेक्टर रीसेट करना चाहते हैं?",
		["Are you sure you want to leave the game?"]="क्या आप वाकई गेम छोड़ना चाहते हैं?",
		["Game or Player?"]="गेम या खिलाड़ी?", ["Which Player?"]="कौन-सा खिलाड़ी?", ["Type Of Abuse"]="दुर्व्यवहार का प्रकार",
		["In your own words, help us understand what went wrong."]="अपने शब्दों में बताएँ कि क्या हुआ, ताकि हम समझ सकें।",
		["Submit"]="सबमिट करें", ["Game"]="गेम", ["Player"]="खिलाड़ी", ["Shift Lock"]="कैमरा लॉक",
		["Camera Mode"]="कैमरा मोड", ["Movement Mode"]="मूवमेंट मोड", ["Experience Language"]="अनुभव की भाषा",
		["Camera Sensitivity"]="कैमरा संवेदनशीलता", ["Volume"]="वॉल्यूम", ["Input Device"]="इनपुट डिवाइस",
		["Output Device"]="आउटपुट डिवाइस", ["Fullscreen"]="फ़ुलस्क्रीन", ["Graphics Mode"]="ग्राफ़िक्स मोड",
		["Graphics Quality"]="ग्राफ़िक्स गुणवत्ता", ["Performance Stats"]="प्रदर्शन आँकड़े", ["Camera Inverted"]="उल्टा कैमरा",
		["Video Camera"]="वीडियो कैमरा", ["On"]="चालू", ["Off"]="बंद", ["Show"]="दिखाएँ", ["Hide"]="छिपाएँ",
		["Tap to Move"]="टैप करके चलें", ["Click to Move"]="क्लिक करके चलें",
		["Experience Invite could not be sent. Please try again later."]="अनुभव का आमंत्रण नहीं भेजा जा सका। कृपया बाद में फिर कोशिश करें।",
		["Set by Developer"]="डेवलपर द्वारा सेट", ["Automatic Chat Translation"]="स्वचालित चैट अनुवाद",
		["Give Feedback"]="प्रतिक्रिया दें", ["Give Translation Feedback"]="अनुवाद पर प्रतिक्रिया दें",
		["View Untranslated Messages"]="अनुवाद न किए गए संदेश दिखाएँ", ["Transparent"]="पारदर्शी", ["Opaque"]="अपारदर्शी",
		["Largest"]="सबसे बड़ा", ["Learn More"]="और जानें",
	},
	fr = {
		["Settings"]="Paramètres", ["People"]="Joueurs", ["Help"]="Aide", ["Report"]="Signaler",
		["Invite friends to join"]="Inviter des amis", ["Invite"]="Inviter", ["Invited..."]="Invité...",
		["Mute All"]="Couper le son de tous", ["Unmute All"]="Réactiver le son de tous", ["Share Invite Link"]="Partager le lien d’invitation",
		["Share"]="Partager", ["Search for friends"]="Rechercher des amis", ["Back"]="Retour",
		["Reset"]="Réinitialiser", ["Don't Reset"]="Ne pas réinitialiser", ["Reset Character"]="Réinitialiser le personnage",
		["Leave"]="Quitter", ["Don't Leave"]="Rester", ["Leave Game"]="Quitter le jeu", ["Resume Game"]="Reprendre le jeu",
		["Are you sure you want to reset your character?"]="Voulez-vous vraiment réinitialiser votre personnage ?",
		["Are you sure you want to leave the game?"]="Voulez-vous vraiment quitter le jeu ?",
		["Game or Player?"]="Jeu ou joueur ?", ["Which Player?"]="Quel joueur ?", ["Type Of Abuse"]="Type d’abus",
		["In your own words, help us understand what went wrong."]="Expliquez avec vos propres mots ce qui s’est passé.",
		["Submit"]="Envoyer", ["Game"]="Jeu", ["Player"]="Joueur", ["Shift Lock"]="Verrouillage de caméra",
		["Camera Mode"]="Mode de caméra", ["Movement Mode"]="Mode de déplacement", ["Experience Language"]="Langue de l’expérience",
		["Camera Sensitivity"]="Sensibilité de la caméra", ["Volume"]="Volume", ["Input Device"]="Périphérique d’entrée",
		["Output Device"]="Périphérique de sortie", ["Fullscreen"]="Plein écran", ["Graphics Mode"]="Mode graphique",
		["Graphics Quality"]="Qualité graphique", ["Performance Stats"]="Statistiques de performance", ["Camera Inverted"]="Caméra inversée",
		["Video Camera"]="Caméra vidéo", ["On"]="Activé", ["Off"]="Désactivé", ["Show"]="Afficher", ["Hide"]="Masquer",
		["Tap to Move"]="Appuyer pour se déplacer", ["Click to Move"]="Cliquer pour se déplacer",
		["Experience Invite could not be sent. Please try again later."]="Impossible d’envoyer l’invitation à l’expérience. Réessayez plus tard.",
		["Set by Developer"]="Défini par le développeur", ["Automatic Chat Translation"]="Traduction automatique du chat",
		["Give Feedback"]="Envoyer des commentaires", ["Give Translation Feedback"]="Commenter la traduction",
		["View Untranslated Messages"]="Afficher les messages non traduits", ["Transparent"]="Transparent", ["Opaque"]="Opaque",
		["Largest"]="Le plus grand", ["Learn More"]="En savoir plus",
	},
	de = {
		["Settings"]="Einstellungen", ["People"]="Spieler", ["Help"]="Hilfe", ["Report"]="Melden",
		["Invite friends to join"]="Freunde einladen", ["Invite"]="Einladen", ["Invited..."]="Eingeladen...",
		["Mute All"]="Alle stummschalten", ["Unmute All"]="Stummschaltung für alle aufheben", ["Share Invite Link"]="Einladungslink teilen",
		["Share"]="Teilen", ["Search for friends"]="Freunde suchen", ["Back"]="Zurück",
		["Reset"]="Zurücksetzen", ["Don't Reset"]="Nicht zurücksetzen", ["Reset Character"]="Charakter zurücksetzen",
		["Leave"]="Verlassen", ["Don't Leave"]="Nicht verlassen", ["Leave Game"]="Spiel verlassen", ["Resume Game"]="Spiel fortsetzen",
		["Are you sure you want to reset your character?"]="Möchtest du deinen Charakter wirklich zurücksetzen?",
		["Are you sure you want to leave the game?"]="Möchtest du das Spiel wirklich verlassen?",
		["Game or Player?"]="Spiel oder Spieler?", ["Which Player?"]="Welcher Spieler?", ["Type Of Abuse"]="Art des Verstoßes",
		["In your own words, help us understand what went wrong."]="Beschreibe mit eigenen Worten, was passiert ist.",
		["Submit"]="Senden", ["Game"]="Spiel", ["Player"]="Spieler", ["Shift Lock"]="Kamerasperre",
		["Camera Mode"]="Kameramodus", ["Movement Mode"]="Bewegungsmodus", ["Experience Language"]="Erlebnissprache",
		["Camera Sensitivity"]="Kameraempfindlichkeit", ["Volume"]="Lautstärke", ["Input Device"]="Eingabegerät",
		["Output Device"]="Ausgabegerät", ["Fullscreen"]="Vollbild", ["Graphics Mode"]="Grafikmodus",
		["Graphics Quality"]="Grafikqualität", ["Performance Stats"]="Leistungsstatistiken", ["Camera Inverted"]="Kamera umkehren",
		["Video Camera"]="Videokamera", ["On"]="Ein", ["Off"]="Aus", ["Show"]="Anzeigen", ["Hide"]="Ausblenden",
		["Tap to Move"]="Tippen zum Bewegen", ["Click to Move"]="Klicken zum Bewegen",
		["Experience Invite could not be sent. Please try again later."]="Die Einladung zum Erlebnis konnte nicht gesendet werden. Bitte versuche es später erneut.",
		["Set by Developer"]="Vom Entwickler festgelegt", ["Automatic Chat Translation"]="Automatische Chatübersetzung",
		["Give Feedback"]="Feedback geben", ["Give Translation Feedback"]="Übersetzungsfeedback geben",
		["View Untranslated Messages"]="Nicht übersetzte Nachrichten anzeigen", ["Transparent"]="Transparent", ["Opaque"]="Undurchsichtig",
		["Largest"]="Größte", ["Learn More"]="Mehr erfahren",
	},
	it = {
		["Settings"]="Impostazioni", ["People"]="Giocatori", ["Help"]="Aiuto", ["Report"]="Segnala",
		["Invite friends to join"]="Invita amici", ["Invite"]="Invita", ["Invited..."]="Invitato...",
		["Mute All"]="Disattiva audio per tutti", ["Unmute All"]="Riattiva audio per tutti", ["Share Invite Link"]="Condividi link d’invito",
		["Share"]="Condividi", ["Search for friends"]="Cerca amici", ["Back"]="Indietro",
		["Reset"]="Reimposta", ["Don't Reset"]="Non reimpostare", ["Reset Character"]="Reimposta personaggio",
		["Leave"]="Esci", ["Don't Leave"]="Resta", ["Leave Game"]="Esci dal gioco", ["Resume Game"]="Riprendi gioco",
		["Are you sure you want to reset your character?"]="Vuoi davvero reimpostare il tuo personaggio?",
		["Are you sure you want to leave the game?"]="Vuoi davvero uscire dal gioco?",
		["Game or Player?"]="Gioco o giocatore?", ["Which Player?"]="Quale giocatore?", ["Type Of Abuse"]="Tipo di abuso",
		["In your own words, help us understand what went wrong."]="Descrivi con parole tue cosa è successo.",
		["Submit"]="Invia", ["Game"]="Gioco", ["Player"]="Giocatore", ["Shift Lock"]="Blocco telecamera",
		["Camera Mode"]="Modalità telecamera", ["Movement Mode"]="Modalità movimento", ["Experience Language"]="Lingua dell’esperienza",
		["Camera Sensitivity"]="Sensibilità telecamera", ["Volume"]="Volume", ["Input Device"]="Dispositivo di input",
		["Output Device"]="Dispositivo di output", ["Fullscreen"]="Schermo intero", ["Graphics Mode"]="Modalità grafica",
		["Graphics Quality"]="Qualità grafica", ["Performance Stats"]="Statistiche prestazioni", ["Camera Inverted"]="Telecamera invertita",
		["Video Camera"]="Videocamera", ["On"]="Attivo", ["Off"]="Disattivo", ["Show"]="Mostra", ["Hide"]="Nascondi",
		["Tap to Move"]="Tocca per muoverti", ["Click to Move"]="Fai clic per muoverti",
		["Experience Invite could not be sent. Please try again later."]="Impossibile inviare l’invito all’esperienza. Riprova più tardi.",
		["Set by Developer"]="Impostato dallo sviluppatore", ["Automatic Chat Translation"]="Traduzione automatica della chat",
		["Give Feedback"]="Invia feedback", ["Give Translation Feedback"]="Invia feedback sulla traduzione",
		["View Untranslated Messages"]="Mostra messaggi non tradotti", ["Transparent"]="Trasparente", ["Opaque"]="Opaco",
		["Largest"]="Più grande", ["Learn More"]="Scopri di più",
	},
	ja = {
		["Settings"]="設定", ["People"]="プレイヤー", ["Help"]="ヘルプ", ["Report"]="報告",
		["Invite friends to join"]="友達を招待", ["Invite"]="招待", ["Invited..."]="招待済み...",
		["Mute All"]="全員をミュート", ["Unmute All"]="全員のミュートを解除", ["Share Invite Link"]="招待リンクを共有",
		["Share"]="共有", ["Search for friends"]="友達を検索", ["Back"]="戻る",
		["Reset"]="リセット", ["Don't Reset"]="リセットしない", ["Reset Character"]="キャラクターをリセット",
		["Leave"]="退出", ["Don't Leave"]="退出しない", ["Leave Game"]="ゲームを退出", ["Resume Game"]="ゲームに戻る",
		["Are you sure you want to reset your character?"]="本当にキャラクターをリセットしますか？",
		["Are you sure you want to leave the game?"]="本当にゲームを退出しますか？",
		["Game or Player?"]="ゲームまたはプレイヤー？", ["Which Player?"]="プレイヤーを選択", ["Type Of Abuse"]="違反の種類",
		["In your own words, help us understand what went wrong."]="何が起きたのか、あなたの言葉で説明してください。",
		["Submit"]="送信", ["Game"]="ゲーム", ["Player"]="プレイヤー", ["Shift Lock"]="カメラロック",
		["Camera Mode"]="カメラモード", ["Movement Mode"]="移動モード", ["Experience Language"]="エクスペリエンスの言語",
		["Camera Sensitivity"]="カメラ感度", ["Volume"]="音量", ["Input Device"]="入力デバイス",
		["Output Device"]="出力デバイス", ["Fullscreen"]="全画面表示", ["Graphics Mode"]="グラフィックモード",
		["Graphics Quality"]="グラフィック品質", ["Performance Stats"]="パフォーマンス統計", ["Camera Inverted"]="カメラ反転",
		["Video Camera"]="ビデオカメラ", ["On"]="オン", ["Off"]="オフ", ["Show"]="表示", ["Hide"]="非表示",
		["Tap to Move"]="タップして移動", ["Click to Move"]="クリックして移動",
		["Experience Invite could not be sent. Please try again later."]="エクスペリエンスへの招待を送信できませんでした。後でもう一度お試しください。",
		["Set by Developer"]="開発者が設定", ["Automatic Chat Translation"]="チャットの自動翻訳",
		["Give Feedback"]="フィードバックを送信", ["Give Translation Feedback"]="翻訳についてフィードバック",
		["View Untranslated Messages"]="未翻訳のメッセージを表示", ["Transparent"]="透明", ["Opaque"]="不透明",
		["Largest"]="最大", ["Learn More"]="詳細を見る",
	},
	ko = {
		["Settings"]="설정", ["People"]="플레이어", ["Help"]="도움말", ["Report"]="신고",
		["Invite friends to join"]="친구 초대", ["Invite"]="초대", ["Invited..."]="초대됨...",
		["Mute All"]="모두 음소거", ["Unmute All"]="모두 음소거 해제", ["Share Invite Link"]="초대 링크 공유",
		["Share"]="공유", ["Search for friends"]="친구 검색", ["Back"]="뒤로",
		["Reset"]="초기화", ["Don't Reset"]="초기화 안 함", ["Reset Character"]="캐릭터 초기화",
		["Leave"]="나가기", ["Don't Leave"]="나가지 않기", ["Leave Game"]="게임 나가기", ["Resume Game"]="게임으로 돌아가기",
		["Are you sure you want to reset your character?"]="캐릭터를 초기화하시겠습니까?",
		["Are you sure you want to leave the game?"]="게임을 나가시겠습니까?",
		["Game or Player?"]="게임 또는 플레이어?", ["Which Player?"]="플레이어 선택", ["Type Of Abuse"]="신고 유형",
		["In your own words, help us understand what went wrong."]="무슨 일이 있었는지 직접 설명해 주세요.",
		["Submit"]="제출", ["Game"]="게임", ["Player"]="플레이어", ["Shift Lock"]="카메라 고정",
		["Camera Mode"]="카메라 모드", ["Movement Mode"]="이동 모드", ["Experience Language"]="체험 언어",
		["Camera Sensitivity"]="카메라 감도", ["Volume"]="음량", ["Input Device"]="입력 장치",
		["Output Device"]="출력 장치", ["Fullscreen"]="전체 화면", ["Graphics Mode"]="그래픽 모드",
		["Graphics Quality"]="그래픽 품질", ["Performance Stats"]="성능 통계", ["Camera Inverted"]="카메라 반전",
		["Video Camera"]="비디오 카메라", ["On"]="켜기", ["Off"]="끄기", ["Show"]="표시", ["Hide"]="숨기기",
		["Tap to Move"]="탭하여 이동", ["Click to Move"]="클릭하여 이동",
		["Experience Invite could not be sent. Please try again later."]="체험 초대를 보낼 수 없습니다. 나중에 다시 시도해 주세요.",
		["Set by Developer"]="개발자가 설정함", ["Automatic Chat Translation"]="자동 채팅 번역",
		["Give Feedback"]="의견 보내기", ["Give Translation Feedback"]="번역 의견 보내기",
		["View Untranslated Messages"]="번역되지 않은 메시지 보기", ["Transparent"]="투명", ["Opaque"]="불투명",
		["Largest"]="가장 크게", ["Learn More"]="자세히 알아보기",
	},
	ar = {
		["Settings"]="الإعدادات", ["People"]="اللاعبون", ["Help"]="المساعدة", ["Report"]="إبلاغ",
		["Invite friends to join"]="دعوة الأصدقاء", ["Invite"]="دعوة", ["Invited..."]="تمت الدعوة...",
		["Mute All"]="كتم صوت الجميع", ["Unmute All"]="إلغاء كتم صوت الجميع", ["Share Invite Link"]="مشاركة رابط الدعوة",
		["Share"]="مشاركة", ["Search for friends"]="البحث عن الأصدقاء", ["Back"]="رجوع",
		["Reset"]="إعادة ضبط", ["Don't Reset"]="عدم إعادة الضبط", ["Reset Character"]="إعادة ضبط الشخصية",
		["Leave"]="مغادرة", ["Don't Leave"]="عدم المغادرة", ["Leave Game"]="مغادرة اللعبة", ["Resume Game"]="متابعة اللعبة",
		["Are you sure you want to reset your character?"]="هل أنت متأكد من رغبتك في إعادة ضبط شخصيتك؟",
		["Are you sure you want to leave the game?"]="هل أنت متأكد من رغبتك في مغادرة اللعبة؟",
		["Game or Player?"]="اللعبة أم اللاعب؟", ["Which Player?"]="أي لاعب؟", ["Type Of Abuse"]="نوع الإساءة",
		["In your own words, help us understand what went wrong."]="اشرح بكلماتك ما حدث لمساعدتنا على فهم المشكلة.",
		["Submit"]="إرسال", ["Game"]="اللعبة", ["Player"]="اللاعب", ["Shift Lock"]="قفل الكاميرا",
		["Camera Mode"]="وضع الكاميرا", ["Movement Mode"]="وضع الحركة", ["Experience Language"]="لغة التجربة",
		["Camera Sensitivity"]="حساسية الكاميرا", ["Volume"]="مستوى الصوت", ["Input Device"]="جهاز الإدخال",
		["Output Device"]="جهاز الإخراج", ["Fullscreen"]="ملء الشاشة", ["Graphics Mode"]="وضع الرسومات",
		["Graphics Quality"]="جودة الرسومات", ["Performance Stats"]="إحصاءات الأداء", ["Camera Inverted"]="عكس الكاميرا",
		["Video Camera"]="كاميرا الفيديو", ["On"]="تشغيل", ["Off"]="إيقاف", ["Show"]="إظهار", ["Hide"]="إخفاء",
		["Tap to Move"]="اضغط للتحرك", ["Click to Move"]="انقر للتحرك",
		["Experience Invite could not be sent. Please try again later."]="تعذر إرسال دعوة التجربة. يُرجى المحاولة لاحقًا.",
		["Set by Developer"]="تم التعيين بواسطة المطوّر", ["Automatic Chat Translation"]="ترجمة الدردشة تلقائيًا",
		["Give Feedback"]="إرسال ملاحظات", ["Give Translation Feedback"]="إرسال ملاحظات الترجمة",
		["View Untranslated Messages"]="عرض الرسائل غير المترجمة", ["Transparent"]="شفاف", ["Opaque"]="معتم",
		["Largest"]="الأكبر", ["Learn More"]="معرفة المزيد",
	},
	tr = {
		["Settings"]="Ayarlar", ["People"]="Oyuncular", ["Help"]="Yardım", ["Report"]="Bildir",
		["Invite friends to join"]="Arkadaşları davet et", ["Invite"]="Davet et", ["Invited..."]="Davet edildi...",
		["Mute All"]="Herkesi sessize al", ["Unmute All"]="Herkesin sesini aç", ["Share Invite Link"]="Davet bağlantısını paylaş",
		["Share"]="Paylaş", ["Search for friends"]="Arkadaş ara", ["Back"]="Geri",
		["Reset"]="Sıfırla", ["Don't Reset"]="Sıfırlama", ["Reset Character"]="Karakteri sıfırla",
		["Leave"]="Ayrıl", ["Don't Leave"]="Ayrılma", ["Leave Game"]="Oyundan ayrıl", ["Resume Game"]="Oyuna dön",
		["Are you sure you want to reset your character?"]="Karakterini sıfırlamak istediğinden emin misin?",
		["Are you sure you want to leave the game?"]="Oyundan ayrılmak istediğinden emin misin?",
		["Game or Player?"]="Oyun mu oyuncu mu?", ["Which Player?"]="Hangi oyuncu?", ["Type Of Abuse"]="İhlal türü",
		["In your own words, help us understand what went wrong."]="Ne olduğunu anlamamıza yardımcı olmak için kendi sözlerinle açıkla.",
		["Submit"]="Gönder", ["Game"]="Oyun", ["Player"]="Oyuncu", ["Shift Lock"]="Kamera kilidi",
		["Camera Mode"]="Kamera modu", ["Movement Mode"]="Hareket modu", ["Experience Language"]="Deneyim dili",
		["Camera Sensitivity"]="Kamera hassasiyeti", ["Volume"]="Ses düzeyi", ["Input Device"]="Giriş aygıtı",
		["Output Device"]="Çıkış aygıtı", ["Fullscreen"]="Tam ekran", ["Graphics Mode"]="Grafik modu",
		["Graphics Quality"]="Grafik kalitesi", ["Performance Stats"]="Performans istatistikleri", ["Camera Inverted"]="Ters kamera",
		["Video Camera"]="Video kamera", ["On"]="Açık", ["Off"]="Kapalı", ["Show"]="Göster", ["Hide"]="Gizle",
		["Tap to Move"]="Hareket etmek için dokun", ["Click to Move"]="Hareket etmek için tıkla",
		["Experience Invite could not be sent. Please try again later."]="Deneyim daveti gönderilemedi. Lütfen daha sonra tekrar deneyin.",
		["Set by Developer"]="Geliştirici tarafından ayarlandı", ["Automatic Chat Translation"]="Otomatik sohbet çevirisi",
		["Give Feedback"]="Geri bildirim gönder", ["Give Translation Feedback"]="Çeviri hakkında geri bildirim gönder",
		["View Untranslated Messages"]="Çevrilmemiş mesajları göster", ["Transparent"]="Şeffaf", ["Opaque"]="Opak",
		["Largest"]="En büyük", ["Learn More"]="Daha fazla bilgi",
	},
	pl = {
		["Settings"]="Ustawienia", ["People"]="Gracze", ["Help"]="Pomoc", ["Report"]="Zgłoś",
		["Invite friends to join"]="Zaproś znajomych", ["Invite"]="Zaproś", ["Invited..."]="Zaproszono...",
		["Mute All"]="Wycisz wszystkich", ["Unmute All"]="Włącz dźwięk wszystkim", ["Share Invite Link"]="Udostępnij link zaproszenia",
		["Share"]="Udostępnij", ["Search for friends"]="Szukaj znajomych", ["Back"]="Wstecz",
		["Reset"]="Resetuj", ["Don't Reset"]="Nie resetuj", ["Reset Character"]="Resetuj postać",
		["Leave"]="Wyjdź", ["Don't Leave"]="Nie wychodź", ["Leave Game"]="Opuść grę", ["Resume Game"]="Wznów grę",
		["Are you sure you want to reset your character?"]="Czy na pewno chcesz zresetować postać?",
		["Are you sure you want to leave the game?"]="Czy na pewno chcesz opuścić grę?",
		["Game or Player?"]="Gra czy gracz?", ["Which Player?"]="Który gracz?", ["Type Of Abuse"]="Rodzaj naruszenia",
		["In your own words, help us understand what went wrong."]="Opisz własnymi słowami, co się stało.",
		["Submit"]="Prześlij", ["Game"]="Gra", ["Player"]="Gracz", ["Shift Lock"]="Blokada kamery",
		["Camera Mode"]="Tryb kamery", ["Movement Mode"]="Tryb poruszania", ["Experience Language"]="Język doświadczenia",
		["Camera Sensitivity"]="Czułość kamery", ["Volume"]="Głośność", ["Input Device"]="Urządzenie wejściowe",
		["Output Device"]="Urządzenie wyjściowe", ["Fullscreen"]="Pełny ekran", ["Graphics Mode"]="Tryb grafiki",
		["Graphics Quality"]="Jakość grafiki", ["Performance Stats"]="Statystyki wydajności", ["Camera Inverted"]="Odwrócona kamera",
		["Video Camera"]="Kamera wideo", ["On"]="Wł.", ["Off"]="Wył.", ["Show"]="Pokaż", ["Hide"]="Ukryj",
		["Tap to Move"]="Dotknij, aby się poruszyć", ["Click to Move"]="Kliknij, aby się poruszyć",
		["Experience Invite could not be sent. Please try again later."]="Nie udało się wysłać zaproszenia do gry. Spróbuj ponownie później.",
		["Set by Developer"]="Ustawione przez twórcę", ["Automatic Chat Translation"]="Automatyczne tłumaczenie czatu",
		["Give Feedback"]="Przekaż opinię", ["Give Translation Feedback"]="Przekaż opinię o tłumaczeniu",
		["View Untranslated Messages"]="Pokaż nieprzetłumaczone wiadomości", ["Transparent"]="Przezroczysty", ["Opaque"]="Nieprzezroczysty",
		["Largest"]="Największy", ["Learn More"]="Dowiedz się więcej",
	},
	id = {
		["Settings"]="Pengaturan", ["People"]="Pemain", ["Help"]="Bantuan", ["Report"]="Laporkan",
		["Invite friends to join"]="Undang teman", ["Invite"]="Undang", ["Invited..."]="Diundang...",
		["Mute All"]="Bisukan semua", ["Unmute All"]="Bunyikan semua", ["Share Invite Link"]="Bagikan tautan undangan",
		["Share"]="Bagikan", ["Search for friends"]="Cari teman", ["Back"]="Kembali",
		["Reset"]="Atur ulang", ["Don't Reset"]="Jangan atur ulang", ["Reset Character"]="Atur ulang karakter",
		["Leave"]="Keluar", ["Don't Leave"]="Jangan keluar", ["Leave Game"]="Keluar dari game", ["Resume Game"]="Lanjutkan game",
		["Are you sure you want to reset your character?"]="Yakin ingin mengatur ulang karakter?",
		["Are you sure you want to leave the game?"]="Yakin ingin keluar dari game?",
		["Game or Player?"]="Game atau pemain?", ["Which Player?"]="Pemain yang mana?", ["Type Of Abuse"]="Jenis pelanggaran",
		["In your own words, help us understand what went wrong."]="Jelaskan dengan kata-kata sendiri apa yang terjadi.",
		["Submit"]="Kirim", ["Game"]="Game", ["Player"]="Pemain", ["Shift Lock"]="Kunci kamera",
		["Camera Mode"]="Mode kamera", ["Movement Mode"]="Mode gerakan", ["Experience Language"]="Bahasa pengalaman",
		["Camera Sensitivity"]="Sensitivitas kamera", ["Volume"]="Volume", ["Input Device"]="Perangkat input",
		["Output Device"]="Perangkat output", ["Fullscreen"]="Layar penuh", ["Graphics Mode"]="Mode grafis",
		["Graphics Quality"]="Kualitas grafis", ["Performance Stats"]="Statistik performa", ["Camera Inverted"]="Kamera terbalik",
		["Video Camera"]="Kamera video", ["On"]="Aktif", ["Off"]="Nonaktif", ["Show"]="Tampilkan", ["Hide"]="Sembunyikan",
		["Tap to Move"]="Ketuk untuk bergerak", ["Click to Move"]="Klik untuk bergerak",
		["Experience Invite could not be sent. Please try again later."]="Undangan pengalaman tidak dapat dikirim. Coba lagi nanti.",
		["Set by Developer"]="Diatur oleh pengembang", ["Automatic Chat Translation"]="Terjemahan chat otomatis",
		["Give Feedback"]="Kirim masukan", ["Give Translation Feedback"]="Kirim masukan terjemahan",
		["View Untranslated Messages"]="Lihat pesan yang belum diterjemahkan", ["Transparent"]="Transparan", ["Opaque"]="Buram",
		["Largest"]="Terbesar", ["Learn More"]="Pelajari lebih lanjut",
	},
	vi = {
		["Settings"]="Cài đặt", ["People"]="Người chơi", ["Help"]="Trợ giúp", ["Report"]="Báo cáo",
		["Invite friends to join"]="Mời bạn bè tham gia", ["Invite"]="Mời", ["Invited..."]="Đã mời...",
		["Mute All"]="Tắt tiếng tất cả", ["Unmute All"]="Bật tiếng tất cả", ["Share Invite Link"]="Chia sẻ liên kết mời",
		["Share"]="Chia sẻ", ["Search for friends"]="Tìm bạn bè", ["Back"]="Quay lại",
		["Reset"]="Đặt lại", ["Don't Reset"]="Không đặt lại", ["Reset Character"]="Đặt lại nhân vật",
		["Leave"]="Rời khỏi", ["Don't Leave"]="Không rời khỏi", ["Leave Game"]="Thoát trò chơi", ["Resume Game"]="Tiếp tục trò chơi",
		["Are you sure you want to reset your character?"]="Bạn có chắc muốn đặt lại nhân vật không?",
		["Are you sure you want to leave the game?"]="Bạn có chắc muốn thoát trò chơi không?",
		["Game or Player?"]="Trò chơi hay người chơi?", ["Which Player?"]="Người chơi nào?", ["Type Of Abuse"]="Loại vi phạm",
		["In your own words, help us understand what went wrong."]="Hãy mô tả bằng lời của bạn để giúp chúng tôi hiểu chuyện gì đã xảy ra.",
		["Submit"]="Gửi", ["Game"]="Trò chơi", ["Player"]="Người chơi", ["Shift Lock"]="Khóa camera",
		["Camera Mode"]="Chế độ camera", ["Movement Mode"]="Chế độ di chuyển", ["Experience Language"]="Ngôn ngữ trải nghiệm",
		["Camera Sensitivity"]="Độ nhạy camera", ["Volume"]="Âm lượng", ["Input Device"]="Thiết bị đầu vào",
		["Output Device"]="Thiết bị đầu ra", ["Fullscreen"]="Toàn màn hình", ["Graphics Mode"]="Chế độ đồ họa",
		["Graphics Quality"]="Chất lượng đồ họa", ["Performance Stats"]="Thống kê hiệu suất", ["Camera Inverted"]="Đảo ngược camera",
		["Video Camera"]="Máy quay video", ["On"]="Bật", ["Off"]="Tắt", ["Show"]="Hiện", ["Hide"]="Ẩn",
		["Tap to Move"]="Chạm để di chuyển", ["Click to Move"]="Nhấp để di chuyển",
		["Experience Invite could not be sent. Please try again later."]="Không thể gửi lời mời trải nghiệm. Vui lòng thử lại sau.",
		["Set by Developer"]="Do nhà phát triển đặt", ["Automatic Chat Translation"]="Tự động dịch trò chuyện",
		["Give Feedback"]="Gửi phản hồi", ["Give Translation Feedback"]="Gửi phản hồi về bản dịch",
		["View Untranslated Messages"]="Xem tin nhắn chưa dịch", ["Transparent"]="Trong suốt", ["Opaque"]="Đục",
		["Largest"]="Lớn nhất", ["Learn More"]="Tìm hiểu thêm",
	},
	th = {
		["Settings"]="การตั้งค่า", ["People"]="ผู้เล่น", ["Help"]="ช่วยเหลือ", ["Report"]="รายงาน",
		["Invite friends to join"]="เชิญเพื่อนเข้าร่วม", ["Invite"]="เชิญ", ["Invited..."]="เชิญแล้ว...",
		["Mute All"]="ปิดเสียงทั้งหมด", ["Unmute All"]="เปิดเสียงทั้งหมด", ["Share Invite Link"]="แชร์ลิงก์คำเชิญ",
		["Share"]="แชร์", ["Search for friends"]="ค้นหาเพื่อน", ["Back"]="ย้อนกลับ",
		["Reset"]="รีเซ็ต", ["Don't Reset"]="ไม่รีเซ็ต", ["Reset Character"]="รีเซ็ตตัวละคร",
		["Leave"]="ออก", ["Don't Leave"]="ไม่ออก", ["Leave Game"]="ออกจากเกม", ["Resume Game"]="เล่นเกมต่อ",
		["Are you sure you want to reset your character?"]="คุณแน่ใจหรือไม่ว่าต้องการรีเซ็ตตัวละคร?",
		["Are you sure you want to leave the game?"]="คุณแน่ใจหรือไม่ว่าต้องการออกจากเกม?",
		["Game or Player?"]="เกมหรือผู้เล่น?", ["Which Player?"]="ผู้เล่นคนใด?", ["Type Of Abuse"]="ประเภทการละเมิด",
		["In your own words, help us understand what went wrong."]="โปรดอธิบายด้วยคำพูดของคุณเองว่าเกิดอะไรขึ้น",
		["Submit"]="ส่ง", ["Game"]="เกม", ["Player"]="ผู้เล่น", ["Shift Lock"]="ล็อกกล้อง",
		["Camera Mode"]="โหมดกล้อง", ["Movement Mode"]="โหมดการเคลื่อนไหว", ["Experience Language"]="ภาษาในประสบการณ์",
		["Camera Sensitivity"]="ความไวของกล้อง", ["Volume"]="ระดับเสียง", ["Input Device"]="อุปกรณ์อินพุต",
		["Output Device"]="อุปกรณ์เอาต์พุต", ["Fullscreen"]="เต็มหน้าจอ", ["Graphics Mode"]="โหมดกราฟิก",
		["Graphics Quality"]="คุณภาพกราฟิก", ["Performance Stats"]="สถิติประสิทธิภาพ", ["Camera Inverted"]="กลับด้านกล้อง",
		["Video Camera"]="กล้องวิดีโอ", ["On"]="เปิด", ["Off"]="ปิด", ["Show"]="แสดง", ["Hide"]="ซ่อน",
		["Tap to Move"]="แตะเพื่อเคลื่อนที่", ["Click to Move"]="คลิกเพื่อเคลื่อนที่",
		["Experience Invite could not be sent. Please try again later."]="ส่งคำเชิญเข้าประสบการณ์ไม่สำเร็จ โปรดลองอีกครั้งในภายหลัง",
		["Set by Developer"]="ตั้งค่าโดยผู้พัฒนา", ["Automatic Chat Translation"]="แปลแชทอัตโนมัติ",
		["Give Feedback"]="ส่งความคิดเห็น", ["Give Translation Feedback"]="ส่งความคิดเห็นเกี่ยวกับคำแปล",
		["View Untranslated Messages"]="แสดงข้อความที่ยังไม่ได้แปล", ["Transparent"]="โปร่งใส", ["Opaque"]="ทึบ",
		["Largest"]="ใหญ่ที่สุด", ["Learn More"]="เรียนรู้เพิ่มเติม",
	},
	nl = {
		["Settings"]="Instellingen", ["People"]="Spelers", ["Help"]="Help", ["Report"]="Melden",
		["Invite friends to join"]="Vrienden uitnodigen", ["Invite"]="Uitnodigen", ["Invited..."]="Uitgenodigd...",
		["Mute All"]="Iedereen dempen", ["Unmute All"]="Dempen voor iedereen opheffen", ["Share Invite Link"]="Uitnodigingslink delen",
		["Share"]="Delen", ["Search for friends"]="Vrienden zoeken", ["Back"]="Terug",
		["Reset"]="Resetten", ["Don't Reset"]="Niet resetten", ["Reset Character"]="Personage resetten",
		["Leave"]="Verlaten", ["Don't Leave"]="Niet verlaten", ["Leave Game"]="Spel verlaten", ["Resume Game"]="Spel hervatten",
		["Are you sure you want to reset your character?"]="Weet je zeker dat je je personage wilt resetten?",
		["Are you sure you want to leave the game?"]="Weet je zeker dat je het spel wilt verlaten?",
		["Game or Player?"]="Spel of speler?", ["Which Player?"]="Welke speler?", ["Type Of Abuse"]="Soort overtreding",
		["In your own words, help us understand what went wrong."]="Beschrijf in je eigen woorden wat er is gebeurd.",
		["Submit"]="Verzenden", ["Game"]="Spel", ["Player"]="Speler", ["Shift Lock"]="Cameravergrendeling",
		["Camera Mode"]="Cameramodus", ["Movement Mode"]="Bewegingsmodus", ["Experience Language"]="Ervaringstaal",
		["Camera Sensitivity"]="Cameragevoeligheid", ["Volume"]="Volume", ["Input Device"]="Invoerapparaat",
		["Output Device"]="Uitvoerapparaat", ["Fullscreen"]="Volledig scherm", ["Graphics Mode"]="Grafische modus",
		["Graphics Quality"]="Grafische kwaliteit", ["Performance Stats"]="Prestatiestatistieken", ["Camera Inverted"]="Camera omkeren",
		["Video Camera"]="Videocamera", ["On"]="Aan", ["Off"]="Uit", ["Show"]="Tonen", ["Hide"]="Verbergen",
		["Tap to Move"]="Tik om te bewegen", ["Click to Move"]="Klik om te bewegen",
		["Experience Invite could not be sent. Please try again later."]="De uitnodiging voor de ervaring kon niet worden verzonden. Probeer het later opnieuw.",
		["Set by Developer"]="Ingesteld door ontwikkelaar", ["Automatic Chat Translation"]="Automatische chatvertaling",
		["Give Feedback"]="Feedback geven", ["Give Translation Feedback"]="Feedback over vertaling geven",
		["View Untranslated Messages"]="Niet-vertaalde berichten tonen", ["Transparent"]="Transparant", ["Opaque"]="Ondoorzichtig",
		["Largest"]="Grootst", ["Learn More"]="Meer informatie",
	},
}

-- Extra fallbacks for more Roblox-supported languages. The full CoreScript
-- localization tables still take priority for stock phrases; these cover the
-- custom invite/report wording most likely to be absent from historical tables.
MenuFallbackTranslations.ms = {
	["Invite friends to join"]="Jemput rakan untuk menyertai", ["Share Invite Link"]="Kongsi pautan jemputan",
	["Search for friends"]="Cari rakan", ["Mute All"]="Senyapkan semua", ["Unmute All"]="Nyahsenyap semua",
	["Reset"]="Tetapkan semula", ["Don't Reset"]="Jangan tetapkan semula", ["Reset Character"]="Tetapkan semula watak",
	["Leave"]="Keluar", ["Don't Leave"]="Jangan keluar", ["Resume Game"]="Sambung permainan",
	["Experience Language"]="Bahasa pengalaman", ["Game or Player?"]="Permainan atau pemain?",
	["Which Player?"]="Pemain yang mana?", ["Type Of Abuse"]="Jenis salah laku", ["Submit"]="Hantar",
	["In your own words, help us understand what went wrong."]="Terangkan dengan kata-kata anda sendiri perkara yang berlaku.",
	["Experience Invite could not be sent. Please try again later."]="Jemputan pengalaman tidak dapat dihantar. Sila cuba lagi kemudian.",
}
MenuFallbackTranslations.fil = {
	["Invite friends to join"]="Imbitahan ang mga kaibigan", ["Share Invite Link"]="Ibahagi ang link ng imbitasyon",
	["Search for friends"]="Maghanap ng mga kaibigan", ["Mute All"]="I-mute ang lahat", ["Unmute All"]="I-unmute ang lahat",
	["Reset"]="I-reset", ["Don't Reset"]="Huwag i-reset", ["Reset Character"]="I-reset ang karakter",
	["Leave"]="Umalis", ["Don't Leave"]="Huwag umalis", ["Resume Game"]="Ipagpatuloy ang laro",
	["Experience Language"]="Wika ng experience", ["Game or Player?"]="Laro o manlalaro?",
	["Which Player?"]="Aling manlalaro?", ["Type Of Abuse"]="Uri ng pang-aabuso", ["Submit"]="Isumite",
	["In your own words, help us understand what went wrong."]="Sa sarili mong mga salita, ipaliwanag kung ano ang nangyari.",
	["Experience Invite could not be sent. Please try again later."]="Hindi naipadala ang imbitasyon sa experience. Pakisubukang muli mamaya.",
}
MenuFallbackTranslations.bn = {
	["Invite friends to join"]="বন্ধুদের আমন্ত্রণ জানান", ["Share Invite Link"]="আমন্ত্রণের লিংক শেয়ার করুন",
	["Search for friends"]="বন্ধু খুঁজুন", ["Mute All"]="সবাইকে মিউট করুন", ["Unmute All"]="সবার মিউট বন্ধ করুন",
	["Reset"]="রিসেট", ["Don't Reset"]="রিসেট করবেন না", ["Reset Character"]="চরিত্র রিসেট করুন",
	["Leave"]="বেরিয়ে যান", ["Don't Leave"]="বেরিয়ে যাবেন না", ["Resume Game"]="গেম চালিয়ে যান",
	["Experience Language"]="অভিজ্ঞতার ভাষা", ["Game or Player?"]="গেম নাকি খেলোয়াড়?",
	["Which Player?"]="কোন খেলোয়াড়?", ["Type Of Abuse"]="অপব্যবহারের ধরন", ["Submit"]="জমা দিন",
	["In your own words, help us understand what went wrong."]="কী ঘটেছে তা বুঝতে নিজের ভাষায় ব্যাখ্যা করুন।",
	["Experience Invite could not be sent. Please try again later."]="অভিজ্ঞতার আমন্ত্রণ পাঠানো যায়নি। অনুগ্রহ করে পরে আবার চেষ্টা করুন।",
}
MenuFallbackTranslations.ro = {
	["Invite friends to join"]="Invită prieteni", ["Share Invite Link"]="Partajează linkul de invitație",
	["Search for friends"]="Caută prieteni", ["Mute All"]="Dezactivează sunetul tuturor", ["Unmute All"]="Activează sunetul tuturor",
	["Reset"]="Resetează", ["Don't Reset"]="Nu reseta", ["Reset Character"]="Resetează personajul",
	["Leave"]="Ieși", ["Don't Leave"]="Rămâi", ["Resume Game"]="Reia jocul",
	["Experience Language"]="Limba experienței", ["Game or Player?"]="Joc sau jucător?",
	["Which Player?"]="Care jucător?", ["Type Of Abuse"]="Tipul abuzului", ["Submit"]="Trimite",
	["In your own words, help us understand what went wrong."]="Descrie cu propriile cuvinte ce s-a întâmplat.",
	["Experience Invite could not be sent. Please try again later."]="Invitația la experiență nu a putut fi trimisă. Încearcă din nou mai târziu.",
}
MenuFallbackTranslations.cs = {
	["Invite friends to join"]="Pozvat přátele", ["Share Invite Link"]="Sdílet odkaz s pozvánkou",
	["Search for friends"]="Hledat přátele", ["Mute All"]="Ztlumit všechny", ["Unmute All"]="Zapnout zvuk všem",
	["Reset"]="Obnovit", ["Don't Reset"]="Neobnovovat", ["Reset Character"]="Obnovit postavu",
	["Leave"]="Odejít", ["Don't Leave"]="Neodcházet", ["Resume Game"]="Pokračovat ve hře",
	["Experience Language"]="Jazyk zážitku", ["Game or Player?"]="Hra nebo hráč?",
	["Which Player?"]="Který hráč?", ["Type Of Abuse"]="Typ zneužití", ["Submit"]="Odeslat",
	["In your own words, help us understand what went wrong."]="Vlastními slovy popište, co se stalo.",
	["Experience Invite could not be sent. Please try again later."]="Pozvánku do zážitku se nepodařilo odeslat. Zkuste to prosím později.",
}
MenuFallbackTranslations.el = {
	["Invite friends to join"]="Πρόσκληση φίλων", ["Share Invite Link"]="Κοινοποίηση συνδέσμου πρόσκλησης",
	["Search for friends"]="Αναζήτηση φίλων", ["Mute All"]="Σίγαση όλων", ["Unmute All"]="Κατάργηση σίγασης όλων",
	["Reset"]="Επαναφορά", ["Don't Reset"]="Να μην γίνει επαναφορά", ["Reset Character"]="Επαναφορά χαρακτήρα",
	["Leave"]="Έξοδος", ["Don't Leave"]="Παραμονή", ["Resume Game"]="Συνέχεια παιχνιδιού",
	["Experience Language"]="Γλώσσα εμπειρίας", ["Game or Player?"]="Παιχνίδι ή παίκτης;",
	["Which Player?"]="Ποιος παίκτης;", ["Type Of Abuse"]="Τύπος παραβίασης", ["Submit"]="Υποβολή",
	["In your own words, help us understand what went wrong."]="Περιγράψτε με δικά σας λόγια τι συνέβη.",
	["Experience Invite could not be sent. Please try again later."]="Δεν ήταν δυνατή η αποστολή πρόσκλησης στην εμπειρία. Δοκιμάστε ξανά αργότερα.",
}
MenuFallbackTranslations.he = {
	["Invite friends to join"]="הזמנת חברים להצטרף", ["Share Invite Link"]="שיתוף קישור להזמנה",
	["Search for friends"]="חיפוש חברים", ["Mute All"]="השתקת כולם", ["Unmute All"]="ביטול השתקה לכולם",
	["Reset"]="איפוס", ["Don't Reset"]="לא לאפס", ["Reset Character"]="איפוס הדמות",
	["Leave"]="יציאה", ["Don't Leave"]="לא לצאת", ["Resume Game"]="חזרה למשחק",
	["Experience Language"]="שפת החוויה", ["Game or Player?"]="משחק או שחקן?",
	["Which Player?"]="איזה שחקן?", ["Type Of Abuse"]="סוג ההפרה", ["Submit"]="שליחה",
	["In your own words, help us understand what went wrong."]="תארו במילים שלכם מה קרה כדי שנוכל להבין את הבעיה.",
	["Experience Invite could not be sent. Please try again later."]="לא ניתן היה לשלוח את ההזמנה לחוויה. נסו שוב מאוחר יותר.",
}
MenuFallbackTranslations.sv = {
	["Invite friends to join"]="Bjud in vänner", ["Share Invite Link"]="Dela inbjudningslänk", ["Search for friends"]="Sök efter vänner",
	["Mute All"]="Ljud av för alla", ["Unmute All"]="Ljud på för alla", ["Reset"]="Återställ", ["Don't Reset"]="Återställ inte",
	["Reset Character"]="Återställ karaktär", ["Leave"]="Lämna", ["Don't Leave"]="Stanna kvar", ["Resume Game"]="Återuppta spelet",
	["Experience Language"]="Upplevelsespråk", ["Game or Player?"]="Spel eller spelare?", ["Which Player?"]="Vilken spelare?",
	["Type Of Abuse"]="Typ av överträdelse", ["Submit"]="Skicka", ["In your own words, help us understand what went wrong."]="Beskriv med egna ord vad som hände.",
	["Experience Invite could not be sent. Please try again later."]="Det gick inte att skicka inbjudan till upplevelsen. Försök igen senare.",
}
MenuFallbackTranslations.da = {
	["Invite friends to join"]="Inviter venner", ["Share Invite Link"]="Del invitationslink", ["Search for friends"]="Søg efter venner",
	["Mute All"]="Slå lyden fra for alle", ["Unmute All"]="Slå lyden til for alle", ["Reset"]="Nulstil", ["Don't Reset"]="Nulstil ikke",
	["Reset Character"]="Nulstil figur", ["Leave"]="Forlad", ["Don't Leave"]="Bliv", ["Resume Game"]="Fortsæt spillet",
	["Experience Language"]="Oplevelsessprog", ["Game or Player?"]="Spil eller spiller?", ["Which Player?"]="Hvilken spiller?",
	["Type Of Abuse"]="Type af overtrædelse", ["Submit"]="Send", ["In your own words, help us understand what went wrong."]="Beskriv med dine egne ord, hvad der skete.",
	["Experience Invite could not be sent. Please try again later."]="Invitationen til oplevelsen kunne ikke sendes. Prøv igen senere.",
}
MenuFallbackTranslations.nb = {
	["Invite friends to join"]="Inviter venner", ["Share Invite Link"]="Del invitasjonslenke", ["Search for friends"]="Søk etter venner",
	["Mute All"]="Demp alle", ["Unmute All"]="Slå på lyd for alle", ["Reset"]="Tilbakestill", ["Don't Reset"]="Ikke tilbakestill",
	["Reset Character"]="Tilbakestill figur", ["Leave"]="Forlat", ["Don't Leave"]="Bli", ["Resume Game"]="Fortsett spillet",
	["Experience Language"]="Opplevelsens språk", ["Game or Player?"]="Spill eller spiller?", ["Which Player?"]="Hvilken spiller?",
	["Type Of Abuse"]="Type regelbrudd", ["Submit"]="Send inn", ["In your own words, help us understand what went wrong."]="Beskriv med egne ord hva som skjedde.",
	["Experience Invite could not be sent. Please try again later."]="Kunne ikke sende invitasjonen til opplevelsen. Prøv igjen senere.",
}
MenuFallbackTranslations.fi = {
	["Invite friends to join"]="Kutsu ystäviä", ["Share Invite Link"]="Jaa kutsulinkki", ["Search for friends"]="Etsi ystäviä",
	["Mute All"]="Mykistä kaikki", ["Unmute All"]="Poista kaikkien mykistys", ["Reset"]="Nollaa", ["Don't Reset"]="Älä nollaa",
	["Reset Character"]="Nollaa hahmo", ["Leave"]="Poistu", ["Don't Leave"]="Älä poistu", ["Resume Game"]="Jatka peliä",
	["Experience Language"]="Kokemuksen kieli", ["Game or Player?"]="Peli vai pelaaja?", ["Which Player?"]="Mikä pelaaja?",
	["Type Of Abuse"]="Rikkomuksen tyyppi", ["Submit"]="Lähetä", ["In your own words, help us understand what went wrong."]="Kuvaile omin sanoin, mitä tapahtui.",
	["Experience Invite could not be sent. Please try again later."]="Kutsua kokemukseen ei voitu lähettää. Yritä myöhemmin uudelleen.",
}
MenuFallbackTranslations.hu = {
	["Invite friends to join"]="Barátok meghívása", ["Share Invite Link"]="Meghívó hivatkozás megosztása", ["Search for friends"]="Barátok keresése",
	["Mute All"]="Mindenki némítása", ["Unmute All"]="Mindenki némításának feloldása", ["Reset"]="Visszaállítás", ["Don't Reset"]="Ne állítsd vissza",
	["Reset Character"]="Karakter visszaállítása", ["Leave"]="Kilépés", ["Don't Leave"]="Maradás", ["Resume Game"]="Játék folytatása",
	["Experience Language"]="Élmény nyelve", ["Game or Player?"]="Játék vagy játékos?", ["Which Player?"]="Melyik játékos?",
	["Type Of Abuse"]="Visszaélés típusa", ["Submit"]="Küldés", ["In your own words, help us understand what went wrong."]="Saját szavaiddal írd le, mi történt.",
	["Experience Invite could not be sent. Please try again later."]="Nem sikerült elküldeni az élmény meghívóját. Próbáld újra később.",
}
MenuFallbackTranslations.bg = {
	["Invite friends to join"]="Покани приятели", ["Share Invite Link"]="Сподели връзката за покана", ["Search for friends"]="Търси приятели",
	["Mute All"]="Изключи звука на всички", ["Unmute All"]="Включи звука на всички", ["Reset"]="Нулиране", ["Don't Reset"]="Без нулиране",
	["Reset Character"]="Нулиране на героя", ["Leave"]="Изход", ["Don't Leave"]="Остани", ["Resume Game"]="Продължи играта",
	["Experience Language"]="Език на преживяването", ["Game or Player?"]="Игра или играч?", ["Which Player?"]="Кой играч?",
	["Type Of Abuse"]="Вид нарушение", ["Submit"]="Изпрати", ["In your own words, help us understand what went wrong."]="Опиши със свои думи какво се случи.",
	["Experience Invite could not be sent. Please try again later."]="Поканата за преживяването не можа да бъде изпратена. Опитай отново по-късно.",
}

-- Additional custom menu wording not normally found in stock CoreScript tables.
MenuAdditionalTranslations = {
	["ru"] = {
		["Record"] = "Запись",
		["Record Video"] = "Записать видео",
		["Stop Recording"] = "Остановить запись",
		["Screenshot"] = "Снимок экрана",
		["Video"] = "Видео",
		["Take Screenshot"] = "Сделать снимок экрана",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Нажмите «Сделать снимок экрана», чтобы закрыть меню, сделать снимок и сохранить его на компьютере.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Нажмите «Записать видео», чтобы начать запись. Нажмите ещё раз, чтобы остановить её.",
		["In Experience"] = "В игре",
		["In Studio"] = "В Roblox Studio",
		["People's Names"] = "Имена игроков",
		["My Badges"] = "Мои значки",
		["Reduce Motion"] = "Уменьшить анимацию",
		["Text Size"] = "Размер текста",
		["Maximum Frame Rate"] = "Максимальная частота кадров",
		["Chat & Language"] = "Чат и язык",
		["Display & Graphics"] = "Экран и графика",
		["View & Controls"] = "Обзор и управление",
		["Inappropriate Content"] = "Неприемлемый контент",
		["Swearing"] = "Нецензурная лексика",
		["Inappropriate Username"] = "Неподходящее имя пользователя",
		["Bullying"] = "Травля",
		["Scamming"] = "Мошенничество",
		["Dating"] = "Свидания",
		["Cheating/Exploiting"] = "Читерство и эксплойты",
		["Personal Question"] = "Личный вопрос",
		["Offsite Links"] = "Внешние ссылки",
	},
	["uk"] = {
		["Record"] = "Запис",
		["Record Video"] = "Записати відео",
		["Stop Recording"] = "Зупинити запис",
		["Screenshot"] = "Знімок екрана",
		["Video"] = "Відео",
		["Take Screenshot"] = "Зробити знімок екрана",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Натисніть «Зробити знімок екрана», щоб закрити меню, зробити знімок і зберегти його на комп’ютері.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Натисніть «Записати відео», щоб почати запис. Натисніть ще раз, щоб зупинити його.",
		["In Experience"] = "У грі",
		["In Studio"] = "У Roblox Studio",
		["People's Names"] = "Імена гравців",
		["My Badges"] = "Мої значки",
		["Reduce Motion"] = "Зменшити анімацію",
		["Text Size"] = "Розмір тексту",
		["Maximum Frame Rate"] = "Максимальна частота кадрів",
		["Chat & Language"] = "Чат і мова",
		["Display & Graphics"] = "Екран і графіка",
		["View & Controls"] = "Перегляд і керування",
		["Inappropriate Content"] = "Неприйнятний вміст",
		["Swearing"] = "Лайка",
		["Inappropriate Username"] = "Неприйнятне ім’я користувача",
		["Bullying"] = "Булінг",
		["Scamming"] = "Шахрайство",
		["Dating"] = "Знайомства",
		["Cheating/Exploiting"] = "Читерство та експлойти",
		["Personal Question"] = "Особисте запитання",
		["Offsite Links"] = "Зовнішні посилання",
	},
	["es"] = {
		["Record"] = "Grabación",
		["Record Video"] = "Grabar video",
		["Stop Recording"] = "Detener grabación",
		["Screenshot"] = "Captura de pantalla",
		["Video"] = "Video",
		["Take Screenshot"] = "Tomar captura de pantalla",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Haz clic en «Tomar captura de pantalla» para cerrar el menú, tomar una captura y guardarla en tu computadora.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Haz clic en «Grabar video» para comenzar a grabar. Haz clic otra vez para detener la grabación.",
		["In Experience"] = "En la experiencia",
		["In Studio"] = "En Roblox Studio",
		["People's Names"] = "Nombres de los jugadores",
		["My Badges"] = "Mis insignias",
		["Reduce Motion"] = "Reducir movimiento",
		["Text Size"] = "Tamaño del texto",
		["Maximum Frame Rate"] = "Frecuencia máxima de fotogramas",
		["Chat & Language"] = "Chat e idioma",
		["Display & Graphics"] = "Pantalla y gráficos",
		["View & Controls"] = "Vista y controles",
		["Inappropriate Content"] = "Contenido inapropiado",
		["Swearing"] = "Insultos",
		["Inappropriate Username"] = "Nombre de usuario inapropiado",
		["Bullying"] = "Acoso",
		["Scamming"] = "Estafas",
		["Dating"] = "Citas",
		["Cheating/Exploiting"] = "Trampas y exploits",
		["Personal Question"] = "Pregunta personal",
		["Offsite Links"] = "Enlaces externos",
	},
	["pt"] = {
		["Record"] = "Gravação",
		["Record Video"] = "Gravar vídeo",
		["Stop Recording"] = "Parar gravação",
		["Screenshot"] = "Captura de tela",
		["Video"] = "Vídeo",
		["Take Screenshot"] = "Fazer captura de tela",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Clique em «Fazer captura de tela» para fechar o menu, capturar a tela e salvar a imagem no computador.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Clique em «Gravar vídeo» para começar a gravar. Clique novamente para parar a gravação.",
		["In Experience"] = "Na experiência",
		["In Studio"] = "No Roblox Studio",
		["People's Names"] = "Nomes dos jogadores",
		["My Badges"] = "Meus emblemas",
		["Reduce Motion"] = "Reduzir movimento",
		["Text Size"] = "Tamanho do texto",
		["Maximum Frame Rate"] = "Taxa máxima de quadros",
		["Chat & Language"] = "Chat e idioma",
		["Display & Graphics"] = "Tela e gráficos",
		["View & Controls"] = "Visualização e controles",
		["Inappropriate Content"] = "Conteúdo impróprio",
		["Swearing"] = "Palavrões",
		["Inappropriate Username"] = "Nome de usuário impróprio",
		["Bullying"] = "Bullying",
		["Scamming"] = "Golpes",
		["Dating"] = "Namoro",
		["Cheating/Exploiting"] = "Trapaças e exploits",
		["Personal Question"] = "Pergunta pessoal",
		["Offsite Links"] = "Links externos",
	},
	["zh-cn"] = {
		["Record"] = "录制",
		["Record Video"] = "录制视频",
		["Stop Recording"] = "停止录制",
		["Screenshot"] = "屏幕截图",
		["Video"] = "视频",
		["Take Screenshot"] = "截取屏幕截图",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "点击“截取屏幕截图”按钮后，菜单将关闭，截图会保存到你的电脑。",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "点击“录制视频”按钮开始录制。再次点击即可停止录制。",
		["In Experience"] = "游戏中",
		["In Studio"] = "在 Roblox Studio 中",
		["People's Names"] = "玩家名称",
		["My Badges"] = "我的徽章",
		["Reduce Motion"] = "减少动态效果",
		["Text Size"] = "文字大小",
		["Maximum Frame Rate"] = "最高帧率",
		["Chat & Language"] = "聊天与语言",
		["Display & Graphics"] = "显示与图形",
		["View & Controls"] = "视角与控制",
		["Inappropriate Content"] = "不当内容",
		["Swearing"] = "辱骂",
		["Inappropriate Username"] = "不当用户名",
		["Bullying"] = "欺凌",
		["Scamming"] = "诈骗",
		["Dating"] = "约会",
		["Cheating/Exploiting"] = "作弊/利用漏洞",
		["Personal Question"] = "个人问题",
		["Offsite Links"] = "站外链接",
	},
	["zh-tw"] = {
		["Record"] = "錄製",
		["Record Video"] = "錄製影片",
		["Stop Recording"] = "停止錄製",
		["Screenshot"] = "螢幕截圖",
		["Video"] = "影片",
		["Take Screenshot"] = "擷取螢幕截圖",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "按一下「擷取螢幕截圖」按鈕後，選單會關閉，截圖會儲存到你的電腦。",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "按一下「錄製影片」按鈕開始錄製。再次按一下即可停止錄製。",
		["In Experience"] = "遊戲中",
		["In Studio"] = "在 Roblox Studio 中",
		["People's Names"] = "玩家名稱",
		["My Badges"] = "我的徽章",
		["Reduce Motion"] = "減少動態效果",
		["Text Size"] = "文字大小",
		["Maximum Frame Rate"] = "最高影格率",
		["Chat & Language"] = "聊天與語言",
		["Display & Graphics"] = "顯示與圖形",
		["View & Controls"] = "檢視與控制",
		["Inappropriate Content"] = "不當內容",
		["Swearing"] = "辱罵",
		["Inappropriate Username"] = "不當使用者名稱",
		["Bullying"] = "霸凌",
		["Scamming"] = "詐騙",
		["Dating"] = "約會",
		["Cheating/Exploiting"] = "作弊／利用漏洞",
		["Personal Question"] = "個人問題",
		["Offsite Links"] = "站外連結",
	},
	["hi"] = {
		["Record"] = "रिकॉर्डिंग",
		["Record Video"] = "वीडियो रिकॉर्ड करें",
		["Stop Recording"] = "रिकॉर्डिंग रोकें",
		["Screenshot"] = "स्क्रीनशॉट",
		["Video"] = "वीडियो",
		["Take Screenshot"] = "स्क्रीनशॉट लें",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "स्क्रीनशॉट लेने के लिए बटन पर क्लिक करें। मेनू बंद हो जाएगा और स्क्रीनशॉट आपके कंप्यूटर पर सेव होगा।",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "रिकॉर्डिंग शुरू करने के लिए “वीडियो रिकॉर्ड करें” पर क्लिक करें। रोकने के लिए फिर से क्लिक करें।",
		["In Experience"] = "अनुभव में",
		["In Studio"] = "Roblox Studio में",
		["People's Names"] = "खिलाड़ियों के नाम",
		["My Badges"] = "मेरे बैज",
		["Reduce Motion"] = "मोशन कम करें",
		["Text Size"] = "टेक्स्ट आकार",
		["Maximum Frame Rate"] = "अधिकतम फ्रेम दर",
		["Chat & Language"] = "चैट और भाषा",
		["Display & Graphics"] = "डिस्प्ले और ग्राफ़िक्स",
		["View & Controls"] = "दृश्य और नियंत्रण",
		["Inappropriate Content"] = "अनुचित सामग्री",
		["Swearing"] = "गाली-गलौज",
		["Inappropriate Username"] = "अनुचित यूज़रनेम",
		["Bullying"] = "धौंस जमाना",
		["Scamming"] = "धोखाधड़ी",
		["Dating"] = "डेटिंग",
		["Cheating/Exploiting"] = "चीटिंग/एक्सप्लॉइट",
		["Personal Question"] = "व्यक्तिगत सवाल",
		["Offsite Links"] = "बाहरी लिंक",
	},
	["fr"] = {
		["Record"] = "Enregistrement",
		["Record Video"] = "Enregistrer une vidéo",
		["Stop Recording"] = "Arrêter l’enregistrement",
		["Screenshot"] = "Capture d’écran",
		["Video"] = "Vidéo",
		["Take Screenshot"] = "Prendre une capture d’écran",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Cliquez sur « Prendre une capture d’écran » pour fermer le menu et enregistrer une capture sur votre ordinateur.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Cliquez sur « Enregistrer une vidéo » pour commencer. Cliquez à nouveau pour arrêter l’enregistrement.",
		["In Experience"] = "Dans l’expérience",
		["In Studio"] = "Dans Roblox Studio",
		["People's Names"] = "Noms des joueurs",
		["My Badges"] = "Mes badges",
		["Reduce Motion"] = "Réduire les animations",
		["Text Size"] = "Taille du texte",
		["Maximum Frame Rate"] = "Fréquence d’images maximale",
		["Chat & Language"] = "Chat et langue",
		["Display & Graphics"] = "Affichage et graphismes",
		["View & Controls"] = "Vue et commandes",
		["Inappropriate Content"] = "Contenu inapproprié",
		["Swearing"] = "Insultes",
		["Inappropriate Username"] = "Nom d’utilisateur inapproprié",
		["Bullying"] = "Harcèlement",
		["Scamming"] = "Escroquerie",
		["Dating"] = "Rencontres",
		["Cheating/Exploiting"] = "Triche/exploits",
		["Personal Question"] = "Question personnelle",
		["Offsite Links"] = "Liens externes",
	},
	["de"] = {
		["Record"] = "Aufnahme",
		["Record Video"] = "Video aufnehmen",
		["Stop Recording"] = "Aufnahme stoppen",
		["Screenshot"] = "Screenshot",
		["Video"] = "Video",
		["Take Screenshot"] = "Screenshot aufnehmen",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Klicke auf „Screenshot aufnehmen“, um das Menü zu schließen und einen Screenshot auf deinem Computer zu speichern.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Klicke auf „Video aufnehmen“, um die Aufnahme zu starten. Klicke erneut, um sie zu stoppen.",
		["In Experience"] = "Im Erlebnis",
		["In Studio"] = "In Roblox Studio",
		["People's Names"] = "Spielernamen",
		["My Badges"] = "Meine Abzeichen",
		["Reduce Motion"] = "Bewegung reduzieren",
		["Text Size"] = "Textgröße",
		["Maximum Frame Rate"] = "Maximale Bildrate",
		["Chat & Language"] = "Chat und Sprache",
		["Display & Graphics"] = "Anzeige und Grafik",
		["View & Controls"] = "Ansicht und Steuerung",
		["Inappropriate Content"] = "Unangemessene Inhalte",
		["Swearing"] = "Beleidigungen",
		["Inappropriate Username"] = "Unangemessener Benutzername",
		["Bullying"] = "Mobbing",
		["Scamming"] = "Betrug",
		["Dating"] = "Dating",
		["Cheating/Exploiting"] = "Cheats/Exploits",
		["Personal Question"] = "Persönliche Frage",
		["Offsite Links"] = "Externe Links",
	},
	["it"] = {
		["Record"] = "Registrazione",
		["Record Video"] = "Registra video",
		["Stop Recording"] = "Interrompi registrazione",
		["Screenshot"] = "Screenshot",
		["Video"] = "Video",
		["Take Screenshot"] = "Fai uno screenshot",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Fai clic su «Fai uno screenshot» per chiudere il menu e salvare uno screenshot sul computer.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Fai clic su «Registra video» per iniziare. Fai di nuovo clic per interrompere la registrazione.",
		["In Experience"] = "Nell’esperienza",
		["In Studio"] = "In Roblox Studio",
		["People's Names"] = "Nomi dei giocatori",
		["My Badges"] = "I miei distintivi",
		["Reduce Motion"] = "Riduci movimento",
		["Text Size"] = "Dimensione testo",
		["Maximum Frame Rate"] = "Frequenza fotogrammi massima",
		["Chat & Language"] = "Chat e lingua",
		["Display & Graphics"] = "Schermo e grafica",
		["View & Controls"] = "Visuale e controlli",
		["Inappropriate Content"] = "Contenuti inappropriati",
		["Swearing"] = "Volgarità",
		["Inappropriate Username"] = "Nome utente inappropriato",
		["Bullying"] = "Bullismo",
		["Scamming"] = "Truffe",
		["Dating"] = "Appuntamenti",
		["Cheating/Exploiting"] = "Barare/exploit",
		["Personal Question"] = "Domanda personale",
		["Offsite Links"] = "Link esterni",
	},
	["ja"] = {
		["Record"] = "録画",
		["Record Video"] = "動画を録画",
		["Stop Recording"] = "録画を停止",
		["Screenshot"] = "スクリーンショット",
		["Video"] = "動画",
		["Take Screenshot"] = "スクリーンショットを撮る",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "「スクリーンショットを撮る」をクリックするとメニューが閉じ、画像がコンピューターに保存されます。",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "「動画を録画」をクリックして録画を開始します。もう一度クリックすると停止します。",
		["In Experience"] = "エクスペリエンス内",
		["In Studio"] = "Roblox Studio 内",
		["People's Names"] = "プレイヤー名",
		["My Badges"] = "マイバッジ",
		["Reduce Motion"] = "動きを減らす",
		["Text Size"] = "文字サイズ",
		["Maximum Frame Rate"] = "最大フレームレート",
		["Chat & Language"] = "チャットと言語",
		["Display & Graphics"] = "表示とグラフィック",
		["View & Controls"] = "視点と操作",
		["Inappropriate Content"] = "不適切なコンテンツ",
		["Swearing"] = "暴言",
		["Inappropriate Username"] = "不適切なユーザー名",
		["Bullying"] = "いじめ",
		["Scamming"] = "詐欺",
		["Dating"] = "出会い目的",
		["Cheating/Exploiting"] = "チート／不正利用",
		["Personal Question"] = "個人的な質問",
		["Offsite Links"] = "外部リンク",
	},
	["ko"] = {
		["Record"] = "녹화",
		["Record Video"] = "비디오 녹화",
		["Stop Recording"] = "녹화 중지",
		["Screenshot"] = "스크린샷",
		["Video"] = "비디오",
		["Take Screenshot"] = "스크린샷 찍기",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "“스크린샷 찍기”를 클릭하면 메뉴가 닫히고 스크린샷이 컴퓨터에 저장됩니다.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "“비디오 녹화”를 클릭해 녹화를 시작하세요. 다시 클릭하면 녹화가 중지됩니다.",
		["In Experience"] = "체험 내",
		["In Studio"] = "Roblox Studio에서",
		["People's Names"] = "플레이어 이름",
		["My Badges"] = "내 배지",
		["Reduce Motion"] = "움직임 줄이기",
		["Text Size"] = "텍스트 크기",
		["Maximum Frame Rate"] = "최대 프레임 속도",
		["Chat & Language"] = "채팅 및 언어",
		["Display & Graphics"] = "디스플레이 및 그래픽",
		["View & Controls"] = "보기 및 조작",
		["Inappropriate Content"] = "부적절한 콘텐츠",
		["Swearing"] = "욕설",
		["Inappropriate Username"] = "부적절한 사용자 이름",
		["Bullying"] = "괴롭힘",
		["Scamming"] = "사기",
		["Dating"] = "데이트",
		["Cheating/Exploiting"] = "치트/익스플로잇",
		["Personal Question"] = "개인적인 질문",
		["Offsite Links"] = "외부 링크",
	},
	["ar"] = {
		["Record"] = "التسجيل",
		["Record Video"] = "تسجيل فيديو",
		["Stop Recording"] = "إيقاف التسجيل",
		["Screenshot"] = "لقطة شاشة",
		["Video"] = "فيديو",
		["Take Screenshot"] = "التقاط لقطة شاشة",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "انقر على «التقاط لقطة شاشة» لإغلاق القائمة وحفظ لقطة الشاشة على جهاز الكمبيوتر.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "انقر على «تسجيل فيديو» لبدء التسجيل. انقر مرة أخرى لإيقافه.",
		["In Experience"] = "داخل التجربة",
		["In Studio"] = "في Roblox Studio",
		["People's Names"] = "أسماء اللاعبين",
		["My Badges"] = "شاراتي",
		["Reduce Motion"] = "تقليل الحركة",
		["Text Size"] = "حجم النص",
		["Maximum Frame Rate"] = "أقصى معدل للإطارات",
		["Chat & Language"] = "الدردشة واللغة",
		["Display & Graphics"] = "العرض والرسومات",
		["View & Controls"] = "الرؤية وعناصر التحكم",
		["Inappropriate Content"] = "محتوى غير ملائم",
		["Swearing"] = "ألفاظ نابية",
		["Inappropriate Username"] = "اسم مستخدم غير ملائم",
		["Bullying"] = "تنمر",
		["Scamming"] = "احتيال",
		["Dating"] = "مواعدة",
		["Cheating/Exploiting"] = "غش/استغلال الثغرات",
		["Personal Question"] = "سؤال شخصي",
		["Offsite Links"] = "روابط خارجية",
	},
	["tr"] = {
		["Record"] = "Kayıt",
		["Record Video"] = "Video kaydet",
		["Stop Recording"] = "Kaydı durdur",
		["Screenshot"] = "Ekran görüntüsü",
		["Video"] = "Video",
		["Take Screenshot"] = "Ekran görüntüsü al",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Ekran görüntüsü almak için düğmeye tıkla; menü kapanır ve görüntü bilgisayarına kaydedilir.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Kaydı başlatmak için “Video kaydet” düğmesine tıkla. Durdurmak için tekrar tıkla.",
		["In Experience"] = "Deneyimde",
		["In Studio"] = "Roblox Studio’da",
		["People's Names"] = "Oyuncu adları",
		["My Badges"] = "Rozetlerim",
		["Reduce Motion"] = "Hareketi azalt",
		["Text Size"] = "Metin boyutu",
		["Maximum Frame Rate"] = "Maksimum kare hızı",
		["Chat & Language"] = "Sohbet ve dil",
		["Display & Graphics"] = "Ekran ve grafikler",
		["View & Controls"] = "Görünüm ve kontroller",
		["Inappropriate Content"] = "Uygunsuz içerik",
		["Swearing"] = "Küfür",
		["Inappropriate Username"] = "Uygunsuz kullanıcı adı",
		["Bullying"] = "Zorbalık",
		["Scamming"] = "Dolandırıcılık",
		["Dating"] = "Flört",
		["Cheating/Exploiting"] = "Hile/istismar",
		["Personal Question"] = "Kişisel soru",
		["Offsite Links"] = "Harici bağlantılar",
	},
	["pl"] = {
		["Record"] = "Nagrywanie",
		["Record Video"] = "Nagraj wideo",
		["Stop Recording"] = "Zatrzymaj nagrywanie",
		["Screenshot"] = "Zrzut ekranu",
		["Video"] = "Wideo",
		["Take Screenshot"] = "Zrób zrzut ekranu",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Kliknij „Zrób zrzut ekranu”, aby zamknąć menu i zapisać zrzut na komputerze.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Kliknij „Nagraj wideo”, aby rozpocząć nagrywanie. Kliknij ponownie, aby je zatrzymać.",
		["In Experience"] = "W grze",
		["In Studio"] = "W Roblox Studio",
		["People's Names"] = "Nazwy graczy",
		["My Badges"] = "Moje odznaki",
		["Reduce Motion"] = "Ogranicz ruch",
		["Text Size"] = "Rozmiar tekstu",
		["Maximum Frame Rate"] = "Maksymalna liczba klatek",
		["Chat & Language"] = "Czat i język",
		["Display & Graphics"] = "Obraz i grafika",
		["View & Controls"] = "Widok i sterowanie",
		["Inappropriate Content"] = "Nieodpowiednie treści",
		["Swearing"] = "Wulgaryzmy",
		["Inappropriate Username"] = "Nieodpowiednia nazwa użytkownika",
		["Bullying"] = "Nękanie",
		["Scamming"] = "Oszustwa",
		["Dating"] = "Randki",
		["Cheating/Exploiting"] = "Oszukiwanie/exploity",
		["Personal Question"] = "Pytanie osobiste",
		["Offsite Links"] = "Linki zewnętrzne",
	},
	["id"] = {
		["Record"] = "Rekaman",
		["Record Video"] = "Rekam video",
		["Stop Recording"] = "Hentikan rekaman",
		["Screenshot"] = "Tangkapan layar",
		["Video"] = "Video",
		["Take Screenshot"] = "Ambil tangkapan layar",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Klik tombol “Ambil tangkapan layar” untuk menutup menu dan menyimpan tangkapan layar ke komputer.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Klik “Rekam video” untuk mulai merekam. Klik sekali lagi untuk menghentikan rekaman.",
		["In Experience"] = "Di pengalaman",
		["In Studio"] = "Di Roblox Studio",
		["People's Names"] = "Nama pemain",
		["My Badges"] = "Lencana saya",
		["Reduce Motion"] = "Kurangi gerakan",
		["Text Size"] = "Ukuran teks",
		["Maximum Frame Rate"] = "Kecepatan bingkai maksimum",
		["Chat & Language"] = "Obrolan dan bahasa",
		["Display & Graphics"] = "Tampilan dan grafis",
		["View & Controls"] = "Tampilan dan kontrol",
		["Inappropriate Content"] = "Konten tidak pantas",
		["Swearing"] = "Kata-kata kasar",
		["Inappropriate Username"] = "Nama pengguna tidak pantas",
		["Bullying"] = "Perundungan",
		["Scamming"] = "Penipuan",
		["Dating"] = "Kencan",
		["Cheating/Exploiting"] = "Kecurangan/eksploitasi",
		["Personal Question"] = "Pertanyaan pribadi",
		["Offsite Links"] = "Tautan eksternal",
	},
	["vi"] = {
		["Record"] = "Ghi hình",
		["Record Video"] = "Quay video",
		["Stop Recording"] = "Dừng ghi hình",
		["Screenshot"] = "Ảnh chụp màn hình",
		["Video"] = "Video",
		["Take Screenshot"] = "Chụp ảnh màn hình",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Nhấp vào “Chụp ảnh màn hình” để đóng menu và lưu ảnh chụp vào máy tính.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Nhấp “Quay video” để bắt đầu ghi. Nhấp lần nữa để dừng ghi hình.",
		["In Experience"] = "Trong trải nghiệm",
		["In Studio"] = "Trong Roblox Studio",
		["People's Names"] = "Tên người chơi",
		["My Badges"] = "Huy hiệu của tôi",
		["Reduce Motion"] = "Giảm chuyển động",
		["Text Size"] = "Cỡ chữ",
		["Maximum Frame Rate"] = "Tốc độ khung hình tối đa",
		["Chat & Language"] = "Chat và ngôn ngữ",
		["Display & Graphics"] = "Hiển thị và đồ họa",
		["View & Controls"] = "Góc nhìn và điều khiển",
		["Inappropriate Content"] = "Nội dung không phù hợp",
		["Swearing"] = "Chửi tục",
		["Inappropriate Username"] = "Tên người dùng không phù hợp",
		["Bullying"] = "Bắt nạt",
		["Scamming"] = "Lừa đảo",
		["Dating"] = "Hẹn hò",
		["Cheating/Exploiting"] = "Gian lận/khai thác lỗi",
		["Personal Question"] = "Câu hỏi cá nhân",
		["Offsite Links"] = "Liên kết bên ngoài",
	},
	["th"] = {
		["Record"] = "การบันทึก",
		["Record Video"] = "บันทึกวิดีโอ",
		["Stop Recording"] = "หยุดบันทึก",
		["Screenshot"] = "ภาพหน้าจอ",
		["Video"] = "วิดีโอ",
		["Take Screenshot"] = "จับภาพหน้าจอ",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "คลิก “จับภาพหน้าจอ” เพื่อปิดเมนูและบันทึกภาพหน้าจอลงในคอมพิวเตอร์",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "คลิก “บันทึกวิดีโอ” เพื่อเริ่มบันทึก คลิกอีกครั้งเพื่อหยุดบันทึก",
		["In Experience"] = "ในประสบการณ์",
		["In Studio"] = "ใน Roblox Studio",
		["People's Names"] = "ชื่อผู้เล่น",
		["My Badges"] = "ตราของฉัน",
		["Reduce Motion"] = "ลดการเคลื่อนไหว",
		["Text Size"] = "ขนาดข้อความ",
		["Maximum Frame Rate"] = "อัตราเฟรมสูงสุด",
		["Chat & Language"] = "แชทและภาษา",
		["Display & Graphics"] = "การแสดงผลและกราฟิก",
		["View & Controls"] = "มุมมองและการควบคุม",
		["Inappropriate Content"] = "เนื้อหาไม่เหมาะสม",
		["Swearing"] = "คำหยาบ",
		["Inappropriate Username"] = "ชื่อผู้ใช้ไม่เหมาะสม",
		["Bullying"] = "การกลั่นแกล้ง",
		["Scamming"] = "การหลอกลวง",
		["Dating"] = "การออกเดต",
		["Cheating/Exploiting"] = "การโกง/ใช้ช่องโหว่",
		["Personal Question"] = "คำถามส่วนตัว",
		["Offsite Links"] = "ลิงก์ภายนอก",
	},
	["nl"] = {
		["Record"] = "Opname",
		["Record Video"] = "Video opnemen",
		["Stop Recording"] = "Opname stoppen",
		["Screenshot"] = "Schermafbeelding",
		["Video"] = "Video",
		["Take Screenshot"] = "Schermafbeelding maken",
		["By clicking the 'Take Screenshot' button, the menu will close and take a screenshot and save it to your computer."] = "Klik op ‘Schermafbeelding maken’ om het menu te sluiten en de schermafbeelding op je computer op te slaan.",
		["Click the 'Record Video' button to start recording. Click it again to stop recording."] = "Klik op ‘Video opnemen’ om de opname te starten. Klik opnieuw om te stoppen.",
		["In Experience"] = "In de experience",
		["In Studio"] = "In Roblox Studio",
		["People's Names"] = "Spelernamen",
		["My Badges"] = "Mijn badges",
		["Reduce Motion"] = "Beweging verminderen",
		["Text Size"] = "Tekstgrootte",
		["Maximum Frame Rate"] = "Maximale framesnelheid",
		["Chat & Language"] = "Chat en taal",
		["Display & Graphics"] = "Weergave en graphics",
		["View & Controls"] = "Beeld en bediening",
		["Inappropriate Content"] = "Ongepaste inhoud",
		["Swearing"] = "Scheldwoorden",
		["Inappropriate Username"] = "Ongepaste gebruikersnaam",
		["Bullying"] = "Pesten",
		["Scamming"] = "Oplichting",
		["Dating"] = "Dating",
		["Cheating/Exploiting"] = "Cheats/exploits",
		["Personal Question"] = "Persoonlijke vraag",
		["Offsite Links"] = "Externe links",
	},
}
for Language, Entries in pairs(MenuAdditionalTranslations) do
	local Target = MenuFallbackTranslations[Language]
	if not Target then Target = {}; MenuFallbackTranslations[Language] = Target end
	for Source, Translation in pairs(Entries) do
		if Target[Source] == nil then Target[Source] = Translation end
	end
end

-- Native toast messages and report prompts use the same locale lookup as menu labels.
MenuNotificationTranslations = {
	["ru"] = {
		["Invite link copied"] = "Ссылка-приглашение скопирована",
		["The experience link was copied to your clipboard."] = "Ссылка на игру скопирована в буфер обмена.",
		["Share invite link"] = "Поделиться ссылкой-приглашением",
		["Roblox opened the link-sharing prompt."] = "Roblox открыл окно отправки ссылки.",
		["Invite link"] = "Ссылка-приглашение",
		["Clipboard access is unavailable on this client."] = "Буфер обмена недоступен в этом клиенте.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Выберите тип жалобы и причину, а при жалобе на игрока также выберите игрока.",
		["Ok"] = "ОК",
	},
	["uk"] = {
		["Invite link copied"] = "Посилання-запрошення скопійовано",
		["The experience link was copied to your clipboard."] = "Посилання на гру скопійовано в буфер обміну.",
		["Share invite link"] = "Поділитися посиланням-запрошенням",
		["Roblox opened the link-sharing prompt."] = "Roblox відкрив вікно надсилання посилання.",
		["Invite link"] = "Посилання-запрошення",
		["Clipboard access is unavailable on this client."] = "Буфер обміну недоступний у цьому клієнті.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Виберіть тип скарги й причину, а якщо скаржитеся на гравця — виберіть гравця.",
		["Ok"] = "Гаразд",
	},
	["es"] = {
		["Invite link copied"] = "Enlace de invitación copiado",
		["The experience link was copied to your clipboard."] = "El enlace de la experiencia se copió al portapapeles.",
		["Share invite link"] = "Compartir enlace de invitación",
		["Roblox opened the link-sharing prompt."] = "Roblox abrió la ventana para compartir el enlace.",
		["Invite link"] = "Enlace de invitación",
		["Clipboard access is unavailable on this client."] = "El portapapeles no está disponible en este cliente.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Elige un tipo de denuncia y un motivo; si denuncias a un jugador, selecciónalo también.",
		["Ok"] = "Aceptar",
	},
	["pt"] = {
		["Invite link copied"] = "Link de convite copiado",
		["The experience link was copied to your clipboard."] = "O link da experiência foi copiado para a área de transferência.",
		["Share invite link"] = "Compartilhar link de convite",
		["Roblox opened the link-sharing prompt."] = "A Roblox abriu a janela de compartilhamento do link.",
		["Invite link"] = "Link de convite",
		["Clipboard access is unavailable on this client."] = "A área de transferência não está disponível neste cliente.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Escolha um tipo e um motivo de denúncia e selecione um jogador ao denunciar alguém.",
		["Ok"] = "OK",
	},
	["zh-cn"] = {
		["Invite link copied"] = "邀请链接已复制",
		["The experience link was copied to your clipboard."] = "体验链接已复制到剪贴板。",
		["Share invite link"] = "分享邀请链接",
		["Roblox opened the link-sharing prompt."] = "Roblox 已打开链接分享窗口。",
		["Invite link"] = "邀请链接",
		["Clipboard access is unavailable on this client."] = "此客户端无法使用剪贴板。",
		["Choose a report type and reason, and select a player when reporting a player."] = "请选择举报类型和原因；举报玩家时还需选择该玩家。",
		["Ok"] = "确定",
	},
	["zh-tw"] = {
		["Invite link copied"] = "已複製邀請連結",
		["The experience link was copied to your clipboard."] = "體驗連結已複製到剪貼簿。",
		["Share invite link"] = "分享邀請連結",
		["Roblox opened the link-sharing prompt."] = "Roblox 已開啟連結分享視窗。",
		["Invite link"] = "邀請連結",
		["Clipboard access is unavailable on this client."] = "此用戶端無法使用剪貼簿。",
		["Choose a report type and reason, and select a player when reporting a player."] = "請選擇檢舉類型和原因；檢舉玩家時也必須選擇該玩家。",
		["Ok"] = "確定",
	},
	["hi"] = {
		["Invite link copied"] = "निमंत्रण लिंक कॉपी हो गया",
		["The experience link was copied to your clipboard."] = "अनुभव का लिंक क्लिपबोर्ड पर कॉपी हो गया।",
		["Share invite link"] = "निमंत्रण लिंक शेयर करें",
		["Roblox opened the link-sharing prompt."] = "Roblox ने लिंक शेयर करने का प्रॉम्प्ट खोला।",
		["Invite link"] = "निमंत्रण लिंक",
		["Clipboard access is unavailable on this client."] = "इस क्लाइंट पर क्लिपबोर्ड उपलब्ध नहीं है।",
		["Choose a report type and reason, and select a player when reporting a player."] = "रिपोर्ट का प्रकार और कारण चुनें। किसी खिलाड़ी की रिपोर्ट करते समय खिलाड़ी भी चुनें।",
		["Ok"] = "ठीक है",
	},
	["fr"] = {
		["Invite link copied"] = "Lien d’invitation copié",
		["The experience link was copied to your clipboard."] = "Le lien de l’expérience a été copié dans le presse-papiers.",
		["Share invite link"] = "Partager le lien d’invitation",
		["Roblox opened the link-sharing prompt."] = "Roblox a ouvert la fenêtre de partage du lien.",
		["Invite link"] = "Lien d’invitation",
		["Clipboard access is unavailable on this client."] = "Le presse-papiers n’est pas disponible sur ce client.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Choisissez un type et un motif de signalement, puis sélectionnez un joueur si vous signalez un joueur.",
		["Ok"] = "OK",
	},
	["de"] = {
		["Invite link copied"] = "Einladungslink kopiert",
		["The experience link was copied to your clipboard."] = "Der Erlebnislink wurde in die Zwischenablage kopiert.",
		["Share invite link"] = "Einladungslink teilen",
		["Roblox opened the link-sharing prompt."] = "Roblox hat den Dialog zum Teilen des Links geöffnet.",
		["Invite link"] = "Einladungslink",
		["Clipboard access is unavailable on this client."] = "Die Zwischenablage ist in diesem Client nicht verfügbar.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Wähle einen Meldungstyp und einen Grund aus. Wenn du einen Spieler meldest, wähle ihn ebenfalls aus.",
		["Ok"] = "OK",
	},
	["it"] = {
		["Invite link copied"] = "Link di invito copiato",
		["The experience link was copied to your clipboard."] = "Il link dell’esperienza è stato copiato negli appunti.",
		["Share invite link"] = "Condividi link di invito",
		["Roblox opened the link-sharing prompt."] = "Roblox ha aperto la finestra per condividere il link.",
		["Invite link"] = "Link di invito",
		["Clipboard access is unavailable on this client."] = "Gli appunti non sono disponibili in questo client.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Scegli un tipo e un motivo di segnalazione; se segnali un giocatore, selezionalo.",
		["Ok"] = "OK",
	},
	["ja"] = {
		["Invite link copied"] = "招待リンクをコピーしました",
		["The experience link was copied to your clipboard."] = "エクスペリエンスのリンクをクリップボードにコピーしました。",
		["Share invite link"] = "招待リンクを共有",
		["Roblox opened the link-sharing prompt."] = "Roblox がリンク共有画面を開きました。",
		["Invite link"] = "招待リンク",
		["Clipboard access is unavailable on this client."] = "このクライアントではクリップボードを利用できません。",
		["Choose a report type and reason, and select a player when reporting a player."] = "報告の種類と理由を選択してください。プレイヤーを報告する場合は、そのプレイヤーも選択してください。",
		["Ok"] = "OK",
	},
	["ko"] = {
		["Invite link copied"] = "초대 링크 복사됨",
		["The experience link was copied to your clipboard."] = "체험 링크가 클립보드에 복사되었습니다.",
		["Share invite link"] = "초대 링크 공유",
		["Roblox opened the link-sharing prompt."] = "Roblox에서 링크 공유 창을 열었습니다.",
		["Invite link"] = "초대 링크",
		["Clipboard access is unavailable on this client."] = "이 클라이언트에서는 클립보드를 사용할 수 없습니다.",
		["Choose a report type and reason, and select a player when reporting a player."] = "신고 유형과 이유를 선택하세요. 플레이어를 신고하는 경우 해당 플레이어도 선택하세요.",
		["Ok"] = "확인",
	},
	["ar"] = {
		["Invite link copied"] = "تم نسخ رابط الدعوة",
		["The experience link was copied to your clipboard."] = "تم نسخ رابط التجربة إلى الحافظة.",
		["Share invite link"] = "مشاركة رابط الدعوة",
		["Roblox opened the link-sharing prompt."] = "فتح Roblox نافذة مشاركة الرابط.",
		["Invite link"] = "رابط الدعوة",
		["Clipboard access is unavailable on this client."] = "الحافظة غير متاحة في هذا العميل.",
		["Choose a report type and reason, and select a player when reporting a player."] = "اختر نوع البلاغ وسببه، وحدد اللاعب أيضًا عند الإبلاغ عن لاعب.",
		["Ok"] = "موافق",
	},
	["tr"] = {
		["Invite link copied"] = "Davet bağlantısı kopyalandı",
		["The experience link was copied to your clipboard."] = "Deneyim bağlantısı panoya kopyalandı.",
		["Share invite link"] = "Davet bağlantısını paylaş",
		["Roblox opened the link-sharing prompt."] = "Roblox bağlantı paylaşma penceresini açtı.",
		["Invite link"] = "Davet bağlantısı",
		["Clipboard access is unavailable on this client."] = "Pano bu istemcide kullanılamıyor.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Bir bildirim türü ve nedeni seç; bir oyuncuyu bildiriyorsan oyuncuyu da seç.",
		["Ok"] = "Tamam",
	},
	["pl"] = {
		["Invite link copied"] = "Skopiowano link zaproszenia",
		["The experience link was copied to your clipboard."] = "Link do gry został skopiowany do schowka.",
		["Share invite link"] = "Udostępnij link zaproszenia",
		["Roblox opened the link-sharing prompt."] = "Roblox otworzył okno udostępniania linku.",
		["Invite link"] = "Link zaproszenia",
		["Clipboard access is unavailable on this client."] = "Schowek jest niedostępny w tym kliencie.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Wybierz typ i powód zgłoszenia, a przy zgłaszaniu gracza wybierz również tego gracza.",
		["Ok"] = "OK",
	},
	["id"] = {
		["Invite link copied"] = "Tautan undangan disalin",
		["The experience link was copied to your clipboard."] = "Tautan pengalaman disalin ke papan klip.",
		["Share invite link"] = "Bagikan tautan undangan",
		["Roblox opened the link-sharing prompt."] = "Roblox membuka dialog berbagi tautan.",
		["Invite link"] = "Tautan undangan",
		["Clipboard access is unavailable on this client."] = "Papan klip tidak tersedia di klien ini.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Pilih jenis dan alasan laporan. Jika melaporkan pemain, pilih juga pemain tersebut.",
		["Ok"] = "Oke",
	},
	["vi"] = {
		["Invite link copied"] = "Đã sao chép liên kết mời",
		["The experience link was copied to your clipboard."] = "Liên kết trải nghiệm đã được sao chép vào khay nhớ tạm.",
		["Share invite link"] = "Chia sẻ liên kết mời",
		["Roblox opened the link-sharing prompt."] = "Roblox đã mở lời nhắc chia sẻ liên kết.",
		["Invite link"] = "Liên kết mời",
		["Clipboard access is unavailable on this client."] = "Khay nhớ tạm không khả dụng trên ứng dụng này.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Hãy chọn loại và lý do báo cáo; nếu báo cáo người chơi, hãy chọn người chơi đó.",
		["Ok"] = "OK",
	},
	["th"] = {
		["Invite link copied"] = "คัดลอกลิงก์คำเชิญแล้ว",
		["The experience link was copied to your clipboard."] = "คัดลอกลิงก์ประสบการณ์ไปยังคลิปบอร์ดแล้ว",
		["Share invite link"] = "แชร์ลิงก์คำเชิญ",
		["Roblox opened the link-sharing prompt."] = "Roblox เปิดหน้าต่างแชร์ลิงก์แล้ว",
		["Invite link"] = "ลิงก์คำเชิญ",
		["Clipboard access is unavailable on this client."] = "คลิปบอร์ดไม่พร้อมใช้งานในไคลเอนต์นี้",
		["Choose a report type and reason, and select a player when reporting a player."] = "เลือกประเภทและเหตุผลในการรายงาน และเลือกผู้เล่นด้วยหากรายงานผู้เล่น",
		["Ok"] = "ตกลง",
	},
	["nl"] = {
		["Invite link copied"] = "Uitnodigingslink gekopieerd",
		["The experience link was copied to your clipboard."] = "De ervaringslink is naar het klembord gekopieerd.",
		["Share invite link"] = "Uitnodigingslink delen",
		["Roblox opened the link-sharing prompt."] = "Roblox heeft het venster voor het delen van de link geopend.",
		["Invite link"] = "Uitnodigingslink",
		["Clipboard access is unavailable on this client."] = "Het klembord is niet beschikbaar in deze client.",
		["Choose a report type and reason, and select a player when reporting a player."] = "Kies een meldtype en reden en selecteer ook een speler als je een speler meldt.",
		["Ok"] = "OK",
	},
}
for Language, Entries in pairs(MenuNotificationTranslations) do
	local Target = MenuFallbackTranslations[Language]
	if not Target then Target = {}; MenuFallbackTranslations[Language] = Target end
	for Source, Translation in pairs(Entries) do
		if Target[Source] == nil then Target[Source] = Translation end
	end
end

-- Extra friend-list and invite-preview strings.
MenuInvitePreviewTranslations = {
	["ru"] = {
		["Join me in this experience"] = "Присоединяйся ко мне в этой игре",
		["Invite Friends"] = "Пригласить друзей",
		["Add Friend"] = "Добавить в друзья",
		["Request Sent"] = "Запрос отправлен",
	},
	["uk"] = {
		["Join me in this experience"] = "Приєднуйся до мене в цій грі",
		["Invite Friends"] = "Запросити друзів",
		["Add Friend"] = "Додати в друзі",
		["Request Sent"] = "Запит надіслано",
	},
	["es"] = {
		["Join me in this experience"] = "Únete a mí en esta experiencia",
		["Invite Friends"] = "Invitar amigos",
		["Add Friend"] = "Agregar amigo",
		["Request Sent"] = "Solicitud enviada",
	},
	["pt"] = {
		["Join me in this experience"] = "Junte-se a mim nesta experiência",
		["Invite Friends"] = "Convidar amigos",
		["Add Friend"] = "Adicionar amigo",
		["Request Sent"] = "Solicitação enviada",
	},
	["zh-cn"] = {
		["Join me in this experience"] = "加入我所在的体验",
		["Invite Friends"] = "邀请好友",
		["Add Friend"] = "添加好友",
		["Request Sent"] = "请求已发送",
	},
	["zh-tw"] = {
		["Join me in this experience"] = "加入我所在的體驗",
		["Invite Friends"] = "邀請好友",
		["Add Friend"] = "新增好友",
		["Request Sent"] = "已送出請求",
	},
	["hi"] = {
		["Join me in this experience"] = "इस अनुभव में मेरे साथ जुड़ें",
		["Invite Friends"] = "दोस्तों को आमंत्रित करें",
		["Add Friend"] = "दोस्त जोड़ें",
		["Request Sent"] = "अनुरोध भेज दिया गया",
	},
	["fr"] = {
		["Join me in this experience"] = "Rejoins-moi dans cette expérience",
		["Invite Friends"] = "Inviter des amis",
		["Add Friend"] = "Ajouter un ami",
		["Request Sent"] = "Demande envoyée",
	},
	["de"] = {
		["Join me in this experience"] = "Tritt mir in diesem Erlebnis bei",
		["Invite Friends"] = "Freunde einladen",
		["Add Friend"] = "Freund hinzufügen",
		["Request Sent"] = "Anfrage gesendet",
	},
	["it"] = {
		["Join me in this experience"] = "Unisciti a me in questa esperienza",
		["Invite Friends"] = "Invita amici",
		["Add Friend"] = "Aggiungi amico",
		["Request Sent"] = "Richiesta inviata",
	},
	["ja"] = {
		["Join me in this experience"] = "このエクスペリエンスに参加する",
		["Invite Friends"] = "友達を招待",
		["Add Friend"] = "フレンドを追加",
		["Request Sent"] = "リクエストを送信しました",
	},
	["ko"] = {
		["Join me in this experience"] = "이 체험에 함께 참여하세요",
		["Invite Friends"] = "친구 초대",
		["Add Friend"] = "친구 추가",
		["Request Sent"] = "요청 전송됨",
	},
	["ar"] = {
		["Join me in this experience"] = "انضم إليّ في هذه التجربة",
		["Invite Friends"] = "دعوة الأصدقاء",
		["Add Friend"] = "إضافة صديق",
		["Request Sent"] = "تم إرسال الطلب",
	},
	["tr"] = {
		["Join me in this experience"] = "Bu deneyimde bana katıl",
		["Invite Friends"] = "Arkadaşları davet et",
		["Add Friend"] = "Arkadaş ekle",
		["Request Sent"] = "İstek gönderildi",
	},
	["pl"] = {
		["Join me in this experience"] = "Dołącz do mnie w tej grze",
		["Invite Friends"] = "Zaproś znajomych",
		["Add Friend"] = "Dodaj znajomego",
		["Request Sent"] = "Wysłano prośbę",
	},
	["id"] = {
		["Join me in this experience"] = "Bergabunglah denganku di pengalaman ini",
		["Invite Friends"] = "Undang Teman",
		["Add Friend"] = "Tambah Teman",
		["Request Sent"] = "Permintaan Terkirim",
	},
	["vi"] = {
		["Join me in this experience"] = "Tham gia trải nghiệm này cùng tôi",
		["Invite Friends"] = "Mời bạn bè",
		["Add Friend"] = "Thêm bạn",
		["Request Sent"] = "Đã gửi yêu cầu",
	},
	["th"] = {
		["Join me in this experience"] = "เข้าร่วมประสบการณ์นี้กับฉัน",
		["Invite Friends"] = "เชิญเพื่อน",
		["Add Friend"] = "เพิ่มเพื่อน",
		["Request Sent"] = "ส่งคำขอแล้ว",
	},
	["nl"] = {
		["Join me in this experience"] = "Doe mee met mij in deze ervaring",
		["Invite Friends"] = "Vrienden uitnodigen",
		["Add Friend"] = "Vriend toevoegen",
		["Request Sent"] = "Verzoek verzonden",
	},
}
for Language, Entries in pairs(MenuInvitePreviewTranslations) do
	local Target = MenuFallbackTranslations[Language]
	if not Target then Target = {}; MenuFallbackTranslations[Language] = Target end
	for Source, Translation in pairs(Entries) do
		if Target[Source] == nil then Target[Source] = Translation end
	end
end

local MenuBetaNoticeEnglish = "You have opted in to one or more of our beta features:\n• Voice chat\n\nPlease report abuse if you encounter people breaking our Community Guidelines. If you have opted-in to voice chat, Roblox records voice audio anywhere on the platform for moderation and safety purposes. By continuing to use the voice chat feature, you consent to Roblox's collection, use, and storage of your voice recording for moderation and safety purposes. You can opt-out of spatial voice at any time."
MenuSpecialTextTranslations = {
	[MenuBetaNoticeEnglish] = {
		ru = "Вы включили одну или несколько бета-функций:\n• Голосовой чат\n\nСообщайте о нарушениях, если заметите пользователей, нарушающих Правила сообщества. При использовании голосового чата Roblox записывает голос на всей платформе в целях модерации и безопасности. Продолжая пользоваться голосовым чатом, вы соглашаетесь на сбор, использование и хранение Roblox ваших голосовых записей для модерации и безопасности. Вы можете в любое время отключить пространственный голосовой чат.",
		uk = "Ви ввімкнули одну або кілька бетафункцій:\n• Голосовий чат\n\nПовідомляйте про порушення, якщо помітите користувачів, які порушують Правила спільноти. Під час використання голосового чату Roblox записує голос на всій платформі для модерації та безпеки. Продовжуючи користуватися голосовим чатом, ви погоджуєтеся на збір, використання та зберігання Roblox ваших голосових записів для модерації й безпеки. Просторовий голосовий чат можна вимкнути будь-коли.",
		es = "Has activado una o varias funciones beta:\n• Chat de voz\n\nDenuncia los abusos si encuentras personas que incumplan las Normas de la comunidad. Al usar el chat de voz, Roblox graba audio de voz en toda la plataforma con fines de moderación y seguridad. Al continuar usando el chat de voz, aceptas que Roblox recopile, use y almacene tus grabaciones de voz con esos fines. Puedes desactivar la voz espacial en cualquier momento.",
		["zh-cn"] = "你已选择加入一项或多项 Beta 功能：\n• 语音聊天\n\n如果发现有人违反社区准则，请举报不当行为。使用语音聊天时，Roblox 会在整个平台注册语音音频，以用于审核和安全保障。继续使用语音聊天即表示你同意 Roblox 为审核和安全目的收集、使用和存储你的语音录音。你可以随时退出空间语音聊天。",
		["zh-tw"] = "你已選擇加入一項或多項 Beta 功能：\n• 語音聊天\n\n如果發現有人違反社群規範，請檢舉不當行為。使用語音聊天時，Roblox 會在整個平台錄製語音音訊，以用於審核和安全保障。繼續使用語音聊天即表示你同意 Roblox 為審核和安全目的收集、使用及儲存你的語音錄音。你可以隨時退出空間語音聊天。",
		hi = "आपने एक या अधिक बीटा सुविधाओं को चुना है:\n• वॉइस चैट\n\nयदि आपको समुदाय दिशानिर्देशों का उल्लंघन करने वाले लोग मिलें, तो कृपया रिपोर्ट करें। वॉइस चैट का उपयोग करने पर Roblox मॉडरेशन और सुरक्षा के लिए पूरे प्लेटफ़ॉर्म पर वॉइस ऑडियो रिकॉर्ड करता है। वॉइस चैट का उपयोग जारी रखकर, आप मॉडरेशन और सुरक्षा के लिए Roblox द्वारा आपकी वॉइस रिकॉर्डिंग एकत्र करने, उपयोग करने और संग्रहीत करने की सहमति देते हैं। आप किसी भी समय स्पेशियल वॉइस बंद कर सकते हैं।",
		fr = "Vous avez activé une ou plusieurs fonctionnalités bêta :\n• Chat vocal\n\nVeuillez signaler les abus si vous voyez des personnes enfreindre les Règles de la communauté. Lorsque vous utilisez le chat vocal, Roblox enregistre l’audio vocal sur la plateforme à des fins de modération et de sécurité. En continuant à utiliser le chat vocal, vous acceptez que Roblox collecte, utilise et conserve vos enregistrements vocaux à ces fins. Vous pouvez désactiver la voix spatiale à tout moment.",
		de = "Du hast mindestens eine unserer Beta-Funktionen aktiviert:\n• Sprachchat\n\nBitte melde Missbrauch, wenn du Personen bemerkst, die gegen unsere Community-Regeln verstoßen. Bei der Nutzung des Sprachchats zeichnet Roblox Sprachaufnahmen auf der gesamten Plattform zu Moderations- und Sicherheitszwecken auf. Wenn du den Sprachchat weiterhin nutzt, stimmst du zu, dass Roblox deine Sprachaufnahmen zu diesen Zwecken sammelt, nutzt und speichert. Du kannst den räumlichen Sprachchat jederzeit deaktivieren.",
		pt = "Você ativou um ou mais recursos beta:\n• Chat de voz\n\nDenuncie abusos se encontrar pessoas que violem as Diretrizes da Comunidade. Ao usar o chat de voz, a Roblox grava áudio de voz em toda a plataforma para fins de moderação e segurança. Ao continuar usando o chat de voz, você concorda que a Roblox colete, use e armazene suas gravações de voz para esses fins. Você pode desativar a voz espacial a qualquer momento.",
		ja = "1 つ以上のベータ機能に参加しています:\n• ボイスチャット\n\nコミュニティ規定に違反するユーザーを見つけた場合は、違反を報告してください。ボイスチャットを使用すると、Roblox はモデレーションと安全対策のためにプラットフォーム全体で音声を録音します。ボイスチャットの使用を続けることで、Roblox がこれらの目的で音声録音を収集、使用、保存することに同意したものとみなされます。空間音声はいつでも無効にできます。",
		ko = "하나 이상의 베타 기능을 사용하도록 설정했습니다:\n• 음성 채팅\n\n커뮤니티 규정을 위반하는 사용자를 발견하면 악용 사례를 신고해 주세요. 음성 채팅을 사용하면 Roblox는 관리 및 안전을 위해 플랫폼 전반에서 음성을 녹음합니다. 음성 채팅을 계속 사용하면 Roblox가 이러한 목적으로 음성 녹음을 수집, 사용 및 저장하는 데 동의하는 것입니다. 공간 음성은 언제든지 끌 수 있습니다.",
	},
}

-- Build an exact English-source -> locale lookup from the locale tables already
-- shipped with Roblox. CoreScript translations are installed locally by Roblox.
CacheMenuCoreScriptTranslations = function()
	local Tables = nil
	pcall(function() Tables = LocalizationService:GetCorescriptLocalizations() end)
	if type(Tables) ~= "table" then return end
	for _, LocalizationTable in pairs(Tables) do
		local Entries = nil
		pcall(function() Entries = LocalizationTable:GetEntries() end)
		if type(Entries) ~= "table" then
			pcall(function() Entries = LocalizationService:GetTableEntries(LocalizationTable) end)
		end
		if type(Entries) == "table" then
			for _, Entry in pairs(Entries) do
				if type(Entry) == "table" then
					local Source = Entry.Source or Entry.source
					local Values = Entry.Values or Entry.values
					if type(Source) == "string" and Source ~= "" and type(Values) == "table" then
						local SourceMap = MenuCoreTranslationsBySource[Source]
						if not SourceMap then SourceMap = {}; MenuCoreTranslationsBySource[Source] = SourceMap end
						for Locale, Translation in pairs(Values) do
							if type(Locale) == "string" and type(Translation) == "string" and Translation ~= "" then
								local Normalized = NormalizeMenuLocale(Locale)
								if not SourceMap[Normalized] then SourceMap[Normalized] = Translation end
							end
						end
					end
				end
			end
		end
	end
end
pcall(CacheMenuCoreScriptTranslations)

GetMenuLocalizedText = function(Source, Locale)
	Source = tostring(Source or "")
	Locale = NormalizeMenuLocale(Locale or MenuLocalizationLocale)
	if Source == "" then return Source end

	local SpecialMap = MenuSpecialTextTranslations and MenuSpecialTextTranslations[Source]
	if SpecialMap then
		local SpecialLocale = NormalizeMenuLocale(Locale)
		local SpecialBase = SpecialLocale:match("^([^-]+)")
		local SpecialTranslation = SpecialMap[SpecialLocale] or SpecialMap[SpecialBase]
		if not SpecialTranslation and SpecialBase == "zh" then
			SpecialTranslation = (SpecialLocale:find("tw", 1, true) or SpecialLocale:find("hk", 1, true)) and SpecialMap["zh-tw"] or SpecialMap["zh-cn"]
		end
		if SpecialTranslation then return SpecialTranslation end
	end

	local VoiceAction = Source:match("^An error occurred while trying to (mute)%. Please try the voice chat bubble to mute%.$")
		or Source:match("^An error occurred while trying to (unmute)%. Please try the voice chat bubble to unmute%.$")
	if VoiceAction then
		local VoiceMessages = {
			ru = {mute="Не удалось отключить звук. Используйте пузырь голосового чата, чтобы отключить звук.", unmute="Не удалось включить звук. Используйте пузырь голосового чата, чтобы включить звук."},
			uk = {mute="Не вдалося вимкнути звук. Скористайтеся бульбашкою голосового чату, щоб вимкнути звук.", unmute="Не вдалося ввімкнути звук. Скористайтеся бульбашкою голосового чату, щоб увімкнути звук."},
			es = {mute="Se produjo un error al silenciar. Usa la burbuja del chat de voz para silenciar.", unmute="Se produjo un error al activar el sonido. Usa la burbuja del chat de voz para activarlo."},
			["zh-cn"] = {mute="静音时发生错误。请使用语音聊天气泡来静音。", unmute="取消静音时发生错误。请使用语音聊天气泡来取消静音。"},
			["zh-tw"] = {mute="靜音時發生錯誤。請使用語音聊天氣泡來靜音。", unmute="取消靜音時發生錯誤。請使用語音聊天氣泡來取消靜音。"},
			hi = {mute="म्यूट करते समय त्रुटि हुई। म्यूट करने के लिए वॉइस चैट बबल का उपयोग करें।", unmute="अनम्यूट करते समय त्रुटि हुई। अनम्यूट करने के लिए वॉइस चैट बबल का उपयोग करें।"},
			fr = {mute="Une erreur est survenue lors de la désactivation du son. Utilisez la bulle du chat vocal pour couper le son.", unmute="Une erreur est survenue lors de la réactivation du son. Utilisez la bulle du chat vocal pour réactiver le son."},
			de = {mute="Beim Stummschalten ist ein Fehler aufgetreten. Verwende dazu die Sprachchat-Blase.", unmute="Beim Aufheben der Stummschaltung ist ein Fehler aufgetreten. Verwende dazu die Sprachchat-Blase."},
			pt = {mute="Ocorreu um erro ao silenciar. Use o balão do chat de voz para silenciar.", unmute="Ocorreu um erro ao ativar o som. Use o balão do chat de voz para ativar o som."},
			ja = {mute="ミュート中にエラーが発生しました。ボイスチャットの吹き出しからミュートしてください。", unmute="ミュート解除中にエラーが発生しました。ボイスチャットの吹き出しから解除してください。"},
			ko = {mute="음소거 중 오류가 발생했습니다. 음성 채팅 말풍선에서 음소거해 주세요.", unmute="음소거 해제 중 오류가 발생했습니다. 음성 채팅 말풍선에서 해제해 주세요."},
			tr = {mute="Sessize alma sırasında hata oluştu. Sessize almak için sesli sohbet balonunu kullanın.", unmute="Sesi açarken hata oluştu. Sesi açmak için sesli sohbet balonunu kullanın."},
			pl = {mute="Wystąpił błąd podczas wyciszania. Użyj dymka czatu głosowego, aby wyciszyć.", unmute="Wystąpił błąd podczas włączania dźwięku. Użyj dymka czatu głosowego, aby go włączyć."},
			id = {mute="Terjadi kesalahan saat membisukan. Gunakan gelembung obrolan suara untuk membisukan.", unmute="Terjadi kesalahan saat mengaktifkan suara. Gunakan gelembung obrolan suara untuk mengaktifkannya."},
			vi = {mute="Đã xảy ra lỗi khi tắt tiếng. Hãy dùng bong bóng trò chuyện thoại để tắt tiếng.", unmute="Đã xảy ra lỗi khi bật tiếng. Hãy dùng bong bóng trò chuyện thoại để bật tiếng."},
			th = {mute="เกิดข้อผิดพลาดขณะปิดเสียง โปรดใช้ฟองแชทเสียงเพื่อปิดเสียง", unmute="เกิดข้อผิดพลาดขณะเปิดเสียง โปรดใช้ฟองแชทเสียงเพื่อเปิดเสียง"},
			nl = {mute="Er is een fout opgetreden bij het dempen. Gebruik de spraakchatballon om te dempen.", unmute="Er is een fout opgetreden bij het opheffen van dempen. Gebruik de spraakchatballon."},
		}
		local VoiceLocale = Locale:match("^([^-]+)") or Locale
		if VoiceLocale == "zh" then VoiceLocale = (Locale:find("tw", 1, true) or Locale:find("hk", 1, true)) and "zh-tw" or "zh-cn" end
		local LocalizedError = VoiceMessages[VoiceLocale]
		if LocalizedError and LocalizedError[VoiceAction] then return LocalizedError[VoiceAction] end
	end

	local PlainSource = Source:gsub("<[^>]+>", "")
	local LookupSource = PlainSource
	local SourceMap = MenuCoreTranslationsBySource[LookupSource]
	if SourceMap then
		local Candidates = {Locale}
		local BaseLanguage = Locale:match("^([^-]+)")
		if BaseLanguage and BaseLanguage ~= Locale then table.insert(Candidates, BaseLanguage) end
		if BaseLanguage == "zh" then
			if Locale:find("tw", 1, true) or Locale:find("hk", 1, true) or Locale:find("mo", 1, true) then
				table.insert(Candidates, "zh-tw")
				table.insert(Candidates, "zh-hant")
			else
				table.insert(Candidates, "zh-cn")
				table.insert(Candidates, "zh-hans")
			end
		elseif BaseLanguage == "pt" then
			table.insert(Candidates, "pt-br")
		elseif BaseLanguage == "fil" then
			table.insert(Candidates, "tl")
		elseif BaseLanguage == "he" then
			table.insert(Candidates, "iw")
		end
		for _, Candidate in ipairs(Candidates) do
			local Translation = SourceMap[Candidate]
			if Translation and Translation ~= "" and Translation ~= LookupSource then
				if PlainSource ~= Source then
					local StartAt, EndAt = string.find(Source, PlainSource, 1, true)
					if StartAt then return string.sub(Source, 1, StartAt - 1) .. Translation .. string.sub(Source, EndAt + 1) end
				end
				return Translation
			end
		end
	end

	local Language = Locale:match("^([^-]+)") or Locale
	if Language == "zh" then
		if Locale:find("tw", 1, true) or Locale:find("hk", 1, true) or Locale:find("mo", 1, true) or Locale:find("hant", 1, true) then
			Language = "zh-tw"
		else
			Language = "zh-cn"
		end
	elseif Language == "pt" then
		Language = "pt"
	elseif Language == "in" then
		Language = "id"
	elseif Language == "iw" then
		Language = "he"
	end
	local Fallback = MenuFallbackTranslations[Language]
	local Translation = Fallback and Fallback[LookupSource]
	if Translation and Translation ~= "" then
		if PlainSource ~= Source then
			local StartAt, EndAt = string.find(Source, PlainSource, 1, true)
			if StartAt then return string.sub(Source, 1, StartAt - 1) .. Translation .. string.sub(Source, EndAt + 1) end
		end
		return Translation
	end
	return Source
end

GetMenuMeasuredTextWidth = function(Object, Text, TextSize)
	Text = tostring(Text or "")
	TextSize = tonumber(TextSize) or 14
	if Text == "" then return 0 end
	local Width = nil
	if TextService then
		pcall(function()
			local Bounds = TextService:GetTextSize(Text, TextSize, Object.Font, Vector2.new(10000, 1000))
			Width = Bounds.X
		end)
	end
	if not Width or Width <= 0 then
		local Count = #Text
		pcall(function() Count = utf8.len(Text) or Count end)
		Width = Count * TextSize * 0.55
	end
	return Width
end

FitMenuButtonText = function(Object, AvailableWidth, BaseSize)
	if not Object or not Object.Parent then return end
	BaseSize = tonumber(BaseSize) or tonumber(Object.TextSize) or 14
	AvailableWidth = tonumber(AvailableWidth) or 0
	if AvailableWidth <= 0 then return end
	local Text = tostring(Object.Text or "")
	local FittedSize = BaseSize
	for Size = math.floor(BaseSize), 14, -1 do
		if GetMenuMeasuredTextWidth(Object, Text, Size) <= AvailableWidth then
			FittedSize = Size
			break
		end
		FittedSize = Size
	end
	Object.TextSize = FittedSize
end

ApplyMenuLocalizedButtonLayout = function(Object)
	if not Object or not Object.Parent then return end
	local Name = tostring(Object.Name or "")

	-- The share action is content-sized, but keep its original width as a minimum
	-- and cap growth so it cannot cover the invite-row heading.
	if Name == "ShareInviteButton" and Object:IsA("TextButton") then
		local Row = Object.Parent
		local BaseSize = 19
		local Desired = math.ceil(GetMenuMeasuredTextWidth(Object, Object.Text, BaseSize) + 24)
		local RowWidth = Row and tonumber(Row.AbsoluteSize.X) or 0
		local MaxWidth = RowWidth > 0 and math.min(168, math.max(86, RowWidth - 150)) or 150
		local Width = math.max(86, math.min(MaxWidth, Desired))
		Object.Size = UDim2.fromOffset(Width, 32)
		Object.Position = UDim2.new(1, -(Width + 8), 0.5, -16)
		if Row then
			local Title = Row:FindFirstChild("ShareInviteLinkLabel")
			if Title then Title.Size = UDim2.new(1, -(Width + 22), 1, 0) end
		end
		FitMenuButtonText(Object, Width - 12, BaseSize)
		return
	end

	-- Player-row buttons may grow a little for long words, staying right-aligned.
	-- Unlike the previous version, no task is queued for every UI label and no
	-- other row/control geometry is touched.
	if Name == "InviteButtonTextLabel" and Object:IsA("TextLabel") then
		local Button = Object.Parent
		if not Button or not Button:IsA("ImageButton") then return end
		local BaseSize = 18
		local Desired = math.ceil(GetMenuMeasuredTextWidth(Object, Object.Text, BaseSize) + 18)
		local Maximum = USE_NEW_INVITE_MENU and 88 or 124
		local Width = math.max(70, math.min(Maximum, Desired))
		local Height = tonumber(Button.Size.Y.Offset) or 0
		if Height < 1 then Height = 46 end
		Button.Size = UDim2.fromOffset(Width, Height)
		Button.Position = UDim2.new(1, -(Width + 12), 0.5, -(Height / 2))
		FitMenuButtonText(Object, Width - 8, BaseSize)
	end
end

ApplyMenuLocalizedText = function(Object, Source)
	if not Object then return end
	Source = Source ~= nil and Source or MenuLocalizationSources[Object] or ""
	local Translation = GetMenuLocalizedText(Source, MenuLocalizationLocale)
	MenuLocalizationRendered[Object] = Translation
	if Object.Text ~= Translation then Object.Text = Translation end
	if Object:IsA("TextLabel") then
		local Parent = Object.Parent
		if Object.Name == "NameLabel" and Parent and Parent.Name == "InviteFriendsToJoin" then
			Object.Font = Enum.Font.SourceSans
			-- Keep localization from restoring the old oversized 24–28px text.
			-- These configurable values apply equally on PC, phones, and tablets.
			Object.TextSize = INVITE_FRIENDS_TEXT_MAX_SIZE
			Object.TextScaled = true
			Object.TextWrapped = true
			local Constraint = Object:FindFirstChildOfClass("UITextSizeConstraint")
			if Constraint then
				Constraint.MinTextSize = INVITE_FRIENDS_TEXT_MIN_SIZE
				Constraint.MaxTextSize = INVITE_FRIENDS_TEXT_MAX_SIZE
			end
		elseif Object.Name == "MuteAllLabel" and Parent and Parent.Name == "MuteAllVoiceRow" then
			Object.Font = Enum.Font.SourceSans
			Object.TextSize = 28
			Object.TextScaled = true
			Object.TextWrapped = true
			local Constraint = Object:FindFirstChildOfClass("UITextSizeConstraint")
			if Constraint then Constraint.MinTextSize = 24; Constraint.MaxTextSize = 28 end
		end
	end
	if ApplyMenuLocalizedButtonLayout then
		pcall(function() ApplyMenuLocalizedButtonLayout(Object) end)
	end
end

RegisterMenuLocalizableText = function(Object)
	if not Object or not (Object:IsA("TextLabel") or Object:IsA("TextButton")) then return end
	if MenuLocalizationSources[Object] ~= nil then
		local Current = tostring(Object.Text or "")
		if MenuLocalizationSources[Object] == "" and Current ~= "" then
			MenuLocalizationSources[Object] = Current
		end
		ApplyMenuLocalizedText(Object, MenuLocalizationSources[Object])
		return
	end
	local Source = tostring(Object.Text or "")
	MenuLocalizationSources[Object] = Source
	ApplyMenuLocalizedText(Object, Source)
	Object:GetPropertyChangedSignal("Text"):Connect(function()
		if not Object then return end
		local Current = tostring(Object.Text or "")
		if MenuLocalizationRendered[Object] == Current then return end
		-- Runtime-updated English labels become the new source, so states such as
		-- Invite/Invited and Mute/Unmute localize without rebuilding the page.
		MenuLocalizationSources[Object] = Current
		ApplyMenuLocalizedText(Object, Current)
	end)
end

RegisterMenuLocalizationTree = function(Root)
	if not Root then return end
	if Root:IsA("TextLabel") or Root:IsA("TextButton") then RegisterMenuLocalizableText(Root) end
	for _, Descendant in ipairs(Root:GetDescendants()) do
		RegisterMenuLocalizableText(Descendant)
	end
end

ApplyMenuLocalizationLocale = function(Locale)
	Locale = NormalizeMenuLocale(Locale)
	if Locale == "" or Locale == MenuLocalizationLocale then return end
	local OldDescriptionPlaceholder = DESCRIPTION_PLACEHOLDER
	MenuLocalizationLocale = Locale
	DESCRIPTION_PLACEHOLDER = GetMenuLocalizedText("In your own words, help us understand what went wrong.", MenuLocalizationLocale)
	if Description and Description.Parent and (Description.Text == OldDescriptionPlaceholder or Description.Text == "In your own words, help us understand what went wrong.") then
		Description.Text = DESCRIPTION_PLACEHOLDER
	end
	for Object, Source in pairs(MenuLocalizationSources) do
		if Object then ApplyMenuLocalizedText(Object, Source) end
	end
	if LayoutTabs then pcall(LayoutTabs) end
	if ResizeHub then pcall(ResizeHub) end
end

RefreshMenuLocalization = function()
	local DetectedLocale = NormalizeMenuLocale(GetMenuExperienceLocale())
	if not MenuLocalizationOverrideLocale then
		MenuLastObservedExperienceLocale = DetectedLocale
		ApplyMenuLocalizationLocale(DetectedLocale)
	else
		-- Generic locale-property notifications can fire for account/CoreGui
		-- settings too. They must not cancel the user's menu-language choice;
		-- only the bound experience Translator monitor may clear this override.
		ApplyMenuLocalizationLocale(MenuLocalizationOverrideLocale)
	end
end

MenuLocalizationLocale = GetMenuExperienceLocale()
DESCRIPTION_PLACEHOLDER = GetMenuLocalizedText("In your own words, help us understand what went wrong.", MenuLocalizationLocale)
-- Prefer locale-change notifications from the player; keep CoreGui/system
-- notifications as fallback triggers for clients that hide Player.LocaleId.
pcall(function()
	if LocalPlayer then
		LocalPlayer:GetPropertyChangedSignal("LocaleId"):Connect(RefreshMenuLocalization)
	end
end)
pcall(function()
	LocalizationService:GetPropertyChangedSignal("RobloxLocaleId"):Connect(RefreshMenuLocalization)
end)
pcall(function()
	LocalizationService:GetPropertyChangedSignal("SystemLocaleId"):Connect(RefreshMenuLocalization)
end)

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

	RegisterMenuLocalizableText(Object)
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

-- Input/output device helpers. The SoundService device methods return tuples on
-- some clients and nested device tables/maps on others, so normalize both forms.
GetAudioDeviceInfo = function(Direction)
	local MethodName = Direction == "Input" and "GetInputDevice" or "GetOutputDevice"
	local Values = {n = 0}
	local Ok = pcall(function()
		local Method = SoundService[MethodName]
		if type(Method) ~= "function" then error("Audio device query unavailable") end
		Values = table.pack(Method(SoundService))
	end)
	if not Ok then return nil, nil end

	local Name, Guid = nil, nil
	local StringValues = {}
	local function LooksLikeDeviceGuid(Value)
		Value = tostring(Value or "")
		return Value:find("%x%x%x%x%x%x%x%x%-", 1) ~= nil
			or (Value:sub(1, 1) == "{" and Value:sub(-1) == "}")
			or (#Value >= 24 and not Value:find("%s"))
	end
	local function ReadDevice(Device, Depth)
		if type(Device) ~= "table" or (Depth or 0) > 5 then return end
		Name = Name or Device.Name or Device.name or Device.DisplayName or Device.displayName
			or Device.DeviceName or Device.deviceName or Device.Label or Device.label
		Guid = Guid or Device.Guid or Device.guid or Device.Id or Device.id
			or Device.DeviceGuid or Device.deviceGuid or Device.DeviceID or Device.deviceID
			or Device.DeviceId or Device.deviceId or Device.Pin or Device.pin
		for _, Child in pairs(Device) do
			if type(Child) == "table" then ReadDevice(Child, (Depth or 0) + 1) end
		end
	end

	for Index = 1, Values.n or #Values do
		local Value = Values[Index]
		if type(Value) == "table" then
			ReadDevice(Value, 0)
		elseif type(Value) == "string" then
			table.insert(StringValues, Value)
		end
	end
	-- Tuple order differs between client branches. Prefer recognizable GUIDs for
	-- the ID field instead of accidentally displaying a GUID as the microphone name.
	for _, Value in ipairs(StringValues) do
		if LooksLikeDeviceGuid(Value) then
			Guid = Guid or Value
		elseif not Name then
			Name = Value
		elseif not Guid then
			Guid = Value
		end
	end
	return Name and tostring(Name) or nil, Guid and tostring(Guid) or nil
end

GetOutputDeviceInfo = function()
	return GetAudioDeviceInfo("Output")
end

GetInputDeviceInfo = function()
	return GetAudioDeviceInfo("Input")
end

GetAudioDeviceOptions = function(Direction)
	local Names = {"System Default"}
	local DeviceMap = { ["System Default"] = {Name = "", Guid = ""} }
	local Seen = {}
	local UsedLabels = { ["System Default"] = true }

	local function AddDevice(Name, Guid)
		if Name == nil then return end
		Name = tostring(Name)
		Guid = tostring(Guid or "")
		if Name == "" then return end
		local DedupKey = Guid ~= "" and ("guid:" .. Guid) or ("name:" .. Name)
		if Seen[DedupKey] then return end
		Seen[DedupKey] = true

		local Label = Name
		if UsedLabels[Label] then
			local Suffix = Guid ~= "" and Guid:sub(math.max(1, #Guid - 5)) or tostring(#Names + 1)
			Label = Name .. " (" .. Suffix .. ")"
			local N = 2
			while UsedLabels[Label] do
				Label = Name .. " (" .. Suffix .. "-" .. tostring(N) .. ")"
				N += 1
			end
		end
		UsedLabels[Label] = true
		table.insert(Names, Label)
		DeviceMap[Label] = {Name = Name, Guid = Guid}
	end

	local function IsGuidLike(Value)
		Value = tostring(Value or "")
		return Value:find("%x%x%x%x%x%x%x%x%-", 1) ~= nil
			or (Value:sub(1, 1) == "{" and Value:sub(-1) == "}")
			or (#Value >= 24 and not Value:find("%s"))
	end

	local function ParseValue(Value, Depth, KeyHint)
		Depth = Depth or 0
		if Depth > 6 then return end
		if type(Value) == "table" then
			local Name = Value.Name or Value.name or Value.DisplayName or Value.displayName
				or Value.DeviceName or Value.deviceName or Value.Label or Value.label
			local Guid = Value.Guid or Value.guid or Value.DeviceGuid or Value.deviceGuid
				or Value.DeviceID or Value.deviceID or Value.DeviceId or Value.deviceId
				or Value.Id or Value.id or Value.Pin or Value.pin
			if type(Name) == "string" and Name ~= "" then
				AddDevice(Name, Guid)
				return
			end

			-- Accept only recognizable arrays or GUID<->name maps. The previous
			-- parser treated metadata such as CurrentDeviceName/Status as devices.
			for Key, Child in pairs(Value) do
				if type(Child) == "table" then
					ParseValue(Child, Depth + 1, Key)
				elseif type(Child) == "string" then
					if type(Key) == "number" then
						AddDevice(Child, "")
					elseif type(Key) == "string" and IsGuidLike(Key) and not IsGuidLike(Child) then
						AddDevice(Child, Key)
					elseif type(Key) == "string" and IsGuidLike(Child) and not IsGuidLike(Key) then
						AddDevice(Key, Child)
					end
				end
			end
		elseif type(Value) == "string" then
			if KeyHint and type(KeyHint) == "string" and IsGuidLike(KeyHint) and not IsGuidLike(Value) then
				AddDevice(Value, KeyHint)
			else
				AddDevice(Value, "")
			end
		end
	end

	local function IsPlainStringArray(Value)
		if type(Value) ~= "table" then return false end
		local Count = 0
		for Key, Child in pairs(Value) do
			if type(Key) ~= "number" or type(Child) ~= "string" then return false end
			Count += 1
		end
		return Count > 0
	end

	local function ParseReturnValues(Values)
		-- Some builds return parallel arrays: {names...}, {GUIDs...}.
		-- Pair these arrays by index instead of mistakenly listing GUIDs as devices.
		if IsPlainStringArray(Values[1]) and IsPlainStringArray(Values[2]) then
			local First, Second = Values[1], Values[2]
			local FirstLooksLikeIds, SecondLooksLikeIds = 0, 0
			for _, Value in ipairs(First) do if IsGuidLike(Value) then FirstLooksLikeIds += 1 end end
			for _, Value in ipairs(Second) do if IsGuidLike(Value) then SecondLooksLikeIds += 1 end end
			if FirstLooksLikeIds > SecondLooksLikeIds then First, Second = Second, First end
			for Index, DeviceName in ipairs(First) do
				AddDevice(DeviceName, type(Second[Index]) == "string" and Second[Index] or "")
			end
			for Index = #First + 1, #Second do
				if not IsGuidLike(Second[Index]) then AddDevice(Second[Index], "") end
			end
			for Index = 3, Values.n or #Values do ParseValue(Values[Index], 0) end
			return
		end

		-- Other builds return records/maps, or a flat (name, GUID, name, GUID...) tuple.
		local PendingName = nil
		for Index = 1, Values.n or #Values do
			local Value = Values[Index]
			if type(Value) == "table" then
				ParseValue(Value, 0)
			elseif type(Value) == "string" then
				if IsGuidLike(Value) then
					if PendingName then AddDevice(PendingName, Value); PendingName = nil end
				elseif PendingName then
					-- Consecutive plain strings are more likely separate device labels than
					-- a name plus an ID. Preserve each label and don't pair them incorrectly.
					AddDevice(PendingName, "")
					PendingName = Value
				else
					PendingName = Value
				end
			end
		end
		if PendingName and not IsGuidLike(PendingName) then AddDevice(PendingName, "") end
	end

	local AudioApiEnabled = type(GetVoiceAudioApiEnabled) == "function" and GetVoiceAudioApiEnabled() == true
	local function EnumerateSoundServiceDevices()
		local MethodName = Direction == "Input" and "GetInputDevices" or "GetOutputDevices"
		pcall(function()
			local Method = SoundService[MethodName]
			if type(Method) ~= "function" then error("Audio device enumeration unavailable") end
			ParseReturnValues(table.pack(Method(SoundService)))
		end)
	end
	local function EnumerateLegacyVoiceMics()
		if Direction ~= "Input" or not VoiceChatInternal then return end
		pcall(function()
			local Method = VoiceChatInternal.GetMicDevices
			if type(Method) ~= "function" then return end
			ParseReturnValues(table.pack(Method(VoiceChatInternal)))
		end)
	end

	-- In legacy/Automatic mode, VoiceChatInternal owns the actual voice publisher
	-- device list. Querying SoundService first can show an unrelated system audio
	-- input and make the settings page claim the wrong microphone is selected.
	if Direction == "Input" and not AudioApiEnabled then
		EnumerateLegacyVoiceMics()
		if #Names == 1 then EnumerateSoundServiceDevices() end
	else
		EnumerateSoundServiceDevices()
		if Direction == "Input" and #Names == 1 then EnumerateLegacyVoiceMics() end
	end

	local CurrentName, CurrentGuid = GetAudioDeviceInfo(Direction)
	if CurrentName and CurrentName ~= "" then
		local CurrentMatchesVoiceList = false
		for _, Label in ipairs(Names) do
			local Info = DeviceMap[Label]
			if Info and Info.Name == CurrentName then CurrentMatchesVoiceList = true; break end
		end
		-- Do not append an unrelated SoundService device as the current voice mic
		-- when legacy voice provided a different authoritative list.
		if Direction ~= "Input" or AudioApiEnabled or #Names == 1 or CurrentMatchesVoiceList then
			AddDevice(CurrentName, CurrentGuid)
		else
			CurrentName, CurrentGuid = nil, nil
		end
	end
	return Names, DeviceMap, CurrentName, CurrentGuid
end
GetOutputDeviceOptions = function()
	return GetAudioDeviceOptions("Output")
end

GetInputDeviceOptions = function()
	return GetAudioDeviceOptions("Input")
end

SetRealOutputDevice = function(Name, Guid)
	Name, Guid = tostring(Name or ""), tostring(Guid or "")
	local Ok = pcall(function()
		SoundService:SetOutputDevice(Name, Guid)
	end)
	if not Ok then return false end
	if Name == "" and Guid == "" then return true end
	local ActualName, ActualGuid = GetOutputDeviceInfo()
	if ActualName == Name and (Guid == "" or ActualGuid == Guid) then return true end
	return false
end

SetRealInputDevice = function(Name, Guid)
	Name, Guid = tostring(Name or ""), tostring(Guid or "")
	local ApiEnabled = type(GetVoiceAudioApiEnabled) == "function" and GetVoiceAudioApiEnabled() == true

	local function SetModernInput()
		local Setter = nil
		pcall(function() Setter = SoundService.SetInputDevice end)
		if type(Setter) ~= "function" then return false end
		local Ok = pcall(function() Setter(SoundService, Name, Guid) end)
		if not Ok then return false end
		if Name == "" and Guid == "" then return true end
		local ActualName, ActualGuid = GetInputDeviceInfo()
		if ActualName == Name and (Guid == "" or ActualGuid == Guid) then return true end
		-- Some clients accept the write but do not expose a public readback. In
		-- that case, don't accidentally redirect a modern selection to the legacy mic.
		return ActualName == nil or ActualName == ""
	end

	local function SetLegacyInput()
		if not VoiceChatInternal then return false end
		local Setter = nil
		pcall(function() Setter = VoiceChatInternal.SetMicDevice end)
		if type(Setter) ~= "function" then return false end
		-- SetMicDevice is the legacy voice publisher's actual microphone selector;
		-- comparing its selection with SoundService's unrelated output can mis-detect it.
		return pcall(function() Setter(VoiceChatInternal, Name, Guid) end)
	end

	if ApiEnabled then
		return SetModernInput()
	end
	if SetLegacyInput() then return true end
	if ApiEnabled == nil then return SetModernInput() end
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

			-- Use consistent physical-screen coordinates on every platform so the
			-- centered desktop menu is not shifted down by the Roblox top-bar inset.
			-- Fullscreen dimensions are still applied to MenuContainer only on phones.
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.None,
			SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,

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

Connect(ScreenGui.DescendantAdded, function(Descendant)
	-- Defer until Create has finished assigning properties, avoiding capturing a
	-- temporarily empty Text before its intended English source string is set.
	task.defer(function()
		if Descendant and Descendant.Parent then RegisterMenuLocalizableText(Descendant) end
	end)
end)

-- ============================================================
-- VOICE CHAT BETA BADGE / NOTICE POPUP
-- Uses the live TopBarApp LeftFrame when available, rather than an
-- invisible full-screen overlay that can intercept/block top-bar clicks.
-- ============================================================
local function FindVoiceBetaTopBarLeftFrame()
	local TopBarRoot = CoreGui:FindFirstChild("TopBarApp")
	if not TopBarRoot then return nil end
	local App = TopBarRoot:FindFirstChild("TopBarApp") or TopBarRoot
	local TopBarFrame = App:FindFirstChild("TopBarFrame", true)
	local LeftFrame = TopBarFrame and TopBarFrame:FindFirstChild("LeftFrame")
	if LeftFrame and LeftFrame:IsA("GuiObject") then return LeftFrame end
	return nil
end

VoiceBetaTopBarLeftFrame = FindVoiceBetaTopBarLeftFrame()
VoiceBetaNativeOriginalRoot = nil
if VoiceBetaTopBarLeftFrame then
	local OldCustomBadge = VoiceBetaTopBarLeftFrame:FindFirstChild("Settings2016VoiceBetaBadgeRoot")
	if OldCustomBadge then pcall(function() OldCustomBadge:Destroy() end) end
end

-- Clean up the previous overlay-based popup. The reference popup belongs under the
-- badge root itself; keeping it there preserves the original TopBar vertical position.
VoiceBetaPopupOverlayGui = nil
pcall(function()
	local OldOverlay = CoreGui:FindFirstChild("Settings2016VoiceBetaPopupOverlay")
	if OldOverlay then OldOverlay:Destroy() end
end)

if VoiceBetaTopBarLeftFrame then
	-- Restore the native popup to its expected location before detecting it.
	-- The previous run may have moved it into a positioning anchor to escape
	-- the TopBar UIListLayout's vertical centering.
	local ExistingNativeRoot = VoiceBetaTopBarLeftFrame:FindFirstChild("badge")
	local PreviousPopupAnchor = ExistingNativeRoot
		and ExistingNativeRoot:FindFirstChild("Settings2016VoiceBetaPopupAnchor")
	if PreviousPopupAnchor then
		local PreviousPopup = PreviousPopupAnchor:FindFirstChild("popup")
		if PreviousPopup then
			local OldLayoutOrder = PreviousPopup.LayoutOrder
			PreviousPopup.Parent = ExistingNativeRoot
			PreviousPopup.LayoutOrder = OldLayoutOrder
		end
		PreviousPopupAnchor:Destroy()
	end

	local Existing = VoiceBetaTopBarLeftFrame:FindFirstChild("badge")
	if Existing and Existing:IsA("Frame")
		and Existing:FindFirstChild("popup")
		and Existing:FindFirstChild("badge") then
		VoiceBetaNativeOriginalRoot = Existing
		pcall(function() VoiceBetaNativeOriginalRoot.Visible = false end)
	end
end

VoiceBetaBadgeRoot = Create("Frame", {
	Name = "Settings2016VoiceBetaBadgeRoot",
	Parent = VoiceBetaTopBarLeftFrame or ScreenGui,
	Position = VoiceBetaTopBarLeftFrame and UDim2.new(0, 0, 0, 0) or UDim2.fromOffset(116, 0),
	Size = UDim2.new(0, 0, 0, 32),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = false,
	Active = true,
	Interactable = true,
	LayoutOrder = 4,
	Visible = false,
	ZIndex = SETTINGS_BASE_ZINDEX + 150,
})

Create("UIListLayout", {
	Name = "Settings2016VoiceBetaBadgeLayout",
	Parent = VoiceBetaBadgeRoot,
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
	Wraps = false,
})

-- A zero-width layout anchor holds the popup without letting its tall frame
-- participate in the badge's horizontal UIListLayout. The popup is positioned
-- below this anchor, so the layout cannot center it above the topbar and clip it.
VoiceBetaPopupAnchor = Create("Frame", {
	Name = "Settings2016VoiceBetaPopupAnchor",
	Parent = VoiceBetaBadgeRoot,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 0, 0, 32),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = false,
	Active = false,
	Interactable = false,
	LayoutOrder = 2,
	ZIndex = SETTINGS_BASE_ZINDEX + 153,
})

VoiceBetaBadgeButton = Create("ImageButton", {
	Name = "Settings2016VoiceBetaBadgeButton",
	Parent = VoiceBetaBadgeRoot,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Image = "",
	AutoButtonColor = true,
	Active = true,
	Interactable = true,
	Selectable = true,
	LayoutOrder = 1,
	Modal = false,
	ZIndex = SETTINGS_BASE_ZINDEX + 151,
})
Create("UISizeConstraint", {
	Name = "Settings2016VoiceBetaBadgeConstraint",
	Parent = VoiceBetaBadgeButton,
	MinSize = Vector2.new(38, 29),
})

VoiceBetaBadgeText = Create("TextLabel", {
	Name = "Settings2016VoiceBetaBadgeLabel",
	Parent = VoiceBetaBadgeButton,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 3),
	Size = UDim2.new(0, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundColor3 = Color3.fromRGB(233, 207, 104),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Text = "BETA",
	TextColor3 = Color3.fromRGB(0, 0, 0),
	TextSize = 12,
	TextWrapped = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Active = false,
	Interactable = false,
	Selectable = false,
	ZIndex = SETTINGS_BASE_ZINDEX + 152,
})
Create("UIPadding", {
	Name = "Settings2016VoiceBetaBadgePadding",
	Parent = VoiceBetaBadgeText,
	PaddingBottom = UDim.new(0, 1),
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
	PaddingTop = UDim.new(0, 1),
})
Create("UICorner", {
	Name = "Settings2016VoiceBetaBadgeCorner",
	Parent = VoiceBetaBadgeText,
	CornerRadius = UDim.new(0, 3),
})
Create("UIStroke", {
	Name = "Settings2016VoiceBetaBadgeStroke",
	Parent = VoiceBetaBadgeText,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Color = Color3.fromRGB(255, 255, 255),
	Enabled = true,
	LineJoinMode = Enum.LineJoinMode.Round,
	Thickness = 2,
	Transparency = 0,
})

-- Parent the popup to the zero-width anchor, not directly to the horizontal
-- layout. Its top edge sits below the badge instead of being vertically centered
-- inside the 32px badge root (which made the tall popup start off-screen).
VoiceBetaPopup = Create("Frame", {
	Name = "Settings2016VoiceBetaPopup",
	Parent = VoiceBetaPopupAnchor,
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 0, 1, 6),
	Size = UDim2.new(0, 300, 0, 2),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 1,
	ClipsDescendants = false,
	Active = true,
	Interactable = true,
	Visible = false,
	LayoutOrder = 2,
	ZIndex = SETTINGS_BASE_ZINDEX + 153,
})
Create("UIPadding", {
	Name = "Settings2016VoiceBetaPopupPadding",
	Parent = VoiceBetaPopup,
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 8),
})
Create("UIListLayout", {
	Name = "Settings2016VoiceBetaPopupLayout",
	Parent = VoiceBetaPopup,
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 12),
	Wraps = false,
})
Create("UICorner", {
	Name = "Settings2016VoiceBetaPopupCorner",
	Parent = VoiceBetaPopup,
	CornerRadius = UDim.new(0, 8),
})

VoiceBetaPopupText = Create("TextLabel", {
	Name = "Settings2016VoiceBetaPopupText",
	Parent = VoiceBetaPopup,
	Size = UDim2.new(0, 283, 0, 139),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	Text = "You have opted in to one or more of our beta features:\n• Voice chat\n\nPlease report abuse if you encounter people breaking our Community Guidelines. If you have opted-in to voice chat, Roblox records voice audio anywhere on the platform for moderation and safety purposes. By continuing to use the voice chat feature, you consent to Roblox's collection, use, and storage of your voice recording for moderation and safety purposes. You can opt-out of spatial voice at any time.",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 12,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Active = false,
	Interactable = false,
	Selectable = false,
	LayoutOrder = 1,
	ZIndex = SETTINGS_BASE_ZINDEX + 154,
})

VoiceBetaLearnMoreButton = Create("ImageButton", {
	Name = "Settings2016VoiceBetaLearnMoreButton",
	Parent = VoiceBetaPopup,
	Size = UDim2.fromOffset(64, 28),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Image = "",
	AutoButtonColor = false,
	Active = true,
	Interactable = true,
	Selectable = false,
	LayoutOrder = 100,
	ZIndex = SETTINGS_BASE_ZINDEX + 154,
})
Create("UISizeConstraint", {
	Name = "Settings2016VoiceBetaLearnMoreConstraint",
	Parent = VoiceBetaLearnMoreButton,
	MinSize = Vector2.new(64, 28),
})
Create("TextLabel", {
	Name = "Settings2016VoiceBetaLearnMoreText",
	Parent = VoiceBetaLearnMoreButton,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.515625, 0, 0.5, 0),
	Size = UDim2.fromOffset(111, 14),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	RichText = true,
	Text = "<u>Learn More</u>",
	TextColor3 = Color3.fromRGB(82, 173, 244),
	TextSize = 12,
	TextWrapped = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Active = false,
	Interactable = false,
	Selectable = false,
	ZIndex = SETTINGS_BASE_ZINDEX + 155,
})

-- Prefer Roblox's actual beta badge/button/popup if the live TopBarApp exposes it.
-- The native ImageButton is the reliable click target; the popup was designed as its
-- sibling under the existing horizontal UIListLayout. Keep a custom fallback only
-- for clients where this native hierarchy is absent.
VoiceBetaUsingNativeHierarchy = false
if VoiceBetaNativeOriginalRoot and VoiceBetaNativeOriginalRoot.Parent then
    local NativeRoot = VoiceBetaNativeOriginalRoot
    local NativeButton = NativeRoot:FindFirstChild("badge")
    local NativePopup = NativeRoot:FindFirstChild("popup")
    local NativeText = NativeButton and NativeButton:FindFirstChild("text")
    local NativePopupText = NativePopup and NativePopup:FindFirstChild("1")
    local NativeLearnMore = NativePopup and NativePopup:FindFirstChild("link")
    if NativeButton and NativeButton:IsA("ImageButton")
        and NativePopup and NativePopup:IsA("Frame")
        and NativeText and NativeText:IsA("TextLabel") then
        pcall(function() VoiceBetaBadgeRoot:Destroy() end)
        pcall(function() VoiceBetaPopupOverlayGui:Destroy() end)
        VoiceBetaPopupOverlayGui = nil
        VoiceBetaBadgeRoot = NativeRoot
        VoiceBetaBadgeButton = NativeButton
        VoiceBetaBadgeText = NativeText
        VoiceBetaPopup = NativePopup
        VoiceBetaPopupText = NativePopupText
        VoiceBetaLearnMoreButton = NativeLearnMore
        VoiceBetaUsingNativeHierarchy = true
        pcall(function()
            NativeText.Font = Enum.Font.GothamBlack
            local NativeStroke = NativeText:FindFirstChildWhichIsA("UIStroke")
            if not NativeStroke then
                NativeStroke = Instance.new("UIStroke")
                NativeStroke.Name = "Settings2016VoiceBetaBadgeStroke"
                NativeStroke.Parent = NativeText
            end
            NativeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            NativeStroke.Color = Color3.fromRGB(255, 255, 255)
            NativeStroke.Enabled = true
            NativeStroke.LineJoinMode = Enum.LineJoinMode.Round
            NativeStroke.Thickness = 2
            NativeStroke.Transparency = 0
        end)
        pcall(function()
            -- Use an untracked positioning anchor under the native root. Keeping
            -- the native popup instance preserves its click handlers, but removing
            -- it from the horizontal UIListLayout prevents negative Y placement.
            local NativePopupAnchor = NativeRoot:FindFirstChild("Settings2016VoiceBetaPopupAnchor")
            if not NativePopupAnchor then
                NativePopupAnchor = Instance.new("Frame")
                NativePopupAnchor.Name = "Settings2016VoiceBetaPopupAnchor"
                NativePopupAnchor.Parent = NativeRoot
                NativePopupAnchor.Size = UDim2.new(0, 0, 0, 32)
                NativePopupAnchor.Position = UDim2.new(0, 0, 0, 0)
                NativePopupAnchor.BackgroundTransparency = 1
                NativePopupAnchor.BorderSizePixel = 0
                NativePopupAnchor.ClipsDescendants = false
                NativePopupAnchor.Active = false
                NativePopupAnchor.Interactable = false
                NativePopupAnchor.LayoutOrder = NativePopup.LayoutOrder
                NativePopupAnchor.ZIndex = SETTINGS_BASE_ZINDEX + 153
            end
            NativePopup.Parent = NativePopupAnchor
            NativePopup.AnchorPoint = Vector2.new(0, 0)
            NativePopup.Position = UDim2.new(0, 0, 1, 6)
            NativePopup.ClipsDescendants = false
            VoiceBetaPopupAnchor = NativePopupAnchor
        end)
        pcall(function()
            NativeRoot.Size = UDim2.new(NativeRoot.Size.X.Scale, NativeRoot.Size.X.Offset, 0, 32)
            NativeRoot.ClipsDescendants = false
            NativeRoot.AnchorPoint = Vector2.new(NativeRoot.AnchorPoint.X, 0)
            NativeButton.AnchorPoint = Vector2.new(0, 0.5)
            NativeButton.Position = UDim2.new(NativeButton.Position.X.Scale, NativeButton.Position.X.Offset, 0.5, 0)
            NativeButton.Size = UDim2.fromOffset(40, 30)
            local NativeButtonConstraint = NativeButton:FindFirstChildOfClass("UISizeConstraint")
            if NativeButtonConstraint then
                NativeButtonConstraint.MinSize = Vector2.new(38, 29)
                NativeButtonConstraint.MaxSize = Vector2.new(40, 30)
            end
            NativeRoot.Visible = false
            NativePopup.Visible = false
            NativeButton.Active = true
            NativeButton.Interactable = true
            NativeButton.Selectable = true
            NativeText.Active = false
            NativeText.Interactable = false
            NativeText.Selectable = false
            pcall(function()
                NativeText.TextSize = 12
                NativeText.AnchorPoint = Vector2.new(0.5, 0.5)
                NativeText.Position = UDim2.new(0.5, 0, 0.5, 2)
                NativeText.Size = UDim2.new(1, -2, 1, -4)
                NativeText.AutomaticSize = Enum.AutomaticSize.None
                NativeText.TextXAlignment = Enum.TextXAlignment.Center
                NativeText.TextYAlignment = Enum.TextYAlignment.Center
                local NativeTextPadding = NativeText:FindFirstChildOfClass("UIPadding")
                if NativeTextPadding then
                    NativeTextPadding.PaddingTop = UDim.new(0, 0)
                    NativeTextPadding.PaddingBottom = UDim.new(0, 0)
                    NativeTextPadding.PaddingLeft = UDim.new(0, 4)
                    NativeTextPadding.PaddingRight = UDim.new(0, 4)
                end
                local NativeTextCorner = NativeText:FindFirstChildOfClass("UICorner")
                if NativeTextCorner then NativeTextCorner.CornerRadius = UDim.new(0, 3) end
            end)
            if NativeLearnMore then
                NativeLearnMore.Active = true
                NativeLearnMore.Interactable = true
            end
            local LinkText = NativeLearnMore and NativeLearnMore:FindFirstChild("textLabel")
            if LinkText and LinkText:IsA("TextLabel") then
                LinkText.Active = false
                LinkText.Interactable = false
                LinkText.Selectable = false
            end
        end)
    end
end

VoiceBetaPopupOpen = false
local PositionVoiceBetaPopup
local function CenterVoiceBetaBadge()
    local Root = VoiceBetaBadgeRoot
    local Parent = Root and Root.Parent
    if not Root or not Parent then return end

    local TopBarRoot = CoreGui:FindFirstChild("TopBarApp")
    local App = TopBarRoot and (TopBarRoot:FindFirstChild("TopBarApp") or TopBarRoot)
    local TopBarFrame = App and App:FindFirstChild("TopBarFrame", true)
    local ParentY, ParentHeight, RootHeight = 0, 0, 26
    pcall(function() ParentY = Parent.AbsolutePosition.Y end)
    pcall(function() ParentHeight = Parent.AbsoluteSize.Y end)
    pcall(function()
        if Root.AbsoluteSize.Y > 0 then RootHeight = Root.AbsoluteSize.Y end
    end)

    local Y
    if TopBarFrame and TopBarFrame.AbsoluteSize.Y > 0 then
        local TopBarCenterY = TopBarFrame.AbsolutePosition.Y + TopBarFrame.AbsoluteSize.Y / 2
        Y = TopBarCenterY - ParentY - RootHeight / 2
    elseif ParentHeight > 0 then
        Y = (ParentHeight - RootHeight) / 2
    else
        return
    end

    local Position = Root.Position
    Root.Position = UDim2.new(Position.X.Scale, Position.X.Offset, 0, math.floor(Y + 0.5))
end
local function IsVoiceBetaBadgeEligible()
	return VoiceGameSupported == true
		and VoiceAccountAllowed == true
		and VoiceOptionAvailable == true
end

RefreshVoiceBetaBadgeVisibility = function()
	if not VoiceBetaBadgeRoot or not VoiceBetaBadgeRoot.Parent then return end
	local MenuShowing = (Hub and Hub.Visible == true) or SystemMenuButtonClosing == true
	local ShouldShow = IsVoiceBetaBadgeEligible() and not MenuShowing
	if VoiceBetaNativeOriginalRoot and VoiceBetaNativeOriginalRoot.Parent
		and VoiceBetaNativeOriginalRoot ~= VoiceBetaBadgeRoot then
		pcall(function() VoiceBetaNativeOriginalRoot.Visible = false end)
	end
	VoiceBetaBadgeRoot.Visible = ShouldShow
	if not ShouldShow then
		VoiceBetaPopupOpen = false
		VoiceBetaPopup.Visible = false
	elseif VoiceBetaPopupOpen then
		PositionVoiceBetaPopup()
	end
end

local VoiceBetaLastToggleAt = 0
PositionVoiceBetaPopup = function()
	-- The popup is a child of the zero-width anchor in both custom and native
	-- modes. The anchor is laid out beside the badge; the popup itself drops below
	-- the anchor so its height cannot pull it upward or clip it at the screen edge.
	local Anchor = VoiceBetaPopupAnchor
	if not (VoiceBetaPopup and Anchor and Anchor.Parent) then return end
	pcall(function()
		Anchor.ClipsDescendants = false
		Anchor.Size = UDim2.new(0, 0, 0, 32)
		VoiceBetaPopup.AnchorPoint = Vector2.new(0, 0)
		VoiceBetaPopup.Position = UDim2.new(0, 0, 1, 6)
		VoiceBetaPopup.ClipsDescendants = false
	end)
end

local function ToggleVoiceBetaPopup()
	-- Avoid a double toggle if an engine build raises both Activated and a
	-- child-input fallback for the same physical click.
	local Now = os.clock()
	if Now - VoiceBetaLastToggleAt < 0.12 then return end
	VoiceBetaLastToggleAt = Now
	if not VoiceBetaBadgeRoot.Visible or not IsVoiceBetaBadgeEligible() then
		VoiceBetaPopupOpen = false
		VoiceBetaPopup.Visible = false
		RefreshVoiceBetaBadgeVisibility()
		return
	end
	VoiceBetaPopupOpen = not VoiceBetaPopupOpen
	if VoiceBetaPopupOpen then PositionVoiceBetaPopup() end
	VoiceBetaPopup.Visible = VoiceBetaPopupOpen
end

-- Reuse the native TopBarApp handlers when the native hierarchy is present.
-- Adding another toggler to the same native button cancels its own toggle on clients
-- that already open/close the original popup internally. Only the fallback needs code.
if not VoiceBetaUsingNativeHierarchy then
	Connect(VoiceBetaBadgeButton.Activated, ToggleVoiceBetaPopup)
	Connect(VoiceBetaLearnMoreButton.MouseButton1Click, function()
		local Url = "https://en.help.roblox.com/hc/en-us/articles/4405807645972-Voice-FAQ"
		local Opened = pcall(function() GuiService:OpenBrowserWindow(Url) end)
		if not Opened then pcall(function() StarterGui:SetCore("OpenBrowserWindow", Url) end) end
	end)
end

-- TopBarApp can finish loading after this script starts. Move the isolated badge
-- into its LeftFrame when it appears so clicks are handled by the native top bar.
Spawn(function()
	for _ = 1, 40 do
		Wait(0.25)
		if not (VoiceBetaBadgeRoot and VoiceBetaBadgeRoot.Parent) then return end
		local LeftFrame = FindVoiceBetaTopBarLeftFrame()
		if LeftFrame then
			if VoiceBetaNativeOriginalRoot and VoiceBetaNativeOriginalRoot.Parent
				and VoiceBetaNativeOriginalRoot ~= VoiceBetaBadgeRoot then
				pcall(function() VoiceBetaNativeOriginalRoot.Visible = false end)
			end
			if VoiceBetaBadgeRoot.Parent ~= LeftFrame then
				VoiceBetaBadgeRoot.Parent = LeftFrame
				VoiceBetaBadgeRoot.Position = UDim2.new(0, 0, 0, 0)
				VoiceBetaBadgeRoot.LayoutOrder = 4
			end
            VoiceBetaTopBarLeftFrame = LeftFrame
            CenterVoiceBetaBadge()
            if VoiceBetaPopupOpen then PositionVoiceBetaPopup() end
			return
		end
	end
end)

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
	-- Start as the normal 4:3 menu size; ResizeHub expands it only on phones.
	Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.fromOffset(TOTAL_HUB_WIDTH, 600),
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
		-- Read the full phone viewport AFTER removing safe insets. AbsoluteSize may
		-- still reflect the old inset rectangle for this resize pass.
		pcall(function()
			local Camera = workspace.CurrentCamera
			if Camera and Camera.ViewportSize.X > 0 and Camera.ViewportSize.Y > 0 then
				Viewport = Camera.ViewportSize
			end
		end)
	else
		-- Keep physical-screen coordinates on desktop/macOS/tablets too. The menu
		-- itself remains capped in its platform branch; this only fixes the origin.
		pcall(function() ScreenGui.IgnoreGuiInset = true end)
		pcall(function() ScreenGui.ScreenInsets = Enum.ScreenInsets.None end)
		pcall(function() ScreenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None end)
		pcall(function()
			local Camera = workspace.CurrentCamera
			if Camera and Camera.ViewportSize.X > 0 and Camera.ViewportSize.Y > 0 then
				Viewport = Camera.ViewportSize
			end
		end)
	end

	-- UIAspectRatioConstraint has no Enabled property. Use explicit viewport-
	-- aware geometry on phones and desktop; retain the legacy ratio on tablets.
	if Hub.MenuAspectRatio then
		-- Phones and desktop use explicit viewport-aware geometry. Letting the
		-- legacy 4:3 constraint reattach on PC was shrinking the ESC menu again.
		if IsPhone or (not IsMobile and not IsTablet) then
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

			local PhonePageSideInset = 16
			Width = math.max(1, math.min(TOTAL_HUB_WIDTH, math.floor(LayoutViewport.X - PhonePageSideInset * 2 + 0.5)))

			-- Keep the invite page below the camera/notch region while the HubBar
			-- itself remains edge-to-edge.
			local PageTop = 48

			PageHeight = math.max(160, math.floor(LayoutViewport.Y - PageTop - 12 + 0.5))

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

			-- Size the desktop ESC shell BEFORE measuring the invite page. ResizeHub
			-- enters this branch as soon as invite mode is active, so relying on the
			-- normal-page branch leaves the old/short menu size in place until another
			-- interaction happens. Keep the same dimensions as the classic desktop path.
			local DesktopWidth = math.max(280, math.min(TOTAL_HUB_WIDTH, math.floor(Viewport.X - 32 + 0.5)))
			local DesktopHeight = math.min(800, math.max(300, math.floor(Viewport.Y - 32 + 0.5)))
			Hub.MenuContainer.Size = UDim2.fromOffset(DesktopWidth, DesktopHeight)
			Hub.MenuContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
			Hub.MenuContainer.AnchorPoint = Vector2.new(0.5, 0.5)
			Width = DesktopWidth
			PageHeight = DesktopHeight

			if Hub.PageClipper.Parent ~= Hub.MenuContainer then
				Hub.PageClipper.Parent = Hub.MenuContainer
			end
			Hub.PageClipper.AnchorPoint = Vector2.new(0, 0)
			Hub.PageClipper.Size = UDim2.new(1, 0, 1, 0)
			Hub.PageClipper.Position = UDim2.new(0, 0, 0, 0)

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
			if USE_NEW_INVITE_MENU then
				-- Keep the larger list area; the share row now scrolls inside it.
				InviteList.Size = UDim2.new(1, -12, 1, -65)
				InviteList.Position = UDim2.new(0, 6, 0, 65)
			else
				InviteList.Size = UDim2.new(1, -12, 1, -75)
				InviteList.Position = UDim2.new(0, 6, 0, 65)
			end
		end
		if NewInviteShareRow then
			NewInviteShareRow.Visible = USE_NEW_INVITE_MENU
			-- Match the player rows exactly: full InviteList width, zero side inset.
			NewInviteShareRow.Size = UDim2.new(1, 0, 0, INVITE_SHARE_ROW_HEIGHT)
			NewInviteShareRow.Position = UDim2.new(0, 0, 0, 0)
		end

		if not IsMobile then
			InvitePage.Frame.Size = UDim2.new(1, 0, 1, 0)
		else
			InvitePage.Frame.Size = UDim2.new(1, 0, 0, PageHeight)
		end

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
			and math.max(1, math.min(800, math.floor(LayoutViewport.X - 32 + 0.5)))
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
					-- Keep the sliced button background unchanged while disabled.
					First.ImageColor3 = Color3.new(1, 1, 1)
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
		local PageGap = 8
		local BottomGap = 6
		-- Include the top offset and HubBar gap in the vertical budget.
		local PageHeight = math.max(300, math.floor(LayoutViewport.Y - TabletGroupTop - HubHeight - PageGap - BottomHeight - BottomGap - 16 + 0.5))

		Hub.MenuContainer.Size = UDim2.new(0, Width, 0, math.min(LayoutViewport.Y - 10, TabletGroupTop + HubHeight + PageGap + PageHeight + BottomHeight + BottomGap + Top))
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
		Hub.PageClipper.Position = UDim2.new(0, 0, 0, TabletGroupTop + HubHeight + PageGap)

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

		-- Keep the transparent root viewport-sized for modal/shield positioning,
		-- but keep every visible menu surface inset on phones.
		Hub.MenuContainer.Size = UDim2.new(1, 0, 1, 0)
		Hub.MenuContainer.Position = UDim2.new(0, 0, 0, 0)
		Hub.MenuContainer.AnchorPoint = Vector2.new(0, 0)
		local PhoneBarSideInset = 8
		local PhonePageSideInset = 16
		local Width = math.max(1, math.floor(LayoutViewport.X - PhonePageSideInset * 2 + 0.5))

		local GroupTop = SYSTEM_MENU_SIZE.Y + MOBILE_MENU_GAP
		local MobileBarHeight = math.max(44, MOBILE_HUBBAR_HEIGHT)

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
		Hub.HubBar.Size = UDim2.new(1, -(PhoneBarSideInset * 2), 0, MobileBarHeight)
		Hub.HubBar.Position = UDim2.new(0, PhoneBarSideInset, 0, GroupTop)

		Hub.HubBarContainer.Size = UDim2.new(1, 0, 1, 0)
		Hub.HubBarContainer.Position = UDim2.new(0, 0, 0, 0)
		if Hub.HubBarContainerLayout then Hub.HubBarContainerLayout.Parent = Hub.HubBarContainer end

		Hub.PageClipper.Size = UDim2.new(1, -(PhonePageSideInset * 2), 0, PageHeight)
		Hub.PageClipper.Position = UDim2.new(0, PhonePageSideInset, 0.5, PageCenterYOffset)

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

			local ActionHeight = 62
            local MobileVoiceIncluded = VoiceOptionAvailable == true and VoiceChatButton ~= nil and not VOICE_CHAT_FORCE_OFF
            if VoiceChatButton then
                VoiceChatButton.Visible = MobileVoiceIncluded
                if not MobileVoiceIncluded then VoiceChatButton.Parent = nil end
            end
            local PhoneActionButtons = {
                MobileActionButtons.Leave,
                MobileActionButtons.Reset,
                MobileActionButtons.Resume,
            }
            if MobileVoiceIncluded then table.insert(PhoneActionButtons, VoiceChatButton) end
            local ActionCount = #PhoneActionButtons
            -- Every visible phone action gets one equal-width slot. This keeps
            -- VC next to the other controls instead of stranded at the far edge.
            local ActionWidth = 1 / math.max(1, ActionCount)

            if not MobileButtonsContainer or not MobileButtonsContainer.Parent then
                MobileButtonsContainer = Create("Frame", {
                    Name = "ButtonsContainer",
                    Parent = PlayersPage.Frame,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, ActionHeight),
                    Position = UDim2.new(0, 0, 0, 0),
                    ZIndex = SETTINGS_BASE_ZINDEX + 1,
                })
            end
            MobileButtonsContainer.Size = UDim2.new(1, 0, 0, ActionHeight)
            MobileButtonsContainer.Position = UDim2.new(0, 0, 0, 0)

            for Index, Button in ipairs(PhoneActionButtons) do
                if Button then
                    Button.Parent = MobileButtonsContainer
                    Button.ZIndex = SETTINGS_BASE_ZINDEX + 4
                    Button.Visible = Button ~= VoiceChatButton or MobileVoiceIncluded

                    if Button == VoiceChatButton then
                        Button.AnchorPoint = Vector2.new(0, 0)
                        Button.Size = UDim2.new(ActionWidth, -4, 0, ActionHeight)
                        Button.Position = UDim2.new((Index - 1) * ActionWidth, 2, 0, 0)
                        Button.ClipsDescendants = true
                        local VoiceIcon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
                        if VoiceIcon then
                            VoiceIcon.Visible = true
                            VoiceIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                            VoiceIcon.Size = UDim2.fromOffset(36, 36)
                            VoiceIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
                            pcall(function() VoiceIcon.ScaleType = Enum.ScaleType.Fit end)
                        end
                    else
                        Button.AnchorPoint = Vector2.new(0, 0)
                        Button.Size = UDim2.new(ActionWidth, -4, 0, ActionHeight)
                        Button.Position = UDim2.new((Index - 1) * ActionWidth, 2, 0, 0)
                        local Label = Button:FindFirstChild(Button.Name .. "TextLabel")
                        if Label then
                            Label.Position = UDim2.new(0, 0, 0, 0)
                            Label.Size = UDim2.new(1, 0, 1, -6)
                            Label.ZIndex = SETTINGS_BASE_ZINDEX + 5
                            Label.TextWrapped = false
                            Label.TextScaled = true
                            Label.TextSize = 18
                            local LabelConstraint = Label:FindFirstChildOfClass("UITextSizeConstraint")
                            if LabelConstraint then
                                LabelConstraint.MinTextSize = 15
                                LabelConstraint.MaxTextSize = 18
                            else
                                Create("UITextSizeConstraint", {Parent = Label, MinTextSize = 15, MaxTextSize = 18})
                            end
                            Label.TextXAlignment = Enum.TextXAlignment.Center
                            Label.TextYAlignment = Enum.TextYAlignment.Center
                        end
                        for _, Child in ipairs(Button:GetChildren()) do
                            if Child:IsA("ImageLabel") then Child.Visible = false end
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
				Row.Size = UDim2.new(1, -16, 0, 62)
				Row.Position = UDim2.new(0, 8, 0, PlayerStartY + ((Index - 1) * 72))
			end

			local ContentHeight = PlayerStartY + (#PlayerRows * 72)
			-- The content frame follows its real contents. PageView.CanvasSize remains
			-- viewport-sized when needed, so the page scrolls without making player
			-- rows or the underlying list frame itself fullscreen-height.
			PlayersPage.Frame.Size = UDim2.new(1, 0, 0, math.max(240, ContentHeight))
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
		-- CLASSIC DESKTOP LAYOUT (Windows + macOS)
		-- Keep the menu centered and capped; fullscreen is phone-only.
		-- ====================================================
		local ViewportWidth = math.max(280, math.floor(Viewport.X - 32 + 0.5))
		local ViewportHeight = math.max(300, math.floor(Viewport.Y - 32 + 0.5))
		local ContainerWidth = math.max(280, math.min(TOTAL_HUB_WIDTH, ViewportWidth))
		-- Keep the desktop ESC panel tall; do not calculate its height from the
		-- 4:3 width ratio. Cap only against the usable screen height.
		local ContainerHeight = math.min(800, ViewportHeight)
		local BarHeight = 60
		local BottomHeight = 70
		local PageGap = 8
		local PageHeight = math.max(150, ContainerHeight - BarHeight - BottomHeight - PageGap)

		Hub.MenuContainer.Size = UDim2.fromOffset(ContainerWidth, ContainerHeight)
		Hub.MenuContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
		Hub.MenuContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		if Hub.MenuAspectRatio and Hub.MenuAspectRatio.Parent then
			Hub.MenuAspectRatio.Parent = nil
		end

		Hub.HubBar.Parent = Hub.MenuContainer
		Hub.HubBar.AnchorPoint = Vector2.new(0, 0)
		Hub.HubBar.Size = UDim2.new(1, 0, 0, BarHeight)
		Hub.HubBar.Position = UDim2.new(0, 0, 0, 0)
		Hub.HubBar.Image = TAB_BAR_IMAGE
		Hub.HubBar.ImageTransparency = HomeButtonEnabled and 1 or 0
		Hub.HubBarContainer.Size = UDim2.new(1, HomeButtonEnabled and -70 or 0, 1, 0)
		Hub.HubBarContainer.Position = UDim2.new(0, HomeButtonEnabled and 70 or 0, 0, 0)
		if Hub.HubBarContainerLayout then Hub.HubBarContainerLayout.Parent = nil end

		if HomeButton then
			HomeButton.Visible = HomeButtonEnabled
			HomeButton.Size = UDim2.fromOffset(60, 60)
			HomeButton.Position = UDim2.new(0, 0, 0, 0)
		end

		Hub.PageClipper.Parent = Hub.MenuContainer
		Hub.PageClipper.AnchorPoint = Vector2.new(0, 0)
		Hub.PageClipper.Size = UDim2.new(1, 0, 0, PageHeight)
		Hub.PageClipper.Position = UDim2.new(0, 0, 0, BarHeight + PageGap)
		Hub.PageView.AnchorPoint = Vector2.new(0, 0)
		Hub.PageView.Position = UDim2.new(0, 0, 0, 0)
		Hub.PageView.Size = UDim2.new(1, 0, 1, -20)
		Hub.PageView.CanvasPosition = Vector2.new(0, 0)
		Hub.BottomButtonFrame.Parent = Hub.MenuContainer
		Hub.BottomButtonFrame.Size = UDim2.new(1, 0, 0, BottomHeight)
		Hub.BottomButtonFrame.Position = UDim2.new(0, 0, 1, -BottomHeight)

		if Hub.CurrentPage and Hub.CurrentPage.Frame then
			Hub.CurrentPage.Frame.Position = UDim2.new(0, 0, 0, 0)
			local PageContentHeight = math.max(0, Hub.CurrentPage.Frame.Position.Y.Offset + Hub.CurrentPage.Frame.Size.Y.Offset)
			local PageViewHeight = math.max(0, PageHeight - 20)
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
			Hub.HubBarContainerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
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
				local Title = Page.Icon:FindFirstChild("Title")
				if IsMobile then
					local IconWidth = 36
					local IconHeight = 36
					local GroupGap = 2
					local MinLeftInset = 4
					local RightInset = 8
					local TabWidth = tonumber(Tab.AbsoluteSize.X) or 0
					if TabWidth <= 0 then
						local BarWidth = tonumber(Hub.HubBar.AbsoluteSize.X) or 0
						TabWidth = BarWidth / Count
					end
					local MaxTitleWidth = math.max(28, math.floor(TabWidth - IconWidth - GroupGap - MinLeftInset - RightInset))
					local TitleWidth = MaxTitleWidth
					local FittedTextSize = 15
					if Title then
						for CandidateSize = 18, 15, -1 do
							local MeasuredWidth = GetMenuMeasuredTextWidth(Title, Title.Text, CandidateSize)
							FittedTextSize = CandidateSize
							if MeasuredWidth <= MaxTitleWidth then
								TitleWidth = math.max(28, math.ceil(MeasuredWidth + 3))
								break
							end
						end
					end
					local GroupWidth = IconWidth + GroupGap + TitleWidth
					local IconLeft = math.max(MinLeftInset, math.floor(TabWidth - RightInset - GroupWidth + 0.5))
					Page.Icon.Size = UDim2.fromOffset(IconWidth, IconHeight)
					Page.Icon.Position = UDim2.new(0, IconLeft, 0.5, -IconHeight / 2)
					if Title then
						Title.TextColor3 = Color3.new(1, 1, 1)
						Title.TextTransparency = Selected and 0 or 0.5
						Title.Size = UDim2.new(0, TitleWidth, 1, 0)
						Title.Position = UDim2.new(1, GroupGap, 0, 0)
						Title.TextWrapped = false
						Title.TextScaled = false
						Title.TextXAlignment = Enum.TextXAlignment.Right
						Title.TextYAlignment = Enum.TextYAlignment.Center
						Title.TextSize = FittedTextSize
						Title.ClipsDescendants = false
					end
				else
					if Title then
						Title.TextColor3 = Color3.new(1, 1, 1)
						Title.TextTransparency = Selected and 0 or 0.5
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
-- Distinct from account-wide VC eligibility: only mark players in this client's connected voice group or with a locally received voice meter.
VoiceCompatibleCache = {}
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

-- Roblox's current rollout semantics matter here: UseAudioApi=Automatic means
-- the legacy internal voice path today. Only Enabled makes AudioDeviceInput the
-- authoritative microphone object. Return nil only if the property is unreadable.
GetVoiceAudioApiEnabled = function()
	-- UseAudioApi is PluginSecurity on current clients. A normal read can fail even
	-- when the rollout is Enabled, which used to silently disable remote analysis.
	local Mode = nil
	local Ok = pcall(function() Mode = VoiceChatService.UseAudioApi end)
	if (not Ok or Mode == nil) and type(gethiddenproperty) == "function" then
		local HiddenOk, HiddenMode = pcall(function()
			return gethiddenproperty(VoiceChatService, "UseAudioApi")
		end)
		if HiddenOk and HiddenMode ~= nil then Mode = HiddenMode end
	end
	if Mode == nil then return nil end
	local Name = string.lower(tostring(Mode):match("([%w_]+)$") or tostring(Mode))
	if Name == "enabled" or Name == "2" then return true end
	if Name == "disabled" or Name == "automatic" or Name == "0" or Name == "1" then return false end
	return nil
end

local function ReadVoiceInputProperty(Input, Property)
	if not Input then return nil, false end
	local Ok, Value = pcall(function() return Input[Property] end)
	if Ok and Value ~= nil then return Value, true end
	-- IsReady/Active can be RobloxScriptSecurity on some clients. Use the hidden
	-- property reader only as a fallback; never make a missing protected read look
	-- like an explicit false value.
	if type(gethiddenproperty) == "function" then
		local HiddenOk, HiddenValue = pcall(function() return gethiddenproperty(Input, Property) end)
		if HiddenOk and HiddenValue ~= nil then return HiddenValue, true end
	end
	return nil, false
end

-- A real, correctly-owned AudioDeviceInput is the authoritative modern Audio API
-- object. IsReady is protected on some clients, so unreadability must not reject it.
local function IsConfirmedRemoteVoiceInput(Player, Input)
	if not Player or not Input then return false end
	local Valid = false
	local ReadOk = pcall(function()
		Valid = Input:IsA("AudioDeviceInput")
			and Input.Player == Player
			and Input.Name ~= "Settings2016LocalAudioDeviceInput"
	end)
	if not ReadOk or not Valid then return false end
	if Player == LocalPlayer then return true end
	-- AudioDeviceInput only proves remote voice eligibility on the modern Audio API
	-- path. If rollout state is Automatic, Disabled, or unreadable, fail closed:
	-- some client builds expose audio objects that are not evidence of VC access.
	if GetVoiceAudioApiEnabled() ~= true then return false end
	-- IsReady can be false while initializing or protected on some clients; class,
	-- exact Player ownership, and confirmed Audio API rollout are the evidence.
	return true
end

-- Remote meter inputs are eligibility evidence only when the modern Audio API is
-- explicitly enabled. Unknown/legacy rollout must never promote a remote VC icon.
local function IsRemoteVoiceMeterInput(Player, Input)
	if not Player or not Input or not Input.Parent or Player == LocalPlayer then return false end
	if GetVoiceAudioApiEnabled() ~= true then return false end
	local Valid = false
	pcall(function()
		Valid = Input:IsA("AudioDeviceInput")
			and Input.Player == Player
			and Input.Name ~= "Settings2016LocalAudioDeviceInput"
	end)
	return Valid
end

GetAudioDeviceInputCache = {}
VoiceActivityPeak = {}
VoiceActivityStamp = {}
VoiceActivityPeakMeasured = {}
VoiceActivityActive = {}
VoiceActivitySpeakingState = {}
VoiceActivitySpeakingStateStamp = {}
NativeVoiceIconObjects = {}
NativeVoiceIconImages = {}
-- These caches are used only for the local user's mute/connection icon.
NativeVoiceIconLastImages = {}
NativeVoiceIconLastSeenAt = {}
NativeVoiceIconConnections = {}
NativeVoiceIconPropertyConnections = {}
NativeVoiceIconConnectedObjects = {}
NativeVoiceScanStamp = 0
NativeVoiceScanScheduled = false

DisconnectNativeVoiceIconConnections = function(UserId)
	local ChangedConnection = NativeVoiceIconConnections[UserId]
	if ChangedConnection then
		pcall(function() ChangedConnection:Disconnect() end)
		NativeVoiceIconConnections[UserId] = nil
	end
	local PropertyConnections = NativeVoiceIconPropertyConnections[UserId]
	if type(PropertyConnections) == "table" then
		for _, Connection in ipairs(PropertyConnections) do
			pcall(function() Connection:Disconnect() end)
		end
	end
	NativeVoiceIconPropertyConnections[UserId] = nil
	NativeVoiceIconConnectedObjects[UserId] = nil
end

-- Index real Roblox-created voice inputs once. Earlier builds scanned every
-- CoreGui/SoundService descendant on every icon refresh, which caused severe UI lag.
VoiceAudioInputIndexInitialized = false
IndexExistingVoiceAudioInputs = function()
	if VoiceAudioInputIndexInitialized then return end
	-- Do not permanently mark the scan complete while rollout state is unknown;
	-- retry once Roblox reports Audio API Enabled.
	if GetVoiceAudioApiEnabled() ~= true then return end
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
		if Owner ~= LocalPlayer and not IsConfirmedRemoteVoiceInput(Owner, Candidate) then return end
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
end

GetAudioDeviceInput = function(Player)
	if not Player then return nil end
	local AudioApiMode = GetVoiceAudioApiEnabled()
	-- For remote players, only the explicit Enabled rollout makes a Player-owned
	-- AudioDeviceInput authoritative for voice eligibility. A nil/unreadable mode
	-- must not be interpreted as permission to show a VC icon.
	if Player ~= LocalPlayer and AudioApiMode ~= true then
		GetAudioDeviceInputCache[Player] = nil
		return nil
	end
	-- Keep the local user's prior fallback behavior when rollout state is unknown,
	-- but never use local legacy-mode inputs to infer remote eligibility.
	if Player == LocalPlayer and AudioApiMode == false then
		GetAudioDeviceInputCache[Player] = nil
		return nil
	end
	local Cached = GetAudioDeviceInputCache[Player]
	if Cached and Cached.Parent then
		local Matches = false
		pcall(function()
			Matches = Cached:IsA("AudioDeviceInput")
				and Cached.Player == Player
				and Cached.Name ~= "Settings2016LocalAudioDeviceInput"
		end)
		if Matches and Player ~= LocalPlayer then
			Matches = IsConfirmedRemoteVoiceInput(Player, Cached)
		end
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
		if Player ~= LocalPlayer and not IsConfirmedRemoteVoiceInput(Player, Candidate) then return end
		local Score = 0
		local Ready, ReadyReadable = ReadVoiceInputProperty(Candidate, "IsReady")
		local Active, ActiveReadable = ReadVoiceInputProperty(Candidate, "Active")
		local Muted, MutedReadable = ReadVoiceInputProperty(Candidate, "Muted")
		if ReadyReadable and Ready == true then Score += 8 end
		if ActiveReadable and Active == true then Score += 4 end
		if MutedReadable and Muted == true then Score -= 1 end
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

EnsureVoiceAnalyzer = function(Player, InputOverride)
	if not Player then return nil end

	local Input = InputOverride
	if not Input and Player ~= LocalPlayer and type(GetVoiceMeterInput) == "function" then
		Input = GetVoiceMeterInput(Player)
	end
	if not Input then Input = GetAudioDeviceInput(Player) end
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
	local MeterInput = nil
	if Player and Player ~= LocalPlayer and type(GetVoiceMeterInput) == "function" then
		MeterInput = GetVoiceMeterInput(Player)
	end
	local Analyzer = EnsureVoiceAnalyzer(Player, MeterInput)
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

-- Meter-only lookup. The mute-state path remains gated by GetAudioDeviceInput;
-- this separate lookup lets the live peak analyzer use a genuine active input if the
-- client exposes one, without trusting it as authoritative mute state in legacy mode.
VoiceMeterInputCache = VoiceMeterInputCache or {}
VoiceMeterInputScanStamp = VoiceMeterInputScanStamp or setmetatable({}, {__mode = "k"})
VoiceMeterInputCoreGuiScanStamp = VoiceMeterInputCoreGuiScanStamp or setmetatable({}, {__mode = "k"})
GetVoiceMeterInput = function(Player)
	if not Player then return nil end
	local function IsUsable(Input)
		if not Input or not Input.Parent then return false end
		local Valid = false
		pcall(function()
			Valid = Input:IsA("AudioDeviceInput")
				and Input.Player == Player
				and Input.Name ~= "Settings2016LocalAudioDeviceInput"
		end)
		if not Valid then return false end
		if Player == LocalPlayer then return true end
		return IsRemoteVoiceMeterInput(Player, Input)
	end

	local Cached = VoiceMeterInputCache[Player]
	if IsUsable(Cached) then return Cached end
	VoiceMeterInputCache[Player] = nil

	Cached = GetAudioDeviceInputCache[Player]
	if IsUsable(Cached) then
		VoiceMeterInputCache[Player] = Cached
		return Cached
	end

	local Now = os.clock()
	if Now - (VoiceMeterInputScanStamp[Player] or 0) < 0.6 then return nil end
	VoiceMeterInputScanStamp[Player] = Now

	local Best, BestScore = nil, -math.huge
	pcall(function()
		for _, Child in ipairs(Player:GetChildren()) do
			if IsUsable(Child) then
				local Active, ActiveReadable = ReadVoiceInputProperty(Child, "Active")
				local Ready, ReadyReadable = ReadVoiceInputProperty(Child, "IsReady")
				local Muted, MutedReadable = ReadVoiceInputProperty(Child, "Muted")
				if not (ActiveReadable and Active == false) then
					local Score = (ReadyReadable and Ready == true and 8 or 0)
						+ (ActiveReadable and Active == true and 4 or 0)
						+ (MutedReadable and Muted == true and -1 or 0)
					if Score > BestScore then Best, BestScore = Child, Score end
				end
			end
		end
	end)
	if Best then
		VoiceMeterInputCache[Player] = Best
		GetAudioDeviceInputCache[Player] = Best
	end
	return Best
end


EnsureVoiceMeterAnalyzer = function(Player)
	if not Player then return nil end
	if Player ~= LocalPlayer then
		local Input = GetVoiceMeterInput(Player) or GetAudioDeviceInput(Player)
		if Input then return EnsureVoiceAnalyzer(Player, Input) end
		return nil
	end

	local Input = GetVoiceMeterInput(Player)
	if not Input then return GetVoiceAnalyzer(Player) end

	local Analyzer = VoiceAnalyzers[Player]
	if not (Analyzer and Analyzer.Parent and Analyzer:IsA("AudioAnalyzer")) then
		pcall(function()
			Analyzer = SoundService:FindFirstChild("Settings2016VoiceAnalyzer_" .. tostring(Player.UserId))
		end)
	end
	if not Analyzer then
		pcall(function()
			Analyzer = Instance.new("AudioAnalyzer")
			Analyzer.Name = "Settings2016VoiceAnalyzer_" .. tostring(Player.UserId)
			Analyzer.SpectrumEnabled = false
			Analyzer.Parent = SoundService
		end)
	end
	if not Analyzer then return nil end

	local Wire = VoiceAnalyzerWires[Player]
	if not (Wire and Wire.Parent and Wire:IsA("Wire")) then
		Wire = nil
		pcall(function()
			for _, Child in ipairs(Analyzer:GetChildren()) do
				if Child:IsA("Wire") then Wire = Child; break end
			end
		end)
	end
	if not Wire then
		pcall(function()
			Wire = Instance.new("Wire")
			Wire.Name = "Settings2016VoiceMeterWire"
			Wire.Parent = Analyzer
		end)
	end
	if not Wire then return nil end
	local Wired = pcall(function()
		Wire.SourceInstance = Input
		Wire.SourceName = "Output"
		Wire.TargetInstance = Analyzer
		Wire.TargetName = "Input"
	end)
	if not Wired then return nil end
	VoiceAnalyzers[Player] = Analyzer
	VoiceAnalyzerWires[Player] = Wire
	return Analyzer
end

-- Discover audio sources off the UI refresh path. On experiences using the modern
-- Audio API, each voice-eligible Player owns a real AudioDeviceInput. Wire it to a local
-- AudioAnalyzer and cache the result; never inspect chat or UI objects for speech state.
local VoiceMeterDiscoveryWorkerStarted = false
if not VoiceMeterDiscoveryWorkerStarted then
	VoiceMeterDiscoveryWorkerStarted = true
	Spawn(function()
		-- Capture this run's GUI; do not let reruns keep the previous worker alive.
		local WorkerScreenGui = ScreenGui
		while WorkerScreenGui and WorkerScreenGui.Parent do
			if VoiceGameSupported then
				-- Snapshot rollout mode once per pass. Remote AudioDeviceInput can confirm
				-- eligibility only when Roblox explicitly reports the Audio API as Enabled.
				local AudioApiCanConfirmEligibility = GetVoiceAudioApiEnabled() == true
				for _, Player in ipairs(Players:GetPlayers()) do
					local Input = GetVoiceMeterInput(Player)
					if Input and Input.Parent then
						-- Keep analyzer discovery available, but don't let a meter-only input
						-- promote a player's VC icon when UseAudioApi is Disabled/Automatic.
						VoiceMeterInputCache[Player] = Input
						if Player == LocalPlayer and AudioApiCanConfirmEligibility then
							GetAudioDeviceInputCache[Player] = Input
						elseif Player ~= LocalPlayer and AudioApiCanConfirmEligibility
							and IsConfirmedRemoteVoiceInput(Player, Input) then
							GetAudioDeviceInputCache[Player] = Input
							VoiceEnabledCache[tonumber(Player.UserId) or 0] = true
						end
						pcall(function() EnsureVoiceAnalyzer(Player, Input) end)
					end
				end
			end
			Wait(0.25)
		end
	end)
end

GetVoiceLevel = function(Player)
	if not Player then return 0 end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	local Now = os.clock()
	local Stamp = tonumber(VoiceActivityStamp[UserId]) or 0
	local ActivityIsRecent = Stamp > 0 and (Now - Stamp) <= 0.65
	local ActivityPeak = tonumber(VoiceActivityPeak[UserId]) or 0
	local SpeakingState = VoiceActivitySpeakingState[UserId]
	local SpeakingStateStamp = tonumber(VoiceActivitySpeakingStateStamp[UserId]) or 0
	local SpeakingStateIsActive = SpeakingState == true and SpeakingStateStamp > 0

	if ActivityIsRecent and VoiceActivityPeakMeasured[UserId] == true
		and ActivityPeak > VOICE_SILENCE_FLOOR then
		return Clamp(ActivityPeak, 0, 1)
	end

	local Analyzer = VoiceAnalyzers[Player]
	if Analyzer and Analyzer.Parent then
		local Peak = nil
		local Rms = nil
		local Ok = pcall(function()
			Peak = tonumber(Analyzer.PeakLevel)
			Rms = tonumber(Analyzer.RmsLevel)
		end)
		if Ok then
			if Peak == nil or Peak ~= Peak then Peak = 0 end
			if Rms == nil or Rms ~= Rms then Rms = 0 end
			Peak = Clamp(math.max(Peak, Rms), 0, 1)
			if Peak > VOICE_SILENCE_FLOOR then return Peak end
		end
	end

	-- Legacy clients may expose the local user's real CoreScript mic meter sprite
	-- even when AudioDeviceInput is unavailable. This is local-only (never bubbles
	-- or remote-player UI) and is used only if the analyzer has no live level.
	if Player == LocalPlayer then
		local NativeImage = NativeVoiceIconImages[UserId]
		local NativeObject = NativeVoiceIconObjects[UserId]
		if NativeObject and NativeObject.Parent then
			pcall(function()
				local CurrentImage = tostring(NativeObject.Image or "")
				if CurrentImage ~= "" then
					NativeImage = CurrentImage
					NativeVoiceIconImages[UserId] = CurrentImage
				end
			end)
		end
		local Percent = type(NativeImage) == "string" and tonumber(NativeImage:match("Unmuted(%d+)@3x%.png")) or nil
		if Percent and Percent > 0 then return Clamp(Percent / 100, 0, 1) end
	end

	-- The internal speech event carries the state independently of proximity UI.
	-- It does not give a calibrated level, so use the first activity sprite only.
	if Player ~= LocalPlayer and SpeakingStateIsActive then
		return (VOICE_REMOTE_SILENCE_FLOOR or 0.003) + 0.04
	end
	if SpeakingState == false then return 0 end
	if ActivityIsRecent and VoiceActivityPeakMeasured[UserId] == true then
		return Clamp(ActivityPeak, 0, 1)
	end
	return 0
end

-- AudioAnalyzer.PeakLevel is a linear 0..1 amplitude, not decibels.
-- Real microphones can report a tiny residual floor while nobody is speaking;
-- suppress it so silence does not light up as the Unmuted20 sprite.
VOICE_SILENCE_FLOOR = 0.020
-- Explicit remote-speaking booleans are held until an explicit false event arrives.
-- Remote receive streams can be attenuated by proximity/volume, so use a lower
-- floor than the local capture stream while still suppressing effectively-zero samples.
VOICE_REMOTE_SILENCE_FLOOR = 0.003

VoiceUnmutedIcon = function(Level, UseSpeaker)
	local Root = UseSpeaker and VOICE_SPEAKER_ROOT or VOICE_MIC_ROOT
	local SilenceFloor = UseSpeaker and VOICE_REMOTE_SILENCE_FLOOR or VOICE_SILENCE_FLOOR
	Level = tonumber(Level) or 0
	if Level ~= Level or Level <= SilenceFloor then
		return Root .. "Unmuted0@3x.png"
	end
	-- Spread audible levels over the visible buckets after gating the silence floor.
	local AudibleLevel = Clamp((Level - SilenceFloor) / (1 - SilenceFloor), 0, 1)
	if AudibleLevel < 0.2 then return Root .. "Unmuted20@3x.png" end
	if AudibleLevel < 0.4 then return Root .. "Unmuted40@3x.png" end
	if AudibleLevel < 0.6 then return Root .. "Unmuted60@3x.png" end
	if AudibleLevel < 0.8 then return Root .. "Unmuted80@3x.png" end
	return Root .. "Unmuted100@3x.png"
end

-- Mirror only the native, per-player voice image that Roblox places inside the
-- exact ExperienceChat bubble for that UserId. This preserves Roblox's proximity-
-- limited speaking meter instead of inventing range from generic participant data.
IsNativeVoiceIconVisible = function(Object)
    if not Object then return false end
    local Current = Object
    while Current and Current ~= CoreGui do
        local Visible = true
        pcall(function()
            if Current:IsA("ScreenGui") then
                Visible = Current.Enabled
            elseif Current:IsA("GuiObject") then
                Visible = Current.Visible
            end
        end)
        if not Visible then return false end
        Current = Current.Parent
    end
    return true
end

local function IsNativeVoiceStateImage(Image)
    Image = tostring(Image or "")
    return Image:find("VoiceChat", 1, true) ~= nil
        and (Image:find("Muted", 1, true) ~= nil
            or Image:find("Unmuted", 1, true) ~= nil
            or Image:find("Connecting", 1, true) ~= nil
            or Image:find("Error", 1, true) ~= nil)
end

local function IsNativeVoicePositiveState(Image)
    Image = tostring(Image or "")
    local IsUnmuted = Image:find("Unmuted", 1, true) ~= nil
    local IsMuted = Image:find("Muted", 1, true) ~= nil and not IsUnmuted
    return Image:find("VoiceChat", 1, true) ~= nil and (IsUnmuted or IsMuted)
end

local function FindLocalNativeVoiceImageObject()
    local RobloxGui = CoreGui and CoreGui:FindFirstChild("RobloxGui")
    local Shield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")
    local Button = Shield and Shield:FindFirstChild("MuteSelfButton", true)
    if not Button then return nil end
    local Candidates = {Button}
    pcall(function()
        for _, Descendant in ipairs(Button:GetDescendants()) do table.insert(Candidates, Descendant) end
    end)
    for _, Candidate in ipairs(Candidates) do
        local IsImage, Image = false, ""
        pcall(function()
            IsImage = Candidate:IsA("ImageLabel") or Candidate:IsA("ImageButton")
            Image = tostring(Candidate.Image or "")
        end)
        if IsImage and IsNativeVoiceStateImage(Image) and IsNativeVoiceIconVisible(Candidate) then
            return Candidate
        end
    end
    return nil
end

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
        Bubble = BubbleChatRoot:FindFirstChild("BubbleChat_" .. tostring(UserId)
            ) or BubbleChatRoot:FindFirstChild(tostring(UserId))
    end)
    if not Bubble then return nil end
    local VoiceBubble = nil
    pcall(function() VoiceBubble = Bubble:FindFirstChild("VoiceBubble", true) end)
    if not VoiceBubble then return nil end

    local InsertObject = nil
    pcall(function() InsertObject = VoiceBubble:FindFirstChild("Insert", true) end)
    local function IsVoiceImage(Object)
        local IsImage, Image = false, ""
        pcall(function()
            IsImage = Object and (Object:IsA("ImageLabel") or Object:IsA("ImageButton"))
            Image = tostring(Object and Object.Image or "")
        end)
        return IsImage and IsNativeVoiceStateImage(Image)
    end
    if IsVoiceImage(InsertObject) then return InsertObject end
    local Ok, Descendants = pcall(function() return VoiceBubble:GetDescendants() end)
    if not Ok then return nil end
    local Best, BestScore = nil, -1
    for _, Object in ipairs(Descendants) do
        if IsVoiceImage(Object) then
            local Score = 0
            if string.lower(tostring(Object.Name or "")) == "insert" then Score = Score + 100 end
            if IsNativeVoiceIconVisible(Object) then Score = Score + 10 end
            if Score > BestScore then Best = Object; BestScore = Score end
        end
    end
    return Best
end

NormalizeRemoteSpeakerImage = function(Image)
    Image = tostring(Image or "")
    if Image == "" or not Image:find("VoiceChat", 1, true) then return nil end
    Image = Image:gsub("/MicDark/", "/SpeakerLight/")
    Image = Image:gsub("/MicLight/", "/SpeakerLight/")
    Image = Image:gsub("/SpeakerDark/", "/SpeakerLight/")
    if Image:find(VOICE_ICON_ROOT, 1, true)
        and not Image:find("/SpeakerLight/", 1, true)
        and not Image:find("/SpeakerDark/", 1, true) then
        local Filename = Image:match("([^/]+)$")
        if Filename then Image = VOICE_SPEAKER_ROOT .. Filename end
    end
    return Image
end

GetNativeVoiceMeterLevel = function(Player, NativeImage)
    if not Player or type(NativeImage) ~= "string" or not NativeImage:find("Unmuted", 1, true) then return nil end
    local UserId = tonumber(Player.UserId or Player.userId) or 0
    local Object = NativeVoiceIconObjects[UserId]
    if not (Object and Object.Parent) and Player ~= LocalPlayer then Object = FindNativeVoiceBubbleIconObject(Player) end
    if not Object then return nil end
    local Offset, RectSize
    local ReadOk = pcall(function() Offset = Object.ImageRectOffset; RectSize = Object.ImageRectSize end)
    if not ReadOk or not Offset or not RectSize or (RectSize.X <= 0 and RectSize.Y <= 0) then return nil end
    local FrameX, FrameY = 0, 0
    if Offset.X > 0 and RectSize.X > 0 then FrameX = math.floor(Offset.X / RectSize.X + 0.5) end
    if Offset.Y > 0 and RectSize.Y > 0 then FrameY = math.floor(Offset.Y / RectSize.Y + 0.5) end
    return Clamp(math.max(FrameX, FrameY) / 5, 0, 1)
end

RefreshRemoteVoiceButton = function(Player, SourceObject)
    if not Player or Player == LocalPlayer then return end
    local UserId = tonumber(Player.UserId or Player.userId) or 0
    if UserId <= 1 then return end
    local Row = PlayersPage and PlayersPage.Frame and PlayersPage.Frame:FindFirstChild("PlayerLabel" .. Player.Name)
    local Button = Row and Row:FindFirstChild(Player.Name .. "VoiceButton")
    local Icon = Button and Button:FindFirstChild("VoiceIcon")
    if not Icon then return end

    local Source = SourceObject
    if not (Source and Source.Parent and IsNativeVoiceIconVisible(Source)) then Source = NativeVoiceIconObjects[UserId] end
    if not (Source and Source.Parent and IsNativeVoiceIconVisible(Source)) then Source = nil end
    local NativeImage, NativeOffset, NativeRectSize = "", Vector2.new(0, 0), Vector2.new(0, 0)
    if Source then
        pcall(function()
            NativeImage = tostring(Source.Image or "")
            NativeOffset = Source.ImageRectOffset
            NativeRectSize = Source.ImageRectSize
        end)
    end

    local LocallyMuted = false
    pcall(function() LocallyMuted = GetRemoteVoiceMuted(Player) == true end)
    local NativeUnmuted = NativeImage:find("Unmuted", 1, true) ~= nil
    local NativeMuted = NativeImage:find("Muted", 1, true) ~= nil and not NativeUnmuted
    local DisplayImage = nil
    local MirrorNativeSpriteFrame = false

    if LocallyMuted or VoiceMutedPlayers[UserId] == true or NativeMuted then
        DisplayImage = VOICE_SPEAKER_ROOT .. "Muted@3x.png"
    elseif NativeUnmuted then
        -- The native bubble's atlas frame already applies Roblox's proximity gate.
        -- Mirror it directly so out-of-range players do not animate from global VAD.
        DisplayImage = NormalizeRemoteSpeakerImage(NativeImage)
        MirrorNativeSpriteFrame = DisplayImage ~= nil
            and (NativeRectSize.X > 0 or NativeRectSize.Y > 0)
    else
        local Level = 0
        pcall(function() Level = tonumber(GetVoiceLevel(Player)) or 0 end)
        Level = (Level == Level) and Clamp(Level, 0, 1) or 0
        local Now = os.clock()
        local ActivityStamp = tonumber(VoiceActivityStamp[UserId]) or 0
        local ActivityAge = ActivityStamp > 0 and (Now - ActivityStamp) or math.huge
        local ActivityRecent = ActivityAge >= 0 and ActivityAge <= 0.65
        local SpeakingState = VoiceActivitySpeakingState[UserId]
        local SpeakingStamp = tonumber(VoiceActivitySpeakingStateStamp[UserId]) or 0
        local ExplicitSpeaking = SpeakingState == true and SpeakingStamp > 0
        local MeasuredPeak = ActivityRecent and VoiceActivityPeakMeasured[UserId] == true
        if Level > VOICE_REMOTE_SILENCE_FLOOR then
            DisplayImage = VoiceUnmutedIcon(Level, true)
        elseif ExplicitSpeaking then
            DisplayImage = VOICE_SPEAKER_ROOT .. "Unmuted20@3x.png"
        elseif MeasuredPeak then
            DisplayImage = VoiceUnmutedIcon(tonumber(VoiceActivityPeak[UserId]) or 0, true)
        elseif NativeImage:find("Connecting", 1, true) or NativeImage:find("Error", 1, true) then
            DisplayImage = NormalizeRemoteSpeakerImage(NativeImage)
            MirrorNativeSpriteFrame = DisplayImage ~= nil and (NativeRectSize.X > 0 or NativeRectSize.Y > 0)
        else
            DisplayImage = VoiceContrastIcon(GetVoiceIcon(Player, false))
        end
    end

    if DisplayImage and DisplayImage ~= "" then
        if Icon.Image ~= DisplayImage then Icon.Image = DisplayImage end
        if MirrorNativeSpriteFrame and Source then
            pcall(function() Icon.ImageRectOffset = NativeOffset; Icon.ImageRectSize = NativeRectSize end)
        else
            pcall(function() Icon.ImageRectOffset = Vector2.new(0, 0); Icon.ImageRectSize = Vector2.new(0, 0) end)
        end
    end
end

RefreshNativeVoiceMirrorCache = function(Force)
    local Now = os.clock()
    local MinimumInterval = Force and 0.15 or 0.75
    if NativeVoiceScanStamp > 0 and (Now - NativeVoiceScanStamp) < MinimumInterval then return end
    NativeVoiceScanStamp = Now

    local ActiveIds = {}
    local LocalUserId = tonumber(LocalPlayer and LocalPlayer.UserId) or 0
    local LocalObject = FindLocalNativeVoiceImageObject()
    if LocalUserId > 1 and LocalObject then
        ActiveIds[LocalUserId] = true
        NativeVoiceIconObjects[LocalUserId] = LocalObject
        local Image = ""
        pcall(function() Image = tostring(LocalObject.Image or "") end)
        NativeVoiceIconImages[LocalUserId] = Image
        NativeVoiceIconLastImages[LocalUserId] = Image
        NativeVoiceIconLastSeenAt[LocalUserId] = Now
    end

    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            local UserId = tonumber(Player.UserId or Player.userId) or 0
            if UserId > 1 then
                local Source = FindNativeVoiceBubbleIconObject(Player)
                if Source and Source.Parent and IsNativeVoiceIconVisible(Source) then
                    ActiveIds[UserId] = true
                    local Previous = NativeVoiceIconObjects[UserId]
                    NativeVoiceIconObjects[UserId] = Source
                    local Image = ""
                    pcall(function() Image = tostring(Source.Image or "") end)
                    NativeVoiceIconImages[UserId] = Image
                    NativeVoiceIconLastImages[UserId] = Image
                    NativeVoiceIconLastSeenAt[UserId] = Now

                    if Previous ~= Source then
                        DisconnectNativeVoiceIconConnections(UserId)
                        NativeVoiceIconObjects[UserId] = Source
                        NativeVoiceIconConnectedObjects[UserId] = Source
                        local MainOk, MainConnection = pcall(function()
                            return Source.AncestryChanged:Connect(function()
                                if ScheduleNativeVoiceMirrorRefresh then ScheduleNativeVoiceMirrorRefresh() end
                            end)
                        end)
                        if MainOk then NativeVoiceIconConnections[UserId] = MainConnection end
                        local Connections = {}
                        for _, PropertyName in ipairs({"Image", "ImageRectOffset", "ImageRectSize", "Visible"}) do
                            pcall(function()
                                table.insert(Connections, Source:GetPropertyChangedSignal(PropertyName):Connect(function()
                                    local CurrentImage = ""
                                    pcall(function() CurrentImage = tostring(Source.Image or "") end)
                                    NativeVoiceIconImages[UserId] = CurrentImage
                                    NativeVoiceIconLastImages[UserId] = CurrentImage
                                    NativeVoiceIconLastSeenAt[UserId] = os.clock()
                                    if RefreshRemoteVoiceButton then RefreshRemoteVoiceButton(Player, Source) end
                                    if PropertyName == "Visible" and ScheduleNativeVoiceMirrorRefresh then ScheduleNativeVoiceMirrorRefresh() end
                                end))
                            end)
                        end
                        NativeVoiceIconPropertyConnections[UserId] = Connections
                    end
                    if RefreshRemoteVoiceButton then RefreshRemoteVoiceButton(Player, Source) end
                end
            end
        end
    end

    for UserId in pairs(NativeVoiceIconObjects) do
        if not ActiveIds[UserId] then
            NativeVoiceIconObjects[UserId] = nil
            NativeVoiceIconImages[UserId] = nil
            if UserId ~= LocalUserId then
                NativeVoiceIconLastImages[UserId] = nil
                NativeVoiceIconLastSeenAt[UserId] = nil
                DisconnectNativeVoiceIconConnections(UserId)
            end
        end
    end
end

ScheduleNativeVoiceMirrorRefresh = function()
    if NativeVoiceScanScheduled then return end
    NativeVoiceScanScheduled = true
    Spawn(function()
        Wait(0.12)
        NativeVoiceScanScheduled = false
        RefreshNativeVoiceMirrorCache(true)
    end)
end

FindNativeVoiceIcon = function(Player)
    if not Player then return nil end
    local UserId = tonumber(Player.UserId or Player.userId) or 0
    local Now = os.clock()
    local Object = NativeVoiceIconObjects[UserId]
    if Player == LocalPlayer then
        if not (Object and Object.Parent and IsNativeVoiceIconVisible(Object))
            or not NativeSelfIconProbeStamp or (Now - NativeSelfIconProbeStamp) >= 0.35 then
            NativeSelfIconProbeStamp = Now
            Object = FindLocalNativeVoiceImageObject()
            NativeVoiceIconObjects[UserId] = Object
        end
    elseif not (Object and Object.Parent and IsNativeVoiceIconVisible(Object)) then
        Object = FindNativeVoiceBubbleIconObject(Player)
        if Object and Object.Parent and IsNativeVoiceIconVisible(Object) then
            NativeVoiceIconObjects[UserId] = Object
        else
            Object = nil
        end
    end
    if Object and Object.Parent then
        local Image = ""
        pcall(function() Image = tostring(Object.Image or "") end)
        if Image ~= "" then
            NativeVoiceIconImages[UserId] = Image
            NativeVoiceIconLastImages[UserId] = Image
            NativeVoiceIconLastSeenAt[UserId] = Now
            return Image
        end
    end
    return nil
end

FindNativePlayerVoice = function(Player)
	if not Player or Player == LocalPlayer then return false end
	local UserId = tonumber(Player.UserId or Player.userId) or 0
	if UserId <= 1 then return false end
	-- Do not infer entitlement from a rendered chat-bubble image: CoreGui can keep
	-- template VoiceBubble objects around for players who do not have VC. The only
	-- Audio API signal accepted here is a verified Player-owned input in Enabled mode.
	return GetVoiceAudioApiEnabled() == true and GetAudioDeviceInput(Player) ~= nil
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

	-- A player can be globally voice-eligible but belong to a different age/voice
	-- group. Do not show a target mute button just because their AudioDeviceInput
	-- exists. The authoritative client-side compatibility evidence is membership in
	-- the current internal voice session, or a non-zero native/local receive meter.
	if VoiceCompatibleCache[UserId] == true then return true end

	-- Do not use this script's AudioAnalyzer as compatibility evidence: its extra
	-- input-to-analyzer wire can measure a remote mic source without proving that
	-- Roblox is routing that speaker to this listener's age/voice group.
	-- Only the native per-player VoiceBubble's proximity-limited atlas meter can act
	-- as a local reception fallback when the internal joined-participant event is absent.
	local Native = FindNativeVoiceIcon(Player)
	if Native then
		local Meter = GetNativeVoiceMeterLevel(Player, Native)
		if type(Meter) == "number" and Meter > 0 then
			VoiceCompatibleCache[UserId] = true
			return true
		end
	end
	return false
end

GetVoiceIcon = function(Player, ForcedMuted)
	local UserId = tonumber(Player and (Player.UserId or Player.userId)) or 0
	local IsLocal = Player == LocalPlayer
	local Root = IsLocal and VOICE_MIC_ROOT or VOICE_SPEAKER_ROOT
	local Native = FindNativeVoiceIcon(Player)
	local function StateIcon(State)
		return Root .. State .. "@3x.png"
	end
	local function IsMutedImage(Image)
		return type(Image) == "string" and Image:find("Muted", 1, true) ~= nil
			and Image:find("Unmuted", 1, true) == nil
	end
	local function IsUnmutedImage(Image)
		return type(Image) == "string" and Image:find("Unmuted", 1, true) ~= nil
	end

	-- A row's mute glyph describes our local receive-side mute, not the other
	-- person's microphone state. Remote participants use SpeakerLight sprites.
	if not IsLocal and (ForcedMuted == true or VoiceMutedPlayers[UserId] == true) then
		return StateIcon("Muted")
	end

	-- Preserve a genuine native muted state before considering speech activity.
	if not IsLocal and IsMutedImage(Native) then
		return StateIcon("Muted")
	end

	if IsLocal then
		-- Live input/publisher state is authoritative. A native icon image can lag
		-- behind a mute click, so it must not get first refusal over that state.
		local StateOk, Muted = pcall(function() return GetLocalVoiceMuted() end)
		if StateOk and Muted == true then return StateIcon("Muted") end

		-- Only trust a native muted image if the real underlying state is unknown.
		if IsMutedImage(Native) and not (StateOk and Muted == false) then
			return StateIcon("Muted")
		end

		local HasLiveUnmutedState = StateOk and Muted == false
		if IsUnmutedImage(Native) or HasLiveUnmutedState then
			local ActivityLevel = GetVoiceLevel(Player)
			if VoiceActivitySpeakingState[UserId] == true and ActivityLevel <= VOICE_SILENCE_FLOOR then
				-- Legacy VAD can indicate activity without numeric samples.
				return VOICE_MIC_ROOT .. "Unmuted20@3x.png"
			end
			return VoiceUnmutedIcon(ActivityLevel, false)
		end

		if StateOk and Muted == nil then return StateIcon("Connecting") end
		-- Use the analyzer already wired by the background setup worker. Never search
		-- Player/Character descendants from the render path.
		local Analyzer = VoiceAnalyzers[Player]
		if Analyzer and Analyzer.Parent then
			local Ok, Level = pcall(function() return tonumber(Analyzer.PeakLevel) end)
			if Ok and Level and Level > 0.00001 then return VoiceUnmutedIcon(Clamp(Level, 0, 1), false) end
		end
		local ActivityLevel = GetVoiceLevel(Player)
		if ActivityLevel > VOICE_SILENCE_FLOOR then return VoiceUnmutedIcon(ActivityLevel, false) end
		if VoiceActivitySpeakingState[UserId] == true then return VOICE_MIC_ROOT .. "Unmuted20@3x.png" end
		return StateIcon("Unmuted0")
	end

	-- Remote speech animation is derived only from audio samples/activity events.
	local Now = os.clock()
	local ActivityStamp = tonumber(VoiceActivityStamp[UserId]) or 0
	local ActivityAge = ActivityStamp > 0 and (Now - ActivityStamp) or math.huge
	local HasRecentActivity = ActivityAge >= 0 and ActivityAge <= 0.65
	local SpeakingState = VoiceActivitySpeakingState[UserId]
	local SpeakingStateStamp = tonumber(VoiceActivitySpeakingStateStamp[UserId]) or 0
	local HasExplicitSpeakingState = SpeakingState == true and SpeakingStateStamp > 0

	if not HasRecentActivity and VoiceActivityActive[UserId] == true then
		VoiceActivityActive[UserId] = false
		VoiceActivityPeak[UserId] = 0
		VoiceActivityPeakMeasured[UserId] = false
	end

	-- GetVoiceLevel reads cached analyzer samples or explicit activity events only.
	local Level = 0
	local LevelOk = pcall(function() Level = tonumber(GetVoiceLevel(Player)) or 0 end)
	if not LevelOk or Level ~= Level then Level = 0 end
	Level = Clamp(Level, 0, 1)
	if Level > VOICE_REMOTE_SILENCE_FLOOR then
		return VoiceUnmutedIcon(Level, true)
	end

	-- Legacy/internal speech-state events do not always expose a numeric level.
	-- Their explicit true state remains latched until an explicit false event arrives.
	if HasExplicitSpeakingState then
		return StateIcon("Unmuted20")
	end

	-- Remote mute/connection status comes from local mute state and voice eligibility.
	local CachedInput = VoiceMeterInputCache[Player] or GetAudioDeviceInputCache[Player]
	if type(Native) == "string" and Native ~= "" then
		if IsMutedImage(Native) then return StateIcon("Muted") end
		if Native:find("Error", 1, true) or Native:find("Connecting", 1, true) then
			if VoiceEnabledCache[UserId] == true or CachedInput ~= nil then
				return StateIcon("Unmuted0")
			end
			return StateIcon("Connecting")
		end
	end

	if SpeakingState == false then
		return StateIcon("Unmuted0")
	end
	if VoiceEnabledCache[UserId] == true or CachedInput ~= nil then
		return StateIcon("Unmuted0")
	end
	return StateIcon("Connecting")
end

VoiceProcessActivityInfo = function(ActivityInfo, AllowLegacyActiveState)
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
	local function MarkVoiceActivityEvidence()
		-- Do not mark someone voice-enabled simply because an inactive/zero event
		-- arrived. Only positive speech evidence or a true speaking-only event counts.
		if not ActivityPlayer then return end
		local WasKnown = VoiceEnabledCache[UserId] == true
		VoiceEnabledCache[UserId] = true
		VoiceCheckError[UserId] = nil
		if not WasKnown and RebuildPlayersPage then RebuildPlayersPage() end
	end

	-- Prefer speech-specific flags. A generic `active` field can describe a connection
	-- rather than speech, so it must not override an explicit isSpeaking=true value.
	local Speaking = ActivityInfo.isSpeaking
	if Speaking == nil then Speaking = ActivityInfo.IsSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.is_speaking end
	if Speaking == nil then Speaking = ActivityInfo.speaking end
	if Speaking == nil then Speaking = ActivityInfo.Speaking end
	if Speaking == nil then Speaking = ActivityInfo.isTalking end
	if Speaking == nil then Speaking = ActivityInfo.IsTalking end
	if Speaking == nil then Speaking = ActivityInfo.talking end
	if Speaking == nil then Speaking = ActivityInfo.isSpeakingNow end
	if Speaking == nil then Speaking = ActivityInfo.SpeakingNow end
	-- Do not treat a live microphone/connection as speech. Generic active flags
	-- were the source of false VC icons for players who were not talking.
	if Speaking == nil then Speaking = ActivityInfo.isUserSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.IsUserSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.is_voice_speaking end
	if Speaking == nil then Speaking = ActivityInfo.isVoiceSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.voiceSpeaking end
	if Speaking == nil then Speaking = ActivityInfo.voice_speaking end
	if Speaking == nil then Speaking = ActivityInfo.speechActive end
	if Speaking == nil then Speaking = ActivityInfo.isSpeechActive end

	-- Some legacy CoreScript builds send only an `active` / `isActive` bit in the
	-- mic-activity event. It is ambiguous for unknown users, so accept it as speech
	-- state only after this exact player has already been confirmed to have voice.
	-- This keeps out-of-range speech updates working without turning every participant
	-- in a connection-state collection into a voice-chat user.
    if Speaking == nil and (AllowLegacyActiveState == true or VoiceEnabledCache[UserId] == true) then
        local GenericActive = ActivityInfo.isActive
        if GenericActive == nil then GenericActive = ActivityInfo.IsActive end
        if GenericActive == nil then GenericActive = ActivityInfo.isMicActive end
        if GenericActive == nil then GenericActive = ActivityInfo.IsMicActive end
        if GenericActive == nil then GenericActive = ActivityInfo.isVoiceActive end
        if GenericActive == nil then GenericActive = ActivityInfo.IsVoiceActive end
        if GenericActive == nil then GenericActive = ActivityInfo.active end
        if GenericActive == nil then GenericActive = ActivityInfo.Active end
        if type(GenericActive) == "boolean" then Speaking = GenericActive end
	end
	if type(Speaking) == "string" then
		local StateText = string.lower(Speaking)
		if StateText:find("speaking", 1, true) or StateText:find("talking", 1, true) then
			Speaking = true
		elseif StateText == "silent" or StateText == "idle" or StateText == "not_speaking"
			or StateText == "not speaking" or StateText == "stopped" then
			Speaking = false
		else
			Speaking = nil
		end
	end

	-- Read an actual numeric peak before treating a possibly stale inactive
	-- field as authoritative; the older implementation did this in that order.
	local Peak = nil
	local PeakField = ""
	for _, Key in ipairs({
		-- Prefer explicit dBFS readings over generic zero-valued placeholder fields.
		"dBFS", "dbfs", "decibels", "Decibels", "dB", "Db", "db",
		"peakLevel", "PeakLevel", "peak", "Peak", "level", "Level",
		"loudness", "Loudness", "volume", "Volume", "micLevel", "MicLevel",
		"peak_level", "micPeak", "MicPeak", "voiceLevel", "VoiceLevel",
		"rmsLevel", "RmsLevel", "rms", "Rms", "activityLevel", "ActivityLevel",
		"audioLevel", "AudioLevel", "amplitude", "Amplitude"
	}) do
		local Value = tonumber(ActivityInfo[Key])
		if Value ~= nil then Peak = Value; PeakField = string.lower(Key); break end
	end

	if Speaking == true or Speaking == false then
		VoiceActivitySpeakingState[UserId] = Speaking
		VoiceActivitySpeakingStateStamp[UserId] = os.clock()
	end

	if Peak ~= nil then
		-- Linear values are 0..1; percentage values can be 0..100. Explicit dBFS
		-- fields must be <= 0: positive values are invalid, not a 20% peak.
		local IsDecibelField = PeakField:find("db", 1, true) or PeakField:find("decibel", 1, true)
		if IsDecibelField then
			if Peak >= 0 then Peak = 0 else Peak = 10 ^ (Peak / 20) end
		elseif Peak < 0 then
			Peak = 0
		elseif Peak > 1 and Peak <= 100 then
			Peak = Peak / 100
		end
		Peak = Clamp(Peak, 0, 1)
		if Peak > 0.00001 then
			MarkVoiceActivityEvidence()
			VoiceActivityPeak[UserId] = Peak
			VoiceActivityStamp[UserId] = os.clock()
			VoiceActivityActive[UserId] = true
			VoiceActivityPeakMeasured[UserId] = true
			return
		else
			if Speaking == true then
				-- Some event variants pair speaking=true with a default numeric zero; retain the state without inventing a measured peak.
				MarkVoiceActivityEvidence()
				VoiceActivityPeak[UserId] = 0
				VoiceActivityStamp[UserId] = os.clock()
				VoiceActivityActive[UserId] = true
				VoiceActivityPeakMeasured[UserId] = false
			else
				VoiceActivityPeak[UserId] = 0
				VoiceActivityStamp[UserId] = 0
				VoiceActivityActive[UserId] = false
				VoiceActivityPeakMeasured[UserId] = true
			end
			return
		end
	end

	if Speaking == true then
		MarkVoiceActivityEvidence()
		-- The event confirms speech-state change but contains no numeric level.
		-- Keep activity metadata only; never invent a fake microphone peak.
		VoiceActivityPeak[UserId] = 0
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

-- Legacy participant events can identify clients that have actually joined the
-- voice session. Do not use GetParticipants() snapshots as eligibility proof: some
-- client builds include non-voice/group entries there. Use the explicit
-- ParticipantsStateChanged `participantsJoined` payload instead.
VoiceExtractJoinedUserId = function(Value, Depth)
	Depth = Depth or 0
	if Depth > 4 or Value == nil then return nil end
	local Kind = typeof(Value)
	if Kind == "Instance" then
		local Id = nil
		pcall(function()
			if Value:IsA("Player") then Id = tonumber(Value.UserId) end
		end)
		return Id and Id > 1 and Id or nil
	end
	if type(Value) == "number" then return Value > 1 and Value or nil end
	if type(Value) == "string" then
		local Id = tonumber(Value)
		return Id and Id > 1 and Id or nil
	end
	if type(Value) ~= "table" then return nil end
	for _, Field in ipairs({"UserId", "userId", "PlayerUserId", "playerUserId", "participantUserId", "ParticipantUserId", "speakerUserId", "SpeakerUserId", "user_id", "UserID", "userID", "id", "Id"}) do
        local Id = tonumber(Value[Field])
		if Id and Id > 1 then return Id end
	end
	for _, Field in ipairs({"Player", "player", "Participant", "participant", "User", "user"}) do
		local Nested = Value[Field]
		if Nested ~= Value then
			local Id = VoiceExtractJoinedUserId(Nested, Depth + 1)
			if Id then return Id end
		end
	end
	return nil
end

VoiceMarkJoinedParticipant = function(Value, Key)
	-- This callback receives the explicit ParticipantsStateChanged participantsJoined
	-- payload, not the broad GetParticipants snapshot. A player joining this local
	-- voice session is a stronger compatibility signal than global AudioDeviceInput
	-- existence or account-wide voice eligibility.
	local UserId = VoiceExtractJoinedUserId(Value) or VoiceExtractJoinedUserId(Key)
	if not UserId and type(Key) == "string" then
		local NamedPlayer = Players:FindFirstChild(Key)
		if NamedPlayer and NamedPlayer:IsA("Player") then UserId = tonumber(NamedPlayer.UserId) end
	end
	if not UserId or UserId <= 1 or UserId == LocalPlayer.UserId then return false end
	local Player = nil
	pcall(function() Player = Players:GetPlayerByUserId(UserId) end)
	if not Player or Player == LocalPlayer then return false end
	local WasCompatible = VoiceCompatibleCache[UserId] == true
	VoiceCompatibleCache[UserId] = true
	VoiceEnabledCache[UserId] = true
	VoiceCheckError[UserId] = nil
	return not WasCompatible
end

VoiceConsumeJoinedParticipants = function(Collection)
	if type(Collection) ~= "table" then return false end
	local Changed = false
	for Key, Value in pairs(Collection) do
		if VoiceMarkJoinedParticipant(Value, Key) then Changed = true end
	end
	return Changed
end

VoiceConsumeLeftParticipants = function(Collection)
	if type(Collection) ~= "table" then return false end
	local Changed = false
	for Key, Value in pairs(Collection) do
		local UserId = VoiceExtractJoinedUserId(Value) or VoiceExtractJoinedUserId(Key)
		if not UserId and type(Key) == "string" then
			local NamedPlayer = Players:FindFirstChild(Key)
			if NamedPlayer and NamedPlayer:IsA("Player") then UserId = tonumber(NamedPlayer.UserId) end
		end
		if UserId and UserId > 1 and VoiceCompatibleCache[UserId] == true then
			VoiceCompatibleCache[UserId] = nil
			Changed = true
		end
	end
	return Changed
end

VoiceExtractParticipantUserId = function(Value, Depth)
	Depth = Depth or 0
	if Depth > 4 or Value == nil then return nil end
	local ValueType = typeof(Value)
	if ValueType == "Instance" then
		local IsPlayer = false
		local Id = nil
		pcall(function()
			IsPlayer = Value:IsA("Player")
			Id = tonumber(Value.UserId or Value.userId or Value.PlayerUserId or Value.playerUserId)
		end)
		if IsPlayer and Id and Id > 1 then return Id end
		if Id and Id > 1 then return Id end
		return nil
	end
	if type(Value) == "number" then
		return Value > 1 and Value or nil
	end
	if type(Value) == "string" then
		local Id = tonumber(Value)
		return Id and Id > 1 and Id or nil
	end
	if type(Value) ~= "table" then return nil end

	for _, Key in ipairs({
		"UserId", "userId", "PlayerUserId", "playerUserId", "participantUserId",
		"ParticipantUserId", "speakerUserId", "SpeakerUserId", "user_id",
		"player_user_id", "UserID", "userID", "participantId", "ParticipantId"
	}) do
		local Id = tonumber(Value[Key])
		if Id and Id > 1 then return Id end
	end
	for _, Key in ipairs({"Player", "player", "Participant", "participant", "User", "user", "participantInfo", "ParticipantInfo"}) do
		local Nested = Value[Key]
		if Nested ~= Value then
			local Id = VoiceExtractParticipantUserId(Nested, Depth + 1)
			if Id then return Id end
		end
	end
	return nil
end

-- A participant ID alone is NOT proof that the account has voice chat enabled.
-- Only an explicit positive voice field can promote the eligibility cache.
VoiceMarkParticipantEvidence = function(Value, Key)
	local Record = type(Value) == "table" and Value or nil
	if not Record then return false end
	local ExplicitVoiceFields = {
		"voiceEnabled", "VoiceEnabled", "isVoiceEnabled", "IsVoiceEnabled",
		"hasVoice", "HasVoice", "hasVoiceChat", "HasVoiceChat",
		"voiceChatEnabled", "VoiceChatEnabled", "isVoiceChatEnabled", "IsVoiceChatEnabled",
		"voiceEligible", "VoiceEligible", "isVoiceEligible", "IsVoiceEligible",
	}
	local ExplicitTrue = false
	for _, Field in ipairs(ExplicitVoiceFields) do
		if Record[Field] == true then ExplicitTrue = true; break end
	end
	if not ExplicitTrue then return false end
	local UserId = VoiceExtractParticipantUserId(Record) or VoiceExtractParticipantUserId(Key)
	if not UserId and type(Key) == "string" then
		local NamedPlayer = Players:FindFirstChild(Key)
		if NamedPlayer and NamedPlayer:IsA("Player") then UserId = tonumber(NamedPlayer.UserId) end
	end
	if not UserId then
		local NumericKey = tonumber(Key)
		if NumericKey and NumericKey > 1000 then UserId = NumericKey end
	end
	if not UserId or UserId <= 1 or UserId == LocalPlayer.UserId then return false end
	local Player = nil
	pcall(function() Player = Players:GetPlayerByUserId(UserId) end)
	if not Player then return false end
	local WasKnown = VoiceEnabledCache[UserId] == true
	VoiceEnabledCache[UserId] = true
	VoiceCheckError[UserId] = nil
	return not WasKnown
end

-- Decode the legacy participant snapshot, keyed by UserId/Player or returned as participant records.
-- Speech state is intentionally handled only by VoiceProcessActivityInfo.
VoiceConsumeParticipantCollection = function(Collection, Depth)
	if type(Collection) ~= "table" then return false end
	Depth = Depth or 0
	if Depth > 4 then return false end
	local Changed = false
	local DirectUserId = VoiceExtractParticipantUserId(Collection)
	if DirectUserId then
		if VoiceMarkParticipantEvidence(Collection) then Changed = true end
		return Changed
	end
	for Key, Value in next, Collection do
		local UserId = VoiceExtractParticipantUserId(Value) or VoiceExtractParticipantUserId(Key)
		if not UserId and type(Key) == "string" then
			local NamedPlayer = Players:FindFirstChild(Key)
			if NamedPlayer and NamedPlayer:IsA("Player") then UserId = tonumber(NamedPlayer.UserId) end
		end
		if UserId and UserId > 1 and UserId ~= LocalPlayer.UserId then
			if VoiceMarkParticipantEvidence(Value, Key) then Changed = true end
			-- GetParticipants() is a participant snapshot, not a speech-level feed.
			-- Do not interpret its booleans or generic fields as mic activity.
		elseif type(Value) == "table" and Depth < 4 then
			if VoiceConsumeParticipantCollection(Value, Depth + 1) then Changed = true end
		end
	end
	return Changed
end

RefreshVoiceParticipants = function()
	-- Keep participant discovery active when the local client is disconnected.
	if not VoiceGameSupported then return false end
	local PlayerList = Players:GetPlayers()
	local Changed = false

	-- Modern Audio API: use Player-owned AudioDeviceInput instances.
	-- Legacy/Automatic mode: the internal participant list is the remaining
	-- client-side signal for players actually present in the voice session.
	-- This does not inspect voice bubbles, chat bubbles, or their sprite frames.

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

	-- On legacy/Automatic mode, recover remote participant identity from the
	-- same participant snapshot used by the earlier working version. This path only
	-- marks eligibility for IDs that resolve to a Player currently in this server;
	-- snapshot fields are never sent to the speech-meter parser.
	if VoiceChatInternal and GetVoiceAudioApiEnabled() ~= true then
		Protect(function()
			local Participants = VoiceChatInternal:GetParticipants()
			if type(Participants) == "table" then
				if VoiceConsumeParticipantCollection(Participants) then Changed = true end
			end
		end)
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
		-- This script has already checked both the place's voice support and the
		-- local account's eligibility. Keep that positive result authoritative; the
		-- per-user query may return a stale/false result on legacy clients.
		if VoiceOptionAvailable == true or VoiceAccountAllowed == true then return true end
		local Ok, Enabled = pcall(function()
			return VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId) == true
		end)
		if Ok and Enabled == true then return true end
		-- In supported experiences, legacy clients can report a false/failed public
		-- eligibility query while their internal voice context is already enabled.
		if VoiceChatInternal then
			local InternalOk, InternalEnabled = pcall(function()
				return VoiceChatInternal:IsContextVoiceEnabled() == true
			end)
			if InternalOk and InternalEnabled == true then return true end
		end
		if Ok then return Enabled end
		return nil
	end

	-- The client can confirm remote eligibility through a genuine Player-owned input
	-- when the modern Audio API is enabled; it is independent of UI visibility.
	if VoiceEnabledCache[UserId] == true then return true end
	if GetVoiceMeterInput(Player) then
		VoiceEnabledCache[UserId] = true
		return true
	end
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

GetLocalVoiceMuted = function()
	local AudioApiEnabled = GetVoiceAudioApiEnabled()
	local Input = nil
	if AudioApiEnabled ~= false then
		pcall(function() Input = GetAudioDeviceInput(LocalPlayer) end)
	end
	-- The meter lookup can still find a genuine local input if the rollout flag
	-- itself is unreadable. Only a real AudioDeviceInput owned by LocalPlayer is used.
	if not Input then
		pcall(function() Input = GetVoiceMeterInput(LocalPlayer) end)
	end

	local IsRealLocalInput = false
	if Input then
		pcall(function()
			IsRealLocalInput = Input:IsA("AudioDeviceInput")
				and Input.Player == LocalPlayer
				and Input.Name ~= "Settings2016LocalAudioDeviceInput"
		end)
	end
	if IsRealLocalInput then
		-- Roblox's real Core UI microphone toggle changes AudioDeviceInput.Active;
		-- the separate Muted property is scriptable and does not by itself reflect
		-- the user's microphone toggle. Active=false therefore takes priority.
		local Active, ActiveOk = ReadVoiceInputProperty(Input, "Active")
		local Muted, MutedOk = ReadVoiceInputProperty(Input, "Muted")
		if ActiveOk and type(Active) == "boolean" and Active == false then
			return true
		end
		if MutedOk and type(Muted) == "boolean" and Muted == true then
			return true
		end
		if ActiveOk and type(Active) == "boolean" and Active == true then
			if MutedOk and type(Muted) == "boolean" then return Muted end
			return false
		end
		if MutedOk and type(Muted) == "boolean" then return Muted end
	end

	-- Legacy / Automatic pipeline: use the native publisher's actual pause state.
	-- Do not let an old CoreGui image saying "Unmuted" override it.
	if AudioApiEnabled ~= true and VoiceChatInternal then
		local Ok, Muted = pcall(function()
			return VoiceChatInternal:IsPublishPaused()
		end)
		if Ok and type(Muted) == "boolean" then return Muted end
	end

	-- Fallback: read the actual local self-mute icon in Roblox's ESC Settings page.
	-- This is only a local mute-state fallback, never remote speaking detection.
	local Native = nil
	pcall(function() Native = FindNativeVoiceIcon(LocalPlayer) end)
	if type(Native) == "string" and Native ~= "" then
		local SaysUnmuted = Native:find("Unmuted", 1, true) ~= nil
		local SaysMuted = Native:find("Muted", 1, true) ~= nil and not SaysUnmuted
		if SaysMuted then return true end
		if SaysUnmuted then return false end
	end

	-- If the menu has closed, tolerate only a very recent observed native state.
	local UserId = tonumber(LocalPlayer and LocalPlayer.UserId) or 0
	local CachedImage = NativeVoiceIconLastImages[UserId]
	local SeenAt = tonumber(NativeVoiceIconLastSeenAt[UserId]) or 0
	if SeenAt > 0 and (os.clock() - SeenAt) <= 0.75 then
		local SaysUnmuted = type(CachedImage) == "string" and CachedImage:find("Unmuted", 1, true) ~= nil
		local SaysMuted = type(CachedImage) == "string" and CachedImage:find("Muted", 1, true) ~= nil and not SaysUnmuted
		if SaysMuted then return true end
		if SaysUnmuted then return false end
	end

	return nil
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
	local AudioApiEnabled = GetVoiceAudioApiEnabled()
	local Input = AudioApiEnabled ~= false and GetAudioDeviceInput(LocalPlayer) or nil

	-- Audio API path: set and verify the real input. The legacy publisher may
	-- still expose stale values, so it must not veto a verified Audio API write.
	if AudioApiEnabled == true and Input then
		local WriteOk, ReadBack = pcall(function()
			Input.Muted = Muted
			return Input.Muted == true
		end)
		if WriteOk and ReadBack == Muted then
			LocalVoiceMuted = Muted
			return true
		end
	end

	-- Legacy path (UseAudioApi=Automatic/Disabled, or mode unreadable): change the
	-- publisher's pause state and verify it. Never use this path when Audio API is Enabled.
	if AudioApiEnabled ~= true and VoiceChatInternal then
		pcall(function() VoiceChatInternal:PublishPause(Muted) end)
		Wait(0.08)
		local ReadOk, PauseAfter = pcall(function() return VoiceChatInternal:IsPublishPaused() end)
		if ReadOk and type(PauseAfter) == "boolean" and PauseAfter == Muted then
			LocalVoiceMuted = Muted
			return true
		end
	end

	-- If rollout mode is unreadable, try a ready input after the legacy route.
	if AudioApiEnabled == nil and Input then
		local Ready = false
		pcall(function() Ready = Input.IsReady == true or Input.Active == true end)
		if Ready then
			local WriteOk, ReadBack = pcall(function()
				Input.Muted = Muted
				return Input.Muted == true
			end)
			if WriteOk and ReadBack == Muted then
				LocalVoiceMuted = Muted
				return true
			end
		end
	end

	-- Last-resort native control is used only when its menu is already open; don't
	-- synthesize Escape cycles or silently claim success on a stale icon.
	local MenuReadOk, MenuIsOpen = pcall(function() return GuiService.MenuIsOpen end)
	if MenuReadOk and MenuIsOpen == true then
		local NativeCallOk, NativeApplied = pcall(function() return InvokeNativeMuteSelfButton(Muted) end)
		if NativeCallOk and NativeApplied then
			local VerifyOk, VerifyMuted = pcall(function() return GetLocalVoiceMuted() end)
			if VerifyOk and VerifyMuted == Muted then
				LocalVoiceMuted = Muted
				return true
			end
		end
	end

	LocalVoiceMuted = GetLocalVoiceMuted()
	return false
end

RefreshLocalVoiceState = function()
	local Entitled = false
	local Success = false
	Success = Protect(function()
		Entitled = VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId) == true
		return true
	end)
	-- Fail closed if the official user eligibility request fails. An internal
	-- controller is not proof that this user is permitted to use voice here.
	LocalVoiceEnabled = VoiceChatEnabled and Success and Entitled
	VoiceEnabledCache[LocalPlayer.UserId] = Success and Entitled == true
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
    -- Hard configuration override. This is checked before normal availability
    -- so no button, callback, or auto-connect worker can turn VC back on.
    if VOICE_CHAT_FORCE_OFF then
        VoiceChatDesiredOn = false
        VoiceChatEnabled = false
        LocalVoiceEnabled = false
        VoiceConnectionAttempting = false
        VoiceMuteAllActive = false
        VoiceEnabledCache = {}
        VoiceCompatibleCache = {}
        VoiceMutedPlayers = {}
        if VoiceChatInternal then
            pcall(function() VoiceChatInternal:Leave() end)
        end
        if VoiceChatButton then pcall(function() VoiceChatButton.Visible = false end) end
        if VoiceBetaBadgeRoot then pcall(function() VoiceBetaBadgeRoot.Visible = false end) end
        if VoiceChatSelector then
            pcall(function() VoiceChatSelector:SetSelectionIndex(2, false) end)
        end
        if RebuildPlayersPage then pcall(RebuildPlayersPage) end
        if ConfigureMobileActionButtons then pcall(ConfigureMobileActionButtons) end
        return false
    end

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
		LocalVoiceMuted = GetLocalVoiceMuted()
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
					IsPhone and UDim2.new(1, -16, 0, 62) or UDim2.new(1, 0, 0, 62),

				Position =
					UDim2.new(
						0,
						IsPhone and 8 or 0,
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

	-- Create a per-player control only after player-specific voice evidence exists
	-- (a real audio input or explicit participant/activity event).
	-- Unknown eligibility is not enough to create a button.
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
		-- Visibility is tied to positive player-specific evidence, never merely to
		-- VoiceChatService existing or this place supporting voice.
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

		-- Expose the owning row so final Settings-page pruning retains this dropdown.
		RowFrame =
			Row,

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
	local RowHeight = 62
	local SideBySide = VoiceActive and InviteFriends and not PhoneLayout
	local FullRowSize = UDim2.new(1, 0, 0, RowHeight)
	local HalfRowSize = UDim2.new(0.5, -3, 0, RowHeight)
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
			Image = "rbxassetid://80022950003290",
			Size = UDim2.fromOffset(PhoneLayout and 22 or 26, PhoneLayout and 22 or 26),
			Position = UDim2.new(0, PhoneLayout and 8 or 14, 0.5, PhoneLayout and -10 or -12),
			ScaleType = Enum.ScaleType.Fit, ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})
		Create("TextLabel", {
			Name = "NameLabel", Parent = Row, BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans, TextSize = INVITE_FRIENDS_TEXT_MAX_SIZE,
			TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = "Invite friends to join", TextWrapped = true, TextScaled = true,
			Size = UDim2.new(1, PhoneLayout and -42 or -78, 1, 0),
			Position = UDim2.new(0, PhoneLayout and 36 or 50, 0, PhoneLayout and 2 or 0),
			ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})
		Create("UITextSizeConstraint", {
			Name = "InviteFriendsTextConstraint",
			Parent = Row:FindFirstChild("NameLabel"),
			MinTextSize = INVITE_FRIENDS_TEXT_MIN_SIZE,
			MaxTextSize = INVITE_FRIENDS_TEXT_MAX_SIZE,
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
			Size = UDim2.fromOffset(PhoneLayout and 22 or 30, PhoneLayout and 22 or 30),
			Position = UDim2.new(0, PhoneLayout and 8 or 14, 0.5, PhoneLayout and -11 or -15),
			ScaleType = Enum.ScaleType.Fit, ZIndex = SETTINGS_BASE_ZINDEX + 4,
		})
		local Label = Create("TextLabel", {
			Name = "MuteAllLabel", Parent = MuteRow, BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans, TextSize = 28,
			TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = "Mute All", TextWrapped = true, TextScaled = true,
			Size = UDim2.new(1, PhoneLayout and -44 or -56, 1, 0),
			Position = UDim2.new(0, PhoneLayout and 36 or 52, 0, 0),
			ZIndex = SETTINGS_BASE_ZINDEX + 4,
		})
		Create("UITextSizeConstraint", {Name = "MuteAllTextConstraint", Parent = Label, MinTextSize = 24, MaxTextSize = 28})
		Label.Font = Enum.Font.SourceSans
		Label.TextSize = 28
		Label.TextScaled = true
		Label.TextWrapped = true
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
	local RowHeight = 62
	local RowGap = 6
	local Cursor = StartY or 72
	local HasBothActions = InviteRow ~= nil and MuteRow ~= nil
	local HalfWidth = UDim2.new(0.5, -3, 0, RowHeight)

	if HasBothActions then
		-- Full-width stacked action rows leave enough room for the exact 24px
		-- bottom-button typography used by both labels.
		InviteRow.Size = UDim2.new(1, 0, 0, RowHeight)
		InviteRow.Position = UDim2.new(0, 0, 0, Cursor)
		MuteRow.Size = UDim2.new(1, 0, 0, RowHeight)
		MuteRow.Position = UDim2.new(0, 0, 0, Cursor + RowHeight + RowGap)
		Cursor = Cursor + (RowHeight * 2) + RowGap + 10
	else
		local OnlyRow = InviteRow or MuteRow
		if OnlyRow then
			OnlyRow.Size = UDim2.new(1, 0, 0, RowHeight)
			OnlyRow.Position = UDim2.new(0, 0, 0, Cursor)
			Cursor = Cursor + RowHeight + 10
		end
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

			if IsPhone then
				Row.Size = UDim2.new(1, -16, 0, 62)
			end
			Row.Position =
				UDim2.new(
					0,
					IsPhone and 8 or 0,
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
NewInviteShareRow = nil
ShareInviteButton = nil

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
		USE_NEW_INVITE_MENU and UDim2.new(0, 150, 0, 56) or UDim2.new(0, 132, 0, 56),
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
			if NewInviteShareRow then NewInviteShareRow.Visible = false end

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
			USE_NEW_INVITE_MENU and Enum.Font.SourceSans or Enum.Font.SourceSansBold,

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

SearchFrame.Visible = true

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

	SearchFrame.Visible = true

	if not IsMobile then
		InviteBackLabel.Text = "Back"
		InviteBackLabel.TextSize = 24
		InviteBackLabel.TextXAlignment = Enum.TextXAlignment.Center
		InviteBackLabel.TextYAlignment = Enum.TextYAlignment.Center
		SearchFrame.Size = UDim2.new(0, 220, 0, 34)
		SearchFrame.Position = UDim2.new(1, -228, 0, 15)
		SearchFrame.BackgroundTransparency = 1
		SearchFrame.BorderSizePixel = 0
		local SearchStroke = SearchFrame:FindFirstChildOfClass("UIStroke")
		if SearchStroke then SearchStroke.Transparency = 0 end
		SearchBox.Visible = true
		SearchPlaceholder.Visible = SearchBox.Text == ""
		SearchIcon.Visible = SearchBox.Text == "" or SearchBox:IsFocused()
		return
	end

	InviteBackLabel.Text = "<"
	InviteBackLabel.TextSize = 30
	InviteBackLabel.TextXAlignment = Enum.TextXAlignment.Center
	InviteBackLabel.TextYAlignment = Enum.TextYAlignment.Center
	InviteBackButton.Size = UDim2.fromOffset(USE_NEW_INVITE_MENU and 52 or 44, 48)
	InviteBackButton.Position = UDim2.fromOffset(4, 4)
	InviteBackButton.BackgroundTransparency = 1
	InviteBackButton.BackgroundColor3 = Color3.new(0, 0, 0)
	InviteBackButton.BorderSizePixel = 0
	InviteBackButton.Image = ""
	InviteBackButton.ImageTransparency = 1
	InviteBackButton.AutoButtonColor = false
	InviteBackLabel.BackgroundTransparency = 1

	local Expanded = INVITE_MOBILE_SEARCH_EXPANDED
	local Width = Expanded and INVITE_MOBILE_SEARCH_WIDTH or INVITE_MOBILE_SEARCH_COLLAPSED
	SearchFrame.Size = UDim2.fromOffset(Width, 36)
	SearchFrame.Position = UDim2.new(1, -(Width + 6), 0, 10)
	SearchFrame.BackgroundTransparency = 1
	SearchFrame.BorderSizePixel = 0
	local SearchStroke = SearchFrame:FindFirstChildOfClass("UIStroke")
	if SearchStroke then SearchStroke.Transparency = Expanded and 0 or 1 end
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

-- Invite-row selection visuals and focus navigation are intentionally disabled.
-- Rows remain clickable only through their actual Invite buttons, and the share
-- row is a normal scrolling-list item rather than a selectable overlay.
InviteSelectionButtons = {}
InviteSelectionFriends = {}
InviteSelectionInviteButtons = {}
InviteSelectionInviteLabels = {}
InviteSelectionImages = {}
InviteSelectedIndex = 0
InviteSelectedFriendId = nil

SetInviteGuiSelection = function(Button)
	local Selected = GuiService.SelectedObject
	if Selected and InvitePage and InvitePage.Frame and Selected:IsDescendantOf(InvitePage.Frame) then
		Protect(function() GuiService.SelectedObject = nil end)
	end
end

UpdateInviteSelectionVisual = function()
	for _, Image in ipairs(InviteSelectionImages) do
		if Image then Image.Visible = false end
	end
end

HideInviteSelection = function()
	UpdateInviteSelectionVisual()
	SetInviteGuiSelection()
	local SelectedCore = GuiService.SelectedCoreObject
	if SelectedCore and InvitePage and InvitePage.Frame then
		local IsInviteDescendant = false
		pcall(function() IsInviteDescendant = SelectedCore:IsDescendantOf(InvitePage.Frame) end)
		if IsInviteDescendant then Protect(function() GuiService.SelectedCoreObject = nil end) end
	end
	InviteSelectedIndex = 0
	InviteSelectedFriendId = nil
end

KeepInviteSelectionVisible = function() end

SetInviteSelection = function(Index, PreserveScroll)
	if #InviteSelectionButtons == 0 then
		InviteSelectedIndex = 0
		InviteSelectedFriendId = nil
		return
	end
	Index = math.clamp(tonumber(Index) or 1, 1, #InviteSelectionButtons)
	local Friend = InviteSelectionFriends[Index]
	InviteSelectedIndex = Index
	InviteSelectedFriendId = Friend and tostring(Friend.Id) or nil
	UpdateInviteSelectionVisual()
	SetInviteGuiSelection()
end

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

-- New Invite Friends layout only. The old invite page remains in the source
-- and is selected unchanged when all three fast flags are explicitly False.
NewInviteShareRow = Create("ImageLabel", {
	Name = "NewInviteShareRow",
	Parent = InviteList,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Image = TAB_BAR_IMAGE,
	ImageTransparency = 0,
	ImageColor3 = Color3.new(1, 1, 1),
	ScaleType = Enum.ScaleType.Slice,
	SliceCenter = Rect.new(4, 4, 6, 6),
	Size = UDim2.new(1, 0, 0, INVITE_SHARE_ROW_HEIGHT),
	Position = UDim2.new(0, 0, 0, 0),
	Visible = false,
	ZIndex = SETTINGS_BASE_ZINDEX + 10,
})

Create("TextLabel", {
	Name = "ShareInviteLinkLabel",
	Parent = NewInviteShareRow,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Font = Enum.Font.SourceSans,
	TextSize = 28,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Share Invite Link",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Size = UDim2.new(1, -108, 1, 0),
	Position = UDim2.new(0, 10, 0, 0),
	ZIndex = SETTINGS_BASE_ZINDEX + 11,
})

ShareInviteButton = Create("TextButton", {
	Name = "ShareInviteButton",
	Parent = NewInviteShareRow,
	BackgroundColor3 = Color3.fromRGB(248, 248, 248),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	AutoButtonColor = true,
	Active = true,
	Selectable = false,
	Font = Enum.Font.SourceSans,
	TextSize = 19,
	TextColor3 = Color3.fromRGB(32, 34, 38),
	Text = "Share",
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Size = UDim2.fromOffset(86, 32),
	Position = UDim2.new(1, -94, 0.5, -16),
	ZIndex = SETTINGS_BASE_ZINDEX + 12,
})
Create("UICorner", {Parent = ShareInviteButton, CornerRadius = UDim.new(0, 3)})

-- Use NotificationScript2's own BindableEvent when it exists. This enters the
-- CoreScript notification queue directly, rather than creating another toast UI.
local CoreNotificationLayerGeneration = 0
local CoreNotificationOriginalDisplayOrders = {}
local function NotifyInviteShare(Title, Message)
	-- These labels are rendered by Roblox's native notification UI, outside our ScreenGui.
	Title = GetMenuLocalizedText(tostring(Title), MenuLocalizationLocale)
	Message = GetMenuLocalizedText(tostring(Message), MenuLocalizationLocale)
	local CoreSent, UsedCoreEvent = pcall(function()
		local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
		local Event = RobloxGui and RobloxGui:FindFirstChild("SendNotificationInfo")
		if not Event or not Event:IsA("BindableEvent") then return false end
		Event:Fire({
			GroupName = "Developer",
			Title = tostring(Title),
			Text = tostring(Message),
			DetailText = tostring(Message),
			Image = "",
			Duration = 5,
		})
		CoreNotificationLayerGeneration += 1
		local ThisGeneration = CoreNotificationLayerGeneration
		local MinimumOrder = (ScreenGui and ScreenGui.DisplayOrder or 9000) + 100
		local function RaiseNotificationLayer()
			for _, Object in ipairs(CoreGui:GetDescendants()) do
				if Object.Name == "NotificationFrame" and Object:IsA("GuiObject") then
					local Ancestor = Object.Parent
					while Ancestor and Ancestor ~= CoreGui do
						if Ancestor:IsA("ScreenGui") then
							pcall(function()
								if Ancestor.DisplayOrder < MinimumOrder then
									if CoreNotificationOriginalDisplayOrders[Ancestor] == nil then
										CoreNotificationOriginalDisplayOrders[Ancestor] = Ancestor.DisplayOrder
									end
									Ancestor.DisplayOrder = MinimumOrder
								end
							end)
							break
						end
						Ancestor = Ancestor.Parent
					end
				end
			end
		end
		pcall(RaiseNotificationLayer)
		task.spawn(function()
			for _ = 1, 5 do
				task.wait(0.04)
				pcall(RaiseNotificationLayer)
			end
			-- NotificationScript2 uses a five-second lifetime plus its tween-out.
			-- Restore CoreGui's original layer order once this toast has cleared.
			task.wait(5.8)
			if ThisGeneration ~= CoreNotificationLayerGeneration then return end
			for Gui, OriginalOrder in pairs(CoreNotificationOriginalDisplayOrders) do
				if Gui and Gui.Parent and Gui:IsA("ScreenGui") then
					pcall(function()
						if Gui.DisplayOrder >= MinimumOrder then Gui.DisplayOrder = OriginalOrder end
					end)
				end
				CoreNotificationOriginalDisplayOrders[Gui] = nil
			end
		end)
		return true
	end)
	if CoreSent and UsedCoreEvent then return end

	-- Compatibility fallback for clients that do not expose NotificationScript2's event.
	local SetCoreSent = pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = tostring(Title),
			Text = tostring(Message),
			Duration = 5,
		})
	end)
	if not SetCoreSent then
		warn("[Settings2016 Invite] " .. tostring(Title) .. ": " .. tostring(Message))
	end
end

local function ShareInviteLink()
	local Link = "https://www.roblox.com/games/" .. tostring(game.PlaceId)
	if type(game.JobId) == "string" and game.JobId ~= "" then
		Link = Link .. "?gameInstanceId=" .. game.JobId
	end

	-- Prefer a direct clipboard copy so sharing does not replace the custom menu
	-- with Roblox's separate link-sharing prompt.
	local Clipboard = nil
	pcall(function() Clipboard = setclipboard end)
	if type(Clipboard) ~= "function" then pcall(function() Clipboard = toclipboard end) end
	if type(Clipboard) ~= "function" then
		pcall(function()
			local Env = getgenv and getgenv() or nil
			Clipboard = Env and (Env.setclipboard or Env.toclipboard) or nil
		end)
	end
	if type(Clipboard) == "function" then
		local Copied = pcall(function() Clipboard(Link) end)
		if Copied then
			NotifyInviteShare("Invite link copied", "The experience link was copied to your clipboard.")
			return
		end
	end

	-- If clipboard functions are unavailable, use Roblox's supported sharing API.
	local Options = {
		ExpirationSeconds = 20000,
		PreviewTitle = tostring(game.Name or "Roblox experience"),
		PreviewDescription = GetMenuLocalizedText("Join me in this experience", MenuLocalizationLocale),
	}
	local ApiOk, ApiResult = pcall(function()
		return SocialService:PromptLinkSharingAsync(LocalPlayer, Options)
	end)
	local ResultIsSuccess = false
	if ApiOk then
		pcall(function() ResultIsSuccess = ApiResult == Enum.PromptLinkSharingResult.Success end)
	end
	if ResultIsSuccess then
		NotifyInviteShare("Share invite link", "Roblox opened the link-sharing prompt.")
	else
		NotifyInviteShare("Invite link", "Clipboard access is unavailable on this client.")
		warn("[Settings2016 Invite] Invite link: " .. Link)
	end
end

Connect(ShareInviteButton.Activated, ShareInviteLink)

NewInviteShareRow.Visible = false

INVITE_MOBILE_HEADER_DIVIDER = Create("Frame", {
	Name = "InviteHeaderDivider",
	Parent = InvitePage.Frame,
	BackgroundColor3 = Color3.fromRGB(120, 120, 120),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -20, 0, 1),
	Position = UDim2.new(0, 10, 0, 62),
	Visible = false,
	ZIndex = SETTINGS_BASE_ZINDEX + 14,
})

Connect(InviteList:GetPropertyChangedSignal("CanvasPosition"), function()
	if INVITE_MOBILE_HEADER_DIVIDER and InviteList.Parent then
		INVITE_MOBILE_HEADER_DIVIDER.Visible = not USE_NEW_INVITE_MENU and InviteList.Visible and InviteList.CanvasPosition.Y <= 0
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

-- Restore the older, muted presence colors used by the original invite list.
-- Online is green, In Studio is orange, Offline is gray. In Experience uses
-- a white filled-circle texture with a genuinely transparent play cutout.
ONLINE_COLOR = Color3.fromRGB(2, 183, 90)
IN_EXPERIENCE_COLOR = Color3.new(1, 1, 1)
IN_STUDIO_COLOR = Color3.fromRGB(246, 136, 2)
OFFLINE_COLOR = Color3.fromRGB(128, 128, 128)

-- Generate a tiny transparent PNG locally so the play triangle is alpha=0,
-- not a black/colored glyph over a hollow ring. This script already targets
-- executor environments (getgenv); use their custom-asset API when available.
IN_EXPERIENCE_CUTOUT_IMAGE = ""
do
	local Encoded = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAACeklEQVR42s2XMW/UQBCFP9t3VEFEIqSkBESVCkQTURBBSREh6KG830D4BSkjQQo6EL8AiQYKhJQqNCiglEkDAoKgytl+NG/Jyrmzby9AMtLqfOvdebNvd55nM0l0WAYUQNnonwVyP9fAXuN9D6iAVoCsI4DCTgBOA9fdFoDLBsHBfQA2gdduP0f4OGySxrXCv/OSViTtaHLb8Zz5hq9DbVRnJin38x1Ju5HjStJQUimpbrTS76po/K59YJ9ZVwAx+GrkaGiQSa32nGCr44Jogvf8/NgTy8aKUq2yD9knxshGBVA0Vr7f4jTV9htMFM0AQsdyNKHuoDh1S0IQyzFmoD6TNCfpswdXLavfiP6XidtRG2Mu4ObOUwED4JxzNh+RsbX7B8Bt4HskUJ1q5rmVMQaeUwQGZqLV1x17f8MUXpT0MvFs1BELM4EBAYuOTJbeNqu88o/ALeCRWchbFe9A1mWsRUCB6qWI5kmsAvoGXbE8f4pkt21L6hgzd1QLUYSTWu3WA94CV4B1B5G1sBEwFoAs91ftUnRQUq006A/gAXAP+BYd7lGHEWPOBgb6HM0q+8mB58BV4IUZGrcd/cDA37L4AG8D793XmqI9DxgeETyLsuAC8BS41pFVw5AFe8BWYhY0ixYZ/D6wYfByDHjA2AL2gg5sRjSmrDqUXWeBZ8AT4Iz7ei1bhTH/6MCrxCwIgZfATeAdcDfSgKJj7gHmFFK8ZCk+Jelho2iZSooL4Bew1iEgwb4C54E3VsFYkCZN1zVjFimf49C/LulLwqpbP8fTFiSplVFrQZJakpWJ1dBEJdmJKEqPvSw/EReT/341O/bLaVcA//x6/ht4q8aJ2TkUBwAAAABJRU5ErkJggg=="
	local function DecodeBase64(Data)
		local Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local Lookup = {}
		for I = 1, #Alphabet do Lookup[Alphabet:sub(I, I)] = I - 1 end
		local Out, Buffer, Bits = {}, 0, 0
		for I = 1, #Data do
			local C = Data:sub(I, I)
			if C ~= "=" then
				local V = Lookup[C]
				if V then
					Buffer = Buffer * 64 + V
					Bits = Bits + 6
					if Bits >= 8 then
						Bits = Bits - 8
						Out[#Out + 1] = string.char(math.floor(Buffer / (2 ^ Bits)) % 256)
						Buffer = Buffer % (2 ^ Bits)
					end
				end
			end
		end
		return table.concat(Out)
	end
	pcall(function()
		local Write = writefile
		local GetAsset = getcustomasset or getsynasset
		if type(GetAsset) ~= "function" then
			pcall(function()
				if syn and type(syn.getcustomasset) == "function" then GetAsset = syn.getcustomasset end
			end)
		end
		if type(Write) ~= "function" or type(GetAsset) ~= "function" then return end
		local Path = "Settings2016_InExperiencePlayCutout.png"
		Write(Path, DecodeBase64(Encoded))
		IN_EXPERIENCE_CUTOUT_IMAGE = GetAsset(Path)
	end)
end

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

StyleNewInviteAction = function(Button, Label, Disabled)
	if not Button or not Label then return end

	-- Player-row Invite uses the same original HubBar MenuButton asset and
	-- SourceSansBold label as the older invite menu. The play cutout belongs
	-- exclusively to the In Experience presence marker, not this action button.
	local OldCorner = Button:FindFirstChildOfClass("UICorner")
	if OldCorner then OldCorner:Destroy() end
	Button.BorderSizePixel = 0
	Button.BackgroundColor3 = Color3.new(1, 1, 1)
	Button.BackgroundTransparency = 1
	Button.Selectable = false
	Button.ZIndex = SETTINGS_BASE_ZINDEX + 6
	Label.BackgroundTransparency = 1
	Label.TextTransparency = 0
	Label.TextWrapped = false
	Label.TextScaled = false
	Label.TextXAlignment = Enum.TextXAlignment.Center
	Label.TextYAlignment = Enum.TextYAlignment.Center
	Label.ZIndex = SETTINGS_BASE_ZINDEX + 7

	if Disabled then
		-- Keep the accepted-invite state as plain text; hide the button art fully.
		Button.Image = BUTTON_IMAGE
		Button.ImageTransparency = 1
		Button.BackgroundTransparency = 1
		Button.AutoButtonColor = false
		Button.Active = false
		Button.Size = UDim2.fromOffset(INVITE_BUTTON_WIDTH, INVITE_BUTTON_HEIGHT)
		Button.Position = UDim2.new(1, -(INVITE_BUTTON_WIDTH + 12), 0.5, -(INVITE_BUTTON_HEIGHT / 2))
		Label.Text = "Invited..."
		Label.Font = Enum.Font.SourceSans
		Label.TextSize = 18
		Label.TextColor3 = INVITED_COLOR
	else
		Button.Image = BUTTON_IMAGE
		Button.ImageTransparency = 0
		Button.BackgroundTransparency = 1
		Button.AutoButtonColor = false
		Button.Active = true
		Button.Size = UDim2.fromOffset(INVITE_BUTTON_WIDTH, INVITE_BUTTON_HEIGHT)
		Button.Position = UDim2.new(1, -(INVITE_BUTTON_WIDTH + 12), 0.5, -(INVITE_BUTTON_HEIGHT / 2))
		Label.Text = "Invite"
		Label.Font = Enum.Font.SourceSansBold
		Label.TextSize = 18
		Label.TextColor3 = Color3.new(1, 1, 1)
	end
	Label.Size = UDim2.new(1, 0, 1, -8)
	Label.Position = UDim2.new(0, 0, 0, 0)
end

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

		-- FFlag-selected legacy invite menu: show the requested failure message and
		-- do not invoke the modern invite prompt or falsely mark the friend invited.
		if not USE_NEW_INVITE_MENU then
			if type(ShowInviteFailureError) == "function" then
				ShowInviteFailureError()
			end
			return
		end

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
			if USE_NEW_INVITE_MENU then
				StyleNewInviteAction(Button, Label, false)
			else
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
			end
			return
		end

		-- Persist the invited target only after the native invite prompt
		-- successfully opened, exactly like the older working build.
		InvitedFriendIds[FriendKey] = true
		InviteState.InvitedFriendIds = InvitedFriendIds
		Friend.Invited = true
		PendingInviteFriendIds[FriendKey] = true

		if USE_NEW_INVITE_MENU then
			StyleNewInviteAction(Button, Label, true)
		else
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
						if USE_NEW_INVITE_MENU then
							StyleNewInviteAction(Button, Label, true)
						else
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
						end
					else
						-- The native prompt was closed without sending the selected
						-- friend. Restore the normal Invite action.
						if USE_NEW_INVITE_MENU then
							StyleNewInviteAction(Button, Label, false)
						else
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
							(USE_NEW_INVITE_MENU and (INVITE_SHARE_ROW_HEIGHT + INVITE_SHARE_ROW_GAP) or PLAYER_LIST_OFFSET)
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

		-- Keep only an inert indexing object for the invite-button arrays. No
		-- SelectionImageObject, selection border, or gamepad focus overlay is used.
		SelectionButton.Active = false
		SelectionButton.Selectable = false
		SelectionButton.SelectionImageObject = nil
		local SelectionIndex = #InviteSelectionButtons + 1
		Insert(InviteSelectionButtons, SelectionButton)
		Insert(InviteSelectionFriends, Friend)

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
					BackgroundColor3 = USE_NEW_INVITE_MENU and Color3.fromRGB(48, 50, 55) or Color3.new(1, 1, 1),
					BackgroundTransparency = 0,
					BorderSizePixel = USE_NEW_INVITE_MENU and 0 or 2,
					BorderColor3 = Color3.fromRGB(205, 205, 205),
					Size = USE_NEW_INVITE_MENU and UDim2.fromOffset(40, 40) or UDim2.new(0, 36, 0, 36),
					Position = USE_NEW_INVITE_MENU and UDim2.new(0, 12, 0.5, -20) or UDim2.new(0, 12, 0.5, -18),
					ZIndex = SETTINGS_BASE_ZINDEX + 2,
				})
		if USE_NEW_INVITE_MENU then
			local AvatarCorner = Instance.new("UICorner")
			AvatarCorner.CornerRadius = UDim.new(1, 0)
			AvatarCorner.Parent = AvatarBackground
		end

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
					Size = USE_NEW_INVITE_MENU and UDim2.fromOffset(36, 36) or UDim2.new(0, 32, 0, 32),
					Position = USE_NEW_INVITE_MENU and UDim2.new(0, 14, 0.5, -18) or UDim2.new(0, 14, 0.5, -16),
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = SETTINGS_BASE_ZINDEX + 3,
				}
			)
		if USE_NEW_INVITE_MENU then
			local AvatarCorner = Instance.new("UICorner")
			AvatarCorner.CornerRadius = UDim.new(1, 0)
			AvatarCorner.Parent = Avatar
		end

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
				TextSize = USE_NEW_INVITE_MENU and 22 or 24,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = DisplayText,
				TextWrapped = false,
				Size = USE_NEW_INVITE_MENU and UDim2.new(1, -184, 0, 26) or UDim2.new(1, -330, 0, 30),
				Position = USE_NEW_INVITE_MENU and UDim2.new(0, 82, 0, 7) or UDim2.new(0, 60, 0, 5),
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
				TextSize = USE_NEW_INVITE_MENU and 22 or 17,
				TextColor3 = Color3.fromRGB(190, 190, 190),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "@" .. (Friend.Username or ""),
				TextWrapped = false,
				Size = USE_NEW_INVITE_MENU and UDim2.new(1, -184, 0, 26) or UDim2.new(1, -330, 0, 22),
				Position = USE_NEW_INVITE_MENU and UDim2.new(0, 60, 0, 29) or UDim2.new(0, 60, 0, 27),
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
				Visible = not USE_NEW_INVITE_MENU,
				Size = UDim2.new(1, -330, 0, 18),
				Position = UDim2.new(0, 60, 0, 40),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			}
		)

		if USE_NEW_INVITE_MENU then
			local IsInExperience = StatusText == "In Experience"
			local PresenceSize = 16 -- identical size for the white cutout circle and colored presence dots
			local PresenceDot
			if IsInExperience and IN_EXPERIENCE_CUTOUT_IMAGE ~= "" then
				-- The PNG itself is a filled white circle. The triangle's alpha is
				-- zero, so the player-row background is genuinely visible through it.
				PresenceDot = Create("ImageLabel", {
					Name = "PresenceDot", Parent = Row,
					BackgroundTransparency = 1, BorderSizePixel = 0,
					Image = IN_EXPERIENCE_CUTOUT_IMAGE,
					ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 0,
					ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromOffset(PresenceSize, PresenceSize),
					Position = UDim2.new(0, 56, 0, 20 - PresenceSize / 2),
					ZIndex = SETTINGS_BASE_ZINDEX + 5,
				})
			else
				PresenceDot = Create("Frame", {
					Name = "PresenceDot", Parent = Row,
					BackgroundColor3 = StatusColor, BackgroundTransparency = 0,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(PresenceSize, PresenceSize),
					Position = UDim2.new(0, 56, 0, 20 - PresenceSize / 2),
					ZIndex = SETTINGS_BASE_ZINDEX + 5,
				})
				local PresenceCorner = Instance.new("UICorner")
				PresenceCorner.CornerRadius = UDim.new(1, 0)
				PresenceCorner.Parent = PresenceDot
			end
		end

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
			InviteLabel.Font = Enum.Font.SourceSans
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

		if USE_NEW_INVITE_MENU then
			local NewButton = Row:FindFirstChild("InviteButton")
			local NewLabel = NewButton and NewButton:FindFirstChild("InviteButtonTextLabel")
			if NewButton and NewLabel then
				StyleNewInviteAction(NewButton, NewLabel, Friend.Invited == true)
			end
		end

		return Row

	end

-- ============================================================
-- REBUILD INVITE LIST
-- ============================================================

UpdateInviteListScrollbar = function()
	if not InviteList then return end
	-- Keep scrolling functional without showing a visible scrollbar.
	InviteList.ScrollBarThickness = 0
	InviteList.VerticalScrollBarInset = Enum.ScrollBarInset.None
end

RebuildInviteList =
	function()

		-- New invite-menu rows are not selected or highlighted.
		InviteSelectedIndex = 0
		InviteSelectedFriendId = nil
		Protect(function() GuiService.SelectedObject = nil end)
		Protect(function() GuiService.SelectedCoreObject = nil end)

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

		local ShareScrollOffset = USE_NEW_INVITE_MENU and (INVITE_SHARE_ROW_HEIGHT + INVITE_SHARE_ROW_GAP) or 0
		local FriendRowsHeight = math.max(0, Count * (INVITE_ROW_HEIGHT + INVITE_ROW_GAP) - INVITE_ROW_GAP)
		InviteList.CanvasSize = UDim2.new(0, 0, 0, ShareScrollOffset + FriendRowsHeight)

		UpdateInviteListScrollbar()
		Spawn(function()
			Wait()
			UpdateInviteListScrollbar()
		end)

		InviteSelectedIndex = 0
		InviteSelectedFriendId = nil
		Protect(function() GuiService.SelectedObject = nil end)
		Protect(function() GuiService.SelectedCoreObject = nil end)

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
		InviteList.CanvasPosition = Vector2.new(0, 0)
		if NewInviteShareRow then NewInviteShareRow.Visible = USE_NEW_INVITE_MENU end
		if SearchFrame then SearchFrame.Visible = true end

		if INVITE_MOBILE_HEADER_DIVIDER then INVITE_MOBILE_HEADER_DIVIDER.Visible = not USE_NEW_INVITE_MENU end

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
		-- The invite page has no selection overlay or auto-focused player row.
		InviteSelectedIndex = 0
		InviteSelectedFriendId = nil
		Protect(function() GuiService.SelectedObject = nil end)
		Protect(function() GuiService.SelectedCoreObject = nil end)
		ResizeHub()
		if ConfigureInviteMobileHeader then ConfigureInviteMobileHeader() end
		if InviteList then
			InviteList.ScrollBarThickness = 0
			InviteList.VerticalScrollBarInset = Enum.ScrollBarInset.None
		end

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
		if RefreshVoiceBetaBadgeVisibility then RefreshVoiceBetaBadgeVisibility() end
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

-- Keep the slider group centered in the same right-side control column.
-- The numeric field occupies the last 50px of the row; keep a 6px gap before it.
-- Use 42px hitboxes so the 30px +/- artwork does not clip at the button edges.
CameraSensitivitySlider.SliderFrame.Size = UDim2.new(0, 430, 0, 50)
CameraSensitivitySlider.SliderFrame.Position = UDim2.new(1, -494, 0.5, -25)
StretchSliderBars(CameraSensitivitySlider, 60, 386, nil, 42, 4)

CameraSensitivityNumberFrame = Create("Frame", {
	Name = "CameraSensitivityNumberFrame",
	Parent = CameraSensitivitySlider.RowFrame,
	BackgroundColor3 = Color3.fromRGB(58, 58, 58),
	BackgroundTransparency = 0,
	BorderSizePixel = 2,
	BorderColor3 = Color3.fromRGB(205, 205, 205),
	Size = UDim2.new(0, 50, 0, 38),
	Position = UDim2.new(1, -58, 0.5, -19),
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
OutputDeviceNames, OutputDeviceMap, CurrentOutputName, CurrentOutputGuid = GetOutputDeviceOptions()
local CurrentOutputIndex = 1
for Index, Name in ipairs(OutputDeviceNames) do
	local Info = OutputDeviceMap[Name]
	if Info and CurrentOutputName and CurrentOutputName == Info.Name
		and (not CurrentOutputGuid or CurrentOutputGuid == "" or CurrentOutputGuid == Info.Guid) then
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
		if not Info then return end
		if not SetRealOutputDevice(Info.Name, Info.Guid) then
			Spawn(function()
				Wait(0.25)
				local ActualName, ActualGuid = GetOutputDeviceInfo()
				for DeviceIndex, DeviceName in ipairs(OutputDeviceNames) do
					local ActualInfo = OutputDeviceMap[DeviceName]
					if ActualInfo and ActualName == ActualInfo.Name
						and (not ActualGuid or ActualGuid == "" or ActualGuid == ActualInfo.Guid) then
						if AudioOutputSelector then AudioOutputSelector:SetSelectionIndex(DeviceIndex, false) end
						break
					end
				end
			end)
		end
	end
)

VolumeSlider = MakeSlider(
	GamePage,
	"Volume",
	10,
	Floor((GameSettings.MasterVolume or 1) * 10),
	function(Value)
		SetMasterVolume(Value / 10)
		PlayVolumeChangeSound()
	end
)

-- Voice UI must be gated by a real native voice control for this experience.
-- EnableDefaultVoice is CreatorHub/PluginSecurity and defaults to true; by itself
-- it is NOT reliable proof that the current experience exposes voice to players.
-- Likewise, account eligibility is not proof that this particular experience allows it.
-- The native ESC self-mute control is created by Roblox's own voice UI in a
-- voice-enabled context. Require that control and its genuine VoiceChat state icon
-- in addition to the live internal context check; fail closed if either is missing.
local function HasNativeExperienceVoiceControl()
    local RobloxGui = nil
    local SettingsShield = nil
    local NativeButton = nil
    local Ok = pcall(function()
        RobloxGui = CoreGui:FindFirstChild("RobloxGui")
        SettingsShield = RobloxGui and RobloxGui:FindFirstChild("SettingsClippingShield")
        NativeButton = SettingsShield and SettingsShield:FindFirstChild("MuteSelfButton", true)
    end)
    if not Ok or not NativeButton then return false end

    local Candidates = {NativeButton}
    local DescendantsOk, Descendants = pcall(function()
        return NativeButton:GetDescendants()
    end)
    if DescendantsOk and type(Descendants) == "table" then
        for _, Descendant in ipairs(Descendants) do
            table.insert(Candidates, Descendant)
        end
    end

    for _, Candidate in ipairs(Candidates) do
        local IsImage, Image = false, ""
        pcall(function()
            IsImage = Candidate:IsA("ImageLabel") or Candidate:IsA("ImageButton")
            Image = tostring(Candidate.Image or "")
        end)
        if IsImage and Image:find("VoiceChat", 1, true)
            and (Image:find("Muted", 1, true)
                or Image:find("Unmuted", 1, true)
                or Image:find("Connecting", 1, true)
                or Image:find("Error", 1, true)) then
            return true
        end
    end
    return false
end

GetGameVoiceSupport = function()
    -- The top-of-file "NEVER" mode intentionally overrides all automatic
    -- place/context checks, so the rest of the script sees voice as unavailable.
    if VOICE_CHAT_FORCE_OFF then return false end

	local SettingReadable = false
	local DefaultVoiceEnabled = nil

	local ReadOk, Enabled = pcall(function()
		return VoiceChatService.EnableDefaultVoice
	end)
	if ReadOk and type(Enabled) == "boolean" then
		SettingReadable = true
		DefaultVoiceEnabled = Enabled
	elseif type(gethiddenproperty) == "function" then
		local HiddenOk, HiddenEnabled = pcall(function()
			return gethiddenproperty(VoiceChatService, "EnableDefaultVoice")
		end)
		if HiddenOk and type(HiddenEnabled) == "boolean" then
			SettingReadable = true
			DefaultVoiceEnabled = HiddenEnabled
		end
	end

	if not SettingReadable or DefaultVoiceEnabled ~= true then
		return false
	end

	-- Older experiences used MaxPlayers > 100 as a voice-off switch. Keep
	-- honoring that configuration so the custom controls don't appear there.
	local MaxPlayers = nil
	pcall(function() MaxPlayers = Players.MaxPlayers end)
	if type(MaxPlayers) == "number" and MaxPlayers > 100 then
		return false
	end

	-- Require Roblox's live context gate as a second positive signal. The service
	-- property can retain a default-looking true value in clients where voice is
	-- not actually available in the current context. A missing/locked/unknown
	-- context result is not proof of support, so fail closed instead of showing
	-- custom voice controls in an unsupported experience.
	if not VoiceChatInternal then return false end
	local ContextOk, ContextEnabled = pcall(function()
		return VoiceChatInternal:IsContextVoiceEnabled()
	end)
	if not ContextOk or type(ContextEnabled) ~= "boolean" or ContextEnabled ~= true then
		return false
	end

    -- This prevents the false positive where the service's default-true property
    -- plus a stale/overly-broad internal context result makes custom VC controls
    -- appear in an experience where Roblox has not exposed its own voice controls.
    if not HasNativeExperienceVoiceControl() then return false end

	return true
end

-- This is the documented client-side account eligibility check. It only checks
-- the local player. If the request fails, do not guess from IsContextVoiceEnabled
-- or from a generic CoreGui button: those can exist even when this account is not
-- eligible. The poller retries later, so a temporary HTTP failure can recover.
GetAccountVoiceAllowed = function()
    if VOICE_CHAT_FORCE_OFF then return false end
	local Success, Allowed = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId)
	end)
	return Success and Allowed == true
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
VoiceAccountAllowed = VoiceGameSupported == true and GetAccountVoiceAllowed() == true
VoiceOptionAvailable = VoiceGameSupported == true and VoiceAccountAllowed == true
if VoiceAccountAllowed == true and LocalPlayer and LocalPlayer.UserId then
	VoiceEnabledCache[tonumber(LocalPlayer.UserId) or 0] = true
end
if RefreshVoiceBetaBadgeVisibility then RefreshVoiceBetaBadgeVisibility() end

-- Do not change VoiceChatService.UseAudioApi from the client. Roblox owns the
-- Audio API rollout and creates the real AudioDeviceInput when that path is active.
VoiceInitiallyConnected = VoiceOptionAvailable and IsLocalVoiceConnectionReady()
-- Do not expose an On/Off connection selector: voice is auto-requested whenever
-- the experience supports voice and Roblox confirms that this local account is eligible.
VoiceChatEnabled = VoiceOptionAvailable == true
VoiceChatDesiredOn = VoiceOptionAvailable == true
RefreshLocalVoiceState()
VoiceChatSelector = nil

InputDeviceNames, InputDeviceMap, CurrentInputName, CurrentInputGuid = GetInputDeviceOptions()
local CurrentInputIndex = 1
for Index, Name in ipairs(InputDeviceNames) do
	local Info = InputDeviceMap[Name]
	if Info and CurrentInputName and CurrentInputName == Info.Name
		and (not CurrentInputGuid or CurrentInputGuid == "" or CurrentInputGuid == Info.Guid) then
		CurrentInputIndex = Index
		break
	end
end

AudioInputSelector = MakeSelector(
	GamePage,
	"Input Device",
	InputDeviceNames,
	CurrentInputIndex,
	function(Index, Value)
		local Info = InputDeviceMap[Value]
		if not Info then return end
		if not SetRealInputDevice(Info.Name, Info.Guid) then
			Spawn(function()
				Wait(0.25)
				local ActualName, ActualGuid = GetInputDeviceInfo()
				for DeviceIndex, DeviceName in ipairs(InputDeviceNames) do
					local ActualInfo = InputDeviceMap[DeviceName]
					if ActualInfo and ActualName == ActualInfo.Name
						and (not ActualGuid or ActualGuid == "" or ActualInfo.Guid == ActualGuid) then
						if AudioInputSelector then AudioInputSelector:SetSelectionIndex(DeviceIndex, false) end
						break
					end
				end
			end)
		end
	end
)

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
	-- Input Device now belongs to the main Settings page, not the voice-only rows.
	RemoveRow(VoiceChatSelector)
	VoiceChatSelector = nil
	if GamePage and GamePage.ReflowRows then pcall(function() GamePage:ReflowRows() end) end
end

-- Rebuild now that VoiceGameSupported is initialized. The very first player-list
-- build occurs earlier in startup, before this eligibility check has a value.
if RebuildPlayersPage then RebuildPlayersPage() end

Spawn(function()
	-- Capture this run's GUI; do not let reruns keep the previous worker alive.
	local WorkerScreenGui = ScreenGui
	while WorkerScreenGui and WorkerScreenGui.Parent do
		Wait(VoiceOptionAvailable and 8 or 1.5)
		local NewGameSupport = GetGameVoiceSupport()
		local NewAccountAllowed = NewGameSupport == true and GetAccountVoiceAllowed() == true
		-- Re-evaluate both gates on every pass. Never keep an old true value just
		-- because the voice auto-join preference was previously enabled: this is what
		-- caused voice UI to persist into places with voice disabled.
		local NewOptionAvailable = NewGameSupport == true and NewAccountAllowed == true
		local Changed = NewGameSupport ~= VoiceGameSupported
			 or NewAccountAllowed ~= VoiceAccountAllowed
			 or NewOptionAvailable ~= VoiceOptionAvailable
		local SupportBecameAvailable = NewGameSupport == true and VoiceGameSupported ~= true
		VoiceGameSupported = NewGameSupport
		VoiceAccountAllowed = NewAccountAllowed
		VoiceOptionAvailable = NewOptionAvailable
		if RefreshVoiceBetaBadgeVisibility then RefreshVoiceBetaBadgeVisibility() end
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
			VoiceConnectionAttempting = false
			VoiceChatEnabled = false
			LocalVoiceEnabled = false
			-- Make the global mute/connect action impossible while the current place
			-- or this account is not voice-enabled, even if the menu was already open.
			if VoiceChatButton then VoiceChatButton.Visible = false end
			VoiceEnabledCache = {}
			VoiceMutedPlayers = {}
			VoiceMuteAllActive = false
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


-- Experience Language is distinct from Chat Translation Language. Prefer the
-- universe-specific locale list, falling back to the known Roblox locale list if
-- the client cannot fetch the localization endpoint.
local ExperienceLanguageNameByLocale = {}
for _, Item in ipairs(ChatTranslationLanguageEntries) do
	ExperienceLanguageNameByLocale[NormalizeChatTranslationLocale(Item[2])] = Item[1]
end

local function FetchExperienceLanguageEntries()
	local Result = {}
	local Seen = {}
	local function Add(Locale, DisplayName)
		Locale = NormalizeChatTranslationLocale(Locale):gsub("_", "-")
		if Locale == "" or Seen[Locale] then return end
		DisplayName = tostring(DisplayName or ExperienceLanguageNameByLocale[Locale] or "")
		if DisplayName == "" then
			local Short = Locale:match("^[^-]+") or Locale
			DisplayName = ExperienceLanguageNameByLocale[Short] or Locale
		end
		Seen[Locale] = true
		table.insert(Result, {DisplayName, Locale})
	end

	local Body = nil
	local Url = "https://gameinternationalization.roblox.com/v1/supported-languages/games/"
		.. tostring(game.GameId) .. "/in-experience-language-selection"
	pcall(function()
		if game.HttpGet then Body = game:HttpGet(Url) end
	end)
	if Body then
		pcall(function()
			local Decoded = HttpService:JSONDecode(Body)
			local List = Decoded
			if type(Decoded) == "table" then
				List = Decoded.languages or Decoded.supportedLanguages or Decoded.supported_languages
					or Decoded.locales or Decoded.data or Decoded
			end
			if type(List) == "table" then
				for Key, Item in pairs(List) do
					if type(Item) == "string" then
						if type(Key) == "string" and not tonumber(Key) then Add(Key, Item) else Add(Item, nil) end
					elseif type(Item) == "table" then
						local Locale = Item.localeCode or Item.locale_code or Item.locale or Item.code
							or Item.languageCode or Item.language_code or Item.target_language_code or Item.id
						local Display = Item.displayName or Item.display_name or Item.languageName
							or Item.language_name or Item.nativeName or Item.native_name or Item.name
						if Locale then Add(Locale, Display) end
					end
				end
			end
		end)
	end

	if #Result == 0 then
		for _, Item in ipairs(ChatTranslationLanguageEntries) do Add(Item[2], Item[1]) end
	else
		table.sort(Result, function(A, B) return A[1]:lower() < B[1]:lower() end)
	end
	return Result
end

ExperienceLanguageEntries = FetchExperienceLanguageEntries()
ExperienceLanguageNames = {}
ExperienceLanguageCodes = {}
for Index, Item in ipairs(ExperienceLanguageEntries) do
	ExperienceLanguageNames[Index] = Item[1]
	ExperienceLanguageCodes[Item[1]] = Item[2]
end

ExperienceLanguageTranslator = nil
ExperienceLanguageTranslatorLookupAttempted = false
GetExperienceTranslatorLocale = function()
	local Locale = nil
	pcall(function()
		local Translator = ExperienceLanguageTranslator
		if Translator then Locale = Translator.LocaleId end
	end)
	if type(Locale) ~= "string" or Locale == "" then return nil end
	return NormalizeChatTranslationLocale(Locale):gsub("_", "-")
end

GetCurrentExperienceLocale = function()
	local Locale = GetExperienceTranslatorLocale()

	-- Prefer the live Translator object. Roblox updates its LocaleId when the
	-- player changes Experience Language in the native in-game settings.
	if not Locale and not ExperienceLanguageTranslatorLookupAttempted then
		-- Use the documented async API rather than the older sync variant, which
		-- can be absent or return a translator that doesn't track the live setting.
		ExperienceLanguageTranslatorLookupAttempted = true
		pcall(function()
			local Translator = LocalizationService:GetTranslatorForPlayerAsync(LocalPlayer)
			if Translator then
				ExperienceLanguageTranslator = Translator
				Locale = Translator.LocaleId
			end
		end)
	end
	if not Locale then
		Locale = GetHiddenOrSetting(LocalizationService, "ExperienceSettingsLocaleId", nil)
	end
	if not Locale then Locale = GetSetting(LocalPlayer, "LocaleId", "en-us") end
	return NormalizeChatTranslationLocale(Locale):gsub("_", "-")
end

SetExperienceLanguage = function(Locale)
	Locale = NormalizeChatTranslationLocale(Locale):gsub("_", "-")
	if Locale == "" then return false end

	local function WaitForExperienceLocale()
		-- Only count it as a native change when the live Translator actually
		-- reports the selected locale; a hidden-property write is not proof.
		for _ = 1, 30 do
			Wait(0.1)
			if GetExperienceTranslatorLocale() == Locale then
				MenuLocalizationOverrideLocale = nil
				MenuLastObservedExperienceLocale = Locale
				pcall(function()
					if type(RefreshMenuLocalization) == "function" then RefreshMenuLocalization() end
				end)
				return true
			end
		end
		return false
	end

	if GetExperienceTranslatorLocale() == Locale then
		MenuLocalizationOverrideLocale = nil
		MenuLastObservedExperienceLocale = Locale
		ApplyMenuLocalizationLocale(Locale)
		return true
	end

	-- Current clients expose the native setter on Player (RobloxScriptSecurity).
	-- An executor may or may not be permitted to call it, so probe it first.
	local PlayerSetter = nil
	pcall(function() PlayerSetter = LocalPlayer.SetExperienceSettingsLocaleId end)
	if type(PlayerSetter) == "function" then
		local Ok = pcall(function() PlayerSetter(LocalPlayer, Locale) end)
		if Ok and WaitForExperienceLocale() then return true end
	end

	-- Compatibility with older/custom clients that still expose the removed
	-- LocalizationService-level method.
	local Method = nil
	pcall(function() Method = LocalizationService.SetExperienceSettingsLocaleId end)
	if type(Method) == "function" then
		local Ok = pcall(function() Method(LocalizationService, Locale) end)
		if Ok and WaitForExperienceLocale() then return true end
	end

	-- Last compatibility attempt for legacy executor/client combinations. If it
	-- does not change the live translator, roll back the speculative writes.
	if type(sethiddenproperty) == "function" then
		local PreviousHiddenValues = {}
		for _, Property in ipairs({"ExperienceSettingsLocaleId", "PlayerChoiceLocaleId", "InExperienceLocaleId"}) do
			local PreviousValue = GetHiddenOrSetting(LocalizationService, Property, nil)
			local Ok = pcall(function() sethiddenproperty(LocalizationService, Property, Locale) end)
			if Ok then table.insert(PreviousHiddenValues, {Name = Property, Value = PreviousValue}) end
		end
		if #PreviousHiddenValues > 0 and WaitForExperienceLocale() then return true end
		for _, Entry in ipairs(PreviousHiddenValues) do
			pcall(function() sethiddenproperty(LocalizationService, Entry.Name, Entry.Value) end)
		end
	end

	-- Do not snap the user's dropdown back to the detected account locale.
	-- When the native setter is blocked, this choice still changes this custom
	-- ESC menu's translations; the native Roblox experience locale may stay put.
	MenuLocalizationOverrideLocale = Locale
	ApplyMenuLocalizationLocale(Locale)
	return true
end
local CurrentExperienceLocale = GetCurrentExperienceLocale()
MenuLastObservedExperienceLocale = NormalizeMenuLocale(CurrentExperienceLocale)
pcall(function()
	if type(RefreshMenuLocalization) == "function" then RefreshMenuLocalization() end
end)
local CurrentExperienceLanguageIndex = nil
for Index, Item in ipairs(ExperienceLanguageEntries) do
	if NormalizeChatTranslationLocale(Item[2]) == CurrentExperienceLocale then
		CurrentExperienceLanguageIndex = Index
		break
	end
end
-- Some experiences list a base locale ("es") while Roblox reports a regional
-- locale ("es-es"). Match the base language only if no exact locale is present.
if not CurrentExperienceLanguageIndex then
	local CurrentLanguageBase = CurrentExperienceLocale:match("^([^-]+)") or CurrentExperienceLocale
	for Index, Item in ipairs(ExperienceLanguageEntries) do
		local ItemLocale = NormalizeChatTranslationLocale(Item[2])
		if (ItemLocale:match("^([^-]+)") or ItemLocale) == CurrentLanguageBase then
			CurrentExperienceLanguageIndex = Index
			break
		end
	end
end
if not CurrentExperienceLanguageIndex then
	for Index, Item in ipairs(ExperienceLanguageEntries) do
		if NormalizeChatTranslationLocale(Item[2]) == "en-us" or NormalizeChatTranslationLocale(Item[2]) == "en" then
			CurrentExperienceLanguageIndex = Index
			break
		end
	end
end
CurrentExperienceLanguageIndex = CurrentExperienceLanguageIndex or 1

ExperienceLanguageSelector = MakeDropDown(
	GamePage,
	"Experience Language",
	ExperienceLanguageNames,
	CurrentExperienceLanguageIndex,
	function(Index, Value)
		local Locale = ExperienceLanguageCodes[Value]
		if not Locale then return end
		SetExperienceLanguage(Locale)
	end
)
-- Center the 300px dropdown in the same 502px control column as the other controls.
-- (502 - 300) / 2 = 101px inset from the column's left edge.
ExperienceLanguageSelector.DropDownFrame.Position = UDim2.new(1, -401, 0.5, -22)

-- Follow the live in-experience language, including changes made in Roblox's
-- native ESC settings while this custom menu is open or hidden. Use the
-- Translator.LocaleId event for immediate updates and a small polling fallback
-- for clients where the selector setting is exposed only through hidden state.
do
	local MonitorData = Data
	local BoundTranslator = nil
	local TranslatorLocaleConnection = nil
	local LastSeenExperienceLocale = NormalizeChatTranslationLocale(GetCurrentExperienceLocale())
	local NextTranslatorBindAttempt = 0

	local function SyncExperienceLanguage(Locale, NativeLocaleChanged)
		Locale = NormalizeChatTranslationLocale(Locale or GetCurrentExperienceLocale()):gsub("_", "-")
		if Locale == "" then return end

		local DetectedLocale = NormalizeMenuLocale(GetMenuExperienceLocale())
		if NativeLocaleChanged then
			-- Only the bound Translator's property event or a poll of that already-
			-- bound Translator counts as a genuine native language change.
			MenuLastObservedExperienceLocale = DetectedLocale
			MenuLocalizationOverrideLocale = nil
		elseif not MenuLastObservedExperienceLocale then
			MenuLastObservedExperienceLocale = DetectedLocale
		end
		if MenuLocalizationOverrideLocale and not NativeLocaleChanged then
			ApplyMenuLocalizationLocale(MenuLocalizationOverrideLocale)
			return
		end

		if MenuLocalizationLocale ~= Locale and type(RefreshMenuLocalization) == "function" then
			RefreshMenuLocalization()
		end

		local SelectedLanguageName = nil
		local LocaleBase = Locale:match("^([^-]+)") or Locale
		for _, LanguageName in ipairs(ExperienceLanguageNames) do
			if NormalizeChatTranslationLocale(ExperienceLanguageCodes[LanguageName]) == Locale then
				SelectedLanguageName = LanguageName
				break
			end
		end
		if not SelectedLanguageName then
			for _, LanguageName in ipairs(ExperienceLanguageNames) do
				local ItemLocale = NormalizeChatTranslationLocale(ExperienceLanguageCodes[LanguageName])
				if (ItemLocale:match("^([^-]+)") or ItemLocale) == LocaleBase then
					SelectedLanguageName = LanguageName
					break
				end
			end
		end
		if SelectedLanguageName and ExperienceLanguageSelector then
			pcall(function()
				ExperienceLanguageSelector:SetSelectionByValue(SelectedLanguageName, false)
			end)
		end
	end

	local function BindExperienceTranslator()
		local Translator = nil
		pcall(function()
			Translator = LocalizationService:GetTranslatorForPlayerAsync(LocalPlayer)
		end)
		if not Translator or Translator == BoundTranslator then return end

		if TranslatorLocaleConnection then
			pcall(function() TranslatorLocaleConnection:Disconnect() end)
		end
		BoundTranslator = Translator
		ExperienceLanguageTranslator = Translator
		TranslatorLocaleConnection = nil
		pcall(function()
			TranslatorLocaleConnection = Connect(Translator:GetPropertyChangedSignal("LocaleId"), function()
				local Actual = GetCurrentExperienceLocale()
				LastSeenExperienceLocale = NormalizeChatTranslationLocale(Actual)
				SyncExperienceLanguage(Actual, true)
			end)
		end)
		local Actual = GetCurrentExperienceLocale()
		LastSeenExperienceLocale = NormalizeChatTranslationLocale(Actual)
		SyncExperienceLanguage(Actual)
	end

	-- Try to bind immediately, then keep retrying briefly if the player translator
	-- has not finished initializing. The monitor ends automatically on script reload.
	Spawn(function()
		BindExperienceTranslator()
		while getgenv().Settings2016Data == MonitorData do
			Wait(0.5)
			local Actual = NormalizeChatTranslationLocale(GetCurrentExperienceLocale()):gsub("_", "-")
			if Actual ~= "" and Actual ~= LastSeenExperienceLocale then
				LastSeenExperienceLocale = Actual
				SyncExperienceLanguage(Actual, BoundTranslator ~= nil)
			end
			if not BoundTranslator then
				local Now = os.clock()
				if Now >= NextTranslatorBindAttempt then
					NextTranslatorBindAttempt = Now + 2
					BindExperienceTranslator()
				end
			end
		end
	end)
end

MakeSectionHeader(GamePage, "Display & Graphics")

FullscreenSelector = MakeSelector(
	GamePage,
	"Fullscreen",
	{"On", "Off"},
	(GameSettings:InFullScreen() and 1) or 2,
	function(Index)
		local Desired = Index == 1
		local Current = false
		pcall(function() Current = GameSettings:InFullScreen() == true end)
		if Current == Desired then return end
		local Success = pcall(function() GuiService:ToggleFullscreen() end)
		if not Success and keypress and keyrelease then
			pcall(function() keypress(0x7A); keyrelease(0x7A) end)
		end
		Spawn(function()
			Wait(0.25)
			local Actual = false
			pcall(function() Actual = GameSettings:InFullScreen() == true end)
			if FullscreenSelector then FullscreenSelector:SetSelectionIndex(Actual and 1 or 2, false) end
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

-- VR is a user setting on clients that expose the internal VREnabled property.
-- Attempt the hidden property first, then the normal assignment; never invent a
-- separate local-only visual state that would claim the engine changed when it did not.
VRCurrent = GetHiddenOrSetting(GameSettings, "VREnabled", false) == true
VRSelector = MakeSelector(
	GamePage,
	"VR",
	{"On", "Off"},
	VRCurrent and 1 or 2,
	function(Index)
		local Desired = Index == 1
		local Wrote = false
		if sethiddenproperty then
			Wrote = pcall(function() sethiddenproperty(GameSettings, "VREnabled", Desired) end) or Wrote
		end
		Wrote = pcall(function() GameSettings.VREnabled = Desired end) or Wrote
		if not Wrote and VRService then
			if sethiddenproperty then
				Wrote = pcall(function() sethiddenproperty(VRService, "VREnabled", Desired) end) or Wrote
			end
		end
		-- Read the real property back so a rejected engine write doesn't leave the UI lying.
		Spawn(function()
			Wait(0.15)
			local Actual = GetHiddenOrSetting(GameSettings, "VREnabled", VRCurrent) == true
			VRCurrent = Actual
			if VRSelector then VRSelector:SetSelectionIndex(Actual and 1 or 2, false) end
		end)
	end
)

VideoCaptureService = nil
pcall(function() VideoCaptureService = game:GetService("VideoCaptureService") end)
VideoCameraNames = {"System Default"}
VideoCameraMap = { ["System Default"] = "" }
VideoCameraSeenIds = {}
GetVideoCameraId = function()
	if not VideoCaptureService then return "" end
	local Value = GetHiddenOrSetting(VideoCaptureService, "CameraID", "")
	return tostring(Value or "")
end

local function AddVideoCamera(CameraId, DisplayName)
	CameraId = tostring(CameraId or "")
	DisplayName = tostring(DisplayName or "")
	if CameraId == "" or VideoCameraSeenIds[CameraId] then return end
	if DisplayName == "" then DisplayName = "Camera " .. tostring(#VideoCameraNames) end
	local Label = DisplayName
	local Suffix = 2
	while VideoCameraMap[Label] ~= nil do
		Label = DisplayName .. " (" .. tostring(Suffix) .. ")"
		Suffix += 1
	end
	VideoCameraSeenIds[CameraId] = true
	VideoCameraMap[Label] = CameraId
	table.insert(VideoCameraNames, Label)
end

local function ParseVideoCameraDevices(Value, Depth)
	Depth = Depth or 0
	if Depth > 6 or type(Value) ~= "table" then return end
	local CameraId = Value.CameraID or Value.CameraId or Value.cameraId or Value.cameraID
		or Value.Id or Value.id or Value.Guid or Value.guid or Value.DeviceId or Value.deviceId
	local DisplayName = Value.Name or Value.name or Value.DisplayName or Value.displayName
		or Value.DeviceName or Value.deviceName or Value.Label or Value.label
	if CameraId then AddVideoCamera(CameraId, DisplayName) end
	for Key, Child in pairs(Value) do
		if type(Child) == "table" then
			ParseVideoCameraDevices(Child, Depth + 1)
		elseif type(Key) == "string" and type(Child) == "string" then
			local KeyLooksLikeId = Key:find("%x%x%x%x%x%x%x%x%-", 1) ~= nil
				or (Key:sub(1, 1) == "{" and Key:sub(-1) == "}")
				or (#Key >= 24 and not Key:find("%s"))
			if KeyLooksLikeId then AddVideoCamera(Key, Child) else AddVideoCamera(Child, Key) end
		end
	end
end

if VideoCaptureService then
	pcall(function()
		local Devices = VideoCaptureService:GetCameraDevices()
		ParseVideoCameraDevices(Devices, 0)
	end)
	local CurrentCameraId = GetVideoCameraId()
	if CurrentCameraId ~= "" and not VideoCameraSeenIds[CurrentCameraId] then
		AddVideoCamera(CurrentCameraId, "Current Camera")
	end
end

local CurrentVideoCameraId = GetVideoCameraId()
local CurrentVideoCameraIndex = 1
for Index, Label in ipairs(VideoCameraNames) do
	if VideoCameraMap[Label] == CurrentVideoCameraId then CurrentVideoCameraIndex = Index break end
end

VideoCameraSelector = MakeSelector(
	GamePage,
	"Video Camera",
	VideoCameraNames,
	CurrentVideoCameraIndex,
	function(Index, Value)
		if not VideoCaptureService then return end
		local CameraId = VideoCameraMap[Value]
		if CameraId == nil then return end
		local Wrote = false
		if sethiddenproperty then
			Wrote = pcall(function() sethiddenproperty(VideoCaptureService, "CameraID", CameraId) end) or Wrote
		end
		Wrote = pcall(function() VideoCaptureService.CameraID = CameraId end) or Wrote
		Spawn(function()
			Wait(0.15)
			local Actual = GetVideoCameraId()
			for CameraIndex, CameraLabel in ipairs(VideoCameraNames) do
				if VideoCameraMap[CameraLabel] == Actual then
					if VideoCameraSelector then VideoCameraSelector:SetSelectionIndex(CameraIndex, false) end
					break
				end
			end
		end)
	end
)


-- ============================================================
-- MINIMAL SETTINGS PAGE: only the requested controls, in the requested order.
-- We build controls with their normal callbacks above, then keep only these rows.
-- ============================================================
SetSettingsRowTitle = function(Selector, Title)
	local Row = Selector and Selector.RowFrame
	if not Row then return end
	local Base = Row.Name:gsub("Frame$", "")
	local Label = Row:FindFirstChild(Base .. "Label")
	if Label and Label:IsA("TextLabel") then Label.Text = Title end
end

SetSettingsRowTitle(ShiftLockMode, "Shift Lock")
SetSettingsRowTitle(CameraMode, "Camera Mode")
SetSettingsRowTitle(MovementMode, "Movement Mode")
SetSettingsRowTitle(ExperienceLanguageSelector, "Experience Language")
SetSettingsRowTitle(CameraSensitivitySlider, "Camera Sensitivity")
SetSettingsRowTitle(VolumeSlider, "Volume")
SetSettingsRowTitle(AudioInputSelector, "Input Device")
SetSettingsRowTitle(AudioOutputSelector, "Output Device")
SetSettingsRowTitle(FullscreenSelector, "Fullscreen")
SetSettingsRowTitle(GraphicsMode, "Graphics Mode")
SetSettingsRowTitle(GraphicsSlider, "Graphics Quality")
SetSettingsRowTitle(PerformanceSelector, "Performance Stats")
SetSettingsRowTitle(CameraInvertedSelector, "Camera Inverted")
SetSettingsRowTitle(VRSelector, "VR")
SetSettingsRowTitle(VideoCameraSelector, "Video Camera")

local AllowedSettingsRow = {}
local OrderedSettingsRows = {}
local function KeepRequestedSettingsRow(Row)
	if Row and Row.Parent and not AllowedSettingsRow[Row] then
		AllowedSettingsRow[Row] = true
		table.insert(OrderedSettingsRows, Row)
	end
end

-- Explicit append calls preserve the exact order even if a specific engine build
-- omits one hidden/native control and returns nil for its selector object.
KeepRequestedSettingsRow(ShiftLockMode and ShiftLockMode.RowFrame)
KeepRequestedSettingsRow(CameraMode and CameraMode.RowFrame)
KeepRequestedSettingsRow(MovementMode and MovementMode.RowFrame)
KeepRequestedSettingsRow(ExperienceLanguageSelector and ExperienceLanguageSelector.RowFrame)
KeepRequestedSettingsRow(CameraSensitivitySlider and CameraSensitivitySlider.RowFrame)
KeepRequestedSettingsRow(VolumeSlider and VolumeSlider.RowFrame)
KeepRequestedSettingsRow(AudioInputSelector and AudioInputSelector.RowFrame)
KeepRequestedSettingsRow(AudioOutputSelector and AudioOutputSelector.RowFrame)
KeepRequestedSettingsRow(FullscreenSelector and FullscreenSelector.RowFrame)
KeepRequestedSettingsRow(GraphicsMode and GraphicsMode.RowFrame)
KeepRequestedSettingsRow(GraphicsSlider and GraphicsSlider.RowFrame)
KeepRequestedSettingsRow(PerformanceSelector and PerformanceSelector.RowFrame)
KeepRequestedSettingsRow(MicroProfilerRow)
KeepRequestedSettingsRow(CameraInvertedSelector and CameraInvertedSelector.RowFrame)
KeepRequestedSettingsRow(VRSelector and VRSelector.RowFrame)
KeepRequestedSettingsRow(VideoCameraSelector and VideoCameraSelector.RowFrame)
for _, Row in ipairs(GamePage.Rows) do
	if not AllowedSettingsRow[Row] then
		pcall(function() Row:Destroy() end)
	end
end
GamePage.Rows = OrderedSettingsRows
local SettingsRowsY = 0
for _, Row in ipairs(GamePage.Rows) do
	Row.Parent = GamePage.Frame
	Row.Position = UDim2.new(0, 0, 0, SettingsRowsY)
	SettingsRowsY += math.max(1, Row.Size.Y.Offset)
end
GamePage.NextY = SettingsRowsY
GamePage.Frame.Size = UDim2.new(1, 0, 0, PAGE_TOP_PADDING + SettingsRowsY)

-- Keep the Fullscreen selector synchronized if the host/window changes outside the menu.
Spawn(function()
	while FullscreenSelector and FullscreenSelector.RowFrame and FullscreenSelector.RowFrame.Parent do
		local Actual = false
		pcall(function() Actual = GameSettings:InFullScreen() == true end)
		local Index = Actual and 1 or 2
		if FullscreenSelector:GetSelectedIndex() ~= Index then
			FullscreenSelector:SetSelectionIndex(Index, false)
		end
		Wait(0.5)
	end
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
	function(_Active)
		if not Submit or not SubmitLabel then return end
		-- Keep Submit interactable at all times; the click handler explains
		-- missing selections instead of making the button look disabled.
		Submit.Active = true
		Submit.Selectable = true
		Submit.AutoButtonColor = true
		Submit.ImageTransparency = 0
		Submit.ZIndex = SETTINGS_BASE_ZINDEX + 3
		SubmitLabel.ZIndex = Submit.ZIndex + 1
		SubmitLabel.TextTransparency = 0
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

ReportMode:SetSize(UDim2.new(0, 450, 0, 50))
ReportMode:SetPosition(UDim2.new(1, -450, 0.5, -25))

WhichPlayer =
	MakeDropDown(
		ReportPage,
		"Which Player?",
		PlayerNames,
		nil,
		function() RefreshSubmitState(ReportMode) end
	)

WhichPlayer:SetInteractable(false)
if WhichPlayer.DropDownFrame then
	WhichPlayer.DropDownFrame.Size = UDim2.new(0, 380, 0, 44)
	WhichPlayer.DropDownFrame.Position = UDim2.new(1, -430, 0.5, -22)
end

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
if TypeOfAbuse.DropDownFrame then
	TypeOfAbuse.DropDownFrame.Size = UDim2.new(0, 380, 0, 44)
	TypeOfAbuse.DropDownFrame.Position = UDim2.new(1, -430, 0.5, -22)
end

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

SubmitReportThroughNativeCore = function(TargetPlayer, IsPlayerReport, Reason, DescriptionText)
	local RobloxGui = CoreGui:FindFirstChild("RobloxGui")
	local Modules = RobloxGui and RobloxGui:FindFirstChild("Modules")
	local SettingsModules = Modules and Modules:FindFirstChild("Settings")
	local Pages = SettingsModules and SettingsModules:FindFirstChild("Pages")
	local ReportModuleScript = Pages and Pages:FindFirstChild("ReportAbuseMenu")
	if not ReportModuleScript then return false end

	local RequireOk, NativeReport = pcall(require, ReportModuleScript)
	if not RequireOk or type(NativeReport) ~= "table" or not NativeReport.HubRef then
		return false
	end

	local OpenOk = pcall(function()
		if IsPlayerReport then
			NativeReport:ReportPlayer(TargetPlayer)
		else
			local NativeHub = NativeReport.HubRef
			if NativeHub:GetVisibility() then
				NativeHub:SwitchToPage(NativeReport, false)
			else
				NativeHub:SetVisibility(true, false, NativeReport)
			end
		end
	end)
	if not OpenOk then return false end

	-- The custom menu may have a higher CoreGui display order. Hide it so the
	-- official report form and its CoreScript-owned Submit button are accessible.
	pcall(function()
		if Hub and Hub.Visible and type(SetVisibility) == "function" then
			SetVisibility(false, true)
		end
	end)

	-- The page controls are constructed by the native Settings hub on demand.
	local Deadline = os.clock() + 4
	while os.clock() < Deadline do
		if NativeReport.GameOrPlayerMode and NativeReport.WhichPlayerMode
			and NativeReport.TypeOfAbuseMode and NativeReport.AbuseDescription
			and NativeReport.AbuseDescription.Selection then
			break
		end
		Wait(0.05)
	end
	if not (NativeReport.GameOrPlayerMode and NativeReport.WhichPlayerMode
		and NativeReport.TypeOfAbuseMode and NativeReport.AbuseDescription
		and NativeReport.AbuseDescription.Selection) then
		return "opened"
	end

	pcall(function()
		NativeReport.GameOrPlayerMode:SetSelectionIndex(IsPlayerReport and 2 or 1, true)
	end)
	Wait(0.1)
	if IsPlayerReport and TargetPlayer then
		pcall(function() NativeReport:UpdatePlayerDropDown() end)
		pcall(function() NativeReport.WhichPlayerMode:SetSelectionByValue(TargetPlayer.Name, true) end)
	end

	local NativePlayerReasons = {
		"Swearing", "Inappropriate Username", "Bullying", "Scamming", "Dating",
		"Cheating/Exploiting", "Personal Question", "Offsite Links",
	}
	local NativeGameReason = "Inappropriate Content"
	local NativeReason = IsPlayerReport and Reason or NativeGameReason
	local NativeReasons = IsPlayerReport and NativePlayerReasons or {NativeGameReason}
	local ReasonIndex = 1
	for Index, Value in ipairs(NativeReasons) do
		if Value == NativeReason then ReasonIndex = Index; break end
	end
	local NativeDescription = DescriptionText or ""
	if not IsPlayerReport and Reason ~= NativeGameReason then
		NativeDescription = "Selected report category: " .. tostring(Reason) .. "\n\n" .. NativeDescription
	end
	pcall(function() NativeReport.TypeOfAbuseMode:SetSelectionIndex(ReasonIndex, true) end)
	pcall(function() NativeReport.AbuseDescription.Selection.Text = NativeDescription end)
	Wait(0.1)

	local NativeSubmit = nil
	pcall(function()
		NativeSubmit = NativeReport.AbuseDescription.Selection:FindFirstChild("SubmitButton", true)
	end)
	if not NativeSubmit and NativeReport.Page then
		pcall(function() NativeSubmit = NativeReport.Page:FindFirstChild("SubmitButton", true) end)
	end
	if NativeSubmit and type(firesignal) == "function" then
		local FireOk = pcall(function() firesignal(NativeSubmit.MouseButton1Click) end)
		if FireOk then return "submitted" end
	end

	-- Official native page stays open and prefilled. The user can submit through the
	-- CoreScript's own button if signal injection is unavailable in this environment.
	pcall(function()
		GuiService:SendNotification({
			Title = "Report",
			Text = "Roblox's official report form is filled in. Press Submit there to send it.",
		})
	end)
	return "opened"
end

Submit, SubmitLabel =
	MakeStyledButton(
		"SubmitButton",
		"Submit",
		UDim2.new(0, 198, 0, 50),
		function()
			if not CanSubmitReport(ReportMode) then
				ShowAlert("Choose a report type and reason, and select a player when reporting a player.", "Ok")
				return
			end

			local IsPlayerReport = ReportMode:GetSelectedIndex() == 2
			local Reason = ((IsPlayerReport and ABUSE_TYPES_PLAYER) or ABUSE_TYPES_GAME)[TypeOfAbuse:GetSelectedIndex()]
			local TargetPlayer = IsPlayerReport and NameToPlayer[WhichPlayer:GetSelectedValue()] or nil
			local DescriptionText = GetReportDescription()

			local Success = Protect(function()
				if IsPlayerReport then
					if not TargetPlayer then
						error("No valid player was selected for the report")
					end
					-- Same API/signature as Roblox's native ReportAbuseMenu.
					Players:ReportAbuse(TargetPlayer, Reason, DescriptionText)
				else
					-- Roblox's legacy in-experience menu submits game reports through
					-- ReportAbuse(nil, reason, formattedPlaceDetails), not just the raw text.
					local PlaceId = tostring(game.PlaceId)
					local PlaceName = "N/A"
					local PlaceDescription = "N/A"
					pcall(function()
						local ProductInfo = MarketplaceService:GetProductInfo(game.PlaceId, Enum.InfoType.Asset)
						PlaceName = ProductInfo.Name or PlaceName
						PlaceDescription = ProductInfo.Description or PlaceDescription
					end)
					local FormattedText = string.format(
						"User Report: \n    %s \nPlace Title: \n    %s \nPlaceId: \n    %s \nPlace Description: \n    %s \n",
						DescriptionText,
						PlaceName,
						PlaceId,
						PlaceDescription
					)
					Players:ReportAbuse(nil, Reason, FormattedText)
				end
			end)

			local AlertText = "Thanks for your report! Our moderators will review the chat logs and evaluate what happened."
			if Reason == "Cheating/Exploiting" then
				AlertText = "Thanks for your report! We've recorded your report for evaluation."
			elseif Reason == "Inappropriate Username" then
				AlertText = "Thanks for your report! Our moderators will evaluate the username."
			elseif Reason == "Bad Model or Script" or Reason == "Inappropriate Content" or Reason == "Offsite Link" or Reason == "Offsite Links" then
				AlertText = "Thanks for your report! Our moderators will review the place and make a determination."
			end
			if not Success then
				local NativeFallback = SubmitReportThroughNativeCore(
					TargetPlayer,
					IsPlayerReport,
					Reason,
					DescriptionText
				)
				if NativeFallback == "submitted" then
					-- Native ReportAbuseMenu owns the submission result/confirmation UI.
					return
				elseif NativeFallback == "opened" then
					-- Do not cover the official report form with a custom error/alert.
					return
				end
				local ReportTargetName = "the experience"
				if IsPlayerReport then
					ReportTargetName = (TargetPlayer and TargetPlayer.Name)
						or tostring(WhichPlayer:GetSelectedValue() or "the selected player")
				else
					ReportTargetName = tostring(game.Name or "the experience")
					pcall(function()
						local ProductInfo = MarketplaceService:GetProductInfo(game.PlaceId, Enum.InfoType.Asset)
						if ProductInfo and type(ProductInfo.Name) == "string" and ProductInfo.Name ~= "" then
							ReportTargetName = ProductInfo.Name
						end
					end)
				end
				AlertText = string.format(
					"Roblox didn't let the script report %s for %s, because they don't like scripts doing anything.",
					ReportTargetName,
					tostring(Reason or "the selected reason")
				)
			end

			ShowAlert(AlertText, "Ok", function()
				ReportMode:SetSelectionIndex(1, true)
				WhichPlayer:ResetSelectionIndex()
				TypeOfAbuse:ResetSelectionIndex()
				Description.Text = DESCRIPTION_PLACEHOLDER
				SetVisibility(false)
			end, not Success)
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
			TextSize = 20,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -9, 0, 32),
			Position = UDim2.new(0, 9, 0, 0),
			ZIndex = SETTINGS_BASE_ZINDEX + 3,
		})

		for Index, Binding in ipairs(Bindings) do
			local Row = Create("Frame", {
				Parent = Group,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 56),
				Position = UDim2.new(0, 0, 0, 32 + ((Index - 1) * 60)),
				ZIndex = SETTINGS_BASE_ZINDEX + 2,
			})
			Create("TextLabel", {
				Parent = Row,
				BackgroundTransparency = 1,
				Text = Binding[1],
				Font = Enum.Font.SourceSansBold,
				TextSize = 20,
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
				TextSize = 20,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.55, 0, 1, 0),
				Position = UDim2.new(0.5, -4, 0, 0),
				ZIndex = SETTINGS_BASE_ZINDEX + 3,
			})
		end

		Group.Size = UDim2.new(Group.Size.X.Scale, Group.Size.X.Offset, 0, 32 + (#Bindings * 60))
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
			Selector.SelectorFrame.Size = UDim2.new(0.64, 0, 0, 50)
			Selector.SelectorFrame.Position = UDim2.new(1, -2, 0.5, 0)
			Selector.SelectorFrame.AnchorPoint = Vector2.new(1, 0.5)
		end
		if Selector and Selector.DropDownFrame then
			Selector.DropDownFrame.Size = UDim2.new(0.64, 0, 0, 44)
			Selector.DropDownFrame.Position = UDim2.new(1, -2, 0.5, -22)
			Selector.DropDownFrame.AnchorPoint = Vector2.new(1, 0)
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
	if (Platform == Enum.Platform.Windows or IsOSX) then
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

-- Keep the custom Record tab on Windows and macOS. Remove stale copies
-- only on platforms where this menu does not provide the Record tab.
if not IsOSX and UserInputService:GetPlatform() ~= Enum.Platform.Windows then
	-- Remove any stale Record tab left by earlier runs on unsupported platforms.
	RecordPage = nil
	RecorderPageButton = nil
	RecorderPageButtonLabel = nil
	if Hub and Hub.HubBarContainer then
		for _, Tab in ipairs(Hub.HubBarContainer:GetChildren()) do
			local Name = string.lower(tostring(Tab.Name or ""))
			local Label = Tab:FindFirstChild("TabLabel", true)
			local Title = Label and Label:FindFirstChild("Title", true)
			local Text = Title and tostring(Title.Text or "") or ""
			if Name:find("record", 1, true) or Text == "Record" then
				pcall(function() Tab:Destroy() end)
			end
		end
	end
end

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
		-- ImageColor3 tints the sliced button background, so keep it normal.
		ResetButton.ImageColor3 = NormalColor
		if ResetButtonLabel then
			ResetButtonLabel.TextColor3 = Allowed and NormalColor or DisabledColor
		end
	end

	if MobileActionButtons and MobileActionButtons.Reset then
		local Button = MobileActionButtons.Reset
		Button.Active = Allowed
		Button.Selectable = Allowed
		Button.AutoButtonColor = false
		-- Preserve the button background; the nested icon and label are tinted below.
		Button.ImageColor3 = NormalColor
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
	function(AlertMessage, OkButtonText, Cleanup, ForceBlueButton)
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
		if ForceBlueButton then
			-- Keep the selected blue Roblox button asset for the entire lifetime
			-- of the error dialog; don't rely on hover/selection state.
			Button.Image = BUTTON_SELECTED_IMAGE
			Button.ImageColor3 = Color3.new(1, 1, 1)
			Button.AutoButtonColor = false
		end
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
			if IsMobile then
				-- Phones and tablets use mobile-style confirmation buttons at the bottom.
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
	RegisterMenuLocalizableText(Label)

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

ShowInviteFailureError = function()
	local Message = "Experience Invite could not be sent. Please try again later."
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
VoiceChatButton.Visible = VoiceOptionAvailable == true and not VOICE_CHAT_FORCE_OFF

VoiceChatIcon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
if VoiceChatIcon then
	VoiceChatIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	VoiceChatIcon.Size = UDim2.fromOffset(50, 50)
	VoiceChatIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
end

ConfigureMobileActionButtons = function()
    local VoiceActive = VoiceOptionAvailable == true and VoiceChatButton ~= nil and not VOICE_CHAT_FORCE_OFF
    local ActionHeight = 62

    if IsMobile then
        VoiceChatButton.Visible = VoiceActive
        if not VoiceActive then VoiceChatButton.Parent = nil end
        if IsTablet then
            Hub.BottomButtonFrame.Parent = Hub.MenuContainer
            Hub.BottomButtonFrame.Visible = Hub.Visible and not Hub.InInviteMenu and not Hub.InConfirmation
            Hub.BottomButtonFrame.ZIndex = SETTINGS_BASE_ZINDEX + 6
            MobileActionButtons.Reset.Parent = Hub.BottomButtonFrame
            MobileActionButtons.Leave.Parent = Hub.BottomButtonFrame
            MobileActionButtons.Resume.Parent = Hub.BottomButtonFrame
        elseif PlayersPage and PlayersPage.Frame then
            if not MobileButtonsContainer or not MobileButtonsContainer.Parent then
                MobileButtonsContainer = Create("Frame", {
                    Name = "ButtonsContainer", Parent = PlayersPage.Frame,
                    BackgroundTransparency = 1, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, ActionHeight), Position = UDim2.new(0, 0, 0, 0),
                    ZIndex = SETTINGS_BASE_ZINDEX + 1,
                })
            end
            MobileButtonsContainer.Size = UDim2.new(1, 0, 0, ActionHeight)
            MobileButtonsContainer.Position = UDim2.new(0, 0, 0, 0)
            MobileActionButtons.Reset.Parent = MobileButtonsContainer
            MobileActionButtons.Leave.Parent = MobileButtonsContainer
            MobileActionButtons.Resume.Parent = MobileButtonsContainer
            if VoiceActive then VoiceChatButton.Parent = MobileButtonsContainer end
        end

        local ActionButtons = {MobileActionButtons.Leave, MobileActionButtons.Reset, MobileActionButtons.Resume}
        if VoiceActive then table.insert(ActionButtons, VoiceChatButton) end
        local ButtonCount = #ActionButtons
        local Fraction = 1 / math.max(1, ButtonCount)
        for Index, Button in ipairs(ActionButtons) do
            Button.ZIndex = SETTINGS_BASE_ZINDEX + 4
            Button.Visible = Button ~= VoiceChatButton or VoiceActive
            if Button == VoiceChatButton then
                Button.AnchorPoint = Vector2.new(0, 0)
                Button.Size = UDim2.new(Fraction, -4, 0, ActionHeight)
                Button.Position = UDim2.new((Index - 1) * Fraction, 2, 0, 0)
                Button.ClipsDescendants = true
                local Icon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
                if Icon then
                    Icon.Visible = true
                    Icon.AnchorPoint = Vector2.new(0.5, 0.5)
                    Icon.Size = UDim2.fromOffset(36, 36)
                    Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
                    pcall(function() Icon.ScaleType = Enum.ScaleType.Fit end)
                end
            else
                Button.AnchorPoint = Vector2.new(0, 0)
                Button.Size = UDim2.new(Fraction, -4, 0, ActionHeight)
                Button.Position = UDim2.new((Index - 1) * Fraction, 2, 0, 0)
                for _, Child in ipairs(Button:GetChildren()) do
                    if Child:IsA("ImageLabel") then Child.Visible = false end
                end
                local Label = Button:FindFirstChild(Button.Name .. "TextLabel")
                if Label then
                    Label.TextSize = 18
                    Label.TextWrapped = true
                    Label.TextScaled = true
                    local LabelConstraint = Label:FindFirstChildOfClass("UITextSizeConstraint")
                    if LabelConstraint then
                        LabelConstraint.MinTextSize = 15
                        LabelConstraint.MaxTextSize = 18
                    else
                        Create("UITextSizeConstraint", {Parent = Label, MinTextSize = 15, MaxTextSize = 18})
                    end
                    Label.TextXAlignment = Enum.TextXAlignment.Center
                    Label.TextYAlignment = Enum.TextYAlignment.Center
                    Label.Position = UDim2.new(0, 0, 0, 0)
                    Label.Size = UDim2.new(1, 0, 1, -6)
                end
            end
        end

        if IsTablet then
            Hub.BottomButtonFrame.Parent = Hub.MenuContainer
            Hub.BottomButtonFrame.Visible = Hub.Visible and not Hub.InInviteMenu and not Hub.InConfirmation
            Hub.BottomButtonFrame.Size = UDim2.new(1, 0, 0, ActionHeight)
            Hub.BottomButtonFrame.Position = UDim2.new(0, 0, 1, -ActionHeight)
            Hub.BottomButtonFrame.ZIndex = SETTINGS_BASE_ZINDEX + 6
            Hub.BottomButtonFrame.ClipsDescendants = false
        else
            Hub.BottomButtonFrame.Visible = false
        end
    else
        -- PC desktop: keep the existing action geometry and reserve space for the mic.
        local FrameWidth = tonumber(Hub.BottomButtonFrame.AbsoluteSize.X) or 0
        if FrameWidth <= 0 then FrameWidth = Hub.BottomButtonFrame.Size.X.Offset end
        if FrameWidth <= 0 then FrameWidth = 800 end
        local FrameHeight = 70
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
            pcall(function() VoiceChatIcon.ScaleType = Enum.ScaleType.Fit end)
        end
    end
end


-- One-time low-noise capability diagnostic (no device names or private mic data).
Spawn(function()
	Wait(2)
	local Mode = GetVoiceAudioApiEnabled()
	local ModeText = Mode == true and "Enabled" or (Mode == false and "Automatic/Disabled" or "unreadable")
	local LocalInput = GetVoiceMeterInput(LocalPlayer)
	local LocalAnalyzer = LocalInput and EnsureVoiceMeterAnalyzer(LocalPlayer) or nil
	local LocalWireConnected = false
	local LocalWire = VoiceAnalyzerWires[LocalPlayer]
	if LocalWire and LocalWire.Parent then pcall(function() LocalWireConnected = LocalWire.Connected == true end) end
	local RemoteInputs, RemoteWires = 0, 0
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= LocalPlayer then
			local Input = GetVoiceMeterInput(Player)
			if Input then
				RemoteInputs += 1
				local Analyzer = VoiceAnalyzers[Player]
				local Wire = VoiceAnalyzerWires[Player]
				local Connected = false
				if Wire and Wire.Parent then pcall(function() Connected = Wire.Connected == true end) end
				if Analyzer and Connected then RemoteWires += 1 end
			end
		end
	end
	print(string.format("[Settings2016 Voice Meter] AudioAPI=%s | LocalInput=%s | LocalAnalyzer=%s | LocalWire=%s | RemoteInputs=%d | RemoteWiredAnalyzers=%d", ModeText, LocalInput and "found" or "missing", LocalAnalyzer and "created" or "missing", LocalWireConnected and "connected" or "disconnected/missing", RemoteInputs, RemoteWires))
end)

-- ============================================================
-- RESET BUTTON AVAILABILITY WATCH
-- ============================================================
Spawn(function()
	-- Capture this run's GUI; do not let reruns keep the previous worker alive.
	local WorkerScreenGui = ScreenGui
	while WorkerScreenGui and WorkerScreenGui.Parent do
		ApplyResetButtonAvailability()
		Wait(0.25)
	end
end)

-- Meter discovery is handled by VoiceMeterDiscoveryWorkerStarted above; do not run a second scanner.

VoiceAutoReconnectStamp = 0

-- PeakLevel changes much faster than the GUI refresh loop. Keep the bottom
-- microphone icon on a fast sampling loop so it follows live microphone peaks.
Spawn(function()
	-- Capture this run's GUI; do not let reruns keep the previous worker alive.
	local WorkerScreenGui = ScreenGui
	while WorkerScreenGui and WorkerScreenGui.Parent do
		if VoiceOptionAvailable == true and VoiceChatButton and VoiceChatButton.Parent then
			LocalVoiceMuted = GetLocalVoiceMuted()
			local Icon = VoiceChatButton:FindFirstChildWhichIsA("ImageLabel", true)
			if Icon then
				local Image = VoiceContrastIcon(GetVoiceIcon(LocalPlayer))
				if Icon.Image ~= Image then Icon.Image = Image end
			end
		end
		Wait(0.016)
	end
end)

Spawn(function()
	-- Capture this run's GUI; do not let reruns keep the previous worker alive.
	local WorkerScreenGui = ScreenGui
	while WorkerScreenGui and WorkerScreenGui.Parent do
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
        if VoiceGameSupported then
            RefreshNativeVoiceMirrorCache(false)
        end
        local Changed = RefreshVoiceParticipants()
		if Changed and RebuildPlayersPage then RebuildPlayersPage() end

		if VoiceChatButton and VoiceChatButton.Parent then
			local VoiceActive = VoiceOptionAvailable == true and VoiceChatButton ~= nil and not VOICE_CHAT_FORCE_OFF
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
					local BeforeVoice = HasConfirmedPlayerVoice(Player)
					CheckVoiceForPlayer(Player)
					local HasVoice = HasConfirmedPlayerVoice(Player)
					if BeforeVoice ~= HasVoice then
						if RebuildPlayersPage then RebuildPlayersPage() end
						break
                    elseif VoiceButton then
                        VoiceButton.Visible = HasVoice
                        RefreshRemoteVoiceButton(Player)
                    end
				end
			end
		end

			Wait(1.0)
		end
	end)

-- Refresh visible player-row mic meters at 30 Hz; only cached analyser/event values are read here.
Spawn(function()
	-- Capture this run's GUI; do not let reruns keep the previous worker alive.
	local WorkerScreenGui = ScreenGui
	while WorkerScreenGui and WorkerScreenGui.Parent do
		if VoiceGameSupported and Hub and Hub.Visible and PlayersPage and PlayersPage.Frame then
			for _, Player in next, Players:GetPlayers() do
				if Player ~= LocalPlayer then
					local UserId = tonumber(Player.UserId or Player.userId) or 0
					local Row = PlayersPage.Frame:FindFirstChild("PlayerLabel" .. Player.Name)
					local VoiceButton = Row and Row:FindFirstChild(Player.Name .. "VoiceButton")
					local VoiceIcon = VoiceButton and VoiceButton:FindFirstChild("VoiceIcon")
                    if VoiceIcon then
                        RefreshRemoteVoiceButton(Player)
                    end
				end
			end
		end
		Wait(1 / 30)
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
	local AudioApiMode = GetVoiceAudioApiEnabled()
	-- Remote inputs are evidence only when the rollout is explicitly Enabled.
	-- Preserve the local connection path if rollout state is merely unreadable.
	if Owner ~= LocalPlayer and AudioApiMode ~= true then return end
	if Owner == LocalPlayer and AudioApiMode == false then return end
	GetAudioDeviceInputCache[Owner] = Descendant
	if Owner == LocalPlayer then
		if VoiceChatDesiredOn and IsLocalVoiceConnectionReady() then
			VoiceChatEnabled = true
			RefreshLocalVoiceState()
		end
	else
		local UserId = tonumber(Owner.UserId or Owner.userId) or 0
		if IsConfirmedRemoteVoiceInput(Owner, Descendant) then
			VoiceEnabledCache[UserId] = true
			VoiceCheckError[UserId] = nil
			local Override = VoiceMutedPlayers[UserId]
			if Override ~= nil then
				SetRemoteVoiceMuted(Owner, Override)
			elseif VoiceMuteAllActive then
				SetRemoteVoiceMuted(Owner, true)
			end
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
		-- Remote AudioDeviceInput children only confirm eligibility when Roblox has
		-- explicitly enabled the modern Audio API for this client.
		if GetVoiceAudioApiEnabled() ~= true then return end
		GetAudioDeviceInputCache[Player] = Child
		VoiceMeterInputCache[Player] = nil
		VoiceEligibilityQueryStamp[Player.UserId] = nil
		if IsConfirmedRemoteVoiceInput(Player, Child) then
			VoiceEnabledCache[Player.UserId] = true
			local Override = VoiceMutedPlayers[Player.UserId]
			if Override ~= nil then SetRemoteVoiceMuted(Player, Override)
			elseif VoiceMuteAllActive then SetRemoteVoiceMuted(Player, true) end
			EnsureVoiceAnalyzer(Player, Child)
			if RebuildPlayersPage then RebuildPlayersPage() end
		end
	end)
end

for _, Player in ipairs(Players:GetPlayers()) do
	WatchVoicePlayerAudio(Player)
end

Connect(Players.PlayerAdded, function(Player)
	local UserId = tonumber(Player.UserId) or 0
	VoiceCompatibleCache[UserId] = nil
	VoiceEnabledCache[UserId] = nil
	VoiceCheckError[UserId] = nil
	VoiceEligibilityQueryStamp[UserId] = nil
	VoiceActivityPeak[UserId] = nil
	VoiceActivityStamp[UserId] = nil
	VoiceActivityPeakMeasured[UserId] = nil
	VoiceActivityActive[UserId] = nil
	VoiceActivitySpeakingState[UserId] = nil
	VoiceActivitySpeakingStateStamp[UserId] = nil
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
	VoiceCompatibleCache[UserId] = nil
	VoiceEnabledCache[UserId] = nil
	VoiceEligibilityQueryStamp[UserId] = nil
	VoiceActivityPeak[UserId] = nil
	VoiceActivityStamp[UserId] = nil
	VoiceActivityPeakMeasured[UserId] = nil
	VoiceActivityActive[UserId] = nil
	VoiceActivitySpeakingState[UserId] = nil
	VoiceActivitySpeakingStateStamp[UserId] = nil
	NativeVoiceIconObjects[UserId] = nil
	NativeVoiceIconImages[UserId] = nil
	NativeVoiceIconLastImages[UserId] = nil
    DisconnectNativeVoiceIconConnections(UserId)
    NativeVoiceIconConnectedObjects[UserId] = nil
	if RebuildPlayersPage then task.defer(RebuildPlayersPage) end
end)

if VoiceChatInternal then
	Protect(function()
		Connect(VoiceChatInternal.ParticipantsStateChanged, function(ParticipantsLeft, ParticipantsJoined, UpdatedStates)
			if not VoiceGameSupported then return end
			-- In legacy/Automatic mode, use the event's explicit participantsJoined
			-- payload. GetParticipants() snapshots can include non-voice/group entries.
			local Changed = false
			if type(ParticipantsLeft) == "table" then
				if VoiceConsumeLeftParticipants(ParticipantsLeft) then Changed = true end
			end
			if type(ParticipantsJoined) == "table" then
				if VoiceConsumeJoinedParticipants(ParticipantsJoined) then Changed = true end
			end
			if RefreshVoiceParticipants() then Changed = true end
			if Changed and RebuildPlayersPage then RebuildPlayersPage() end
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
			if type(SpeakingOrInfo) == "boolean" then
				-- A separate boolean argument is the current event state; it must win over
				-- stale activity flags copied from the payload table.
				Payload.isSpeaking = SpeakingOrInfo
			elseif type(SpeakingOrInfo) == "number" then
				Payload.peakLevel = SpeakingOrInfo
			elseif type(SpeakingOrInfo) == "table" then
				for Key, Value in next, SpeakingOrInfo do if Payload[Key] == nil then Payload[Key] = Value end end
			end
			if type(PeakValue) == "number" then
				local ExistingPeak = tonumber(Payload.peakLevel or Payload.PeakLevel or Payload.peak or Payload.Peak or Payload.level or Payload.Level)
				local ExplicitlyInactive = Payload.isSpeaking == false or Payload.IsSpeaking == false or Payload.active == false or Payload.Active == false
				-- Preserve a positive measured peak unless the event explicitly reports inactivity.
				if PeakValue > 0 or ExistingPeak == nil or ExistingPeak <= 0 or ExplicitlyInactive then
					Payload.peakLevel = PeakValue
				end
			end
			if Payload.isSpeaking == false or Payload.IsSpeaking == false or Payload.active == false or Payload.Active == false then
				Payload.peakLevel = 0
			end
			VoiceProcessActivityInfo(Payload, false)
		end)
	end)
end


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
		if RefreshVoiceBetaBadgeVisibility then RefreshVoiceBetaBadgeVisibility() end

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
				SystemMenuHitbox.Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX() - 4, SYSTEM_MENU_OFFSET_Y - 4)
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
				SystemMenuButton.Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX(), SYSTEM_MENU_OFFSET_Y)
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
				if RefreshVoiceBetaBadgeVisibility then RefreshVoiceBetaBadgeVisibility() end
				if SystemMenuHitbox then
					SystemMenuHitbox.Visible = true
					SystemMenuHitbox.Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX() - 4, SYSTEM_MENU_OFFSET_Y - 4)
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
						if RefreshVoiceBetaBadgeVisibility then RefreshVoiceBetaBadgeVisibility() end
						SetRecorderOverlayVisibility(true)
						-- Keep the invisible 40x40 shield permanently over the native top-left button.
						if SystemMenuHitbox then
							SystemMenuHitbox.Visible = true
							SystemMenuHitbox.Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX() - 4, SYSTEM_MENU_OFFSET_Y - 4)
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
			Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX(), SYSTEM_MENU_OFFSET_Y),
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
		Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX() - 4, SYSTEM_MENU_OFFSET_Y - 4),
		Visible = false,
		ZIndex = SETTINGS_BASE_ZINDEX + 102,
	}
)
Insert(Data.Objects, SystemMenuHitbox)

NativeSystemMenuButtonCache = NativeSystemMenuButtonCache or {}
NativeSystemMenuButtonCacheInitialized = NativeSystemMenuButtonCacheInitialized or false
NativeSystemMenuReference = NativeSystemMenuReference or nil

-- Find Roblox's own top-bar close/menu control, anchored to the same branch as
-- ChatIcon. The native control may live in LegacyCloseFrame or a similarly named
-- close container, so discovery checks children of LeftFrame.Parent instead of
-- hard-coding one fragile full path.
FindNativeSystemMenuReference =
	function()
		if NativeSystemMenuReference and NativeSystemMenuReference.Parent then
			return NativeSystemMenuReference
		end

		local TopBarRoot = CoreGui:FindFirstChild("TopBarApp")
		local App = TopBarRoot and (TopBarRoot:FindFirstChild("TopBarApp") or TopBarRoot)
		local TopBarFrame = App and App:FindFirstChild("TopBarFrame", true)
		if not TopBarFrame then return nil end

		local ChatIcon = TopBarFrame:FindFirstChild("ChatIcon", true)
		local LeftFrame = ChatIcon and ChatIcon.Parent
		local SearchRoot = (LeftFrame and LeftFrame.Parent) or TopBarFrame
		local BestButton = nil
		local BestSizeDifference = math.huge
		local TargetSize = 30

		local function ConsiderButton(Button)
			if not Button or not Button:IsA("GuiButton") then return end
			local Size = Button.AbsoluteSize
			if not Size or Size.X <= 0 or Size.Y <= 0 then return end
			local Difference = math.abs(Size.X - TargetSize) + math.abs(Size.Y - TargetSize)
			if Difference < BestSizeDifference then
				BestButton = Button
				BestSizeDifference = Difference
			end
		end

		local function SearchCloseContainer(Container)
			if not Container then return end
			local FrameContainer = Container:FindFirstChild("Frame", true)
			local SearchContainer = FrameContainer and FrameContainer:IsA("GuiObject") and FrameContainer or Container
			if SearchContainer:IsA("GuiButton") then ConsiderButton(SearchContainer) end
			for _, Descendant in ipairs(SearchContainer:GetDescendants()) do
				ConsiderButton(Descendant)
			end
		end

		-- First honor the requested LegacyCloseFrame / close-child pattern.
		for _, Child in ipairs(SearchRoot:GetChildren()) do
			local LowerName = string.lower(Child.Name)
			local HasClose = LowerName:find("close", 1, true) ~= nil or Child:FindFirstChild("Close") ~= nil
			local FrameNode = Child:FindFirstChild("Frame", true)
			if HasClose and (FrameNode or Child:IsA("Frame")) then
				SearchCloseContainer(Child)
			end
		end

		-- Fallback for client builds where the close frame is nested one level deeper.
		if not BestButton then
			for _, Descendant in ipairs(SearchRoot:GetDescendants()) do
				local LowerName = string.lower(Descendant.Name)
				local HasClose = LowerName:find("legacycloseframe", 1, true) ~= nil
						or (LowerName:find("close", 1, true) ~= nil and Descendant:FindFirstChild("Frame", true) ~= nil)
				if HasClose then SearchCloseContainer(Descendant) end
			end
		end

		-- Reject distant-size matches rather than accidentally locking onto an unrelated
		-- close button. If Roblox changes dimensions, the existing position remains safe.
		if BestButton and BestSizeDifference <= 2 then
			NativeSystemMenuReference = BestButton
			return BestButton
		end
		return nil
	end

GetNativeSystemMenuPosition =
	function()
		local Reference = FindNativeSystemMenuReference and FindNativeSystemMenuReference()
		if not Reference or not Reference.Parent then return nil end
		local Position = Reference.AbsolutePosition
		if not Position then return nil end
		return Position
	end

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
		local NativePosition = GetNativeSystemMenuPosition and GetNativeSystemMenuPosition()
		local CustomParentOrigin = Vector2.new(0, 0)
		if SystemMenuButton.Parent and SystemMenuButton.Parent:IsA("GuiObject") then
			CustomParentOrigin = SystemMenuButton.Parent.AbsolutePosition
		end
		local AlignedPosition = NativePosition
			and UDim2.fromOffset(NativePosition.X - CustomParentOrigin.X, NativePosition.Y - CustomParentOrigin.Y)
			or UDim2.fromOffset(GetSystemMenuButtonOffsetX(), SYSTEM_MENU_OFFSET_Y)
		if SystemMenuHitbox then
			SystemMenuHitbox.Visible = true
			SystemMenuHitbox.Size = UDim2.fromOffset(40, 40)
			if IsMobile and NativePosition then
				-- Center the 40x40 touch target over the native 30x30 visual button.
				SystemMenuHitbox.Position = UDim2.fromOffset(NativePosition.X - 5, NativePosition.Y - 5)
			else
				SystemMenuHitbox.Position = UDim2.fromOffset(GetSystemMenuButtonOffsetX() - 4, SYSTEM_MENU_OFFSET_Y - 4)
			end
		end

		if Hub.Visible then
			SystemMenuButton.Position = AlignedPosition
			SystemMenuButton.Size = UDim2.fromOffset(30, 30)
			pcall(function()
				SystemMenuButton.ImageTransparency = 0
			end)
		else
			-- While closing, preserve the normal visible 30x30 button. After the
			-- tween completes, SetVisibility hides the visual button permanently.
			if SystemMenuButtonClosing then
				SystemMenuButton.Position = AlignedPosition
				SystemMenuButton.Size = UDim2.fromOffset(30, 30)
				pcall(function()
					SystemMenuButton.ImageTransparency = 0
				end)
				SystemMenuButton.Visible = true
			else
				SystemMenuButton.Position = AlignedPosition
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
	-- Capture the original button so this worker ends when this run is cleaned up.
	local WorkerSystemMenuButton = SystemMenuButton
	while WorkerSystemMenuButton and WorkerSystemMenuButton.Parent do
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
		if NewInviteShareRow then NewInviteShareRow.Visible = false end
		if INVITE_MOBILE_HEADER_DIVIDER then INVITE_MOBILE_HEADER_DIVIDER.Visible = false end
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

RegisterMenuLocalizationTree(ScreenGui)
RegisterMenuLocalizationTree(VoiceBetaBadgeRoot)
SetTopBarAppEnabled(true)
SwitchToPage(GamePage, true, true)
ConfigureMobileActionButtons()
ResizeHub()
ConfigureMobileActionButtons()
ApplyMobileTextSizing(ScreenGui)
if VOICE_CHAT_FORCE_OFF then
    -- Do this after all voice controls and internal helpers exist. The guard in
    -- SetVoiceChatPreference keeps this forced-off if any later callback runs.
    SetVoiceChatPreference(false)
elseif VoiceOptionAvailable and SetVoiceChatPreference then
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
