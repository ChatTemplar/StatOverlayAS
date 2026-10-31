-- Stat Overlay for Azeroth Survivors.
-- Reads the character pane's numbers from AZS_STATS (see addon_docs.md) and shows them on screen.
-- /statoverlay opens the options menu.

local ADDON_NAME = "StatOverlay"
local POLL_INTERVAL = 0.2
local FLAT = "Interface\\Buttons\\WHITE8X8"

-- kind (the game's formats, as Survivor UI's character pane reads them):
--   "mult"   a multiplier (1.25 = 125%); shown as a percent
--   "pct"    a chance or share; 0.25 or 25 both shown as 25%
--   "share"  a share sent as a fraction (0.02 = 2%), however large
--   "bonus"  a bonus sent as a fraction, shown with its sign (0.15 = +15%)
--   "yards"  a distance in yards
--   "num"    a plain number
local STAT_DEFS = {
	{ key = "hp",    label = "Max Health",       kind = "num" },
	{ key = "dmg",   label = "Damage",           kind = "mult" },
	{ key = "crit",  label = "Crit Chance",      kind = "pct" },
	{ key = "cm",    label = "Crit Damage",      kind = "mult" },
	{ key = "arm",   label = "Damage Reduction", kind = "pct" },
	{ key = "cd",    label = "Cooldown",         kind = "mult" },
	{ key = "area",  label = "Area of Effect",   kind = "mult" },
	{ key = "cnt",   label = "Extra Targets",    kind = "num" },
	{ key = "echo",  label = "Echo",             kind = "share" },
	{ key = "spd",   label = "Movement Speed",   kind = "mult" },
	{ key = "pick",  label = "Pickup Range",     kind = "yards" },
	{ key = "reg",   label = "Health per Second", kind = "num" },
	{ key = "heal",  label = "Kill Heal",        kind = "num" },
	{ key = "lch",   label = "Lifesteal",        kind = "share" },
	{ key = "thn",   label = "Thorns",           kind = "share" },
	{ key = "liv",   label = "Lives",            kind = "num" },
	{ key = "xp",    label = "Experience",       kind = "mult" },
	{ key = "luck",  label = "Luck",             kind = "bonus" },
	{ key = "gold",  label = "Gold",             kind = "mult" },
	-- The rest of the character pane's numbers, which used to show under
	-- their game keys (bp, dots, big, ...).
	{ key = "bp",    label = "Buff Power",           kind = "bonus" },
	{ key = "dots",  label = "DoT Stacks",           kind = "num" },
	{ key = "doth",  label = "DoT Haste",            kind = "bonus" },
	{ key = "big",   label = "Damage vs Elites",     kind = "bonus" },
	{ key = "exe",   label = "Execute Damage",       kind = "bonus" },
	{ key = "cc",    label = "Damage vs Controlled", kind = "bonus" },
	{ key = "dotd",  label = "Damage vs Afflicted",  kind = "bonus" },
	{ key = "shd",   label = "Shielded Damage",      kind = "bonus" },
	{ key = "auto",  label = "Melee Damage",         kind = "bonus" },
	{ key = "pet",   label = "Pet Damage",           kind = "bonus" },
}

local KNOWN = {}
for i = 1, table.getn(STAT_DEFS) do
	KNOWN[STAT_DEFS[i].key] = true
end

local IN_RUN = { playing = true, choosing = true, paused = true }

local FONTS = {
	{ name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
	{ name = "Skurri",        path = "Fonts\\skurri.ttf" },
	{ name = "Morpheus",      path = "Fonts\\MORPHEUS.ttf" },
}
local FONT_NAMES = {}
for i = 1, table.getn(FONTS) do
	FONT_NAMES[i] = FONTS[i].name
end
local OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE" }
local OUTLINE_NAMES = { "None", "Outline", "Thick Outline" }

local BASIC_COLORS = {
	title  = { 1, 0.82, 0.35, 1 },
	label  = { 0.95, 0.9, 0.7, 1 },
	value  = { 1, 1, 1, 1 },
	status = { 0.7, 0.75, 0.82, 1 },
}

local COMMON_DEFAULTS = {
	style = "basic",
	scale = 1,
	width = 240,
	showTitle = true,
	showStatus = true,
	fetchStats = true,
}

local ELV_DEFAULTS = {
	font = 2,
	fontSize = 12,
	outline = 2,
	rowHeight = 16,
	pad = 6,
	border = 1,
	stripes = true,
	bg          = { 0.06, 0.06, 0.06, 0.85 },
	borderColor = { 0, 0, 0, 1 },
	title       = { 0.25, 0.65, 1, 1 },
	label       = { 0.8, 0.8, 0.8, 1 },
	value       = { 1, 1, 1, 1 },
}

local frame
local menu
local rows = {}
local lastUpdated
local lastPhase
local elapsed = 0
local redraw, refreshMenu, refreshStatList

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------

local function copyColor(c)
	return { c[1], c[2], c[3], c[4] }
end

local function initDB()
	if type(StatOverlayDB) ~= "table" then
		StatOverlayDB = {}
	end
	local cfg = StatOverlayDB
	for k, v in pairs(COMMON_DEFAULTS) do
		if cfg[k] == nil then
			cfg[k] = v
		end
	end
	if type(cfg.hidden) ~= "table" then
		cfg.hidden = {}
	end
	if type(cfg.elv) ~= "table" then
		cfg.elv = {}
	end
	for k, v in pairs(ELV_DEFAULTS) do
		if cfg.elv[k] == nil then
			if type(v) == "table" then
				cfg.elv[k] = copyColor(v)
			else
				cfg.elv[k] = v
			end
		end
	end
	if not FONTS[cfg.elv.font] then
		cfg.elv.font = ELV_DEFAULTS.font
	end
	if not OUTLINES[cfg.elv.outline] then
		cfg.elv.outline = ELV_DEFAULTS.outline
	end
	cfg.showExtra = nil
end

local function db()
	return StatOverlayDB
end

local function isElv()
	return db().style == "elvui"
end

local function say(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffd2a24aStat Overlay:|r " .. msg)
	end
end

---------------------------------------------------------------------------
-- Game data
---------------------------------------------------------------------------

-- The game's stats, while it has sent some.
local function liveStats()
	if type(AZS_STATS) == "table" and next(AZS_STATS) ~= nil then
		return AZS_STATS
	end
	return nil
end

-- A /reload empties AZS_STATS, and the game sends it again only when a stat
-- changes or the character pane opens. Until then, the last stats seen (kept
-- per character) stand in.
local function stats()
	local live = liveStats()
	if live then
		return live
	end
	local kept = StatOverlayDB and StatOverlayDB.lastStats
	return kept and kept[UnitName("player") or "?"]
end

local function keepStats()
	local live = liveStats()
	if not (live and StatOverlayDB) then
		return
	end
	StatOverlayDB.lastStats = StatOverlayDB.lastStats or {}
	local copy = {}
	for key, value in pairs(live) do
		if type(value) ~= "table" then
			copy[key] = value
		end
	end
	StatOverlayDB.lastStats[UnitName("player") or "?"] = copy
end

-- And the game is asked for them: opening the character pane makes it send
-- its stats, so after a reload the pane is opened and shut at once, quietly,
-- if they are still missing. Twice at most, never while the pane is open.
local fetchAt, fetchTries

local function fetchStats()
	if liveStats() or not (StatOverlayDB and StatOverlayDB.fetchStats) then
		return
	end
	if not (ToggleCharacter and CharacterFrame and AZS_GetPhase) or CharacterFrame:IsShown() then
		return
	end
	local play = PlaySound
	PlaySound = function() end
	pcall(ToggleCharacter, "PaperDollFrame")
	if CharacterFrame:IsShown() then
		pcall(ToggleCharacter, "PaperDollFrame")
	end
	PlaySound = play
end

local function phase()
	if type(AZS_GetPhase) == "function" then
		return AZS_GetPhase()
	end
	return nil
end

-- A trailing ".0" is noise; keep one decimal otherwise.
local function fmtNum(v)
	if math.abs(v - math.floor(v + 0.5)) < 0.05 then
		return string.format("%d", math.floor(v + 0.5))
	end
	return string.format("%.1f", v)
end

local function formatValue(v, kind)
	if v == nil then
		return "--"
	end
	if type(v) ~= "number" then
		return tostring(v)
	end
	if db().raw then
		return tostring(v)
	end
	if kind == "mult" then
		-- Multipliers arrive as ratios (1.25); anything large is already a percent.
		if math.abs(v) < 20 then
			v = v * 100
		end
		return fmtNum(v) .. "%"
	elseif kind == "pct" then
		if math.abs(v) < 1 then
			v = v * 100
		end
		return fmtNum(v) .. "%"
	elseif kind == "share" then
		return fmtNum(v * 100) .. "%"
	elseif kind == "bonus" then
		local text = fmtNum(v * 100) .. "%"
		if v > 0 then
			text = "+" .. text
		end
		return text
	elseif kind == "yards" then
		return fmtNum(v) .. " yd"
	end
	return fmtNum(v)
end

-- Keys the game sends that this addon has no label for ("and more" in the docs).
-- Gear keys (g + a stat key) are left out; they show in the row tooltips.
local function extraKeys(s)
	local keys = {}
	for k, v in pairs(s) do
		if not KNOWN[k] and type(v) ~= "table" then
			local isGear = string.sub(k, 1, 1) == "g" and s[string.sub(k, 2)] ~= nil
			if not isGear then
				table.insert(keys, k)
			end
		end
	end
	table.sort(keys)
	return keys
end

-- Every stat the player can pick: the labelled ones, then whatever else the game sends.
local function statEntries()
	local list = {}
	for i = 1, table.getn(STAT_DEFS) do
		table.insert(list, { key = STAT_DEFS[i].key, label = STAT_DEFS[i].label, kind = STAT_DEFS[i].kind })
	end
	local s = stats()
	if s then
		local keys = extraKeys(s)
		for i = 1, table.getn(keys) do
			table.insert(list, { key = keys[i], label = keys[i], kind = "num" })
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Overlay look
---------------------------------------------------------------------------

local function textColor(role)
	if isElv() then
		if role == "status" then
			role = "label"
		end
		return db().elv[role]
	end
	return BASIC_COLORS[role]
end

local function styleText(fs, role)
	if isElv() then
		local e = db().elv
		local flags = OUTLINES[e.outline]
		if flags == "NONE" then
			flags = ""
		end
		local size = e.fontSize
		if role == "title" then
			size = size + 1
		end
		fs:SetFont(FONTS[e.font].path, size, flags)
		fs:SetShadowOffset(0, 0)
	else
		local obj = GameFontHighlightSmall
		if role == "title" then
			obj = GameFontNormal
		end
		fs:SetFontObject(obj)
		-- SetFontObject may not undo an earlier SetFont, so copy the font across too.
		if obj.GetFont then
			local path, size, flags = obj:GetFont()
			if path then
				fs:SetFont(path, size, flags)
			end
		end
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	end
	local c = textColor(role)
	fs:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Returns where the rows start, row height, side padding and bottom padding.
local function layout()
	local cfg = db()
	local header = cfg.showTitle or cfg.showStatus
	if isElv() then
		local e = cfg.elv
		if header then
			return e.fontSize + 10, e.rowHeight, e.pad + e.border, e.pad + e.border
		end
		return e.pad + e.border, e.rowHeight, e.pad + e.border, e.pad + e.border
	end
	if header then
		return 24, 16, 10, 8
	end
	return 10, 16, 10, 8
end

local function startMove()
	if not db().locked then
		frame:StartMoving()
	end
end

local function stopMove()
	frame:StopMovingOrSizing()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then
		local cfg = db()
		cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
	end
end

local function styleRow(row)
	styleText(row.label, "label")
	styleText(row.value, "value")
end

local function getRow(index)
	if rows[index] then
		return rows[index]
	end
	local row = CreateFrame("Frame", nil, frame)
	row:EnableMouse(true)

	local stripe = row:CreateTexture(nil, "BACKGROUND")
	stripe:SetAllPoints(row)
	stripe:SetTexture(1, 1, 1, 0.05)
	row.stripe = stripe

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", row, "LEFT", 0, 0)
	label:SetJustifyH("LEFT")
	row.label = label

	local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	value:SetJustifyH("RIGHT")
	row.value = value

	row:SetScript("OnEnter", function()
		local s = stats()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(this.labelText, 1, 0.85, 0.4)
		GameTooltip:AddLine("AZS_STATS." .. this.key .. " = " .. tostring(s and s[this.key]), 0.8, 0.8, 0.8)
		local gear = s and s["g" .. this.key]
		if gear ~= nil then
			GameTooltip:AddLine("From gear: " .. tostring(gear), 0.6, 0.85, 1)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	-- Rows take the mouse for tooltips, so pass drags on to the frame.
	row:SetScript("OnMouseDown", startMove)
	row:SetScript("OnMouseUp", stopMove)

	styleRow(row)
	rows[index] = row
	return row
end

local function setRow(n, entry, text, active)
	local cfg = db()
	local top, rowH, pad = layout()
	local row = getRow(n)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(top + ((n - 1) * rowH)))
	row:SetWidth(cfg.width - (pad * 2))
	row:SetHeight(rowH)
	row.key = entry.key
	row.labelText = entry.label
	row.label:SetText(entry.label .. ":")
	row.value:SetText(text)
	if active then
		local c = textColor("value")
		row.value:SetTextColor(c[1], c[2], c[3], c[4])
	else
		row.value:SetTextColor(0.5, 0.5, 0.5, 1)
	end
	if isElv() and cfg.elv.stripes and math.mod(n, 2) == 0 then
		row.stripe:Show()
	else
		row.stripe:Hide()
	end
	row:Show()
end

local function refresh()
	local cfg = db()
	local s = stats()
	local ph = phase()
	local active = ph and IN_RUN[ph]

	if ph then
		frame.status:SetText(ph)
	else
		frame.status:SetText("no run")
	end

	local list = statEntries()
	local n = 0
	for i = 1, table.getn(list) do
		local entry = list[i]
		if not cfg.hidden[entry.key] then
			n = n + 1
			setRow(n, entry, formatValue(s and s[entry.key], entry.kind), active)
		end
	end

	for i = n + 1, table.getn(rows) do
		rows[i]:Hide()
	end
	local top, rowH, _, bottom = layout()
	frame:SetHeight(top + (n * rowH) + bottom)
end

local function applyStyle()
	local cfg = db()
	local top, _, pad = layout()
	frame:SetScale(cfg.scale)
	frame:SetWidth(cfg.width)

	frame.title:ClearAllPoints()
	frame.status:ClearAllPoints()
	if isElv() then
		local e = cfg.elv
		local b = e.border
		if b > 0 then
			frame:SetBackdrop({
				bgFile = FLAT,
				edgeFile = FLAT,
				edgeSize = b,
				insets = { left = b, right = b, top = b, bottom = b },
			})
		else
			frame:SetBackdrop({ bgFile = FLAT })
		end
		frame:SetBackdropColor(e.bg[1], e.bg[2], e.bg[3], e.bg[4])
		local bc = e.borderColor
		frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])

		frame.line:SetTexture(bc[1], bc[2], bc[3], bc[4])
		frame.line:ClearAllPoints()
		frame.line:SetPoint("TOPLEFT", frame, "TOPLEFT", b, -(top - 4))
		frame.line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -b, -(top - 4))
		frame.line:SetHeight(math.max(b, 1))
		if cfg.showTitle or cfg.showStatus then
			frame.line:Show()
		else
			frame.line:Hide()
		end

		frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(b + 3))
		frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -(b + 4))
	else
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(0.03, 0.03, 0.04, 0.88)
		frame:SetBackdropBorderColor(0.55, 0.55, 0.65, 1)
		frame.line:Hide()
		frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -6)
		frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
	end

	styleText(frame.title, "title")
	styleText(frame.status, "status")
	if cfg.showTitle then
		frame.title:Show()
	else
		frame.title:Hide()
	end
	if cfg.showStatus then
		frame.status:Show()
	else
		frame.status:Hide()
	end

	for i = 1, table.getn(rows) do
		styleRow(rows[i])
	end
end

redraw = function()
	applyStyle()
	refresh()
end

local function applyState()
	local cfg = db()
	frame:ClearAllPoints()
	frame:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.relPoint or "TOPLEFT", cfg.x or 24, cfg.y or -120)
	if cfg.shown == false then
		frame:Hide()
	else
		frame:Show()
	end
end

local function createFrame()
	frame = CreateFrame("Frame", "StatOverlayFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:Hide()

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetText("Stat Overlay")
	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.line = frame:CreateTexture(nil, "ARTWORK")

	frame:SetScript("OnMouseDown", startMove)
	frame:SetScript("OnMouseUp", stopMove)

	-- AZS_STATS_UPDATED is the GetTime() of the table's last change, so polling it is cheap.
	frame:SetScript("OnUpdate", function()
		elapsed = elapsed + arg1
		if elapsed < POLL_INTERVAL then
			return
		end
		elapsed = 0
		local ph = phase()
		if fetchAt and GetTime() >= fetchAt then
			fetchTries = (fetchTries or 0) + 1
			fetchAt = fetchTries < 2 and not liveStats() and GetTime() + 5 or nil
			fetchStats()
		end
		if AZS_STATS_UPDATED ~= lastUpdated or ph ~= lastPhase then
			lastUpdated = AZS_STATS_UPDATED
			lastPhase = ph
			keepStats()
			refresh()
			if menu and menu:IsShown() then
				refreshStatList()
			end
		end
	end)

	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function()
		if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
			initDB()
			applyState()
			redraw()
		elseif event == "PLAYER_ENTERING_WORLD" then
			-- A moment for the world to settle before asking for the stats.
			fetchAt, fetchTries = GetTime() + 2, 0
		end
	end)
end

---------------------------------------------------------------------------
-- Options menu
---------------------------------------------------------------------------

local widgetCount = 0
local function widgetName(kind)
	widgetCount = widgetCount + 1
	return "StatOverlayMenu" .. kind .. widgetCount
end

local function addRefresher(fn)
	table.insert(menu.refreshers, fn)
end

local function makeHeader(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function makeCheck(parent, label, x, y, getter, setter)
	local name = widgetName("Check")
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	cb:SetWidth(24)
	cb:SetHeight(24)
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	getglobal(name .. "Text"):SetText(label)
	cb:SetScript("OnClick", function()
		setter(this:GetChecked() and true or false)
		redraw()
		refreshMenu()
	end)
	addRefresher(function()
		cb:SetChecked(getter() and 1 or nil)
	end)
	return cb
end

local function makeSlider(parent, label, x, y, minV, maxV, step, fmt, getter, setter)
	local name = widgetName("Slider")
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetWidth(180)
	s:SetHeight(16)
	s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	getglobal(name .. "Low"):SetText(string.format(fmt, minV))
	getglobal(name .. "High"):SetText(string.format(fmt, maxV))
	local text = getglobal(name .. "Text")
	local function show(v)
		text:SetText(label .. ": " .. string.format(fmt, v))
	end
	s:SetScript("OnValueChanged", function()
		local v = math.floor(this:GetValue() / step + 0.5) * step
		show(v)
		if this.ready then
			setter(v)
			redraw()
		end
	end)
	addRefresher(function()
		s.ready = false
		s:SetValue(getter())
		show(getter())
		s.ready = true
	end)
	return s
end

-- A button that steps through a list; right-click steps back.
local function makeCycle(parent, label, x, y, names, getter, setter)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetText(label)
	local b = CreateFrame("Button", widgetName("Cycle"), parent, "UIPanelButtonTemplate")
	b:SetWidth(180)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function()
		local count = table.getn(names)
		local i = getter()
		if arg1 == "RightButton" then
			i = i - 1
			if i < 1 then
				i = count
			end
		else
			i = i + 1
			if i > count then
				i = 1
			end
		end
		setter(i)
		redraw()
		refreshMenu()
	end)
	addRefresher(function()
		b:SetText(names[getter()])
	end)
	return b
end

local function openColorPicker(key)
	local c = db().elv[key]
	local prev = copyColor(c)
	local hasOpacity = (key == "bg" or key == "borderColor")

	-- Clear the callbacks while the picker is set up, so it can't write stale values into c.
	ColorPickerFrame.func = nil
	ColorPickerFrame.opacityFunc = nil
	ColorPickerFrame.cancelFunc = nil
	ColorPickerFrame.hasOpacity = hasOpacity
	ColorPickerFrame.opacity = 1 - (c[4] or 1)
	ColorPickerFrame.previousValues = prev
	ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()

	local function apply()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		c[1], c[2], c[3] = r, g, b
		if hasOpacity then
			c[4] = 1 - OpacitySliderFrame:GetValue()
		end
		redraw()
		refreshMenu()
	end
	ColorPickerFrame.func = apply
	ColorPickerFrame.opacityFunc = apply
	ColorPickerFrame.cancelFunc = function()
		c[1], c[2], c[3], c[4] = prev[1], prev[2], prev[3], prev[4]
		redraw()
		refreshMenu()
	end
end

local function makeColor(parent, label, x, y, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(180)
	b:SetHeight(16)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local edge = b:CreateTexture(nil, "BACKGROUND")
	edge:SetWidth(16)
	edge:SetHeight(16)
	edge:SetPoint("LEFT", b, "LEFT", 0, 0)
	edge:SetTexture(0.7, 0.7, 0.7, 1)

	local swatch = b:CreateTexture(nil, "ARTWORK")
	swatch:SetWidth(14)
	swatch:SetHeight(14)
	swatch:SetPoint("CENTER", edge, "CENTER", 0, 0)

	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", edge, "RIGHT", 6, 0)
	fs:SetText(label)

	b:SetScript("OnClick", function()
		openColorPicker(key)
	end)
	addRefresher(function()
		local c = db().elv[key]
		swatch:SetTexture(c[1], c[2], c[3], 1)
	end)
	return b
end

local function makeButton(parent, text, x, y, width, onClick)
	local b = CreateFrame("Button", widgetName("Button"), parent, "UIPanelButtonTemplate")
	b:SetWidth(width)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

refreshStatList = function()
	local panel = menu.statsPanel
	local cfg = db()
	local list = statEntries()
	local n = table.getn(list)
	local perCol = math.max(1, math.ceil(n / 3))
	for i = 1, n do
		local cb = panel.checks[i]
		if not cb then
			local name = "StatOverlayMenuStat" .. i
			cb = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
			cb:SetWidth(24)
			cb:SetHeight(24)
			cb.text = getglobal(name .. "Text")
			cb:SetScript("OnClick", function()
				if this:GetChecked() then
					db().hidden[this.key] = nil
				else
					db().hidden[this.key] = true
				end
				redraw()
			end)
			panel.checks[i] = cb
		end
		local col = math.floor((i - 1) / perCol)
		local line = i - 1 - (col * perCol)
		cb:ClearAllPoints()
		cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + (col * 150), -40 - (line * 22))
		cb.key = list[i].key
		cb.text:SetText(list[i].label)
		cb:SetChecked(not cfg.hidden[cb.key] and 1 or nil)
		cb:Show()
	end
	for i = n + 1, table.getn(panel.checks) do
		panel.checks[i]:Hide()
	end
end

refreshMenu = function()
	if not menu then
		return
	end
	for i = 1, table.getn(menu.refreshers) do
		menu.refreshers[i]()
	end
	refreshStatList()
	if isElv() then
		menu.elv:Show()
		menu.basicNote:Hide()
	else
		menu.elv:Hide()
		menu.basicNote:Show()
	end
end

local function setAllHidden(hidden)
	local list = statEntries()
	for i = 1, table.getn(list) do
		if hidden then
			db().hidden[list[i].key] = true
		else
			db().hidden[list[i].key] = nil
		end
	end
	redraw()
	refreshMenu()
end

local function resetAppearance()
	local cfg = db()
	cfg.scale = COMMON_DEFAULTS.scale
	cfg.width = COMMON_DEFAULTS.width
	cfg.showTitle = COMMON_DEFAULTS.showTitle
	cfg.showStatus = COMMON_DEFAULTS.showStatus
	cfg.elv = nil
	initDB()
	redraw()
	refreshMenu()
end

local function buildStatsPanel(panel)
	panel.checks = {}
	makeHeader(panel, "Stats to show", 20, -8)
	makeButton(panel, "Show all", 240, -4, 100, function() setAllHidden(false) end)
	makeButton(panel, "Hide all", 346, -4, 100, function() setAllHidden(true) end)
end

local function buildLookPanel(panel)
	local cfg = db

	-- Left column: style and layout, shared by both styles.
	makeHeader(panel, "Style", 20, -4)
	makeCheck(panel, "Basic (WoW)", 20, -20,
		function() return not isElv() end,
		function() cfg().style = "basic" end)
	makeCheck(panel, "ElvUI", 20, -44,
		function() return isElv() end,
		function() cfg().style = "elvui" end)

	makeHeader(panel, "Layout", 20, -80)
	makeSlider(panel, "Scale", 20, -112, 0.5, 2, 0.05, "%.2f",
		function() return cfg().scale end,
		function(v) cfg().scale = v end)
	makeSlider(panel, "Width", 20, -152, 160, 400, 10, "%d",
		function() return cfg().width end,
		function(v) cfg().width = v end)
	makeCheck(panel, "Show title", 20, -182,
		function() return cfg().showTitle end,
		function(v) cfg().showTitle = v end)
	makeCheck(panel, "Show run phase", 20, -206,
		function() return cfg().showStatus end,
		function(v) cfg().showStatus = v end)
	makeCheck(panel, "Lock position", 20, -230,
		function() return cfg().locked end,
		function(v) cfg().locked = v end)
	makeCheck(panel, "Show overlay", 20, -254,
		function() return cfg().shown ~= false end,
		function(v) cfg().shown = v; applyState() end)
	makeCheck(panel, "Show raw values", 20, -278,
		function() return cfg().raw end,
		function(v) cfg().raw = v end)
	makeCheck(panel, "Fetch stats after a reload", 20, -302,
		function() return cfg().fetchStats end,
		function(v) cfg().fetchStats = v end)
	makeButton(panel, "Reset appearance", 20, -336, 160, resetAppearance)

	-- Right column: everything the ElvUI style lets you change.
	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", panel, "TOPLEFT", 250, -24)
	note:SetWidth(200)
	note:SetJustifyH("LEFT")
	note:SetText("Choose the ElvUI style to change the font, colours, border and spacing.")
	menu.basicNote = note

	local elv = CreateFrame("Frame", nil, panel)
	elv:SetPoint("TOPLEFT", panel, "TOPLEFT", 240, 0)
	elv:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	menu.elv = elv

	local function e()
		return db().elv
	end

	makeHeader(elv, "ElvUI look", 10, -4)
	makeCycle(elv, "Font", 10, -24, FONT_NAMES,
		function() return e().font end,
		function(i) e().font = i end)
	makeCycle(elv, "Outline", 10, -66, OUTLINE_NAMES,
		function() return e().outline end,
		function(i) e().outline = i end)
	makeSlider(elv, "Font size", 10, -122, 8, 24, 1, "%d",
		function() return e().fontSize end,
		function(v) e().fontSize = v end)
	makeSlider(elv, "Row height", 10, -160, 10, 32, 1, "%d",
		function() return e().rowHeight end,
		function(v) e().rowHeight = v end)
	makeSlider(elv, "Padding", 10, -198, 0, 20, 1, "%d",
		function() return e().pad end,
		function(v) e().pad = v end)
	makeSlider(elv, "Border size", 10, -236, 0, 4, 1, "%d",
		function() return e().border end,
		function(v) e().border = v end)
	makeCheck(elv, "Striped rows", 10, -270,
		function() return e().stripes end,
		function(v) e().stripes = v end)

	makeHeader(elv, "Colours", 10, -300)
	makeColor(elv, "Background", 10, -318, "bg")
	makeColor(elv, "Border", 10, -336, "borderColor")
	makeColor(elv, "Title", 10, -354, "title")
	makeColor(elv, "Labels", 10, -372, "label")
	makeColor(elv, "Values", 10, -390, "value")
end

local function createMenu()
	menu = CreateFrame("Frame", "StatOverlayMenu", UIParent)
	menu.refreshers = {}
	menu:SetWidth(500)
	menu:SetHeight(500)
	menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	menu:SetFrameStrata("HIGH")
	menu:EnableMouse(true)
	menu:SetMovable(true)
	menu:SetClampedToScreen(true)
	menu:RegisterForDrag("LeftButton")
	menu:SetScript("OnDragStart", function() this:StartMoving() end)
	menu:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	menu:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	menu:Hide()
	-- Escape closes it.
	table.insert(UISpecialFrames, "StatOverlayMenu")

	local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", menu, "TOP", 0, -16)
	title:SetText("Stat Overlay")

	local close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, -6)

	local statsPanel = CreateFrame("Frame", nil, menu)
	statsPanel:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -70)
	statsPanel:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
	menu.statsPanel = statsPanel

	local lookPanel = CreateFrame("Frame", nil, menu)
	lookPanel:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -70)
	lookPanel:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)

	local tabStats, tabLook
	local function showTab(which)
		if which == "stats" then
			statsPanel:Show()
			lookPanel:Hide()
			tabStats:Disable()
			tabLook:Enable()
		else
			statsPanel:Hide()
			lookPanel:Show()
			tabStats:Enable()
			tabLook:Disable()
		end
	end
	tabStats = makeButton(menu, "Stats", 20, -40, 100, function() showTab("stats") end)
	tabLook = makeButton(menu, "Appearance", 126, -40, 100, function() showTab("look") end)

	buildStatsPanel(statsPanel)
	buildLookPanel(lookPanel)
	showTab("stats")

	menu:SetScript("OnShow", function()
		refreshMenu()
	end)
end

local function toggleMenu()
	if not menu then
		createMenu()
	end
	if menu:IsShown() then
		menu:Hide()
	else
		menu:Show()
	end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function dump()
	local s = stats()
	if not s then
		say("AZS_STATS is not available")
		return
	end
	local keys = {}
	for k in pairs(s) do
		table.insert(keys, k)
	end
	table.sort(keys)
	say("AZS_STATS (" .. tostring(phase()) .. "):")
	local line = ""
	for i = 1, table.getn(keys) do
		line = line .. keys[i] .. "=" .. tostring(s[keys[i]]) .. "  "
		if math.mod(i, 6) == 0 then
			DEFAULT_CHAT_FRAME:AddMessage(line)
			line = ""
		end
	end
	if line ~= "" then
		DEFAULT_CHAT_FRAME:AddMessage(line)
	end
end

local function slashHandler(msg)
	local cmd = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
	local cfg = db()
	if cmd == "" or cmd == "config" or cmd == "options" or cmd == "menu" then
		toggleMenu()
		return
	elseif cmd == "toggle" then
		cfg.shown = not frame:IsShown()
	elseif cmd == "lock" then
		cfg.locked = true
		say("locked")
	elseif cmd == "unlock" then
		cfg.locked = false
		say("unlocked")
	elseif cmd == "reset" then
		cfg.point, cfg.relPoint, cfg.x, cfg.y = nil, nil, nil, nil
		say("position reset")
	elseif cmd == "raw" then
		cfg.raw = not cfg.raw
		say("raw values " .. (cfg.raw and "on" or "off"))
	elseif cmd == "dump" then
		dump()
	else
		say("/so (or /statoverlay) [config] | toggle | lock | unlock | reset | raw | dump")
	end
	applyState()
	redraw()
	refreshMenu()
end

SLASH_STATOVERLAY1 = "/statoverlay"
SLASH_STATOVERLAY2 = "/sov"
SLASH_STATOVERLAY3 = "/so"
SlashCmdList["STATOVERLAY"] = slashHandler

createFrame()
