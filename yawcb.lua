-- YAWCB recolors Blizzard's cast bars. It does not draw its own bar or run
-- an OnUpdate, so the cast timer stays Blizzard's.
--
-- Two profiles live in YAWCBDB. "player" is the player cast bar. "nameplate"
-- is the target spell bar and every other nameplate cast bar. Each profile
-- has a mode (default, class, a class token, or custom) and a custom color.
--
-- The fill texture is already painted by Blizzard. Paint desaturates that
-- texture and tints it, so the shape stays and the chosen color shows.
-- Blizzard then sets the fill back to white, and HookColorReset paints again.

local addonName = ...

-- DEFAULT_COLOR is the custom swatch until the player picks one.
-- The settings control stores AARRGGBB.
local DEFAULT_COLOR = "ffffb300"

-- CLASS_ORDER is the classic class list, stopping at Druid.
local CLASS_ORDER = {
	"WARRIOR",
	"PALADIN",
	"HUNTER",
	"ROGUE",
	"PRIEST",
	"SHAMAN",
	"MAGE",
	"WARLOCK",
	"DRUID",
}

-- BARS is the settings and saved-variable layout for both profiles.
-- modeKey and colorKey are fields on YAWCBDB. The variable names are the
-- settings panel ids.
local BARS = {
	{
		kind = "player",
		title = "Player cast bar",
		modeKey = "mode",
		colorKey = "color",
		modeVariable = "YAWCB_MODE",
		colorVariable = "YAWCB_CAST_COLOR",
		modeLabel = "Player bar color",
		colorLabel = "Player custom color",
	},
	{
		kind = "nameplate",
		title = "Enemy cast bars",
		modeKey = "nameplateMode",
		colorKey = "nameplateColor",
		modeVariable = "YAWCB_NAMEPLATE_MODE",
		colorVariable = "YAWCB_NAMEPLATE_COLOR",
		modeLabel = "Enemy bar color",
		colorLabel = "Enemy custom color",
	},
}

local category
local hookedMixin = false
local hookedNameplateMixin = false

-- PlayerBar returns the player cast bar. The client exposes one of these names.
local function PlayerBar()
	return PlayerCastingBarFrame or CastingBarFrame
end

-- IsForbidden reports whether a nameplate frame is tainted and must be left alone.
local function IsForbidden(frame)
	return frame and frame.IsForbidden and frame:IsForbidden()
end

-- PlainString returns value when it is an ordinary string.
-- Unit tokens can be secret values in combat, and those cannot be compared.
local function PlainString(value)
	if type(value) ~= "string" then
		return nil
	end
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

-- NameplateOf returns the nameplate that owns bar, or nil when bar is some
-- other status bar. The chain is plate -> UnitFrame -> castBar.
local function NameplateOf(bar)
	if IsForbidden(bar) then
		return nil
	end
	local parent = bar:GetParent()
	if not parent or IsForbidden(parent) or parent.castBar ~= bar then
		return nil
	end
	local plate = parent:GetParent()
	if not plate or IsForbidden(plate) or plate.UnitFrame ~= parent then
		return nil
	end
	return plate
end

-- IsPlayerBar reports whether bar should use the player color.
-- That is the player cast bar, a bar whose unit is "player", or the personal nameplate.
local function IsPlayerBar(bar)
	if not bar or IsForbidden(bar) then
		return false
	end
	if bar == PlayerCastingBarFrame or bar == CastingBarFrame then
		return true
	end

	local unit = PlainString(bar.unit)
	if unit == "player" then
		return true
	end

	local plate = NameplateOf(bar)
	if plate and C_NamePlate and C_NamePlate.GetNamePlateForUnit and plate == C_NamePlate.GetNamePlateForUnit("player") then
		return true
	end

	local parent = bar:GetParent()
	if parent and not IsForbidden(parent) and PlainString(parent.unit) == "player" then
		return true
	end
	return false
end

-- KindFor returns "player", "nameplate", or nil.
-- "nameplate" covers the target spell bar and enemy nameplate cast bars.
-- Nil means this status bar is not a cast bar we recolor.
local function KindFor(bar)
	if not bar or IsForbidden(bar) then
		return nil
	end
	if IsPlayerBar(bar) then
		return "player"
	end
	if bar == TargetFrameSpellBar then
		return "nameplate"
	end

	local unit = PlainString(bar.unit)
	if unit == "target" or (unit and unit:match("^nameplate")) then
		return "nameplate"
	end

	local plate = NameplateOf(bar)
	if plate then
		return "nameplate"
	end
end

-- Profile returns the BARS entry for kind.
local function Profile(kind)
	for _, profile in ipairs(BARS) do
		if profile.kind == kind then
			return profile
		end
	end
end

-- NormalizeHex turns a color code into AARRGGBB.
-- A 6-digit code is RGB and gets a full alpha prefix. Anything else is ignored.
local function NormalizeHex(value)
	if type(value) ~= "string" then
		return nil
	end
	local hex = value:gsub("#", ""):lower()
	if #hex == 6 then
		hex = "ff" .. hex
	end
	if #hex ~= 8 or not hex:match("^%x+$") then
		return nil
	end
	return hex
end

-- CustomRGB returns the saved swatch for colorKey as r, g, b.
-- A missing or bad code uses DEFAULT_COLOR.
local function CustomRGB(colorKey)
	local hex = NormalizeHex(YAWCBDB and YAWCBDB[colorKey]) or DEFAULT_COLOR
	local color = CreateColorFromHexString(hex) or CreateColorFromHexString(DEFAULT_COLOR)
	return color:GetRGB()
end

-- ClassColor returns the class color for classFile as r, g, b.
local function ClassColor(classFile)
	if type(classFile) ~= "string" or classFile == "" then
		return nil
	end

	local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
	if not color and RAID_CLASS_COLORS then
		color = RAID_CLASS_COLORS[classFile]
	end
	if not color then
		return nil
	end
	if color.GetRGB then
		return color:GetRGB()
	end
	return color.r, color.g, color.b
end

-- WrapClassText colors text with the class color for the settings dropdown.
local function WrapClassText(classFile, text)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color and color.WrapTextInColorCode then
		return color:WrapTextInColorCode(text)
	end
	return text
end

-- BarMode returns the saved mode for kind. An empty save means "class".
local function BarMode(kind)
	local profile = Profile(kind)
	if not profile or not YAWCBDB then
		return "class"
	end
	return YAWCBDB[profile.modeKey] or "class"
end

-- ResolvedRGB returns the r, g, b to paint for kind.
-- "default" returns nil so the caller leaves Blizzard's colors in place.
-- "class" uses the player's class. A class token uses that class.
-- Nil also means the class color is not available yet, so the bar is left alone.
local function ResolvedRGB(kind)
	local profile = Profile(kind)
	if not profile then
		return nil
	end

	local mode = BarMode(kind)
	if mode == "default" then
		return nil
	end

	if mode == "custom" then
		return CustomRGB(profile.colorKey)
	end

	local classFile = mode
	if mode == "class" then
		classFile = select(2, UnitClass("player"))
	end

	local r, g, b = ClassColor(classFile)
	if r then
		return r, g, b
	end

	return ClassColor(select(2, UnitClass("player")))
end

-- recoloring stops Paint and the color hook from calling each other.
local recoloring = false

-- STANDARD_FILL is the player cast bar's fill atlas.
-- Enemy bars get this texture so they tint the same way the player bar does.
local STANDARD_FILL = "ui-castingbar-filling-standard"

-- FillTexture returns the status bar texture that gets desaturated and tinted.
local function FillTexture(bar)
	if bar.GetStatusBarTexture then
		return bar:GetStatusBarTexture()
	end
end

-- Undesaturate puts a texture back to Blizzard's own color.
local function Undesaturate(tex)
	if not tex then
		return
	end
	if tex.SetDesaturated then
		tex:SetDesaturated(false)
	end
	if tex.SetVertexColor then
		tex:SetVertexColor(1, 1, 1, 1)
	end
end

-- Paint tints bar's fill to r, g, b and stores that color on the bar.
-- The spell icon, spark, flash, and interrupt shield are put back to white
-- so only the fill changes. Enemy bars are switched onto STANDARD_FILL first.
local function Paint(bar, r, g, b)
	if recoloring or not bar or IsForbidden(bar) or not r then
		return
	end
	recoloring = true
	pcall(function()
		bar.yawcbR, bar.yawcbG, bar.yawcbB = r, g, b
		if bar.SetStatusBarDesaturated then
			bar:SetStatusBarDesaturated(false)
		end

		local kind = KindFor(bar)
		if kind == "nameplate" then
			bar:SetStatusBarTexture(STANDARD_FILL)
		end

		local tex = FillTexture(bar)
		if tex then
			tex:SetDesaturated(true)
		end
		-- SetStatusBarColor replaces the texture tint, so the vertex color comes after it.
		bar:SetStatusBarColor(r, g, b, 1)
		if tex then
			tex:SetVertexColor(r, g, b, 1)
		end

		Undesaturate(bar.Icon)
		Undesaturate(bar.Spark)
		Undesaturate(bar.Flash)
		Undesaturate(bar.BorderShield)
	end)
	recoloring = false
end

-- RestoreBar clears our tint and asks Blizzard to draw the fill again.
-- yawcbR is cleared first so the color hook does not paint back over the restore.
local function RestoreBar(bar)
	if not bar or IsForbidden(bar) or bar.yawcbRestoring then
		return
	end
	bar.yawcbR, bar.yawcbG, bar.yawcbB = nil, nil, nil
	bar.yawcbRestoring = true
	pcall(function()
		if bar.SetStatusBarDesaturated then
			bar:SetStatusBarDesaturated(false)
		end
		Undesaturate(FillTexture(bar))
		Undesaturate(bar.Icon)
		Undesaturate(bar.Spark)
		Undesaturate(bar.Flash)
		if bar.UpdateBarFillTexture then
			bar:UpdateBarFillTexture(false)
		end
		if bar.UpdateIconShown then
			bar:UpdateIconShown()
		end
	end)
	bar.yawcbRestoring = false
end

-- HookColorReset watches SetStatusBarColor on one bar.
-- Blizzard sets the fill to white after choosing its atlas. When that happens
-- and this bar still has a saved tint, Paint runs again.
local function HookColorReset(bar)
	if not bar or bar.yawcbColorHooked or IsForbidden(bar) then
		return
	end
	hooksecurefunc(bar, "SetStatusBarColor", function(self, cr, cg, cb)
		if recoloring or not self.yawcbR then
			return
		end
		local secret = issecretvalue and (issecretvalue(cr) or issecretvalue(cg) or issecretvalue(cb))
		if not secret and math.abs((cr or 0) - self.yawcbR) < 0.02 and math.abs((cg or 0) - self.yawcbG) < 0.02 and math.abs((cb or 0) - self.yawcbB) < 0.02 then
			return
		end
		Paint(self, self.yawcbR, self.yawcbG, self.yawcbB)
	end)
	bar.yawcbColorHooked = true
end

-- Apply paints bar from its profile. A "default" profile is a no-op here;
-- ApplyKind restores those bars instead.
local function Apply(bar)
	if recoloring or not bar or bar.yawcbRestoring then
		return
	end

	local kind = KindFor(bar)
	if not kind then
		return
	end
	if BarMode(kind) == "default" then
		return
	end

	local r, g, b = ResolvedRGB(kind)
	if not r then
		return
	end

	HookColorReset(bar)
	Paint(bar, r, g, b)
end

-- EachEnemyBar calls callback for the target spell bar and every enemy
-- nameplate cast bar. The personal nameplate is skipped.
local function EachEnemyBar(callback)
	if TargetFrameSpellBar then
		callback(TargetFrameSpellBar)
	end
	if not C_NamePlate or not C_NamePlate.GetNamePlates then
		return
	end
	local playerPlate = C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		if plate and plate ~= playerPlate and not IsForbidden(plate) then
			local unitFrame = plate.UnitFrame
			if unitFrame and not IsForbidden(unitFrame) and unitFrame.castBar and not IsPlayerBar(unitFrame.castBar) then
				callback(unitFrame.castBar)
			end
		end
	end
end

-- ApplyKind paints every bar of kind, or restores them when the mode is "default".
local function ApplyKind(kind)
	local restore = BarMode(kind) == "default"
	local function Handle(bar)
		if restore then
			RestoreBar(bar)
		else
			Apply(bar)
		end
	end

	if kind == "player" then
		local bar = PlayerBar()
		if bar then
			Handle(bar)
		end
		return
	end

	if kind == "nameplate" then
		EachEnemyBar(Handle)
	end
end

-- ModeOptions builds the color dropdown: default, the player's class,
-- each classic class, then custom.
local function ModeOptions()
	local container = Settings.CreateControlTextContainer()
	container:Add("default", "Default", "The original cast bar colors.")
	local _, playerClass = UnitClass("player")
	local mine = "My class color"
	if playerClass then
		mine = WrapClassText(playerClass, mine)
	end
	container:Add("class", mine)

	for _, classFile in ipairs(CLASS_ORDER) do
		if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
			local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
			container:Add(classFile, WrapClassText(classFile, name))
		end
	end

	container:Add("custom", "Custom", "Use the custom color below.")
	return container:GetData()
end

-- OpenSettings opens this addon's page. /yawcb calls it.
local function OpenSettings()
	if not category or not Settings or not Settings.OpenToCategory then
		return
	end
	Settings.OpenToCategory(category:GetID())
end

-- RegisterSettings builds the two sections in the game settings panel.
-- kind and colorKey are locals inside the loop so each control keeps its own
-- profile. A loop variable would be shared by every callback.
local function RegisterSettings()
	if category or not Settings or not Settings.RegisterVerticalLayoutCategory then
		return
	end

	local stringType = (Settings.VarType and Settings.VarType.String) or "string"
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("YAWCB")

	for _, profile in ipairs(BARS) do
		local kind = profile.kind
		local colorKey = profile.colorKey
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(profile.title))

		local modeSetting = Settings.RegisterAddOnSetting(category, profile.modeVariable, profile.modeKey, YAWCBDB, stringType, profile.modeLabel, "class")
		modeSetting:SetValueChangedCallback(function()
			ApplyKind(kind)
		end)
		Settings.CreateDropdown(category, modeSetting, ModeOptions, "Your class color, any class color, or a custom color.")

		local colorSetting = Settings.RegisterAddOnSetting(category, profile.colorVariable, colorKey, YAWCBDB, stringType, profile.colorLabel, DEFAULT_COLOR)
		colorSetting:SetValueChangedCallback(function(_, value)
			local hex = NormalizeHex(value)
			if hex then
				YAWCBDB[colorKey] = hex
			end
			-- Changing the mode applies the bar from that callback.
			-- A bar already set to custom would not fire it, so apply here.
			if modeSetting:GetValue() ~= "custom" then
				modeSetting:SetValue("custom")
			else
				ApplyKind(kind)
			end
		end)

		local tooltip = "Pick a color. This bar switches to Custom when you use the swatch."
		local data = Settings.CreateSettingInitializerData(colorSetting, nil, tooltip)
		layout:AddInitializer(Settings.CreateSettingInitializer("SettingsColorSwatchControlTemplate", data))

		-- ResetToDefault sets this profile back to Blizzard's colors.
		-- Setting the mode applies the bar. If it is already default, apply anyway.
		local function ResetToDefault()
			if modeSetting:GetValue() ~= "default" then
				modeSetting:SetValue("default")
			else
				ApplyKind(kind)
			end
		end
		layout:AddInitializer(CreateSettingsButtonInitializer("Reset " .. profile.title, "Reset to default", ResetToDefault, "Put this bar back to the default colors.", true))
	end

	Settings.RegisterAddOnCategory(category)
end

-- TryHook attaches Apply to the cast bar mixins once they exist.
-- Nameplate bars share the player mixin on some clients, and that function
-- is hooked only once. Then both profiles are applied to bars already on screen.
local function TryHook()
	if not hookedMixin and CastingBarMixin and CastingBarMixin.UpdateBarFillTexture then
		hooksecurefunc(CastingBarMixin, "UpdateBarFillTexture", Apply)
		hookedMixin = true
	end

	if not hookedNameplateMixin and NamePlateCastingBarMixin and NamePlateCastingBarMixin.UpdateBarFillTexture then
		if not CastingBarMixin or NamePlateCastingBarMixin.UpdateBarFillTexture ~= CastingBarMixin.UpdateBarFillTexture then
			hooksecurefunc(NamePlateCastingBarMixin, "UpdateBarFillTexture", Apply)
		end
		hookedNameplateMixin = true
	end

	ApplyKind("player")
	ApplyKind("nameplate")
end

-- EnsureDB creates YAWCBDB and fills any missing mode or color.
local function EnsureDB()
	if type(YAWCBDB) ~= "table" then
		YAWCBDB = {}
	end
	for _, profile in ipairs(BARS) do
		if type(YAWCBDB[profile.modeKey]) ~= "string" then
			YAWCBDB[profile.modeKey] = "class"
		end
		if type(YAWCBDB[profile.colorKey]) ~= "string" then
			YAWCBDB[profile.colorKey] = DEFAULT_COLOR
		end
	end
end

-- The event frame loads saved variables, registers settings, and hooks cast
-- bars. Nameplates can load after this addon, so ADDON_LOADED for
-- Blizzard_NamePlates hooks again. Entering the world, gaining a nameplate,
-- or changing target applies the colors to bars that just appeared.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		EnsureDB()
		RegisterSettings()
		if not category and EventUtil and EventUtil.ContinueOnAddOnLoaded then
			EventUtil.ContinueOnAddOnLoaded("Blizzard_Settings", RegisterSettings)
		end
	end

	if event == "ADDON_LOADED" and name ~= addonName and name ~= "Blizzard_NamePlates" then
		return
	end

	TryHook()
end)

SLASH_YAWCB1 = "/yawcb"
SlashCmdList.YAWCB = OpenSettings
