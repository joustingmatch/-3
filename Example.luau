-- The library lives in its own function so its locals don't count against
-- the script below it: Luau allows 200 locals per function.
local Library = (function()
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local Library = {}

Library.Flags = {}
Library.Windows = {}

local function normalize(source, map)
    local opts = {}
    if type(source) == "string" then
        opts.Name = source
    elseif type(source) == "table" then
        for key, value in pairs(source) do
            opts[key] = value
        end
    end
    for from, to in pairs(map or {}) do
        if opts[to] == nil and opts[from] ~= nil then
            opts[to] = opts[from]
        end
    end
    if opts.Range then
        opts.Min = opts.Min or opts.Range[1]
        opts.Max = opts.Max or opts.Range[2]
    end
    return opts
end

local function finishElement(tab, opts, element, frame, kind)
    element._type = kind
    element._frame = frame
    element._window = tab and tab.Window
    element._listeners = element._listeners or {}
    local window = tab and tab.Window
    local searchText = opts.Name or opts.Text or opts.Title
    element._searchName = type(searchText) == "string" and searchText or ""
    element._searchKey = string.lower(element._searchName)
    if tab and tab._items then
        table.insert(tab._items, element)
    end
    if opts.Flag then
        Library.Flags[opts.Flag] = element
        if window then
            window:_flagCreated(opts.Flag, element)
        end
    end
    element._userVisible = opts.Visible ~= false
    function element:IsVisible()
        return element._userVisible
    end
    function element:_isShown()
        return element._userVisible and not element._dependHidden and not (tab and tab._userVisible == false)
    end
    function element:SetVisible(visible)
        visible = visible and true or false
        if visible == element._userVisible or element._destroyed then
            return
        end
        element._userVisible = visible
        if not visible then
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
        if frame then
            frame.Visible = visible and not element._dependHidden
        end
        if window then
            window._controlsDirty = true
        end
    end
    if frame and not element._userVisible then
        frame.Visible = false
    end
    -- Disabled: dimmed under a cover that swallows input.
    function element:SetDisabled(disabled)
        Library._setDisabled(element, frame, disabled)
    end
    function element:IsDisabled()
        return element.Disabled == true
    end
    if opts.Disabled == true then
        element:SetDisabled(true)
    end
    -- DependsOn: shown (or enabled, with DependsMode = "Disable") only while
    -- other flags allow it. See Library._dependsMet for the rule forms.
    function element:SetDependsOn(rule, mode)
        element._dependsOn = rule
        element._dependsMode = mode or element._dependsMode
        element._dependsMet = nil
        if rule == nil then
            Library._applyDepends(element, true)
        elseif window then
            Library._watchDepends(window, element)
        end
    end
    if opts.DependsOn ~= nil then
        element._dependsMode = opts.DependsMode
        element:SetDependsOn(opts.DependsOn)
    end
    -- Tooltip: a string, or { Title, Text, Icon }. nil, false or "" hides it.
    function element:SetTooltip(tip)
        element._tooltip = tip
        if frame and window and not element._tooltipBound then
            element._tooltipBound = true
            window:_attachTooltip(element, frame)
        end
    end
    function element:GetTooltip()
        return element._tooltip
    end
    if opts.Tooltip ~= nil and opts.Tooltip ~= false then
        element:SetTooltip(opts.Tooltip)
    end
    function element:Destroy()
        if element._destroyed then
            return
        end
        element._destroyed = true
        if window and window._tipOwner == element then
            window:_hideTooltip()
        end
        for _, disconnect in ipairs(element._listeners) do
            disconnect()
        end
        element._listeners = {}
        if tab and tab._items then
            local index = table.find(tab._items, element)
            if index then
                table.remove(tab._items, index)
            end
        end
        if opts.Flag and Library.Flags[opts.Flag] == element then
            Library.Flags[opts.Flag] = nil
        end
        if window then
            window._controlsDirty = true
        end
        if frame then
            frame:Destroy()
        end
    end
    return element
end

Library.Theme = {
    Background = Color3.fromRGB(15, 15, 15),
    Surface = Color3.fromRGB(20, 20, 20),
    Surface2 = Color3.fromRGB(25, 25, 25),
    Surface3 = Color3.fromRGB(50, 50, 50),
    Stroke = Color3.fromRGB(40, 40, 40),
    StrokeHover = Color3.fromRGB(70, 70, 70),
    Accent = Color3.fromRGB(128, 160, 246),
    AccentDark = Color3.fromRGB(12, 12, 12),
    Text = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(140, 140, 140),
    Warning = Color3.fromRGB(240, 176, 108),
    Success = Color3.fromRGB(150, 220, 170),
    Error = Color3.fromRGB(240, 120, 120),
}

-- Order decides which key wins when two theme colors are identical.
local THEME_KEYS = {
    "Accent", "AccentDark", "Background", "Surface", "Surface2", "Surface3",
    "Stroke", "StrokeHover", "Text", "Muted", "Warning", "Success", "Error",
}

local function rgb(r, g, b)
    return Color3.fromRGB(r, g, b)
end

-- Muted text is drawn small, so lift it toward Text until it clears WCAG AA
-- (4.5:1) against Surface2, the lightest surface it usually sits on.
function Library._readableMuted(muted, text, surface)
    local function luminance(color)
        local function channel(v)
            return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
        end
        return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
    end
    local back = luminance(surface)
    for step = 0, 20 do
        local candidate = muted:Lerp(text, step / 20)
        local front = luminance(candidate)
        if (math.max(front, back) + 0.05) / (math.min(front, back) + 0.05) >= 4.6 then
            return candidate
        end
    end
    return text
end

local function preset(background, surface, surface2, surface3, strokeColor, strokeHover, accent, accentDark, text, muted)
    return {
        Background = rgb(table.unpack(background)),
        Surface = rgb(table.unpack(surface)),
        Surface2 = rgb(table.unpack(surface2)),
        Surface3 = rgb(table.unpack(surface3)),
        Stroke = rgb(table.unpack(strokeColor)),
        StrokeHover = rgb(table.unpack(strokeHover)),
        Accent = rgb(table.unpack(accent)),
        AccentDark = rgb(table.unpack(accentDark)),
        Text = rgb(table.unpack(text)),
        Muted = Library._readableMuted(rgb(table.unpack(muted)), rgb(table.unpack(text)), rgb(table.unpack(surface2))),
    }
end

Library.ThemePresets = {
    -- Colours here must not be pure white, pure black or any other colour the
    -- library hard-codes, or those objects would get bound to the theme.
    Midnight = preset({ 15, 18, 26 }, { 18, 22, 31 }, { 22, 26, 37 }, { 37, 44, 60 }, { 34, 40, 55 }, { 70, 84, 112 }, { 128, 160, 246 }, { 14, 18, 30 }, { 228, 232, 242 }, { 116, 126, 148 }),
    Ocean = preset({ 12, 20, 24 }, { 15, 24, 29 }, { 18, 29, 35 }, { 31, 48, 56 }, { 29, 44, 52 }, { 58, 92, 104 }, { 110, 214, 222 }, { 10, 24, 28 }, { 226, 238, 240 }, { 108, 134, 140 }),
    Rose = preset({ 21, 21, 21 }, { 26, 26, 26 }, { 31, 31, 31 }, { 48, 48, 48 }, { 44, 44, 44 }, { 92, 116, 50 }, { 183, 243, 74 }, { 21, 21, 21 }, { 243, 243, 238 }, { 134, 134, 128 }),
    Emerald = preset({ 13, 20, 17 }, { 16, 24, 20 }, { 20, 29, 24 }, { 33, 47, 40 }, { 30, 44, 37 }, { 62, 96, 78 }, { 132, 226, 170 }, { 12, 26, 18 }, { 228, 240, 233 }, { 110, 136, 122 }),
    Amber = preset({ 22, 18, 13 }, { 27, 22, 16 }, { 32, 26, 19 }, { 49, 41, 31 }, { 46, 38, 28 }, { 100, 82, 58 }, { 246, 196, 120 }, { 30, 22, 10 }, { 242, 236, 226 }, { 140, 126, 106 }),
    Mono = preset({ 16, 16, 17 }, { 20, 20, 21 }, { 25, 25, 26 }, { 40, 40, 42 }, { 38, 38, 40 }, { 84, 84, 88 }, { 236, 236, 240 }, { 20, 20, 22 }, { 234, 234, 236 }, { 122, 122, 128 }),
    Nebula = preset({ 14, 12, 28 }, { 18, 15, 35 }, { 23, 19, 43 }, { 39, 32, 68 }, { 35, 29, 62 }, { 84, 68, 140 }, { 199, 125, 255 }, { 22, 10, 40 }, { 236, 230, 252 }, { 124, 114, 160 }),
    Synthwave = preset({ 20, 12, 30 }, { 25, 15, 37 }, { 31, 18, 45 }, { 52, 30, 72 }, { 47, 27, 66 }, { 110, 58, 150 }, { 255, 94, 198 }, { 38, 8, 30 }, { 250, 232, 246 }, { 150, 118, 160 }),
    Sakura = preset({ 24, 14, 20 }, { 29, 17, 24 }, { 35, 20, 29 }, { 54, 32, 45 }, { 50, 29, 41 }, { 112, 66, 92 }, { 255, 158, 200 }, { 36, 12, 24 }, { 248, 232, 240 }, { 150, 112, 132 }),
    Velvet = preset({ 20, 10, 16 }, { 25, 12, 20 }, { 31, 15, 25 }, { 50, 25, 40 }, { 46, 23, 37 }, { 104, 52, 82 }, { 222, 110, 170 }, { 30, 8, 20 }, { 244, 228, 238 }, { 142, 106, 126 }),
    Crimson = preset({ 18, 10, 12 }, { 23, 12, 15 }, { 28, 14, 18 }, { 46, 24, 29 }, { 42, 22, 27 }, { 104, 46, 56 }, { 244, 74, 94 }, { 32, 8, 12 }, { 244, 230, 232 }, { 142, 106, 112 }),
    Sunset = preset({ 22, 13, 14 }, { 27, 16, 17 }, { 33, 19, 21 }, { 52, 31, 32 }, { 48, 28, 30 }, { 112, 62, 58 }, { 255, 138, 92 }, { 34, 14, 8 }, { 248, 234, 228 }, { 150, 118, 110 }),
    Gold = preset({ 14, 13, 11 }, { 18, 17, 14 }, { 23, 21, 17 }, { 38, 35, 28 }, { 35, 32, 26 }, { 92, 80, 54 }, { 232, 196, 122 }, { 30, 22, 8 }, { 240, 234, 222 }, { 136, 126, 106 }),
    Cyber = preset({ 13, 13, 15 }, { 17, 17, 19 }, { 21, 21, 24 }, { 36, 36, 40 }, { 33, 33, 37 }, { 86, 84, 70 }, { 250, 226, 72 }, { 30, 26, 4 }, { 240, 240, 232 }, { 126, 124, 118 }),
    Toxic = preset({ 11, 14, 11 }, { 14, 18, 14 }, { 18, 23, 18 }, { 31, 39, 30 }, { 28, 36, 28 }, { 74, 98, 60 }, { 184, 255, 74 }, { 18, 30, 6 }, { 232, 242, 228 }, { 116, 134, 110 }),
    Matcha = preset({ 16, 19, 14 }, { 20, 23, 17 }, { 24, 28, 21 }, { 40, 46, 34 }, { 37, 42, 31 }, { 84, 98, 70 }, { 176, 214, 140 }, { 18, 26, 10 }, { 236, 240, 228 }, { 128, 136, 116 }),
    Aurora = preset({ 10, 20, 22 }, { 12, 25, 27 }, { 15, 30, 33 }, { 26, 50, 53 }, { 24, 45, 48 }, { 50, 104, 104 }, { 94, 240, 180 }, { 6, 30, 22 }, { 224, 246, 240 }, { 102, 142, 134 }),
    Frost = preset({ 13, 17, 23 }, { 16, 21, 28 }, { 20, 26, 34 }, { 34, 43, 56 }, { 31, 40, 52 }, { 72, 92, 118 }, { 164, 214, 255 }, { 12, 22, 34 }, { 230, 238, 246 }, { 114, 128, 146 }),
    Abyss = preset({ 7, 11, 22 }, { 9, 14, 28 }, { 12, 18, 35 }, { 22, 31, 58 }, { 20, 28, 52 }, { 44, 64, 120 }, { 72, 148, 255 }, { 6, 14, 34 }, { 226, 234, 250 }, { 100, 116, 152 }),
    -- Seasonal and themed palettes.
    Halloween = preset({ 18, 12, 20 }, { 23, 15, 25 }, { 28, 18, 30 }, { 46, 30, 48 }, { 43, 28, 44 }, { 104, 62, 40 }, { 255, 138, 36 }, { 36, 16, 4 }, { 246, 234, 224 }, { 146, 120, 128 }),
    Haunted = preset({ 14, 12, 20 }, { 18, 15, 26 }, { 22, 18, 32 }, { 38, 31, 54 }, { 35, 29, 50 }, { 70, 96, 64 }, { 156, 255, 110 }, { 14, 30, 8 }, { 232, 240, 228 }, { 120, 116, 140 }),
    Christmas = preset({ 12, 20, 15 }, { 15, 25, 19 }, { 19, 30, 23 }, { 32, 50, 38 }, { 30, 46, 35 }, { 100, 54, 56 }, { 236, 72, 80 }, { 34, 8, 10 }, { 240, 244, 236 }, { 120, 142, 128 }),
    Valentine = preset({ 24, 12, 17 }, { 30, 14, 21 }, { 36, 17, 25 }, { 58, 27, 40 }, { 54, 25, 37 }, { 130, 56, 84 }, { 255, 92, 140 }, { 40, 8, 20 }, { 252, 232, 240 }, { 160, 112, 132 }),
    Lunar = preset({ 22, 10, 10 }, { 28, 12, 12 }, { 34, 15, 14 }, { 54, 24, 22 }, { 50, 22, 20 }, { 130, 92, 40 }, { 246, 196, 84 }, { 38, 16, 6 }, { 250, 236, 222 }, { 160, 120, 108 }),
    Tropical = preset({ 10, 22, 24 }, { 12, 27, 30 }, { 15, 33, 36 }, { 26, 54, 58 }, { 24, 50, 54 }, { 44, 110, 110 }, { 255, 170, 90 }, { 36, 18, 6 }, { 232, 246, 244 }, { 104, 144, 142 }),
    Dracula = preset({ 24, 25, 33 }, { 29, 30, 40 }, { 34, 36, 47 }, { 52, 55, 70 }, { 48, 50, 64 }, { 98, 114, 164 }, { 189, 147, 249 }, { 26, 18, 44 }, { 246, 246, 238 }, { 126, 132, 168 }),
    Coffee = preset({ 20, 16, 13 }, { 25, 20, 16 }, { 30, 24, 19 }, { 48, 39, 31 }, { 45, 36, 29 }, { 104, 82, 62 }, { 214, 170, 124 }, { 32, 22, 12 }, { 240, 230, 218 }, { 142, 124, 108 }),
}

Library.ThemeName = "Midnight"

Library.Assets = {
    Shadow = "rbxassetid://6014261993",
    Glow = "rbxassetid://8992230677",
    Logo = "rbxassetid://103859712365480",
}

local LUCIDE_URL = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua"
local lucideSet = nil

local function loadLucide()
    if lucideSet ~= nil then
        return lucideSet
    end
    local ok, result = pcall(function()
        local source = game:HttpGet(LUCIDE_URL)
        return loadstring(source)()
    end)
    if ok and type(result) == "table" then
        lucideSet = result
    else
        lucideSet = false
        warn("[AirFlow] lucide icons unavailable: " .. tostring(result))
    end
    return lucideSet
end

local FONT_PRESETS = {
    ValleySans = {
        Regular = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Regular.ttf",
        Medium = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Medium.ttf",
        SemiBold = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-SemiBold.ttf",
    },
}

local FONT_WEIGHTS = {
    Regular = { 400, Enum.FontWeight.Regular },
    Medium = { 500, Enum.FontWeight.Medium },
    SemiBold = { 600, Enum.FontWeight.SemiBold },
    Bold = { 700, Enum.FontWeight.Bold },
}

function Library:LoadFont(opts)
    opts = normalize(opts, {})
    if type(writefile) ~= "function" or type(isfile) ~= "function" or typeof(getcustomasset) ~= "function" then
        warn("[AirFlow] custom fonts need writefile, isfile and getcustomasset")
        return false
    end
    local name = opts.Name or "CustomFont"
    local weights = opts.Weights or FONT_PRESETS[name]
    if type(weights) ~= "table" then
        warn("[AirFlow] no font weights for " .. name)
        return false
    end
    local folder = opts.Folder or "AirFlowFonts"
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
            makefolder(folder)
        end
    end)
    local faces = {}
    for weightName, url in pairs(weights) do
        local info = FONT_WEIGHTS[weightName]
        if info then
            local path = folder .. "/" .. name .. "-" .. weightName .. ".ttf"
            local ok = true
            if not isfile(path) then
                ok = pcall(function()
                    writefile(path, game:HttpGet(url))
                end)
            end
            if ok then
                table.insert(faces, { name = weightName, weight = info[1], style = "normal", assetId = getcustomasset(path) })
            else
                warn("[AirFlow] could not download " .. weightName .. " weight of " .. name)
            end
        end
    end
    if #faces == 0 then
        return false
    end
    local familyPath = folder .. "/" .. name .. ".json"
    local okWrite = pcall(function()
        writefile(familyPath, HttpService:JSONEncode({ name = name, faces = faces }))
    end)
    if not okWrite then
        return false
    end
    local family = getcustomasset(familyPath)
    local function face(weightName, fallback)
        local info = FONT_WEIGHTS[weightName]
        if info and weights[weightName] then
            return Font.new(family, info[2])
        end
        return fallback
    end
    Library.Fonts.Regular = face("Regular", Library.Fonts.Regular)
    Library.Fonts.Medium = face("Medium", face("Regular", Library.Fonts.Medium))
    Library.Fonts.Bold = face("SemiBold", face("Bold", Library.Fonts.Bold))
    return true
end

function Library:PreloadIcons()
    return loadLucide() ~= false
end

-- Numbers, digit strings and asset URLs are custom images; anything else is
-- a lucide name.
local function assetId(value)
    if type(value) == "number" then
        return "rbxassetid://" .. string.format("%.0f", value)
    end
    if type(value) == "string" then
        if value:match("^%d+$") then
            return "rbxassetid://" .. value
        end
        if value:find("^rbxassetid://") or value:find("^rbxasset://") or value:find("^rbxthumb://") or value:find("^http") then
            return value
        end
    end
    return nil
end

-- Returns image, rect offset, rect size, whether it is a custom image, and
-- whether that custom image should still take the theme tint.
local function resolveIcon(icon)
    if typeof(icon) == "table" then
        return assetId(icon.Image) or icon.Image, icon.RectOffset, icon.RectSize, true, icon.Tint == true
    end
    local asset = assetId(icon)
    if asset then
        return asset, nil, nil, true, false
    end
    if type(icon) ~= "string" then
        return nil
    end
    local name = icon:gsub("^lucide:", "")
    local set = loadLucide()
    if not set then
        return nil
    end
    local entry = (set.Icons and set.Icons[name]) or set[name]
    if type(entry) == "table" then
        local image = entry.Image
        if type(image) == "number" then
            image = "rbxassetid://" .. tostring(image)
        end
        local sheet = (set.Spritesheets and set.Spritesheets[tostring(image)]) or image
        return sheet, entry.ImageRectPosition, entry.ImageRectSize
    elseif type(entry) == "string" then
        return entry
    end
    warn("[AirFlow] unknown lucide icon: " .. name)
    return nil
end

local BUTTON_HINT_ICON = "chevron-right"

local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Library.Fonts = {
    Regular = Font.new(FONT_FAMILY, Enum.FontWeight.Regular),
    Medium = Font.new(FONT_FAMILY, Enum.FontWeight.Medium),
    Bold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold),
}

local Theme = Library.Theme
local Assets = Library.Assets

-- The OuroFlow mark, embedded as a 256px grayscale PNG so it needs no upload.
-- It is written to the workspace once and loaded with getcustomasset; the
-- white-to-grey shading is multiplied by the theme accent like the old logo.
-- Without file functions the uploaded asset above stays in use.
local EMBEDDED_LOGO = "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"

local function decodeBase64(data)
    local lookup = {}
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do
        lookup[alphabet:byte(i)] = i - 1
    end
    local out = {}
    for i = 1, #data, 4 do
        local a, b, c, d = data:byte(i, i + 3)
        local n = lookup[a] * 262144 + lookup[b] * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
        local x, y, z = n // 65536, n // 256 % 256, n % 256
        if d ~= 61 then
            out[#out + 1] = string.char(x, y, z)
        elseif c ~= 61 then
            out[#out + 1] = string.char(x, y)
        else
            out[#out + 1] = string.char(x)
        end
    end
    return table.concat(out)
end

pcall(function()
    if type(writefile) ~= "function" or typeof(getcustomasset) ~= "function" then
        return
    end
    local folder = "AirFlowAssets"
    if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
        makefolder(folder)
    end
    local path = folder .. "/OuroFlowLogo.png"
    local png = decodeBase64(EMBEDDED_LOGO)
    local fresh = type(isfile) == "function" and type(readfile) == "function" and isfile(path) and readfile(path) == png
    if not fresh then
        writefile(path, png)
    end
    local asset = getcustomasset(path)
    if type(asset) == "string" and asset ~= "" then
        Assets.Logo = asset
    end
end)
local Fonts = Library.Fonts

local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Library.Touch = TOUCH

local SIDEBAR_WIDTH = 188
local HEADER_HEIGHT = 62
local TAB_TILE_HEIGHT = 34
local CARD_HEIGHT = TOUCH and 54 or 48
local CARD_HEIGHT_DESC = TOUCH and 70 or 64
local DROPDOWN_OPTION_HEIGHT = TOUCH and 40 or 34
local CHIP_HEIGHT = TOUCH and 34 or 28
local PROFILE_HEIGHT = 64
local SEARCH_WIDTH = 176
local STACK_BELOW = 440

-- Elements read their geometry from one of these. Cards stand alone on a tab,
-- rows sit flush inside a groupbox.
local METRICS = {
    Card = {
        Compact = false,
        Height = CARD_HEIGHT,
        DescHeight = CARD_HEIGHT_DESC,
        Chip = CHIP_HEIGHT,
        Option = DROPDOWN_OPTION_HEIGHT,
        TextSize = 14,
        DescSize = 13,
        TitleHeight = 18,
        DescGap = 20,
        DescLine = 17,
        Slider = CARD_HEIGHT_DESC,
    },
    Row = {
        Compact = true,
        Height = TOUCH and 40 or 32,
        DescHeight = TOUCH and 54 or 46,
        Chip = TOUCH and 30 or 24,
        Option = TOUCH and 34 or 28,
        TextSize = 13,
        DescSize = 12,
        TitleHeight = 16,
        DescGap = 17,
        DescLine = 15,
        Slider = TOUCH and 54 or 46,
    },
}

local tweenInfoCache = {}

-- Theme bindings: every instance property painted with a theme color is
-- remembered by theme key, so SetTheme can repaint the whole UI live.
-- Held strongly: an Instance's Lua handle can be collected while the Instance
-- still exists, which would silently drop it from a weak table. Destroyed
-- objects are pruned instead, once they have been parentless for two sweeps.
local themeBindings = {}
local themeHooks = {}
local themeLookup = {}
local orphanMarks = {}
local bindingCount = 0
local sweepAt = 4000

local function pruneTable(map, counted)
    for object in pairs(map) do
        if object.Parent == nil then
            if orphanMarks[object] then
                map[object] = nil
                orphanMarks[object] = nil
                if counted then
                    bindingCount -= 1
                end
            else
                orphanMarks[object] = true
            end
        else
            orphanMarks[object] = nil
        end
    end
end

local function sweepBindings()
    pruneTable(themeBindings, true)
    pruneTable(themeHooks, false)
    sweepAt = math.max(4000, bindingCount * 2)
end

local function colorKey(color)
    return math.floor(color.R * 255 + 0.5) .. "," .. math.floor(color.G * 255 + 0.5) .. "," .. math.floor(color.B * 255 + 0.5)
end

local function rebuildThemeLookup()
    table.clear(themeLookup)
    for index = #THEME_KEYS, 1, -1 do
        local name = THEME_KEYS[index]
        themeLookup[colorKey(Library.Theme[name])] = name
    end
end
rebuildThemeLookup()

local function bindColors(object, props)
    for property, value in pairs(props) do
        if typeof(value) == "Color3" then
            local name = themeLookup[colorKey(value)]
            local bound = themeBindings[object]
            if name then
                if not bound then
                    bound = {}
                    themeBindings[object] = bound
                    bindingCount += 1
                    if bindingCount >= sweepAt then
                        sweepBindings()
                    end
                end
                bound[property] = name
            elseif bound then
                bound[property] = nil
            end
        end
    end
end

-- Repaints every bound property from the colours on screen to the new theme.
-- One Heartbeat loop lerps each theme key once per frame and assigns the
-- result, instead of creating a tween per object, which hitched the frame the
-- theme changed on large UIs. A change mid-fade picks up from what is shown.
local shownTheme = table.clone(Library.Theme)
local themeDriver = nil

local function paintBinding(object, bound, colors)
    for property, name in pairs(bound) do
        local color = colors[name]
        if color then
            object[property] = color
        end
    end
end

local function paintBindings(colors)
    for object, bound in pairs(themeBindings) do
        pcall(paintBinding, object, bound, colors)
    end
end

local function driveTheme(duration)
    if themeDriver then
        themeDriver:Disconnect()
        themeDriver = nil
    end
    local from, colors = {}, {}
    for _, name in ipairs(THEME_KEYS) do
        local target = Library.Theme[name]
        local current = shownTheme[name] or target
        if current ~= target then
            from[name] = current
            colors[name] = current
        end
    end
    local function finish()
        for _, name in ipairs(THEME_KEYS) do
            colors[name] = Library.Theme[name]
            shownTheme[name] = Library.Theme[name]
        end
        paintBindings(colors)
    end
    if duration <= 0 or next(from) == nil then
        finish()
        return
    end
    local elapsed = 0
    themeDriver = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= duration then
            themeDriver:Disconnect()
            themeDriver = nil
            finish()
            return
        end
        local alpha = 1 - (1 - elapsed / duration) ^ 5
        for name, start in pairs(from) do
            local color = start:Lerp(Library.Theme[name], alpha)
            colors[name] = color
            shownTheme[name] = color
        end
        paintBindings(colors)
    end)
end

-- Runs fn now and again whenever the theme changes, while owner exists.
local function onTheme(owner, fn)
    themeHooks[owner] = fn
    fn()
end

local function tween(object, props, duration, style, direction, raw)
    duration = duration or 0.2
    if not raw then
        bindColors(object, props)
    end
    if duration <= 0 then
        for key, value in pairs(props) do
            object[key] = value
        end
        return nil
    end
    style = style or Enum.EasingStyle.Quart
    direction = direction or Enum.EasingDirection.Out
    local key = duration .. style.Name .. direction.Name
    local info = tweenInfoCache[key]
    if not info then
        info = TweenInfo.new(duration, style, direction)
        tweenInfoCache[key] = info
    end
    local t = TweenService:Create(object, info, props)
    t:Play()
    return t
end

local function create(className, props, children)
    local inst = Instance.new(className)
    for key, value in pairs(props) do
        if key ~= "Parent" then
            inst[key] = value
        end
    end
    bindColors(inst, props)
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end

    if props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

-- Corners in pixels follow the player's corner radius setting: each one
-- remembers the radius it was drawn at, and Library:SetCornerRadius rescales
-- them all. Scale corners (pills, circles) stay as they are.
Library.Roundness = 1
-- A strong table: weak keys would drop the Lua handles for corners nothing
-- else in Lua holds, and those corners would never rescale. Destroyed ones
-- are pruned whenever the radius changes.
Library._cornerBases = {}

local function corner(parent, radius)
    radius = radius or UDim.new(0, 8)
    local object = create("UICorner", {
        CornerRadius = radius.Scale == 0 and UDim.new(0, math.floor(radius.Offset * Library.Roundness + 0.5)) or radius,
        Parent = parent,
    })
    if radius.Scale == 0 then
        Library._cornerBases[object] = radius.Offset
    end
    return object
end

-- A corner that ignores the setting, for shapes that animate their own
-- radius (the minimized island, the morph panels).
function Library._fixedCorner(parent, radius)
    return create("UICorner", { CornerRadius = radius, Parent = parent })
end

-- The radius the window's own corners are drawn at right now.
function Library._radius(pixels)
    return math.floor(pixels * Library.Roundness + 0.5)
end

local function stroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or Theme.Stroke,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function padding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
        Parent = parent,
    })
end

local function label(props)
    local defaults = {
        BackgroundTransparency = 1,
        TextColor3 = Theme.Text,
        TextSize = 14,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for key, value in pairs(props) do
        defaults[key] = value
    end
    return create("TextLabel", defaults)
end

local function glow(parent, size, position, transparency, rotation)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Color3.fromRGB(226, 218, 230),
        ImageTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = parent,
    })
    local gradient = create("UIGradient", {
        Rotation = rotation or 90,
        Parent = image,
    })
    onTheme(gradient, function()
        gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Theme.Accent)
    end)
    return image
end

local function edgeHighlight(parent)
    return create("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = parent,
    })
end

local CUSTOM_ICON_SCALE = 1.35

local function applyIcon(imageLabel, icon, fixedSize)
    local image, rectOffset, rectSize, custom, tint = resolveIcon(icon)
    if not image then
        return
    end
    imageLabel.Image = image
    imageLabel.ImageRectOffset = rectOffset or Vector2.zero
    imageLabel.ImageRectSize = rectSize or Vector2.zero
    -- The built-in logo is a white mark meant to be tinted.
    if icon == Assets.Logo then
        tint = true
    end
    local keepColours = custom and not tint
    imageLabel:SetAttribute("CustomIcon", keepColours or nil)
    if keepColours then
        -- Original colours, and out of the theme's reach.
        tween(imageLabel, { ImageColor3 = Color3.new(1, 1, 1) }, 0)
    end
    -- Uploaded images usually carry transparent padding and read smaller than
    -- the lucide set, so they are drawn larger. A table icon can pick its own
    -- Scale. Brand logos pass fixedSize, their slots are already sized for them.
    local scale = custom and not fixedSize and icon ~= Assets.Logo and (typeof(icon) == "table" and tonumber(icon.Scale) or CUSTOM_ICON_SCALE) or 1
    local scaler = imageLabel:FindFirstChild("CustomIconScale")
    if scale ~= 1 then
        scaler = scaler or create("UIScale", { Name = "CustomIconScale", Parent = imageLabel })
        scaler.Scale = scale
    elseif scaler then
        scaler:Destroy()
    end
end

-- Selection state for icons: tinted icons change colour, custom images keep
-- their colours and dim instead.
local function tintIcon(imageLabel, color, active, duration)
    if imageLabel:GetAttribute("CustomIcon") then
        tween(imageLabel, { ImageTransparency = active and 0 or 0.4 }, duration)
    else
        tween(imageLabel, { ImageColor3 = color }, duration)
    end
end

local function defaultParent()
    local hidden
    pcall(function()
        if typeof(gethui) == "function" then
            hidden = gethui()
        end
    end)
    if typeof(hidden) == "Instance" then
        return hidden
    end
    local core
    pcall(function()
        core = game:GetService("CoreGui")
        local probe = Instance.new("Folder")
        probe.Parent = core
        probe:Destroy()
    end)
    if core then
        return core
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local insetFrame, insetValue = nil, Vector2.zero
local function pointerPosition()
    local frame = time()
    if insetFrame ~= frame then
        insetFrame = frame
        insetValue = GuiService:GetGuiInset()
    end
    return UserInputService:GetMouseLocation() - insetValue
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function usingTouch()
    return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- A press that turned into a scroll is not a tap. Returns a check to call
-- from the click handler.
local function tapGuard(button, getScroller)
    local startCanvas
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            local frame = getScroller()
            startCanvas = frame and frame.CanvasPosition
        end
    end)
    return function()
        local frame = getScroller()
        return not (startCanvas and frame and (frame.CanvasPosition - startCanvas).Magnitude > 4)
    end
end

local function pointInside(point, object)
    local position, size = object.AbsolutePosition, object.AbsoluteSize
    return point.X >= position.X and point.X <= position.X + size.X
        and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function glowIcon(parent, icon, color, position)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = position,
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, icon)
    return holder, image
end

local function arrowIndicator(parent, anchorX, offsetX)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(anchorX, 0.5),
        Position = UDim2.new(anchorX, offsetX, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local indicator = {}
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, "chevron-down")
    if image.Image ~= "" then
        function indicator:Set(open)
            tween(image, {
                Rotation = open and 180 or 0,
                ImageColor3 = open and Theme.Accent or Theme.Muted,
            }, 0.3, Enum.EasingStyle.Quint)
        end
        return indicator
    end
    image:Destroy()
    local function glyph(rotation, transparency)
        return label({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            Text = "›",
            TextSize = 22,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Theme.Muted,
            TextTransparency = transparency,
            Rotation = rotation,
            Parent = holder,
        })
    end
    local down = glyph(90, 0)
    local up = glyph(270, 1)
    function indicator:Set(open)
        tween(down, { TextTransparency = open and 1 or 0 }, 0.2)
        tween(up, { TextTransparency = open and 0 or 1, TextColor3 = open and Theme.Accent or Theme.Muted }, 0.2)
    end
    return indicator
end

local ripplePool = {}

local function ripple(button)
    local mouse = pointerPosition()
    local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2
    local circle = table.remove(ripplePool)
    -- A pooled circle can't be reparented if it was destroyed along the way.
    if circle and not pcall(function()
        circle.Parent = nil
    end) then
        circle = nil
    end
    if not circle then
        circle = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        })
        corner(circle, UDim.new(1, 0))
    end
    circle.Position = UDim2.fromOffset(mouse.X - button.AbsolutePosition.X, mouse.Y - button.AbsolutePosition.Y)
    circle.Size = UDim2.fromOffset(0, 0)
    circle.BackgroundColor3 = Theme.Accent
    circle.BackgroundTransparency = 0.82
    circle.ZIndex = button.ZIndex + 1
    circle.Parent = button
    tween(circle, { Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1 }, 0.55)
    task.delay(0.55, function()
        -- A button destroyed mid-ripple takes the circle with it: drop it.
        if circle.Parent ~= button or not button.Parent then
            pcall(circle.Destroy, circle)
            return
        end
        circle.Parent = nil
        if #ripplePool < 4 then
            table.insert(ripplePool, circle)
        else
            circle:Destroy()
        end
    end)
end

local function flashStroke(strokeObject)
    if not strokeObject or strokeObject:GetAttribute("Hidden") then
        return
    end
    tween(strokeObject, { Color = Theme.Accent, Transparency = 0.2 }, 0.08)
    task.delay(0.12, function()
        tween(strokeObject, { Color = Theme.Stroke, Transparency = 0 }, 0.35)
    end)
end

local function hoverStroke(target, strokeObject)
    target.MouseEnter:Connect(function()
        tween(strokeObject, { Color = Theme.StrokeHover }, 0.12)
    end)
    target.MouseLeave:Connect(function()
        tween(strokeObject, { Color = Theme.Stroke }, 0.25)
    end)
end

local KEY_NAMES = {
    [Enum.KeyCode.LeftControl] = "LCtrl",
    [Enum.KeyCode.RightControl] = "RCtrl",
    [Enum.KeyCode.LeftShift] = "LShift",
    [Enum.KeyCode.RightShift] = "RShift",
    [Enum.KeyCode.LeftAlt] = "LAlt",
    [Enum.KeyCode.RightAlt] = "RAlt",
    [Enum.KeyCode.Return] = "Enter",
    [Enum.KeyCode.Escape] = "Esc",
    [Enum.KeyCode.Backspace] = "Backspace",
}

local function keyName(keyCode)
    if keyCode == nil then
        return "None"
    end
    return KEY_NAMES[keyCode] or keyCode.Name
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return
    end
    local ok, err = pcall(callback, ...)
    if not ok then
        warn("[AirFlow] callback error: " .. tostring(err))
    end
end

-- Runs a user callback on its own thread and waits for it with task.wait.
-- A callback that yields inside an engine call (InvokeServer and the like)
-- resumes at game identity, which can no longer touch the GUI in CoreGui;
-- keeping that on a separate thread leaves the caller's identity intact.
local function isolatedCall(callback)
    local result = nil
    task.spawn(function()
        result = table.pack(pcall(callback))
    end)
    while result == nil do
        task.wait()
    end
    return table.unpack(result, 1, result.n)
end

local function numberFormat(min, max, step)
    local decimals = 0
    local text = tostring(step)
    local dot = text:find("%.")
    if dot then
        decimals = #text - dot
    end
    local pattern = "%." .. decimals .. "f"
    return {
        snap = function(value)
            value = math.floor(value / step + 0.5) * step
            return math.clamp(value, min, max)
        end,
        format = function(value)
            return string.format(pattern, value)
        end,
    }
end

local function metricsOf(tab)
    return tab._metrics or METRICS.Card
end

-- Width of a value control inside a groupbox row. Every dropdown and input in
-- a groupbox uses the same share of the row, so their left edges line up.
local function rowControlWidth(frame, window)
    local width = frame.AbsoluteSize.X / window.Scale.Scale
    return math.clamp(math.floor(width * 0.48), 90, 220)
end

local function card(tab, className, height, opts)
    local compact = metricsOf(tab).Compact
    local props = {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = compact and 1 or 0,
        BorderSizePixel = 0,
        LayoutOrder = tab:_nextOrder(),
        Parent = tab.List,
    }
    if className == "TextButton" then
        props.AutoButtonColor = false
        props.Text = ""
    end
    local frame = create(className, props)
    frame:SetAttribute("NoDrag", true)
    corner(frame)
    local frameStroke = stroke(frame, Theme.Stroke, compact and 1 or 0)
    if compact then
        frameStroke:SetAttribute("Hidden", true)
    end
    return frame, frameStroke
end

local function titleDesc(parent, name, desc, rightReserve, metrics)
    metrics = metrics or METRICS.Card
    local title, descLabel
    if desc then
        local top = math.floor((metrics.DescHeight - (metrics.DescGap + metrics.DescLine)) / 2)
        title = label({
            Position = UDim2.fromOffset(14, top),
            Size = UDim2.new(1, -(14 + rightReserve), 0, metrics.TitleHeight),
            Text = name,
            TextSize = metrics.TextSize,
            Parent = parent,
        })
        descLabel = label({
            Position = UDim2.fromOffset(14, top + metrics.DescGap),
            Size = UDim2.new(1, -(14 + rightReserve), 0, metrics.DescLine),
            Text = desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = parent,
        })
    else
        title = label({
            Position = UDim2.fromOffset(14, 0),
            Size = UDim2.new(1, -(14 + rightReserve), 1, 0),
            Text = name,
            TextSize = metrics.TextSize,
            Parent = parent,
        })
    end
    return title, descLabel
end

local function beginElement(tab, opts, map, className, rightReserve, fallbackName)
    opts = normalize(opts, map)
    local metrics = metricsOf(tab)
    local height = opts.Desc and metrics.DescHeight or metrics.Height
    local frame, frameStroke = card(tab, className or "Frame", height, opts)
    hoverStroke(frame, frameStroke)
    local title, descLabel
    if rightReserve then
        title, descLabel = titleDesc(frame, opts.Name or fallbackName, opts.Desc, rightReserve, metrics)
    end
    return opts, frame, frameStroke, height, title, descLabel
end

local function reserveRight(title, descLabel, width)
    if title then
        title.Size = UDim2.new(1, -(14 + width), title.Size.Y.Scale, title.Size.Y.Offset)
    end
    if descLabel then
        descLabel.Size = UDim2.new(1, -(14 + width), 0, descLabel.Size.Y.Offset)
    end
end

local Tab = {}
Tab.__index = Tab

function Tab:_nextOrder()
    self._order = self._order + 1
    return self._order
end

function Tab:Section(text)
    local visible = not (type(text) == "table" and text.Visible == false)
    if type(text) == "table" then
        text = text.Name or text.Title or ""
    end
    local inset = metricsOf(self).Compact and 14 or 2
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    local text_ = label({
        Position = UDim2.fromOffset(inset, 8),
        Size = UDim2.new(0, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = string.upper(text),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = holder,
    })
    local ruleInset = inset == 2 and 0 or inset
    local rule = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -ruleInset, 0, 16),
        Size = UDim2.new(1, -12, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = holder,
    })
    local function fitRule()
        rule.Size = UDim2.new(1, -(text_.AbsoluteSize.X / self.Window.Scale.Scale + inset + 12 + ruleInset), 0, 1)
    end
    text_:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRule)
    task.defer(fitRule)
    return finishElement(self, { Visible = visible }, {
        Set = function(_, value)
            text_.Text = string.upper(value)
        end,
    }, holder, "Section")
end

function Tab:Divider(opts)
    local caption = type(opts) == "table" and (opts.Text or opts.Name) or type(opts) == "string" and opts or nil
    if caption then
        -- A centred caption with a rule on each side.
        local inset = metricsOf(self).Compact and 14 or 2
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            LayoutOrder = self:_nextOrder(),
            Parent = self.List,
        })
        local text_ = label({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 0, 0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = caption,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = holder,
        })
        padding(text_, 8, 8)
        local rules = {}
        for index, anchor in ipairs({ 0, 1 }) do
            rules[index] = create("Frame", {
                AnchorPoint = Vector2.new(anchor, 0.5),
                Position = UDim2.new(anchor, anchor == 0 and inset or -inset, 0.5, 0),
                Size = UDim2.new(0.5, -inset, 0, 1),
                BackgroundColor3 = Theme.Stroke,
                BorderSizePixel = 0,
                Parent = holder,
            })
        end
        local function fitRules()
            local half = text_.AbsoluteSize.X / self.Window.Scale.Scale / 2
            for _, rule in ipairs(rules) do
                rule.Size = UDim2.new(0.5, -(inset + half), 0, 1)
            end
        end
        text_:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRules)
        task.defer(fitRules)
        return finishElement(self, { Visible = not (type(opts) == "table" and opts.Visible == false) }, {
            Set = function(_, value)
                text_.Text = tostring(value)
            end,
        }, holder, "Divider")
    end
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    if metricsOf(self).Compact then
        line.BackgroundTransparency = 1
        line.Size = UDim2.new(1, 0, 0, 9)
        create("Frame", {
            Position = UDim2.fromOffset(14, 4),
            Size = UDim2.new(1, -28, 0, 1),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            Parent = line,
        })
    end
    return finishElement(self, { Visible = not (type(opts) == "table" and opts.Visible == false) }, {}, line, "Divider")
end

function Tab:Label(opts)
    opts = normalize(opts, { Name = "Text", Title = "Text" })
    -- Obsidian-style: plain full-strength text sitting on the groupbox, wrapping.
    local text_ = label({
        Size = UDim2.new(1, 0, 0, 18),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = Library._rich(opts.Text or ""),
        TextSize = 14,
        FontFace = Fonts.Regular,
        TextColor3 = Library._color(opts.Color) or Theme.Text,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        RichText = true,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    if metricsOf(self).Compact then
        padding(text_, 14, 14)
    else
        padding(text_, 2, 2)
    end
    local handle = {
        Set = function(_, value)
            text_.Text = Library._rich(value)
        end,
        Get = function()
            return text_.Text
        end,
        SetColor = function(_, color)
            tween(text_, { TextColor3 = Library._color(color) or Theme.Text }, 0.25)
        end,
    }
    if type(opts.Update) == "function" then
        local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
        local running = true
        handle._listeners = handle._listeners or {}
        table.insert(handle._listeners, function()
            running = false
        end)
        task.spawn(function()
            while running and text_.Parent do
                local ok, value = isolatedCall(opts.Update)
                if ok and value ~= nil then
                    text_.Text = Library._rich(value)
                elseif not ok then
                    warn("[AirFlow] label update error: " .. tostring(value))
                end
                task.wait(rate)
            end
        end)
        function handle:SetUpdateRate(seconds)
            rate = math.max(tonumber(seconds) or rate, 0.05)
        end
    end
    return finishElement(self, opts, handle, text_, "Label")
end

function Tab:Paragraph(opts)
    opts = normalize(opts, { Title = "Name" })
    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if metricsOf(self).Compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = frame,
    })
    label({
        Size = UDim2.new(1, 0, 0, 14),
        Text = opts.Name or "",
        LayoutOrder = 1,
        Parent = frame,
    })
    local content = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = Library._rich(opts.Content or ""),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        RichText = true,
        LayoutOrder = 2,
        Parent = frame,
    })
    return finishElement(self, opts, {
        Set = function(_, value)
            content.Text = Library._rich(value)
        end,
    }, frame, "Paragraph")
end

local function rowButton(tab, opts)
    local primary = opts.Style == "Primary"
    local boxHeight = TOUCH and 34 or 28
    local height = boxHeight + 6 + (opts.Desc and 16 or 0)
    local button = card(tab, "TextButton", height, opts)

    local box = create("Frame", {
        Position = UDim2.fromOffset(14, 3),
        Size = UDim2.new(1, -28, 0, boxHeight),
        BackgroundColor3 = primary and Theme.Accent or Theme.Surface3,
        BackgroundTransparency = primary and 0.12 or 0.45,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = button,
    })
    corner(box, UDim.new(0, 6))
    local boxStroke = stroke(box, primary and Theme.Accent or Theme.Stroke, primary and 0.4 or 0)

    local row = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = box,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = row,
    })
    local textColor = primary and Theme.AccentDark or Theme.Text
    if opts.Icon then
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = primary and Theme.AccentDark or Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = row,
        })
        applyIcon(image, opts.Icon)
    end
    local title = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = opts.Name or "Button",
        TextSize = 13,
        TextColor3 = textColor,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = row,
    })
    if opts.Desc then
        label({
            Position = UDim2.fromOffset(14, boxHeight + 6),
            Size = UDim2.new(1, -28, 0, 14),
            Text = opts.Desc,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = button,
        })
    end

    local restBg = primary and 0.12 or 0.45
    button.MouseEnter:Connect(function()
        tween(box, { BackgroundTransparency = primary and 0 or 0.2 }, 0.12)
        tween(boxStroke, primary and { Transparency = 0 } or { Color = Theme.StrokeHover }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(box, { BackgroundTransparency = restBg }, 0.25)
        tween(boxStroke, primary and { Transparency = 0.4 } or { Color = Theme.Stroke }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(box)
        safeCall(opts.Callback)
    end)

    return finishElement(tab, opts, {
        _title = title,
        _titleColor = textColor,
        _fillHost = box,
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
end

function Tab:Button(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if (opts.Confirm or opts.HoldToConfirm) and not opts._gated then
        return Library._gateButton(self, opts)
    end
    if metricsOf(self).Compact then
        return rowButton(self, opts)
    end
    local primary = opts.Style == "Primary"
    local height = opts.Desc and CARD_HEIGHT_DESC or CARD_HEIGHT
    local button, buttonStroke = card(self, "TextButton", height, opts)
    button.ClipsDescendants = true

    if primary then
        tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
        tween(buttonStroke, { Color = Theme.Accent }, 0)
        buttonStroke.Transparency = 0.4
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0 }, 0.12)
            tween(buttonStroke, { Transparency = 0 }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.12 }, 0.25)
            tween(buttonStroke, { Transparency = 0.4 }, 0.25)
        end)
    else
        hoverStroke(button, buttonStroke)
    end

    local textColor = primary and Theme.AccentDark or Theme.Text
    local iconOffset = 0
    if opts.Icon then
        glowIcon(button, opts.Icon, primary and Theme.AccentDark or Theme.Accent, UDim2.new(0, 14, 0.5, 0))
        iconOffset = 26
    end
    local title = titleDesc(button, opts.Name or "Button", opts.Desc, 30)
    if iconOffset > 0 then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                child.Position = child.Position + UDim2.fromOffset(iconOffset, 0)
                child.Size = child.Size - UDim2.fromOffset(iconOffset, 0)
            end
        end
    end
    if primary then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                tween(child, { TextColor3 = textColor }, 0)
            end
        end
    end

    glowIcon(button, BUTTON_HINT_ICON, primary and Theme.AccentDark or Theme.Muted, UDim2.new(1, -30, 0.5, 0))

    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(opts.Callback)
    end)

    return finishElement(self, opts, {
        _title = title,
        _titleColor = textColor,
        _fillHost = button,
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
end

function Tab:Toggle(opts)
    local button, buttonStroke
    opts, button, buttonStroke = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" }, "TextButton", 56, "Toggle")

    local pill = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = TOUCH and UDim2.fromOffset(44, 24) or UDim2.fromOffset(36, 20),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = button,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill, Theme.Stroke)

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = TOUCH and UDim2.fromOffset(18, 18) or UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = pill,
    })
    corner(knob, UDim.new(1, 0))
    local pillGlow = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 24, 1, 24),
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 1,
        ZIndex = 0,
        Parent = pill,
    })

    local self_ = { Value = opts.Default == true }

    local function render(animate)
        local on = self_.Value
        local duration = animate and 0.25 or 0
        tween(pill, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
        tween(pillGlow, { ImageTransparency = on and 0.75 or 1 }, duration)
        local knobSize = TOUCH and 18 or 14
        tween(knob, {
            Position = on and UDim2.new(0, (TOUCH and 44 or 36) - 3 - knobSize, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
        }, duration, Enum.EasingStyle.Back)
        if animate then
            tween(knob, { Size = UDim2.fromOffset(knobSize + 4, knobSize - 2) }, 0.08)
            task.delay(0.08, function()
                tween(knob, { Size = UDim2.fromOffset(knobSize, knobSize) }, 0.2, Enum.EasingStyle.Back)
            end)
        end
    end

    local fromClick = false
    function self_:Set(value, silent)
        value = value == true
        if value == self_.Value then
            return
        end
        self_.Value = value
        render(true)
        if not fromClick then
            flashStroke(buttonStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end

    function self_:Get()
        return self_.Value
    end

    render(false)
    button.MouseButton1Click:Connect(function()
        fromClick = true
        self_:Set(not self_.Value)
        fromClick = false
    end)

    local handle = finishElement(self, opts, self_, button, "Toggle")
    if self_.Value then
        safeCall(opts.Callback, true)
    end
    return handle
end

function Tab:Slider(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" })
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local numbers = numberFormat(min, max, step)

    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local height = metrics.Slider
    local frame, frameStroke = card(self, "Frame", height, opts)
    hoverStroke(frame, frameStroke)

    label({
        Position = UDim2.fromOffset(14, compact and 5 or 12),
        Size = UDim2.new(1, -120, 0, 18),
        Text = opts.Name or "Slider",
        TextSize = metrics.TextSize,
        Parent = frame,
    })

    local valueChip = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, compact and -14 or -10, 0, compact and 2 or 9),
        Size = UDim2.fromOffset(40, 24),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(valueChip, UDim.new(0, 6))
    local chipStroke = stroke(valueChip)
    local valueLabel = label({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = valueChip,
    })
    local valueBox = create("TextBox", {
        Position = UDim2.fromOffset(9, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Visible = false,
        Parent = valueChip,
    })
    create("UISizeConstraint", { MinSize = Vector2.new(14, 0), Parent = valueBox })
    local suffixLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = suffix,
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        Parent = valueChip,
    })
    local chipButton = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = valueChip,
    })
    local editing = false
    local function fitChip(instant)
        local width
        if editing then
            width = 9 + valueBox.AbsoluteSize.X / (self.Window.Scale.Scale) + suffixLabel.TextBounds.X + 9
            suffixLabel.Position = UDim2.fromOffset(9 + valueBox.AbsoluteSize.X / (self.Window.Scale.Scale), 0)
        else
            width = valueLabel.TextBounds.X + 18
        end
        width = math.max(width, 36)
        if instant then
            valueChip.Size = UDim2.fromOffset(width, 24)
        else
            tween(valueChip, { Size = UDim2.fromOffset(width, 24) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not editing then
            fitChip(false)
        end
    end)
    valueBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if editing then
            fitChip(false)
        end
    end)

    local track = create("Frame", {
        Position = UDim2.new(0, 14, 0, height - (compact and 13 or 18)),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))

    local knobGlow = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 0.85,
        ZIndex = 2,
        Parent = track,
    })
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = track,
    })
    corner(knob, UDim.new(1, 0))

    local hit = create("TextButton", {
        Position = UDim2.new(0, 8, 0, height - (compact and 13 or 18) - (TOUCH and 19 or 13)),
        Size = UDim2.new(1, -16, 0, TOUCH and 40 or 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = frame,
    })

    local self_ = { Value = math.clamp(opts.Default or min, min, max) }
    local dragging = false
    chipButton.MouseEnter:Connect(function()
        tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    chipButton.MouseLeave:Connect(function()
        if not valueBox:IsFocused() then
            tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        end
    end)
    chipButton.MouseButton1Click:Connect(function()
        editing = true
        valueBox.Text = numbers.format(self_.Value)
        valueLabel.Visible = false
        valueBox.Visible = true
        suffixLabel.Visible = suffix ~= ""
        chipButton.Visible = false
        tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
        valueBox:CaptureFocus()
        task.defer(fitChip, false)
    end)
    valueBox.FocusLost:Connect(function()
        local typed = tonumber(valueBox.Text)
        editing = false
        valueBox.Visible = false
        suffixLabel.Visible = false
        valueLabel.Visible = true
        chipButton.Visible = true
        tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        if typed then
            self_:Set(typed)
        end
        fitChip(false)
    end)
    hit.MouseEnter:Connect(function()
        if not dragging then
            tween(knobGlow, { ImageTransparency = 0.78, Size = UDim2.fromOffset(34, 34) }, 0.15)
        end
    end)
    hit.MouseLeave:Connect(function()
        if not dragging then
            tween(knobGlow, { ImageTransparency = 0.85, Size = UDim2.fromOffset(28, 28) }, 0.2)
        end
    end)

    local snap = numbers.snap

    local function fraction()
        return (max - min) == 0 and 0 or (self_.Value - min) / (max - min)
    end

    local function moveTo(frac, duration, style)
        style = style or Enum.EasingStyle.Linear
        tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, duration, style)
        tween(knob, { Position = UDim2.new(frac, 0, 0.5, 0) }, duration, style)
        tween(knobGlow, { Position = UDim2.new(frac, 0, 0.5, 0) }, duration, style)
    end

    local function render(duration, style)
        moveTo(fraction(), duration, style)
        valueLabel.Text = numbers.format(self_.Value) .. suffix
    end

    local function settleTo(previousFrac)
        local target = fraction()
        local width = math.max(track.AbsoluteSize.X, 1)
        local overshoot = (target >= previousFrac and 1 or -1) * (5 / width)
        moveTo(math.clamp(target + overshoot, 0, 1), 0.22, Enum.EasingStyle.Quint)
        task.delay(0.22, function()
            if not dragging then
                moveTo(fraction(), 0.18, Enum.EasingStyle.Quint)
            end
        end)
        valueLabel.Text = numbers.format(self_.Value) .. suffix
    end

    local function bounceKnob()
        tween(knob, { Size = UDim2.fromOffset(14, 12) }, 0.08)
        tween(knobGlow, { Size = UDim2.fromOffset(32, 32), ImageTransparency = 0.78 }, 0.12)
        task.delay(0.1, function()
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Quint)
            tween(knobGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.25)
        end)
    end

    function self_:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == self_.Value then
            return
        end
        local previousFrac = fraction()
        self_.Value = value
        if dragging then
            render(0.05)
        else
            settleTo(previousFrac)
            bounceKnob()
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end

    function self_:Get()
        return self_.Value
    end

    local function updateFromX(x)
        local frac = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        self_:Set(min + (max - min) * frac)
    end

    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            self_.Dragging = true
            tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.15, Enum.EasingStyle.Back)
            tween(knobGlow, { Size = UDim2.fromOffset(44, 44), ImageTransparency = 0.7 }, 0.15)
            updateFromX(pointerPosition().X)
        end
    end)

    self.Window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            updateFromX(pointerPosition().X)
        end
    end, self_)

    self.Window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            self_.Dragging = false
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.2)
            tween(knobGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.2)
            safeCall(opts.OnRelease, self_.Value)
        end
    end, self_)

    self_.Value = snap(self_.Value)
    render(0)
    task.defer(fitChip, true)
    return finishElement(self, opts, self_, frame, "Slider")
end

function Tab:Dropdown(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentOption = "Default", Value = "Default", MultipleOptions = "Multi", Values = "Options" })
    if opts.Multi and type(opts.Default) ~= "table" and opts.Default ~= nil then
        opts.Default = { opts.Default }
    elseif not opts.Multi and type(opts.Default) == "table" then
        opts.Default = opts.Default[1]
    end
    local multi = opts.Multi == true
    local options = opts.Options or {}
    local frame, frameStroke, height
    opts, frame, frameStroke, height = beginElement(self, opts, {}, "Frame")
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local chipHeight = metrics.Chip
    local window = self.Window
    local ROW = TOUCH and 34 or 22
    local MAX_ROWS = opts.MaxRows or 6
    -- Stacked (the default in compact rows): the chip spans the whole row,
    -- with the name (if any) above it.
    local stacked = compact and opts.Stacked ~= false
    local stackTop = 2
    if stacked then
        stackTop = (opts.Name or "") ~= "" and 20 or 2
        chipHeight = TOUCH and 34 or 30
        height = stackTop + chipHeight + 4
        frame.Size = UDim2.new(1, 0, 0, height)
    end

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    local titleLabel, descLabel
    if not stacked then
        titleLabel, descLabel = titleDesc(header, opts.Name or "Dropdown", opts.Desc, 180, metrics)
    elseif stackTop > 2 then
        titleLabel = label({
            Position = UDim2.fromOffset(14, 1),
            Size = UDim2.new(1, -28, 0, 16),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = header,
        })
    end

    local chip = create("Frame", {
        AnchorPoint = stacked and Vector2.zero or Vector2.new(1, 0.5),
        Position = stacked and UDim2.fromOffset(14, stackTop) or UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(60, chipHeight),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = header,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    local valueLabel = label({
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -34, 1, 0),
        TextColor3 = Theme.Muted,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = chip,
    })
    local arrow = arrowIndicator(chip, 1, -6)
    local measure = label({
        Size = UDim2.fromOffset(0, chipHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        Visible = false,
        Parent = chip,
    })
    local fullText = ""
    local function trimmed()
        local maxText = (stacked and frame.AbsoluteSize.X / window.Scale.Scale - 28 or compact and rowControlWidth(frame, window) or 190) - 10 - 34
        measure.Text = fullText
        if measure.TextBounds.X <= maxText then
            return fullText
        end
        local text = fullText
        while #text > 1 do
            text = text:sub(1, -2)
            measure.Text = text .. ".."
            if measure.TextBounds.X <= maxText then
                return text .. ".."
            end
        end
        return ".."
    end
    local function fitChip(instant)
        if stacked then
            chip.Size = UDim2.new(1, -28, 0, chipHeight)
            return
        end
        local width
        if compact then
            width = rowControlWidth(frame, window)
        else
            width = math.clamp(valueLabel.TextBounds.X + 10 + 34, 60, 190)
        end
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            chip.Size = UDim2.fromOffset(width, chipHeight)
        else
            tween(chip, { Size = UDim2.fromOffset(width, chipHeight) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not compact then
            fitChip(false)
        end
    end)
    if compact then
        -- The chip follows the row every frame; re-measuring the text waits
        -- until the width stops changing so resizing stays cheap.
        local lastWidth, pending = 0, false
        frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            local width = frame.AbsoluteSize.X
            if width == lastWidth then
                return
            end
            lastWidth = width
            fitChip(true)
            if not pending then
                pending = true
                task.delay(0.12, function()
                    pending = false
                    valueLabel.Text = trimmed()
                end)
            end
        end)
    end

    -- Popup: floats over the window under the chip, with search, bulk
    -- actions for multi selection and a scrolling list of checkbox rows.
    -- The popup is a plain clipped frame that unfolds out of the chip, so text
    -- stays crisp. The shadow sits outside the clip.
    local popup = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Size = UDim2.fromOffset(220, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 45,
        Parent = window.Body,
    })
    popup:SetAttribute("NoDrag", true)
    local popupShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-18, -12),
        Size = UDim2.new(1, 36, 1, 36),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = popup,
    })
    local panel = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = popup,
    })
    corner(panel, UDim.new(0, 10))
    local panelStroke = stroke(panel, Theme.Stroke, 1)
    edgeHighlight(panel)
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 120),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    padding(inner, 8, 8, 8, 8)

    local searchHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = inner,
    })
    corner(searchHolder, UDim.new(0, 7))
    local searchStroke = stroke(searchHolder)
    local searchIconHolder, searchIcon = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIconHolder.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = opts.SearchPlaceholder or "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = searchHolder,
    })
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    searchBox.FocusLost:Connect(function()
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
    end)

    local actions = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Visible = multi,
        Parent = inner,
    })
    local function actionButton(text, position)
        local button = create("TextButton", {
            Position = position,
            Size = UDim2.new(0.5, -3, 1, 0),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            Parent = actions,
        })
        corner(button, UDim.new(0, 6))
        local buttonStroke = stroke(button)
        label({
            Size = UDim2.fromScale(1, 1),
            Text = text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = button,
        })
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0.05 }, 0.15)
            tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.35 }, 0.25)
            tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        end)
        button.MouseButton1Click:Connect(function()
            ripple(button)
        end)
        return button
    end
    local selectAll = actionButton(opts.SelectAllText or "Select all", UDim2.fromOffset(0, 0))
    local clearAll = actionButton(opts.ClearAllText or "Clear all", UDim2.new(0.5, 3, 0, 0))

    local list = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 100),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand: AutomaticCanvasSize under the window's UIScale
        -- sometimes leaves the canvas short, so the list would not scroll.
        CanvasSize = UDim2.new(),
        Parent = inner,
    })
    local noResults = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = opts.NoResultsText or "No results",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = false,
        Parent = list,
    })

    local self_ = { Open = false }
    local selected = {}
    local filter = ""
    -- The list is virtual: only the rows in view exist, and they are reused
    -- as it scrolls, so thousands of options cost the same as a handful.
    local pool = {}
    local shown = {}
    local lowerKeys = {}
    local STEP = ROW + 2

    -- CanvasPosition is in screen pixels while rows are laid out in unscaled
    -- units, so under a UIScale the visible slice has to be scaled back.
    local function canvasScale()
        local logical = list.CanvasSize.Y.Offset
        return logical > 0 and list.AbsoluteCanvasSize.Y / logical or 1
    end

    local function lowerOf(option)
        local key = lowerKeys[option]
        if key == nil then
            key = string.lower(tostring(option))
            lowerKeys[option] = key
        end
        return key
    end

    local function matches(option)
        return filter == "" or string.find(lowerOf(option), filter, 1, true) ~= nil
    end

    -- Option labels are rich text, so the part matching the search can light up.
    local function escapeRich(text)
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end
    local function optionText(option)
        local text = tostring(option)
        local at = filter ~= "" and string.find(string.lower(text), filter, 1, true)
        if not at then
            return escapeRich(text)
        end
        local stop = at + #filter - 1
        return escapeRich(text:sub(1, at - 1))
            .. '<font color="#' .. Theme.Accent:ToHex() .. '"><b>' .. escapeRich(text:sub(at, stop)) .. "</b></font>"
            .. escapeRich(text:sub(stop + 1))
    end

    if multi then
        for _, value in ipairs(opts.Default or {}) do
            selected[value] = true
        end
    elseif opts.Default ~= nil then
        selected[opts.Default] = true
    end

    local function currentValue()
        if multi then
            local picked = {}
            for _, option in ipairs(options) do
                if selected[option] then
                    table.insert(picked, option)
                end
            end
            return picked
        end
        for _, option in ipairs(options) do
            if selected[option] then
                return option
            end
        end
        return nil
    end

    -- Rows are plain text: the pick reads in the accent, hovering lifts any row.
    local function restRow(entry, duration)
        local on, hover = entry.On == true, entry.Hover == true
        tween(entry.Frame, { BackgroundTransparency = hover and 0.6 or 1 }, duration)
        tween(entry.Label, { TextColor3 = on and Theme.Accent or Theme.Text }, duration)
    end

    local function paintOption(button, animate)
        local on = selected[button.Option] == true
        if button.On == on and animate then
            return
        end
        button.On = on
        local duration = animate and 0.18 or 0
        restRow(button, duration)
        if multi then
            tween(button.Box, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
            tween(button.BoxStroke, { Color = on and Theme.Accent or Theme.Stroke }, duration)
        else
            tween(button.Bar, {
                BackgroundTransparency = on and 0 or 1,
                Size = UDim2.fromOffset(3, on and ROW - 10 or 4),
            }, animate and 0.3 or 0, Enum.EasingStyle.Quint)
        end
        tween(button.Check, { ImageTransparency = on and 0 or 1 }, duration)
        if animate and on then
            button.CheckScale.Scale = 0.5
            tween(button.CheckScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
        else
            button.CheckScale.Scale = 1
        end
    end

    local function renderValue(animate)
        local value = currentValue()
        if #options == 0 then
            fullText = opts.EmptyText or "None"
        elseif multi then
            -- Two names at most, then a count, so a long pick stays readable.
            if #value > 2 then
                fullText = tostring(value[1]) .. ", " .. tostring(value[2]) .. "  +" .. (#value - 2)
            else
                fullText = #value > 0 and table.concat(value, ", ") or (opts.NoneText or "None")
            end
        else
            fullText = value ~= nil and tostring(value) or (opts.NoneText or "None")
        end
        valueLabel.Text = trimmed()
        -- A picked value reads in full colour; "None" stays muted.
        local picked = #options > 0 and (if multi then #value > 0 else value ~= nil)
        tween(valueLabel, { TextColor3 = picked and Theme.Text or Theme.Muted }, animate and 0.15 or 0)
        for _, button in ipairs(pool) do
            if button.Option ~= nil then
                paintOption(button, animate)
            end
        end
    end

    local renderRows

    local function visibleCount()
        return #shown
    end

    local searchShown = true
    local targetSize = Vector2.new(220, 120)
    local opened = false
    local function layoutPopup(instant)
        searchShown = opts.Searchable ~= false and #options > (opts.SearchAfter or 0)
        searchHolder.Visible = searchShown
        local top = 0
        if searchShown then
            top += 38
        end
        actions.Position = UDim2.fromOffset(0, top)
        if multi and #options > 0 then
            actions.Visible = true
            top += 34
        else
            actions.Visible = false
        end
        local count = visibleCount()
        noResults.Visible = count == 0
        local rows = math.clamp(count, 1, MAX_ROWS)
        local listHeight = rows * ROW + (rows - 1) * 2
        list.CanvasSize = UDim2.fromOffset(0, math.max(count, 1) * (ROW + 2) - 2)
        local scale = window.Scale.Scale
        -- Shrink the list to whichever side of the chip has more room, so the
        -- popup never runs off a short window (phones in landscape).
        local host = window:_popupHost(frame)
        local bodyHeight = host.AbsoluteSize.Y / scale
        local chipTop = (chip.AbsolutePosition.Y - host.AbsolutePosition.Y) / scale
        local room = math.max(bodyHeight - (chipTop + chip.AbsoluteSize.Y / scale) - 14, chipTop - 14) - top - 16
        if room >= ROW then
            listHeight = math.min(listHeight, room)
        end
        list.Position = UDim2.fromOffset(0, top)
        list.Size = UDim2.new(1, 0, 0, listHeight)
        renderRows()
        local width = math.max(math.floor(chip.AbsoluteSize.X / scale), opts.PopupWidth or 210)
        local bodyWidth = host.AbsoluteSize.X / scale
        width = math.min(width, math.max(bodyWidth - 16, 120))
        targetSize = Vector2.new(width, top + listHeight + 16)
        inner.Size = UDim2.new(1, 0, 0, targetSize.Y)
        if not opened then
            return
        end
        if instant then
            popup.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
        else
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, targetSize.Y) }, 0.22, Enum.EasingStyle.Quint)
        end
    end

    local function applyFilter()
        if filter == "" then
            shown = options
        else
            shown = {}
            for _, option in ipairs(options) do
                if matches(option) then
                    table.insert(shown, option)
                end
            end
        end
        renderRows()
    end

    local scroller = nil
    local function place()
        local body = window:_popupHost(frame)
        local scale = window.Scale.Scale
        if scroller then
            local centre = chip.AbsolutePosition + chip.AbsoluteSize / 2
            if not pointInside(centre, scroller) then
                self_:SetOpen(false)
                return
            end
        end
        local bodySize = body.AbsoluteSize / scale
        local chipPosition = (chip.AbsolutePosition - body.AbsolutePosition) / scale
        local chipSize = chip.AbsoluteSize / scale
        local right = math.clamp(chipPosition.X + chipSize.X, targetSize.X + 8, math.max(bodySize.X - 8, targetSize.X + 8))
        local below = chipPosition.Y + chipSize.Y + 2
        -- Opening upward pins the content to the bottom edge so it unfolds from the chip.
        if below + targetSize.Y > bodySize.Y - 8 and chipPosition.Y - 2 - targetSize.Y >= 8 then
            popup.AnchorPoint = Vector2.new(1, 1)
            popup.Position = UDim2.fromOffset(right, chipPosition.Y - 2)
            inner.AnchorPoint = Vector2.new(0, 1)
            inner.Position = UDim2.fromScale(0, 1)
        else
            popup.AnchorPoint = Vector2.new(1, 0)
            popup.Position = UDim2.fromOffset(right, below)
            inner.AnchorPoint = Vector2.zero
            inner.Position = UDim2.fromScale(0, 0)
        end
    end

    local stopFollowing = nil
    local closeGeneration = 0
    -- The page behind stops scrolling while the popup is open, so wheel and
    -- swipe input always reach the list instead of dragging the page away.
    local lockedScroller = nil
    local function unlockScroller()
        if lockedScroller then
            lockedScroller.ScrollingEnabled = true
            lockedScroller = nil
        end
    end
    local function scrollToSelected()
        list.CanvasPosition = Vector2.zero
        if multi then
            return
        end
        local value = currentValue()
        if value == nil then
            return
        end
        local index = table.find(shown, value)
        if index then
            list.CanvasPosition = Vector2.new(0, math.max(0, (index - 2) * STEP) * canvasScale())
        end
    end
    local function setOpen(open)
        if open == self_.Open then
            return
        end
        self_.Open = open
        arrow:Set(open)
        tween(chipStroke, { Color = open and Theme.Accent or Theme.Stroke, Transparency = open and 0.35 or 0 }, 0.2)
        tween(chip, { BackgroundColor3 = open and Theme.Surface or Theme.Background }, 0.2)
        closeGeneration += 1
        if open then
            if window._closePopup and window._closePopup ~= self_._close then
                window._closePopup()
            end
            window._closePopup = self_._close
            scroller = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
            if scroller and scroller.ScrollingEnabled then
                lockedScroller = scroller
                scroller.ScrollingEnabled = false
            end
            -- Drawn over a floating panel when the dropdown lives in one.
            popup.Parent = window:_popupHost(frame)
            filter = ""
            searchBox.Text = ""
            searchBox.PlaceholderText = opts.SearchPlaceholder or (#options > 6 and ("Search " .. #options .. " options") or "Search")
            applyFilter()
            layoutPopup(true)
            renderValue(false)
            scrollToSelected()
            opened = true
            popup.Size = UDim2.fromOffset(targetSize.X, 0)
            place()
            popup.Visible = true
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, targetSize.Y) }, 0.3, Enum.EasingStyle.Quint)
            tween(panelStroke, { Transparency = 0 }, 0.12)
            tween(popupShadow, { ImageTransparency = 0.4 }, 0.3)
            if not stopFollowing then
                stopFollowing = window:_listen("Render", place)
            end
        else
            if window._closePopup == self_._close then
                window._closePopup = nil
            end
            unlockScroller()
            if searchBox:IsFocused() then
                searchBox:ReleaseFocus()
            end
            opened = false
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, 0) }, 0.2, Enum.EasingStyle.Quint)
            tween(popupShadow, { ImageTransparency = 1 }, 0.16)
            local generation = closeGeneration
            task.delay(0.14, function()
                if closeGeneration == generation and not self_.Open then
                    tween(panelStroke, { Transparency = 1 }, 0.06)
                end
            end)
            task.delay(0.21, function()
                if closeGeneration == generation and not self_.Open then
                    popup.Visible = false
                    if stopFollowing then
                        stopFollowing()
                        stopFollowing = nil
                    end
                end
            end)
        end
    end
    self_._close = function()
        setOpen(false)
    end

    local function commit()
        renderValue(true)
        safeCall(opts.Callback, currentValue())
    end

    local function newEntry()
        local row = create("TextButton", {
            Size = UDim2.new(1, -6, 0, ROW),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            Parent = list,
        })
        corner(row, UDim.new(0, 7))
        -- Multi selection ticks a checkbox on the left. A single pick
        -- gets an accent bar on the left edge.
        local box, boxStroke, bar, check
        if multi then
            box = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 8, 0.5, 0),
                Size = UDim2.fromOffset(18, 18),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Parent = row,
            })
            corner(box, UDim.new(0, 5))
            boxStroke = stroke(box, Theme.Stroke)
            check = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.AccentDark,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = box,
            })
        else
            bar = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 2, 0.5, 0),
                Size = UDim2.fromOffset(3, 4),
                BackgroundColor3 = Theme.Accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Parent = row,
            })
            corner(bar, UDim.new(1, 0))
            check = create("ImageLabel", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(14, 14),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Accent,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Visible = false,
                Parent = row,
            })
        end
        applyIcon(check, "check")
        local checkScale = create("UIScale", { Parent = check })
        local text_ = label({
            Position = UDim2.fromOffset(multi and 36 or 14, 0),
            Size = UDim2.new(1, multi and -44 or -46, 1, 0),
            Text = "",
            TextSize = 13,
            TextColor3 = Theme.Text,
            RichText = true,
            Parent = row,
        })
        local entry = { Option = nil, Frame = row, Box = box, BoxStroke = boxStroke, Bar = bar, Check = check, CheckScale = checkScale, Label = text_, On = nil, Hover = false }
        local isTap = tapGuard(row, function()
            return list
        end)
        row.MouseEnter:Connect(function()
            -- Touch fires enter without a matching leave; skip the hover.
            if usingTouch() then
                return
            end
            entry.Hover = true
            restRow(entry, 0.15)
            if boxStroke and not selected[entry.Option] then
                tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
            end
        end)
        row.MouseLeave:Connect(function()
            entry.Hover = false
            restRow(entry, 0.25)
            if boxStroke and not selected[entry.Option] then
                tween(boxStroke, { Color = Theme.Stroke }, 0.25)
            end
        end)
        row.MouseButton1Click:Connect(function()
            local option = entry.Option
            if option == nil or not isTap() then
                return
            end
            if selected[option] then
                if not multi and opts.AllowNone == false then
                    setOpen(false)
                    return
                end
                selected[option] = nil
            else
                if not multi then
                    selected = {}
                end
                selected[option] = true
            end
            commit()
            if not multi then
                setOpen(false)
            end
        end)
        return entry
    end

    -- Binds the pool to the rows in view: row i of the filtered list sits at
    -- (i - 1) * STEP in the canvas.
    renderRows = function()
        if not self_.Open then
            return
        end
        -- Each index keeps the same pool slot while it stays in view (slot =
        -- index mod count), so scrolling only rebinds rows entering the edge
        -- instead of reshuffling every row each step.
        local first = math.max(math.floor(list.CanvasPosition.Y / canvasScale() / STEP), 1)
        local count = math.ceil(list.Size.Y.Offset / STEP) + 3
        for slot = 1, math.max(count, #pool) do
            local index = slot <= count and first + (slot - first) % count or 0
            local option = slot <= count and shown[index] or nil
            local entry = pool[slot]
            if option == nil then
                if entry then
                    entry.Frame.Visible = false
                    entry.Option = nil
                end
            else
                if not entry then
                    entry = newEntry()
                    pool[slot] = entry
                end
                entry.Frame.Position = UDim2.fromOffset(0, (index - 1) * STEP)
                local text = optionText(option)
                local fresh = entry.Option ~= option
                if fresh or entry.Text ~= text then
                    entry.Text = text
                    entry.Label.Text = text
                end
                if fresh then
                    entry.Option = option
                    entry.On = nil
                    paintOption(entry, false)
                end
                entry.Frame.Visible = true
            end
        end
    end
    list:GetPropertyChangedSignal("CanvasPosition"):Connect(renderRows)

    local function buildOptions()
        table.clear(lowerKeys)
        for _, entry in ipairs(pool) do
            entry.Option = nil
        end
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end

    selectAll.MouseButton1Click:Connect(function()
        for _, option in ipairs(shown) do
            selected[option] = true
        end
        commit()
    end)
    clearAll.MouseButton1Click:Connect(function()
        selected = {}
        commit()
    end)

    function self_:Set(value, silent)
        selected = {}
        if multi then
            for _, item in ipairs(type(value) == "table" and value or { value }) do
                selected[item] = true
            end
        elseif value ~= nil then
            selected[value] = true
        end
        renderValue(self_.Open)
        flashStroke(frameStroke)
        if not silent then
            safeCall(opts.Callback, currentValue())
        end
    end

    function self_:Get()
        return currentValue()
    end

    local function sameValue(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return a == b
        end
        if #a ~= #b then
            return false
        end
        for index, item in ipairs(a) do
            if b[index] ~= item then
                return false
            end
        end
        return true
    end

    -- A kept pick only counts once its option exists, so a list filled in after a
    -- config load changes the value; the callback runs so scripts see it.
    function self_:Refresh(newOptions, keepSelection, silent)
        local before = currentValue()
        options = newOptions or {}
        if not keepSelection then
            selected = {}
        end
        buildOptions()
        renderValue(false)
        if not silent and not sameValue(before, currentValue()) then
            safeCall(opts.Callback, currentValue())
        end
    end

    -- SetOptions(list, { KeepSelection = true, Silent = false }): replace the
    -- options. Picks are kept by default; a boolean works as KeepSelection.
    function self_:SetOptions(newOptions, settings)
        local keep, silent = true, false
        if type(settings) == "boolean" then
            keep = settings
        elseif type(settings) == "table" then
            local wanted = settings.KeepSelection
            if wanted == nil then
                wanted = settings.keepSelection
            end
            if wanted ~= nil then
                keep = wanted ~= false
            end
            silent = settings.Silent == true or settings.silent == true
        end
        self_:Refresh(newOptions, keep, silent)
    end

    function self_:GetOptions()
        return table.clone(options)
    end

    -- Every pick, including ones whose option isn't in the list right now, so
    -- saving never drops them.
    function self_:_saveValue()
        local picked = currentValue()
        if multi then
            local seen = {}
            for _, item in ipairs(picked) do
                seen[item] = true
            end
            for item in pairs(selected) do
                if not seen[item] then
                    table.insert(picked, item)
                end
            end
            return picked
        end
        if picked == nil then
            picked = next(selected)
        end
        return picked
    end

    function self_:SetOpen(open)
        setOpen(open == true)
    end

    local headerTap = tapGuard(header, function()
        return frame:FindFirstAncestorWhichIsA("ScrollingFrame")
    end)
    header.MouseButton1Click:Connect(function()
        if headerTap() then
            setOpen(not self_.Open)
        end
    end)
    -- The chip answers the pointer before it is opened.
    header.MouseEnter:Connect(function()
        if not self_.Open and not usingTouch() then
            tween(chipStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(chip, { BackgroundColor3 = Theme.Surface }, 0.15)
        end
    end)
    header.MouseLeave:Connect(function()
        if not self_.Open then
            tween(chipStroke, { Color = Theme.Stroke }, 0.25)
            tween(chip, { BackgroundColor3 = Theme.Background }, 0.25)
        end
    end)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        filter = string.lower(searchBox.Text)
        list.CanvasPosition = Vector2.zero
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end)
    self_._listeners = {
        function()
            setOpen(false)
            unlockScroller()
            if stopFollowing then
                stopFollowing()
                stopFollowing = nil
            end
            popup:Destroy()
        end,
    }
    window:_listen("Began", function(input)
        if not self_.Open then
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape then
            setOpen(false)
        elseif isPress(input) then
            local point = pointerPosition()
            if not pointInside(point, popup) and not pointInside(point, header) then
                setOpen(false)
            end
        end
    end, self_)

    buildOptions()
    renderValue(false)
    task.defer(fitChip, true)
    return finishElement(self, opts, self_, frame, "Dropdown")
end

Library._amountSuffixes = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }

function Library._parseAmount(text)
    text = string.lower(tostring(text)):gsub("[%s,_%$]", "")
    text = text:gsub("kg$", ""):gsub("/s$", "")
    local number = tonumber(text)
    if number then
        return number
    end
    local digits, suffix = text:match("^(.-)(%a+)$")
    local scale = suffix and Library._amountSuffixes[suffix]
    number = digits and tonumber(digits)
    if number and scale then
        return number * scale
    end
    return nil
end

function Tab:Input(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", PlaceholderText = "Placeholder", CurrentValue = "Default", Value = "Default" }, "Frame", 160, "Input")
    local compact = metricsOf(self).Compact
    local boxHeight = compact and metricsOf(self).Chip + 2 or 30

    local boxHolder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(170, boxHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(boxHolder, UDim.new(0, 6))
    local boxStroke = stroke(boxHolder)

    local boxIcon = opts.Icon
    if boxIcon then
        glowIcon(boxHolder, boxIcon, Theme.Muted, UDim2.new(0, 8, 0.5, 0))
    end
    local box = create("TextBox", {
        Position = UDim2.fromOffset(boxIcon and 30 or 8, 0),
        Size = UDim2.new(1, boxIcon and -38 or -16, 1, 0),
        BackgroundTransparency = 1,
        Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = compact and 13 or 14,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = boxHolder,
    })
    boxHolder.ClipsDescendants = true

    local lastText = box.Text
    local value = opts.Numeric and Library._parseAmount(lastText) or nil
    if opts.Numeric and not value then
        lastText = ""
    end
    local focused = false
    local textInset = (boxIcon and 30 or 8) + 8
    local function fitBox(instant)
        local width
        if compact then
            width = rowControlWidth(frame, self.Window)
        else
            local cardWidth = frame.AbsoluteSize.X / self.Window.Scale.Scale
            local maxWidth = math.clamp(cardWidth - 14 - 110 - 20, 100, 200)
            local measured = box.TextBounds.X
            if #box.Text == 0 then
                measured = math.min(box.TextBounds.X, 90)
            end
            width = math.clamp(measured + textInset + 12, 90, maxWidth) + (focused and 8 or 0)
            width = math.min(width, maxWidth + 8)
        end
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            boxHolder.Size = UDim2.fromOffset(width, boxHeight)
        else
            tween(boxHolder, { Size = UDim2.fromOffset(width, boxHeight) }, 0.18)
        end
    end
    local lastWidth = 0
    frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if frame.AbsoluteSize.X ~= lastWidth then
            lastWidth = frame.AbsoluteSize.X
            fitBox(true)
        end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        fitBox(false)
    end)
    box:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitBox(false)
    end)
    task.defer(fitBox, true)

    box.Focused:Connect(function()
        focused = true
        tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
        fitBox(false)
    end)
    box.FocusLost:Connect(function(enterPressed)
        focused = false
        tween(boxStroke, { Color = Theme.Stroke }, 0.15)
        fitBox(false)
        if opts.Numeric then
            local number = Library._parseAmount(box.Text)
            if not number then
                box.Text = lastText
                return
            end
            lastText, value = box.Text, number
            safeCall(opts.Callback, number, enterPressed)
            return
        end
        safeCall(opts.Callback, box.Text, enterPressed)
    end)

    return finishElement(self, opts, {
        Set = function(_, newValue, silent)
            local before = box.Text
            box.Text = tostring(newValue == nil and "" or newValue)
            if opts.Numeric then
                local number = Library._parseAmount(box.Text)
                if number then
                    lastText, value = box.Text, number
                else
                    box.Text = lastText
                    return
                end
            end
            flashStroke(frameStroke)
            -- Configs load through here, so the script hears the loaded text.
            if not silent and box.Text ~= before then
                safeCall(opts.Callback, opts.Numeric and value or box.Text, false)
            end
        end,
        Get = function()
            if opts.Numeric then
                return value
            end
            return box.Text
        end,
        _saveValue = opts.Numeric and function()
            return lastText
        end or nil,
    }, frame, "Input")
end

function Tab:Keybind(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentKeybind = "Default", Value = "Default" }, "Frame", 110, "Keybind")
    if type(opts.Default) == "string" then
        opts.Default = Enum.KeyCode[opts.Default]
    end
    local compact = metricsOf(self).Compact
    local chipHeight = metricsOf(self).Chip

    local chip = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(44, chipHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    local chipLabel = label({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })

    local self_ = { Value = opts.Default, Listening = false }

    local function fitChip(instant)
        local width = math.max(chipLabel.TextBounds.X + 20, TOUCH and 44 or 36)
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            chip.Size = UDim2.fromOffset(width, chipHeight)
        else
            tween(chip, { Size = UDim2.fromOffset(width, chipHeight) }, 0.2)
        end
    end
    chipLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitChip(false)
    end)

    local function render()
        chipLabel.Text = self_.Listening and "..." or keyName(self_.Value)
        tween(chipStroke, { Color = self_.Listening and Theme.StrokeHover or Theme.Stroke }, 0.15)
        tween(chipLabel, { TextColor3 = self_.Listening and Theme.Accent or Theme.Muted }, 0.15)
    end

    function self_:Set(keyCode, silent)
        local wasListening = self_.Listening
        self_.Value = keyCode
        self_.Listening = false
        render()
        if not wasListening then
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.OnChanged, keyCode)
        end
    end

    chip.MouseButton1Click:Connect(function()
        self_.Listening = not self_.Listening
        render()
    end)

    self.Window:_listen("Began", function(input, gameProcessed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        if self_.Listening then
            self.Window._consumedKey = input.KeyCode
            self.Window._consumedAt = os.clock()
            if input.KeyCode == Enum.KeyCode.Escape then
                self_.Listening = false
                render()
            else
                self_:Set(input.KeyCode)
            end
            return
        end
        if not gameProcessed and self_.Value ~= nil and input.KeyCode == self_.Value then
            safeCall(opts.Callback, input.KeyCode)
        end
    end, self_)

    render()
    task.defer(fitChip, true)
    function self_:Get()
        return self_.Value
    end
    self_._onHide = function()
        if self_.Listening then
            self_.Listening = false
            render()
        end
    end
    return finishElement(self, opts, self_, frame, "Keybind")
end

function Tab:ColorPicker(opts)
    local PANEL_HEIGHT = 194
    local frame, frameStroke, height
    opts, frame, frameStroke, height = beginElement(self, opts, { Title = "Name", Description = "Desc", Color = "Default", CurrentValue = "Default", Value = "Default" }, "Frame")
    frame.ClipsDescendants = true
    local metrics = metricsOf(self)
    local compact = metrics.Compact

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    titleDesc(header, opts.Name or "Color", opts.Desc, 140, metrics)

    -- Closed, the row shows the hex code beside a rounded swatch.
    local swatch = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -38 or -34, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(swatch, UDim.new(0, 6))
    stroke(swatch, Theme.Stroke)
    local swatchHex = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -68 or -64, 0.5, 0),
        Size = UDim2.fromOffset(64, 16),
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })
    local arrow = arrowIndicator(header, 1, compact and -14 or -12)

    local panel = create("Frame", {
        Position = UDim2.fromOffset(14, height + 2),
        Size = UDim2.new(1, -28, 0, PANEL_HEIGHT - 12),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = frame,
    })

    -- Saturation runs left to right, brightness top to bottom.
    local svBox = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 118),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(svBox, UDim.new(0, 8))
    stroke(svBox, Theme.Stroke)
    local svHueGradient = create("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 0, 0)),
        Parent = svBox,
    })
    local svDark = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        Parent = svBox,
    })
    corner(svDark, UDim.new(0, 8))
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90,
        Parent = svDark,
    })

    -- Both handles are a white ring filled with the colour under them, with a
    -- faint dark edge so they read on light and dark spots alike.
    local function knob(parent, size)
        local ring = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = parent,
        })
        corner(ring, UDim.new(1, 0))
        stroke(ring, Color3.new(0, 0, 0), 0.7)
        local fill = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -4, 1, -4),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = ring,
        })
        corner(fill, UDim.new(1, 0))
        return ring, fill
    end
    local svCursor, svFill = knob(svBox, 14)

    -- Hue is a slim horizontal track under the square.
    local hueBar = create("TextButton", {
        Position = UDim2.fromOffset(0, 132),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(hueBar, UDim.new(1, 0))
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = hueBar,
    })
    local hueCursor, hueFill = knob(hueBar, 16)
    hueCursor.Position = UDim2.fromScale(0, 0.5)

    -- Bottom row: a preview chip and hex field on the left, RGB on the right.
    local hexHolder = create("Frame", {
        Position = UDim2.fromOffset(0, 154),
        Size = UDim2.fromOffset(compact and 110 or 124, 28),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = panel,
    })
    corner(hexHolder, UDim.new(0, 7))
    local hexStroke = stroke(hexHolder)
    local preview = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 6, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BorderSizePixel = 0,
        Parent = hexHolder,
    })
    corner(preview, UDim.new(0, 4))
    stroke(preview, Theme.Stroke)
    local hexBox = create("TextBox", {
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -38, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = false,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = hexHolder,
    })
    local rgbLabel = label({
        Position = UDim2.fromOffset(compact and 118 or 134, 154),
        Size = UDim2.new(1, compact and -118 or -134, 0, 28),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = panel,
    })

    local self_ = { Open = false }
    local hue, sat, val = Color3.toHSV(opts.Default or Theme.Accent)
    local dragTarget = nil

    local function toHex(color)
        return string.format("#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function render(duration)
        local color = Color3.fromHSV(hue, sat, val)
        self_.Value = color
        swatch.BackgroundColor3 = color
        preview.BackgroundColor3 = color
        svFill.BackgroundColor3 = color
        hueFill.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        swatchHex.Text = toHex(color)
        svHueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
        tween(svCursor, { Position = UDim2.fromScale(sat, 1 - val) }, duration, Enum.EasingStyle.Quint)
        tween(hueCursor, { Position = UDim2.fromScale(hue, 0.5) }, duration, Enum.EasingStyle.Quint)
        if not hexBox:IsFocused() then
            hexBox.Text = toHex(color)
        end
        rgbLabel.Text = string.format("%d  %d  %d",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function commit(duration, silent)
        render(duration)
        if not silent then
            safeCall(opts.Callback, self_.Value)
        end
    end

    function self_:Set(color, silent)
        hue, sat, val = Color3.toHSV(color)
        commit(0.25, silent)
        flashStroke(frameStroke)
    end

    function self_:Get()
        return self_.Value
    end

    local function setOpen(open)
        self_.Open = open
        tween(frame, { Size = UDim2.new(1, 0, 0, open and (height + PANEL_HEIGHT) or height) }, 0.35, Enum.EasingStyle.Quint)
        arrow:Set(open)
        if open then
            panel.Visible = true
        else
            task.delay(0.35, function()
                if not self_.Open then
                    panel.Visible = false
                end
            end)
        end
    end

    function self_:SetOpen(open)
        setOpen(open == true)
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not self_.Open)
    end)

    local function updateSV(position)
        sat = math.clamp((position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
        val = 1 - math.clamp((position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
        commit(0.04)
    end
    local function updateHue(position)
        hue = math.clamp((position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
        commit(0.04)
    end

    svBox.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "sv"
            tween(svCursor, { Size = UDim2.fromOffset(18, 18) }, 0.2, Enum.EasingStyle.Quint)
            updateSV(pointerPosition())
        end
    end)
    hueBar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "hue"
            tween(hueCursor, { Size = UDim2.fromOffset(20, 20) }, 0.2, Enum.EasingStyle.Quint)
            updateHue(pointerPosition())
        end
    end)
    self.Window:_listen("Changed", function(input)
        if not dragTarget or not isMove(input) then
            return
        end
        local position = pointerPosition()
        if dragTarget == "sv" then
            updateSV(position)
        else
            updateHue(position)
        end
    end, self_)
    self.Window:_listen("Ended", function(input)
        if dragTarget and isPress(input) then
            dragTarget = nil
            tween(svCursor, { Size = UDim2.fromOffset(14, 14) }, 0.25, Enum.EasingStyle.Quint)
            tween(hueCursor, { Size = UDim2.fromOffset(16, 16) }, 0.25, Enum.EasingStyle.Quint)
        end
    end, self_)

    hexBox.Focused:Connect(function()
        tween(hexStroke, { Color = Theme.StrokeHover }, 0.15)
    end)
    hexBox.FocusLost:Connect(function()
        tween(hexStroke, { Color = Theme.Stroke }, 0.15)
        local r, g, b = hexBox.Text:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            self_:Set(Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)))
        else
            hexBox.Text = toHex(self_.Value)
        end
    end)

    render(0)
    return finishElement(self, opts, self_, frame, "ColorPicker")
end

function Tab:Stepper(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" }, "Frame", 150, "Stepper")
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local numbers = numberFormat(min, max, step)
    local compact = metricsOf(self).Compact
    local chipHeight = metricsOf(self).Chip

    local group = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(0, chipHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(group, UDim.new(0, 6))
    local groupStroke = stroke(group)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = group,
    })

    local function stepButton(text, order)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(chipHeight, chipHeight),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Theme.Muted,
            TextSize = 18,
            FontFace = Fonts.Medium,
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = group,
        })
        button.MouseEnter:Connect(function()
            tween(button, { TextColor3 = Theme.Accent }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { TextColor3 = Theme.Muted }, 0.2)
        end)
        return button
    end
    local minus = stepButton("−", 1)
    local valueLabel = label({
        Size = UDim2.new(0, 30, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = group,
    })
    local plus = stepButton("+", 3)
    local function fitValue(instant)
        local width = math.max(valueLabel.TextBounds.X + 12, 30)
        if instant then
            valueLabel.Size = UDim2.new(0, width, 1, 0)
        else
            tween(valueLabel, { Size = UDim2.new(0, width, 1, 0) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitValue(false)
    end)
    group:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        reserveRight(titleLabel, descLabel, group.AbsoluteSize.X / self.Window.Scale.Scale + (compact and 24 or 20))
    end)

    local self_ = { Value = math.clamp(opts.Default or min, min, max) }
    local snap = numbers.snap
    local fromButton = false
    local function render()
        valueLabel.Text = numbers.format(self_.Value) .. suffix
        tween(minus, { TextTransparency = self_.Value <= min and 0.6 or 0 }, 0.15)
        tween(plus, { TextTransparency = self_.Value >= max and 0.6 or 0 }, 0.15)
    end
    function self_:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == self_.Value then
            return
        end
        self_.Value = value
        render()
        if not fromButton then
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end
    function self_:Get()
        return self_.Value
    end

    local function bump(direction)
        fromButton = true
        self_:Set(self_.Value + direction * step)
        fromButton = false
        tween(groupStroke, { Color = Theme.StrokeHover }, 0.08)
        task.delay(0.12, function()
            tween(groupStroke, { Color = Theme.Stroke }, 0.2)
        end)
    end
    local function holdRepeat(button, direction)
        local holding = false
        button.InputBegan:Connect(function(input)
            if not isPress(input) then
                return
            end
            holding = true
            bump(direction)
            task.delay(0.4, function()
                while holding do
                    bump(direction)
                    task.wait(0.07)
                end
            end)
        end)
        button.InputEnded:Connect(function(input)
            if isPress(input) then
                holding = false
            end
        end)
        button.MouseLeave:Connect(function()
            holding = false
        end)
    end
    holdRepeat(minus, -1)
    holdRepeat(plus, 1)

    render()
    task.defer(fitValue, true)
    return finishElement(self, opts, self_, frame, "Stepper")
end

function Tab:Progress(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local extra = compact and 6 or 10
    local frame, frameStroke = card(self, "Frame", (opts.Desc and metrics.DescHeight or metrics.Height) + extra, opts)
    hoverStroke(frame, frameStroke)
    local top
    if opts.Desc then
        top = math.floor((metrics.DescHeight - (metrics.DescGap + metrics.DescLine)) / 2) - 2
    else
        top = compact and 5 or 12
    end

    label({
        Position = UDim2.fromOffset(14, top),
        Size = UDim2.new(1, -110, 0, 18),
        Text = opts.Name or "Progress",
        TextSize = metrics.TextSize,
        Parent = frame,
    })
    if opts.Desc then
        label({
            Position = UDim2.fromOffset(14, top + metrics.DescGap),
            Size = UDim2.new(1, -110, 0, metrics.DescLine),
            Text = opts.Desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = frame,
        })
    end
    local valueLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, top),
        Size = UDim2.fromOffset(90, 18),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 13,
        TextColor3 = Library._color(opts.TextColor) or Theme.Accent,
        RichText = true,
        Parent = frame,
    })
    local track = create("Frame", {
        Position = UDim2.new(0, 14, 1, compact and -12 or -16),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Library._color(opts.Color) or Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))

    local self_ = { Value = math.clamp(opts.Default or 0, 0, 1) }
    local formatter = opts.Format
    local function render(duration)
        local frac = self_.Value
        tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, duration, Enum.EasingStyle.Quint)
        if type(formatter) == "function" then
            valueLabel.Text = Library._rich(formatter(frac))
        else
            valueLabel.Text = string.format("%d%%", math.floor(frac * 100 + 0.5))
        end
    end
    function self_:Set(value, silent)
        value = math.clamp(tonumber(value) or 0, 0, 1)
        if value == self_.Value then
            return
        end
        self_.Value = value
        render(0.35)
        if not silent then
            safeCall(opts.Callback, value)
        end
    end
    function self_:Get()
        return self_.Value
    end
    function self_:SetColor(color)
        tween(fill, { BackgroundColor3 = Library._color(color) or Theme.Accent }, 0.25)
    end
    -- The percentage's colour; nil goes back to the accent.
    function self_:SetTextColor(color)
        tween(valueLabel, { TextColor3 = Library._color(color) or Theme.Accent }, 0.25)
    end
    -- Runs render now, and again on a theme change for theme tags in Format.
    onTheme(valueLabel, function()
        render(0)
    end)
    return finishElement(self, opts, self_, frame, "Progress")
end

-- An always-open list the player puts in order: drag a row (by its grip on
-- touch, anywhere on PC) or nudge it with the arrows. Past MaxRows the list
-- scrolls, and dragging near its top or bottom edge scrolls it along.
function Tab:OrderList(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Options = "Items", Values = "Items" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local window = self.Window
    local ROW = TOUCH and 40 or 32
    local GAP = 4
    local STEP = ROW + GAP
    local GRIP = TOUCH and 34 or 26
    local ARROW = TOUCH and 30 or 22
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 6), 1)
    local numbered = opts.Numbered ~= false
    local arrows = opts.Arrows ~= false

    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = frame,
    })
    local name = tostring(opts.Name or "")
    label({
        Size = UDim2.new(1, 0, 0, 18),
        Text = name,
        TextSize = metrics.TextSize,
        Visible = name ~= "",
        LayoutOrder = 1,
        Parent = frame,
    })
    if opts.Desc then
        label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = frame,
        })
    end
    local scroller = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, ROW + 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand, like the dropdown list, so it scrolls under UIScale.
        CanvasSize = UDim2.new(),
        ScrollingEnabled = false,
        LayoutOrder = 3,
        Parent = frame,
    })
    scroller:SetAttribute("NoDrag", true)
    local content = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local empty = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = tostring(opts.EmptyText or "Nothing to order"),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Visible = false,
        Parent = content,
    })

    -- A lucide icon, or a text glyph when the icon set didn't load.
    local function iconButton(parent, icon, glyph, rotation, props)
        props.BackgroundTransparency = 1
        props.Text = ""
        props.AutoButtonColor = false
        props.Parent = parent
        local button = create("TextButton", props)
        local image = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = TOUCH and UDim2.fromOffset(16, 16) or UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(image, icon)
        if image.Image ~= "" then
            return button, { Object = image, Color = "ImageColor3", Fade = "ImageTransparency" }
        end
        image:Destroy()
        local text_ = label({
            Size = UDim2.fromScale(1, 1),
            Text = glyph,
            TextSize = 18,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            Rotation = rotation,
            Parent = button,
        })
        return button, { Object = text_, Color = "TextColor3", Fade = "TextTransparency" }
    end
    local function tint(icon, color, transparency, duration)
        tween(icon.Object, { [icon.Color] = color, [icon.Fade] = transparency }, duration)
    end

    local self_ = {}
    local entries = {}
    -- The last order Set asked for, including items not in the list right now,
    -- so a saved order still applies once Refresh brings those items in.
    local remembered = {}
    local dragging = nil
    local nudge, beginDrag

    local function slotY(slot)
        return 1 + (slot - 1) * STEP
    end

    local function values()
        local list = {}
        for index, entry in ipairs(entries) do
            list[index] = entry.Value
        end
        return list
    end

    local function layout(instant)
        local count = #entries
        for slot, entry in ipairs(entries) do
            entry.Index.Text = tostring(slot)
            if entry ~= dragging then
                tween(entry.Frame, { Position = UDim2.fromOffset(3, slotY(slot)) }, instant and 0 or 0.22, Enum.EasingStyle.Quint)
            end
            if entry.UpIcon then
                tween(entry.UpIcon.Object, { [entry.UpIcon.Fade] = slot == 1 and 0.7 or 0 }, instant and 0 or 0.15)
                tween(entry.DownIcon.Object, { [entry.DownIcon.Fade] = slot == count and 0.7 or 0 }, instant and 0 or 0.15)
            end
        end
    end

    local function fit()
        local count = #entries
        local canvas = math.max(count, 1) * STEP - GAP + 2
        local shown = math.clamp(count, 1, maxRows)
        local height = shown * STEP - GAP + 2
        local scrolling = count > maxRows
        scroller.Size = UDim2.new(1, 0, 0, height)
        scroller.CanvasSize = UDim2.fromOffset(0, canvas)
        content.Size = UDim2.new(1, scrolling and -8 or 0, 0, canvas)
        if not dragging then
            scroller.ScrollingEnabled = scrolling
        end
        empty.Visible = count == 0
        local maxScroll = math.max(canvas - height, 0)
        if scroller.CanvasPosition.Y > maxScroll then
            scroller.CanvasPosition = Vector2.new(0, maxScroll)
        end
    end

    local function changed(silent)
        self_.Value = values()
        if not silent then
            safeCall(opts.Callback, values())
        end
    end

    local function listScroller()
        if scroller.ScrollingEnabled then
            return scroller
        end
        return frame:FindFirstAncestorWhichIsA("ScrollingFrame")
    end

    local function newEntry(value)
        local row = create("Frame", {
            Size = UDim2.new(1, -6, 0, ROW),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = content,
        })
        corner(row, UDim.new(0, 7))
        local entry = { Value = value, Frame = row }
        entry.Stroke = stroke(row)
        entry.Scale = create("UIScale", { Parent = row })
        local grip
        grip, entry.GripIcon = iconButton(row, "grip-vertical", "=", 0, {
            Size = UDim2.new(0, GRIP, 1, 0),
        })
        local x = GRIP
        entry.Index = label({
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(0, 22, 1, 0),
            TextSize = 12,
            TextColor3 = Theme.Accent,
            TextTruncate = Enum.TextTruncate.None,
            Visible = numbered,
            Parent = row,
        })
        if numbered then
            x += 22
        end
        local right = arrows and ARROW * 2 + 8 or 10
        entry.Text = label({
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(1, -(x + right), 1, 0),
            Text = tostring(value),
            TextSize = 13,
            Parent = row,
        })
        local buttons = {}
        if arrows then
            local up, down
            up, entry.UpIcon = iconButton(row, "chevron-up", "›", -90, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -(ARROW + 6), 0, 0),
                Size = UDim2.new(0, ARROW, 1, 0),
            })
            down, entry.DownIcon = iconButton(row, "chevron-down", "›", 90, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -4, 0, 0),
                Size = UDim2.new(0, ARROW, 1, 0),
            })
            for button, direction in pairs({ [up] = -1, [down] = 1 }) do
                local icon = direction < 0 and entry.UpIcon or entry.DownIcon
                local isTap = tapGuard(button, listScroller)
                button.MouseEnter:Connect(function()
                    if not usingTouch() then
                        tween(icon.Object, { [icon.Color] = Theme.Accent }, 0.12)
                    end
                end)
                button.MouseLeave:Connect(function()
                    tween(icon.Object, { [icon.Color] = Theme.Muted }, 0.2)
                end)
                button.MouseButton1Click:Connect(function()
                    if isTap() then
                        nudge(entry, direction)
                    end
                end)
                table.insert(buttons, button)
            end
        end
        grip.InputBegan:Connect(function(input)
            if isPress(input) then
                beginDrag(entry)
            end
        end)
        -- On PC the whole row drags; on touch only the grip does, so a swipe
        -- across the rows still scrolls.
        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local point = pointerPosition()
            for _, button in ipairs(buttons) do
                if pointInside(point, button) then
                    return
                end
            end
            beginDrag(entry)
        end)
        row.MouseEnter:Connect(function()
            if not usingTouch() and entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.StrokeHover }, 0.12)
                tint(entry.GripIcon, Theme.Text, 0, 0.12)
            end
        end)
        row.MouseLeave:Connect(function()
            if entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.Stroke }, 0.25)
                tint(entry.GripIcon, Theme.Muted, 0, 0.25)
            end
        end)
        return entry
    end

    -- Reuses the rows whose item is still in the list, so a reorder slides
    -- rows instead of rebuilding them.
    local function build(list)
        local pool = {}
        for _, entry in ipairs(entries) do
            pool[entry.Value] = pool[entry.Value] or {}
            table.insert(pool[entry.Value], entry)
        end
        local nextEntries = {}
        for index, value in ipairs(list) do
            local bucket = pool[value]
            local entry = bucket and table.remove(bucket, 1)
            if not entry then
                entry = newEntry(value)
                entry.Frame.Position = UDim2.fromOffset(3, slotY(index))
            end
            nextEntries[index] = entry
        end
        for _, bucket in pairs(pool) do
            for _, entry in ipairs(bucket) do
                entry.Frame:Destroy()
            end
        end
        entries = nextEntries
    end

    -- items sorted by where they sit in ranking; the rest keep their order after.
    local function arrange(items, ranking)
        local left = {}
        for _, value in ipairs(items) do
            left[value] = (left[value] or 0) + 1
        end
        local result = {}
        for _, pass in ipairs({ ranking, items }) do
            for _, value in ipairs(pass) do
                if (left[value] or 0) > 0 then
                    left[value] -= 1
                    table.insert(result, value)
                end
            end
        end
        return result
    end

    local function scrollIntoView(slot)
        local top = slotY(slot) - 1
        local view = scroller.AbsoluteWindowSize.Y / window.Scale.Scale
        local y = scroller.CanvasPosition.Y
        if top < y then
            y = top
        elseif top + ROW + 2 > y + view then
            y = top + ROW + 2 - view
        end
        if y ~= scroller.CanvasPosition.Y then
            tween(scroller, { CanvasPosition = Vector2.new(0, math.max(y, 0)) }, 0.2)
        end
    end

    function nudge(entry, direction)
        if dragging then
            return
        end
        local from = table.find(entries, entry)
        local to = from and from + direction
        if not to or to < 1 or to > #entries then
            return
        end
        entries[from], entries[to] = entries[to], entries[from]
        layout(false)
        tween(entry.Stroke, { Color = Theme.Accent }, 0.08)
        task.delay(0.18, function()
            if entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.Stroke }, 0.3)
            end
        end)
        scrollIntoView(to)
        changed(false)
    end

    local grabOffset, lastPointer = 0, nil
    local startEntries, stopRender, lockedPage = nil, nil, nil

    -- Moves the held row under the pointer and slides the others out of its way.
    local function follow(pointer)
        local scale = window.Scale.Scale
        local y = (pointer.Y - grabOffset - scroller.AbsolutePosition.Y) / scale + scroller.CanvasPosition.Y
        y = math.clamp(y, slotY(1), slotY(#entries))
        dragging.Frame.Position = UDim2.fromOffset(3, y)
        local slot = math.clamp(math.floor((y - 1) / STEP + 0.5) + 1, 1, #entries)
        local current = table.find(entries, dragging)
        if current ~= slot then
            table.remove(entries, current)
            table.insert(entries, slot, dragging)
            layout(false)
        end
    end

    -- Holding the row near the list's top or bottom edge scrolls it, faster
    -- the closer the pointer gets.
    local function autoScroll(deltaTime)
        if not dragging or not lastPointer then
            return
        end
        local scale = window.Scale.Scale
        local top = scroller.AbsolutePosition.Y
        local bottom = top + scroller.AbsoluteSize.Y
        local zone = ROW * scale
        local speed = 0
        if lastPointer.Y < top + zone then
            speed = -(top + zone - lastPointer.Y) / zone
        elseif lastPointer.Y > bottom - zone then
            speed = (lastPointer.Y - (bottom - zone)) / zone
        end
        if speed == 0 then
            return
        end
        local maxScroll = math.max(scroller.CanvasSize.Y.Offset - scroller.AbsoluteWindowSize.Y / scale, 0)
        local y = math.clamp(scroller.CanvasPosition.Y + math.clamp(speed, -1.5, 1.5) * 360 * deltaTime, 0, maxScroll)
        if y ~= scroller.CanvasPosition.Y then
            scroller.CanvasPosition = Vector2.new(0, y)
            follow(lastPointer)
        end
    end

    function beginDrag(entry)
        if dragging or #entries < 2 or self_._destroyed then
            return
        end
        dragging = entry
        startEntries = table.clone(entries)
        lastPointer = pointerPosition()
        grabOffset = lastPointer.Y - entry.Frame.AbsolutePosition.Y
        entry.Frame.ZIndex = 5
        tween(entry.Frame, { BackgroundColor3 = Theme.Surface3 }, 0.12)
        tween(entry.Stroke, { Color = Theme.Accent }, 0.12)
        tween(entry.Scale, { Scale = 1.02 }, 0.18, Enum.EasingStyle.Back)
        tint(entry.GripIcon, Theme.Accent, 0, 0.12)
        -- Neither the list nor the page scrolls under the finger while dragging.
        scroller.ScrollingEnabled = false
        local page = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
        if page and page.ScrollingEnabled then
            lockedPage = page
            page.ScrollingEnabled = false
        end
        stopRender = window:_listen("Render", autoScroll)
    end

    local function endDrag(silent)
        local entry = dragging
        if not entry then
            return
        end
        dragging = nil
        lastPointer = nil
        if stopRender then
            stopRender()
            stopRender = nil
        end
        if lockedPage then
            lockedPage.ScrollingEnabled = true
            lockedPage = nil
        end
        tween(entry.Frame, { BackgroundColor3 = Theme.Surface }, 0.2)
        tween(entry.Stroke, { Color = Theme.Stroke }, 0.25)
        tween(entry.Scale, { Scale = 1 }, 0.2)
        tint(entry.GripIcon, Theme.Muted, 0, 0.25)
        task.delay(0.22, function()
            if entry ~= dragging then
                entry.Frame.ZIndex = 1
            end
        end)
        layout(false)
        fit()
        for index, other in ipairs(entries) do
            if startEntries[index] ~= other then
                changed(silent)
                break
            end
        end
    end

    window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            lastPointer = pointerPosition()
            follow(lastPointer)
        end
    end, self_)
    window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            endDrag(false)
        end
    end, self_)
    table.insert(self_._listeners, function()
        endDrag(true)
    end)
    self_._onHide = function()
        endDrag(false)
    end

    -- Reorders the items already in the list. Unknown items are remembered for
    -- a later Refresh; items missing from the list keep their order after.
    function self_:Set(list, silent)
        if type(list) ~= "table" then
            return
        end
        endDrag(true)
        remembered = table.clone(list)
        build(arrange(values(), remembered))
        layout(false)
        fit()
        changed(silent)
    end

    function self_:Get()
        return values()
    end

    -- Replaces the items. Items that were already there keep the player's
    -- order unless keepOrder is false; new ones go to the end.
    function self_:Refresh(items, keepOrder, silent)
        endDrag(true)
        items = type(items) == "table" and table.clone(items) or {}
        if keepOrder ~= false then
            items = arrange(items, self_:_saveValue())
        else
            remembered = {}
        end
        build(items)
        layout(false)
        fit()
        changed(silent)
    end

    -- The shown order, then remembered items that aren't in the list right now.
    function self_:_saveValue()
        local list = values()
        local left = {}
        for _, value in ipairs(list) do
            left[value] = (left[value] or 0) + 1
        end
        for _, value in ipairs(remembered) do
            if (left[value] or 0) > 0 then
                left[value] -= 1
            else
                table.insert(list, value)
            end
        end
        return list
    end

    build(type(opts.Items) == "table" and opts.Items or {})
    layout(true)
    fit()
    self_.Value = values()
    return finishElement(self, opts, self_, frame, "OrderList")
end


for name, method in pairs(table.clone(Tab)) do
    if type(method) == "function" and name:sub(1, 1) ~= "_" and name:sub(1, 6) ~= "Create" then
        Tab["Create" .. name] = method
    end
end

local function detectExecutor()
    local name
    pcall(function()
        if typeof(identifyexecutor) == "function" then
            name = (identifyexecutor())
        elseif typeof(getexecutorname) == "function" then
            name = getexecutorname()
        end
    end)
    if type(name) == "string" and #name > 0 then
        return name
    end
    return RunService:IsStudio() and "Studio" or "Unknown"
end

local function executorReport(opts)
    local executor = detectExecutor()
    local supported = opts.SupportedExecutors
    if type(supported) == "table" then
        local lowered = string.lower(executor)
        for _, name in ipairs(supported) do
            if string.find(lowered, string.lower(tostring(name)), 1, true) then
                return executor, true, "Your executor is supported and fully compatible."
            end
        end
        return executor, false, "Not on the supported list. Some features may not work."
    end
    local capabilities = {
        { "writefile", writefile },
        { "readfile", readfile },
        { "getcustomasset", getcustomasset },
        { "setclipboard", setclipboard or toclipboard },
        { "request", request or http_request or (syn and syn.request) },
    }
    local missing = {}
    for _, entry in ipairs(capabilities) do
        if type(entry[2]) ~= "function" then
            table.insert(missing, entry[1])
        end
    end
    if #missing == 0 then
        return executor, true, "Your executor is supported and fully compatible."
    end
    return executor, false, "Missing " .. table.concat(missing, ", ") .. ". Some features may not work."
end

-- "Don't ask again" on the unsupported executor warning: the executor's
-- name goes in a file in the script folder, and the warning is skipped while
-- the same executor is in use. Resetting the folder brings it back.
-- A table, not separate locals: the main chunk is at Luau's 200 local limit.
local UnsupportedSkip = {}

function UnsupportedSkip.Path(folder)
    return tostring(folder) .. "/unsupported_skip.txt"
end

function UnsupportedSkip.Available()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

function UnsupportedSkip.Saved(folder, executor)
    if not UnsupportedSkip.Available() then
        return false
    end
    local path = UnsupportedSkip.Path(folder)
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or nil
    end)
    return ok and saved == executor
end

function UnsupportedSkip.Write(folder, path, content)
    if not UnsupportedSkip.Available() then
        return false
    end
    return pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local built = ""
            for segment in tostring(folder):gmatch("[^/\\]+") do
                built = built == "" and segment or built .. "/" .. segment
                if not isfolder(built) then
                    makefolder(built)
                end
            end
        end
        writefile(path, content)
    end)
end

function UnsupportedSkip.Save(folder, executor)
    return UnsupportedSkip.Write(folder, UnsupportedSkip.Path(folder), executor)
end

-- Custom disclaimers ticked "Don't show again": one key per line in
-- disclaimers.txt. The key is the disclaimer's Id, or a hash of its title
-- and text, so rewording a disclaimer shows it again.
function UnsupportedSkip.DisclaimerKey(entry)
    if entry.Id ~= nil then
        return (tostring(entry.Id):gsub("[\r\n]", " "))
    end
    local source = tostring(entry.Title) .. "\0" .. tostring(entry.Text)
    local hash = 5381
    for index = 1, #source do
        hash = (hash * 33 + source:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

function UnsupportedSkip.DisclaimerAccepted(folder, key)
    if not UnsupportedSkip.Available() then
        return false
    end
    local path = tostring(folder) .. "/disclaimers.txt"
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or ""
    end)
    if not ok or type(saved) ~= "string" then
        return false
    end
    for line in saved:gmatch("[^\r\n]+") do
        if line == key then
            return true
        end
    end
    return false
end

function UnsupportedSkip.AcceptDisclaimer(folder, key)
    if UnsupportedSkip.DisclaimerAccepted(folder, key) then
        return true
    end
    local path = tostring(folder) .. "/disclaimers.txt"
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or ""
    end)
    saved = ok and type(saved) == "string" and saved or ""
    if saved ~= "" and not saved:match("\n$") then
        saved ..= "\n"
    end
    return UnsupportedSkip.Write(folder, path, saved .. key .. "\n")
end

local gameInfoCache = nil

local function fetchGameInfo()
    if gameInfoCache == nil then
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(game.PlaceId)
        end)
        gameInfoCache = ok and type(info) == "table" and info or false
    end
    return gameInfoCache or nil
end

local function detectGameName()
    local info = fetchGameInfo()
    if info and info.Name then
        return info.Name
    end
    return RunService:IsStudio() and "Studio" or "Unknown game"
end

local REGION_NAMES = {
    US = "United States", GB = "United Kingdom", DE = "Germany", FR = "France",
    NL = "Netherlands", SG = "Singapore", JP = "Japan", AU = "Australia",
    BR = "Brazil", IN = "India", HK = "Hong Kong", CA = "Canada",
}

local function detectRegion(callback)
    task.spawn(function()
        local requester = request or http_request or (syn and syn.request) or (http and http.request)
        local region
        if type(requester) == "function" then
            pcall(function()
                local response = requester({ Url = "https://ipinfo.io/json", Method = "GET" })
                local body = type(response) == "table" and (response.Body or response.body) or nil
                if type(body) == "string" then
                    local data = HttpService:JSONDecode(body)
                    if type(data) == "table" and data.country then
                        local label = REGION_NAMES[data.country] or data.country
                        region = data.city and (data.city .. ", " .. label) or label
                    end
                end
            end)
        end
        callback(region or "Unavailable")
    end)
end

local NOTIFY_COLORS = setmetatable({}, {
    __index = function(_, kind)
        if kind == "Success" or kind == "Warning" or kind == "Error" then
            return Theme[kind]
        end
        return nil
    end,
})

local Window = {}
Window.__index = Window

-- Shared across executions of the script, so a rerun can find the last window.
function Library._registry()
    local ok, env = pcall(function()
        return getgenv and getgenv() or shared
    end)
    env = ok and type(env) == "table" and env or shared
    if type(env) ~= "table" then
        return nil
    end
    if type(env.__AirFlowWindows) ~= "table" then
        env.__AirFlowWindows = {}
    end
    return env.__AirFlowWindows
end

function Library.Window(_, opts)
    opts = normalize(opts, { Name = "Title", LoadingSubtitle = "Subtitle", ToggleUIKeybind = "Keybind" })

    if type(opts.Keybind) == "string" then
        opts.Keybind = Enum.KeyCode[opts.Keybind]
    end
    local size = opts.Size or UDim2.fromOffset(760, 520)
    local keybind = opts.Keybind or Enum.KeyCode.RightControl

    local self = setmetatable({
        Tabs = {},
        CurrentTab = nil,
        Open = true,
        Keybind = keybind,
        _connections = {},
        _controls = {},
        _inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} },
        _frameSteps = {},
        _destroyed = false,
        _identity = { Names = {}, Avatars = {} },
        _pinned = {},
        Minimized = false,
        _hideName = false,
        _hideAvatar = false,
        Title = opts.Title or "Airflow",
        _logoIcon = opts.Icon or Assets.Logo,
        _sessionStart = os.clock(),
        _islandLocked = opts.IslandDraggable == false,
    }, Window)
    local saving = type(opts.ConfigurationSaving) == "table" and opts.ConfigurationSaving or {}
    self.ConfigFolder = saving.FolderName or "AirflowUI"
    -- Re-executing the script unloads the copy it left behind first, so the
    -- old toggles stop before the new autoload starts them again.
    self._registryKey = "AirFlow:" .. tostring(self.ConfigFolder) .. ":" .. tostring(opts.Title or "Airflow")
    local registry = Library._registry()
    if registry then
        local previous = registry[self._registryKey]
        if type(previous) == "table" and type(previous.Destroy) == "function" then
            pcall(previous.Destroy, previous)
        end
        registry[self._registryKey] = self
    end
    self.ConfigName = saving.FileName
    self._configListeners = {}
    self._pendingFlags = {}

    local startTheme = opts.DefaultTheme or opts.Theme
    if startTheme ~= nil then
        Library.DefaultTheme = startTheme
    end
    self:_applyDefaultTheme()
    self._uiScale = math.clamp(tonumber(opts.UIScale) or 1, 0.6, 1.5)
    self._adaptive = opts.AdaptiveSize ~= false
    self.UIScale = self._uiScale
    if opts.Density ~= nil then
        Library:SetDensity(opts.Density)
    end
    if opts.CornerRadius ~= nil then
        Library:SetCornerRadius(opts.CornerRadius, true)
    end
    local function dispatch(kind)
        return function(...)
            for _, handler in ipairs(self._inputListeners[kind]) do
                handler(...)
            end
        end
    end
    local renderDispatch = dispatch("Render")
    table.insert(self._connections, RunService.RenderStepped:Connect(function(deltaTime)
        renderDispatch(deltaTime)
        for _, step in ipairs(self._frameSteps) do
            step(deltaTime)
        end
    end))
    table.insert(self._connections, UserInputService.InputBegan:Connect(dispatch("Began")))
    table.insert(self._connections, UserInputService.InputChanged:Connect(dispatch("Changed")))
    table.insert(self._connections, UserInputService.InputEnded:Connect(dispatch("Ended")))

    local gui = create("ScreenGui", {
        Name = opts.Name or "AirflowUI",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    self.Gui = gui

    local root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = size,
        BackgroundTransparency = 1,
        Parent = gui,
    })
    self.Root = root
    local scale = create("UIScale", { Parent = root })
    self.Scale = scale

    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.6,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = root,
    })
    self.Shadow = shadow
    self._shadowRest = 0.6

    -- The body is a plain Frame so resizing never re-renders the window into a
    -- texture. It only moves into the fader CanvasGroup while fading.
    local fader = create("CanvasGroup", {
        Name = "Fader",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        ZIndex = 2,
        Parent = root,
    })
    self._fader = fader
    self._bodyAlpha = 1
    local body = create("Frame", {
        Name = "Body",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = fader,
    })
    self.Body = body
    corner(body, UDim.new(0, 10))
    self.BodyStroke = stroke(body, Theme.Stroke)
    edgeHighlight(body)
    -- Background image: made first so everything else in the body draws over it.
    self._backgroundImage = create("ImageLabel", {
        Name = "BackgroundImage",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        ImageTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = body,
    })
    corner(self._backgroundImage, UDim.new(0, 10))
    self.BackgroundTransparency = math.clamp(tonumber(opts.BackgroundTransparency) or 0.35, 0, 1)
    self._backgroundGeneration = 0

    -- The sidebar is a flush, solid rail down the left edge, split from the
    -- content by a single hairline.
    local sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = body,
    })
    self.Sidebar = sidebar
    -- One rounded fill that runs past the rail's right edge, where the rail
    -- clips it: the left corners round with the window, the right edge is
    -- square, and nothing overlaps, so it fades evenly when see-through.
    local sidebarFill = create("Frame", {
        Name = "Fill",
        Size = UDim2.new(1, 24, 1, 0),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = sidebar,
    })
    corner(sidebarFill, UDim.new(0, 10))
    self.SidebarFill = sidebarFill
    create("Frame", {
        Name = "Divider",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = sidebar,
    })

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
        Parent = sidebar,
    })
    local logo = create("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 14, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
        BackgroundTransparency = 1,
        Image = "",
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = header,
    })
    applyIcon(logo, opts.Icon or Assets.Logo, true)
    local subtitle = opts.Version or opts.Subtitle
    label({
        Position = UDim2.new(0, 56, 0.5, subtitle and -15 or -9),
        Size = UDim2.new(1, -68, 0, 18),
        Text = self.Title,
        TextSize = 14,
        FontFace = Fonts.Bold,
        Parent = header,
    })
    if subtitle then
        label({
            Position = UDim2.new(0, 56, 0.5, 3),
            Size = UDim2.new(1, -68, 0, 14),
            Text = tostring(subtitle),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
    end

    local profileEnabled = opts.Profile ~= false
    local tabList = create("ScrollingFrame", {
        Name = "Tabs",
        Position = UDim2.fromOffset(0, HEADER_HEIGHT),
        Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + (profileEnabled and PROFILE_HEIGHT + 4 or 12))),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = sidebar,
    })
    self.TabList = tabList
    -- The highlight sits beside the stack of buttons, so it scrolls and clips
    -- with them and glides between tiles.
    local indicator = create("Frame", {
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -16, 0, TAB_TILE_HEIGHT),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        Parent = tabList,
    })
    corner(indicator, UDim.new(0, 7))
    -- The active tab is just a quiet neutral fill with white text; the bar
    -- is kept for callers but stays hidden.
    local pill = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(2, 14),
        BackgroundColor3 = Theme.Accent,
        Visible = false,
        BorderSizePixel = 0,
        Parent = indicator,
    })
    corner(pill, UDim.new(1, 0))
    self._indicatorPill = pill
    self.Indicator = indicator
    local stack = create("Frame", {
        Name = "Stack",
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = tabList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = stack,
    })
    self._tabStack = stack

    -- More tabs than fit: a fade and a small "more" chip at the hidden end.
    self:_overflowHint(sidebar, tabList, stack, true, Theme.Surface)

    if profileEnabled then
        self:_buildProfile(sidebar)
    end

    local content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(SIDEBAR_WIDTH + 1, 0),
        Size = UDim2.new(1, -(SIDEBAR_WIDTH + 1), 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = body,
    })
    self.Content = content
    self:_sidebarResize(sidebar, tonumber(opts.SidebarWidth) or SIDEBAR_WIDTH)
    self._outLayer = create("CanvasGroup", {
        Name = "TransitionOut",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 2,
        Parent = content,
    })
    self._inLayer = create("CanvasGroup", {
        Name = "TransitionIn",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 3,
        Parent = content,
    })

    local minimizeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = content,
    })
    minimizeButton:SetAttribute("NoDrag", true)
    -- A bare "minimize" arrows glyph, no box: muted at rest, full text
    -- colour and a touch smaller on hover, as if pulling in.
    local minimizeGlyph = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = minimizeButton,
    })
    applyIcon(minimizeGlyph, "minimize-2")
    minimizeButton.MouseEnter:Connect(function()
        tween(minimizeGlyph, { ImageColor3 = Theme.Text, Size = UDim2.fromOffset(18, 18) }, 0.2, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseLeave:Connect(function()
        tween(minimizeGlyph, { ImageColor3 = Theme.Muted, Size = UDim2.fromOffset(20, 20) }, 0.25, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseButton1Click:Connect(function()
        self:Minimize()
    end)
    self.MinimizeButton = minimizeButton

    if opts.Search ~= false then
        self:_buildSearch(content)
    end

    local notifyHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -20),
        Size = UDim2.new(0, 280, 1, -40),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local function fitToasts()
        notifyHolder.Size = UDim2.new(0, math.min(280, gui.AbsoluteSize.X - 40), 1, -40)
    end
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToasts))
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 4),
        Parent = notifyHolder,
    })
    self.NotifyHolder = notifyHolder
    self._notifyOrder = 0
    self._toasts = {}
    self.MaxNotifications = opts.MaxNotifications or 4

    self._controlsDirty = true
    table.insert(self._connections, body.DescendantAdded:Connect(function()
        self._controlsDirty = true
    end))
    table.insert(self._connections, body.DescendantRemoving:Connect(function()
        self._controlsDirty = true
    end))

    self:SetDragStyle(opts.DragStyle or (opts.DragSkeleton == false and "Off" or "Outline"))
    self:SetIslandStyle(opts.IslandStyle)
    if opts.Transparent then
        self:SetTransparent(true)
    end
    if opts.Background then
        task.spawn(self.SetBackground, self, opts.Background)
    end
    self:_enableDrag()
    self.MaxSize = opts.MaxSize
    self.KeepOnScreen = opts.KeepOnScreen ~= false
    self:_enableResize(opts.MinSize or Vector2.new(480, 360))
    -- The window's exact size rides along in configs as a hidden flag.
    if opts.SaveSize ~= false then
        local window = self
        local sizeFlag = { _type = "WindowSize", _listeners = {} }
        function sizeFlag:Get()
            local current = window:GetSize()
            return { Width = current.X, Height = current.Y }
        end
        function sizeFlag:Set(value)
            if type(value) == "table" and tonumber(value.Width) and tonumber(value.Height) then
                window:SetSize(Vector2.new(tonumber(value.Width), tonumber(value.Height)))
            end
        end
        local flag = type(opts.SaveSize) == "string" and opts.SaveSize or "__WindowSize"
        Library.Flags[flag] = sizeFlag
        self:_flagCreated(flag, sizeFlag)
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == self.Keybind then
            task.defer(function()
                local consumed = self._consumedKey == input.KeyCode and os.clock() - (self._consumedAt or 0) < 0.2
                self._consumedKey = nil
                if not consumed and not self._destroyed then
                    if self.Minimized then
                        self:Restore()
                    else
                        self:Toggle(not self.Open)
                    end
                end
            end)
        end
    end))

    pcall(function()
        if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            syn.protect_gui(gui)
        end
    end)
    gui.Parent = opts.Parent or defaultParent()

    scale.Scale = 0.9
    shadow.ImageTransparency = 1
    self.BodyStroke.Transparency = 1
    root.Visible = false
    self:_fitToScreen(true)
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:_fitToScreen()
        self:_clampToScreen()
    end))
    local toggleOpts = opts.ToggleButton
    if toggleOpts == nil or toggleOpts == true then
        toggleOpts = {}
    end
    if type(toggleOpts) == "table" then
        self:_createToggleButton(toggleOpts)
    end
    -- The toggle button already brings a hidden window back.
    local toggleShown = self.ToggleButton ~= nil and self:_toggleButtonAllowed()
    if (opts.OpenButton ~= nil and opts.OpenButton ~= false) or (opts.OpenButton == nil and TOUCH and not toggleShown) then
        self:_createOpenButton(type(opts.OpenButton) == "table" and opts.OpenButton or {})
    end
    if opts.Backdrop ~= false then
        self:_buildBackdrop(type(opts.Backdrop) == "table" and opts.Backdrop or {})
    end
    self._introDone = false

    table.insert(Library.Windows, self)

    if opts.Home ~= false then
        self:_buildHome(type(opts.Home) == "table" and opts.Home or {})
    end

    local loading = opts.Loading
    if type(loading) == "table" then
        opts.LoadingDuration = loading.Duration or opts.LoadingDuration
        opts.LoadingText = loading.Text or loading.Subtitle or opts.LoadingText
        opts.LoadingSteps = loading.Steps or opts.LoadingSteps
        opts.LoadingTitle = loading.Title or opts.LoadingTitle
        loading = loading.Enabled ~= false
    end
    -- An executor off the supported list (or missing the file / asset API)
    -- stops at a warning card before the window opens.
    local prompts = {}
    local gate = opts.UnsupportedExecutor
    if gate ~= false then
        gate = type(gate) == "table" and gate or {}
        local list = opts.SupportedExecutors or (type(opts.Home) == "table" and opts.Home.SupportedExecutors or nil)
        local executor, supported, message = executorReport({ SupportedExecutors = list })
        if not supported and not UnsupportedSkip.Saved(self.ConfigFolder, executor) then
            local block = gate.Block == true
            local folder = self.ConfigFolder
            table.insert(prompts, {
                Title = gate.Title or "Unsupported executor",
                Subtitle = executor,
                Text = block and ((gate.Text or message) .. " This script can't run here.") or (gate.Text or message),
                Icon = "shield-alert",
                Color = Theme.Warning,
                ContinueText = "Continue anyway",
                ExitText = "Exit",
                Block = block,
                RememberText = "Don't ask again on this executor",
                Remember = function()
                    UnsupportedSkip.Save(folder, executor)
                end,
            })
        end
    end
    -- Custom disclaimers queue up after the executor warning, in order. Each
    -- one must be accepted (or skipped by an earlier "Don't show again").
    local disclaimers = opts.Disclaimer or opts.Disclaimers
    if type(disclaimers) == "string" or (type(disclaimers) == "table" and (disclaimers.Title ~= nil or disclaimers.Text ~= nil)) then
        disclaimers = { disclaimers }
    end
    if type(disclaimers) == "table" then
        for _, entry in ipairs(disclaimers) do
            if type(entry) == "string" then
                entry = { Text = entry }
            end
            if type(entry) == "table" then
                local key = UnsupportedSkip.DisclaimerKey(entry)
                local folder = self.ConfigFolder
                local block = entry.Block == true
                local rememberable = entry.Remember ~= false and not block
                if not (rememberable and UnsupportedSkip.DisclaimerAccepted(folder, key)) then
                    local callback = entry.Callback
                    table.insert(prompts, {
                        Title = entry.Title or "Disclaimer",
                        Subtitle = entry.Subtitle,
                        Text = entry.Text or "",
                        Icon = entry.Icon or "info",
                        Color = entry.Color or Theme.Accent,
                        ContinueText = entry.AcceptText or "I understand",
                        ExitText = entry.DeclineText == nil and "Exit" or entry.DeclineText,
                        RememberText = rememberable and (entry.RememberText or "Don't show again") or nil,
                        Remember = function()
                            UnsupportedSkip.AcceptDisclaimer(folder, key)
                        end,
                        Callback = type(callback) == "function" and callback or nil,
                        Block = block,
                    })
                end
            end
        end
    end
    if #prompts > 0 then
        opts._prompts = prompts
    end
    if loading == false and opts._prompts then
        opts.LoadingDuration = opts.LoadingDuration or 0.5
        loading = true
    end
    if loading == false then
        task.defer(function()
            self:_playIntro()
        end)
    else
        self:_showLoader(opts)
    end
    return self
end

Library.CreateWindow = Library.Window



function Library:Notify(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Notify(opts)
    end
end

function Library:Confirm(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Confirm(opts)
    end
end

function Library:Dialog(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Dialog(opts)
    end
end

local function isShown(object, stopAt, point)
    local child = object
    while child and child ~= stopAt and child:IsA("GuiObject") do
        if not child.Visible then
            return false
        end
        local parent = child.Parent
        if parent and parent ~= stopAt and parent:IsA("GuiObject") and (parent.ClipsDescendants or parent:IsA("ScrollingFrame")) and not pointInside(point, parent) then
            return false
        end
        child = parent
    end
    return true
end

function Window:_refreshControls()
    local controls = {}
    for _, object in ipairs(self.Body:GetDescendants()) do
        if object:IsA("GuiButton") or object:IsA("TextBox") or object:GetAttribute("NoDrag") then
            table.insert(controls, object)
        end
    end
    self._controls = controls
    self._controlsDirty = false
end

function Window:_overControl(point)
    if self._dialog or self:_overPopout(point) then
        return true
    end
    if self._controlsDirty then
        self:_refreshControls()
    end
    for _, object in ipairs(self._controls) do
        if object.Parent and pointInside(point, object) and isShown(object, self.Body, point) then
            return true
        end
    end
    return false
end

-- Tooltips: one shared card per window that follows the pointer over any
-- element built with Tooltip = "..." or { Title, Text, Icon }. It appears
-- after a short hover (straight away when moving from one tooltip to the
-- next), hides on press, and shows on a long press on touch screens.
function Window:_tooltipCard()
    if self._tip then
        return self._tip
    end
    local holder = create("CanvasGroup", {
        Name = "Tooltip",
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 60,
        Parent = self.Gui,
    })
    local tipScale = create("UIScale", { Parent = holder })
    -- Bare text, no card: a dark outline keeps it readable over anything.
    -- The holder is sized from the text by hand, since scale sizes inside an
    -- automatic size would stretch it across the screen.
    local PAD = 4
    local panel = create("Frame", {
        Position = UDim2.fromOffset(PAD, PAD),
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Parent = holder,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = panel,
    })
    local function outline(object)
        create("UIStroke", {
            Color = Color3.new(0, 0, 0),
            Transparency = 0.35,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
            Parent = object,
        })
    end
    local head = create("Frame", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = panel,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = head,
    })
    local icon = create("ImageLabel", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = head,
    })
    local title = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = head,
    })
    outline(title)
    local body = label({
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        TextSize = 12,
        FontFace = Fonts.Medium,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        LineHeight = 1.1,
        LayoutOrder = 2,
        Parent = panel,
    })
    outline(body)
    create("UISizeConstraint", { MaxSize = Vector2.new(240, math.huge), Parent = body })
    local function fit()
        local scale = math.max(tipScale.Scale, 0.01)
        local size = panel.AbsoluteSize / scale
        holder.Size = UDim2.fromOffset(size.X + PAD * 2, size.Y + PAD * 2)
    end
    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    local tip = {
        Holder = holder,
        Scale = tipScale,
        Pad = PAD,
        Head = head,
        Icon = icon,
        Title = title,
        Body = body,
        Shown = false,
        Fit = fit,
    }
    self._tip = tip
    -- Follow the pointer, and drop the card once its element is gone or off
    -- screen (tab switched, window hidden or minimized).
    self:_listen("Render", function(deltaTime)
        local owner = self._tipOwner
        if not owner then
            return
        end
        local frame = owner._frame
        if owner._destroyed or not self.Open or self.Minimized or not frame or not frame.Parent
            or (owner._isShown and not owner:_isShown()) or not isShown(frame, self.Body, frame.AbsolutePosition + frame.AbsoluteSize / 2) then
            self:_hideTooltip()
            return
        end
        local pointer = pointerPosition() - self.Gui.AbsolutePosition
        local pad = tip.Pad * tipScale.Scale
        local size = holder.AbsoluteSize - Vector2.one * pad * 2
        local view = self.Gui.AbsoluteSize
        local x, y
        if tip.Touch then
            x, y = pointer.X - size.X / 2, pointer.Y - size.Y - 30
        else
            x, y = pointer.X + 14, pointer.Y + 20
            if x + size.X > view.X - 8 then
                x = pointer.X - size.X - 10
            end
            if y + size.Y > view.Y - 8 then
                y = pointer.Y - size.Y - 12
            end
        end
        local target = Vector2.new(
            math.clamp(x, 8, math.max(8, view.X - size.X - 8)),
            math.clamp(y, 8, math.max(8, view.Y - size.Y - 8))
        )
        local current = tip.Position
        if not current or tip.Snap then
            -- Rises a few pixels into place as it fades in.
            current = target + Vector2.new(0, 6)
            tip.Snap = false
        else
            current = current:Lerp(target, math.min(deltaTime * 22, 1))
        end
        tip.Position = current
        holder.Position = UDim2.fromOffset(math.floor(current.X - pad + 0.5), math.floor(current.Y - pad + 0.5))
    end)
    -- A press anywhere (a dropdown chip inside the card, a key) hides it.
    self:_listen("Began", function(input)
        if self._tipOwner and not tip.Touch and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Keyboard) then
            self:_hideTooltip()
        end
    end)
    return tip
end

function Window:_showTooltip(element, touch)
    local value = element._tooltip
    local text, titleText, iconName
    if type(value) == "table" then
        text, titleText, iconName = value.Text or value.Content or value.Desc, value.Title or value.Name, value.Icon
    elseif value ~= nil and value ~= false then
        text = tostring(value)
    end
    if (text == nil or text == "") and (titleText == nil or titleText == "") then
        return
    end
    local tip = self:_tooltipCard()
    tip.Title.Text = titleText or ""
    tip.Title.Visible = titleText ~= nil and titleText ~= ""
    tip.Icon.Visible = iconName ~= nil
    if iconName ~= nil then
        applyIcon(tip.Icon, iconName)
    end
    tip.Head.Visible = tip.Title.Visible or iconName ~= nil
    tip.Body.Text = text or ""
    tip.Body.Visible = text ~= nil and text ~= ""
    tip.Fit()
    tip.Body.TextColor3 = Theme.Text
    tip.Scale.Scale = math.max(self.Scale.Scale, 0.75)
    tip.Touch = touch == true
    local wasShown = tip.Shown
    self._tipOwner = element
    tip.Shown = true
    tip.Generation = (tip.Generation or 0) + 1
    local holder = tip.Holder
    if not wasShown then
        tip.Snap = true
        holder.Visible = true
        holder.GroupTransparency = 1
        tip.Scale.Scale = tip.Scale.Scale * 0.96
    end
    tween(holder, { GroupTransparency = 0 }, 0.14, Enum.EasingStyle.Quad)
    tween(tip.Scale, { Scale = math.max(self.Scale.Scale, 0.75) }, 0.18, Enum.EasingStyle.Back)
end

function Window:_hideTooltip(element)
    local tip = self._tip
    if not tip or not tip.Shown or (element and self._tipOwner ~= element) then
        return
    end
    self._tipOwner = nil
    self._tipHiddenAt = os.clock()
    tip.Shown = false
    tip.Generation = (tip.Generation or 0) + 1
    local generation = tip.Generation
    tween(tip.Holder, { GroupTransparency = 1 }, 0.1, Enum.EasingStyle.Quad)
    task.delay(0.1, function()
        if tip.Generation == generation then
            tip.Holder.Visible = false
        end
    end)
end

function Window:_attachTooltip(element, frame)
    local hovering, token, pressAt = false, 0, nil
    local function begin(delay, touch)
        token += 1
        local mine = token
        task.delay(delay, function()
            if token ~= mine or not hovering or element._destroyed or self._destroyed then
                return
            end
            -- A finger that moved was scrolling, not holding.
            if touch and pressAt and (pointerPosition() - pressAt).Magnitude > 10 then
                return
            end
            self:_showTooltip(element, touch)
        end)
    end
    table.insert(element._listeners, (function()
        local connections = {
            frame.MouseEnter:Connect(function()
                if usingTouch() then
                    return
                end
                hovering = true
                local recent = os.clock() - (self._tipHiddenAt or 0) < 0.35 or self._tipOwner ~= nil
                begin(recent and 0 or 0.45, false)
            end),
            frame.MouseLeave:Connect(function()
                hovering = false
                token += 1
                self:_hideTooltip(element)
            end),
            frame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    hovering = true
                    pressAt = pointerPosition()
                    begin(0.5, true)
                end
            end),
            frame.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    hovering = false
                    token += 1
                    self:_hideTooltip(element)
                end
            end),
        }
        return function()
            for _, connection in ipairs(connections) do
                connection:Disconnect()
            end
        end
    end)())
end

-- While dragging, a stand-in follows the pointer while the window stays put,
-- and the window glides into its spot on release. The look is the player's
-- Drag Style; "Off" drags the window itself.
Library.DragStyles = { "Outline", "Brackets", "Ghost", "Frame", "Off" }

local function makeSkeleton(window)
    local root = window.Root
    local style = window.DragStyle or "Outline"
    local skeleton = create("Frame", {
        AnchorPoint = root.AnchorPoint,
        Position = root.Position,
        Size = UDim2.fromOffset(root.AbsoluteSize.X, root.AbsoluteSize.Y),
        BackgroundColor3 = style == "Ghost" and Theme.Background or Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 40,
        Parent = window.Gui,
    })
    corner(skeleton, UDim.new(0, 10))
    -- Each part fades from hidden to its shown values, and back on release.
    local parts = {}
    local function part(object, shown)
        local hidden = {}
        for key in pairs(shown) do
            hidden[key] = 1
        end
        table.insert(parts, { Object = object, Shown = shown, Hidden = hidden })
    end
    local function brackets(length, inset)
        for _, spot in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
            local at = UDim2.new(spot.X, spot.X == 0 and inset or -inset, spot.Y, spot.Y == 0 and inset or -inset)
            for _, size in ipairs({ UDim2.fromOffset(length, 2), UDim2.fromOffset(2, length) }) do
                local bracket = create("Frame", {
                    AnchorPoint = spot,
                    Position = at,
                    Size = size,
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Parent = skeleton,
                })
                corner(bracket, UDim.new(1, 0))
                part(bracket, { BackgroundTransparency = 0 })
            end
        end
    end
    if style == "Brackets" then
        -- Just the four corners of the window, a little longer.
        brackets(22, 0)
    elseif style == "Ghost" then
        -- A see-through copy of the window's panel.
        part(skeleton, { BackgroundTransparency = 0.35 })
        part(stroke(skeleton, Theme.Stroke, 1, 1), { Transparency = 0 })
    elseif style == "Frame" then
        -- A single quiet line, nothing else.
        part(stroke(skeleton, Theme.StrokeHover, 1, 1), { Transparency = 0 })
    else
        -- Outline: a faint accent wash, an outline and corner brackets.
        part(skeleton, { BackgroundTransparency = 0.92 })
        part(stroke(skeleton, Theme.Accent, 1, 1.5), { Transparency = 0.2 })
        brackets(16, 6)
    end
    local scale = create("UIScale", { Scale = 1.02, Parent = skeleton })
    for _, item in ipairs(parts) do
        tween(item.Object, item.Shown, 0.15, Enum.EasingStyle.Quad)
    end
    tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
    local function fade()
        for _, item in ipairs(parts) do
            tween(item.Object, item.Hidden, 0.2, Enum.EasingStyle.Quad)
        end
        task.delay(0.22, function()
            skeleton:Destroy()
        end)
    end
    return skeleton, fade
end

function Window:_enableDrag()
    local dragging, moved = false, false
    local grabOffset, pressPoint = Vector2.zero, Vector2.zero
    local target = nil
    local skeleton, fadeSkeleton = nil, nil

    local function centre()
        local root = self.Root
        return root.AbsolutePosition + root.AbsoluteSize * root.AnchorPoint - self.Gui.AbsolutePosition
    end

    local function dropSkeleton()
        if not skeleton then
            return
        end
        local spot = Vector2.new(skeleton.Position.X.Offset, skeleton.Position.Y.Offset)
        if self.KeepOnScreen then
            spot = self:_clampedCentre(spot)
        end
        if self._clampTween then
            self._clampTween:Cancel()
        end
        self._clampTween = tween(self.Root, { Position = UDim2.fromOffset(spot.X, spot.Y) }, 0.3, Enum.EasingStyle.Quint)
        fadeSkeleton()
        skeleton, fadeSkeleton = nil, nil
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input)
        if not isPress(input) then
            return
        end
        if not self.Open or not self.Root.Visible then
            return
        end
        local point = pointerPosition()
        if self._resizeActive or (self._grip and pointInside(point, self._grip)) then
            return
        end
        if not pointInside(point, self.Body) or self:_overControl(point) then
            return
        end
        if self._clampTween then
            self._clampTween:Cancel()
            self._clampTween = nil
        end
        dragging, moved = true, false
        pressPoint = point
        grabOffset = point - centre()
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if isPress(input) then
            dragging = false
            target = nil
            if skeleton then
                dropSkeleton()
            else
                self:_clampToScreen()
            end
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not dragging then
            return
        end
        local point = pointerPosition()
        if not moved and (point - pressPoint).Magnitude > 3 then
            moved = true
            if self.DragSkeleton then
                skeleton, fadeSkeleton = makeSkeleton(self)
            end
        end
        if not moved then
            return
        end
        -- Hidden or minimized mid-drag: land it where the outline is.
        if skeleton and (not self.Open or not self.Root.Visible) then
            dragging = false
            dropSkeleton()
            return
        end
        target = point - grabOffset
        local alpha = 1 - math.exp(-deltaTime * 45)
        if skeleton then
            local current = Vector2.new(skeleton.Position.X.Offset, skeleton.Position.Y.Offset)
            local step = current:Lerp(target, alpha)
            skeleton.Position = UDim2.fromOffset(step.X, step.Y)
        else
            local step = centre():Lerp(target, alpha)
            self.Root.Position = UDim2.fromOffset(step.X, step.Y)
        end
    end)
end

-- One of Library.DragStyles; anything else falls back to "Outline".
-- Returns the style it settled on.
function Window:SetDragStyle(style)
    style = table.find(Library.DragStyles, style) and style or "Outline"
    self.DragStyle = style
    self.DragSkeleton = style ~= "Off"
    return style
end

function Window:GetDragStyle()
    return self.DragStyle
end

-- How the minimized island shows the session card: opening it while
-- hovered, or keeping it open the whole time it's minimized.
Library.IslandStyles = { "Show on Hover", "Always Show" }

-- One of Library.IslandStyles; anything else falls back to "Show on Hover".
-- Returns the style it settled on.
function Window:SetIslandStyle(style)
    style = table.find(Library.IslandStyles, style) and style or "Show on Hover"
    self.IslandStyle = style
    if self._islandSettle then
        self._islandSettle()
    end
    return style
end

function Window:GetIslandStyle()
    return self.IslandStyle
end

-- The older on/off switch: off is the "Off" style, on brings back the
-- default style if it was off.
function Window:SetDragSkeleton(enabled)
    if enabled == false then
        self:SetDragStyle("Off")
    elseif self.DragStyle == "Off" or not self.DragStyle then
        self:SetDragStyle("Outline")
    end
end

-- The sidebar's divider is a grab strip: dragging it sets the rail's width,
-- kept between a usable minimum and enough room for the content.
function Window:_sidebarResize(sidebar, width)
    local divider = sidebar:FindFirstChild("Divider")
    local want = width
    local function apply(value, remember)
        if remember ~= false then
            want = value
        end
        local room = self.Body.AbsoluteSize.X / self.Scale.Scale - 300
        value = math.floor(math.clamp(value, 150, math.max(math.min(300, room), 150)))
        self.SidebarWidth = value
        sidebar.Size = UDim2.new(0, value, 1, 0)
        self.Content.Position = UDim2.fromOffset(value + 1, 0)
        self.Content.Size = UDim2.new(1, -(value + 1), 1, 0)
    end
    self.SetSidebarWidth = function(_, value)
        apply(tonumber(value) or SIDEBAR_WIDTH)
    end
    apply(width)
    local grip = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 6, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 6,
        Parent = sidebar,
    })
    grip:SetAttribute("NoDrag", true)
    local dragging, startX, startWidth = false, 0, width
    local function light(on)
        if divider then
            tween(divider, { BackgroundColor3 = on and Theme.Accent or Theme.Stroke }, 0.15)
        end
    end
    grip.MouseEnter:Connect(function()
        light(true)
    end)
    grip.MouseLeave:Connect(function()
        if not dragging then
            light(false)
        end
    end)
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, startX, startWidth = true, input.Position.X, self.SidebarWidth
            want = startWidth
            light(true)
        end
    end)
    self:_listen("Changed", function(input)
        if dragging and isMove(input) then
            apply(startWidth + (input.Position.X - startX) / self.Scale.Scale)
        end
    end)
    self:_listen("Ended", function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            light(false)
        end
    end)
    -- Shrinking the window pulls an over-wide rail back in.
    self.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not dragging then
            apply(want, false)
        end
    end)
end

-- See-through window: the body and sidebar let the game show through, and the
-- shadow lightens so it doesn't smudge behind them.
function Window:SetTransparent(enabled)
    self.Transparent = enabled == true
    local on = self.Transparent
    self._shadowRest = on and 0.85 or 0.6
    tween(self.Body, { BackgroundTransparency = on and 0.35 or 0 }, 0.25)
    -- See-through, the rail stays a touch more solid than the body so the
    -- tabs keep their contrast; over a background image it lets more through.
    local railAlpha = on and 0.5 or (self.Background and 0.45 or 0)
    tween(self.SidebarFill, { BackgroundTransparency = railAlpha }, 0.25)
    if self.Open and not self.Minimized and self.Root.Visible then
        tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.25)
    end
end

local function orderedChildren(parent)
    local children = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            table.insert(children, child)
        end
    end
    table.sort(children, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)
    return children
end

local function popIn(object, delay, force)
    if not object.Visible and not force then
        return
    end
    object.Visible = false
    task.delay(delay, function()
        if not object.Parent then
            return
        end
        local scaleObject = create("UIScale", { Scale = 0.94, Parent = object })
        object.Visible = true
        tween(scaleObject, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
        task.delay(0.4, function()
            scaleObject:Destroy()
        end)
    end)
end

function Window:_revealCards(tab, baseDelay)
    local container = tab.CurrentSubTab or tab
    if container._revealed then
        return
    end
    container._revealed = true
    local index = 0
    local function reveal(object)
        popIn(object, (baseDelay or 0) + index * 0.035)
        index += 1
    end
    local columns = container._columnSet
    for _, child in ipairs(orderedChildren(container.List)) do
        if columns and child == columns.Holder then
            local left, right = orderedChildren(columns.Left), orderedChildren(columns.Right)
            for row = 1, math.max(#left, #right) do
                if left[row] then
                    reveal(left[row])
                end
                if right[row] then
                    reveal(right[row])
                end
            end
        else
            reveal(child)
        end
    end
end

function Window:_playIntro(morph)
    if self._introDone or self._destroyed then
        return
    end
    self._introDone = true
    self:_refreshBackdrop(true)
    task.delay(0.4, function()
        self:_refreshToggleButton()
    end)
    -- Build the minimized bar ahead of time so the first minimize doesn't
    -- pay for it mid-click.
    task.delay(1.5, function()
        if not self._destroyed and not self.MiniBar then
            self:_buildMiniBar()
        end
    end)
    -- "Minimize UI on Start": fold into the island once, right after the
    -- first intro of this execution.
    if self:GetMinimizeOnStart() then
        task.delay(0.6, function()
            if not self._destroyed and self.Open and not self.Minimized then
                self:Minimize()
            end
        end)
    end
    local root, shadow, scale = self.Root, self.Shadow, self.Scale
    if self.CurrentTab then
        self:_revealCards(self.CurrentTab, morph and 0.15 or 0.25)
    end
    root.Visible = true
    if morph then
        scale.Scale = self._fitScale or 1
        root.Position = UDim2.fromScale(0.5, 0.5)
        self:_fade(0, 0.3)
        tween(self.BodyStroke, { Transparency = 0 }, 0.3)
        tween(shadow, { ImageTransparency = 0.6 }, 0.3)
    else
        root.Position = UDim2.new(0.5, 0, 0.5, 24)
        tween(scale, { Scale = self._fitScale or 1 }, 0.5, Enum.EasingStyle.Back)
        tween(root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.5, Enum.EasingStyle.Quint)
        self:_fade(0, 0.35)
        tween(self.BodyStroke, { Transparency = 0 }, 0.35)
    end
    if not morph then
        tween(shadow, { ImageTransparency = 0.6 }, 0.5)
    end

    for index, tab in ipairs(self.Tabs) do
        popIn(tab._button, 0.1 + index * 0.05, true)
    end
    self.Indicator.Visible = false
    task.delay(0.15 + #self.Tabs * 0.05, function()
        if self.CurrentTab then
            self:_placeIndicator(self.CurrentTab)
        end
    end)
end

function Window:_showLoader(opts)
    local duration = opts.LoadingDuration or 1.6
    local gui = self.Gui
    -- A compact card: logo, title and subtitle on top, a checklist of the
    -- loading steps under a hairline, and a thin progress line along the
    -- bottom edge. Everything but the prompt cards lives in one canvas group
    -- so it can fade as a unit.
    local steps = opts.LoadingSteps or { "Preparing interface", "Loading icons", "Almost there" }
    local WIDTH, PAD, STEP = 340, 22, 24
    local listTop = 80
    local height = listTop + #steps * STEP + 18
    local loader = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WIDTH, height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 10,
        Parent = gui,
    })
    local loaderCorner = corner(loader, UDim.new(0, 12))
    local loaderStroke = stroke(loader, Theme.Stroke, 1)
    local loaderScale = create("UIScale", { Scale = 0.97, Parent = loader })
    local loaderShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = loader,
    })
    local content = create("CanvasGroup", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = loader,
    })

    local logo = create("ImageLabel", {
        Position = UDim2.fromOffset(PAD, PAD),
        Size = UDim2.fromOffset(30, 30),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = content,
    })
    applyIcon(logo, opts.Icon or Assets.Logo, true)
    local TEXT_X = PAD + 42
    local titleLabel = label({
        Position = UDim2.fromOffset(TEXT_X, PAD - 2),
        Size = UDim2.new(1, -(TEXT_X + 70), 0, 18),
        Text = opts.LoadingTitle or opts.Title or "Airflow",
        TextSize = 15,
        FontFace = Fonts.Bold,
        Parent = content,
    })
    local statusLabel = label({
        Position = UDim2.fromOffset(TEXT_X, PAD + 17),
        Size = UDim2.new(1, -(TEXT_X + 70), 0, 15),
        Text = opts.LoadingText or opts.Subtitle or "Loading",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = content,
    })
    local percentLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -PAD, 0, PAD + 6),
        Size = UDim2.fromOffset(56, 16),
        Text = "0%",
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = content,
    })
    create("Frame", {
        Position = UDim2.fromOffset(PAD, listTop - 14),
        Size = UDim2.new(1, -PAD * 2, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = content,
    })

    -- Each step: a marker and its text. Pending is a dim dot, the running
    -- step a turning arc, and a finished one a check.
    local rows = {}
    for index, text in ipairs(steps) do
        local row = create("Frame", {
            Position = UDim2.fromOffset(PAD, listTop + (index - 1) * STEP),
            Size = UDim2.new(1, -PAD * 2, 0, STEP),
            BackgroundTransparency = 1,
            Parent = content,
        })
        local dot = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(6, 6),
            BackgroundColor3 = Theme.Surface3,
            BorderSizePixel = 0,
            Parent = row,
        })
        corner(dot, UDim.new(1, 0))
        local spinner = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = row,
        })
        corner(spinner, UDim.new(1, 0))
        local spinnerStroke = create("UIStroke", {
            Color = Theme.Accent,
            Thickness = 2,
            Parent = spinner,
        })
        create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(0.501, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = spinnerStroke,
        })
        local check = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            Parent = row,
        })
        applyIcon(check, "check")
        local stepLabel = label({
            Position = UDim2.fromOffset(24, 0),
            Size = UDim2.new(1, -24, 1, 0),
            Text = tostring(text),
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTransparency = 1,
            Parent = row,
        })
        rows[index] = { Dot = dot, Spinner = spinner, Check = check, Label = stepLabel, State = "pending" }
        -- The rows fade in one after another once the card is up.
        task.delay(0.15 + index * 0.06, function()
            if loader.Parent and rows[index].State == "pending" then
                tween(stepLabel, { TextTransparency = 0.45 }, 0.3)
            end
        end)
    end
    local function setStep(index, state)
        local row = rows[index]
        if not row or row.State == state then
            return
        end
        row.State = state
        row.Dot.Visible = state == "pending"
        row.Spinner.Visible = state == "active"
        tween(row.Check, { ImageTransparency = state == "done" and 0 or 1 }, 0.2)
        tween(row.Label, {
            TextTransparency = state == "pending" and 0.45 or 0,
            TextColor3 = state == "active" and Theme.Text or Theme.Muted,
        }, 0.2)
    end

    local track = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = content,
    })
    local fill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })

    tween(loader, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.45, Enum.EasingStyle.Quint)
    tween(loaderScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Quint)
    tween(loaderShadow, { ImageTransparency = 0.55 }, 0.4)
    tween(fill, { Size = UDim2.fromScale(0.85, 1) }, duration * 0.8, Enum.EasingStyle.Quart)
    -- The percentage follows the bar and the running step's arc turns.
    local percentStep
    percentStep = RunService.RenderStepped:Connect(function(deltaTime)
        if not loader.Parent then
            percentStep:Disconnect()
            return
        end
        percentLabel.Text = math.floor(fill.Size.X.Scale * 100 + 0.5) .. "%"
        for _, row in ipairs(rows) do
            if row.State == "active" then
                row.Spinner.Rotation = (row.Spinner.Rotation + deltaTime * 360) % 360
            end
        end
    end)

    task.spawn(loadLucide)

    for index in ipairs(steps) do
        task.delay(duration * (index - 1) / #steps, function()
            if not loader.Parent then
                return
            end
            if index > 1 then
                setStep(index - 1, "done")
            end
            setStep(index, "active")
        end)
    end
    local function completeSteps()
        for index in ipairs(rows) do
            setStep(index, "done")
        end
    end

    local function finish()
        completeSteps()
        tween(content, { GroupTransparency = 1 }, 0.18)

        local fit = self._fitScale or 1
        local target = self.Root.Size
        tween(loader, {
            Size = UDim2.fromOffset(target.X.Offset * fit, target.Y.Offset * fit),
            Position = UDim2.fromScale(0.5, 0.5),
        }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderCorner, { CornerRadius = UDim.new(0, Library._radius(10)) }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)

        task.delay(0.28, function()
            self:_playIntro(true)
            tween(loader, { GroupTransparency = 1 }, 0.25)
            tween(loaderStroke, { Transparency = 1 }, 0.2)
            tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
        end)
        task.delay(0.6, function()
            loader:Destroy()
        end)
    end

    -- Prompt cards (unsupported executor, custom disclaimers): the checklist
    -- gives way to one card at a time, each with Exit and Continue, before
    -- the window opens.
    local function hideBar()
        completeSteps()
        tween(content, { GroupTransparency = 1 }, 0.18)
    end

    local function showCard(info, onContinue)
        local WIDTH, PAD, MAX_BODY = 360, 24, 220
        local tone = info.Color or Theme.Accent
        -- Fixed width from the start, so the body wraps at its final width
        -- while the loader is still resizing.
        local warnCard = create("CanvasGroup", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0, WIDTH, 1, 0),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            ZIndex = 5,
            Parent = loader,
        })
        local badge = create("Frame", {
            Position = UDim2.fromOffset(PAD, PAD),
            Size = UDim2.fromOffset(44, 44),
            BackgroundColor3 = tone,
            BackgroundTransparency = 0.86,
            BorderSizePixel = 0,
            Parent = warnCard,
        })
        corner(badge, UDim.new(0, 12))
        stroke(badge, tone, 1).Transparency = 0.6
        local badgeIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(22, 22),
            BackgroundTransparency = 1,
            ImageColor3 = tone,
            ScaleType = Enum.ScaleType.Fit,
            Parent = badge,
        })
        applyIcon(badgeIcon, info.Icon or "info")
        label({
            Position = UDim2.fromOffset(PAD + 58, info.Subtitle and PAD + 3 or PAD + 12),
            Size = UDim2.new(1, -(PAD * 2 + 58), 0, 20),
            Text = info.Title,
            TextSize = 17,
            Parent = warnCard,
        })
        if info.Subtitle then
            label({
                Position = UDim2.fromOffset(PAD + 58, PAD + 25),
                Size = UDim2.new(1, -(PAD * 2 + 58), 0, 16),
                Text = tostring(info.Subtitle),
                TextSize = 13,
                TextColor3 = tone,
                Parent = warnCard,
            })
        end
        -- Long text scrolls past MAX_BODY instead of pushing the card off screen.
        local scroller = create("ScrollingFrame", {
            Position = UDim2.fromOffset(PAD, PAD + 60),
            Size = UDim2.new(1, -PAD * 2, 0, 16),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = TOUCH and 4 or 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(),
            Parent = warnCard,
        })
        local body = label({
            Size = UDim2.new(1, -8, 0, 0),
            Text = tostring(info.Text),
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = scroller,
        })
        local row = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, PAD, 1, -PAD + 4),
            Size = UDim2.new(1, -PAD * 2, 0, 34),
            BackgroundTransparency = 1,
            Parent = warnCard,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
            Parent = row,
        })

        -- Don't ask again: only offered when Continue is, and the executor
        -- can write the file that remembers it.
        local remember = false
        local rememberRow = nil
        if not info.Block and info.RememberText and UnsupportedSkip.Available() then
            local boxSize = TOUCH and 20 or 16
            rememberRow = create("TextButton", {
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, PAD, 1, -PAD + 4 - 34 - 12),
                Size = UDim2.new(1, -PAD * 2, 0, TOUCH and 28 or 22),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                Parent = warnCard,
            })
            local box = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.fromOffset(boxSize, boxSize),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Parent = rememberRow,
            })
            corner(box, UDim.new(0, 4))
            local boxStroke = stroke(box, Theme.Stroke, 1)
            local check = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(boxSize - 4, boxSize - 4),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.AccentDark,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = box,
            })
            applyIcon(check, "check")
            local rememberLabel = label({
                Position = UDim2.fromOffset(boxSize + 8, 0),
                Size = UDim2.new(1, -(boxSize + 8), 1, 0),
                Text = info.RememberText,
                TextSize = 12,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = rememberRow,
            })
            rememberRow.MouseEnter:Connect(function()
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.StrokeHover }, 0.12)
                tween(rememberLabel, { TextColor3 = Theme.Text }, 0.12)
            end)
            rememberRow.MouseLeave:Connect(function()
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.Stroke }, 0.2)
                tween(rememberLabel, { TextColor3 = remember and Theme.Text or Theme.Muted }, 0.2)
            end)
            rememberRow.MouseButton1Click:Connect(function()
                remember = not remember
                tween(box, { BackgroundColor3 = remember and Theme.Accent or Theme.Surface2 }, 0.15)
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.Stroke }, 0.15)
                tween(check, { ImageTransparency = remember and 0 or 1 }, 0.15)
                tween(rememberLabel, { TextColor3 = remember and Theme.Text or Theme.Muted }, 0.15)
            end)
        end

        local chosen = false
        local function button(text, primary, order, callback)
            local frame = create("TextButton", {
                Size = UDim2.fromOffset(0, 34),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = primary and Theme.Accent or Theme.Surface2,
                BackgroundTransparency = primary and 0.12 or 0,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = order,
                Parent = row,
            })
            corner(frame, UDim.new(0, 7))
            local frameStroke = stroke(frame, primary and Theme.Accent or Theme.Stroke, 1)
            frameStroke.Transparency = primary and 0.4 or 0
            padding(frame, 14, 14)
            label({
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = text,
                TextSize = 13,
                TextColor3 = primary and Theme.AccentDark or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Center,
                Parent = frame,
            })
            frame.MouseEnter:Connect(function()
                if primary then
                    tween(frame, { BackgroundTransparency = 0 }, 0.12)
                    tween(frameStroke, { Transparency = 0 }, 0.12)
                else
                    tween(frameStroke, { Color = Theme.StrokeHover }, 0.12)
                end
            end)
            frame.MouseLeave:Connect(function()
                if primary then
                    tween(frame, { BackgroundTransparency = 0.12 }, 0.2)
                    tween(frameStroke, { Transparency = 0.4 }, 0.2)
                else
                    tween(frameStroke, { Color = Theme.Stroke }, 0.2)
                end
            end)
            frame.MouseButton1Click:Connect(function()
                if chosen then
                    return
                end
                chosen = true
                callback()
            end)
        end
        if info.ExitText ~= false then
            button(info.ExitText or "Exit", info.Block, 1, function()
                if info.Callback then
                    task.spawn(info.Callback, false)
                end
                tween(loader, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 12) }, 0.25, Enum.EasingStyle.Quint)
                tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
                task.delay(0.25, function()
                    self:Destroy()
                end)
            end)
        end
        if not info.Block then
            button(info.ContinueText or "Continue", true, 2, function()
                if remember and info.Remember then
                    info.Remember()
                end
                if info.Callback then
                    task.spawn(info.Callback, true)
                end
                tween(warnCard, { GroupTransparency = 1 }, 0.15)
                task.delay(0.15, function()
                    warnCard:Destroy()
                    onContinue()
                end)
            end)
        end

        -- The card grows to fit the message, then it fades in. The wrapped
        -- height can land a few frames late (font loading, the scroller's
        -- layout), so the card refits whenever it changes.
        local laidOut = false
        -- TextBounds of wrapped text stops at the label's current height, so
        -- the card would fit to its own clipped text; the full wrapped height
        -- is measured at the body's width instead.
        local function measure()
            local ok, size = pcall(function()
                local params = Instance.new("GetTextBoundsParams")
                params.Text = body.Text
                params.Font = body.FontFace
                params.Size = body.TextSize
                params.Width = WIDTH - PAD * 2 - 8
                return game:GetService("TextService"):GetTextBoundsAsync(params)
            end)
            return ok and size and math.ceil(size.Y) + 2 or body.TextBounds.Y
        end
        local function fit(duration)
            local textHeight = math.max(measure(), 16)
            local bodyHeight = math.min(textHeight, MAX_BODY)
            body.Size = UDim2.new(1, -8, 0, textHeight)
            scroller.Size = UDim2.new(1, -PAD * 2, 0, bodyHeight)
            scroller.CanvasSize = UDim2.fromOffset(0, textHeight)
            local height = PAD + 60 + bodyHeight + 18 + 34 + PAD - 4
            if rememberRow then
                height += rememberRow.Size.Y.Offset + 10
            end
            tween(loader, { Size = UDim2.fromOffset(WIDTH, height) }, duration, Enum.EasingStyle.Quint)
        end
        body:GetPropertyChangedSignal("TextBounds"):Connect(function()
            if laidOut and loader.Parent and warnCard.Parent then
                fit(0.2)
            end
        end)
        task.delay(0.15, function()
            if not loader.Parent then
                return
            end
            laidOut = true
            fit(0.35)
            task.delay(0.12, function()
                tween(warnCard, { GroupTransparency = 0 }, 0.3)
                badge.Size = UDim2.fromOffset(34, 34)
                badge.Position = UDim2.fromOffset(PAD + 5, PAD + 5)
                tween(badge, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(PAD, PAD) }, 0.45, Enum.EasingStyle.Back)
            end)
        end)
    end

    local function runPrompts(queue, index)
        if not loader.Parent then
            return
        end
        local info = queue[index]
        if not info then
            finish()
            return
        end
        showCard(info, function()
            runPrompts(queue, index + 1)
        end)
    end

    task.delay(duration, function()
        tween(fill, { Size = UDim2.fromScale(1, 1) }, 0.25, Enum.EasingStyle.Quint)
        task.delay(0.25, function()
            if not loader.Parent then
                return
            end
            if opts._prompts then
                hideBar()
                runPrompts(opts._prompts, 1)
            else
                finish()
            end
        end)
    end)
end

function Window:_fitToScreen(instant)
    local viewport = self.Gui.AbsoluteSize
    if viewport.X == 0 or viewport.Y == 0 then
        return
    end
    local size = self.Root.Size
    -- The player's UI scale, times the adaptive factor for this screen, shrunk
    -- further when the window wouldn't fit.
    local wanted = (self._uiScale or 1) * (self._adaptive ~= false and Library._adaptiveFactor(viewport) or 1)
    local scale = math.min(wanted, (viewport.X - 24) / math.max(size.X.Offset, 1), (viewport.Y - 24) / math.max(size.Y.Offset, 1))
    self._fitScale = math.max(scale, 0.45)
    if self._introDone and self.Open then
        if instant then
            self.Scale.Scale = self._fitScale
        else
            tween(self.Scale, { Scale = self._fitScale }, 0.2)
        end
    end
end

-- Adaptive size: the window is drawn for a 1080p screen and grows on larger
-- ones (up to 1.75x on 4K) or shrinks a little on small laptops, so it covers
-- about the same share of any screen. 1080p-class screens, windowed or with
-- the topbar inset, stay at exactly 1. Touch screens only use the fit.
function Library._adaptiveFactor(viewport)
    if TOUCH then
        return 1
    end
    local factor = math.min(viewport.X / 1920, viewport.Y / 1020)
    if factor > 0.9 and factor < 1.15 then
        return 1
    end
    return math.clamp(math.floor(factor * 20 + 0.5) / 20, 0.85, 1.75)
end

function Window:SetAdaptiveSize(enabled)
    self._adaptive = enabled ~= false
    self:_fitToScreen()
    task.delay(0.22, function()
        if not self._destroyed then
            self:_clampToScreen()
        end
    end)
end

function Window:GetAdaptiveSize()
    return self._adaptive ~= false
end

-- UI scale: 0.6 to 1.5 on top of the automatic fit to small screens.
function Window:SetUIScale(value)
    value = math.clamp(tonumber(value) or 1, 0.6, 1.5)
    self.UIScale = value
    self._uiScale = value
    self:_fitToScreen()
    task.delay(0.22, function()
        if not self._destroyed then
            self:_clampToScreen()
        end
    end)
end

function Window:GetUIScale()
    return self._uiScale or 1
end

-- Density: the spacing between cards, groupboxes and rows. Shared by every
-- window, like the theme. Anything built with Library._space follows it.
Library.DensityModes = { Compact = 0.55, Default = 1, Comfortable = 1.45 }
Library.Density = "Default"

-- Small gaps (a groupbox's 2px rows) still move visibly between modes.
function Library._spaced(base, factor)
    if base <= 0 then
        return 0
    end
    return math.max(math.floor(base * factor + (factor - 1) * 4 + 0.5), 0)
end

function Library._space(object, base)
    local factor = Library.DensityModes[Library.Density] or 1
    if object:IsA("UIListLayout") or object:IsA("UIGridLayout") then
        object:SetAttribute("Space", base)
        object.Padding = UDim.new(0, Library._spaced(base, factor))
    elseif object:IsA("UIPadding") then
        -- base is { left, right, top, bottom }
        object:SetAttribute("SpaceL", base[1])
        object:SetAttribute("SpaceR", base[2])
        object:SetAttribute("SpaceT", base[3])
        object:SetAttribute("SpaceB", base[4])
        object.PaddingLeft = UDim.new(0, math.floor(base[1] * math.sqrt(factor) + 0.5))
        object.PaddingRight = UDim.new(0, math.floor(base[2] * math.sqrt(factor) + 0.5))
        object.PaddingTop = UDim.new(0, Library._spaced(base[3], factor))
        object.PaddingBottom = UDim.new(0, Library._spaced(base[4], factor))
    end
    return object
end

function Library:SetDensity(mode)
    if type(mode) == "string" then
        for name in pairs(Library.DensityModes) do
            if name:lower() == mode:lower() then
                mode = name
                break
            end
        end
    end
    if not Library.DensityModes[mode] then
        mode = "Default"
    end
    Library.Density = mode
    for _, window in ipairs(Library.Windows) do
        if window.Gui and window.Gui.Parent then
            for _, object in ipairs(window.Gui:GetDescendants()) do
                local base = object:GetAttribute("Space")
                if base then
                    Library._space(object, base)
                elseif object:GetAttribute("SpaceL") then
                    Library._space(object, {
                        object:GetAttribute("SpaceL"), object:GetAttribute("SpaceR"),
                        object:GetAttribute("SpaceT"), object:GetAttribute("SpaceB"),
                    })
                end
            end
        end
    end
    return mode
end

function Window:SetDensity(mode)
    return Library:SetDensity(mode)
end

function Window:GetDensity()
    return Library.Density
end

-- Nearest centre that keeps the whole window inside the viewport.
function Window:_clampedCentre(centre)
    local viewport = self.Gui.AbsoluteSize
    local half = self.Root.AbsoluteSize / 2
    return Vector2.new(
        math.clamp(centre.X, math.min(half.X, viewport.X / 2), math.max(viewport.X - half.X, viewport.X / 2)),
        math.clamp(centre.Y, math.min(half.Y, viewport.Y / 2), math.max(viewport.Y - half.Y, viewport.Y / 2))
    )
end

function Window:_clampToScreen()
    if not self.KeepOnScreen or self._resizeActive then
        return
    end
    local root = self.Root
    local centre = root.AbsolutePosition + root.AbsoluteSize / 2 - self.Gui.AbsolutePosition
    local clamped = self:_clampedCentre(centre)
    if (clamped - centre).Magnitude > 0.5 then
        self._clampTween = tween(root, { Position = UDim2.fromOffset(clamped.X, clamped.Y) }, 0.25, Enum.EasingStyle.Quint)
    end
end

function Window:_createOpenButton(opts)
    local gui = self.Gui
    local pill = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill, Theme.Stroke)
    padding(pill, 12, 16)
    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 31,
        Parent = pill,
    })
    applyIcon(icon, opts.Icon or Assets.Logo, true)
    label({
        Position = UDim2.fromOffset(28, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = opts.Title or "Airflow",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = 31,
        Parent = pill,
    })
    self.OpenButton = pill

    local dragging, moved = false, false
    local grab = Vector2.zero
    pill.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - pill.AbsolutePosition
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if isMove(input) then
            local point = pointerPosition() - grab - gui.AbsolutePosition
            if (point - (pill.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
                moved = true
            end
            pill.AnchorPoint = Vector2.new(0, 0)
            pill.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - pill.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - pill.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if dragging and isPress(input) then
            dragging = false
            if not moved then
                self:Toggle()
            end
        end
    end))
end

-- Square floating button that minimizes and restores the window. Shown on
-- touch devices only, or everywhere with Platform = "Both".
function Window:_toggleButtonAllowed()
    return self._toggleEnabled and (TOUCH or self._togglePlatform == "Both")
end

function Window:_refreshToggleButton()
    local button = self.ToggleButton
    if not button then
        return
    end
    local shown = self._introDone and not self._destroyed and self:_toggleButtonAllowed()
    if shown and not button.Visible then
        button.Visible = true
        button.Size = UDim2.fromOffset(0, 0)
        tween(button, { Size = UDim2.fromOffset(self._toggleSize, self._toggleSize) }, 0.45, Enum.EasingStyle.Quint)
    elseif not shown then
        button.Visible = false
    end
    -- Folded (window minimized or hidden): the outline takes the accent.
    local folded = self.Minimized or not self.Open
    tween(self._toggleStroke, { Color = folded and Theme.Accent or Theme.Stroke, Transparency = folded and 0.3 or 0 }, 0.35)
    local icon = self._toggleIcon
    tween(icon, { Rotation = folded and 180 or 0 }, 0.5, Enum.EasingStyle.Quint)
    if not icon:GetAttribute("CustomIcon") then
        tween(icon, { ImageColor3 = folded and Theme.Text or Theme.Accent }, 0.35)
    end
end

function Window:_createToggleButton(opts)
    local gui = self.Gui
    local size = tonumber(opts.Size) or (TOUCH and 56 or 50)
    local iconSize = math.floor(size * 0.46)
    self._toggleEnabled = opts.Enabled ~= false
    self._togglePlatform = opts.Platform == "Both" and "Both" or "Mobile"
    self._toggleSize = size
    local button = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = opts.Position or UDim2.new(0, 18 + size / 2, 0.5, 0),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(button, UDim.new(0, 12))
    local buttonStroke = stroke(button, Theme.Stroke)
    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(iconSize, iconSize),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 31,
        Parent = button,
    })
    local buttonScale = create("UIScale", { Parent = button })
    self.ToggleButton = button
    self._toggleStroke = buttonStroke
    self._toggleIcon = icon
    self:SetToggleButtonIcon(opts.Icon or "layout-grid")

    local dragging, moved = false, false
    local grab = Vector2.zero
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - button.AbsolutePosition
            tween(buttonScale, { Scale = 0.94 }, 0.18, Enum.EasingStyle.Quint)
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging or not isMove(input) then
            return
        end
        local point = pointerPosition() - grab - gui.AbsolutePosition
        if (point - (button.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
            moved = true
        end
        if moved then
            button.AnchorPoint = Vector2.zero
            button.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - button.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - button.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging or not isPress(input) then
            return
        end
        dragging = false
        tween(buttonScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        if moved then
            return
        end
        ripple(button)
        if not self.Open then
            self:Toggle(true)
        elseif self.Minimized then
            self:Restore()
        else
            self:Minimize()
        end
    end))
end

function Window:SetToggleButton(enabled)
    self._toggleEnabled = enabled ~= false
    self:_refreshToggleButton()
end

function Window:SetToggleButtonPlatform(platform)
    self._togglePlatform = platform == "Both" and "Both" or "Mobile"
    self:_refreshToggleButton()
end

function Window:SetToggleButtonIcon(icon)
    local image = self._toggleIcon
    if not image then
        return
    end
    image.Image = ""
    applyIcon(image, icon)
    if image.Image == "" then
        applyIcon(image, Assets.Logo)
    end
    if not image:GetAttribute("CustomIcon") then
        tween(image, { ImageColor3 = (self.Minimized or not self.Open) and Theme.Text or Theme.Accent }, 0)
    end
end

function Window:_enableResize(minSize)
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)
    self._minSize = minSize
    local root = self.Root
    local grip = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 4, 1, 4),
        Size = UDim2.fromOffset(32, 32),
        BackgroundTransparency = 1,
        Active = true,
        ZIndex = 20,
        Parent = root,
    })
    self._grip = grip
    -- An arc that traces the window's own rounded corner: a rounded square
    -- laid over the corner whose outline fades out away from it, so only the
    -- curve and a short run of each edge show. Faint at rest, accent in use.
    local gripArc = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        ZIndex = 20,
        Parent = grip,
    })
    corner(gripArc, UDim.new(0, 10))
    local gripStroke = create("UIStroke", {
        Color = Theme.Muted,
        Thickness = 2,
        Transparency = 0.55,
        Parent = gripArc,
    })
    create("UIGradient", {
        Rotation = 45,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.55, 1),
            NumberSequenceKeypoint.new(0.85, 0),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = gripStroke,
    })
    local function lightGrip(on)
        tween(gripStroke, {
            Color = on and Theme.Accent or Theme.Muted,
            Transparency = on and 0 or 0.55,
        }, on and 0.15 or 0.3, Enum.EasingStyle.Quint)
    end

    -- The size follows the pointer through a critically damped spring, so it
    -- glides after the cursor and eases to rest when released instead of
    -- snapping. While resizing, the window is anchored at its top-left corner
    -- so only the right and bottom edges move and nothing jitters on half pixels.
    local STIFFNESS = 20
    local resizing = false
    local startSize = Vector2.zero
    local startPointer = Vector2.zero
    local current = Vector2.zero
    local velocity = Vector2.zero
    local target = Vector2.zero
    local applied = Vector2.zero

    local function readSize()
        return Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
    end

    local function pin()
        if root.AnchorPoint == Vector2.zero then
            return
        end
        -- A clamp tween still writing centre coordinates would fight the new anchor.
        if self._clampTween then
            self._clampTween:Cancel()
            self._clampTween = nil
        end
        local topLeft = root.AbsolutePosition - self.Gui.AbsolutePosition
        root.AnchorPoint = Vector2.zero
        root.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
    end

    local function unpin()
        local topLeft = root.AbsolutePosition - self.Gui.AbsolutePosition
        local half = root.AbsoluteSize / 2
        root.AnchorPoint = Vector2.new(0.5, 0.5)
        root.Position = UDim2.fromOffset(topLeft.X + half.X, topLeft.Y + half.Y)
    end

    local function clampSize(size)
        return Vector2.new(
            math.floor(math.clamp(size.X, minSize.X, maxSize.X) + 0.5),
            math.floor(math.clamp(size.Y, minSize.Y, maxSize.Y) + 0.5)
        )
    end

    grip.InputBegan:Connect(function(input)
        if not isPress(input) or not self.Open then
            return
        end
        if not self._resizeActive then
            pin()
            current = readSize()
            velocity = Vector2.zero
            applied = current
        end
        self._resizeActive = true
        resizing = true
        startSize = current
        startPointer = pointerPosition()
        target = clampSize(startSize)
        lightGrip(true)
    end)
    grip.MouseEnter:Connect(function()
        if not resizing then
            lightGrip(true)
        end
    end)
    grip.MouseLeave:Connect(function()
        if not resizing then
            lightGrip(false)
        end
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if resizing and isPress(input) then
            resizing = false
            lightGrip(false)
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not self._resizeActive then
            return
        end
        if resizing then
            local delta = (pointerPosition() - startPointer) / self.Scale.Scale
            target = clampSize(startSize + delta)
        end
        local dt = math.min(deltaTime, 1 / 30)
        local decay = math.exp(-STIFFNESS * dt)
        local offset = current - target
        local drift = (velocity + offset * STIFFNESS) * dt
        velocity = (velocity - drift * STIFFNESS) * decay
        current = target + (offset + drift) * decay

        local rounded = Vector2.new(math.floor(current.X + 0.5), math.floor(current.Y + 0.5))
        if rounded ~= applied then
            applied = rounded
            root.Size = UDim2.fromOffset(rounded.X, rounded.Y)
        end

        if not resizing and (current - target).Magnitude < 0.3 and velocity.Magnitude < 3 then
            current = target
            velocity = Vector2.zero
            applied = target
            root.Size = UDim2.fromOffset(target.X, target.Y)
            unpin()
            self._resizeActive = false
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end)
end

-- The window's own size in pixels, before the UI scale and screen fit.
function Window:GetSize()
    return Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
end

-- Resizes to an exact size, kept within MinSize and MaxSize. Ignored while the
-- player is dragging the grip.
function Window:SetSize(size, instant)
    if typeof(size) == "UDim2" then
        size = Vector2.new(size.X.Offset, size.Y.Offset)
    end
    if typeof(size) ~= "Vector2" or self._resizeActive then
        return
    end
    local minSize = self._minSize or Vector2.zero
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)
    size = Vector2.new(
        math.floor(math.clamp(size.X, minSize.X, maxSize.X) + 0.5),
        math.floor(math.clamp(size.Y, minSize.Y, maxSize.Y) + 0.5)
    )
    if size == self:GetSize() then
        return
    end
    local duration = (instant or not self.Root.Visible) and 0 or 0.3
    tween(self.Root, { Size = UDim2.fromOffset(size.X, size.Y) }, duration, Enum.EasingStyle.Quint)
    task.delay(duration + 0.02, function()
        if not self._destroyed then
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end)
end

-- Configs are plain JSON, one file per config, in the same shape as a share code:
--   {"Folder":"MyHub","Name":"farm","Version":1,"Config":"{\"AutoFarm\":{\"Value\":true,\"Type\":\"Toggle\"}}"}
-- Config holds the flags as their own JSON string, each one {"Value":...,"Type":...}.
-- Colours are {"Hex":"ff5a5a"}, keybinds are key names, an empty dropdown has no Value.

local CONFIG_VERSION = 1
local LEGACY_SHARE_PREFIX = "airflow:"

local function configPath(self, name)
    return self.ConfigFolder .. "/" .. name .. ".json"
end

local function fileApiAvailable()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

-- Makes every missing folder along the path, so FolderName can be "Hub/Game".
local function ensureFolder(folder)
    if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
        return
    end
    local path = ""
    for segment in tostring(folder):gmatch("[^/\\]+") do
        path = path == "" and segment or path .. "/" .. segment
        if not isfolder(path) then
            makefolder(path)
        end
    end
end

local function colorToHex(color)
    return string.format("%02x%02x%02x",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

local function colorFromValue(value)
    if type(value) == "table" then
        if type(value.Hex) == "string" then
            value = value.Hex
        elseif type(value[1]) == "number" then
            -- Older configs stored { r, g, b } in 0-1.
            return Color3.new(value[1], value[2] or 0, value[3] or 0)
        end
    end
    if type(value) == "string" then
        local r, g, b = value:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
        end
    end
    return nil
end

local function serializeFlag(element)
    local kind = element._type
    local value = element:Get()
    if type(element._saveValue) == "function" then
        value = element:_saveValue()
    end
    if kind == "Keybind" then
        return { Type = kind, Value = value and value.Name or nil }
    elseif kind == "ColorPicker" then
        return { Type = kind, Value = typeof(value) == "Color3" and { Hex = colorToHex(value) } or nil }
    end
    return { Type = kind, Value = value }
end

local function deserializeFlag(element, entry, silent)
    local kind = element._type
    local value = entry.Value
    if kind == "Keybind" then
        element:Set(type(value) == "string" and Enum.KeyCode[value] or nil, silent)
    elseif kind == "ColorPicker" then
        local color = colorFromValue(value)
        if color then
            element:Set(color, silent)
        end
    elseif kind == "Dropdown" then
        -- A dropdown saved with nothing picked has no Value at all.
        element:Set(value, silent)
    elseif kind == "Toggle" then
        if type(value) == "boolean" then
            element:Set(value, silent)
        end
    elseif kind == "Slider" or kind == "Stepper" or kind == "Progress" then
        local number = tonumber(value)
        if number then
            element:Set(number, silent)
        end
    elseif value ~= nil then
        element:Set(value, silent)
    end
end

local function entryMatches(element, entry)
    return type(entry) == "table" and (entry.Type == nil or entry.Type == element._type)
end

-- Flags a config holds but no element has claimed yet are kept here. They are
-- applied when an element with that flag is created and written back on save,
-- so a config survives elements that only exist some of the time.
local function collectFlags(self)
    local data = {}
    if self and self._pendingFlags then
        for flag, pending in pairs(self._pendingFlags) do
            data[flag] = pending.Entry
        end
    end
    local ignore = self and self._ignoreFlags or {}
    for flag in pairs(ignore) do
        data[flag] = nil
    end
    for flag, element in pairs(Library.Flags) do
        if not ignore[flag] and element._type and type(element.Get) == "function" then
            local ok, entry = pcall(serializeFlag, element)
            if ok then
                data[flag] = entry
            end
        end
    end
    return data
end

-- Values first, switches last: a toggle's callback then starts with the
-- sliders and dropdowns it reads already in place. Override per window with
-- Window:SetLoadingOrder.
Library.LoadingOrder = { "Dropdown", "Slider", "Stepper", "Input", "ColorPicker", "Keybind", "Toggle" }

-- Flags a config never saves or loads, like Obsidian's SaveManager:SetIgnoreIndexes.
function Window:SetIgnoreFlags(flags)
    self._ignoreFlags = self._ignoreFlags or {}
    for _, flag in ipairs(flags or {}) do
        self._ignoreFlags[flag] = true
    end
end

function Window:SetLoadingOrder(order)
    self._loadingOrder = type(order) == "table" and order or nil
end

function Window:_applyFlags(data, silent)
    silent = silent == true
    self._pendingFlags = {}
    local ignore = self._ignoreFlags or {}
    local order = self._loadingOrder or Library.LoadingOrder
    local queue = {}
    for flag, entry in pairs(data) do
        if not ignore[flag] then
            local element = Library.Flags[flag]
            if element and type(element.Set) == "function" then
                if entryMatches(element, entry) then
                    table.insert(queue, { Element = element, Entry = entry, Rank = table.find(order, element._type) or 0 })
                end
            elseif type(entry) == "table" then
                self._pendingFlags[flag] = { Entry = entry, Silent = silent }
            end
        end
    end
    table.sort(queue, function(a, b)
        return a.Rank < b.Rank
    end)
    -- Like Obsidian: each flag is deferred onto its own thread, so a callback
    -- that loops while its toggle is on can't stall the others or the script
    -- that asked for the load.
    for _, item in ipairs(queue) do
        task.defer(function()
            if not item.Element._destroyed and not self._destroyed then
                pcall(deserializeFlag, item.Element, item.Entry, silent)
            end
        end)
    end
end

-- Every flagged element reports here: its starting value becomes its default,
-- and a value waiting from an earlier load is applied once the constructor returns.
function Window:_flagCreated(flag, element)
    local ok, entry = pcall(serializeFlag, element)
    if ok then
        element._defaultEntry = entry
    end
    local pending = self._pendingFlags and self._pendingFlags[flag]
    if not pending then
        return
    end
    task.defer(function()
        if self._pendingFlags[flag] ~= pending or Library.Flags[flag] ~= element or element._destroyed then
            return
        end
        self._pendingFlags[flag] = nil
        if entryMatches(element, pending.Entry) then
            pcall(deserializeFlag, element, pending.Entry, pending.Silent)
        end
    end)
end

-- Anything listening for config changes (the config manager's status line).
function Window:_configChanged()
    for _, handler in ipairs(self._configListeners) do
        safeCall(handler)
    end
end

function Window:OnConfigChanged(handler)
    table.insert(self._configListeners, handler)
    return function()
        local index = table.find(self._configListeners, handler)
        if index then
            table.remove(self._configListeners, index)
        end
    end
end

local function validConfigName(name)
    return type(name) == "string" and name ~= "" and not name:find('[\\/:%*%?"<>|]')
end

local function encodeConfig(self, name, flags)
    return HttpService:JSONEncode({
        Folder = self.ConfigFolder,
        Name = name,
        Version = CONFIG_VERSION,
        Config = HttpService:JSONEncode(flags),
    })
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for index = 1, #B64 do
    B64_INDEX[B64:byte(index)] = index - 1
end

-- Only for reading the old "airflow:<base64>" share codes.
local function base64Decode(text)
    if #text % 4 ~= 0 then
        return nil
    end
    local out = {}
    for index = 1, #text, 4 do
        local n, pad = 0, 0
        for offset = 0, 3 do
            local byte = text:byte(index + offset)
            local value = B64_INDEX[byte]
            if byte == 61 and index + 3 >= #text then
                pad += 1
                value = 0
            elseif value == nil or pad > 0 then
                return nil
            end
            n = n * 64 + value
        end
        if pad > 2 then
            return nil
        end
        local chunk = string.char(bit32.extract(n, 16, 8), bit32.extract(n, 8, 8), bit32.extract(n, 0, 8))
        table.insert(out, chunk:sub(1, 3 - pad))
    end
    return table.concat(out)
end

-- Reads a config file or a pasted code: the JSON above (Config as a string or
-- a table), a bare flag table, or an old "airflow:" code. Returns flags, info.
local function decodeConfig(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text:sub(1, #LEGACY_SHARE_PREFIX) == LEGACY_SHARE_PREFIX then
        text = base64Decode((text:sub(#LEGACY_SHARE_PREFIX + 1):gsub("%s", "")))
        if not text then
            return nil, "invalid config code"
        end
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        return nil, "invalid config code"
    end
    local info = {}
    -- A bare flag table could have a flag named Config, but its entry carries a Type.
    if type(data.Config) == "string" or (type(data.Config) == "table" and data.Config.Type == nil) then
        info.Folder = type(data.Folder) == "string" and data.Folder or nil
        info.Name = type(data.Name) == "string" and data.Name or nil
        info.Version = tonumber(data.Version)
        local flags = data.Config
        if type(flags) == "string" then
            ok, flags = pcall(function()
                return HttpService:JSONDecode(data.Config)
            end)
            if not ok then
                return nil, "invalid config code"
            end
        end
        if type(flags) ~= "table" then
            return nil, "invalid config code"
        end
        data = flags
    end
    for flag, entry in pairs(data) do
        if type(flag) ~= "string" or type(entry) ~= "table" then
            return nil, "invalid config code"
        end
    end
    return data, info
end

local function writeConfig(self, name, data)
    if not validConfigName(name) then
        return false, "invalid config name"
    end
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    local encoded, text = pcall(encodeConfig, self, name, data)
    if not encoded then
        return false, "could not encode config"
    end
    ensureFolder(self.ConfigFolder)
    return pcall(writefile, configPath(self, name), text)
end

local function readConfig(self, name)
    if not fileApiAvailable() then
        return nil, "file API unavailable"
    end
    if not validConfigName(name) then
        return nil, "invalid config name"
    end
    local path = configPath(self, name)
    if not isfile(path) then
        return nil, "no config named " .. tostring(name)
    end
    local ok, text = pcall(readfile, path)
    if not ok or type(text) ~= "string" then
        return nil, "could not read " .. name
    end
    local data, info = decodeConfig(text)
    if not data then
        return nil, "config is not valid JSON"
    end
    return data, info
end

function Window:ConfigExists(name)
    return validConfigName(name) and fileApiAvailable() and isfile(configPath(self, name)) or false
end

function Window:SaveConfig(name)
    name = name or self.ConfigName
    if not name then
        return false, "no config name"
    end
    local ok, err = writeConfig(self, name, collectFlags(self))
    if ok then
        self.ConfigName = name
    end
    return ok, err
end

function Window:LoadConfig(name, silent)
    name = name or self.ConfigName
    if not name then
        return false, "no config name"
    end
    local data, err = readConfig(self, name)
    if not data then
        return false, err
    end
    self:_applyFlags(data, silent)
    self.ConfigName = name
    self.LoadedConfig = name
    self:_configChanged()
    return true
end

function Window:DeleteConfig(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end
    if not validConfigName(name) then
        return false, "invalid config name"
    end
    local path = configPath(self, name)
    if not isfile(path) then
        return false, "no config named " .. name
    end
    local ok, err = pcall(delfile, path)
    if not ok then
        return false, err
    end
    if self.LoadedConfig == name then
        self.LoadedConfig = nil
    end
    self:_configChanged()
    return true
end

-- Moves the file and anything pointing at it: the loaded name and both autoloads.
function Window:RenameConfig(name, newName)
    if not validConfigName(newName) then
        return false, "invalid config name"
    end
    if name == newName then
        return true
    end
    if self:ConfigExists(newName) then
        return false, newName .. " already exists"
    end
    local data, err = readConfig(self, name)
    if not data then
        return false, err
    end
    local ok
    ok, err = writeConfig(self, newName, data)
    if not ok then
        return false, err
    end
    if type(delfile) == "function" then
        pcall(delfile, configPath(self, name))
    end
    if self.LoadedConfig == name then
        self.LoadedConfig = newName
    end
    if self.ConfigName == name then
        self.ConfigName = newName
    end
    for _, scope in ipairs({ "Global", "Account" }) do
        if self:GetAutoload(scope) == name then
            self:SetAutoload(newName, scope)
        end
    end
    self:_configChanged()
    return true
end

function Window:ListConfigs()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(self.ConfigFolder) then
        return names
    end
    local ok, paths = pcall(listfiles, self.ConfigFolder)
    if not ok or type(paths) ~= "table" then
        return names
    end
    for _, path in ipairs(paths) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

-- Puts every flagged element back to the value it was created with.
function Window:ResetConfig(silent)
    self._pendingFlags = {}
    for _, element in pairs(Library.Flags) do
        if element._defaultEntry and type(element.Set) == "function" then
            pcall(deserializeFlag, element, element._defaultEntry, silent == true)
        end
    end
    self:_configChanged()
    return true
end

-- Empties a folder and removes it, one file at a time when the executor has
-- no delfolder or it refuses a folder that still has files in it.
local function wipeFolder(path)
    if type(isfolder) ~= "function" or not isfolder(path) then
        return true
    end
    if type(delfolder) == "function" and pcall(delfolder, path) and not isfolder(path) then
        return true
    end
    if type(listfiles) == "function" then
        local ok, entries = pcall(listfiles, path)
        for _, entry in ipairs(ok and entries or {}) do
            if isfolder(entry) then
                wipeFolder(entry)
            elseif type(delfile) == "function" then
                pcall(delfile, entry)
            end
        end
    end
    if type(delfolder) == "function" then
        pcall(delfolder, path)
    end
    return not isfolder(path)
end

-- Deletes the script's whole workspace folder: configs, themes, the default
-- theme, autoload, settings and the execution count.
function Window:ClearWorkspace()
    local ok = wipeFolder(self.ConfigFolder)
    self.LoadedConfig = nil
    for _, handler in ipairs(self._workspaceListeners or {}) do
        safeCall(handler)
    end
    self:_configChanged()
    return ok
end

-- Share codes are the same JSON a config file holds.

function Window:ExportConfig(name)
    local data, err
    if name then
        data, err = readConfig(self, name)
        if not data then
            return nil, err
        end
    else
        data = collectFlags(self)
        name = self.LoadedConfig or self.ConfigName
    end
    local ok, code = pcall(encodeConfig, self, name, data)
    if not ok then
        return nil, "could not encode config"
    end
    return code
end

-- Reads a code without applying it. Returns flags and { Folder, Name, Version }.
function Window:DecodeConfig(code)
    return decodeConfig(code)
end

-- saveAs: a name to save under, true for the name inside the code, or nil to
-- only apply it. Codes made for another folder are refused unless force is set.
function Window:ImportConfig(code, saveAs, force)
    local data, info = decodeConfig(code)
    if not data then
        return false, info
    end
    if not force and info.Folder and info.Folder ~= self.ConfigFolder then
        return false, "config is for " .. info.Folder
    end
    if saveAs == true then
        saveAs = info.Name
        if not validConfigName(saveAs) then
            return false, "config has no usable name"
        end
    end
    if saveAs then
        local ok, err = writeConfig(self, saveAs, data)
        if not ok then
            return false, err
        end
    end
    self:_applyFlags(data)
    if saveAs then
        self.ConfigName = saveAs
        self.LoadedConfig = saveAs
    end
    self:_configChanged()
    return true, nil, saveAs
end

local function readText(path)
    if not fileApiAvailable() or not isfile(path) then
        return nil
    end
    local ok, text = pcall(readfile, path)
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

local function removeFile(path)
    if fileApiAvailable() and type(delfile) == "function" and isfile(path) then
        pcall(delfile, path)
    end
end

-- Manager settings (autoload mode) live beside the configs, apart
-- from the flags, so loading a config never changes them.

local function settingsPath(self)
    return self.ConfigFolder .. "/configsettings.txt"
end

function Window:_readConfigSettings()
    local text = readText(settingsPath(self))
    if text then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(text)
        end)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

function Window:_writeConfigSettings(changes)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    local data = self:_readConfigSettings()
    for key, value in pairs(changes) do
        data[key] = value
    end
    ensureFolder(self.ConfigFolder)
    return pcall(writefile, settingsPath(self), HttpService:JSONEncode(data))
end

-- Autoload: one config name kept next to the configs, either for every
-- account ("Global") or only the local player ("Account").

local function autoloadPath(self, scope)
    if scope == "Account" then
        return self.ConfigFolder .. "/autoload_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0) .. ".txt"
    end
    return self.ConfigFolder .. "/autoload.txt"
end

function Window:GetAutoloadMode()
    return self:_readConfigSettings().AutoloadMode == "Account" and "Account" or "Global"
end

function Window:GetAutoload(scope)
    if scope then
        return readText(autoloadPath(self, scope))
    end
    return readText(autoloadPath(self, "Account")) or readText(autoloadPath(self, "Global"))
end

function Window:SetAutoload(name, scope)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    scope = scope or self:GetAutoloadMode()
    local ok, err = true, nil
    if name == nil or name == "" then
        removeFile(autoloadPath(self, scope))
        if scope == "Global" then
            removeFile(autoloadPath(self, "Account"))
        end
    else
        ensureFolder(self.ConfigFolder)
        ok, err = pcall(writefile, autoloadPath(self, scope), tostring(name))
        if ok and scope == "Global" then
            removeFile(autoloadPath(self, "Account"))
        end
    end
    self:_configChanged()
    return ok, err
end

-- Switching the mode moves the current autoload so only one stays active.
function Window:SetAutoloadMode(mode)
    mode = mode == "Account" and "Account" or "Global"
    if mode == self:GetAutoloadMode() then
        return true
    end
    local current = self:GetAutoload()
    local ok, err = self:_writeConfigSettings({ AutoloadMode = mode })
    if not ok then
        return false, err
    end
    removeFile(autoloadPath(self, mode == "Account" and "Global" or "Account"))
    if current then
        return self:SetAutoload(current, mode)
    end
    self:_configChanged()
    return true
end

-- Minimize UI on Start: kept with the config settings so it applies on the
-- next execution no matter which config loads.
function Window:GetMinimizeOnStart()
    return self:_readConfigSettings().MinimizeOnStart == true
end

function Window:SetMinimizeOnStart(enabled)
    return self:_writeConfigSettings({ MinimizeOnStart = enabled == true })
end

function Window:LoadAutoload(silent)
    if self._autoloaded then
        return false, "autoload already ran"
    end
    self._autoloaded = true
    local name = self:GetAutoload()
    if not name then
        return false, "no autoload config"
    end
    local ok, err = self:LoadConfig(name, silent)
    pcall(self.Notify, self, {
        Title = ok and "Autoload" or "Autoload failed",
        Content = ok and ("Loaded config %q"):format(name) or tostring(err),
        Type = ok and "Success" or "Error",
        Duration = 3,
    })
    return ok, err
end

-- Themes

Library._themeListeners = {}

local function toColor(value)
    if typeof(value) == "Color3" then
        return value
    elseif type(value) == "string" then
        local r, g, b = value:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
        end
    elseif type(value) == "table" then
        local r, g, b = value[1] or value.R, value[2] or value.G, value[3] or value.B
        if tonumber(r) and tonumber(g) and tonumber(b) then
            return Color3.fromRGB(r, g, b)
        end
    end
    return nil
end

local function hexOf(color)
    return string.format("#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

-- Coloured text for statuses, metrics, table cells and labels. A theme key
-- used as a tag, <Success>online</Success>, follows theme changes; plain
-- rich text such as <font color="#ff5a5a"> works too. Library.Colorize wraps
-- text for you. Table fields, not locals: the chunk is at Luau's 200 limit.
Library._toneTags = {}
for _, name in ipairs(THEME_KEYS) do
    Library._toneTags[string.lower(name)] = name
end

-- DependsOn rules: "Flag" (its value is on: true, a non-empty pick, a
-- non-zero number), { Flag, Value, Not } (Value may be a list of accepted
-- values; a multi dropdown passes when it holds any of them), a list of rules
-- that must all pass, or a function returning true.
function Library._dependsMet(rule)
    if type(rule) == "function" then
        local ok, result = pcall(rule)
        return ok and result and true or false
    end
    if type(rule) == "string" then
        rule = { Flag = rule }
    end
    if type(rule) ~= "table" then
        return true
    end
    if rule.Flag == nil then
        for _, sub in ipairs(rule) do
            if not Library._dependsMet(sub) then
                return false
            end
        end
        return true
    end
    local element = Library.Flags[rule.Flag]
    local met = false
    if element and type(element.Get) == "function" then
        local ok, value = pcall(element.Get, element)
        if ok then
            if rule.Value ~= nil then
                local wanted = type(rule.Value) == "table" and rule.Value or { rule.Value }
                local values = type(value) == "table" and value or { value }
                for _, item in ipairs(wanted) do
                    if table.find(values, item) then
                        met = true
                        break
                    end
                end
            else
                met = value == true
                    or (type(value) == "number" and value ~= 0)
                    or (type(value) == "string" and value ~= "")
                    or (type(value) == "table" and next(value) ~= nil)
                    or typeof(value) == "EnumItem"
                    or typeof(value) == "Color3"
            end
        end
    end
    if rule.Not then
        met = not met
    end
    return met
end

function Library._applyDepends(element, force)
    local met = element._dependsOn == nil or Library._dependsMet(element._dependsOn)
    if met == element._dependsMet and not force then
        return
    end
    element._dependsMet = met
    local mode = string.lower(tostring(element._dependsMode or "Hide"))
    if mode == "disable" then
        if element._dependHidden then
            Library._setDependHidden(element, false)
        end
        element._dependDisabled = not met
        Library._setDisabled(element, element._frame, element.Disabled)
    else
        if element._dependDisabled then
            element._dependDisabled = false
            Library._setDisabled(element, element._frame, element.Disabled)
        end
        Library._setDependHidden(element, not met)
    end
end

function Library._setDependHidden(element, hidden)
    hidden = hidden == true
    if hidden == (element._dependHidden == true) then
        return
    end
    element._dependHidden = hidden
    if hidden then
        if element._onHide then
            element._onHide()
        end
        if element.Open and type(element.SetOpen) == "function" then
            element:SetOpen(false)
        end
    end
    local frame = element._frame
    if frame then
        frame.Visible = element._userVisible ~= false and not hidden
    end
    if element._window then
        element._window._controlsDirty = true
    end
end

-- Rules are checked ten times a second, so they follow config loads and
-- changes made from code as well as clicks.
function Library._watchDepends(window, element)
    if not window._dependents then
        window._dependents = {}
        local last = 0
        window:_listen("Render", function()
            local now = os.clock()
            if now - last < 0.1 then
                return
            end
            last = now
            local list = window._dependents
            for index = #list, 1, -1 do
                local item = list[index]
                if item._destroyed then
                    table.remove(list, index)
                elseif item._dependsOn ~= nil then
                    Library._applyDepends(item)
                end
            end
        end)
    end
    if not table.find(window._dependents, element) then
        table.insert(window._dependents, element)
    end
    Library._applyDepends(element, true)
end

-- SetDisabled(true) or a DependsOn rule in "Disable" mode dims the element
-- under a cover that swallows clicks; either one keeps it disabled.
function Library._setDisabled(element, frame, disabled)
    element.Disabled = disabled == true
    if not frame then
        return
    end
    local off = element.Disabled or element._dependDisabled == true
    if off == (element._covered == true) then
        return
    end
    element._covered = off
    if off then
        if element._onHide then
            element._onHide()
        end
        if element.Open and type(element.SetOpen) == "function" then
            element:SetOpen(false)
        end
    end
    local cover = element._cover
    if not cover then
        cover = create("TextButton", {
            Name = "DisabledCover",
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            ZIndex = 20,
            Visible = false,
            Parent = frame,
        })
        cover:SetAttribute("NoDrag", true)
        corner(cover)
        element._cover = cover
    end
    element._coverGeneration = (element._coverGeneration or 0) + 1
    local generation = element._coverGeneration
    if off then
        cover.Visible = true
        tween(cover, { BackgroundTransparency = 0.4 }, 0.15)
    else
        tween(cover, { BackgroundTransparency = 1 }, 0.15)
        task.delay(0.16, function()
            if element._coverGeneration == generation then
                cover.Visible = false
            end
        end)
    end
end

-- Confirm = true (or the text to show): the first click arms the button and
-- a second one within ConfirmTimeout seconds runs it. HoldToConfirm = true
-- (one second) or a number of seconds: the button fills while held and runs
-- when full.
function Library._gateButton(tab, opts)
    local real = opts.Callback
    local holdTime = opts.HoldToConfirm == true and 1 or tonumber(opts.HoldToConfirm)
    local gated = table.clone(opts)
    gated._gated = true
    local handle
    local name = tostring(opts.Name or "Button")
    local armed, generation = false, 0
    local function setArmed(value)
        armed = value
        generation += 1
        if not handle then
            return
        end
        handle._title.Text = value and tostring(type(opts.Confirm) == "string" and opts.Confirm or "Click again to confirm") or name
        tween(handle._title, { TextColor3 = value and Theme.Warning or handle._titleColor }, 0.15)
    end
    gated.Callback = function()
        if holdTime then
            return
        end
        if armed then
            setArmed(false)
            safeCall(real)
            return
        end
        setArmed(true)
        local current = generation
        task.delay(tonumber(opts.ConfirmTimeout) or 3, function()
            if armed and generation == current then
                setArmed(false)
            end
        end)
    end
    handle = tab:Button(gated)
    local setText = handle.SetText
    handle.SetText = function(self_, value)
        name = tostring(value)
        if not armed then
            setText(self_, value)
        end
    end
    function handle:Disarm()
        if armed then
            setArmed(false)
        end
    end
    if holdTime then
        local host = handle._fillHost
        local fill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0,
            ZIndex = 0,
            Parent = host,
        })
        local holding = 0
        local function release()
            holding += 1
            tween(fill, { Size = UDim2.fromScale(0, 1) }, 0.2, Enum.EasingStyle.Quint)
        end
        local frame = handle._frame
        frame.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if handle.Disabled or handle._dependDisabled then
                return
            end
            holding += 1
            local current = holding
            fill.Size = UDim2.fromScale(0, 1)
            tween(fill, { Size = UDim2.fromScale(1, 1) }, holdTime, Enum.EasingStyle.Linear)
            task.delay(holdTime, function()
                if holding == current and not handle._destroyed then
                    holding += 1
                    tween(fill, { BackgroundTransparency = 0.45 }, 0.08)
                    task.delay(0.12, function()
                        fill.BackgroundTransparency = 0.7
                        tween(fill, { Size = UDim2.fromScale(0, 1) }, 0.25, Enum.EasingStyle.Quint)
                    end)
                    safeCall(real)
                end
            end)
        end)
        frame.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                release()
            end
        end)
        frame.MouseLeave:Connect(release)
    end
    return handle
end

-- A theme key, a Color3, "#rrggbb" or { r, g, b } as a Color3.
function Library._color(value)
    if type(value) == "string" then
        local key = Library._toneTags[string.lower(value)]
        if key then
            return Theme[key]
        end
    end
    return toColor(value)
end

function Library._rich(text)
    text = tostring(text == nil and "" or text)
    if not string.find(text, "<", 1, true) then
        return text
    end
    return (string.gsub(text, "<(/?)(%a+%d*)>", function(slash, name)
        local key = Library._toneTags[string.lower(name)]
        if not key then
            return nil
        end
        if slash == "/" then
            return "</font>"
        end
        return '<font color="' .. hexOf(Theme[key]) .. '">'
    end))
end

-- Library.Colorize("12 ms", "Success") or Library:Colorize(text, Color3).
function Library.Colorize(...)
    local args = { ... }
    if args[1] == Library then
        table.remove(args, 1)
    end
    local text, color = tostring(args[1] == nil and "" or args[1]), args[2]
    local key = type(color) == "string" and Library._toneTags[string.lower(color)]
    if key then
        return "<" .. key .. ">" .. text .. "</" .. key .. ">"
    end
    local resolved = toColor(color)
    if not resolved then
        return text
    end
    return '<font color="' .. hexOf(resolved) .. '">' .. text .. "</font>"
end

-- The window's corner radius in pixels, 0 (square) to 20; every other
-- rounded corner scales with it. The default is 10. Corners ease to the new
-- radius instead of jumping. Returns the radius it settled on.
function Library:SetCornerRadius(pixels, instant)
    pixels = math.clamp(math.floor((tonumber(pixels) or 10) + 0.5), 0, 20)
    Library.Roundness = pixels / 10
    for object, base in pairs(Library._cornerBases) do
        if not object.Parent then
            Library._cornerBases[object] = nil
        else
            local radius = UDim.new(0, math.floor(base * Library.Roundness + 0.5))
            if instant then
                object.CornerRadius = radius
            else
                tween(object, { CornerRadius = radius }, 0.25, Enum.EasingStyle.Quint)
            end
        end
    end
    return pixels
end

function Library:GetCornerRadius()
    return math.floor(Library.Roundness * 10 + 0.5)
end

function Library:SetTheme(theme, instant)
    if type(theme) == "string" then
        local found = Library.ThemePresets[theme]
        if not found then
            return false
        end
        Library.ThemeName = theme
        theme = found
    elseif type(theme) ~= "table" then
        return false
    end
    local changed = false
    for _, name in ipairs(THEME_KEYS) do
        local color = toColor(theme[name])
        if color and color ~= Theme[name] then
            Theme[name] = color
            changed = true
        end
    end
    if not changed then
        return true
    end
    rebuildThemeLookup()
    sweepBindings()
    driveTheme(instant and 0 or 0.3)
    for owner, fn in pairs(themeHooks) do
        if owner.Parent then
            pcall(fn)
        end
    end
    for _, fn in ipairs(Library._themeListeners) do
        pcall(fn)
    end
    return true
end

function Library:GetTheme()
    local copy = {}
    for _, name in ipairs(THEME_KEYS) do
        copy[name] = Theme[name]
    end
    return copy
end

-- The script's starting theme: a preset name or a colour table. A default the
-- player picked in the theme manager still wins over it.
function Library:SetDefaultTheme(theme)
    Library.DefaultTheme = theme
    if theme == nil then
        return true
    end
    local live = false
    for _, window in ipairs(Library.Windows) do
        if not window._destroyed then
            if window:GetDefaultTheme() then
                return true
            end
            live = true
        end
    end
    return Library:SetTheme(theme, not live)
end

function Library:GetDefaultTheme()
    return Library.DefaultTheme
end

local function themeFolder(self)
    return self.ConfigFolder .. "/themes"
end

function Window:SaveTheme(name)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    if type(name) ~= "string" or name == "" then
        return false, "theme needs a name"
    end
    ensureFolder(self.ConfigFolder)
    ensureFolder(themeFolder(self))
    local data = {}
    for _, key in ipairs(THEME_KEYS) do
        data[key] = hexOf(Theme[key])
    end
    return pcall(function()
        writefile(themeFolder(self) .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
end

function Window:LoadTheme(name, instant)
    if Library.ThemePresets[name] then
        return Library:SetTheme(name, instant)
    end
    local text = readText(themeFolder(self) .. "/" .. tostring(name) .. ".json")
    if not text then
        return false, "no theme named " .. tostring(name)
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        return false, "theme is not valid JSON"
    end
    Library.ThemeName = name
    return Library:SetTheme(data, instant)
end

function Window:DeleteTheme(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end
    local path = themeFolder(self) .. "/" .. tostring(name) .. ".json"
    if not isfile(path) then
        return false, "no theme named " .. tostring(name)
    end
    delfile(path)
    if self:GetDefaultTheme() == name then
        self:SetDefaultTheme(nil)
    end
    return true
end

function Window:ListThemes()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(themeFolder(self)) then
        return names
    end
    for _, path in ipairs(listfiles(themeFolder(self))) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function Window:GetDefaultTheme()
    return readText(themeFolder(self) .. "/default.txt")
end

function Window:SetDefaultTheme(name)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    ensureFolder(self.ConfigFolder)
    ensureFolder(themeFolder(self))
    local path = themeFolder(self) .. "/default.txt"
    if name == nil or name == "" then
        if isfile(path) and type(delfile) == "function" then
            pcall(delfile, path)
        end
        return true
    end
    return pcall(writefile, path, tostring(name))
end

function Window:_applyDefaultTheme()
    local name = self:GetDefaultTheme()
    if name then
        local ok, loaded = pcall(self.LoadTheme, self, name, true)
        if ok and loaded then
            return
        end
    end
    if Library.DefaultTheme ~= nil then
        pcall(Library.SetTheme, Library, Library.DefaultTheme, true)
    end
end

-- Background images

-- Image assets anyone can use, from Fluent-modded's themes.
Library.BackgroundPresets = {
    ["Deep Violet"] = "rbxassetid://136310484943077",
    ["Blood Red"] = "rbxassetid://121343473918667",
    ["Cyanic"] = "rbxassetid://95656189244173",
    ["Amber Glow"] = "rbxassetid://107795771598485",
    ["Bloomings"] = "rbxassetid://133541508207801",
    ["Lavender Pink"] = "rbxassetid://126107479485287",
}
Library.BackgroundPresetOrder = { "Deep Violet", "Blood Red", "Cyanic", "Amber Glow", "Bloomings", "Lavender Pink" }

-- Table fields, not locals: the library chunk is at Luau's 200 local limit.
Library._imageExtensions = { png = true, jpg = true, jpeg = true, webp = true, gif = true, bmp = true }

function Window:_backgroundFolder()
    return self.ConfigFolder .. "/backgrounds"
end

function Window:_trimBackground(source)
    return (tostring(source or ""):match("^%s*(.-)%s*$"))
end

-- Turns a background source into something ImageLabel.Image takes. Web images
-- are downloaded once into backgrounds/cache and loaded with getcustomasset,
-- so this yields the first time a URL is used.
function Window:_resolveBackground(source)
    source = self:_trimBackground(source)
    local preset = Library.BackgroundPresets[source]
    if preset then
        return preset
    end
    if source:match("^%d+$") then
        return "rbxassetid://" .. source
    end
    if source:match("^rbxassetid://%d+") or source:match("^rbxasset://") or source:match("^rbxthumb://")
        or source:match("^https?://www%.roblox%.com/asset") then
        return source
    end
    local canLoad = fileApiAvailable() and typeof(getcustomasset) == "function"
    if source:match("^https?://") then
        if not canLoad then
            return nil, "web images need writefile and getcustomasset"
        end
        local clean = source:match("^[^?#]+") or source
        local ext = (clean:match("%.(%w+)$") or "png"):lower()
        if not Library._imageExtensions[ext] then
            ext = "png"
        end
        local key = (clean:gsub("^https?://", ""):gsub("[^%w]", "_")):sub(-60)
        local folder = self:_backgroundFolder() .. "/cache"
        local path = folder .. "/" .. key .. "_" .. #source .. "." .. ext
        if not isfile(path) then
            local ok, body = pcall(function()
                local request = (syn and syn.request) or http_request or request
                if request then
                    local response = request({ Url = source, Method = "GET" })
                    return response and response.Body
                end
                return game:HttpGet(source, true)
            end)
            if not ok or type(body) ~= "string" or #body < 128 then
                return nil, "could not download the image"
            end
            local head = body:sub(1, 64):lower()
            if head:find("<!doctype") or head:find("<html") then
                return nil, "that link is a web page, not an image"
            end
            ensureFolder(folder)
            if not pcall(writefile, path, body) then
                return nil, "could not save the image"
            end
        end
        local ok, asset = pcall(getcustomasset, path)
        if ok and type(asset) == "string" and asset ~= "" then
            return asset
        end
        pcall(delfile, path)
        return nil, "the downloaded file is not an image"
    end
    -- A file in the backgrounds folder, or any path in the workspace.
    if canLoad then
        for _, path in ipairs({ self:_backgroundFolder() .. "/" .. source, source }) do
            if isfile(path) then
                local ok, asset = pcall(getcustomasset, path)
                if ok and type(asset) == "string" and asset ~= "" then
                    return asset
                end
                return nil, "could not load " .. source
            end
        end
    end
    return nil, "no image called " .. source
end

-- source: a preset name, an image asset id, an rbxassetid:// link, an http(s)
-- image URL, or an image file in <ConfigFolder>/backgrounds. nil or "None"
-- removes it. May yield while a web image downloads.
function Window:SetBackground(source)
    self._backgroundGeneration += 1
    local generation = self._backgroundGeneration
    local image = self._backgroundImage
    source = source ~= false and self:_trimBackground(source) or ""
    if source == "" or source == "None" then
        self.Background = nil
        tween(image, { ImageTransparency = 1 }, 0.25)
        task.delay(0.25, function()
            if self._backgroundGeneration == generation then
                image.Visible = false
                image.Image = ""
            end
        end)
        self:SetTransparent(self.Transparent)
        return true
    end
    local asset, err = self:_resolveBackground(source)
    if self._backgroundGeneration ~= generation or self._destroyed then
        return false, "replaced by a newer background"
    end
    if not asset then
        return false, err
    end
    self.Background = source
    image.Image = asset
    image.Visible = true
    tween(image, { ImageTransparency = self.BackgroundTransparency }, 0.3)
    self:SetTransparent(self.Transparent)
    return true
end

function Window:GetBackground()
    return self.Background
end

-- 0 shows the image fully, 1 hides it behind the theme background colour.
function Window:SetBackgroundTransparency(value)
    self.BackgroundTransparency = math.clamp(tonumber(value) or 0.35, 0, 1)
    if self.Background then
        tween(self._backgroundImage, { ImageTransparency = self.BackgroundTransparency }, 0.15)
    end
end

-- Preset names, then the image files in <ConfigFolder>/backgrounds.
function Window:ListBackgrounds()
    local names = table.clone(Library.BackgroundPresetOrder)
    local folder = self:_backgroundFolder()
    if type(listfiles) == "function" and type(isfolder) == "function" and isfolder(folder) then
        local files = {}
        for _, path in ipairs(listfiles(folder)) do
            local name = path:match("([^/\]+)$")
            local ext = name and name:match("%.(%w+)$")
            if ext and Library._imageExtensions[ext:lower()] then
                table.insert(files, name)
            end
        end
        table.sort(files)
        for _, name in ipairs(files) do
            table.insert(names, name)
        end
    end
    return names
end

local function emptyState(parent, icon, text)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, -10),
        Size = UDim2.fromOffset(200, 70),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 0.15,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, icon)
    local caption = label({
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.new(1, 0, 0, 16),
        Text = text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })
    return holder, caption, image
end

local function fadeSlideIn(group, restY)
    restY = restY or 0
    group.GroupTransparency = 1
    group.Position = UDim2.fromOffset(0, restY + 14)
    group.Visible = true
    tween(group, { GroupTransparency = 0, Position = UDim2.fromOffset(0, restY) }, 0.32, Enum.EasingStyle.Quint)
end

local function formatDuration(seconds)
    seconds = math.max(math.floor(seconds), 0)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor(seconds / 60) % 60
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds % 60)
    end
    return string.format("%ds", seconds)
end

local function shortId(id)
    if type(id) ~= "string" or id == "" then
        return "Studio"
    end
    if #id > 16 then
        return id:sub(1, 8) .. "..." .. id:sub(-4)
    end
    return id
end

local function copyToClipboard(text)
    local setter = setclipboard or toclipboard or (Clipboard and Clipboard.set)
    if type(setter) ~= "function" then
        return false
    end
    return (pcall(setter, tostring(text)))
end

local function fetchServers(order)
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullGames=true",
        game.PlaceId,
        order
    )
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok or type(body) ~= "string" then
        return nil
    end
    local decoded, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil
    end
    return data.data
end

-- Small on/off pill used on the home card for the privacy switches.
local function miniSwitch(parent, initial, order, callback)
    local pill = create("TextButton", {
        Size = UDim2.fromOffset(30, 16),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill)
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = pill,
    })
    corner(knob, UDim.new(1, 0))
    local on = initial == true
    local function render(animate)
        local duration = animate and 0.22 or 0
        tween(pill, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
        tween(knob, {
            Position = on and UDim2.new(0, 16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
            BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
        }, duration, Enum.EasingStyle.Back)
    end
    pill.MouseButton1Click:Connect(function()
        on = not on
        render(true)
        safeCall(callback, on)
    end)
    render(false)
    return pill
end

local function softButton(parent, text, props, callback)
    local button = create("TextButton", {
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = parent,
    })
    for key, value in pairs(props) do
        button[key] = value
    end
    corner(button, UDim.new(0, 6))
    local buttonStroke = stroke(button)
    local text_ = label({
        Size = UDim2.fromScale(1, 1),
        Text = text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })
    if button.AutomaticSize == Enum.AutomaticSize.X then
        text_.Size = UDim2.new(0, 0, 1, 0)
        text_.AutomaticSize = Enum.AutomaticSize.X
        text_.TextTruncate = Enum.TextTruncate.None
        padding(button, 14, 14)
    end
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0.15 }, 0.12)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.45 }, 0.25)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(callback)
    end)
    return button, text_
end

local function panelCard(parent, height, order)
    local frame = create("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = parent,
    })
    frame:SetAttribute("NoDrag", true)
    corner(frame, UDim.new(0, 10))
    stroke(frame)
    return frame
end

local STAT_TYPES = {
    Players = { "users", "Players" },
    Friends = { "user-check", "Friends" },
    Execs = { "zap", "Execs" },
    Session = { "timer", "Session" },
    Uptime = { "timer", "Session" },
    FPS = { "gauge", "FPS" },
    Ping = { "wifi", "Ping" },
    Executor = { "terminal", "Executor" },
    Game = { "gamepad-2", "Game" },
    Region = { "globe", "Region" },
    Time = { "clock", "Time" },
    ServerAge = { "server", "Server age" },
    Memory = { "cpu", "Memory" },
}

-- Health colour for a live metric: Success under good, Warning under bad,
-- Error past it. lowerIsBetter flips the scale (ping, memory).
function Library._healthColor(value, good, bad, lowerIsBetter)
    if type(value) ~= "number" then
        return Theme.Text
    end
    if lowerIsBetter then
        return value <= good and Theme.Success or value <= bad and Theme.Warning or Theme.Error
    end
    return value >= good and Theme.Success or value >= bad and Theme.Warning or Theme.Error
end

local function bumpExecutions(folder)
    if not fileApiAvailable() then
        return nil
    end
    local path = folder .. "/executions.txt"
    local count = 0
    pcall(function()
        ensureFolder(folder)
        if isfile(path) then
            count = tonumber(readfile(path)) or 0
        end
    end)
    count += 1
    pcall(writefile, path, tostring(count))
    return count
end

-- Containers: a tab or sub tab owns a scrolling list. Elements added straight
-- to it stack full width, groupboxes go into two columns underneath.

local function buildContainer(owner, parent, top, emptyIcon, emptyText)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, top),
        Size = UDim2.new(1, 0, 1, -top),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.5,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = parent,
    })
    Library._space(padding(list, 24, 24, 2, 24), { 24, 24, 2, 24 })
    Library._space(create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = list,
    }), 8)
    owner.List = list
    owner._items = {}
    owner._groupboxes = {}
    owner._childCount = 0
    owner._emptyText = emptyText
    owner._empty, owner._emptyCaption = emptyState(parent, emptyIcon, emptyText)
    list.ChildAdded:Connect(function(child)
        if child:IsA("GuiObject") then
            owner._childCount += 1
            owner:_refreshEmpty()
        end
    end)
    list.ChildRemoved:Connect(function(child)
        if child:IsA("GuiObject") then
            owner._childCount = math.max(owner._childCount - 1, 0)
            owner:_refreshEmpty()
        end
    end)
    owner:_refreshEmpty()
    return list
end

function Tab:_refreshEmpty()
    local empty = self._empty
    if not empty then
        return
    end
    if self._subTabs then
        empty.Visible = false
    else
        empty.Visible = self._childCount == 0
    end
end

function Tab:_columns()
    if self._columnSet then
        return self._columnSet
    end
    local holder = create("Frame", {
        Name = "Columns",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 100000,
        Parent = self.List,
    })
    local layout = Library._space(create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = holder,
    }), 10)
    local function column(order)
        local frame = create("Frame", {
            Size = UDim2.new(0.5, -5, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = holder,
        })
        Library._space(create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            Parent = frame,
        }), 10)
        return frame
    end
    local set = { Holder = holder, Left = column(1), Right = column(2), Counts = { 0, 0 }, Stacked = false }
    local window = self.Window
    -- Narrow windows stack the right column under the left one.
    local function relayout()
        local width = holder.AbsoluteSize.X / window.Scale.Scale
        if width <= 0 then
            return
        end
        local stacked = width < STACK_BELOW
        local gap = layout.Padding.Offset
        if stacked == set.Stacked and gap == set.Gap then
            return
        end
        set.Stacked = stacked
        set.Gap = gap
        layout.FillDirection = stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
        local size = stacked and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -gap / 2, 0, 0)
        set.Left.Size = size
        set.Right.Size = size
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
    layout:GetPropertyChangedSignal("Padding"):Connect(relayout)
    task.defer(relayout)
    self._columnSet = set
    return set
end

function Tab:Groupbox(opts, icon)
    if self._groupbox then
        return self.Parent:Groupbox(opts, icon)
    end
    opts = normalize(opts, { Title = "Name" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = icon
    end
    local window = self.Window
    local set = self:_columns()
    local side = opts.Side
    if side == "Left" or side == 1 then
        side = 1
    elseif side == "Right" or side == 2 then
        side = 2
    else
        side = set.Counts[1] <= set.Counts[2] and 1 or 2
    end
    set.Counts[side] += 1

    local box = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = set.Counts[side],
        Parent = side == 1 and set.Left or set.Right,
    })
    box:SetAttribute("NoDrag", true)
    corner(box, UDim.new(0, 10))
    stroke(box)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = box,
    })

    -- The header is a filled strip: icon and bold title on the left, a
    -- chevron on the right. Pressing anywhere on it folds the box.
    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = 1,
        Parent = box,
    })
    corner(header, UDim.new(0, 10))
    -- Squares the strip's lower corners so it meets the body flat.
    local headerFill = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = header,
    })
    local titleX = 14
    if opts.Icon then
        local headerIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 2,
            Parent = header,
        })
        applyIcon(headerIcon, opts.Icon)
        titleX = 37
    end
    local collapseButton = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 2,
        Parent = header,
    })
    applyIcon(collapseButton, "chevron-down")
    -- Beside the chevron, a button that pops the box out into a floating
    -- panel (and docks it back once it's out). PopOut = false leaves it off.
    local canPop = opts.PopOut ~= false
    local popButton, popIcon
    if canPop then
        popButton = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -34, 0.5, 0),
            Size = UDim2.fromOffset(24, 24),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
            Parent = header,
        })
        corner(popButton, UDim.new(0, 6))
        popIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(13, 13),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ImageTransparency = TOUCH and 0 or 0.45,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 3,
            Parent = popButton,
        })
        applyIcon(popIcon, "picture-in-picture-2")
    end
    local title = label({
        Position = UDim2.fromOffset(titleX, 0),
        Size = UDim2.new(1, -(titleX + (canPop and 66 or 40)), 1, 0),
        Text = opts.Name or "Groupbox",
        TextSize = 13,
        FontFace = Fonts.Bold,
        ZIndex = 2,
        Parent = header,
    })

    local rule = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = box,
    })
    local body = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        LayoutOrder = 3,
        Parent = box,
    })
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = body,
    })
    Library._space(padding(inner, 0, 0, 6, 8), { 0, 0, 6, 8 })
    Library._space(create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = inner,
    }), 2)

    local group = setmetatable({
        Name = opts.Name or "Groupbox",
        Window = window,
        Parent = self,
        List = inner,
        Frame = box,
        _frame = box,
        _order = 0,
        _groupbox = true,
        _metrics = METRICS.Row,
        _items = {},
    }, Tab)
    table.insert(self._groupboxes, group)
    -- A groupbox named "Menu" gets the built-in "Minimize UI on Start" toggle,
    -- so existing scripts pick it up without calling CreateMinimizeOnStart.
    -- It lands above the first button (usually Unload), or at the end.
    if type(group.Name) == "string" and string.lower(group.Name:match("^%s*(.-)%s*$")) == "menu" then
        task.defer(function()
            if window._destroyed or window._minimizeOnStartToggle or not box.Parent then
                return
            end
            local toggle = group:CreateMinimizeOnStart()
            local frame = toggle and toggle._frame
            if not frame then
                return
            end
            local before
            for _, element in ipairs(group._items) do
                local other = element._frame
                if element._type == "Button" and other and other.Parent == frame.Parent
                    and (not before or other.LayoutOrder < before.LayoutOrder) then
                    before = other
                end
            end
            if before then
                local order = before.LayoutOrder
                for _, child in ipairs(frame.Parent:GetChildren()) do
                    if child:IsA("GuiObject") and child ~= frame and child.LayoutOrder >= order then
                        child.LayoutOrder += 1
                    end
                end
                frame.LayoutOrder = order
                group._order += 1
            end
        end)
    end

    local collapsed = false
    local generation = 0
    local function setCollapsed(value, instant)
        value = value == true
        if value == collapsed then
            return
        end
        collapsed = value
        generation += 1
        local current = generation
        local duration = instant and 0 or 0.32
        -- Anything open inside the box (a dropdown list, a picker, a focused
        -- box) closes with it, rather than floating over a folded header.
        if value then
            for _, element in ipairs(group._items) do
                if element._onHide then
                    element._onHide()
                end
                if element.Open and type(element.SetOpen) == "function" then
                    element:SetOpen(false)
                end
            end
        end
        window._controlsDirty = true
        local scale = window.Scale.Scale
        if value then
            body.AutomaticSize = Enum.AutomaticSize.None
            body.Size = UDim2.new(1, 0, 0, body.AbsoluteSize.Y / scale)
            tween(body, { Size = UDim2.new(1, 0, 0, 0) }, duration, Enum.EasingStyle.Quint)
        else
            tween(body, { Size = UDim2.new(1, 0, 0, inner.AbsoluteSize.Y / scale) }, duration, Enum.EasingStyle.Quint)
            local function settle()
                if generation == current and not collapsed then
                    body.AutomaticSize = Enum.AutomaticSize.Y
                    body.Size = UDim2.new(1, 0, 0, 0)
                end
            end
            if duration > 0 then
                task.delay(duration, settle)
            else
                settle()
            end
        end
        local motion = instant and 0 or 0.3
        -- Folded, the strip is the whole box: the hairline under it drops out
        -- of the layout once the body has closed, so the box ends exactly at
        -- the strip and both share the same rounded corners.
        if value then
            local function fold()
                if generation == current and collapsed then
                    rule.Visible = false
                    headerFill.Visible = false
                end
            end
            if duration > 0 then
                task.delay(duration, fold)
            else
                fold()
            end
        else
            rule.Visible = true
            headerFill.Visible = true
        end
        tween(collapseButton, { Rotation = value and -90 or 0 }, motion, Enum.EasingStyle.Quint)
    end

    local function hover(on)
        local duration = on and 0.15 or 0.25
        tween(collapseButton, { ImageColor3 = on and Theme.Text or Theme.Muted }, duration)
        if popIcon and not TOUCH then
            tween(popIcon, { ImageTransparency = on and 0 or 0.45 }, duration)
        end
    end
    header.MouseEnter:Connect(function()
        hover(true)
    end)
    header.MouseLeave:Connect(function()
        hover(false)
    end)
    local isTap = tapGuard(header, function()
        return box:FindFirstAncestorWhichIsA("ScrollingFrame")
    end)
    -- Popping out: the box itself is lifted out of its column into a panel
    -- on the window's pop-out layer, and a slot holds its place in the column
    -- (pressing the slot docks it back). The header drags the panel; a drop
    -- is clamped on screen and the spot is remembered for the next pop-out.
    local popped, popGeneration = false, 0
    local panel, panelScale, panelShadow, slot, stopPanel
    local dragStart, dragOrigin, dragMoved, suppressClick = nil, nil, false, false
    -- PC only: dragging a docked header pops it out under the cursor.
    local pendingPop
    -- The panel's bottom-right grip resizes it; a set height scrolls the box.
    local resizeStart, resizeOrigin, resizeHeight
    local MIN_POP_WIDTH, MIN_POP_HEIGHT = 200, 80
    local animating = false

    local function layerScale()
        return math.max(window.Scale.Scale, 0.05)
    end
    local function toLayer(point)
        return (point - window._popLayer.AbsolutePosition) / layerScale()
    end
    -- Keeps a panel's top-centre spot on screen, header always reachable.
    local function clampSpot(spot, width, height)
        local view = window._popLayer.AbsoluteSize / layerScale()
        local margin = 8
        local x = math.clamp(spot.X, width / 2 + margin, math.max(view.X - width / 2 - margin, width / 2 + margin))
        local y = math.clamp(spot.Y, margin, math.max(view.Y - math.min(height, 120) - margin, margin))
        return Vector2.new(x, y)
    end
    local function closeInner()
        for _, element in ipairs(group._items) do
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
    end
    local function setPopIcon(out)
        if popIcon then
            applyIcon(popIcon, out and "minimize-2" or "picture-in-picture-2")
        end
    end

    local finishPop
    local function popOut(fromDrag)
        if popped or not canPop or not box.Parent or group._destroyed then
            return
        end
        -- A dock still in flight lands first, so the box is back in its column.
        if group._settleDock then
            group._settleDock()
        end
        local layer = window:_popoutLayer()
        popped = true
        group._popped = true
        popGeneration += 1
        local current = popGeneration
        closeInner()
        window:_closePopups()
        local scale = layerScale()
        local column = box.Parent
        local from = toLayer(box.AbsolutePosition)
        local width = box.AbsoluteSize.X / scale
        local height = box.AbsoluteSize.Y / scale

        -- The slot left behind: starts at the box's height so nothing below
        -- jumps, then eases down to a slim bar.
        slot = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = box.LayoutOrder,
            Parent = column,
        })
        slot:SetAttribute("NoDrag", true)
        corner(slot, UDim.new(0, 10))
        stroke(slot, Theme.Stroke, 1).Transparency = 0.3
        local slotLabel = label({
            Size = UDim2.new(1, -24, 0, 40),
            Position = UDim2.fromOffset(12, 0),
            Text = Library._rich(group.Name) .. '<font transparency="0.4">  ·  popped out, click to dock</font>',
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            RichText = true,
            TextTransparency = 1,
            Parent = slot,
        })
        local thisSlot = slot
        slot.MouseEnter:Connect(function()
            tween(thisSlot, { BackgroundTransparency = 0.35 }, 0.15)
        end)
        slot.MouseLeave:Connect(function()
            tween(thisSlot, { BackgroundTransparency = 0.6 }, 0.25)
        end)
        slot.MouseButton1Click:Connect(function()
            if slot == thisSlot then
                group:Dock()
            end
        end)
        tween(slot, { Size = UDim2.new(1, 0, 0, 40) }, 0.42, Enum.EasingStyle.Quint)
        tween(slotLabel, { TextTransparency = 0 }, 0.3)
        slot.Visible = box.Visible

        panel = create("Frame", {
            Name = "PopOut",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(from.X + width / 2, from.Y),
            Size = UDim2.fromOffset(width, height),
            BackgroundTransparency = 1,
            Parent = layer,
        })
        panel:SetAttribute("NoDrag", true)
        panelScale = create("UIScale", { Parent = panel })
        panelShadow = create("ImageLabel", {
            Position = UDim2.fromOffset(-24, -18),
            Size = UDim2.new(1, 48, 1, 44),
            BackgroundTransparency = 1,
            Image = Assets.Shadow,
            ImageColor3 = Color3.new(0, 0, 0),
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(49, 49, 450, 450),
            ZIndex = 0,
            Parent = panel,
        })
        -- The box sits in a scroller, so a panel resized shorter than the
        -- box still reaches every row.
        local holder = create("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Muted,
            VerticalScrollBarInset = Enum.ScrollBarInset.None,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            ZIndex = 1,
            Parent = panel,
        })
        holder:SetAttribute("NoDrag", true)
        -- Edges and corners all resize: each handle carries the sides it
        -- moves (-1 left/top, 1 right/bottom, 0 untouched).
        local edge = TOUCH and 12 or 7
        local handles = {
            { -1, -1 }, { 0, -1 }, { 1, -1 },
            { -1, 0 }, { 1, 0 },
            { -1, 1 }, { 0, 1 }, { 1, 1 },
        }
        local gripIcon
        for _, dir in ipairs(handles) do
            local dx, dy = dir[1], dir[2]
            local handle = create("TextButton", {
                AnchorPoint = Vector2.new((dx + 1) / 2, (dy + 1) / 2),
                Position = UDim2.new((dx + 1) / 2, dx * edge / 2, (dy + 1) / 2, dy * edge / 2),
                Size = UDim2.new(dx == 0 and 1 or 0, dx == 0 and -edge * 2 or edge * 2, dy == 0 and 1 or 0, dy == 0 and -edge * 2 or edge * 2),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                ZIndex = (dx ~= 0 and dy ~= 0) and 21 or 20,
                Parent = panel,
            })
            handle:SetAttribute("NoDrag", true)
            if dx == 1 and dy == 1 then
                gripIcon = create("ImageLabel", {
                    AnchorPoint = Vector2.new(1, 1),
                    Position = UDim2.new(1, -edge - 2, 1, -edge - 2),
                    Size = UDim2.fromOffset(11, 11),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ImageTransparency = 0.35,
                    Rotation = 90,
                    ScaleType = Enum.ScaleType.Fit,
                    ZIndex = 21,
                    Parent = handle,
                })
                applyIcon(gripIcon, "move-diagonal-2")
            end
            handle.MouseEnter:Connect(function()
                tween(gripIcon, { ImageColor3 = Theme.Text, ImageTransparency = 0 }, 0.15)
            end)
            handle.MouseLeave:Connect(function()
                tween(gripIcon, { ImageColor3 = Theme.Muted, ImageTransparency = 0.35 }, 0.25)
            end)
            handle.InputBegan:Connect(function(input)
                if not popped or not isPress(input) or not panel then
                    return
                end
                local w, h = panel.Size.X.Offset, panel.Size.Y.Offset
                local left = panel.Position.X.Offset - w / 2
                local top = panel.Position.Y.Offset
                resizeStart = Vector2.new(input.Position.X, input.Position.Y)
                resizeOrigin = { left, top, left + w, top + h, dx, dy }
                animating = false
                closeInner()
                window:_closePopups()
            end)
        end
        table.insert(window._popPanels, panel)
        box.Parent = holder
        if group._popWidth then
            width = math.max(group._popWidth, MIN_POP_WIDTH)
            panel.Size = UDim2.fromOffset(width, height)
        end
        resizeHeight = group._popHeight
        window._controlsDirty = true
        setPopIcon(true)

        -- Lifts off the column: a spring up and out to its float spot, with
        -- the shadow deepening under it.
        if fromDrag then
            -- Picked up by a drag: no flight, it stays under the cursor.
            panelScale.Scale = 1.025
            panelShadow.ImageTransparency = 0.15
            finishPop(current)
            return
        end
        local spot = clampSpot(group._popSpot or Vector2.new(from.X + width / 2 + 22, from.Y - 14), width, height)
        animating = true
        panelScale.Scale = 0.97
        tween(panel, { Position = UDim2.fromOffset(spot.X, spot.Y) }, 0.5, Enum.EasingStyle.Quint)
        tween(panelScale, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
        tween(panelShadow, { ImageTransparency = 0.35 }, 0.4)
        finishPop(current)
    end

    function finishPop(current)
        task.delay(0.5, function()
            if popGeneration == current then
                animating = false
            end
        end)

        -- Each frame: the panel follows the box's height (folding, rows
        -- coming and going), mirrors its visibility, and stays on screen.
        local thisPanel = panel
        stopPanel = window:_listen("Render", function()
            if panel ~= thisPanel or not thisPanel.Parent then
                return
            end
            -- A set height is the panel's height: a taller box scrolls in it,
            -- a shorter one stretches to fill it (unless folded).
            local fixed = not collapsed and resizeHeight or nil
            local minSize = UDim2.new(1, 0, 0, fixed or 0)
            if box.Size ~= minSize then
                box.Size = minSize
            end
            local boxHeight = box.AbsoluteSize.Y / layerScale()
            local panelHeight = fixed or boxHeight
            if not resizeStart and math.abs(thisPanel.Size.Y.Offset - panelHeight) > 0.5 then
                thisPanel.Size = UDim2.fromOffset(thisPanel.Size.X.Offset, panelHeight)
            end
            thisPanel.Visible = box.Visible
            if slot then
                slot.Visible = box.Visible
            end
            if not animating and not dragStart and not resizeStart then
                local position = Vector2.new(thisPanel.Position.X.Offset, thisPanel.Position.Y.Offset)
                local clamped = clampSpot(position, thisPanel.Size.X.Offset, panelHeight)
                if (clamped - position).Magnitude > 0.5 then
                    thisPanel.Position = UDim2.fromOffset(clamped.X, clamped.Y)
                end
            end
        end)
    end

    local function dock(instant)
        if not popped then
            return
        end
        popped = false
        group._popped = false
        popGeneration += 1
        dragStart, dragMoved, suppressClick = nil, false, false
        resizeStart, pendingPop = nil, nil
        box.Size = UDim2.new(1, 0, 0, 0)
        closeInner()
        window:_closePopups()
        local oldPanel, oldSlot, oldStop, oldScale, oldShadow = panel, slot, stopPanel, panelScale, panelShadow
        panel, slot, stopPanel = nil, nil, nil
        setPopIcon(false)
        group._popSpot = Vector2.new(oldPanel.Position.X.Offset, oldPanel.Position.Y.Offset)
        local settled = false
        local function settle()
            if settled then
                return
            end
            settled = true
            if group._settleDock == settle then
                group._settleDock = nil
            end
            if oldStop then
                oldStop()
            end
            local index = table.find(window._popPanels, oldPanel)
            if index then
                table.remove(window._popPanels, index)
            end
            -- Back into the column, unless it was popped again meanwhile.
            if box:IsDescendantOf(oldPanel) then
                if oldSlot and oldSlot.Parent and not group._destroyed then
                    box.Parent = oldSlot.Parent
                    box.LayoutOrder = oldSlot.LayoutOrder
                end
            end
            if oldSlot then
                oldSlot:Destroy()
            end
            if not box:IsDescendantOf(oldPanel) then
                oldPanel:Destroy()
            end
            animating = false
            window._controlsDirty = true
        end
        group._settleDock = settle
        -- Flies home only when its slot is on screen; otherwise (another tab,
        -- the window hidden) it just drops back into place.
        local canFly = not instant and oldSlot and oldSlot.Parent and window.Root.Visible and box.Visible
            and oldSlot.AbsoluteSize.X > 0 and isShown(oldSlot, window.Body, oldSlot.AbsolutePosition + oldSlot.AbsoluteSize / 2)
        if not canFly then
            settle()
            return
        end
        animating = true
        local scale = layerScale()
        local height = box.AbsoluteSize.Y / scale
        local width = oldSlot.AbsoluteSize.X / scale
        tween(oldSlot, { Size = UDim2.new(1, 0, 0, height) }, 0.36, Enum.EasingStyle.Quint)
        local oldLabel = oldSlot:FindFirstChildWhichIsA("TextLabel")
        if oldLabel then
            tween(oldLabel, { TextTransparency = 1 }, 0.12)
        end
        -- The slot's top stays put as it grows, so its spot is the landing.
        local target = toLayer(oldSlot.AbsolutePosition)
        tween(oldPanel, {
            Position = UDim2.fromOffset(target.X + width / 2, target.Y),
            Size = UDim2.fromOffset(width, height),
        }, 0.36, Enum.EasingStyle.Quint)
        tween(oldScale, { Scale = 1 }, 0.2)
        tween(oldShadow, { ImageTransparency = 1 }, 0.3)
        task.delay(0.37, settle)
    end

    -- Dragging the floating panel by its header.
    header.InputBegan:Connect(function(input)
        if not popped and canPop and not TOUCH and isPress(input) then
            pendingPop = Vector2.new(input.Position.X, input.Position.Y)
            return
        end
        if not popped or not isPress(input) or not panel then
            return
        end
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        dragOrigin = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        dragMoved = false
        suppressClick = false
    end)
    window:_listen("Changed", function(input)
        if not isMove(input) then
            return
        end
        if resizeStart and panel then
            local delta = (Vector2.new(input.Position.X, input.Position.Y) - resizeStart) / layerScale()
            local view = window._popLayer.AbsoluteSize / layerScale()
            local boxHeight = box.AbsoluteSize.Y / layerScale()
            local left, top, right, bottom, dx, dy = table.unpack(resizeOrigin)
            local maxWidth = math.max(view.X - 16, MIN_POP_WIDTH)
            local minHeight = MIN_POP_HEIGHT
            local maxHeight = math.max(view.Y - 16, MIN_POP_HEIGHT)
            -- The dragged side moves; the opposite one stays put.
            if dx == 1 then
                right = left + math.clamp(right - left + delta.X, MIN_POP_WIDTH, maxWidth)
            elseif dx == -1 then
                left = right - math.clamp(right - left - delta.X, MIN_POP_WIDTH, maxWidth)
            end
            if dy == 1 then
                bottom = top + math.clamp(bottom - top + delta.Y, minHeight, maxHeight)
            elseif dy == -1 then
                top = bottom - math.clamp(bottom - top - delta.Y, minHeight, maxHeight)
            end
            local newHeight = bottom - top
            if dy ~= 0 then
                resizeHeight = newHeight
            end
            panel.Size = UDim2.fromOffset(right - left, newHeight)
            panel.Position = UDim2.fromOffset((left + right) / 2, top)
            window._controlsDirty = true
            return
        end
        if pendingPop and not popped then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - pendingPop
            if delta.Magnitude < 2 then
                return
            end
            local start = pendingPop
            pendingPop = nil
            window:_popoutLayer()
            local origin = toLayer(box.AbsolutePosition) + Vector2.new(box.AbsoluteSize.X / layerScale() / 2, 0)
            popOut(true)
            if not popped or not panel then
                return
            end
            dragStart, dragOrigin = start, origin
            dragMoved, suppressClick = true, true
            animating = false
        end
        if not dragStart or not panel then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if not dragMoved then
            if delta.Magnitude < (TOUCH and 8 or 5) then
                return
            end
            dragMoved, suppressClick = true, true
            animating = false
            closeInner()
            window:_closePopups()
            tween(panelScale, { Scale = 1.025 }, 0.18, Enum.EasingStyle.Quint)
            tween(panelShadow, { ImageTransparency = 0.15 }, 0.18)
        end
        local spot = clampSpot(dragOrigin + delta / layerScale(), panel.Size.X.Offset, panel.Size.Y.Offset)
        panel.Position = UDim2.fromOffset(spot.X, spot.Y)
    end, group)
    window:_listen("Ended", function(input)
        if not isPress(input) then
            return
        end
        pendingPop = nil
        if resizeStart then
            resizeStart = nil
            if panel then
                group._popWidth = panel.Size.X.Offset
                group._popHeight = resizeHeight
                group._popSpot = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
            end
        end
        if not dragStart then
            return
        end
        dragStart = nil
        if dragMoved and panel then
            dragMoved = false
            tween(panelScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            tween(panelShadow, { ImageTransparency = 0.35 }, 0.3)
            group._popSpot = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        end
    end, group)
    if popButton then
        popButton.MouseEnter:Connect(function()
            tween(popButton, { BackgroundTransparency = 0 }, 0.15)
            tween(popIcon, { ImageColor3 = Theme.Text }, 0.15)
        end)
        popButton.MouseLeave:Connect(function()
            tween(popButton, { BackgroundTransparency = 1 }, 0.25)
            tween(popIcon, { ImageColor3 = Theme.Muted }, 0.25)
        end)
        popButton.MouseButton1Click:Connect(function()
            if popped then
                dock()
            else
                popOut()
            end
        end)
    end

    header.MouseButton1Click:Connect(function()
        if suppressClick then
            suppressClick = false
            return
        end
        if isTap() then
            setCollapsed(not collapsed)
        end
    end)

    function group:PopOut()
        popOut()
    end
    function group:Dock()
        dock()
    end
    function group:IsPoppedOut()
        return popped
    end
    function group:SetCollapsed(value)
        setCollapsed(value)
    end
    function group:Collapse()
        setCollapsed(true)
    end
    function group:Expand()
        setCollapsed(false)
    end
    function group:IsCollapsed()
        return collapsed
    end
    function group:SetTitle(text)
        group.Name = tostring(text)
        title.Text = group.Name
    end
    group._userVisible = opts.Visible ~= false
    function group:IsVisible()
        return group._userVisible
    end
    function group:SetVisible(visible)
        visible = visible and true or false
        if visible == group._userVisible then
            return
        end
        group._userVisible = visible
        if not visible then
            for _, element in ipairs(group._items) do
                if element._onHide then
                    element._onHide()
                end
                if element.Open and type(element.SetOpen) == "function" then
                    element:SetOpen(false)
                end
            end
        end
        box.Visible = visible
        window._controlsDirty = true
    end
    if not group._userVisible then
        box.Visible = false
    end
    function group:Destroy()
        for index = #group._items, 1, -1 do
            local element = group._items[index]
            if type(element.Destroy) == "function" then
                element:Destroy()
            end
        end
        local owner = group.Parent
        local index = table.find(owner._groupboxes, group)
        if index then
            table.remove(owner._groupboxes, index)
        end
        set.Counts[side] = math.max(set.Counts[side] - 1, 0)
        dock(true)
        group._destroyed = true
        window._controlsDirty = true
        box:Destroy()
    end

    if opts.Collapsed then
        setCollapsed(true, true)
    end
    if opts.PoppedOut then
        task.defer(popOut)
    end
    return group
end

local function sideGroupbox(side)
    return function(self, opts, icon)
        opts = normalize(opts, { Title = "Name" })
        opts.Side = side
        return self:Groupbox(opts, icon)
    end
end

-- Built-in "Minimize UI on Start" toggle; not a config flag, it saves itself.
function Tab:CreateMinimizeOnStart(opts)
    opts = opts or {}
    local window = self.Window
    if window._minimizeOnStartToggle then
        return window._minimizeOnStartToggle
    end
    window._minimizeOnStartToggle = self:CreateToggle({
        Name = opts.Name or "Minimize UI on Start",
        CurrentValue = window:GetMinimizeOnStart(),
        Callback = function(value)
            window:SetMinimizeOnStart(value)
        end,
    })
    return window._minimizeOnStartToggle
end

Tab.CreateGroupbox = Tab.Groupbox
Tab.AddGroupbox = Tab.Groupbox
Tab.AddLeftGroupbox = sideGroupbox("Left")
Tab.AddRightGroupbox = sideGroupbox("Right")

-- Tabboxes: a groupbox whose header is a row of tabs. Each tab is its own
-- page of rows and only the selected one shows (Obsidian's AddLeftTabbox).
function Tab:Tabbox(opts)
    if self._groupbox then
        return self.Parent:Tabbox(opts)
    end
    opts = normalize(opts, { Title = "Name" })
    local owner = self
    local window = self.Window
    local set = self:_columns()
    local side = opts.Side
    if side == "Left" or side == 1 then
        side = 1
    elseif side == "Right" or side == 2 then
        side = 2
    else
        side = set.Counts[1] <= set.Counts[2] and 1 or 2
    end
    set.Counts[side] += 1

    local box = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = set.Counts[side],
        Parent = side == 1 and set.Left or set.Right,
    })
    box:SetAttribute("NoDrag", true)
    corner(box, UDim.new(0, 10))
    stroke(box)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = box,
    })
    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        LayoutOrder = 1,
        Parent = box,
    })
    corner(header, UDim.new(0, 10))
    create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = header,
    })
    local strip = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = header,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = strip,
    })
    create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = box,
    })
    local body = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        LayoutOrder = 3,
        Parent = box,
    })

    local tabbox = {
        Name = opts.Name or "Tabbox",
        Window = window,
        Parent = owner,
        Frame = box,
        Tabs = {},
        _frame = box,
        _userVisible = opts.Visible ~= false,
    }

    local function closeOpen(page)
        for _, element in ipairs(page._items) do
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
    end

    -- Buttons share the strip evenly; the selected one takes the body's fill
    -- and an accent underline, so it reads as joined to the page below.
    local function relayoutButtons()
        local count = math.max(#tabbox.Tabs, 1)
        for _, page in ipairs(tabbox.Tabs) do
            page._button.Size = UDim2.new(1 / count, 0, 1, 0)
        end
    end
    local function paint(page, instant)
        local on = tabbox.Current == page
        local duration = instant and 0 or 0.2
        tween(page._button, { BackgroundTransparency = on and 0 or 1 }, duration)
        tween(page._label, { TextColor3 = on and Theme.Text or Theme.Muted }, duration)
        tween(page._bar, { BackgroundTransparency = on and 0 or 1 }, duration)
        if page._icon then
            tween(page._icon, { ImageColor3 = on and Theme.Accent or Theme.Muted }, duration)
        end
    end

    function tabbox:SelectTab(page)
        if type(page) == "string" or type(page) == "number" then
            local found
            for index, other in ipairs(tabbox.Tabs) do
                if other.Title == page or index == page then
                    found = other
                end
            end
            page = found
        end
        if not page or page._destroyed or tabbox.Current == page then
            return
        end
        local previous = tabbox.Current
        if previous then
            closeOpen(previous)
            previous._userVisible = false
            previous.List.Visible = false
        end
        tabbox.Current = page
        page._userVisible = tabbox._userVisible
        page.List.Visible = true
        for _, other in ipairs(tabbox.Tabs) do
            paint(other, previous == nil)
        end
        window._controlsDirty = true
    end

    function tabbox:AddTab(name, icon)
        local tabOpts = normalize(name, { Title = "Name" })
        if icon ~= nil and tabOpts.Icon == nil then
            tabOpts.Icon = icon
        end
        local tabName = tabOpts.Name or ("Tab " .. (#tabbox.Tabs + 1))
        local button = create("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = #tabbox.Tabs + 1,
            ZIndex = 2,
            Parent = strip,
        })
        local content = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -12, 1, 0),
            BackgroundTransparency = 1,
            ZIndex = 2,
            Parent = button,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
            Parent = content,
        })
        local tabIcon
        if tabOpts.Icon then
            tabIcon = create("ImageLabel", {
                Size = UDim2.fromOffset(13, 13),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Muted,
                ScaleType = Enum.ScaleType.Fit,
                LayoutOrder = 1,
                ZIndex = 2,
                Parent = content,
            })
            applyIcon(tabIcon, tabOpts.Icon)
        end
        local tabLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = tabName,
            TextSize = 13,
            FontFace = Fonts.Bold,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            ZIndex = 2,
            Parent = content,
        })
        local bar = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.new(1, -16, 0, 2),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = button,
        })
        corner(bar, UDim.new(1, 0))

        local inner = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Visible = false,
            Parent = body,
        })
        Library._space(padding(inner, 0, 0, 6, 8), { 0, 0, 6, 8 })
        Library._space(create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = inner,
        }), 2)

        local page = setmetatable({
            Name = tabbox.Name .. " › " .. tabName,
            Title = tabName,
            Window = window,
            Parent = owner,
            Tabbox = tabbox,
            List = inner,
            Frame = box,
            _frame = box,
            _order = 0,
            _groupbox = true,
            _metrics = METRICS.Row,
            _items = {},
            _userVisible = false,
            _button = button,
            _label = tabLabel,
            _icon = tabIcon,
            _bar = bar,
        }, Tab)
        -- Search treats an unselected tab as folded: expanding it selects it.
        function page:IsCollapsed()
            return tabbox.Current ~= page
        end
        function page:Expand()
            tabbox:SelectTab(page)
        end
        function page:Collapse() end
        function page:Select()
            tabbox:SelectTab(page)
        end
        function page:SetTitle(text)
            page.Title = tostring(text)
            page.Name = tabbox.Name .. " › " .. page.Title
            tabLabel.Text = page.Title
        end
        function page:Destroy()
            for index = #page._items, 1, -1 do
                local element = page._items[index]
                if type(element.Destroy) == "function" then
                    element:Destroy()
                end
            end
            page._destroyed = true
            local at = table.find(tabbox.Tabs, page)
            if at then
                table.remove(tabbox.Tabs, at)
            end
            at = table.find(owner._groupboxes, page)
            if at then
                table.remove(owner._groupboxes, at)
            end
            button:Destroy()
            inner:Destroy()
            relayoutButtons()
            if tabbox.Current == page then
                tabbox.Current = nil
                if tabbox.Tabs[1] then
                    tabbox:SelectTab(tabbox.Tabs[1])
                end
            end
            window._controlsDirty = true
        end

        button.MouseEnter:Connect(function()
            if tabbox.Current ~= page then
                tween(tabLabel, { TextColor3 = Theme.Text }, 0.15)
            end
        end)
        button.MouseLeave:Connect(function()
            if tabbox.Current ~= page then
                tween(tabLabel, { TextColor3 = Theme.Muted }, 0.15)
            end
        end)
        button.Activated:Connect(function()
            tabbox:SelectTab(page)
        end)

        table.insert(tabbox.Tabs, page)
        table.insert(owner._groupboxes, page)
        relayoutButtons()
        if not tabbox.Current then
            tabbox:SelectTab(page)
        else
            paint(page, true)
        end
        return page
    end
    tabbox.CreateTab = tabbox.AddTab
    tabbox.Tab = tabbox.AddTab

    function tabbox:SetTitle(text)
        tabbox.Name = tostring(text)
        for _, page in ipairs(tabbox.Tabs) do
            page.Name = tabbox.Name .. " › " .. page.Title
        end
    end
    function tabbox:IsVisible()
        return tabbox._userVisible
    end
    function tabbox:SetVisible(visible)
        visible = visible and true or false
        if visible == tabbox._userVisible then
            return
        end
        tabbox._userVisible = visible
        if tabbox.Current then
            if not visible then
                closeOpen(tabbox.Current)
            end
            tabbox.Current._userVisible = visible
        end
        box.Visible = visible
        window._controlsDirty = true
    end
    if not tabbox._userVisible then
        box.Visible = false
    end
    function tabbox:Destroy()
        for index = #tabbox.Tabs, 1, -1 do
            tabbox.Tabs[index]:Destroy()
        end
        set.Counts[side] = math.max(set.Counts[side] - 1, 0)
        tabbox._destroyed = true
        window._controlsDirty = true
        box:Destroy()
    end

    for _, entry in ipairs(opts.Tabs or {}) do
        tabbox:AddTab(entry)
    end
    return tabbox
end

Tab.CreateTabbox = Tab.Tabbox
Tab.AddTabbox = Tab.Tabbox
function Tab:AddLeftTabbox(opts)
    opts = normalize(opts, { Title = "Name" })
    opts.Side = "Left"
    return self:Tabbox(opts)
end
function Tab:AddRightTabbox(opts)
    opts = normalize(opts, { Title = "Name" })
    opts.Side = "Right"
    return self:Tabbox(opts)
end

-- Button rows: equal-width buttons side by side.

function Tab:ButtonRow(opts)
    local specs = type(opts) == "table" and (opts.Buttons or opts) or {}
    local compact = metricsOf(self).Compact
    local boxHeight = TOUCH and 34 or 30
    local frame = card(self, "Frame", boxHeight + (compact and 4 or 14), {})
    local inset = compact and 14 or 7
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, compact and 2 or 7),
        Size = UDim2.new(1, -inset * 2, 0, boxHeight),
        BackgroundTransparency = 1,
        Parent = frame,
    })
    local count = math.max(#specs, 1)
    local handle = { Buttons = {} }
    local names = {}
    for index, spec in ipairs(specs) do
        if type(spec) == "string" then
            spec = { Name = spec }
        end
        local text = spec.Name or spec.Title or "Button"
        table.insert(names, text)
        local button, text_ = softButton(holder, text, {
            Position = UDim2.new((index - 1) / count, (index - 1) * 6 / count, 0, 0),
            Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0),
        }, function()
            safeCall(spec.Callback)
        end)
        text_.TextSize = 13
        if spec.Style == "Primary" then
            tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
            tween(text_, { TextColor3 = Theme.AccentDark }, 0)
        elseif spec.Style == "Danger" then
            tween(text_, { TextColor3 = Theme.Error }, 0)
        end
        handle.Buttons[index] = { Button = button, Label = text_ }
    end
    function handle:SetText(index, text)
        local entry = handle.Buttons[index]
        if entry then
            entry.Label.Text = tostring(text)
        end
    end
    return finishElement(self, { Name = table.concat(names, " "), Visible = not (type(opts) == "table" and opts.Visible == false) }, handle, frame, "ButtonRow")
end

-- A text box with an action button beside it, for naming new configs and themes.
-- Without buttonText the box spans the row on its own.
local function actionInput(tab, placeholder, buttonText, callback)
    local boxHeight = TOUCH and 34 or 30
    local frame = card(tab, "Frame", boxHeight + 4, {})
    local inset = metricsOf(tab).Compact and 14 or 7
    local box
    local button = buttonText and softButton(frame, buttonText, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -inset, 0, 2),
        Size = UDim2.fromOffset(0, boxHeight),
        AutomaticSize = Enum.AutomaticSize.X,
    }, function()
        safeCall(callback, box.Text)
    end)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, 2),
        Size = UDim2.new(1, -(inset * 2 + (button and 70 or 0)), 0, boxHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(holder, UDim.new(0, 6))
    local holderStroke = stroke(holder)
    box = create("TextBox", {
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -16, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = holder,
    })
    box.Focused:Connect(function()
        tween(holderStroke, { Color = Theme.StrokeHover }, 0.15)
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(holderStroke, { Color = Theme.Stroke }, 0.2)
        if enterPressed and box.Text ~= "" then
            safeCall(callback, box.Text)
        end
    end)
    if button then
        local function fit()
            local width = button.AbsoluteSize.X / tab.Window.Scale.Scale
            holder.Size = UDim2.new(1, -(inset * 2 + width + 6), 0, boxHeight)
        end
        button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
        task.defer(fit)
    end
    return finishElement(tab, { Name = placeholder }, {
        Get = function()
            return box.Text
        end,
        Set = function(_, value)
            box.Text = tostring(value or "")
        end,
    }, frame, "ActionInput")
end

local function trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- An always-open single-pick list, for the config manager's saved configs.
-- tagsOf(name) returns short markers drawn at the row's right edge.
local function pickList(tab, names, default, rows, tagsOf, onPick, onOpen)
    local ROW = TOUCH and 30 or 24
    local listHeight = ROW * (rows or 5) + 8
    local frame = card(tab, "Frame", listHeight + 4, {})
    local inset = metricsOf(tab).Compact and 14 or 7
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, 2),
        Size = UDim2.new(1, -inset * 2, 0, listHeight),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(holder, UDim.new(0, 6))
    stroke(holder)
    local scroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Stroke,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = holder,
    })
    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
    local empty = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = "no configs yet",
        TextColor3 = Theme.Muted,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })
    local selected, buttons = nil, {}

    local function paint(instant)
        for name, entry in pairs(buttons) do
            local on = name == selected
            tween(entry.Button, { BackgroundTransparency = on and 0.82 or 1 }, instant and 0 or 0.15)
            tween(entry.Label, { TextColor3 = on and Theme.Accent or Theme.Text }, instant and 0 or 0.15)
            entry.Bar.Visible = on
            local tags = tagsOf and tagsOf(name) or ""
            entry.Tags.Text = tags
            entry.Label.Size = UDim2.new(1, -(18 + entry.Tags.TextBounds.X + (tags ~= "" and 6 or 0)), 1, 0)
        end
    end

    local function pick(name)
        if selected == name then
            return
        end
        selected = name
        paint()
        safeCall(onPick, name)
    end

    local handle = {}
    function handle:Refresh(list)
        for _, entry in pairs(buttons) do
            entry.Button:Destroy()
        end
        buttons = {}
        for index, name in ipairs(list or {}) do
            local button = create("TextButton", {
                Size = UDim2.new(1, -4, 0, ROW),
                BackgroundColor3 = Theme.Accent,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = scroll,
            })
            corner(button, UDim.new(0, 4))
            local bar = create("Frame", {
                Position = UDim2.new(0, 0, 0.5, -6),
                Size = UDim2.fromOffset(2, 12),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Visible = false,
                Parent = button,
            })
            local text = label({
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -18, 1, 0),
                Text = name,
                TextSize = 13,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = button,
            })
            local tags = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -8, 0, 0),
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                TextColor3 = Theme.Muted,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = button,
            })
            local lastClick = 0
            button.MouseButton1Click:Connect(function()
                -- A second click on the picked row loads it.
                if selected == name and os.clock() - lastClick < 0.35 then
                    lastClick = 0
                    safeCall(onOpen, name)
                    return
                end
                lastClick = os.clock()
                pick(name)
            end)
            button.MouseEnter:Connect(function()
                if selected ~= name then
                    tween(button, { BackgroundTransparency = 0.93 }, 0.1)
                end
            end)
            button.MouseLeave:Connect(function()
                if selected ~= name then
                    tween(button, { BackgroundTransparency = 1 }, 0.15)
                end
            end)
            buttons[name] = { Button = button, Label = text, Tags = tags, Bar = bar }
        end
        if selected and not buttons[selected] then
            pick(nil)
        end
        empty.Visible = next(buttons) == nil
        paint(true)
    end
    function handle:Get()
        return selected
    end
    function handle:Set(name)
        pick(name and buttons[name] and name or nil)
    end
    function handle:Repaint()
        paint(true)
    end
    handle:Refresh(names)
    handle:Set(default)
    return finishElement(tab, { Name = "Configs" }, handle, frame, "PickList")
end

-- Managers go in their own groupbox when added straight to a tab.
local function managerHost(tab, opts, name, icon)
    if tab._groupbox then
        return tab
    end
    local host = tab:Groupbox({ Name = opts.Name or name, Icon = opts.Icon or icon, Side = opts.Side })
    -- Library chrome, not a script feature: the feature list skips it.
    host._manager = true
    return host
end

function Tab:ConfigManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Configs", "folder")
    local window = self.Window
    local manager = {}
    local list, status, modeList

    local function notify(ok, title, detail)
        window:Notify({ Title = title, Content = detail, Type = ok and "Success" or "Error", Duration = 3 })
    end

    local autoToggle
    local function refreshStatus()
        if not status then
            return
        end
        local count = #window:ListConfigs()
        status:Set(("%d saved  ·  loaded: %s  ·  auto: %s"):format(count, window.LoadedConfig or "none", window:GetAutoload() or "none"))
        list:Repaint()
        if autoToggle then
            local picked = list:Get()
            autoToggle:Set(picked ~= nil and window:GetAutoload() == picked, true)
        end
    end

    local function pickedName()
        local name = list:Get()
        if not name then
            notify(false, "No config selected", "Pick one from the list first")
        end
        return name
    end

    local names = window:ListConfigs()
    local initial = window.LoadedConfig or window:GetAutoload()
    local nameInput
    list = pickList(host, names, table.find(names, initial) and initial or nil, opts.Rows, function(name)
        local tags = {}
        if name == window.LoadedConfig then
            table.insert(tags, "loaded")
        end
        if name == window:GetAutoload() then
            table.insert(tags, "auto")
        end
        return table.concat(tags, " · ")
    end, function(name)
        if nameInput then
            nameInput:Set(name or "")
        end
        refreshStatus()
    end, function(name)
        manager:Load(name)
    end)
    status = host:Label("0 saved")
    host:Label("Config Name:")
    nameInput = actionInput(host, opts.Placeholder or "Type config name here...", nil, function(text)
        manager:Create(text)
    end)
    host:ButtonRow({
        { Name = "Save", Callback = function() manager:Save() end },
        { Name = "Load", Callback = function() manager:Load() end },
    })
    host:ButtonRow({
        { Name = "Delete", Style = "Danger", Callback = function() manager:Delete() end },
        { Name = "Refresh", Callback = function() manager:Refresh() end },
    })
    autoToggle = host:Toggle({
        Name = "Auto Load Config",
        Desc = "Loads the selected config on launch",
        Callback = function(value)
            local picked = list:Get()
            if not picked then
                notify(false, "No config selected", "Pick one from the list first")
            elseif value ~= (window:GetAutoload() == picked) then
                if value then
                    manager:SetAutoload(picked)
                else
                    manager:ClearAutoload()
                end
            end
            refreshStatus()
        end,
    })
    host:Divider({ Text = "more" })
    host:ButtonRow({
        { Name = "Rename", Callback = function() manager:Rename(nil, nameInput:Get()) end },
        { Name = "Reset", Style = "Danger", Callback = function() manager:Reset() end },
    })
    modeList = host:Dropdown({
        Name = "Autoload mode",
        Stacked = true,
        Options = { "All accounts", "This account" },
        Default = window:GetAutoloadMode() == "Account" and "This account" or "All accounts",
        AllowNone = false,
        Callback = function(choice)
            manager:SetAutoloadMode(choice == "This account" and "Account" or "Global")
        end,
    })
    host:Divider({ Text = "share" })
    host:Button({ Name = "Copy code", Callback = function() manager:Export() end })
    local codeInput = actionInput(host, "paste a config code...", nil, function(text)
        manager:Import(text)
    end)
    host:Button({ Name = "Import code", Callback = function() manager:Import(codeInput:Get()) end })

    function manager:Refresh()
        local names = window:ListConfigs()
        local keep = list:Get()
        list:Refresh(names, true)
        if keep and not table.find(names, keep) then
            list:Set(window.LoadedConfig and table.find(names, window.LoadedConfig) and window.LoadedConfig or nil, true)
        end
        refreshStatus()
    end

    local function select(name)
        manager:Refresh()
        list:Set(name, true)
    end

    function manager:Create(name)
        name = trim(name)
        if name == "" then
            notify(false, "Name the config", "Type a name before creating it")
            return
        end
        if not validConfigName(name) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local ok, err = window:SaveConfig(name)
        if ok then
            window.LoadedConfig = name
            nameInput:Set("")
            select(name)
        end
        notify(ok, ok and "Config created" or "Create failed", ok and name or tostring(err))
    end

    function manager:Save(name)
        local typed = trim(nameInput:Get())
        if not name and typed ~= "" and typed ~= list:Get() then
            return manager:Create(typed)
        end
        name = name or list:Get()
        if not name then
            local typed = trim(nameInput:Get())
            if typed == "" then
                notify(false, "No config selected", "Pick one from the list or type a name")
                return
            end
            return manager:Create(typed)
        end
        local ok, err = window:SaveConfig(name)
        if ok then
            window.LoadedConfig = name
            refreshStatus()
        end
        notify(ok, ok and "Config saved" or "Save failed", ok and name or tostring(err))
    end

    function manager:Load(name)
        name = name or pickedName()
        if not name then
            return
        end
        local ok, err = window:LoadConfig(name)
        refreshStatus()
        notify(ok, ok and "Config loaded" or "Load failed", ok and name or tostring(err))
    end

    function manager:Delete(name)
        name = name or pickedName()
        if not name then
            return
        end
        window:Confirm({
            Title = "Delete config",
            Content = "Remove " .. name .. "? This cannot be undone.",
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = window:DeleteConfig(name)
                if ok then
                    if window:GetAutoload("Account") == name then
                        window:SetAutoload(nil, "Account")
                    end
                    if window:GetAutoload("Global") == name then
                        window:SetAutoload(nil, "Global")
                    end
                    list:Set(nil, true)
                end
                manager:Refresh()
                notify(ok, ok and "Config deleted" or "Delete failed", ok and name or tostring(err))
            end,
        })
    end

    function manager:Rename(name, newName)
        name = name or pickedName()
        if not name then
            return
        end
        newName = trim(newName)
        if newName == "" then
            notify(false, "Name the config", "Type the new name in the name box")
            return
        end
        if not validConfigName(newName) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local ok, err = window:RenameConfig(name, newName)
        if ok then
            nameInput:Set("")
            select(newName)
        end
        notify(ok, ok and "Config renamed" or "Rename failed", ok and (name .. " -> " .. newName) or tostring(err))
    end

    function manager:Reset()
        window:Confirm({
            Title = "Reset settings",
            Content = "Put every setting back to its default and delete this script's folder? Saved configs, themes and autoload are removed for good.",
            Icon = "rotate-ccw",
            ConfirmText = "Reset",
            Callback = function()
                window:ResetConfig()
                local wiped = window:ClearWorkspace()
                window:_applyDefaultTheme()
                list:Set(nil, true)
                manager:Refresh()
                modeList:Set("All accounts", true)
                notify(wiped, wiped and "Settings reset" or "Reset incomplete",
                    wiped and "Everything is back to its default" or "Some files in " .. window.ConfigFolder .. " could not be deleted")
            end,
        })
    end

    function manager:SetAutoload(name)
        name = name or pickedName()
        if not name then
            return
        end
        local ok, err = window:SetAutoload(name)
        refreshStatus()
        notify(ok, ok and "Autoload set" or "Autoload failed", ok and name or tostring(err))
    end

    function manager:ClearAutoload()
        local current = window:GetAutoload()
        if not current then
            notify(false, "No autoload", "Nothing is set to autoload")
            return
        end
        local ok, err = window:SetAutoload(nil)
        refreshStatus()
        notify(ok, ok and "Autoload cleared" or "Clear failed", ok and current or tostring(err))
    end

    function manager:ToggleAutoload(name)
        name = name or pickedName()
        if not name then
            return
        end
        if window:GetAutoload() == name then
            manager:ClearAutoload()
        else
            manager:SetAutoload(name)
        end
    end

    function manager:SetAutoloadMode(mode)
        local ok, err = window:SetAutoloadMode(mode)
        local label_ = mode == "Account" and "This account" or "All accounts"
        if modeList:Get() ~= label_ then
            modeList:Set(label_, true)
        end
        notify(ok ~= false, ok ~= false and "Autoload mode" or "Mode change failed", ok ~= false and label_ or tostring(err))
    end

    function manager:Export(name)
        local code, err = window:ExportConfig(name)
        if not code then
            notify(false, "Export failed", tostring(err))
            return nil
        end
        window:CopyToClipboard(code, "Config code")
        return code
    end

    function manager:Import(code)
        code = trim(code)
        if code == "" then
            notify(false, "Nothing to import", "Paste a config code first")
            return
        end
        local data, info = window:DecodeConfig(code)
        if not data then
            notify(false, "Import failed", "Invalid config code")
            return
        end
        -- The typed name wins; otherwise the code's own name, never overwriting a config.
        local saveAs = trim(nameInput:Get())
        if saveAs == "" then
            saveAs = nil
            if validConfigName(info.Name) then
                saveAs = info.Name
                local index = 2
                while window:ConfigExists(saveAs) do
                    saveAs = ("%s (%d)"):format(info.Name, index)
                    index += 1
                end
            end
        elseif not validConfigName(saveAs) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local function run()
            local ok, err = window:ImportConfig(code, saveAs, true)
            if ok then
                codeInput:Set("")
                if saveAs then
                    nameInput:Set("")
                    select(saveAs)
                end
            end
            notify(ok, ok and "Config imported" or "Import failed", ok and (saveAs or "Applied to current settings") or tostring(err))
        end
        if info.Folder and info.Folder ~= window.ConfigFolder then
            window:Confirm({
                Title = "Different script",
                Content = ("This config was made for %s. Import it anyway? Only matching settings are applied."):format(info.Folder),
                Icon = "triangle-alert",
                ConfirmText = "Import",
                Callback = run,
            })
            return
        end
        run()
    end

    local disconnect = window:OnConfigChanged(function()
        -- Configs can arrive from elsewhere, so the list is reread.
        manager:Refresh()
        if window.LoadedConfig and list:Get() == nil then
            list:Set(window.LoadedConfig, true)
        end
    end)
    status._listeners = status._listeners or {}
    table.insert(status._listeners, disconnect)

    refreshStatus()
    return manager
end

local PRESET_ORDER = {
    "Midnight", "Nebula", "Synthwave", "Sakura", "Velvet", "Rose", "Crimson", "Sunset", "Amber", "Gold",
    "Cyber", "Toxic", "Matcha", "Emerald", "Aurora", "Ocean", "Frost", "Abyss", "Mono",
    "Halloween", "Haunted", "Christmas", "Valentine", "Lunar", "Tropical", "Dracula", "Coffee",
}

local function presetNames()
    local names, seen = {}, {}
    for _, name in ipairs(PRESET_ORDER) do
        if Library.ThemePresets[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end
    local extra = {}
    for name in pairs(Library.ThemePresets) do
        if not seen[name] then
            table.insert(extra, name)
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        table.insert(names, name)
    end
    return names
end

function Tab:ThemeManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Themes", "palette")
    local window = self.Window
    local manager = {}
    local themes, status, defaultRow, presets
    local weather, weatherMode, dim, transparent, dragSkeleton, islandStyle
    local background, backgroundInput, backgroundOpacity, backgroundLabel
    local uiScale, density, adaptive, cornerRadius

    local function notify(ok, title, detail)
        window:Notify({ Title = title, Content = detail, Type = ok and "Success" or "Error", Duration = 3 })
    end

    local function refreshStatus()
        local current = window:GetDefaultTheme()
        status:Set("Default theme: " .. (current or "none"))
        local picked = themes:Get() or presets:Get()
        defaultRow:SetText(2, (picked and picked == current) and "Clear Default" or "Set Default")
    end

    local function pickedTheme()
        local name = themes:Get()
        if not name then
            notify(false, "No theme selected", "Pick one from the list first")
        end
        return name
    end

    presets = host:Dropdown({
        Name = "Preset",
        Options = presetNames(),
        Default = Library.ThemePresets[Library.ThemeName or ""] and Library.ThemeName or nil,
        NoneText = "custom",
        AllowNone = false,
        Callback = function(name)
            if name then
                Library:SetTheme(name)
                themes:Set(nil, true)
                refreshStatus()
            end
        end,
    })
    -- Menu look (weather, scale, background...) gets its own groupbox, apart from the colors.
    local menu = host
    if not self._groupbox and opts.Menu ~= false then
        menu = self:Groupbox({ Name = opts.MenuName or "Menu", Icon = opts.MenuIcon or "monitor", Side = opts.MenuSide or opts.Side })
        menu._manager = true
    end
    local labels = { None = "None", Snow = "Snow", Rain = "Rain", Ember = "Hell Fire", Sakura = "Sakura", Fireflies = "Fireflies", Matrix = "Matrix" }
    if window._backdrop and opts.Weather ~= false then
        weather = menu:Dropdown({
            Name = "Weather",
            Options = { "Snow", "Rain", "Hell Fire", "Sakura", "Fireflies", "Matrix", "None" },
            Default = labels[window.Weather] or "None",
            AllowNone = false,
            Callback = function(name)
                if name then
                    window:SetWeather(name)
                end
            end,
        })
    end
    if window._backdrop and opts.Weather ~= false then
        weatherMode = menu:Dropdown({
            Name = "Weather Mode",
            Options = { "Screen", "UI" },
            Default = window.WeatherMode,
            AllowNone = false,
            Callback = function(mode)
                if mode then
                    window:SetWeatherMode(mode)
                end
            end,
        })
    end
    if window._backdrop and opts.Dim ~= false then
        dim = menu:Toggle({
            Name = "Dim",
            Default = window._backdropDim,
            Callback = function(value)
                window:SetDim(value)
            end,
        })
    end
    if opts.Transparent ~= false then
        transparent = menu:Toggle({
            Name = "Transparent",
            Default = window.Transparent == true,
            Callback = function(value)
                window:SetTransparent(value)
            end,
        })
    end
    if opts.DragSkeleton ~= false and opts.DragStyle ~= false then
        dragSkeleton = menu:Dropdown({
            Name = "Drag Style",
            Options = Library.DragStyles,
            Default = window.DragStyle,
            AllowNone = false,
            Callback = function(style)
                if style then
                    window:SetDragStyle(style)
                end
            end,
        })
    end
    if opts.IslandStyle ~= false then
        islandStyle = menu:Dropdown({
            Name = "Dynamic Island",
            Options = Library.IslandStyles,
            Default = window.IslandStyle,
            AllowNone = false,
            Callback = function(style)
                if style then
                    window:SetIslandStyle(style)
                end
            end,
        })
    end
    if opts.AdaptiveSize ~= false then
        adaptive = menu:Toggle({
            Name = "Adaptive Size",
            Default = window:GetAdaptiveSize(),
            Callback = function(value)
                window:SetAdaptiveSize(value)
            end,
        })
    end
    if opts.Scale ~= false then
        uiScale = menu:Slider({
            Name = "UI Scale",
            Min = 60,
            Max = 150,
            Increment = 5,
            Default = math.floor(window:GetUIScale() * 100 + 0.5),
            Suffix = "%",
            -- Rescaling mid-drag would move the slider out from under the
            -- pointer, so a drag applies on release.
            Callback = function(value)
                if not (uiScale and uiScale.Dragging) then
                    window:SetUIScale(value / 100)
                end
            end,
            OnRelease = function(value)
                window:SetUIScale(value / 100)
            end,
        })
    end
    if opts.Density ~= false then
        density = menu:Dropdown({
            Name = "Density",
            Options = { "Compact", "Default", "Comfortable" },
            Default = Library.Density,
            AllowNone = false,
            Callback = function(mode)
                if mode then
                    Library:SetDensity(mode)
                end
            end,
        })
    end
    if opts.CornerRadius ~= false then
        cornerRadius = menu:Slider({
            Name = "Corner Radius",
            Min = 0,
            Max = 20,
            Increment = 1,
            Default = Library:GetCornerRadius(),
            Suffix = "px",
            Callback = function(value)
                Library:SetCornerRadius(value)
            end,
        })
    end
    if opts.Background ~= false then
        -- The dropdown shows listed images by name, "custom" for ids and links.
        backgroundLabel = function(source)
            if source == nil or source == "" then
                return "None"
            end
            return table.find(window:ListBackgrounds(), source) and source or nil
        end
        local function applyBackground(source, fromList)
            task.spawn(function()
                local ok, err = window:SetBackground(source)
                if ok and not fromList then
                    background:Set(backgroundLabel(window.Background), true)
                elseif not ok and err ~= "replaced by a newer background" then
                    notify(false, "Background failed", tostring(err))
                end
            end)
        end
        local options = window:ListBackgrounds()
        table.insert(options, 1, "None")
        background = menu:Dropdown({
            Name = "Background",
            Options = options,
            Default = backgroundLabel(window.Background),
            NoneText = "custom",
            AllowNone = false,
            Callback = function(name)
                if name then
                    applyBackground(name, true)
                end
            end,
        })
        backgroundInput = actionInput(menu, "image id or url", "Set", function(text)
            text = trim(text)
            if text == "" then
                notify(false, "No image", "Paste an image id or link first")
                return
            end
            applyBackground(text)
        end)
        backgroundOpacity = menu:Slider({
            Name = "Background Opacity",
            Min = 0,
            Max = 100,
            Default = math.floor((1 - window.BackgroundTransparency) * 100 + 0.5),
            Suffix = "%",
            Callback = function(value)
                window:SetBackgroundTransparency(1 - value / 100)
            end,
        })
    end
    local nameInput = actionInput(host, opts.Placeholder or "theme name", "Create", function(text)
        manager:Create(text)
    end)
    themes = host:Dropdown({
        Name = "Theme",
        Options = window:ListThemes(),
        Default = (function()
            local current = window:GetDefaultTheme()
            return current and not Library.ThemePresets[current] and current or nil
        end)(),
        EmptyText = "no themes",
        NoneText = "select",
        Callback = function()
            refreshStatus()
        end,
    })
    host:ButtonRow({
        { Name = "Save", Callback = function() manager:Save() end },
        { Name = "Load", Callback = function() manager:Load() end },
    })
    defaultRow = host:ButtonRow({
        { Name = "Delete", Callback = function() manager:Delete() end },
        { Name = "Set Default", Callback = function() manager:ToggleDefault() end },
    })
    status = host:Label("Default theme: none")

    function manager:Refresh()
        themes:Refresh(window:ListThemes(), true)
        if background then
            local options = window:ListBackgrounds()
            table.insert(options, 1, "None")
            background:Refresh(options, true, true)
        end
        refreshStatus()
    end

    function manager:Create(name)
        name = trim(name)
        if name == "" then
            notify(false, "Name the theme", "Type a name before creating it")
            return
        end
        if Library.ThemePresets[name] then
            notify(false, "Name taken", name .. " is a built-in preset")
            return
        end
        local ok, err = window:SaveTheme(name)
        manager:Refresh()
        if ok then
            themes:Set(name, true)
            nameInput:Set("")
            refreshStatus()
        end
        notify(ok, ok and "Theme created" or "Create failed", ok and name or tostring(err))
    end

    function manager:Save(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        local ok, err = window:SaveTheme(name)
        notify(ok, ok and "Theme saved" or "Save failed", ok and name or tostring(err))
    end

    function manager:Load(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        local ok, err = window:LoadTheme(name)
        if ok then
            presets:Set(nil, true)
        end
        notify(ok ~= false, ok and "Theme loaded" or "Load failed", ok and name or tostring(err))
    end

    function manager:Delete(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        window:Confirm({
            Title = "Delete theme",
            Content = "Remove " .. name .. "? This cannot be undone.",
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = window:DeleteTheme(name)
                manager:Refresh()
                notify(ok, ok and "Theme deleted" or "Delete failed", ok and name or tostring(err))
            end,
        })
    end

    function manager:ToggleDefault(name)
        name = name or themes:Get() or presets:Get()
        if not name then
            notify(false, "Nothing selected", "Pick a theme or a preset first")
            return
        end
        local clearing = window:GetDefaultTheme() == name
        local ok, err = window:SetDefaultTheme(not clearing and name or nil)
        refreshStatus()
        notify(ok ~= false, clearing and "Default cleared" or "Default theme set", ok ~= false and name or tostring(err))
    end

    if opts.Customize ~= false then
        host:Divider()
        local fields = opts.Colors or {
            { "Accent", "Accent" },
            { "Background", "Background" },
            { "Surface2", "Surface" },
            { "Text", "Text" },
            { "Muted", "Muted text" },
        }
        for _, field in ipairs(fields) do
            local key, title = field[1], field[2] or field[1]
            local pending, scheduled = nil, false
            local picker
            picker = host:ColorPicker({
                Name = title,
                Default = Theme[key],
                Callback = function(color)
                    -- Dragging the picker fires every frame; repaint at most
                    -- a dozen times a second.
                    pending = color
                    if scheduled then
                        return
                    end
                    scheduled = true
                    task.delay(0.08, function()
                        scheduled = false
                        Library:SetTheme({ [key] = pending }, true)
                        presets:Set(nil, true)
                    end)
                end,
            })
            table.insert(Library._themeListeners, function()
                if picker.Value ~= Theme[key] then
                    picker:Set(Theme[key], true)
                end
            end)
        end
    end

    -- One hidden flag carries the palette and the look settings above, so
    -- configs save and load the theme. Not a flag per toggle: flagged toggles
    -- would count as running features on the minimized island.
    if opts.Flag ~= false then
        local flag = type(opts.Flag) == "string" and opts.Flag or "__Theme"
        local look = { _type = "Theme", _searchName = "Theme", _searchKey = "theme", _listeners = {} }

        function look:Get()
            local colors = {}
            for _, key in ipairs(THEME_KEYS) do
                colors[key] = colorToHex(Theme[key])
            end
            return {
                Name = presets:Get() or themes:Get(),
                Colors = colors,
                Weather = weather and window.Weather or nil,
                WeatherMode = weatherMode and window.WeatherMode or nil,
                -- if-expressions, not and/or: a switched-off value is false, not nil.
                Dim = if dim then window._backdropDim == true else nil,
                Transparent = if transparent then window.Transparent == true else nil,
                DragStyle = dragSkeleton and window.DragStyle or nil,
                IslandStyle = islandStyle and window.IslandStyle or nil,
                CornerRadius = cornerRadius and Library:GetCornerRadius() or nil,
                UIScale = uiScale and window:GetUIScale() or nil,
                AdaptiveSize = if adaptive then window:GetAdaptiveSize() else nil,
                Density = density and Library.Density or nil,
                -- "" is no background; a missing field leaves it alone on load.
                Background = background and (window.Background or "") or nil,
                BackgroundTransparency = background and window.BackgroundTransparency or nil,
            }
        end

        function look:Set(value)
            if type(value) ~= "table" then
                return
            end
            if type(value.Colors) == "table" then
                Library:SetTheme(value.Colors)
            end
            local name = type(value.Name) == "string" and value.Name or nil
            if name and Library.ThemePresets[name] then
                Library.ThemeName = name
                presets:Set(name, true)
                themes:Set(nil, true)
            else
                if name then
                    Library.ThemeName = name
                end
                presets:Set(nil, true)
                themes:Set(name and table.find(window:ListThemes(), name) and name or nil, true)
            end
            if weather and type(value.Weather) == "string" then
                window:SetWeather(value.Weather)
                weather:Set(labels[window.Weather] or "None", true)
            end
            if weatherMode and type(value.WeatherMode) == "string" then
                window:SetWeatherMode(value.WeatherMode)
                weatherMode:Set(window.WeatherMode, true)
            end
            if dim and type(value.Dim) == "boolean" then
                window:SetDim(value.Dim)
                dim:Set(value.Dim, true)
            end
            if transparent and type(value.Transparent) == "boolean" then
                window:SetTransparent(value.Transparent)
                transparent:Set(value.Transparent, true)
            end
            if dragSkeleton and type(value.DragStyle) == "string" then
                dragSkeleton:Set(window:SetDragStyle(value.DragStyle), true)
            elseif dragSkeleton and type(value.DragSkeleton) == "boolean" then
                -- Configs saved before drag styles.
                window:SetDragSkeleton(value.DragSkeleton)
                dragSkeleton:Set(window.DragStyle, true)
            end
            if islandStyle and type(value.IslandStyle) == "string" then
                islandStyle:Set(window:SetIslandStyle(value.IslandStyle), true)
            end
            if cornerRadius and tonumber(value.CornerRadius) then
                cornerRadius:Set(Library:SetCornerRadius(value.CornerRadius), true)
            end
            if adaptive and type(value.AdaptiveSize) == "boolean" then
                window:SetAdaptiveSize(value.AdaptiveSize)
                adaptive:Set(value.AdaptiveSize, true)
            end
            if uiScale and tonumber(value.UIScale) then
                window:SetUIScale(tonumber(value.UIScale))
                uiScale:Set(math.floor(window:GetUIScale() * 100 + 0.5), true)
            end
            if density and type(value.Density) == "string" then
                density:Set(Library:SetDensity(value.Density), true)
            end
            if background and tonumber(value.BackgroundTransparency) then
                window:SetBackgroundTransparency(tonumber(value.BackgroundTransparency))
                backgroundOpacity:Set(math.floor((1 - window.BackgroundTransparency) * 100 + 0.5), true)
            end
            if background and type(value.Background) == "string" and value.Background ~= (window.Background or "") then
                local source = value.Background
                background:Set(backgroundLabel(source), true)
                -- A web image may download first; don't hold up the rest of the config.
                task.spawn(window.SetBackground, window, source)
            end
            refreshStatus()
        end

        Library.Flags[flag] = look
        window:_flagCreated(flag, look)
    end

    -- A reset wipes the themes folder, so drop the stale list.
    window._workspaceListeners = window._workspaceListeners or {}
    table.insert(window._workspaceListeners, function()
        themes:Set(nil, true)
        manager:Refresh()
    end)

    refreshStatus()
    return manager
end

Tab.CreateButtonRow = Tab.ButtonRow
Tab.CreateConfigManager = Tab.ConfigManager
Tab.CreateThemeManager = Tab.ThemeManager

-- Status: read-only key/value lines, mostly for groupboxes, in several styles.

local STATUS_HEIGHT = { Plain = 18, Row = 20, Badge = 24, Dot = 20, Bar = 34, Stat = 44 }

-- Tone: a theme key, a Color3 or "#rrggbb".
local function toneColor(tone)
    return Library._color(tone) or Theme.Accent
end

local function formatNumber(value)
    if value == math.floor(value) then
        return tostring(math.floor(value))
    end
    return string.format("%.1f", value)
end

local function parseFraction(value, max)
    if type(value) == "number" and type(max) == "number" then
        return value, max
    end
    if type(value) == "string" then
        local cleaned = (value:gsub(",", ""))
        local current, total = cleaned:match("^%s*(%-?[%d%.]+)%s*/%s*(%-?[%d%.]+)")
        if current then
            return tonumber(current), tonumber(total)
        end
    end
    return nil, nil
end

function Tab:Status(opts)
    opts = normalize(opts, { Title = "Name", Text = "Value", Content = "Value", CurrentValue = "Value", Default = "Value" })
    local style = STATUS_HEIGHT[opts.Style] and opts.Style or "Plain"
    local compact = metricsOf(self).Compact
    local window = self.Window
    local height = STATUS_HEIGHT[style]
    -- Obsidian-style: no card, the text sits straight on the groupbox.
    local pad = 1
    local frame, frameStroke = card(self, "Frame", height + pad * 2, opts)
    frame.BackgroundTransparency = 1
    frameStroke.Transparency = 1
    frameStroke:SetAttribute("Hidden", true)
    local inset = compact and 14 or 2
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, pad),
        Size = UDim2.new(1, -inset * 2, 0, height),
        BackgroundTransparency = 1,
        Parent = frame,
    })

    local handle = { Value = opts.Value, Max = opts.Max, Tone = opts.Tone or "Accent", Name = opts.Name or "", Color = opts.Color or opts.ValueColor }
    local keyLabel, valueLabel, chip, chipStroke, dot, pulse, fill
    local tinted = false

    local function keyText()
        return style == "Plain" and (handle.Name .. ":") or handle.Name
    end

    if style == "Plain" then
        -- The value sits after the key and wraps beneath itself, growing the row.
        frame.AutomaticSize = Enum.AutomaticSize.Y
        holder.AutomaticSize = Enum.AutomaticSize.Y
        keyLabel = label({
            Size = UDim2.new(0, 0, 0, height),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 14,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Text,
            TextTransparency = 0.4,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = holder,
        })
        valueLabel = label({
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = holder,
        })
        local wrap = opts.Wrap ~= false
        local function place()
            local x = keyLabel.TextBounds.X + 5
            valueLabel.Position = UDim2.fromOffset(x, 0)
            if wrap then
                valueLabel.Size = UDim2.new(1, -x, 0, height)
                valueLabel.AutomaticSize = Enum.AutomaticSize.Y
            else
                valueLabel.Size = UDim2.new(0, 0, 0, height)
                valueLabel.AutomaticSize = Enum.AutomaticSize.X
            end
            valueLabel.TextWrapped = wrap
        end
        keyLabel:GetPropertyChangedSignal("TextBounds"):Connect(place)
        place()
        -- false keeps the value on one line; true lets it wrap again.
        function handle:SetWrap(value)
            wrap = value ~= false
            place()
        end
    elseif style == "Stat" then
        keyLabel = label({
            Position = UDim2.fromOffset(0, 1),
            Size = UDim2.new(1, 0, 0, 16),
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextTransparency = 0.4,
            Parent = holder,
        })
        valueLabel = label({
            Position = UDim2.fromOffset(0, 18),
            Size = UDim2.new(1, 0, 0, 24),
            TextSize = 20,
            FontFace = Fonts.Bold,
            TextColor3 = Theme.Text,
            Parent = holder,
        })
    else
        local keyX = 0
        if style == "Dot" then
            keyX = 18
            pulse = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 5, 0.5, 0),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = toneColor(handle.Tone),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(pulse, UDim.new(1, 0))
            dot = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 5, 0.5, 0),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = toneColor(handle.Tone),
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(dot, UDim.new(1, 0))
            if opts.Pulse ~= false then
                TweenService:Create(pulse, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), {
                    Size = UDim2.fromOffset(20, 20),
                    BackgroundTransparency = 1,
                }):Play()
            else
                pulse.Visible = false
            end
        end
        local rowHeight = style == "Bar" and 18 or height
        keyLabel = label({
            Position = UDim2.fromOffset(keyX, 0),
            Size = UDim2.new(0.55, -keyX, 0, rowHeight),
            TextSize = 14,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Text,
            TextTransparency = 0.4,
            Parent = holder,
        })
        if style == "Badge" then
            tinted = true
            chip = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(0, 20),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = toneColor(handle.Tone),
                BackgroundTransparency = 0.86,
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(chip, UDim.new(1, 0))
            chipStroke = stroke(chip, toneColor(handle.Tone), 0.6)
            padding(chip, 10, 10)
            valueLabel = label({
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                TextSize = 14,
                TextColor3 = toneColor(handle.Tone),
                TextTruncate = Enum.TextTruncate.None,
                Parent = chip,
            })
        else
            valueLabel = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0.45, 0, 0, rowHeight),
                TextSize = 14,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = holder,
            })
        end
        if style == "Bar" then
            local track = create("Frame", {
                Position = UDim2.fromOffset(0, 24),
                Size = UDim2.new(1, 0, 0, 5),
                BackgroundColor3 = Theme.Surface3,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Parent = holder,
            })
            corner(track, UDim.new(1, 0))
            fill = create("Frame", {
                Size = UDim2.new(0, 0, 1, 0),
                BackgroundColor3 = toneColor(handle.Tone),
                BorderSizePixel = 0,
                Parent = track,
            })
            corner(fill, UDim.new(1, 0))
        end
    end

    local lastText = nil
    local function render(animate)
        keyLabel.Text = Library._rich(keyText())
        local value = handle.Value
        local text = value == nil and (opts.Placeholder or "-") or tostring(value)
        if style == "Bar" then
            local current, total = parseFraction(value, handle.Max)
            if current and total then
                handle.Max = total
                text = formatNumber(current) .. " / " .. formatNumber(total)
                local fraction = total > 0 and math.clamp(current / total, 0, 1) or 0
                tween(fill, { Size = UDim2.new(fraction, 0, 1, 0) }, animate and 0.4 or 0, Enum.EasingStyle.Quint)
            elseif type(value) == "number" and value <= 1 then
                text = string.format("%d%%", math.floor(value * 100 + 0.5))
                tween(fill, { Size = UDim2.new(math.clamp(value, 0, 1), 0, 1, 0) }, animate and 0.4 or 0, Enum.EasingStyle.Quint)
            end
        end
        text = Library._rich((opts.Prefix or "") .. text .. (opts.Suffix or ""))
        local changed = lastText ~= nil and text ~= lastText
        lastText = text
        valueLabel.Text = text
        local tone = toneColor(handle.Tone)
        local duration = animate and 0.25 or 0
        -- Color paints the whole value; inline tags still win over it.
        local valueColor = not tinted and Library._color(handle.Color) or Theme.Text
        if not tinted and not (changed and animate and opts.Flash ~= false) then
            tween(valueLabel, { TextColor3 = valueColor }, duration)
        end
        if chip then
            tween(chip, { BackgroundColor3 = tone }, duration)
            tween(chipStroke, { Color = tone }, duration)
            tween(valueLabel, { TextColor3 = tone }, duration)
        end
        if dot then
            tween(dot, { BackgroundColor3 = tone }, duration)
            tween(pulse, { BackgroundColor3 = tone }, 0)
        end
        if fill then
            tween(fill, { BackgroundColor3 = tone }, duration)
        end
        -- A brief accent flash marks a changed value.
        if changed and animate and not tinted and opts.Flash ~= false then
            tween(valueLabel, { TextColor3 = Theme.Accent }, 0.08)
            task.delay(0.1, function()
                if valueLabel.Parent then
                    tween(valueLabel, { TextColor3 = Library._color(handle.Color) or Theme.Text }, 0.45)
                end
            end)
        end
    end

    keyLabel.RichText = true
    valueLabel.RichText = true
    -- Theme tags in the text are baked to colours, so repaint on theme change.
    onTheme(holder, function()
        if lastText ~= nil then
            render(false)
        end
    end)

    function handle:Set(value, max)
        handle.Value = value
        if max ~= nil then
            handle.Max = max
        end
        render(true)
    end
    function handle:Get()
        return handle.Value
    end
    function handle:SetTone(tone)
        handle.Tone = tone
        render(true)
    end
    -- nil goes back to the normal text colour.
    function handle:SetColor(color)
        handle.Color = color
        render(true)
    end
    function handle:SetName(name)
        handle.Name = tostring(name)
        render(false)
    end
    function handle:Text()
        return valueLabel.Text
    end
    -- The value's resting colour, for the copy pinned on the minimized island.
    function handle._shownColor()
        if handle.Color ~= nil then
            return Library._color(handle.Color) or Theme.Text
        end
        if style == "Badge" or style == "Dot" or style == "Bar" then
            return toneColor(handle.Tone)
        end
        return Theme.Text
    end

    handle._listeners = {}
    if type(opts.Update) == "function" then
        local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
        local running = true
        table.insert(handle._listeners, function()
            running = false
        end)
        task.spawn(function()
            while running and frame.Parent do
                local ok, value, extra = isolatedCall(opts.Update)
                if ok then
                    if value ~= nil then
                        handle.Value = value
                    end
                    if type(extra) == "number" then
                        handle.Max = extra
                    elseif type(extra) == "string" or typeof(extra) == "Color3" then
                        handle.Tone = extra
                    end
                    render(true)
                else
                    warn("[AirFlow] status update error: " .. tostring(value))
                end
                task.wait(rate)
            end
        end)
        function handle:SetUpdateRate(seconds)
            rate = math.max(tonumber(seconds) or rate, 0.05)
        end
    end
    if opts.Pin then
        table.insert(window._pinned, handle)
        table.insert(handle._listeners, function()
            local index = table.find(window._pinned, handle)
            if index then
                table.remove(window._pinned, index)
            end
        end)
    end

    render(false)
    return finishElement(self, opts, handle, frame, "Status")
end

function Tab:Statuses(entries, shared)
    local handles = {}
    for index, entry in ipairs(entries or {}) do
        local entryOpts = type(entry) == "table" and table.clone(entry) or { Name = tostring(entry) }
        for key, value in pairs(shared or {}) do
            if entryOpts[key] == nil then
                entryOpts[key] = value
            end
        end
        local handle = self:Status(entryOpts)
        handles[entryOpts.Name or entryOpts.Title or index] = handle
    end
    return handles
end

-- Status list: a read-only block of rows that grows up to MaxRows, then
-- scrolls inside itself. Rows are reused between refreshes so nothing flickers.
function Tab:StatusList(opts)
    opts = normalize(opts, { Title = "Name" })
    local compact = metricsOf(self).Compact
    local window = self.Window
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 5), 1)
    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = frame,
    })
    local heading = label({
        Size = UDim2.new(1, 0, 0, 16),
        Text = string.upper(tostring(opts.Name or "")),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        Visible = tostring(opts.Name or "") ~= "",
        LayoutOrder = 1,
        Parent = frame,
    })
    local scroller = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollingEnabled = false,
        LayoutOrder = 2,
        Parent = frame,
    })
    scroller:SetAttribute("NoDrag", true)
    local content = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local contentPadding = padding(content, 0, 0, 0, 0)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = content,
    })
    local empty = label({
        Size = UDim2.new(1, 0, 0, 24),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(opts.EmptyText or "Nothing yet"),
        TextSize = 13,
        LineHeight = 1.1,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 0,
        Parent = content,
    })

    local rowObjects, rows, signature, raw = {}, {}, nil, {}
    local handle = { _listeners = {} }

    -- Fits the list to its first MaxRows rows, measured, so wrapped rows count
    -- at their real height. Past MaxRows the list scrolls.
    local function fit()
        if handle._destroyed then
            return
        end
        local scale = window.Scale.Scale
        local count = #rows
        local height = 0
        if count == 0 then
            height = empty.AbsoluteSize.Y / scale
        else
            local shown = math.min(count, maxRows)
            for index = 1, shown do
                height += rowObjects[index].Frame.AbsoluteSize.Y / scale
            end
            height += (shown - 1) * 2
        end
        height = math.ceil(height)
        local scrolling = count > maxRows
        scroller.ScrollingEnabled = scrolling
        contentPadding.PaddingRight = UDim.new(0, scrolling and 8 or 0)
        if scroller.Size.Y.Offset ~= height then
            scroller.Size = UDim2.new(1, 0, 0, height)
        end
        local maxScroll = math.max(scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y, 0) / scale
        if scroller.CanvasPosition.Y > maxScroll then
            scroller.CanvasPosition = Vector2.new(0, maxScroll)
        end
    end

    local function fitText(row)
        if row.Value.Visible then
            row.Text.Size = UDim2.new(1, -(math.ceil(row.Value.AbsoluteSize.X / window.Scale.Scale) + 12), 0, 24)
        else
            row.Text.Size = UDim2.new(1, 0, 0, 24)
        end
    end

    local function newRow(order)
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = content,
        })
        local row = {
            Frame = holder,
            Text = label({
                Size = UDim2.new(1, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.Y,
                Text = "",
                TextSize = 13,
                LineHeight = 1.1,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                TextWrapped = true,
                TextTruncate = Enum.TextTruncate.None,
                RichText = true,
                Parent = holder,
            }),
            Value = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = "",
                TextSize = 12,
                FontFace = Fonts.Medium,
                TextColor3 = Theme.Text,
                RichText = true,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.None,
                Visible = false,
                Parent = holder,
            }),
        }
        row.Connections = {
            holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit),
            row.Value:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                fitText(row)
            end),
        }
        return row
    end

    local function normalizeRow(entry)
        if type(entry) == "table" then
            local text = entry.Text or entry.Name or entry[1]
            local tone = entry.Tone or entry.Color
            return {
                Text = tostring(text == nil and "" or text),
                Value = entry.Value ~= nil and tostring(entry.Value) or nil,
                Tone = (type(tone) == "string" or typeof(tone) == "Color3") and tone or nil,
            }
        end
        return { Text = tostring(entry) }
    end

    local function rowKey(entry)
        return entry.Text .. "\0" .. (entry.Value or "\1") .. "\0" .. tostring(entry.Tone or "")
    end

    -- Tone tints the value, or the text when there is no value.
    local function paint(row, entry)
        local key = rowKey(entry)
        if row.Key == key then
            return
        end
        row.Key = key
        row.Text.Text = Library._rich(entry.Text)
        local tone = entry.Tone and Library._color(entry.Tone) or nil
        if entry.Value then
            row.Value.Text = Library._rich(entry.Value)
            row.Value.Visible = true
            tween(row.Value, { TextColor3 = tone or Theme.Text }, 0)
            tween(row.Text, { TextColor3 = Theme.Muted }, 0)
        else
            row.Value.Visible = false
            tween(row.Text, { TextColor3 = tone or Theme.Muted }, 0)
        end
        fitText(row)
    end

    local function dropRow(row)
        for _, connection in ipairs(row.Connections) do
            connection:Disconnect()
        end
        row.Frame:Destroy()
    end

    function handle:Set(list)
        if type(list) ~= "table" or handle._destroyed then
            return
        end
        local nextRows, keys = {}, {}
        raw = {}
        for index, entry in ipairs(list) do
            raw[index] = type(entry) == "table" and table.clone(entry) or entry
            local row = normalizeRow(entry)
            nextRows[index] = row
            keys[index] = rowKey(row)
        end
        local nextSignature = table.concat(keys, "\2") .. "#" .. #nextRows
        if nextSignature == signature then
            return
        end
        signature = nextSignature
        rows = nextRows
        for index, entry in ipairs(rows) do
            local row = rowObjects[index]
            if not row then
                row = newRow(index)
                rowObjects[index] = row
            end
            paint(row, entry)
        end
        for index = #rowObjects, #rows + 1, -1 do
            dropRow(rowObjects[index])
            rowObjects[index] = nil
        end
        empty.Visible = #rows == 0
        fit()
    end
    function handle:Get()
        local copy = {}
        for index, entry in ipairs(raw) do
            copy[index] = type(entry) == "table" and table.clone(entry) or entry
        end
        return copy
    end
    function handle:Clear()
        handle:Set({})
    end
    function handle:SetName(text)
        text = tostring(text or "")
        heading.Text = string.upper(text)
        heading.Visible = text ~= ""
        handle._searchName = text
        handle._searchKey = string.lower(text)
    end
    local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
    function handle:SetUpdateRate(seconds)
        rate = math.max(tonumber(seconds) or rate, 0.05)
    end

    -- Theme tags are baked into the text, so a theme change repaints the rows.
    onTheme(content, function()
        for index, row in ipairs(rowObjects) do
            if rows[index] then
                row.Key = nil
                paint(row, rows[index])
            end
        end
    end)

    local emptyConnection = empty:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    table.insert(handle._listeners, function()
        handle._destroyed = true
        emptyConnection:Disconnect()
        for _, row in ipairs(rowObjects) do
            for _, connection in ipairs(row.Connections) do
                connection:Disconnect()
            end
        end
    end)

    -- Refreshes only while someone can see it: window open and not minimized,
    -- its tab and sub tab showing, and neither it nor its groupbox hidden.
    local function onScreen()
        if window._destroyed or not window.Open or window.Minimized or not handle._userVisible then
            return false
        end
        local page = self
        if page._groupbox then
            if page._userVisible == false then
                return false
            end
            page = page.Parent
        end
        if page._isSubTab then
            if page.Parent.CurrentSubTab ~= page then
                return false
            end
            page = page.Parent
        end
        return window.CurrentTab == page
    end

    if type(opts.Update) == "function" then
        local alive = true
        table.insert(handle._listeners, function()
            alive = false
        end)
        task.defer(function()
            local first = true
            while alive and frame.Parent do
                if first or onScreen() then
                    first = false
                    local ok, result = isolatedCall(opts.Update)
                    if ok then
                        if result ~= nil then
                            handle:Set(result)
                        end
                    else
                        warn("[AirFlow] status list update error: " .. tostring(result))
                    end
                end
                task.wait(rate)
            end
        end)
    end

    handle:Set(opts.Rows or {})
    return finishElement(self, opts, handle, frame, "StatusList")
end

Tab.CreateStatus = Tab.Status
Tab.AddStatus = Tab.Status
Tab.CreateStatuses = Tab.Statuses
Tab.CreateStatusList = Tab.StatusList
Tab.AddStatusList = Tab.StatusList

-- Image and Viewport: media cards. Image shows a picture from the same sources
-- as window backgrounds, plus "Avatar" for the player's headshot. Viewport
-- shows a 3D model or the player's avatar, turning slowly; drag it to spin it
-- by hand.

function Tab:_mediaCard(opts, defaultHeight)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local mediaHeight = math.clamp(tonumber(opts.Height) or defaultHeight, 40, 600)
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local mediaTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local height = mediaTop + mediaHeight + (compact and 6 or inset)
    local frame, frameStroke = card(self, "Frame", height, opts)
    hoverStroke(frame, frameStroke)
    local title, descLabel
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            descLabel = label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    local media = create("Frame", {
        Position = UDim2.fromOffset(inset, mediaTop),
        Size = UDim2.new(1, -inset * 2, 0, mediaHeight),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(media, UDim.new(0, 6))
    stroke(media, Theme.Stroke)
    local placeholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 0.3,
        ScaleType = Enum.ScaleType.Fit,
        Parent = media,
    })
    -- A caption over the bottom of the picture, on a dark fade.
    local captionHolder = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3,
        Parent = media,
    })
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(1, 0),
        Parent = captionHolder,
    })
    local caption = label({
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 1, -10),
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
        ZIndex = 4,
        Parent = captionHolder,
    })
    local function setCaption(text)
        text = text ~= nil and tostring(text) or ""
        caption.Text = text
        captionHolder.Visible = text ~= ""
    end
    setCaption(opts.Caption)
    return opts, {
        Frame = frame,
        Stroke = frameStroke,
        Media = media,
        Placeholder = placeholder,
        Title = title,
        Desc = descLabel,
        SetCaption = setCaption,
    }
end

function Tab:Image(opts)
    local parts
    opts, parts = self:_mediaCard(opts, 160)
    local window = self.Window
    local media = parts.Media
    applyIcon(parts.Placeholder, "image")
    -- Enum lookups throw on unknown names.
    local function scaleType(name, fallback)
        local ok, value = pcall(function()
            return Enum.ScaleType[tostring(name)]
        end)
        return ok and value or fallback
    end
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        ScaleType = scaleType(opts.ScaleType or "Crop", Enum.ScaleType.Crop),
        ZIndex = 2,
        Parent = media,
    })
    corner(image, UDim.new(0, 6))
    if opts.Color then
        image.ImageColor3 = opts.Color
    end

    local handle = { Value = nil }
    local generation = 0

    -- Yields while a web image downloads. Returns ok, err like SetBackground.
    function handle:SetImage(source)
        generation += 1
        local current = generation
        handle.Value = source
        if source == nil or source == "" or source == "None" then
            tween(image, { ImageTransparency = 1 }, 0.2)
            tween(parts.Placeholder, { ImageTransparency = 0.3 }, 0.2)
            return true
        end
        local asset, err
        if type(source) == "number" then
            asset = "rbxassetid://" .. math.floor(source)
        elseif type(source) == "string" and ({ avatar = true, headshot = true })[source:lower()] then
            asset = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=420&h=420"
        else
            local ok, result, message = pcall(window._resolveBackground, window, tostring(source))
            if ok then
                asset, err = result, message
            else
                err = tostring(result)
            end
        end
        if generation ~= current then
            return false, "replaced by a newer image"
        end
        if not asset then
            warn("[AirFlow] image: " .. tostring(err))
            return false, err
        end
        image.ImageTransparency = 1
        image.Image = asset
        -- Fade in once it has loaded, or after a few seconds regardless.
        task.spawn(function()
            local waited = 0
            while not image.IsLoaded and waited < 4 and generation == current and image.Parent do
                waited += task.wait(0.05)
            end
            if generation == current and image.Parent then
                tween(image, { ImageTransparency = 0 }, 0.35)
                tween(parts.Placeholder, { ImageTransparency = 1 }, 0.2)
            end
        end)
        return true
    end
    handle.Set = handle.SetImage

    function handle:Get()
        return handle.Value
    end

    function handle:SetCaption(text)
        parts.SetCaption(text)
    end

    function handle:SetScaleType(name)
        image.ScaleType = scaleType(name, image.ScaleType)
    end

    function handle:SetColor(color)
        image.ImageColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
    end

    function handle:SetTitle(text)
        if parts.Title then
            parts.Title.Text = tostring(text)
        end
    end

    if opts.Image ~= nil then
        task.spawn(handle.SetImage, handle, opts.Image)
    end
    return finishElement(self, opts, handle, parts.Frame, "Image")
end

function Tab:Viewport(opts)
    local parts
    opts, parts = self:_mediaCard(opts, 180)
    local window = self.Window
    local media = parts.Media
    applyIcon(parts.Placeholder, "box")

    local viewport = create("ViewportFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        Ambient = opts.Ambient or Color3.fromRGB(165, 160, 175),
        LightColor = opts.LightColor or Color3.fromRGB(255, 250, 245),
        LightDirection = Vector3.new(-0.6, -1, -0.8),
        ZIndex = 2,
        Parent = media,
    })
    local camera = Instance.new("Camera")
    camera.FieldOfView = math.clamp(tonumber(opts.FieldOfView) or 35, 10, 90)
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    local world = Instance.new("WorldModel")
    world.Parent = viewport

    local handle = {
        Model = nil,
        Spin = opts.Spin ~= false,
        SpinSpeed = tonumber(opts.SpinSpeed) or 25,
    }
    local angle = math.rad(tonumber(opts.Angle) or 0)
    local pitch = math.rad(tonumber(opts.Pitch) or 10)
    local distanceScale = tonumber(opts.Distance) or 1
    local center, distance, basis = nil, 10, CFrame.new()
    local source = nil
    local generation = 0
    local dragging, lastX, resumeAt = false, 0, 0

    local function place()
        if not center then
            return
        end
        local direction = basis:VectorToWorldSpace(Vector3.new(
            math.sin(angle) * math.cos(pitch),
            math.sin(pitch),
            -math.cos(angle) * math.cos(pitch)
        ))
        camera.CFrame = CFrame.lookAt(center + direction * distance, center)
    end

    local function fit(model)
        local cf, size
        if model:IsA("Model") then
            cf, size = model:GetBoundingBox()
            basis = model:GetPivot().Rotation
        elseif model:IsA("BasePart") then
            cf, size = model.CFrame, model.Size
            basis = model.CFrame.Rotation
        else
            return false
        end
        center = cf.Position
        local radius = math.max(size.Magnitude / 2, 0.5)
        distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * distanceScale
        place()
        return true
    end

    -- A copy with its scripts and sounds stripped and every part anchored.
    local function prepare(instance)
        local copy = instance
        if opts.Clone ~= false then
            local archivable = instance.Archivable
            pcall(function()
                instance.Archivable = true
            end)
            local ok, result = pcall(instance.Clone, instance)
            pcall(function()
                instance.Archivable = archivable
            end)
            copy = ok and result or nil
        end
        if not copy then
            return nil
        end
        local function clean(object)
            if object:IsA("LuaSourceContainer") or object:IsA("Sound") or object:IsA("ForceField") then
                object:Destroy()
            elseif object:IsA("BasePart") then
                object.Anchored = true
                object.CanCollide = false
            end
        end
        for _, object in ipairs(copy:GetDescendants()) do
            pcall(clean, object)
        end
        if copy:IsA("BasePart") then
            copy.Anchored = true
        end
        local humanoid = copy:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
        return copy
    end

    local function resolve(value)
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "string" and ({ avatar = true, player = true, character = true })[value:lower()] then
            value = LocalPlayer
        end
        if typeof(value) == "Instance" and value:IsA("Player") then
            local character = value.Character
            if not character then
                character = value.CharacterAdded:Wait()
                -- Let the body parts and accessories load in.
                task.wait(0.5)
            end
            value = character
        end
        return typeof(value) == "Instance" and value or nil
    end

    -- Yields while waiting for a character to spawn.
    function handle:SetModel(value)
        generation += 1
        local current = generation
        source = value
        if handle.Model then
            handle.Model:Destroy()
            handle.Model = nil
        end
        center = nil
        if value == nil then
            tween(viewport, { ImageTransparency = 1 }, 0.2)
            tween(parts.Placeholder, { ImageTransparency = 0.3 }, 0.2)
            return true
        end
        local instance = resolve(value)
        if generation ~= current then
            return false, "replaced by a newer model"
        end
        if not instance then
            return false, "no model to show"
        end
        local copy = prepare(instance)
        if not copy then
            return false, "could not copy the model"
        end
        copy.Parent = world
        handle.Model = copy
        if not fit(copy) then
            copy:Destroy()
            handle.Model = nil
            return false, "not a Model or a part"
        end
        viewport.ImageTransparency = 1
        tween(viewport, { ImageTransparency = 0 }, 0.35)
        tween(parts.Placeholder, { ImageTransparency = 1 }, 0.2)
        return true
    end
    handle.Set = handle.SetModel

    function handle:Get()
        return handle.Model
    end

    -- Copies the source again, e.g. after the character respawned or changed.
    function handle:Refresh()
        return handle:SetModel(source)
    end

    function handle:SetSpin(enabled)
        handle.Spin = enabled ~= false
    end

    function handle:SetSpinSpeed(degrees)
        handle.SpinSpeed = tonumber(degrees) or handle.SpinSpeed
    end

    function handle:SetAngle(degrees)
        angle = math.rad(tonumber(degrees) or 0)
        place()
    end

    function handle:SetCaption(text)
        parts.SetCaption(text)
    end

    function handle:SetTitle(text)
        if parts.Title then
            parts.Title.Text = tostring(text)
        end
    end

    media.InputBegan:Connect(function(input)
        if isPress(input) and handle.Model then
            dragging = true
            lastX = pointerPosition().X
        end
    end)
    window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            local x = pointerPosition().X
            angle -= (x - lastX) * 0.012
            lastX = x
            place()
        end
    end, handle)
    window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            resumeAt = os.clock() + 1.5
        end
    end, handle)
    window:_listen("Render", function(deltaTime)
        if handle.Spin and center and not dragging and os.clock() >= resumeAt and window.Open and not window.Minimized
            and parts.Frame.Visible then
            angle += math.rad(handle.SpinSpeed) * deltaTime
            place()
        end
    end, handle)

    if opts.Model ~= nil then
        task.spawn(handle.SetModel, handle, opts.Model)
    end
    return finishElement(self, opts, handle, parts.Frame, "Viewport")
end

-- Table: rows under a header, sortable by clicking a column. Rank = true adds
-- a # column with medals for the top three, for leaderboards.

function Tab:Table(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Data = "Rows", OnRowClick = "Callback" })
    local window = self.Window
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local rowHeight = tonumber(opts.RowHeight) or (TOUCH and 32 or 26)
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 8), 1)
    local headerHeight = TOUCH and 28 or 24
    local textSize = compact and 12 or 13
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local searchable = opts.Search ~= false
    local searchHeight = TOUCH and 30 or 26
    local searchTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local gridTop = searchTop + (searchable and searchHeight + 6 or 0)
    local bottom = compact and 6 or inset
    -- Editable: typed columns get editors in their cells, an Add row button
    -- sits under the grid and a remove column ends each row.
    local editable = opts.Editable == true
    if not editable and type(opts.Columns) == "table" then
        for _, column in ipairs(opts.Columns) do
            if type(column) == "table" and column.Type ~= nil then
                editable = true
                break
            end
        end
    end
    local canAdd = editable and opts.AllowAdd ~= false
    local canRemove = editable and opts.AllowRemove ~= false
    local addHeight = canAdd and (TOUCH and 30 or 26) + 6 or 0

    local frame, frameStroke = card(self, "Frame", gridTop + headerHeight + rowHeight + addHeight + bottom, opts)
    hoverStroke(frame, frameStroke)
    local title
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    -- Search: filters rows by any cell's text as you type. A count of what
    -- matches shows on the right while it filters.
    local query = ""
    local searchBox, searchCount
    if searchable then
        local holder = create("Frame", {
            Position = UDim2.fromOffset(inset, searchTop),
            Size = UDim2.new(1, -inset * 2, 0, searchHeight),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = frame,
        })
        holder:SetAttribute("NoDrag", true)
        corner(holder, UDim.new(0, 6))
        local searchStroke = stroke(holder)
        local iconHolder, searchIcon = glowIcon(holder, "search", Theme.Muted, UDim2.new(0, 9, 0.5, 0))
        iconHolder.Size = UDim2.fromOffset(13, 13)
        searchCount = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -9, 0, 0),
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Visible = false,
            Parent = holder,
        })
        searchBox = create("TextBox", {
            Position = UDim2.fromOffset(29, 0),
            Size = UDim2.new(1, -90, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = opts.SearchPlaceholder or "Search",
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClearTextOnFocus = false,
            Parent = holder,
        })
        searchBox.Focused:Connect(function()
            tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
        end)
        searchBox.FocusLost:Connect(function()
            tween(searchStroke, { Color = Theme.Stroke }, 0.2)
            tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
        end)
    end

    local grid = create("Frame", {
        Position = UDim2.fromOffset(inset, gridTop),
        Size = UDim2.new(1, -inset * 2, 0, headerHeight + rowHeight),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(grid, UDim.new(0, 6))
    stroke(grid, Theme.Stroke)
    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Parent = grid,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = header,
    })
    local body = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 1, -headerHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = grid,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = body,
    })
    local empty = label({
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 0, rowHeight),
        Text = opts.EmptyText or "Nothing here yet",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = grid,
    })
    local addButton
    if canAdd then
        addButton = create("TextButton", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, inset, 1, -bottom),
            Size = UDim2.new(1, -inset * 2, 0, addHeight - 6),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            Parent = frame,
        })
        addButton:SetAttribute("NoDrag", true)
        corner(addButton, UDim.new(0, 6))
        local addStroke = stroke(addButton)
        local addLabel = label({
            Size = UDim2.fromScale(1, 1),
            Text = "+  " .. tostring(opts.AddText or "Add row"),
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = addButton,
        })
        addButton.MouseEnter:Connect(function()
            tween(addLabel, { TextColor3 = Theme.Text }, 0.12)
            tween(addStroke, { Color = Theme.StrokeHover }, 0.12)
        end)
        addButton.MouseLeave:Connect(function()
            tween(addLabel, { TextColor3 = Theme.Muted }, 0.2)
            tween(addStroke, { Color = Theme.Stroke }, 0.2)
        end)
    end

    local handle = { Rows = {} }
    local shownCount = nil
    local columns, headerCells = {}, {}
    local pool = {}
    local sortKey, sortDescending = nil, false
    local shownHeight = nil
    local MEDALS = {
        Color3.fromRGB(245, 200, 90),
        Color3.fromRGB(200, 206, 218),
        Color3.fromRGB(214, 146, 96),
    }

    local function alignment(column)
        local align = type(column.Align) == "string" and column.Align:lower() or nil
        if align == "right" then
            return Enum.TextXAlignment.Right
        elseif align == "center" or align == "centre" then
            return Enum.TextXAlignment.Center
        end
        return Enum.TextXAlignment.Left
    end

    -- Widths: a number above 1 is pixels, up to 1 is a share of what the pixel
    -- columns leave, and the rest split whatever share is left.
    local function layoutColumns()
        local pixels, shares, autos = 0, 0, 0
        for _, column in ipairs(columns) do
            local width = tonumber(column.Width)
            if width and width > 1 then
                pixels += width
            elseif width and width > 0 then
                shares += width
            else
                autos += 1
            end
        end
        local left = math.max(1 - shares, 0)
        for _, column in ipairs(columns) do
            local width = tonumber(column.Width)
            local share
            if width and width > 1 then
                column.UDim = UDim.new(0, width)
            else
                share = (width and width > 0) and width or (autos > 0 and left / autos or 0)
                column.UDim = UDim.new(share, -pixels * share)
            end
        end
    end

    local function columnValue(row, column)
        if column.Rank or column.Remove then
            return nil
        end
        if row[1] ~= nil or column.Key == nil then
            return row[column.Index]
        end
        return row[column.Key]
    end

    local function display(value, column, row)
        if type(column.Format) == "function" then
            local ok, text = pcall(column.Format, value, row)
            if ok and text ~= nil then
                return tostring(text)
            end
        end
        if type(value) == "number" then
            local whole = value == math.floor(value)
            local text = whole and string.format("%d", value) or string.format("%.2f", value)
            -- Thousands separators on the whole part.
            local sign, int, rest = text:match("^(%-?)(%d+)(.*)$")
            if int then
                int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                return sign .. int .. rest
            end
            return text
        end
        if value == nil then
            return ""
        end
        return tostring(value)
    end

    local function paintHeader()
        for _, cell in ipairs(headerCells) do
            local column = cell.Column
            local active = sortKey ~= nil and sortKey == column
            tween(cell.Label, { TextColor3 = active and Theme.Text or Theme.Muted }, 0.15)
            cell.Arrow.Visible = active
            if active then
                tween(cell.Arrow, { Rotation = sortDescending and 0 or 180 }, 0.2, Enum.EasingStyle.Quint)
            end
        end
    end

    local function sortedRows()
        local list = {}
        for index, row in ipairs(handle.Rows) do
            list[index] = { Row = row, Index = index }
        end
        if sortKey then
            local column = sortKey
            table.sort(list, function(a, b)
                local x, y = columnValue(a.Row, column), columnValue(b.Row, column)
                local nx, ny = tonumber(x), tonumber(y)
                if nx and ny then
                    if nx ~= ny then
                        if sortDescending then
                            return nx > ny
                        end
                        return nx < ny
                    end
                elseif x ~= nil and y ~= nil then
                    local sx, sy = string.lower(tostring(x)), string.lower(tostring(y))
                    if sx ~= sy then
                        if sortDescending then
                            return sx > sy
                        end
                        return sx < sy
                    end
                elseif x ~= y then
                    -- Empty cells sink to the bottom either way.
                    return x ~= nil
                end
                return a.Index < b.Index
            end)
        end
        -- Ranks come from the full order, so filtering never renumbers them.
        for position, item in ipairs(list) do
            item.Rank = position
        end
        if query == "" then
            return list
        end
        local shown = {}
        for _, item in ipairs(list) do
            for _, column in ipairs(columns) do
                if not column.Rank and not column.Remove then
                    local text = display(columnValue(item.Row, column), column, item.Row)
                    text = string.lower((string.gsub(text, "<[^>]->", "")))
                    if string.find(text, query, 1, true) then
                        table.insert(shown, item)
                        break
                    end
                end
            end
        end
        return shown
    end

    local function setCell(row, column, value)
        if row[1] ~= nil or column.Key == nil then
            row[column.Index] = value
        else
            row[column.Key] = value
        end
    end

    local function columnKind(column)
        local kind = string.lower(tostring(column.Type or ""))
        if kind == "boolean" or kind == "bool" or kind == "switch" then
            return "toggle"
        elseif kind == "select" or kind == "option" then
            return "dropdown"
        end
        return kind
    end

    -- One option list per table, opened under a dropdown cell.
    local picker, pickerList, pickerAnchor, pickerSearch, pickerSearchHolder, pickerEmpty
    -- The option list is virtual like the dropdown's: a small pool of
    -- buttons is rebound to whichever options are in view.
    local pickerPool, pickerShown, pickerFit, pickerPick, pickerRender = {}, {}, nil, nil, nil
    local function closePicker()
        if picker then
            picker.Visible = false
            if pickerSearch:IsFocused() then
                pickerSearch:ReleaseFocus()
            end
        end
        pickerAnchor = nil
        if window._closePopup == closePicker then
            window._closePopup = nil
        end
    end
    local function placePicker()
        if not picker or not picker.Visible or not pickerAnchor then
            return
        end
        if not pickerAnchor.Parent or not pickerAnchor:IsDescendantOf(frame) then
            closePicker()
            return
        end
        local host = picker.Parent
        local scale = math.max(window.Scale.Scale, 0.01)
        local position = (pickerAnchor.AbsolutePosition - host.AbsolutePosition) / scale
        local size = pickerAnchor.AbsoluteSize / scale
        local hostSize = host.AbsoluteSize / scale
        local width, height = picker.Size.X.Offset, picker.Size.Y.Offset
        local y = position.Y + size.Y + 4
        if y + height > hostSize.Y - 8 and position.Y - 4 - height >= 8 then
            y = position.Y - 4 - height
        end
        picker.Position = UDim2.fromOffset(math.clamp(position.X, 8, math.max(hostSize.X - width - 8, 8)), y)
    end
    local function openPicker(anchor, row, column)
        if window._closePopup and window._closePopup ~= closePicker then
            window._closePopup()
        end
        if not picker then
            picker = create("Frame", {
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                ZIndex = 45,
                Visible = false,
            })
            picker:SetAttribute("NoDrag", true)
            corner(picker, UDim.new(0, 6))
            stroke(picker, Theme.Stroke)
            -- Search row, shown for Searchable columns.
            pickerSearchHolder = create("Frame", {
                Position = UDim2.fromOffset(4, 4),
                Size = UDim2.new(1, -8, 0, TOUCH and 28 or 24),
                BackgroundColor3 = Theme.Surface,
                BorderSizePixel = 0,
                ZIndex = 46,
                Visible = false,
                Parent = picker,
            })
            corner(pickerSearchHolder, UDim.new(0, 4))
            local searchStroke = stroke(pickerSearchHolder)
            local searchIconHolder, searchIcon = glowIcon(pickerSearchHolder, "search", Theme.Muted, UDim2.new(0, 8, 0.5, 0))
            searchIconHolder.Size = UDim2.fromOffset(12, 12)
            searchIconHolder.ZIndex = 47
            pickerSearch = create("TextBox", {
                Position = UDim2.fromOffset(26, 0),
                Size = UDim2.new(1, -32, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                PlaceholderText = "Search",
                PlaceholderColor3 = Theme.Muted,
                TextColor3 = Theme.Text,
                TextSize = 12,
                FontFace = Fonts.Regular,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ClearTextOnFocus = false,
                ZIndex = 47,
                Parent = pickerSearchHolder,
            })
            pickerSearch.Focused:Connect(function()
                tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
                tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
            end)
            pickerSearch.FocusLost:Connect(function(enterPressed)
                tween(searchStroke, { Color = Theme.Stroke }, 0.2)
                tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
                -- Enter picks the first match.
                if enterPressed and picker.Visible and pickerPick and pickerShown[1] ~= nil then
                    pickerPick(pickerShown[1])
                end
            end)
            pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
                if pickerFit then
                    pickerFit()
                end
            end)
            pickerEmpty = label({
                Size = UDim2.new(1, 0, 0, TOUCH and 28 or 24),
                Text = "No matches",
                TextSize = 12,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 47,
                Visible = false,
                Parent = picker,
            })
            pickerList = create("ScrollingFrame", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Theme.Accent,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                CanvasSize = UDim2.new(),
                ZIndex = 45,
                Parent = picker,
            })
            padding(pickerList, 4, 4, 4, 4)
            pickerList:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if pickerRender and picker.Visible then
                    pickerRender()
                end
            end)
            window:_listen("Began", function(input)
                if not picker.Visible then
                    return
                end
                if input.KeyCode == Enum.KeyCode.Escape then
                    closePicker()
                elseif isPress(input) and not pointInside(pointerPosition(), picker) then
                    closePicker()
                end
            end, handle)
            window:_listen("Render", placePicker, handle)
        end
        pickerPick = function(option)
            closePicker()
            if columnValue(row, column) ~= option then
                setCell(row, column, option)
                handle:_edited()
            end
        end
        local options = column.Options
        if type(options) == "function" then
            local ok, result = pcall(options, row)
            options = ok and result or nil
        end
        options = type(options) == "table" and options or {}
        local current = columnValue(row, column)
        local itemHeight = TOUCH and 28 or 24
        local step = itemHeight + 2
        local keys = {}
        -- Searchable = true always shows the search row; SearchAfter = n shows
        -- it once there are more than n options.
        local searchable = column.Searchable == true
            or (column.Searchable ~= false and tonumber(column.SearchAfter) ~= nil and #options > tonumber(column.SearchAfter))
        local searchHeight = searchable and (TOUCH and 28 or 24) + 4 or 0
        pickerSearchHolder.Visible = searchable
        pickerSearch.Text = ""
        pickerSearch.PlaceholderText = column.SearchPlaceholder or (#options > 6 and ("Search " .. #options .. " options") or "Search")
        local scale = math.max(window.Scale.Scale, 0.01)
        local width = math.max(anchor.AbsoluteSize.X / scale, searchable and 160 or 120)
        local maxShown = math.max(math.floor(tonumber(column.MaxRows) or 6), 1)

        local function poolEntry()
            local entry = {}
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, itemHeight),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                ZIndex = 46,
                Visible = false,
                Parent = pickerList,
            })
            corner(button, UDim.new(0, 4))
            entry.Button = button
            entry.Label = label({
                Position = UDim2.fromOffset(8, 0),
                Size = UDim2.new(1, -16, 1, 0),
                TextSize = 12,
                FontFace = Fonts.Regular,
                ZIndex = 47,
                Parent = button,
            })
            button.MouseEnter:Connect(function()
                tween(button, { BackgroundTransparency = 0.25 }, 0.1)
            end)
            button.MouseLeave:Connect(function()
                tween(button, { BackgroundTransparency = entry.Selected and 0.4 or 1 }, 0.2)
            end)
            button.MouseButton1Click:Connect(function()
                if entry.Option ~= nil and pickerPick then
                    pickerPick(entry.Option)
                end
            end)
            return entry
        end

        pickerRender = function()
            -- CanvasPosition is in screen pixels; undo any UIScale first.
            local logical = pickerList.CanvasSize.Y.Offset
            local scale = logical > 0 and pickerList.AbsoluteCanvasSize.Y / logical or 1
            -- Indices keep a stable slot (index mod count) so scrolling only
            -- rebinds rows at the edges rather than every row each step.
            local first = math.max(math.floor(pickerList.CanvasPosition.Y / scale / step), 1)
            local count = maxShown + 3
            for slot = 1, math.max(count, #pickerPool) do
                local index = slot <= count and first + (slot - first) % count or 0
                local option = slot <= count and pickerShown[index] or nil
                local entry = pickerPool[slot]
                if option == nil then
                    if entry then
                        entry.Button.Visible = false
                        entry.Option = nil
                    end
                else
                    if not entry then
                        entry = poolEntry()
                        pickerPool[slot] = entry
                    end
                    entry.Button.Position = UDim2.fromOffset(0, (index - 1) * step)
                    if entry.Option ~= option then
                        local selected = option == current
                        entry.Option = option
                        entry.Selected = selected
                        entry.Label.Text = tostring(option)
                        entry.Label.TextColor3 = selected and Theme.Accent or Theme.Text
                        entry.Button.BackgroundTransparency = selected and 0.4 or 1
                    end
                    entry.Button.Visible = true
                end
            end
        end

        pickerFit = function()
            local query = string.lower(trim(pickerSearch.Text))
            if query == "" then
                pickerShown = options
            else
                pickerShown = {}
                for _, option in ipairs(options) do
                    local key = keys[option]
                    if key == nil then
                        key = string.lower(tostring(option))
                        keys[option] = key
                    end
                    if string.find(key, query, 1, true) then
                        table.insert(pickerShown, option)
                    end
                end
            end
            local count = #pickerShown
            pickerEmpty.Visible = count == 0
            pickerEmpty.Position = UDim2.fromOffset(0, searchHeight + 4)
            pickerList.Position = UDim2.fromOffset(0, searchHeight)
            pickerList.Size = UDim2.new(1, 0, 1, -searchHeight)
            pickerList.CanvasSize = UDim2.fromOffset(0, math.max(count * step - 2, 0) + 8)
            pickerList.CanvasPosition = Vector2.zero
            picker.Size = UDim2.fromOffset(width, searchHeight + math.clamp(count, 1, maxShown) * step + 6)
            for _, entry in ipairs(pickerPool) do
                entry.Option = nil
            end
            pickerRender()
        end
        pickerFit()
        picker.Parent = window:_popupHost(frame)
        pickerAnchor = anchor
        picker.Visible = true
        window._closePopup = closePicker
        placePicker()
        if searchable and not TOUCH then
            task.defer(function()
                if picker.Visible and pickerAnchor == anchor then
                    pickerSearch:CaptureFocus()
                end
            end)
        end
    end

    local function editorBox(cell)
        local box = create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.new(1, -6, 1, -6),
            BackgroundColor3 = Theme.Surface,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Parent = cell,
        })
        box:SetAttribute("NoDrag", true)
        corner(box, UDim.new(0, 4))
        return box, stroke(box)
    end

    local function makeEditor(entry, column, cell)
        local kind = columnKind(column)
        if kind == "toggle" then
            local align = alignment(column)
            local anchorX = align == Enum.TextXAlignment.Right and 1 or (align == Enum.TextXAlignment.Center and 0.5 or 0)
            local switch = create("TextButton", {
                AnchorPoint = Vector2.new(anchorX, 0.5),
                Position = UDim2.new(anchorX, anchorX == 1 and -6 or 0, 0.5, 0),
                Size = UDim2.fromOffset(28, 16),
                BackgroundColor3 = Theme.Surface3,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                Parent = cell,
            })
            switch:SetAttribute("NoDrag", true)
            corner(switch, UDim.new(1, 0))
            local knob = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 2, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Parent = switch,
            })
            corner(knob, UDim.new(1, 0))
            switch.MouseButton1Click:Connect(function()
                local row = entry.Data
                if row then
                    setCell(row, column, columnValue(row, column) ~= true)
                    handle:_edited()
                end
            end)
            return { Kind = "Toggle", Switch = switch, Knob = knob }
        elseif kind == "dropdown" then
            local box = editorBox(cell)
            local chip = create("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                Parent = box,
            })
            local valueLabel = label({
                Position = UDim2.fromOffset(6, 0),
                Size = UDim2.new(1, -24, 1, 0),
                TextSize = textSize - 1,
                FontFace = Fonts.Regular,
                Parent = chip,
            })
            local arrow = create("ImageLabel", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -5, 0.5, 0),
                Size = UDim2.fromOffset(10, 10),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Muted,
                ScaleType = Enum.ScaleType.Fit,
                Parent = chip,
            })
            applyIcon(arrow, "chevron-down")
            chip.MouseButton1Click:Connect(function()
                if entry.Data then
                    if pickerAnchor == box and picker and picker.Visible then
                        closePicker()
                    else
                        openPicker(box, entry.Data, column)
                    end
                end
            end)
            return { Kind = "Dropdown", Label = valueLabel }
        end
        local numeric = kind == "number"
        local box, boxStroke = editorBox(cell)
        local input = create("TextBox", {
            Position = UDim2.fromOffset(6, 0),
            Size = UDim2.new(1, -12, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = column.Placeholder or "",
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = textSize - 1,
            FontFace = Fonts.Regular,
            TextXAlignment = alignment(column),
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClearTextOnFocus = false,
            Parent = box,
        })
        local editing = nil
        input.Focused:Connect(function()
            tween(boxStroke, { Color = Theme.Accent }, 0.15)
            editing = entry.Data
            if editing then
                local value = columnValue(editing, column)
                input.Text = value == nil and "" or tostring(value)
            end
        end)
        input.FocusLost:Connect(function()
            tween(boxStroke, { Color = Theme.Stroke }, 0.2)
            local row = editing
            editing = nil
            if not row then
                return
            end
            local value = input.Text
            if numeric then
                value = Library._parseAmount(value)
                if value == nil then
                    handle:_redraw()
                    return
                end
                if column.Integer then
                    value = math.floor(value + 0.5)
                end
                value = math.clamp(value, tonumber(column.Min) or -math.huge, tonumber(column.Max) or math.huge)
            end
            if value ~= columnValue(row, column) then
                setCell(row, column, value)
                handle:_edited()
            else
                handle:_redraw()
            end
        end)
        return { Kind = "Input", Input = input, Numeric = numeric }
    end

    local function makeRemove(entry, cell)
        local button = create("ImageButton", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = cell,
        })
        button:SetAttribute("NoDrag", true)
        applyIcon(button, "x")
        button.MouseEnter:Connect(function()
            tween(button, { ImageColor3 = Theme.Error }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { ImageColor3 = Theme.Muted }, 0.2)
        end)
        button.MouseButton1Click:Connect(function()
            local index = entry.Index
            if index and entry.Data and handle.Rows[index] == entry.Data then
                table.remove(handle.Rows, index)
                handle:_edited()
            end
        end)
        return { Kind = "Remove" }
    end

    local function updateEditor(editor, value, column, row)
        if editor.Kind == "Toggle" then
            local on = value == true
            tween(editor.Switch, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, 0.15)
            tween(editor.Knob, { Position = on and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }, 0.15, Enum.EasingStyle.Quint)
        elseif editor.Kind == "Dropdown" then
            editor.Label.Text = value == nil and (column.Placeholder or "Select") or tostring(value)
            editor.Label.TextColor3 = value == nil and Theme.Muted or Theme.Text
        elseif editor.Kind == "Input" and not editor.Input:IsFocused() then
            if value == nil then
                editor.Input.Text = ""
            else
                editor.Input.Text = editor.Numeric and display(value, column, row) or tostring(value)
            end
        end
    end

    local function newRow()
        local rowFrame = create("TextButton", {
            Size = UDim2.new(1, 0, 0, rowHeight),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            Parent = body,
        })
        -- The accent bar on a highlighted row sits beside the cells, outside
        -- their layout.
        local marker = create("Frame", {
            Position = UDim2.new(0, 3, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(0, 2, 1, -10),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = rowFrame,
        })
        corner(marker, UDim.new(1, 0))
        local cellsFrame = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Parent = rowFrame,
        })
        padding(cellsFrame, 10, 10)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = cellsFrame,
        })
        local entry = { Frame = rowFrame, Marker = marker, Cells = {}, Hover = false }
        for order, column in ipairs(columns) do
            local cell = create("Frame", {
                Size = UDim2.new(column.UDim.Scale, column.UDim.Offset, 1, 0),
                BackgroundTransparency = 1,
                LayoutOrder = order,
                Parent = cellsFrame,
            })
            local text = label({
                Size = UDim2.new(1, -6, 1, 0),
                TextSize = textSize,
                FontFace = column.Rank and Fonts.Bold or Fonts.Regular,
                TextColor3 = Theme.Text,
                TextXAlignment = alignment(column),
                RichText = not column.Rank,
                Parent = cell,
            })
            local badge
            if column.Rank then
                text.Size = UDim2.fromScale(1, 1)
                text.TextXAlignment = Enum.TextXAlignment.Center
                badge = create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(rowHeight - 8, rowHeight - 8),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ZIndex = 0,
                    Parent = cell,
                })
                corner(badge, UDim.new(1, 0))
            end
            local editor
            if column.Remove then
                text.Visible = false
                editor = makeRemove(entry, cell)
            elseif editable and column.Type ~= nil then
                text.Visible = false
                editor = makeEditor(entry, column, cell)
            end
            entry.Cells[order] = { Label = text, Badge = badge, Editor = editor }
        end
        local canTap = tapGuard(rowFrame, function()
            return body
        end)
        rowFrame.MouseEnter:Connect(function()
            entry.Hover = true
            tween(rowFrame, { BackgroundTransparency = 0.35 }, 0.1)
        end)
        rowFrame.MouseLeave:Connect(function()
            entry.Hover = false
            tween(rowFrame, {
                BackgroundColor3 = entry.Highlighted and Theme.Accent or Theme.Surface3,
                BackgroundTransparency = entry.Rest or 1,
            }, 0.2)
        end)
        rowFrame.MouseButton1Click:Connect(function()
            if entry.Data and canTap() then
                safeCall(opts.Callback, entry.Data, entry.Index)
            end
        end)
        return entry
    end

    local function fitHeight(instant)
        local count = shownCount or #handle.Rows
        local visible = math.clamp(count, 1, maxRows)
        local gridHeight = headerHeight + visible * rowHeight
        local total = gridTop + gridHeight + addHeight + bottom
        if shownHeight == total then
            return
        end
        local duration = (instant or shownHeight == nil) and 0 or 0.25
        shownHeight = total
        tween(grid, { Size = UDim2.new(1, -inset * 2, 0, gridHeight) }, duration, Enum.EasingStyle.Quint)
        tween(frame, { Size = UDim2.new(1, 0, 0, total) }, duration, Enum.EasingStyle.Quint)
    end

    local function render()
        local list = sortedRows()
        for position, item in ipairs(list) do
            local entry = pool[position]
            if not entry then
                entry = newRow()
                pool[position] = entry
            end
            local row = item.Row
            entry.Data = row
            entry.Index = item.Index
            entry.Frame.LayoutOrder = position
            entry.Frame.Visible = true
            local highlighted = row.Highlight == true
            if not highlighted and type(opts.Highlight) == "function" then
                local ok, result = pcall(opts.Highlight, row, item.Index)
                highlighted = ok and result == true
            end
            entry.Highlighted = highlighted
            entry.Rest = highlighted and 0.86 or (position % 2 == 0 and 0.78 or 1)
            if not entry.Hover then
                entry.Frame.BackgroundColor3 = highlighted and Theme.Accent or Theme.Surface3
                entry.Frame.BackgroundTransparency = entry.Rest
                bindColors(entry.Frame, { BackgroundColor3 = entry.Frame.BackgroundColor3 })
            end
            entry.Marker.BackgroundTransparency = highlighted and 0 or 1
            for order, column in ipairs(columns) do
                local cell = entry.Cells[order]
                if column.Rank then
                    local medal = MEDALS[item.Rank]
                    cell.Label.Text = tostring(item.Rank)
                    cell.Label.TextColor3 = medal and Color3.fromRGB(28, 22, 18) or Theme.Muted
                    bindColors(cell.Label, { TextColor3 = cell.Label.TextColor3 })
                    cell.Badge.BackgroundColor3 = medal or Theme.Surface3
                    cell.Badge.BackgroundTransparency = medal and 0.05 or 1
                elseif column.Remove then
                    -- The remove button needs no per-row state.
                else
                    local value = columnValue(row, column)
                    cell.Label.Text = Library._rich(display(value, column, row))
                    -- Column Color: a colour, a theme key or a function(value, row)
                    -- returning either. A row's Colors[key or index] beats it.
                    local wanted = column.Color
                    if type(wanted) == "function" then
                        local ok, result = pcall(wanted, value, row)
                        wanted = ok and result or nil
                    end
                    if type(row.Colors) == "table" then
                        local own = row.Colors[column.Key or column.Index]
                        if own == nil then
                            own = row.Colors[column.Index]
                        end
                        if own ~= nil then
                            wanted = own
                        end
                    end
                    local color = Library._color(wanted) or (highlighted and Theme.Accent or Theme.Text)
                    cell.Label.TextColor3 = color
                    bindColors(cell.Label, { TextColor3 = color })
                    if cell.Editor then
                        updateEditor(cell.Editor, value, column, row)
                    end
                end
            end
        end
        for position = #list + 1, #pool do
            pool[position].Frame.Visible = false
            pool[position].Data = nil
        end
        shownCount = #list
        empty.Visible = #list == 0
        empty.Text = (#list == 0 and query ~= "" and #handle.Rows > 0) and (opts.NoMatchText or "No rows match")
            or (opts.EmptyText or "Nothing here yet")
        if searchCount then
            searchCount.Visible = query ~= ""
            searchCount.Text = #list .. " / " .. #handle.Rows
        end
        fitHeight()
    end

    local function buildHeader()
        for _, cell in ipairs(headerCells) do
            cell.Frame:Destroy()
        end
        table.clear(headerCells)
        for _, entry in ipairs(pool) do
            entry.Frame:Destroy()
        end
        table.clear(pool)
        local row = header:FindFirstChild("Cells") or create("Frame", {
            Name = "Cells",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Parent = header,
        })
        if not row:FindFirstChildOfClass("UIListLayout") then
            padding(row, 10, 10)
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = row,
            })
        end
        for order, column in ipairs(columns) do
            local cell = create("TextButton", {
                Size = UDim2.new(column.UDim.Scale, column.UDim.Offset, 1, 0),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                LayoutOrder = order,
                Parent = row,
            })
            local align = column.Rank and Enum.TextXAlignment.Center or alignment(column)
            local right = align == Enum.TextXAlignment.Right
            local text = label({
                Size = UDim2.new(1, align == Enum.TextXAlignment.Center and 0 or -16, 1, 0),
                Position = UDim2.fromOffset(right and 16 or 0, 0),
                Text = string.upper(column.Name),
                TextSize = 12,
                FontFace = Fonts.Bold,
                TextColor3 = Theme.Muted,
                TextXAlignment = align,
                Parent = cell,
            })
            local arrow = create("ImageLabel", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Accent,
                ScaleType = Enum.ScaleType.Fit,
                Visible = false,
                Parent = cell,
            })
            applyIcon(arrow, "chevron-down")
            -- The arrow sits just after the header text (before it when the
            -- column is right aligned).
            local function placeArrow()
                local width = text.TextBounds.X
                if right then
                    arrow.Position = UDim2.new(1, -(width + 15), 0.5, 0)
                elseif align == Enum.TextXAlignment.Center then
                    arrow.Position = UDim2.new(0.5, width / 2 + 3, 0.5, 0)
                else
                    local cellWidth = cell.AbsoluteSize.X / math.max(window.Scale.Scale, 0.01)
                    arrow.Position = UDim2.new(0, math.clamp(width + 4, 0, math.max(cellWidth - 12, 0)), 0.5, 0)
                end
            end
            text:GetPropertyChangedSignal("TextBounds"):Connect(placeArrow)
            cell:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeArrow)
            task.defer(placeArrow)
            local sortable = column.Sortable and not column.Rank
            if sortable then
                cell.MouseEnter:Connect(function()
                    if sortKey ~= column then
                        tween(text, { TextColor3 = Theme.Text }, 0.12)
                    end
                end)
                cell.MouseLeave:Connect(function()
                    if sortKey ~= column then
                        tween(text, { TextColor3 = Theme.Muted }, 0.2)
                    end
                end)
                cell.MouseButton1Click:Connect(function()
                    -- Numbers sort high to low first, text A to Z; the second
                    -- click flips it and the third goes back to the given order.
                    if sortKey ~= column then
                        local numeric = false
                        for _, data in ipairs(handle.Rows) do
                            local value = columnValue(data, column)
                            if value ~= nil then
                                numeric = tonumber(value) ~= nil
                                break
                            end
                        end
                        sortKey, sortDescending = column, numeric
                        column.FirstDescending = numeric
                    elseif sortDescending == column.FirstDescending then
                        sortDescending = not sortDescending
                    else
                        sortKey = nil
                    end
                    paintHeader()
                    render()
                end)
            end
            table.insert(headerCells, { Frame = cell, Label = text, Arrow = arrow, Column = column })
        end
        paintHeader()
    end

    function handle:SetColumns(list)
        table.clear(columns)
        if opts.Rank then
            table.insert(columns, { Name = "#", Rank = true, Width = TOUCH and 40 or 36, Sortable = false })
        end
        for index, column in ipairs(type(list) == "table" and list or {}) do
            if type(column) ~= "table" then
                column = { Name = tostring(column) }
            end
            local name = column.Name or column.Title or ("Column " .. index)
            table.insert(columns, {
                Name = name,
                Key = column.Key or name,
                Index = index,
                Width = column.Width,
                Align = column.Align,
                Format = column.Format,
                Color = column.Color,
                Sortable = column.Sortable ~= false and opts.Sortable ~= false,
                Type = column.Type,
                Options = column.Options,
                Min = column.Min,
                Max = column.Max,
                Integer = column.Integer,
                Default = column.Default,
                Placeholder = column.Placeholder,
                Searchable = column.Searchable,
                SearchAfter = column.SearchAfter,
                SearchPlaceholder = column.SearchPlaceholder,
                MaxRows = column.MaxRows,
            })
        end
        if canRemove then
            table.insert(columns, { Name = "", Remove = true, Width = TOUCH and 30 or 26, Sortable = false })
        end
        closePicker()
        sortKey = nil
        layoutColumns()
        buildHeader()
        render()
    end

    local function findColumn(key)
        if type(key) == "number" then
            return columns[key + (opts.Rank and 1 or 0)]
        end
        for _, column in ipairs(columns) do
            if not column.Rank and (column.Key == key or column.Name == key) then
                return column
            end
        end
        return nil
    end

    local function changed()
        if editable then
            safeCall(opts.OnChanged, handle.Rows)
        end
    end

    -- An edit made in a cell: redraw, then tell the script.
    function handle:_edited()
        render()
        changed()
    end

    function handle:_redraw()
        render()
    end

    -- Saved through the config as plain copies of the rows.
    function handle:_saveValue()
        local list = {}
        for index, row in ipairs(handle.Rows) do
            list[index] = table.clone(row)
        end
        return list
    end

    function handle:SetRows(rows, silent)
        handle.Rows = {}
        for index, row in ipairs(type(rows) == "table" and rows or {}) do
            row = type(row) == "table" and row or { row }
            handle.Rows[index] = editable and table.clone(row) or row
        end
        render()
        if not silent then
            changed()
        end
    end
    handle.Set = handle.SetRows

    function handle:GetRows()
        return handle.Rows
    end
    handle.Get = handle.GetRows

    function handle:AddRow(row, position)
        row = type(row) == "table" and row or { row }
        if tonumber(position) then
            table.insert(handle.Rows, math.clamp(math.floor(position), 1, #handle.Rows + 1), row)
        else
            table.insert(handle.Rows, row)
        end
        render()
        return #handle.Rows
    end

    -- Replaces a row (by its index in the list you gave) and flashes it.
    function handle:UpdateRow(index, row)
        if not handle.Rows[index] then
            return false
        end
        handle.Rows[index] = type(row) == "table" and row or { row }
        render()
        for _, entry in ipairs(pool) do
            if entry.Index == index and entry.Frame.Visible then
                local restColor = entry.Highlighted and Theme.Accent or Theme.Surface3
                tween(entry.Frame, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.7 }, 0.08)
                task.delay(0.1, function()
                    if not entry.Hover then
                        tween(entry.Frame, { BackgroundColor3 = restColor, BackgroundTransparency = entry.Rest }, 0.5)
                    end
                end)
                break
            end
        end
        return true
    end

    function handle:RemoveRow(index)
        if not handle.Rows[index] then
            return false
        end
        table.remove(handle.Rows, index)
        render()
        return true
    end

    function handle:Clear()
        handle:SetRows({})
    end

    -- Sort(nil) goes back to the given order.
    function handle:Sort(key, descending)
        sortKey = key ~= nil and findColumn(key) or nil
        sortDescending = descending == true
        if sortKey then
            sortKey.FirstDescending = sortDescending
        end
        paintHeader()
        render()
    end

    function handle:SetTitle(text)
        if title then
            title.Text = tostring(text)
        end
    end

    function handle:SetMaxRows(count)
        maxRows = math.max(math.floor(tonumber(count) or maxRows), 1)
        fitHeight()
    end

    handle:SetColumns(opts.Columns or {})
    handle:SetRows(opts.Rows or {}, true)
    -- A new row: NewRow (a table or a function returning one), or each
    -- column's Default, falling back to off, Min or 0, the first option or "".
    function handle:NewRow()
        if type(opts.NewRow) == "function" then
            local ok, row = pcall(opts.NewRow)
            if ok and type(row) == "table" then
                return row
            end
        elseif type(opts.NewRow) == "table" then
            return table.clone(opts.NewRow)
        end
        local row = {}
        for _, column in ipairs(columns) do
            if not column.Rank and not column.Remove then
                local value = column.Default
                if value == nil then
                    local kind = columnKind(column)
                    if kind == "toggle" then
                        value = false
                    elseif kind == "number" then
                        value = tonumber(column.Min) or 0
                    elseif kind == "dropdown" then
                        value = type(column.Options) == "table" and column.Options[1] or nil
                    else
                        value = ""
                    end
                end
                row[column.Key] = value
            end
        end
        return row
    end
    if addButton then
        addButton.MouseButton1Click:Connect(function()
            if searchBox then
                searchBox.Text = ""
            end
            table.insert(handle.Rows, handle:NewRow())
            handle:_edited()
            task.defer(function()
                body.CanvasPosition = Vector2.new(0, 1e7)
            end)
        end)
    end
    if opts.SortBy ~= nil then
        handle:Sort(opts.SortBy, opts.SortDescending ~= false)
    end
    fitHeight(true)
    if searchBox then
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local text = string.lower(trim(searchBox.Text))
            if text ~= query then
                query = text
                body.CanvasPosition = Vector2.zero
                render()
            end
        end)
    end
    function handle:SetSearch(text)
        if searchBox then
            searchBox.Text = tostring(text or "")
        end
    end
    -- Theme tags in cells are baked to colours; repaint them on theme change.
    onTheme(grid, render)
    return finishElement(self, opts, handle, frame, "Table")
end


-- Log: a capped, scrolling list of timestamped lines, newest at the bottom.
-- It follows new lines while scrolled to the end and stays put otherwise.
function Tab:Log(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Max = "MaxEntries", Limit = "MaxEntries" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local lineHeight = TOUCH and 22 or 20
    local textSize = compact and 12 or 13
    local maxLines = math.max(math.floor(tonumber(opts.MaxRows or opts.Lines) or 6), 1)
    local maxEntries = math.max(math.floor(tonumber(opts.MaxEntries) or 100), 1)
    local listTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local bottom = compact and 6 or inset
    local listHeight = maxLines * lineHeight + 8
    local timestamps = opts.Timestamps ~= false

    local frame, frameStroke = card(self, "Frame", listTop + listHeight + bottom, opts)
    hoverStroke(frame, frameStroke)
    local title
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, listTop),
        Size = UDim2.new(1, -inset * 2, 0, listHeight),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(holder, UDim.new(0, 6))
    stroke(holder, Theme.Stroke)
    local list = create("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = holder,
    })
    padding(list, 8, 8, 4, 4)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })
    local empty = label({
        Size = UDim2.fromScale(1, 1),
        Text = opts.EmptyText or "Nothing logged yet",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })

    local handle = { Entries = {} }
    local lines = {}
    local counter = 0

    local function paint(entry)
        local line = lines[entry]
        if not line then
            return
        end
        local text = Library._rich(entry.Text)
        if timestamps then
            text = ('<font color="#%s">%s</font>  %s'):format(Theme.Muted:ToHex(), os.date(opts.TimeFormat or "%H:%M:%S", entry.Time), text)
        end
        line.Text = text
        line.TextColor3 = Library._color(entry.Color) or Theme.Text
    end

    local function trimTo(count)
        while #handle.Entries > count do
            local old = table.remove(handle.Entries, 1)
            if lines[old] then
                lines[old]:Destroy()
                lines[old] = nil
            end
        end
        empty.Visible = #handle.Entries == 0
    end

    local function atEnd()
        return list.CanvasPosition.Y >= list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y - 4
    end

    -- Push(text, color?): color is a Color3, "#rrggbb" or a theme key ("Success").
    function handle:Push(text, color)
        local follow = atEnd()
        counter += 1
        local entry = { Text = tostring(text == nil and "" or text), Color = color, Time = os.time() }
        table.insert(handle.Entries, entry)
        lines[entry] = label({
            Size = UDim2.new(1, 0, 0, lineHeight),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextSize = textSize,
            FontFace = Fonts.Regular,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            RichText = true,
            LayoutOrder = counter,
            Parent = list,
        })
        paint(entry)
        trimTo(maxEntries)
        if follow then
            task.defer(function()
                list.CanvasPosition = Vector2.new(0, 1e7)
            end)
        end
        return entry
    end
    handle.Add = handle.Push
    handle.Log = handle.Push

    function handle:Clear()
        trimTo(0)
    end

    -- Copies of the entries, oldest first: { Text, Color, Time }.
    function handle:Get()
        local copy = {}
        for index, entry in ipairs(handle.Entries) do
            copy[index] = { Text = entry.Text, Color = entry.Color, Time = entry.Time }
        end
        return copy
    end

    function handle:SetTitle(text)
        if title then
            title.Text = tostring(text)
        end
    end

    function handle:SetMaxEntries(count)
        maxEntries = math.max(math.floor(tonumber(count) or maxEntries), 1)
        trimTo(maxEntries)
    end

    onTheme(holder, function()
        for _, entry in ipairs(handle.Entries) do
            paint(entry)
        end
    end)
    return finishElement(self, opts, handle, frame, "Log")
end

Tab.CreateLog = Tab.Log
Tab.AddLog = Tab.Log
Tab.Feed = Tab.Log
Tab.CreateFeed = Tab.Log
Tab.AddFeed = Tab.Log

Tab.CreateImage = Tab.Image
Tab.AddImage = Tab.Image
Tab.CreateViewport = Tab.Viewport
Tab.AddViewport = Tab.Viewport
Tab.CreateTable = Tab.Table
Tab.AddTable = Tab.Table
Tab.CreateLeaderboard = Tab.Table

local function settleSubOut(ui)
    if ui.OutFrame then
        ui.OutFrame.Parent = ui.Area
        ui.OutFrame.Visible = false
        ui.OutFrame = nil
    end
    ui.Out.Visible = false
end

local function settleSubIn(ui)
    if ui.InFrame then
        ui.InFrame.Parent = ui.Area
        ui.InFrame.Position = UDim2.fromOffset(0, 0)
        ui.InFrame = nil
    end
    ui.In.Visible = false
end

function Tab:_setupSubTabs()
    local top = self._headerBottom
    local page = self._page
    local strip = create("ScrollingFrame", {
        Name = "SubTabs",
        Position = UDim2.fromOffset(24, top - 4),
        Size = UDim2.new(1, -48, 0, 32),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
        Parent = page,
    })
    strip:SetAttribute("NoDrag", true)
    local highlight = create("Frame", {
        Size = UDim2.fromOffset(0, 32),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        Parent = strip,
    })
    corner(highlight, UDim.new(0, 8))
    stroke(highlight, Theme.Stroke)
    local row = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = strip,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = row,
    })
    self.Window:_overflowHint(page, strip, row, false, Theme.Background)
    local areaTop = top + 36
    local area = create("Frame", {
        Name = "SubPages",
        Position = UDim2.fromOffset(0, areaTop),
        Size = UDim2.new(1, 0, 1, -areaTop),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = page,
    })
    local ui = {
        Strip = strip,
        Row = row,
        Highlight = highlight,
        Area = area,
        Out = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 2,
            Parent = area,
        }),
        In = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 3,
            Parent = area,
        }),
        Generation = 0,
    }
    self._sub = ui
    self._subTabs = {}
    self.List.Visible = false
    self:_refreshEmpty()
    -- Keep the pill under the selected tab when widths change after layout.
    row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if self.CurrentSubTab and not ui.Moving then
            self:_placeSubHighlight(self.CurrentSubTab, true)
        end
    end)
end

function Tab:_placeSubHighlight(sub, instant)
    local ui = self._sub
    local scale = self.Window.Scale.Scale
    local button = sub._button
    local width = button.AbsoluteSize.X / scale
    if width <= 0 then
        return
    end
    local x = (button.AbsolutePosition.X - ui.Row.AbsolutePosition.X) / scale
    local props = { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(width, 32) }
    if instant or not ui.Highlight.Visible then
        ui.Highlight.Visible = true
        ui.Highlight.Position = props.Position
        ui.Highlight.Size = props.Size
    else
        ui.Moving = true
        tween(ui.Highlight, props, 0.35, Enum.EasingStyle.Quint)
        task.delay(0.36, function()
            ui.Moving = false
        end)
    end
    local view = ui.Strip.AbsoluteSize.X / scale
    local canvasX = ui.Strip.CanvasPosition.X
    if x < canvasX then
        tween(ui.Strip, { CanvasPosition = Vector2.new(math.max(x - 8, 0), 0) }, 0.3, Enum.EasingStyle.Quint)
    elseif x + width > canvasX + view then
        tween(ui.Strip, { CanvasPosition = Vector2.new(x + width - view + 8, 0) }, 0.3, Enum.EasingStyle.Quint)
    end
end

function Tab:SubTab(opts, icon)
    if self._groupbox or self._isSubTab then
        return self.Parent:SubTab(opts, icon)
    end
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = icon
    end
    if not self._subTabs then
        self:_setupSubTabs()
    end
    local ui = self._sub
    local index = #self._subTabs + 1
    local sub = setmetatable({
        Name = opts.Name or ("Page " .. index),
        Window = self.Window,
        Parent = self,
        _order = 0,
        _isSubTab = true,
        _index = index,
        _iconName = opts.Icon,
    }, Tab)
    local frame = create("Frame", {
        Name = sub.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = ui.Area,
    })
    sub._frame = frame
    buildContainer(sub, frame, 0, opts.Icon or self._iconName or "layout-grid", opts.EmptyText or "Nothing here yet")

    local button = create("TextButton", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = index,
        Parent = ui.Row,
    })
    padding(button, 14, 14)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = button,
    })
    if opts.Icon then
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = button,
        })
        applyIcon(image, opts.Icon)
        if image:GetAttribute("CustomIcon") then
            image.ImageTransparency = 0.4
        end
        sub._iconImage = image
    end
    sub._label = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = sub.Name,
        TextSize = 13,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = button,
    })
    sub._button = button
    button.MouseEnter:Connect(function()
        if self.CurrentSubTab ~= sub then
            tween(sub._label, { TextColor3 = Theme.Text }, 0.12)
        end
    end)
    button.MouseLeave:Connect(function()
        if self.CurrentSubTab ~= sub then
            tween(sub._label, { TextColor3 = Theme.Muted }, 0.2)
        end
    end)
    button.MouseButton1Click:Connect(function()
        self:SelectSubTab(sub)
    end)

    table.insert(self._subTabs, sub)
    if index == 1 then
        self:SelectSubTab(sub, true)
    end
    return sub
end

Tab.CreateSubTab = Tab.SubTab
Tab.AddSubTab = Tab.SubTab

function Tab:SelectSubTab(sub, instant)
    if type(sub) ~= "table" then
        for index, entry in ipairs(self._subTabs or {}) do
            if entry.Name == sub or index == sub then
                sub = entry
                break
            end
        end
    end
    if type(sub) ~= "table" or not self._sub then
        return
    end
    local previous = self.CurrentSubTab
    if previous == sub then
        return
    end
    self.Window:_resetSearch()
    self.Window:_closePopups()
    self.CurrentSubTab = sub
    local ui = self._sub
    settleSubOut(ui)
    settleSubIn(ui)
    ui.Generation += 1
    local generation = ui.Generation

    local fade = instant and 0 or 0.2
    if previous then
        tween(previous._label, { TextColor3 = Theme.Muted }, fade)
        if previous._iconImage then
            tintIcon(previous._iconImage, Theme.Muted, false, fade)
        end
    end
    tween(sub._label, { TextColor3 = Theme.Text }, fade)
    if sub._iconImage then
        tintIcon(sub._iconImage, Theme.Accent, true, fade)
    end
    self:_placeSubHighlight(sub, instant)

    if instant or not previous then
        if previous then
            previous._frame.Visible = false
        end
        sub._frame.Visible = true
        return
    end

    local direction = sub._index > previous._index and 1 or -1
    ui.OutFrame = previous._frame
    previous._frame.Parent = ui.Out
    ui.Out.GroupTransparency = 0
    ui.Out.Position = UDim2.fromOffset(0, 0)
    ui.Out.Visible = true
    tween(ui.Out, { GroupTransparency = 1, Position = UDim2.fromOffset(-direction * 28, 0) }, 0.2)

    ui.InFrame = sub._frame
    sub._frame.Visible = true
    sub._frame.Parent = ui.In
    ui.In.GroupTransparency = 1
    ui.In.Position = UDim2.fromOffset(direction * 28, 0)
    ui.In.Visible = true
    tween(ui.In, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.34, Enum.EasingStyle.Quint)

    task.delay(0.2, function()
        if ui.Generation == generation then
            settleSubOut(ui)
        end
    end)
    task.delay(0.34, function()
        if ui.Generation == generation then
            settleSubIn(ui)
        end
    end)
end

-- Search: one box over the whole window. Typing lists matching tabs, pages,
-- groupboxes and controls from every tab; picking one opens its tab and page,
-- scrolls it into view and flashes it.

Window._searchIcons = {
    Tab = "app-window",
    Page = "panels-top-left",
    Groupbox = "layout-grid",
    Button = "mouse-pointer-click",
    ButtonRow = "mouse-pointer-click",
    Toggle = "toggle-right",
    Slider = "sliders-horizontal",
    Dropdown = "list",
    Input = "text-cursor-input",
    Keybind = "keyboard",
    ColorPicker = "palette",
    Stepper = "chevrons-up-down",
    Progress = "activity",
    Status = "activity",
    StatusList = "activity",
    Label = "type",
    Paragraph = "type",
    OrderList = "list-ordered",
}

function Window:_searchResults(query)
    local results = {}
    local function consider(name, entry)
        if type(name) ~= "string" or name == "" then
            return
        end
        local at = string.find(string.lower(name), query, 1, true)
        if not at then
            return
        end
        entry.Name = name
        entry.At = at
        -- Name starts first, then word starts, then anywhere inside a word.
        entry.Rank = at == 1 and 0 or (string.find(string.sub(name, at - 1, at - 1), "[%s%p]") and 1 or 2)
        entry.Order = #results + 1
        table.insert(results, entry)
    end
    local function shown(element)
        return not element._destroyed
            and element._type ~= "Section" and element._type ~= "Divider"
            and (element._isShown == nil or element:_isShown())
    end
    for _, tab in ipairs(self.Tabs) do
        consider(tab.Name, { Kind = "Tab", Tab = tab, Icon = tab._iconName })
        for _, page in ipairs(tab._subTabs or { tab }) do
            local sub = page._isSubTab and page or nil
            local path = tab.Name
            if sub then
                consider(sub.Name, { Kind = "Page", Tab = tab, Sub = sub, Path = tab.Name })
                path = tab.Name .. "  ›  " .. sub.Name
            end
            if not page._noSearch then
                for _, element in ipairs(page._items or {}) do
                    if shown(element) then
                        consider(element._searchName, { Kind = element._type, Tab = tab, Sub = sub, Target = element, Path = path })
                    end
                end
                for _, group in ipairs(page._groupboxes or {}) do
                    if group._userVisible ~= false then
                        consider(group.Name, { Kind = "Groupbox", Tab = tab, Sub = sub, Target = group, Path = path })
                        local groupPath = path .. "  ›  " .. group.Name
                        for _, element in ipairs(group._items) do
                            if shown(element) then
                                consider(element._searchName, { Kind = element._type, Tab = tab, Sub = sub, Target = element, Group = group, Path = groupPath })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b)
        if a.Rank ~= b.Rank then
            return a.Rank < b.Rank
        end
        return a.Order < b.Order
    end)
    return results
end

-- Marks a found control: it pops, a soft accent glow blooms around it, a
-- sheen of light sweeps across it and a bright spot runs round its border,
-- then everything breathes once more and fades.
function Window:_flash(frame, radius)
    for _, name in ipairs({ "SearchFlash", "SearchGlow" }) do
        local old = frame:FindFirstChild(name)
        if old then
            old:Destroy()
        end
    end
    radius = radius or 8
    local accent = Theme.Accent
    local bright = accent:Lerp(Color3.new(1, 1, 1), 0.65)

    -- Outer glow: a wide, faint stroke around a second outline.
    local halo = create("Frame", {
        Name = "SearchGlow",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 10,
        Parent = frame,
    })
    corner(halo, UDim.new(0, radius))
    local haloStroke = create("UIStroke", {
        Color = accent,
        Thickness = 1,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = halo,
    })

    -- Wash with a moving sheen: a brighter diagonal band crosses it once.
    local wash = create("Frame", {
        Name = "SearchFlash",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10,
        Parent = frame,
    })
    corner(wash, UDim.new(0, radius))
    local sheen = create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.7),
            NumberSequenceKeypoint.new(0.4, 0.55),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(0.6, 0.55),
            NumberSequenceKeypoint.new(1, 0.7),
        }),
        Rotation = 18,
        Offset = Vector2.new(-1, 0),
        Parent = wash,
    })

    -- Border light: the ring's gradient turns, so a bright spot runs round it.
    local ring = create("UIStroke", {
        Color = Color3.new(1, 1, 1),
        Thickness = 1.6,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = wash,
    })
    local runner = create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, accent),
            ColorSequenceKeypoint.new(0.5, bright),
            ColorSequenceKeypoint.new(1, accent),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.45),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 0.45),
        }),
        Parent = ring,
    })

    -- Groupboxes clip their rows, so anything drawn outside a control is cut
    -- off at its corners. The strokes go on the inside of the control where
    -- the engine supports it; otherwise everything is inset by its width.
    local inside = pcall(function()
        haloStroke.BorderStrokePosition = Enum.BorderStrokePosition.Inner
        ring.BorderStrokePosition = Enum.BorderStrokePosition.Inner
    end)
    local glowWidth = inside and 6 or 3
    if not inside then
        halo.Position = UDim2.fromOffset(glowWidth + 1, glowWidth + 1)
        halo.Size = UDim2.new(1, -(glowWidth + 1) * 2, 1, -(glowWidth + 1) * 2)
        wash.Position = UDim2.fromOffset(2, 2)
        wash.Size = UDim2.new(1, -4, 1, -4)
    end

    -- A small pop, unless something else is scaling the control already. It
    -- never grows past full size, which would be clipped as well.
    local pop
    if not frame:FindFirstChildOfClass("UIScale") then
        pop = create("UIScale", { Scale = 0.975, Parent = frame })
        tween(pop, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
    end

    tween(wash, { BackgroundTransparency = 0.8 }, 0.2, Enum.EasingStyle.Quad)
    tween(ring, { Transparency = 0 }, 0.2, Enum.EasingStyle.Quad)
    tween(haloStroke, { Thickness = glowWidth, Transparency = 0.72 }, 0.35, Enum.EasingStyle.Quint)
    tween(sheen, { Offset = Vector2.new(1, 0) }, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    tween(runner, { Rotation = 540 }, 2.2, Enum.EasingStyle.Quad)
    task.spawn(function()
        task.wait(0.75)
        -- One softer breath, then fade out.
        tween(wash, { BackgroundTransparency = 0.9 }, 0.35, Enum.EasingStyle.Sine)
        tween(haloStroke, { Thickness = glowWidth / 2, Transparency = 0.85 }, 0.35, Enum.EasingStyle.Sine)
        task.wait(0.35)
        tween(wash, { BackgroundTransparency = 0.84 }, 0.3, Enum.EasingStyle.Sine)
        tween(haloStroke, { Thickness = glowWidth * 0.85, Transparency = 0.76 }, 0.3, Enum.EasingStyle.Sine)
        task.wait(0.4)
        tween(wash, { BackgroundTransparency = 1 }, 0.55, Enum.EasingStyle.Quad)
        tween(ring, { Transparency = 1 }, 0.65, Enum.EasingStyle.Quad)
        tween(haloStroke, { Thickness = glowWidth, Transparency = 1 }, 0.65, Enum.EasingStyle.Quad)
        task.wait(0.7)
        wash:Destroy()
        halo:Destroy()
        if pop then
            pop:Destroy()
        end
    end)
end

function Window:_revealResult(result)
    local tab, sub, target, group = result.Tab, result.Sub, result.Target, result.Group
    if self.CurrentTab ~= tab then
        self:SelectTab(tab)
    end
    if sub then
        tab:SelectSubTab(sub)
    end
    if not target then
        local button = sub and sub._button or tab._button
        task.delay(0.1, function()
            if button.Parent then
                self:_flash(button, sub and 8 or 10)
            end
        end)
        return
    end
    local expanding = group ~= nil and group:IsCollapsed()
    if expanding then
        group:Expand()
    end
    local list = (sub or tab).List
    task.spawn(function()
        -- Let the freshly shown page lay out before measuring it.
        task.wait()
        task.wait()
        if expanding then
            task.wait(0.3)
        end
        local frame = target._frame
        if self._destroyed or target._destroyed or not frame or not frame.Parent or not list then
            return
        end
        local scale = self.Scale.Scale
        local top = (frame.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
        local height = frame.AbsoluteSize.Y / scale
        local view = list.AbsoluteWindowSize.Y / scale
        local limit = math.max(list.AbsoluteCanvasSize.Y / scale - view, 0)
        local y = math.clamp(top + height / 2 - view / 2, 0, limit)
        if math.abs(y - list.CanvasPosition.Y) > 2 then
            tween(list, { CanvasPosition = Vector2.new(0, y) }, 0.45, Enum.EasingStyle.Quint)
            task.wait(0.25)
        end
        if frame.Parent then
            self:_flash(frame, target._groupbox and 10 or 8)
        end
    end)
end

function Window:_resetSearch()
    if self.SearchBox and self.SearchBox.Text ~= "" then
        self.SearchBox.Text = ""
    end
end

-- Page titles stop short of the search box and close button.
function Window:_fitTitle(tab)
    local right = self.SearchBox and (self._searchWidth or SEARCH_WIDTH) + 72 or 56
    local reserve = tab._titleX + right
    tab._title.Size = UDim2.new(1, -reserve, 0, 24)
    if tab._desc then
        tab._desc.Size = UDim2.new(1, -reserve, 0, 16)
    end
end

function Window:_buildSearch(content)
    -- A recessed field: darker than the header, hairline stroke, icon
    -- inset left and a clear button that only shows while there is text.
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -56, 0, 14),
        Size = UDim2.fromOffset(SEARCH_WIDTH, 34),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = content,
    })
    holder:SetAttribute("NoDrag", true)
    local field = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Parent = holder,
    })
    corner(field, UDim.new(0, 6))
    local fieldStroke = stroke(field, Theme.Stroke, 0, 1)
    local _, icon = glowIcon(field, "search", Theme.Muted, UDim2.new(0, 9, 0.5, 0))
    icon.Parent.AnchorPoint = Vector2.new(0, 0.5)
    icon.Parent.Size = UDim2.fromOffset(13, 13)
    local clear = create("ImageButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -7, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        Visible = false,
        Parent = field,
    })
    applyIcon(clear, "x")
    local box = create("TextBox", {
        Position = UDim2.fromOffset(28, 0),
        Size = UDim2.new(1, -52, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = field,
    })
    clear.MouseEnter:Connect(function()
        tween(clear, { ImageColor3 = Theme.Text }, 0.1)
    end)
    clear.MouseLeave:Connect(function()
        tween(clear, { ImageColor3 = Theme.Muted }, 0.15)
    end)
    clear.MouseButton1Click:Connect(function()
        box.Text = ""
        box:CaptureFocus()
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        clear.Visible = box.Text ~= ""
    end)
    holder.MouseEnter:Connect(function()
        if not box:IsFocused() then
            tween(fieldStroke, { Color = Theme.StrokeHover }, 0.15)
        end
    end)
    holder.MouseLeave:Connect(function()
        if not box:IsFocused() then
            tween(fieldStroke, { Color = Theme.Stroke }, 0.25)
        end
    end)
    self.SearchBox = box

    -- Results float over the window under the box, like a dropdown popup.
    local rowHeight = TOUCH and 40 or 34
    local maxRows = 8
    local popup = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Size = UDim2.fromOffset(300, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 45,
        Parent = self.Body,
    })
    popup:SetAttribute("NoDrag", true)
    local popupShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-18, -12),
        Size = UDim2.new(1, 36, 1, 36),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = popup,
    })
    local panel = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = popup,
    })
    corner(panel, UDim.new(0, 10))
    local panelStroke = stroke(panel, Theme.Stroke, 1)
    edgeHighlight(panel)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(6, 6),
        Size = UDim2.new(1, -12, 1, -12),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(),
        Parent = panel,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = list,
    })
    local noResults = label({
        Size = UDim2.new(1, 0, 0, rowHeight),
        Text = "No results",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = false,
        Parent = list,
    })

    local rows = {}
    local results = {}
    local selected = 1
    local open = false
    local generation = 0
    local shownSize = Vector2.new(300, 0)
    local stopFollowing = nil
    local closeResults

    local function place()
        local scale = self.Scale.Scale
        local bodyPosition = self.Body.AbsolutePosition
        local bodyWidth = self.Body.AbsoluteSize.X / scale
        local right = (holder.AbsolutePosition.X + holder.AbsoluteSize.X - bodyPosition.X) / scale
        local top = (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - bodyPosition.Y) / scale + 6
        right = math.clamp(right, shownSize.X + 8, math.max(bodyWidth - 8, shownSize.X + 8))
        popup.Position = UDim2.fromOffset(right, top)
    end

    local function measure()
        local scale = self.Scale.Scale
        local bodySize = self.Body.AbsoluteSize / scale
        local below = (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - self.Body.AbsolutePosition.Y) / scale + 6
        local count = math.max(#rows, 1)
        local height = math.min(count, maxRows) * (rowHeight + 2) - 2 + 12
        height = math.max(math.min(height, bodySize.Y - below - 12), rowHeight + 12)
        local width = math.min(math.max(holder.AbsoluteSize.X / scale, 300), math.max(bodySize.X - 16, 160))
        shownSize = Vector2.new(width, height)
    end

    local function paintSelection()
        for index, row in ipairs(rows) do
            local on = index == selected
            tween(row.Button, { BackgroundTransparency = on and 0.35 or 1 }, 0.12)
            tintIcon(row.Icon, on and Theme.Accent or Theme.Muted, on, 0.12)
        end
    end

    local function keepSelectionInView()
        local rowTop = (selected - 1) * (rowHeight + 2)
        local view = list.AbsoluteWindowSize.Y / self.Scale.Scale
        local y = list.CanvasPosition.Y
        if rowTop < y then
            y = rowTop
        elseif rowTop + rowHeight > y + view then
            y = rowTop + rowHeight - view
        else
            return
        end
        list.CanvasPosition = Vector2.new(0, math.max(y, 0))
    end

    local function setOpen(value)
        if value == open then
            return
        end
        open = value
        generation += 1
        local current = generation
        if value then
            if self._closePopup and self._closePopup ~= closeResults then
                self._closePopup()
            end
            self._closePopup = closeResults
            place()
            popup.Size = UDim2.fromOffset(shownSize.X, 0)
            popup.Visible = true
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, shownSize.Y) }, 0.26, Enum.EasingStyle.Quint)
            tween(panelStroke, { Transparency = 0 }, 0.12)
            tween(popupShadow, { ImageTransparency = 0.55 }, 0.26)
            if not stopFollowing then
                stopFollowing = self:_listen("Render", place)
            end
        else
            if self._closePopup == closeResults then
                self._closePopup = nil
            end
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, 0) }, 0.18, Enum.EasingStyle.Quint)
            tween(popupShadow, { ImageTransparency = 1 }, 0.14)
            task.delay(0.19, function()
                if generation == current and not open then
                    popup.Visible = false
                    panelStroke.Transparency = 1
                    if stopFollowing then
                        stopFollowing()
                        stopFollowing = nil
                    end
                end
            end)
        end
    end
    closeResults = function()
        setOpen(false)
    end

    local function choose(result)
        if not result then
            return
        end
        setOpen(false)
        box.Text = ""
        if box:IsFocused() then
            box:ReleaseFocus()
        end
        self:_revealResult(result)
    end

    local function escape(text)
        return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
    end

    local function render(query)
        for _, row in ipairs(rows) do
            row.Button:Destroy()
        end
        table.clear(rows)
        results = self:_searchResults(query)
        selected = 1
        local accent = colorToHex(Theme.Accent)
        for index, result in ipairs(results) do
            if index > 50 then
                break
            end
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, rowHeight),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = list,
            })
            corner(button, UDim.new(0, 7))
            -- One line of breadcrumbs: tab, sub tab and groupbox in muted
            -- text, each split by a chevron, ending on the match in accent.
            local crumbs = create("Frame", {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -20, 1, 0),
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                Parent = button,
            })
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 5),
                Parent = crumbs,
            })
            local part = 0
            local firstIcon = nil
            local function crumbIcon(icon)
                if not icon then
                    return
                end
                part += 1
                local image = create("ImageLabel", {
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ScaleType = Enum.ScaleType.Fit,
                    LayoutOrder = part,
                    Parent = crumbs,
                })
                applyIcon(image, icon)
                firstIcon = firstIcon or image
            end
            local function crumbText(text, color, rich)
                part += 1
                return label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = text,
                    RichText = rich == true,
                    TextSize = 13,
                    FontFace = color and Fonts.Medium or Fonts.Regular,
                    TextColor3 = color or Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    LayoutOrder = part,
                    Parent = crumbs,
                })
            end
            local function chevron()
                crumbText(">")
            end
            local tab, sub, group = result.Tab, result.Sub, result.Group
            local onTab = result.Kind == "Tab"
            local onSub = result.Kind == "Page"
            local onGroup = result.Kind == "Groupbox"
            crumbIcon(tab._iconName or "layout-grid")
            if not onTab then
                crumbText(tab.Name)
                if sub then
                    chevron()
                    crumbIcon(sub._iconName or "layers")
                    if not onSub then
                        crumbText(sub.Name)
                    end
                end
                if group and not onGroup then
                    chevron()
                    crumbText(group.Name)
                end
                if not onSub then
                    chevron()
                end
            end
            -- The match itself: accent, with the typed part in bold.
            local name = result.Name
            local stop = result.At + #query
            local marked = escape(string.sub(name, 1, result.At - 1))
                .. "<b>" .. escape(string.sub(name, result.At, stop - 1)) .. "</b>"
                .. escape(string.sub(name, stop))
            crumbText(marked, Theme.Accent, true)
            local image = firstIcon
            local isTap = tapGuard(button, function()
                return list
            end)
            button.MouseEnter:Connect(function()
                if not usingTouch() then
                    selected = index
                    paintSelection()
                end
            end)
            button.MouseButton1Click:Connect(function()
                if isTap() then
                    choose(result)
                end
            end)
            table.insert(rows, { Button = button, Icon = image })
        end
        noResults.Visible = #rows == 0
        list.CanvasSize = UDim2.fromOffset(0, math.max(#rows, 1) * (rowHeight + 2) - 2)
        list.CanvasPosition = Vector2.zero
        paintSelection()
        measure()
        if open then
            place()
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, shownSize.Y) }, 0.2, Enum.EasingStyle.Quint)
        end
    end

    local function update()
        local query = string.match(string.lower(box.Text), "^%s*(.-)%s*$")
        if query == "" then
            setOpen(false)
            return
        end
        render(query)
        setOpen(true)
    end

    box.Focused:Connect(function()
        tween(fieldStroke, { Color = Theme.Accent }, 0.15)
        tween(field, { BackgroundTransparency = 0 }, 0.15)
        tween(icon, { ImageColor3 = Theme.Text }, 0.15)
        if box.Text ~= "" then
            update()
        end
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(fieldStroke, { Color = Theme.Stroke }, 0.2)
        tween(field, { BackgroundTransparency = 0.2 }, 0.2)
        tween(icon, { ImageColor3 = Theme.Muted }, 0.2)
        if enterPressed and open then
            choose(results[selected])
        end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(update)
    self:_listen("Began", function(input)
        if not open then
            return
        end
        if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
            if #rows > 0 then
                local step = input.KeyCode == Enum.KeyCode.Up and -1 or 1
                selected = math.clamp(selected + step, 1, #rows)
                paintSelection()
                keepSelectionInView()
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            setOpen(false)
        elseif isPress(input) then
            local point = pointerPosition()
            if not pointInside(point, popup) and not pointInside(point, holder) then
                setOpen(false)
            end
        end
    end)

    local function fit()
        local width = content.AbsoluteSize.X / self.Scale.Scale
        local searchWidth = math.clamp(math.floor(width * 0.32), 110, SEARCH_WIDTH)
        holder.Size = UDim2.fromOffset(searchWidth, 34)
        if searchWidth ~= self._searchWidth then
            self._searchWidth = searchWidth
            for _, tab in ipairs(self.Tabs) do
                self:_fitTitle(tab)
            end
        end
    end
    content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)
end

-- Identity: the player's name and headshot shown in the sidebar and on the
-- home tab. The privacy switches hide them everywhere at once.

function Window:_trackName(textLabel, kind)
    table.insert(self._identity.Names, { Label = textLabel, Kind = kind })
    self:_renderIdentity()
end

function Window:_trackAvatar(image, placeholder)
    table.insert(self._identity.Avatars, { Image = image, Placeholder = placeholder })
    self:_renderIdentity(true)
end

function Window:_renderIdentity(instant)
    for _, entry in ipairs(self._identity.Names) do
        if entry.Kind == "User" then
            entry.Label.Text = self._hideName and "@hidden" or ("@" .. LocalPlayer.Name)
        else
            entry.Label.Text = self._hideName and "Hidden" or LocalPlayer.DisplayName
        end
    end
    local duration = instant and 0 or 0.2
    for _, entry in ipairs(self._identity.Avatars) do
        tween(entry.Image, { ImageTransparency = self._hideAvatar and 1 or 0 }, duration)
        tween(entry.Placeholder, { ImageTransparency = self._hideAvatar and 0.2 or 1 }, duration)
    end
end

function Window:SetHideName(hidden)
    self._hideName = hidden == true
    self:_renderIdentity()
end

function Window:SetHideAvatar(hidden)
    self._hideAvatar = hidden == true
    self:_renderIdentity()
end

local function avatar(window, parent, props, ringColor, ringTransparency, ringThickness)
    local holder = create("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = parent,
    })
    for key, value in pairs(props) do
        holder[key] = value
    end
    corner(holder, UDim.new(1, 0))
    stroke(holder, ringColor or Theme.Stroke, ringTransparency or 0, ringThickness or 1)
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Parent = holder,
    })
    corner(image, UDim.new(1, 0))
    local placeholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.45, 0.45),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(placeholder, "user")
    window:_trackAvatar(image, placeholder)
    return holder
end

function Window:_buildProfile(sidebar)
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -PROFILE_HEIGHT),
        Size = UDim2.new(1, -20, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = sidebar,
    })
    local card = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -8),
        Size = UDim2.new(1, -16, 0, PROFILE_HEIGHT - 16),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = sidebar,
    })
    corner(card, UDim.new(0, 8))
    local cardStroke = stroke(card, Theme.Stroke, 0)
    local head = avatar(self, card, {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
    })
    local online = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 1, 1, 1),
        Size = UDim2.fromOffset(9, 9),
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = head,
    })
    corner(online, UDim.new(1, 0))
    stroke(online, Theme.Surface2, 0, 2)
    local name = label({
        Position = UDim2.new(0, 48, 0.5, -15),
        Size = UDim2.new(1, -74, 0, 15),
        TextSize = 12,
        FontFace = Fonts.Bold,
        Parent = card,
    })
    self:_trackName(name, "Display")
    local gameLabel = label({
        Position = UDim2.new(0, 48, 0.5, 1),
        Size = UDim2.new(1, -74, 0, 13),
        Text = "…",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card,
    })
    local chevron = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = card,
    })
    applyIcon(chevron, "chevron-right")
    task.spawn(function()
        gameLabel.Text = detectGameName()
    end)
    card.MouseEnter:Connect(function()
        if usingTouch() then
            return
        end
        tween(cardStroke, { Color = Theme.StrokeHover }, 0.12)
        tween(chevron, { ImageColor3 = Theme.Text, Position = UDim2.new(1, -6, 0.5, 0) }, 0.15)
    end)
    card.MouseLeave:Connect(function()
        tween(cardStroke, { Color = Theme.Stroke }, 0.2)
        tween(chevron, { ImageColor3 = Theme.Muted, Position = UDim2.new(1, -8, 0.5, 0) }, 0.2)
    end)
    card.MouseButton1Click:Connect(function()
        if self.Home then
            self:SelectTab(self.Home)
        end
    end)
    self.Profile = card
end

-- Server actions

function Window:Rejoin()
    self:Notify({ Title = "Rejoining", Content = "Teleporting back into this server", Icon = "refresh-cw", Duration = 3 })
    task.spawn(function()
        local ok, err = pcall(function()
            if #Players:GetPlayers() <= 1 or game.JobId == "" then
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
        if not ok then
            self:Notify({ Title = "Rejoin failed", Content = tostring(err), Type = "Error", Duration = 4 })
        end
    end)
end

local function hopServers(window, order, pick, title)
    task.spawn(function()
        local servers = fetchServers(order)
        if not servers then
            window:Notify({ Title = title .. " failed", Content = "Could not load the server list", Type = "Error", Duration = 4 })
            return
        end
        local candidates = {}
        for _, server in ipairs(servers) do
            if type(server) == "table" and server.id ~= game.JobId then
                local playing, capacity = tonumber(server.playing), tonumber(server.maxPlayers)
                if playing and capacity and playing < capacity then
                    table.insert(candidates, server)
                end
            end
        end
        local target = #candidates > 0 and pick(candidates) or nil
        if not target then
            window:Notify({ Title = title .. " failed", Content = "No other open server found", Type = "Warning", Duration = 4 })
            return
        end
        window:Notify({
            Title = title,
            Content = string.format("Joining a server with %d/%d players", target.playing, target.maxPlayers),
            Icon = "server",
            Duration = 3,
        })
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
        end)
        if not ok then
            window:Notify({ Title = title .. " failed", Content = tostring(err), Type = "Error", Duration = 4 })
        end
    end)
end

function Window:ServerHop()
    hopServers(self, "Desc", function(list)
        return list[math.random(1, #list)]
    end, "Server hop")
end

function Window:JoinLowestServer()
    hopServers(self, "Asc", function(list)
        table.sort(list, function(a, b)
            return a.playing < b.playing
        end)
        return list[1]
    end, "Lowest server")
end

function Window:CopyToClipboard(text, what)
    local ok = copyToClipboard(text)
    self:Notify({
        Title = ok and "Copied" or "Clipboard unavailable",
        Content = ok and (what or tostring(text)) or "Your executor has no setclipboard",
        Type = ok and "Success" or "Error",
        Icon = ok and "clipboard-check" or nil,
        Duration = 2.5,
    })
    return ok
end

-- Home

-- Home reads top to bottom: a banner greeting the player, a performance card
-- with live graphs, the server and links side by side, and a status line.

-- A Home card that grows with its stacked contents.
function Window:_homeCard(parent, order)
    local card = panelCard(parent, 0, order)
    card.AutomaticSize = Enum.AutomaticSize.Y
    padding(card, 16, 16, 14, 14)
    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
    return card
end

-- A small caps heading at the top of a Home card.
function Window:_homeCaption(parent, text, order)
    return label({
        Size = UDim2.new(1, 0, 0, 22),
        Text = string.upper(text),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = order,
        Parent = parent,
    })
end

-- A rounded chip of an icon and short text. Returns the chip, its label and
-- its icon so callers can recolour them.
function Window:_homeChip(parent, order, icon, text, color)
    local chip = create("TextButton", {
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    padding(chip, 8, 9)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = chip,
    })
    local image = create("ImageLabel", {
        Size = UDim2.fromOffset(12, 12),
        BackgroundTransparency = 1,
        ImageColor3 = color or Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = chip,
    })
    applyIcon(image, icon)
    local text_ = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = text,
        TextSize = 12,
        TextColor3 = color or Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = chip,
    })
    return chip, text_, image, chipStroke
end

-- A chip that flips on press: on, it takes the accent; off, it sits muted.
function Window:_homeToggleChip(parent, order, icon, text, initial, callback)
    local chip, text_, image, chipStroke = self:_homeChip(parent, order, icon, text)
    local on = initial == true
    local function paint(duration)
        tween(chip, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3, BackgroundTransparency = on and 0.85 or 0.2 }, duration)
        tween(chipStroke, { Color = on and Theme.Accent or Theme.Stroke, Transparency = on and 0.6 or 0 }, duration)
        tween(text_, { TextColor3 = on and Theme.Accent or Theme.Muted }, duration)
        tween(image, { ImageColor3 = on and Theme.Accent or Theme.Muted }, duration)
    end
    paint(0)
    chip.MouseButton1Click:Connect(function()
        on = not on
        paint(0.2)
        safeCall(callback, on)
    end)
    return chip
end

function Window:_homeProfile(list, opts, order)
    local banner = panelCard(list, 140, order)
    banner.ClipsDescendants = true

    -- The avatar bust stands on the banner's right edge and fades in from
    -- the left, so it reads as part of the card rather than a framed photo.
    local bust = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, 0),
        Size = UDim2.fromOffset(140, 140),
        BackgroundTransparency = 1,
        Image = "rbxthumb://type=AvatarBust&id=" .. tostring(LocalPlayer.UserId) .. "&w=420&h=420",
        ScaleType = Enum.ScaleType.Fit,
        Parent = banner,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.45, 0),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = bust,
    })
    local bustPlaceholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.6, 0.55),
        Size = UDim2.fromOffset(40, 40),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = bust,
    })
    applyIcon(bustPlaceholder, "user")
    self:_trackAvatar(bust, bustPlaceholder)

    local textWidth = UDim2.new(1, -190, 0, 0)
    label({
        Position = UDim2.fromOffset(22, 20),
        Size = textWidth + UDim2.fromOffset(0, 14),
        Text = string.upper(opts.Welcome or "Welcome back"),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        Parent = banner,
    })
    local nameLabel = label({
        Position = UDim2.fromOffset(22, 35),
        Size = textWidth + UDim2.fromOffset(0, 32),
        TextSize = 26,
        FontFace = Fonts.Bold,
        Parent = banner,
    })
    self:_trackName(nameLabel, "Display")
    local userLabel = label({
        Position = UDim2.fromOffset(22, 67),
        Size = textWidth + UDim2.fromOffset(0, 16),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = banner,
    })
    self:_trackName(userLabel, "User")

    -- Chips along the bottom: tier, time left, then the privacy toggles.
    local chips = create("Frame", {
        Position = UDim2.new(0, 22, 1, -40),
        Size = UDim2.new(1, -44, 0, 24),
        BackgroundTransparency = 1,
        Parent = banner,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = chips,
    })
    local tier = opts.Tier
    if tier == nil then
        tier = "Free"
    end
    if tier then
        local tierChip, tierText, tierIcon = self:_homeChip(chips, 1, opts.TierIcon or self._logoIcon, tostring(tier), Theme.Accent)
        tierChip.Active = false
        tierText.FontFace = Fonts.Bold
        tierIcon.Size = UDim2.fromOffset(13, 13)
        self.TierLabel = tierText
    end
    local expiryChip, expiryText = self:_homeChip(chips, 2, "clock", "")
    expiryChip.Active = false
    expiryChip.Visible = false
    self:_homeToggleChip(chips, 3, "eye-off", "Name", self._hideName, function(on)
        self:SetHideName(on)
    end)
    self:_homeToggleChip(chips, 4, "user-x", "Avatar", self._hideAvatar, function(on)
        self:SetHideAvatar(on)
    end)

    return function()
        local value = opts.Expiry
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "number" then
            local left = value - os.time()
            expiryText.Text = left > 0 and (formatDuration(left) .. " left") or "Expired"
        elseif value ~= nil then
            expiryText.Text = tostring(value)
        end
        expiryChip.Visible = expiryText.Text ~= ""
    end
end

-- A large live readout with a short bar history under it. Returns the value
-- label and a push(value, color) that adds a sample.
function Window:_homeGraph(parent, order, icon, title, ceiling, unit)
    -- Reads like a perf overlay: name and min/avg/max on one line, the
    -- reading under it, and a dense history strip tinted by health.
    local cell = create("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    label({
        Size = UDim2.new(0.4, 0, 0, 14),
        Text = title,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        Parent = cell,
    })
    local range = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.6, 0, 0, 14),
        Text = "",
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        RichText = true,
        Parent = cell,
    })
    local value = label({
        Position = UDim2.fromOffset(0, 15),
        Size = UDim2.new(1, 0, 0, 26),
        Text = "…",
        TextSize = 22,
        FontFace = Fonts.Bold,
        RichText = true,
        Parent = cell,
    })
    local track = create("Frame", {
        Position = UDim2.fromOffset(0, 46),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = cell,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = track,
    })
    local columns = create("Frame", {
        Size = UDim2.new(1, 0, 1, -1),
        BackgroundTransparency = 1,
        Parent = track,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
        Parent = columns,
    })
    local COUNT = 48
    local bars, samples = {}, {}
    for index = 1, COUNT do
        bars[index] = create("Frame", {
            Size = UDim2.new(1 / COUNT, -1, 0, 0),
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Parent = columns,
        })
    end
    local muted = "#" .. Theme.Muted:ToHex()
    local function setValue(sample)
        value.Text = ('%d<font size="13" color="%s"> %s</font>'):format(sample, muted, unit or "")
    end
    local function push(sample, color)
        setValue(sample)
        table.insert(samples, sample)
        if #samples > COUNT then
            table.remove(samples, 1)
        end
        local top, low, sum = ceiling or 1, math.huge, 0
        for _, s in ipairs(samples) do
            top = math.max(top, s)
            low = math.min(low, s)
            sum += s
        end
        range.Text = ('min <font color="#%s">%d</font>   avg <font color="#%s">%d</font>   max <font color="#%s">%d</font>'):format(
            Theme.Text:ToHex(), low, Theme.Text:ToHex(), math.floor(sum / #samples + 0.5), Theme.Text:ToHex(), math.max(table.unpack(samples)))
        local offset = COUNT - #samples
        for index, bar in ipairs(bars) do
            local s = samples[index - offset]
            local age = COUNT - index
            tween(bar, {
                Size = UDim2.new(1 / COUNT, -1, s and math.max(s / top, 0.04) or 0, 0),
                BackgroundColor3 = color,
                -- Older samples fade so the strip reads left-to-right as time.
                BackgroundTransparency = s and (age == 0 and 0 or 0.45 + 0.35 * age / COUNT) or 1,
            }, 0.3, Enum.EasingStyle.Quint)
        end
    end
    return value, push
end

-- A small figure: value over a quiet caption.
function Window:_homeFigure(parent, order, title)
    local cell = create("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    local value = label({
        Size = UDim2.new(1, -8, 0, 20),
        Text = "…",
        TextSize = 15,
        FontFace = Fonts.Bold,
        RichText = true,
        Parent = cell,
    })
    label({
        Position = UDim2.fromOffset(0, 21),
        Size = UDim2.new(1, -8, 0, 14),
        Text = title,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        Parent = cell,
    })
    return value
end

-- A square tile button: an icon over a short label.
function Window:_homeAction(parent, order, icon, text, callback)
    local button = create("TextButton", {
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(button, UDim.new(0, 8))
    local buttonStroke = stroke(button)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 11),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Text,
        ScaleType = Enum.ScaleType.Fit,
        Parent = button,
    })
    applyIcon(image, icon)
    label({
        Position = UDim2.new(0, 4, 0, 32),
        Size = UDim2.new(1, -8, 0, 14),
        Text = text,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(image, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        tween(image, { ImageColor3 = Theme.Text }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(callback)
    end)
    return button
end

function Window:_homeGame(parent, order)
    local card = self:_homeCard(parent, order)
    local head = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    local icon = create("ImageLabel", {
        Size = UDim2.fromOffset(44, 44),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        Parent = head,
    })
    corner(icon, UDim.new(0, 10))
    stroke(icon)
    local gameName = label({
        Position = UDim2.fromOffset(56, 3),
        Size = UDim2.new(1, -56, 0, 20),
        Text = "Loading",
        TextSize = 15,
        FontFace = Fonts.Bold,
        Parent = head,
    })
    local detail = label({
        Position = UDim2.fromOffset(56, 24),
        Size = UDim2.new(1, -56, 0, 16),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = head,
    })
    local owner = nil
    task.spawn(function()
        local info = fetchGameInfo()
        gameName.Text = info and info.Name or detectGameName()
        owner = info and type(info.Creator) == "table" and info.Creator.Name or nil
    end)

    local actions = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = card,
    })
    padding(actions, 0, 0, 12, 0)
    create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(6, 6),
        CellSize = UDim2.new(0.25, -5, 0, 54),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = actions,
    })
    self:_homeAction(actions, 1, "refresh-cw", "Rejoin", function()
        self:Rejoin()
    end)
    self:_homeAction(actions, 2, "shuffle", "Hop", function()
        self:ServerHop()
    end)
    self:_homeAction(actions, 3, "users", "Lowest", function()
        self:JoinLowestServer()
    end)
    self:_homeAction(actions, 4, "copy", "Job ID", function()
        self:CopyToClipboard(game.JobId, "Job ID")
    end)

    label({
        Size = UDim2.new(1, 0, 0, 26),
        Text = "Job " .. shortId(game.JobId) .. "  ·  Place " .. tostring(game.PlaceId),
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextYAlignment = Enum.TextYAlignment.Bottom,
        LayoutOrder = 3,
        Parent = card,
    })

    -- The detail line keeps the player count live.
    return function()
        local count = #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players"
        detail.Text = owner and ("by " .. owner .. "  ·  " .. count) or count
    end
end

-- One row of the links card: icon, title and text, and a round icon button.
function Window:_homeLink(card, order, icon, title, text, buttonIcon, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = card,
    })
    create("Frame", {
        Name = "Rule",
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = row,
    })
    local holder = glowIcon(row, icon, Theme.Accent, UDim2.new(0, 0, 0.5, 0))
    holder.Size = UDim2.fromOffset(16, 16)
    local titleLabel = label({
        Position = UDim2.fromOffset(28, 6),
        Size = UDim2.new(1, -68, 0, 18),
        Text = title,
        TextSize = 13,
        Parent = row,
    })
    local textLabel = label({
        Position = UDim2.fromOffset(28, 24),
        Size = UDim2.new(1, -68, 0, 15),
        Text = text,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = row,
    })
    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    corner(button, UDim.new(0, 8))
    local buttonStroke = stroke(button)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = button,
    })
    applyIcon(image, buttonIcon)
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(image, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        tween(image, { ImageColor3 = Theme.Muted }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        safeCall(callback)
    end)
    return row, titleLabel, textLabel
end

-- Builds the links card into parent, or nothing when there are no links and
-- the feature list is off. Returns the card (or nil) and the feature refresh.
function Window:_homeLinks(parent, opts, order)
    local links = {}
    if opts.Discord then
        table.insert(links, {
            Icon = opts.DiscordIcon or "message-circle",
            Title = opts.DiscordTitle or "Community",
            Text = opts.Discord,
        })
    end
    if opts.Website then
        table.insert(links, {
            Icon = opts.WebsiteIcon or "globe",
            Title = opts.WebsiteTitle or "Website",
            Text = opts.Website,
        })
    end
    for _, link in ipairs(opts.Links or {}) do
        table.insert(links, link)
    end
    local features = opts.Features
    if #links == 0 and features == false then
        return nil, function() end
    end
    local card = self:_homeCard(parent, order)
    self:_homeCaption(card, "Links", 0)
    for index, link in ipairs(links) do
        local action = type(link.Callback) == "function"
        self:_homeLink(card, index, link.Icon or "link", link.Title or "", link.Text or "", action and "arrow-up-right" or "copy", function()
            if action then
                safeCall(link.Callback)
            else
                self:CopyToClipboard(link.Copy or link.Text, link.Title)
            end
        end)
    end
    local refresh = function() end
    if features ~= false then
        if type(features) == "table" then
            self._featuresTitle = features.Title
            self._features = features.List or (#features > 0 and features or nil)
        end
        local _, _, text_ = self:_homeLink(card, 100,
            type(features) == "table" and features.Icon or "list-checks",
            type(features) == "table" and features.Title or "Feature list",
            "", "chevron-right", function()
                self:ShowFeatures()
            end)
        refresh = function()
            local desc = type(features) == "table" and features.Desc
            text_.Text = desc or (self:_featureSummary())
        end
        task.defer(refresh)
    end
    -- The first row needs no rule above it.
    local first = nil
    for _, child in ipairs(card:GetChildren()) do
        if child:IsA("Frame") and child:FindFirstChild("Rule") and (not first or child.LayoutOrder < first.LayoutOrder) then
            first = child
        end
    end
    if first then
        first.Rule.Visible = false
    end
    return card, refresh
end

-- A quiet status line under the cards: executor support on the left, the
-- hide key on the right.
function Window:_homeExecutor(list, opts, order)
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = list,
    })
    local executor, supported, message = executorReport(opts)
    local dot = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 4, 0.5, 0),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = supported and Theme.Success or Theme.Warning,
        BorderSizePixel = 0,
        Parent = line,
    })
    corner(dot, UDim.new(1, 0))
    local left = create("Frame", {
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -170, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = line,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = left,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = executor,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 1,
        Parent = left,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = message,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = supported and Theme.Muted or Theme.Warning,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = left,
    })

    local hint = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -2, 0.5, 0),
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = line,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = hint,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = TOUCH and "Tap the pill or" or "Hide with",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 1,
        Parent = hint,
    })
    local chip = create("Frame", {
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = hint,
    })
    corner(chip, UDim.new(0, 5))
    stroke(chip)
    padding(chip, 6, 6)
    self._keyChipLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = keyName(self.Keybind),
        TextSize = 12,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })
end

-- Feature list: every control the script adds, grouped by tab, or a list the
-- script writes itself. Items that match a control jump to it when picked.

Window._featureKinds = {
    Toggle = true,
    Slider = true,
    Dropdown = true,
    Input = true,
    Keybind = true,
    ColorPicker = true,
    Stepper = true,
    Button = true,
    ButtonRow = true,
    OrderList = true,
}

function Window:_featureGroups()
    local found, byName = {}, {}
    for _, tab in ipairs(self.Tabs) do
        if tab ~= self.Home and tab._userVisible ~= false then
            local group = { Name = tab.Name, Icon = tab._iconName, Items = {} }
            for _, page in ipairs(tab._subTabs or { tab }) do
                local sub = page._isSubTab and page or nil
                local function add(name, element, box, path)
                    if type(name) ~= "string" or name == "" then
                        return
                    end
                    local item = {
                        Name = name,
                        Kind = element._type == "ButtonRow" and "Button" or element._type,
                        Path = path,
                        Result = { Tab = tab, Sub = sub, Target = element, Group = box },
                    }
                    table.insert(group.Items, item)
                    byName[string.lower(name)] = byName[string.lower(name)] or item
                end
                local function addElement(element, box, path)
                    if element._destroyed or not self._featureKinds[element._type] or (element._isShown and not element:_isShown()) then
                        return
                    end
                    if element._type == "ButtonRow" and element.Buttons then
                        for _, button in ipairs(element.Buttons) do
                            add(button.Label.Text, element, box, path)
                        end
                    else
                        add(element._searchName, element, box, path)
                    end
                end
                if not page._noSearch then
                    for _, element in ipairs(page._items or {}) do
                        addElement(element, nil, sub and sub.Name or nil)
                    end
                    for _, box in ipairs(page._groupboxes or {}) do
                        if box._userVisible ~= false and not box._manager then
                            for _, element in ipairs(box._items) do
                                addElement(element, box, sub and (sub.Name .. "  ›  " .. box.Name) or box.Name)
                            end
                        end
                    end
                end
            end
            if #group.Items > 0 then
                table.insert(found, group)
            end
        end
    end
    local custom = self._features
    if type(custom) ~= "table" then
        return found
    end
    -- A written list: groups of items, or bare items, which gather into one
    -- group where the first one appears.
    local function customItem(entry)
        if type(entry) ~= "table" then
            entry = { Name = entry }
        end
        local name = tostring(entry.Name or entry.Title or entry[1] or "")
        local link = byName[string.lower(name)]
        return {
            Name = name,
            Desc = entry.Desc or entry.Description,
            Tag = entry.Tag,
            Icon = entry.Icon,
            Kind = link and link.Kind,
            Path = link and link.Path,
            Result = link and link.Result,
            Callback = entry.Callback,
        }
    end
    local groups, loose = {}, nil
    for _, entry in ipairs(custom) do
        if type(entry) == "table" and type(entry.Items) == "table" then
            local group = { Name = tostring(entry.Name or entry.Title or "Features"), Icon = entry.Icon, Items = {} }
            for _, item in ipairs(entry.Items) do
                table.insert(group.Items, customItem(item))
            end
            table.insert(groups, group)
        else
            if not loose then
                loose = { Name = self._featuresTitle or "Features", Items = {} }
                table.insert(groups, loose)
            end
            table.insert(loose.Items, customItem(entry))
        end
    end
    return groups
end

function Window:_featureSummary()
    local groups = self:_featureGroups()
    local count = 0
    for _, group in ipairs(groups) do
        count += #group.Items
    end
    local text = count .. (count == 1 and " feature" or " features")
    if type(self._features) ~= "table" and #groups > 0 then
        text ..= " across " .. #groups .. (#groups == 1 and " tab" or " tabs")
    end
    return text, groups, count
end

-- Opens the feature list over the window. Search filters it; picking an item
-- linked to a control closes the list and jumps to that control.
function Window:ShowFeatures()
    if self._dialog then
        self._dialog.Close()
    end
    local summary, groups, total = self:_featureSummary()
    local PAD = 16
    local ROW = TOUCH and 44 or 38
    local body = self.Body

    local overlay = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = body,
    })
    -- A canvas group so the whole list fades as one on open and close.
    local card_ = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(420, 460),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
        Parent = overlay,
    })
    corner(card_, UDim.new(0, 12))
    local cardStroke = stroke(card_, Theme.Stroke, 1)
    local cardScale = create("UIScale", { Scale = 0.94, Parent = card_ })
    local function fit()
        local scale = self.Scale.Scale
        local size = body.AbsoluteSize / scale
        card_.Size = UDim2.fromOffset(math.min(440, size.X - 24), math.min(480, size.Y - 24))
    end
    fit()
    local fitConnection = body:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

    local iconHolder = glowIcon(card_, "list-checks", Theme.Accent, UDim2.new(0, PAD, 0, PAD + 10))
    iconHolder.Size = UDim2.fromOffset(18, 18)
    label({
        Position = UDim2.fromOffset(PAD + 28, PAD),
        Size = UDim2.new(1, -(PAD * 2 + 28 + 36), 0, 18),
        Text = self._featuresTitle or "Features",
        TextSize = 15,
        Parent = card_,
    })
    label({
        Position = UDim2.fromOffset(PAD + 28, PAD + 19),
        Size = UDim2.new(1, -(PAD * 2 + 28 + 36), 0, 14),
        Text = summary,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card_,
    })
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -(PAD - 6), 0, PAD - 6),
        Size = TOUCH and UDim2.fromOffset(40, 40) or UDim2.fromOffset(32, 32),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = card_,
    })
    corner(closeButton, UDim.new(0, 8))
    local closeIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = closeButton,
    })
    applyIcon(closeIcon, "x")
    if closeIcon.Image == "" then
        closeIcon:Destroy()
        label({ Size = UDim2.fromScale(1, 1), Text = "×", TextSize = 20, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Center, Parent = closeButton })
    end
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { BackgroundTransparency = 0.5 }, 0.12)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { BackgroundTransparency = 1 }, 0.2)
    end)

    local top = PAD + 44
    local searchHolder = create("Frame", {
        Position = UDim2.fromOffset(PAD, top),
        Size = UDim2.new(1, -PAD * 2, 0, TOUCH and 36 or 32),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = card_,
    })
    corner(searchHolder, UDim.new(0, 7))
    local searchStroke = stroke(searchHolder)
    local _, searchIcon = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIcon.Parent.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search features",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = searchHolder,
    })
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    searchBox.FocusLost:Connect(function()
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
    end)
    top += (TOUCH and 36 or 32) + 10

    local scroller = create("ScrollingFrame", {
        Position = UDim2.fromOffset(PAD, top),
        Size = UDim2.new(1, -PAD * 2 + 6, 1, -(top + PAD - 4)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(),
        Parent = card_,
    })
    local content = create("Frame", {
        Size = UDim2.new(1, -10, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local layout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = content,
    })
    -- Canvas sized by hand, as elsewhere, so it scrolls under UIScale.
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y / self.Scale.Scale + 4)
    end)
    local noResults = label({
        Size = UDim2.new(1, 0, 0, 60),
        Text = total == 0 and "No features yet" or "No matches",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = total == 0,
        Parent = content,
    })

    local dialog = {}
    local closed = false
    local stopEscape = nil
    function dialog.Close()
        if closed then
            return
        end
        closed = true
        if self._dialog == dialog then
            self._dialog = nil
        end
        fitConnection:Disconnect()
        if stopEscape then
            -- Deferred: Close can run from inside the input dispatch loop.
            task.defer(stopEscape)
        end
        if searchBox:IsFocused() then
            searchBox:ReleaseFocus()
        end
        tween(overlay, { BackgroundTransparency = 1 }, 0.18)
        tween(card_, { Position = UDim2.new(0.5, 0, 0.5, 8), GroupTransparency = 1 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardStroke, { Transparency = 1 }, 0.12)
        task.delay(0.2, function()
            overlay:Destroy()
        end)
    end

    local sections = {}
    local order = 0
    for _, group in ipairs(groups) do
        order += 1
        local header = create("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = content,
        })
        local headIcon = glowIcon(header, group.Icon or "layout-grid", Theme.Accent, UDim2.new(0, 2, 0, 18))
        headIcon.Size = UDim2.fromOffset(14, 14)
        label({
            Position = UDim2.fromOffset(24, 10),
            Size = UDim2.new(1, -70, 0, 16),
            Text = string.upper(group.Name),
            TextSize = 12,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
        local countLabel = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -4, 0, 10),
            Size = UDim2.new(0, 40, 0, 16),
            Text = tostring(#group.Items),
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = header,
        })
        local section = { Header = header, Count = countLabel, Rows = {} }
        for _, item in ipairs(group.Items) do
            order += 1
            local sub = item.Desc or item.Path
            local clickable = item.Result ~= nil or type(item.Callback) == "function"
            local row = create("TextButton", {
                Size = UDim2.new(1, 0, 0, sub and ROW + 4 or ROW - 4),
                BackgroundColor3 = Theme.Surface2,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = order,
                Parent = content,
            })
            corner(row, UDim.new(0, 8))
            local rowIcon = glowIcon(row, item.Icon or self._searchIcons[item.Kind] or "check", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
            rowIcon.Size = UDim2.fromOffset(14, 14)
            local right = 12 + (clickable and 22 or 0)
            local tag
            if item.Tag then
                tag = create("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -(clickable and 30 or 10), 0.5, 0),
                    Size = UDim2.fromOffset(0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 0.85,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(tag, UDim.new(0, 5))
                padding(tag, 7, 7)
                label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = tostring(item.Tag),
                    TextSize = 12,
                    TextColor3 = Theme.Accent,
                    TextTruncate = Enum.TextTruncate.None,
                    Parent = tag,
                })
            end
            local nameLabel = label({
                Position = UDim2.fromOffset(34, sub and 5 or 0),
                Size = UDim2.new(1, -(34 + right), 0, sub and 18 or ROW - 4),
                Text = item.Name,
                TextSize = 13,
                Parent = row,
            })
            local subLabel
            if sub then
                subLabel = label({
                    Position = UDim2.fromOffset(34, 23),
                    Size = UDim2.new(1, -(34 + right), 0, 14),
                    Text = sub,
                    TextSize = 12,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    Parent = row,
                })
            end
            if tag then
                local function reserveTag()
                    local width = 34 + right + tag.AbsoluteSize.X / self.Scale.Scale + 8
                    nameLabel.Size = UDim2.new(1, -width, 0, nameLabel.Size.Y.Offset)
                    if subLabel then
                        subLabel.Size = UDim2.new(1, -width, 0, 14)
                    end
                end
                tag:GetPropertyChangedSignal("AbsoluteSize"):Connect(reserveTag)
                task.defer(reserveTag)
            end
            if clickable then
                local go = create("ImageLabel", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 0.5, 0),
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ImageTransparency = 0.4,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = row,
                })
                applyIcon(go, "arrow-up-right")
            end
            local isTap = tapGuard(row, function()
                return scroller
            end)
            row.MouseEnter:Connect(function()
                if not usingTouch() then
                    tween(row, { BackgroundTransparency = 0.3 }, 0.12)
                end
            end)
            row.MouseLeave:Connect(function()
                tween(row, { BackgroundTransparency = 1 }, 0.2)
            end)
            row.MouseButton1Click:Connect(function()
                if not clickable or not isTap() then
                    return
                end
                dialog.Close()
                if item.Result then
                    self:_revealResult(item.Result)
                end
                safeCall(item.Callback)
            end)
            table.insert(section.Rows, { Frame = row, Key = string.lower(item.Name .. " " .. (sub or "")) })
        end
        table.insert(sections, section)
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = string.lower(searchBox.Text)
        local any = false
        for _, section in ipairs(sections) do
            local shown = 0
            for _, row in ipairs(section.Rows) do
                local match = query == "" or string.find(row.Key, query, 1, true) ~= nil
                row.Frame.Visible = match
                if match then
                    shown += 1
                end
            end
            section.Header.Visible = shown > 0
            section.Count.Text = tostring(shown)
            any = any or shown > 0
        end
        noResults.Visible = not any
        scroller.CanvasPosition = Vector2.zero
    end)
    closeButton.MouseButton1Click:Connect(dialog.Close)
    overlay.MouseButton1Click:Connect(dialog.Close)
    stopEscape = self:_listen("Began", function(input)
        if input.KeyCode == Enum.KeyCode.Escape then
            dialog.Close()
        end
    end)

    self._dialog = dialog
    tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
    tween(card_, { Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 0 }, 0.3, Enum.EasingStyle.Quint)
    tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    return dialog
end

function Window:_homeStats(list, opts, order, tab)
    local show = opts.Stats or { "Players", "Execs", "Session", "FPS", "Ping" }
    -- FPS and ping get large readouts with a bar history; every other stat
    -- is a small figure in the row under them.
    local card = self:_homeCard(list, order)
    local graphs = create("Frame", {
        Size = UDim2.new(1, 0, 0, 76),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(28, 0),
        CellSize = UDim2.new(0.5, -14, 0, 76),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = graphs,
    })
    local rule = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = card,
    })
    local figures = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = card,
    })
    padding(figures, 0, 0, 12, 0)
    local figureGrid = create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(0, 8),
        CellSize = UDim2.new(0.25, 0, 0, 36),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = figures,
    })
    local values, sparks = {}, {}
    local graphCount, figureCount = 0, 0
    for index, name in ipairs(show) do
        local kind = STAT_TYPES[name]
        if kind and not values[name] then
            if name == "FPS" or name == "Ping" then
                graphCount += 1
                values[name], sparks[name] = self:_homeGraph(graphs, index, kind[1], kind[2], name == "FPS" and 60 or 100, name == "FPS" and "fps" or "ms")
            else
                figureCount += 1
                values[name] = self:_homeFigure(figures, index, kind[2])
            end
        end
    end
    graphs.Visible = graphCount > 0
    figures.Visible = figureCount > 0
    rule.Visible = graphCount > 0 and figureCount > 0
    if graphCount == 0 then
        padding(figures, 0, 0, 0, 0)
    end
    local function fitFigures()
        local width = figures.AbsoluteSize.X / self.Scale.Scale
        local columns = math.clamp(figureCount, 1, width >= 440 and 5 or 3)
        figureGrid.CellSize = UDim2.new(1 / columns, 0, 0, 36)
    end
    figures:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFigures)
    task.defer(fitFigures)

    if values.Executor then
        values.Executor.Text = detectExecutor()
    end
    if values.Game then
        values.Game.Text = "Loading"
        task.spawn(function()
            values.Game.Text = detectGameName()
        end)
    end
    if values.Region then
        values.Region.Text = "Loading"
        detectRegion(function(region)
            values.Region.Text = region
        end)
    end
    if values.Execs then
        local executions = bumpExecutions(opts.StatsFolder or self.ConfigFolder)
        values.Execs.Text = executions and tostring(executions) or "—"
    end
    if values.Friends then
        local friends = {}
        local function recount()
            local total = 0
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local known = friends[player.UserId]
                    if known == nil then
                        local ok, result = pcall(function()
                            return LocalPlayer:IsFriendsWith(player.UserId)
                        end)
                        known = ok and result == true
                        friends[player.UserId] = known
                    end
                    if known then
                        total += 1
                    end
                end
            end
            values.Friends.Text = tostring(total)
        end
        task.spawn(recount)
        table.insert(self._connections, Players.PlayerAdded:Connect(function()
            task.spawn(recount)
        end))
        table.insert(self._connections, Players.PlayerRemoving:Connect(function()
            task.defer(recount)
        end))
    end

    local session = values.Session or values.Uptime
    local started = os.clock()
    local frames = 0
    self:_listen("Render", function()
        frames += 1
    end)
    -- FPS, ping and memory are tinted by how healthy they are, unless the
    -- script turns that off with StatColors = false.
    local tinted = opts.StatColors ~= false
    local function tint(valueLabel, color)
        if tinted and valueLabel.TextColor3 ~= color then
            tween(valueLabel, { TextColor3 = color }, 0.3)
        end
    end
    return function()
        if values.FPS then
            sparks.FPS(frames, tinted and Library._healthColor(frames, 50, 30) or Theme.Muted)
        end
        frames = 0
        if values.Ping then
            local ok, ping = pcall(function()
                return math.floor(LocalPlayer:GetNetworkPing() * 1000)
            end)
            ping = ok and ping or 0
            sparks.Ping(ping, tinted and Library._healthColor(ping, 90, 180, true) or Theme.Muted)
        end
        if values.Players then
            values.Players.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
        end
        if session then
            session.Text = formatDuration(os.clock() - started)
        end
        if values.Time then
            values.Time.Text = os.date(opts.TimeFormat or "%H:%M")
        end
        if values.ServerAge then
            values.ServerAge.Text = formatDuration(workspace.DistributedGameTime)
        end
        if values.Memory then
            local ok, memory = pcall(function()
                return StatsService:GetTotalMemoryUsageMb()
            end)
            values.Memory.Text = ok and string.format("%d MB", memory) or "—"
            tint(values.Memory, ok and Library._healthColor(memory, 1500, 3000, true) or Theme.Text)
        end
    end, function()
        frames = 0
    end
end

local function homePage(sub, page)
    local list = sub.List
    if type(page.Content) == "string" then
        local card_ = panelCard(list, 0, 1)
        card_.AutomaticSize = Enum.AutomaticSize.Y
        padding(card_, 16, 16, 14, 16)
        label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = page.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = card_,
        })
    end
    if type(page.Entries) == "table" then
        for index, entry in ipairs(page.Entries) do
            local card_ = panelCard(list, 0, index + 1)
            card_.AutomaticSize = Enum.AutomaticSize.Y
            padding(card_, 16, 16, 14, 16)
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6),
                Parent = card_,
            })
            local head = create("Frame", {
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                LayoutOrder = 1,
                Parent = card_,
            })
            label({
                Size = UDim2.new(1, -90, 1, 0),
                Text = entry.Title or entry.Version or "Update",
                TextSize = 15,
                Parent = head,
            })
            if entry.Date or entry.Tag then
                local chip = create("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Theme.Surface,
                    BorderSizePixel = 0,
                    Parent = head,
                })
                corner(chip, UDim.new(0, 5))
                stroke(chip)
                padding(chip, 8, 8)
                label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = entry.Tag or entry.Date,
                    TextSize = 12,
                    TextColor3 = Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    Parent = chip,
                })
            end
            local body = entry.Content or entry.Body
            if type(entry.Changes) == "table" then
                body = "• " .. table.concat(entry.Changes, "\n• ")
            end
            if body then
                label({
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Text = body,
                    TextSize = 13,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    TextWrapped = true,
                    TextTruncate = Enum.TextTruncate.None,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    LayoutOrder = 2,
                    Parent = card_,
                })
            end
        end
    end
    if type(page.Build) == "function" then
        safeCall(page.Build, sub, list)
    else
        sub._noSearch = true
    end
end

function Window:_buildHome(opts)
    self._hideName = opts.HideName == true
    self._hideAvatar = opts.HideAvatar == true
    self:_renderIdentity(true)
    local tab = self:Tab({
        Name = opts.Name or "Home",
        Desc = opts.Desc,
        Icon = opts.Icon or "house",
        PageTitle = opts.Title or "Home",
    })
    tab._order = 100
    self.Home = tab

    local pages = opts.Pages or opts.Tabs
    local overview = tab
    if type(pages) == "table" and #pages > 0 then
        overview = tab:SubTab({ Name = opts.OverviewName or "Overview", Icon = opts.TabIcon or "layout-grid" })
    end
    overview._noSearch = true
    overview._order = 100
    local list = overview.List

    local refreshExpiry = self:_homeProfile(list, opts, 1)
    local refreshStats, resetStats = self:_homeStats(list, opts, 2, tab)

    -- Server and links side by side, stacked when narrow.
    local split = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = list,
    })
    local splitLayout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = split,
    })
    local function column(order_)
        local frame = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order_,
            Parent = split,
        })
        create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
        return frame
    end
    local leftColumn, rightColumn = column(1), column(2)
    local refreshGame = self:_homeGame(leftColumn, 1)
    local linksCard, refreshFeatures = self:_homeLinks(rightColumn, opts, 1)
    if not linksCard then
        rightColumn:Destroy()
    end
    local function fitSplit()
        local wide = linksCard ~= nil and split.AbsoluteSize.X / self.Scale.Scale >= 540
        splitLayout.FillDirection = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
        local size = wide and UDim2.new(0.5, -5, 0, 0) or UDim2.new(1, 0, 0, 0)
        leftColumn.Size = size
        if linksCard then
            rightColumn.Size = size
        end
    end
    split:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSplit)
    task.defer(fitSplit)

    self:_homeExecutor(list, opts, 4)

    if type(pages) == "table" then
        for _, page in ipairs(pages) do
            homePage(tab:SubTab({ Name = page.Name or page.Title or "Page", Icon = page.Icon }), page)
        end
    end

    refreshExpiry()
    refreshStats()
    refreshGame()
    task.spawn(function()
        while not self._destroyed and tab._page.Parent do
            task.wait(1)
            if self.Open and self.CurrentTab == tab then
                refreshStats()
                refreshExpiry()
                refreshGame()
                refreshFeatures()
            else
                resetStats()
            end
        end
    end)
    return tab
end

function Window:Tab(opts, icon)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = icon
    end
    local tab = setmetatable({
        Name = opts.Name or "Tab",
        Window = self,
        _order = 0,
    }, Tab)

    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, TAB_TILE_HEIGHT),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
        Parent = self._tabStack,
    })
    corner(button, UDim.new(0, 7))
    local buttonStroke = stroke(button, Theme.Stroke, 1)
    buttonStroke.Enabled = false
    tab._button = button

    local hasIcon = opts.Icon ~= nil
    if hasIcon then
        local iconImage = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 20, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(iconImage, opts.Icon)
        if iconImage:GetAttribute("CustomIcon") then
            iconImage.ImageTransparency = 0.4
        end
        tab._icon = iconImage
    end
    tab._label = label({
        Position = UDim2.fromOffset(hasIcon and 38 or 14, 0),
        Size = UDim2.new(1, hasIcon and -46 or -22, 1, 0),
        Text = tab.Name,
        TextSize = 13,
        TextColor3 = Theme.Muted,
        Parent = button,
    })

    local page = create("Frame", {
        Name = tab.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = self.Content,
    })
    tab._page = page
    local titleX = 24
    if hasIcon then
        local holder = glowIcon(page, opts.Icon, Theme.Accent, UDim2.new(0, 24, 0, 32))
        holder.Size = UDim2.fromOffset(20, 20)
        titleX = 54
    end
    tab._titleX = titleX
    tab._title = label({
        Position = UDim2.fromOffset(titleX, 20),
        Size = UDim2.new(1, -titleX, 0, 24),
        Text = opts.PageTitle or tab.Name,
        TextSize = 22,
        Parent = page,
    })
    if opts.Desc then
        tab._desc = label({
            Position = UDim2.fromOffset(titleX, 44),
            Size = UDim2.new(1, -titleX, 0, 16),
            Text = opts.Desc,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = page,
        })
    end
    local listTop = opts.Desc and 70 or 58
    tab._headerBottom = listTop
    tab._iconName = opts.Icon
    buildContainer(tab, page, listTop, opts.Icon or "layout-grid", opts.EmptyText or "Nothing here yet")

    local pressScale = create("UIScale", { Parent = button })
    local function release()
        tween(pressScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
    end
    button.MouseEnter:Connect(function()
        if self.CurrentTab ~= tab and not usingTouch() then
            tween(button, { BackgroundTransparency = 0.75 }, 0.2, Enum.EasingStyle.Quint)
            tween(tab._label, { TextColor3 = Theme.Text }, 0.2)
            if tab._icon then
                tintIcon(tab._icon, Theme.Text, true, 0.2)
            end
        end
    end)
    button.MouseLeave:Connect(function()
        release()
        if self.CurrentTab ~= tab then
            tween(button, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(tab._label, { TextColor3 = Theme.Muted }, 0.3)
            if tab._icon then
                tintIcon(tab._icon, Theme.Muted, false, 0.3)
            end
        end
    end)
    button.MouseButton1Down:Connect(function()
        tween(pressScale, { Scale = 0.97 }, 0.15, Enum.EasingStyle.Quint)
    end)
    button.MouseButton1Up:Connect(release)
    local isTap = tapGuard(button, function()
        return self.TabList
    end)
    button.MouseButton1Click:Connect(function()
        release()
        if isTap() then
            self:SelectTab(tab)
        end
    end)
    tab._stroke = buttonStroke
    self:_fitTitle(tab)

    if not self._introDone then
        button.Visible = false
    end
    table.insert(self.Tabs, tab)
    if #self.Tabs == 1 then
        task.defer(function()
            if not self.CurrentTab then
                self:SelectTab(tab)
            end
        end)
    end
    return tab
end

Window.CreateTab = Window.Tab

-- Tab badges were removed. These stay as no-ops so older scripts that call
-- them keep running.
function Tab:SetBadge() end

function Tab:GetBadge()
    return nil
end

function Window:Dialog(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content" })
    if self._dialog then
        self._dialog.Close()
    end
    local WIDTH = 300
    local PAD = 18

    local overlay = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = self.Body,
    })
    local card = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WIDTH, 120),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 41,
        Parent = overlay,
    })
    corner(card, UDim.new(0, 10))
    local cardStroke = stroke(card, Theme.Stroke, 1)
    local cardScale = create("UIScale", { Scale = 0.94, Parent = card })
    local fading = {}

    local titleOffset = 0
    if opts.Icon then
        local holder, image = glowIcon(card, opts.Icon, Theme.Accent, UDim2.new(0, PAD, 0, PAD + 9))
        image.ImageTransparency = 1
        holder.ZIndex = 42
        image.ZIndex = 42
        table.insert(fading, { image, "ImageTransparency", 0 })
        titleOffset = 24
    end
    local title = label({
        Position = UDim2.fromOffset(PAD + titleOffset, PAD),
        Size = UDim2.new(1, -(PAD * 2 + titleOffset), 0, 18),
        Text = opts.Title or "Are you sure?",
        TextSize = 15,
        TextTransparency = 1,
        ZIndex = 42,
        Parent = card,
    })
    table.insert(fading, { title, "TextTransparency", 0 })

    local contentHeight = 0
    if opts.Content then
        local content = label({
            Position = UDim2.fromOffset(PAD, PAD + 24),
            Size = UDim2.new(1, -PAD * 2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 42,
            Parent = card,
        })
        table.insert(fading, { content, "TextTransparency", 0 })
        contentHeight = math.max(content.TextBounds.Y, 16) + 6
        content:GetPropertyChangedSignal("TextBounds"):Connect(function()
            local newHeight = math.max(content.TextBounds.Y, 16) + 6
            if newHeight ~= contentHeight then
                contentHeight = newHeight
                card.Size = UDim2.fromOffset(WIDTH, PAD + 24 + contentHeight + 12 + 34 + PAD)
                local rowFrame = card:FindFirstChild("ButtonRow")
                if rowFrame then
                    rowFrame.Position = UDim2.fromOffset(PAD, PAD + 24 + contentHeight + 12)
                end
            end
        end)
    end

    local row = create("Frame", {
        Name = "ButtonRow",
        Position = UDim2.fromOffset(PAD, PAD + 24 + contentHeight + 12),
        Size = UDim2.new(1, -PAD * 2, 0, 34),
        BackgroundTransparency = 1,
        ZIndex = 42,
        Parent = card,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = row,
    })
    card.Size = UDim2.fromOffset(WIDTH, PAD + 24 + contentHeight + 12 + 34 + PAD)

    local dialog = {}
    local closed = false
    function dialog.Close()
        if closed then
            return
        end
        closed = true
        if self._dialog == dialog then
            self._dialog = nil
        end
        tween(overlay, { BackgroundTransparency = 1 }, 0.18)
        tween(card, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 8) }, 0.18, Enum.EasingStyle.Quint)
        tween(cardScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardStroke, { Transparency = 1 }, 0.12)
        for _, entry in ipairs(fading) do
            tween(entry[1], { [entry[2]] = 1 }, 0.12)
        end
        task.delay(0.2, function()
            overlay:Destroy()
        end)
    end

    for index, spec in ipairs(opts.Buttons or {}) do
        local primary = spec.Variant == "Primary"
        local buttonFrame = create("TextButton", {
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = primary and Theme.Accent or Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = index,
            ZIndex = 43,
            Parent = row,
        })
        corner(buttonFrame, UDim.new(0, 7))
        local buttonStroke = stroke(buttonFrame, primary and Theme.Accent or Theme.Stroke, 1)
        padding(buttonFrame, 14, 14)
        local text = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = spec.Title or spec.Name or "OK",
            TextSize = 13,
            TextColor3 = primary and Theme.AccentDark or Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTransparency = 1,
            ZIndex = 44,
            Parent = buttonFrame,
        })
        local restBg = primary and 0.12 or 0
        local restStroke = primary and 0.4 or 0
        table.insert(fading, { buttonFrame, "BackgroundTransparency", restBg })
        table.insert(fading, { buttonStroke, "Transparency", restStroke })
        table.insert(fading, { text, "TextTransparency", 0 })
        buttonFrame.MouseEnter:Connect(function()
            if closed then
                return
            end
            if primary then
                tween(buttonFrame, { BackgroundTransparency = 0 }, 0.12)
                tween(buttonStroke, { Transparency = 0 }, 0.12)
            else
                tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        buttonFrame.MouseLeave:Connect(function()
            if closed then
                return
            end
            if primary then
                tween(buttonFrame, { BackgroundTransparency = restBg }, 0.2)
                tween(buttonStroke, { Transparency = restStroke }, 0.2)
            else
                tween(buttonStroke, { Color = Theme.Stroke }, 0.2)
            end
        end)
        buttonFrame.MouseButton1Click:Connect(function()
            dialog.Close()
            safeCall(spec.Callback)
        end)
    end

    if opts.CloseOnBackdrop ~= false then
        overlay.MouseButton1Click:Connect(function()
            dialog.Close()
            safeCall(opts.OnCancel)
        end)
    end

    self._dialog = dialog
    tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
    tween(card, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.3, Enum.EasingStyle.Quint)
    tween(cardStroke, { Transparency = 0 }, 0.25)
    tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    for _, entry in ipairs(fading) do
        tween(entry[1], { [entry[2]] = entry[3] }, 0.25)
    end
    return dialog
end

function Window:Confirm(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content" })
    return self:Dialog({
        Title = opts.Title or "Are you sure?",
        Content = opts.Content,
        Icon = opts.Icon,
        OnCancel = opts.OnCancel,
        Buttons = {
            { Title = opts.CancelText or "Cancel", Callback = opts.OnCancel },
            { Title = opts.ConfirmText or "Confirm", Variant = "Primary", Callback = opts.Callback },
        },
    })
end

function Window:_listen(kind, handler, owner)
    local list = self._inputListeners[kind]
    table.insert(list, handler)
    local function disconnect()
        for index, entry in ipairs(list) do
            if entry == handler then
                table.remove(list, index)
                break
            end
        end
    end
    if owner then
        owner._listeners = owner._listeners or {}
        table.insert(owner._listeners, disconnect)
    end
    return disconnect
end

function Window:_indicatorY(tab)
    local stack = self._tabStack
    return (tab._button.AbsolutePosition.Y - stack.AbsolutePosition.Y) / self.Scale.Scale + stack.Position.Y.Offset
end

function Window:_placeIndicator(tab)
    local indicator = self.Indicator
    local targetY = self:_indicatorY(tab)
    if not indicator.Visible then
        indicator.Visible = true
        indicator.Position = UDim2.fromOffset(8, targetY)
        indicator.BackgroundTransparency = 1
        tween(indicator, { BackgroundTransparency = 0.35 }, 0.3)
    end
    tween(indicator, { Position = UDim2.fromOffset(8, targetY) }, 0.45, Enum.EasingStyle.Quint)
end

-- While a tab list or sub tab strip runs past an end, that end gets a fade
-- and a small chip with a chevron and how many tabs are out of sight there.
-- Pressing the chip scrolls most of a view toward them.
function Window:_overflowHint(host, scroller, items, vertical, fadeColor)
    local overlay = create("Frame", {
        AnchorPoint = scroller.AnchorPoint,
        Position = scroller.Position,
        Size = scroller.Size,
        BackgroundTransparency = 1,
        ZIndex = 3,
        Parent = host,
    })
    local function mirror()
        overlay.Position = scroller.Position
        overlay.Size = scroller.Size
        overlay.Visible = scroller.Visible
    end
    for _, property in ipairs({ "Position", "Size", "Visible" }) do
        scroller:GetPropertyChangedSignal(property):Connect(mirror)
    end

    local function axis(vector)
        return vertical and vector.Y or vector.X
    end
    local function scale()
        return self.Scale and self.Scale.Scale or 1
    end
    local function scrollBy(direction)
        local view = axis(scroller.AbsoluteWindowSize) / scale()
        local limit = math.max(axis(scroller.AbsoluteCanvasSize) / scale() - view, 0)
        local target = math.clamp(axis(scroller.CanvasPosition) + direction * view * 0.75, 0, limit)
        tween(scroller, { CanvasPosition = vertical and Vector2.new(0, target) or Vector2.new(target, 0) }, 0.35, Enum.EasingStyle.Quint)
    end

    local hints = {}
    for _, direction in ipairs({ -1, 1 }) do
        local far = direction > 0
        local fade = create("Frame", {
            AnchorPoint = vertical and Vector2.new(0, far and 1 or 0) or Vector2.new(far and 1 or 0, 0),
            Position = vertical and UDim2.fromScale(0, far and 1 or 0) or UDim2.fromScale(far and 1 or 0, 0),
            Size = vertical and UDim2.new(1, 0, 0, 34) or UDim2.new(0, 48, 1, 0),
            BackgroundColor3 = fadeColor,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            Parent = overlay,
        })
        create("UIGradient", {
            Rotation = vertical and (far and 270 or 90) or (far and 180 or 0),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.4, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = fade,
        })
        local home = vertical and UDim2.new(0.5, 0, far and 1 or 0, far and -5 or 5) or UDim2.new(far and 1 or 0, far and -2 or 2, 0.5, 0)
        local chip = create("TextButton", {
            AnchorPoint = vertical and Vector2.new(0.5, far and 1 or 0) or Vector2.new(far and 1 or 0, 0.5),
            Position = home,
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 2,
            Parent = overlay,
        })
        corner(chip, UDim.new(1, 0))
        local chipStroke = stroke(chip, Theme.Stroke, 1)
        padding(chip, 7, 7)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 3),
            Parent = chip,
        })
        local arrow = create("ImageLabel", {
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            ZIndex = 2,
            Parent = chip,
        })
        applyIcon(arrow, vertical and (far and "chevron-down" or "chevron-up") or (far and "chevron-right" or "chevron-left"))
        local arrowFade = "ImageTransparency"
        if arrow.Image == "" then
            arrow:Destroy()
            arrow = label({
                Size = UDim2.fromOffset(10, 20),
                Text = "›",
                TextSize = 16,
                TextColor3 = Theme.Accent,
                TextTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None,
                Rotation = vertical and (far and 90 or -90) or (far and 0 or 180),
                LayoutOrder = 1,
                ZIndex = 2,
                Parent = chip,
            })
            arrowFade = "TextTransparency"
        end
        local count = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            Visible = false,
            LayoutOrder = 2,
            ZIndex = 2,
            Parent = chip,
        })
        chip.MouseEnter:Connect(function()
            if not usingTouch() then
                tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        chip.MouseLeave:Connect(function()
            tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        end)
        chip.MouseButton1Click:Connect(function()
            scrollBy(direction)
        end)
        hints[direction] = {
            Direction = direction,
            Fade = fade,
            Chip = chip,
            Stroke = chipStroke,
            Arrow = arrow,
            ArrowFade = arrowFade,
            Count = count,
            Home = home,
            Shown = false,
            Generation = 0,
        }
    end

    local function show(hint, on)
        if hint.Shown == on then
            return
        end
        hint.Shown = on
        hint.Generation += 1
        local away = hint.Home + (vertical and UDim2.fromOffset(0, hint.Direction * 6) or UDim2.fromOffset(hint.Direction * 6, 0))
        local value = on and 0 or 1
        if on then
            hint.Fade.Visible = true
            hint.Chip.Visible = true
            hint.Chip.Position = away
            tween(hint.Chip, { Position = hint.Home, BackgroundTransparency = 0.08 }, 0.3, Enum.EasingStyle.Quint)
        else
            tween(hint.Chip, { Position = away, BackgroundTransparency = 1 }, 0.2, Enum.EasingStyle.Quint)
            local generation = hint.Generation
            task.delay(0.21, function()
                if hint.Generation == generation then
                    hint.Fade.Visible = false
                    hint.Chip.Visible = false
                end
            end)
        end
        tween(hint.Fade, { BackgroundTransparency = value }, 0.2)
        tween(hint.Stroke, { Transparency = value }, 0.2)
        tween(hint.Arrow, { [hint.ArrowFade] = value }, 0.2)
        tween(hint.Count, { TextTransparency = value }, 0.2)
    end

    local function refresh()
        local view = axis(scroller.AbsoluteWindowSize)
        local overflow = (axis(scroller.AbsoluteCanvasSize) - view) / scale()
        local position = axis(scroller.CanvasPosition)
        local start = axis(scroller.AbsolutePosition)
        local before, after = 0, 0
        for _, item in ipairs(items:GetChildren()) do
            if item:IsA("GuiObject") and item.Visible and axis(item.AbsoluteSize) > 0 then
                local centre = axis(item.AbsolutePosition) + axis(item.AbsoluteSize) / 2 - start
                if centre < 0 then
                    before += 1
                elseif centre > view then
                    after += 1
                end
            end
        end
        for direction, hint in pairs(hints) do
            local hidden = direction < 0 and before or after
            hint.Count.Text = tostring(hidden)
            hint.Count.Visible = hidden > 0
            show(hint, overflow > 1 and (direction < 0 and position > 1 or direction > 0 and position < overflow - 1))
        end
    end
    for _, property in ipairs({ "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" }) do
        scroller:GetPropertyChangedSignal(property):Connect(refresh)
    end
    task.defer(refresh)
end

function Window:_scrollTabIntoView(tab)
    local list = self.TabList
    local scale = self.Scale.Scale
    local top = (tab._button.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
    local bottom = top + tab._button.AbsoluteSize.Y / scale
    local view = list.AbsoluteWindowSize.Y / scale
    local y = list.CanvasPosition.Y
    if top - 8 < y then
        y = top - 8
    elseif bottom + 8 > y + view then
        y = bottom + 8 - view
    else
        return
    end
    tween(list, { CanvasPosition = Vector2.new(0, math.max(0, y)) }, 0.35, Enum.EasingStyle.Quint)
end

function Window:_closePopups()
    if self._closePopup then
        self._closePopup()
    end
end

-- Popped-out groupboxes float on one screen-wide layer above the window. It
-- carries the window's scale, so a panel keeps the size it had in its column,
-- and it shows while the window is open (minimized included).
function Window:_popoutLayer()
    if self._popLayer then
        return self._popLayer
    end
    local layer = create("Frame", {
        Name = "PopOuts",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 20,
        Parent = self.Gui,
    })
    local layerScale = create("UIScale", { Parent = layer })
    self._popLayer = layer
    self._popPanels = {}
    self:_listen("Render", function()
        local scale = math.max(self.Scale.Scale, 0.05)
        if math.abs(layerScale.Scale - scale) > 1e-4 then
            layerScale.Scale = scale
            layer.Size = UDim2.fromScale(1 / scale, 1 / scale)
        end
        layer.Visible = self.Open == true and not self._destroyed
    end)
    return layer
end

-- Where a control's popup is drawn: the pop-out layer for one inside a
-- floating panel, otherwise the window body.
function Window:_popupHost(object)
    local layer = self._popLayer
    if layer and object and object:IsDescendantOf(layer) then
        return layer
    end
    return self.Body
end

-- A floating panel under the point counts as a control, so pressing it never
-- starts a window drag.
function Window:_overPopout(point)
    local layer = self._popLayer
    if not layer or not layer.Visible then
        return false
    end
    for _, panel in ipairs(self._popPanels) do
        if panel.Parent and panel.Visible and pointInside(point, panel) then
            return true
        end
    end
    return false
end

-- Fades the whole body by lending it to the fader CanvasGroup, then hands it
-- back to the root once fully shown so it renders directly again.
function Window:_fade(target, duration)
    local fader, body = self._fader, self.Body
    self._fadeGeneration = (self._fadeGeneration or 0) + 1
    local generation = self._fadeGeneration
    if body.Parent ~= fader then
        fader.GroupTransparency = self._bodyAlpha
        body.Parent = fader
    end
    fader.Visible = true
    self._bodyAlpha = target
    tween(fader, { GroupTransparency = target }, duration)
    task.delay(duration + 0.03, function()
        if self._fadeGeneration == generation and target <= 0 and not self._destroyed then
            body.Parent = self.Root
            fader.Visible = false
        end
    end)
end

function Window:SelectTab(tab)
    if self.CurrentTab == tab then
        return
    end
    local previous = self.CurrentTab
    self:_resetSearch()
    self:_closePopups()
    self.CurrentTab = tab

    self:_settleTransition()
    local generation = (self._transitionGeneration or 0) + 1
    self._transitionGeneration = generation

    if previous then
        tween(previous._label, { TextColor3 = Theme.Muted }, 0.3)
        if previous._icon then
            tintIcon(previous._icon, Theme.Muted, false, 0.3)
        end
        local outLayer = self._outLayer
        previous._page.Parent = outLayer
        self._outPage = previous._page
        outLayer.GroupTransparency = 0
        outLayer.Position = UDim2.fromOffset(0, 0)
        outLayer.Visible = true
        tween(outLayer, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -6) }, 0.2, Enum.EasingStyle.Quint)
        task.delay(0.18, function()
            if self._transitionGeneration == generation then
                self:_settleOut()
            end
        end)
    end

    tween(tab._button, { BackgroundTransparency = 1 }, 0.2)
    tween(tab._stroke, { Transparency = 1 }, 0.2)
    tween(tab._label, { TextColor3 = Theme.Text }, 0.3)
    if tab._icon then
        tintIcon(tab._icon, Theme.Text, true, 0.3)
    end

    self:_placeIndicator(tab)
    self:_scrollTabIntoView(tab)

    local page = tab._page
    page.Position = UDim2.fromOffset(0, 0)
    page.Visible = true
    page.Parent = self._inLayer
    self._inPage = page
    fadeSlideIn(self._inLayer)
    task.delay(0.32, function()
        if self._transitionGeneration == generation then
            self:_settleIn()
        end
    end)
end

function Window:_settleOut()
    local page = self._outPage
    if page then
        page.Parent = self.Content
        page.Visible = false
        self._outPage = nil
    end
    self._outLayer.Visible = false
end

function Window:_settleIn()
    local page = self._inPage
    if page then
        page.Parent = self.Content
        page.Position = UDim2.fromOffset(0, 0)
        self._inPage = nil
    end
    self._inLayer.Visible = false
end

function Window:_settleTransition()
    self:_settleOut()
    self:_settleIn()
end

-- Backdrop: a black tint over the game while the window is up, with an
-- optional weather layer (rain, snow or hell fire embers) drifting through it.
-- It fades out when the window is minimized or hidden and sweeps back in with
-- a gust when it comes back.

local WEATHER = {
    -- The rain texture is a wide sheet with one faint streak down the middle
    -- (about 1/60 of its width, 57% of its height), so it is stretched much
    -- wider than the drop it draws. See RAIN_STREAK.
    Rain = { Image = "rbxassetid://241868005", Count = 90, Stretch = true },
    Snow = { Image = "rbxassetid://99851851", Count = 60 },
    Ember = { Image = "rbxassetid://242205518", Count = 55 },
    -- Drawn with plain frames and text, no images: petals are tinted pills
    -- that flip as they fall, matrix columns are text strips.
    Sakura = { Petal = true, Count = 46, Glow = Color3.fromRGB(255, 150, 190), GlowAmount = 0.1 },
    Fireflies = { Image = Assets.Glow, Count = 34, Glow = Color3.fromRGB(70, 150, 60), GlowAmount = 0.16 },
    Matrix = {
        Text = true,
        Count = 38,
        Glow = Color3.fromRGB(30, 200, 90),
        GlowAmount = 0.07,
        Glyphs = "01234567890123456789アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン+-*=<>:",
    },
}
local WEATHER_NAMES = {
    rain = "Rain",
    snow = "Snow",
    ember = "Ember",
    embers = "Ember",
    fire = "Ember",
    hellfire = "Ember",
    sakura = "Sakura",
    petals = "Sakura",
    cherryblossom = "Sakura",
    firefly = "Fireflies",
    fireflies = "Fireflies",
    matrix = "Matrix",
    matrixrain = "Matrix",
    code = "Matrix",
}
local RAIN_STREAK = Vector2.new(7 / 420, 151 / 263)
local weatherRandom = Random.new()

-- "UI" keeps the weather inside the window, behind its content; anything
-- else drifts it across the whole screen.
local function weatherMode(mode)
    if type(mode) == "string" and ({ ui = true, window = true, inside = true })[mode:lower()] then
        return "UI"
    end
    return "Screen"
end

local function weatherName(name)
    if type(name) ~= "string" then
        return "None"
    end
    return WEATHER_NAMES[(name:lower():gsub("[%s_%-]", ""))] or "None"
end

local function roll(min, max)
    return weatherRandom:NextNumber(min, max)
end

-- Places a particle. `anywhere` scatters it over the whole screen (first
-- frame after the backdrop appears), otherwise it enters from its edge.
local function seedParticle(kind, particle, width, height, anywhere)
    particle.Time = roll(0, 10)
    particle.Phase = roll(0, math.pi * 2)
    if kind == "Rain" then
        local w = roll(2, 3.5)
        particle.Size = Vector2.new(w, roll(26, 52))
        particle.VY = roll(950, 1400)
        particle.VX = particle.VY * 0.12
        particle.Sway, particle.Spin = 0, 0
        particle.Rotation = -math.deg(math.atan2(particle.VX, particle.VY))
        particle.Alpha = roll(0, 0.35)
        particle.X = roll(-0.15 * width, width)
        particle.Y = anywhere and roll(-40, height) or roll(-120, -particle.Size.Y)
    elseif kind == "Snow" then
        local s = roll(6, 17)
        particle.Size = Vector2.new(s, s)
        particle.VY = roll(30, 55) * (0.6 + s / 17)
        particle.VX = roll(-8, 14)
        particle.Sway = roll(12, 38)
        particle.Frequency = roll(0.5, 1.3)
        particle.Spin = roll(-60, 60)
        particle.Rotation = roll(0, 360)
        particle.Alpha = roll(0.05, 0.45)
        particle.X = roll(0, width)
        particle.Y = anywhere and roll(-20, height) or roll(-60, -s)
    elseif kind == "Sakura" then
        local s = roll(7, 14)
        particle.Size = Vector2.new(s, s * roll(0.55, 0.75))
        particle.VY = roll(35, 70)
        particle.VX = roll(18, 45)
        particle.Sway = roll(14, 34)
        particle.Frequency = roll(0.6, 1.4)
        particle.Flutter = roll(1.2, 2.6)
        particle.Spin = roll(-90, 90)
        particle.Rotation = roll(0, 360)
        particle.Alpha = roll(0.05, 0.35)
        particle.Color = Color3.fromRGB(255, 205, 220):Lerp(Color3.fromRGB(255, 140, 180), roll(0, 1))
        particle.X = roll(-0.25 * width, width)
        particle.Y = anywhere and roll(-20, height) or roll(-60, -s)
    elseif kind == "Fireflies" then
        -- They wander instead of crossing the screen, and live a few seconds:
        -- fade in, pulse, fade out, then turn up somewhere else.
        local s = roll(14, 28)
        particle.Size = Vector2.new(s, s)
        particle.VY = roll(-14, 8)
        particle.VX = roll(-12, 12)
        particle.Sway = roll(10, 30)
        particle.SwayY = roll(8, 22)
        particle.Frequency = roll(0.3, 0.8)
        particle.Spin, particle.Rotation = 0, 0
        particle.Alpha = roll(0, 0.25)
        particle.Life = roll(5, 11)
        particle.Age = anywhere and roll(0, particle.Life) or 0
        particle.Pulse = roll(1.5, 3.5)
        particle.Color = Color3.fromRGB(200, 255, 120):Lerp(Color3.fromRGB(255, 230, 120), roll(0, 1))
        particle.X = roll(0, width)
        particle.Y = roll(height * 0.15, height)
    elseif kind == "Matrix" then
        local definition = WEATHER.Matrix
        if not definition.List then
            definition.List = {}
            for _, code in utf8.codes(definition.Glyphs) do
                table.insert(definition.List, utf8.char(code))
            end
        end
        local list = definition.List
        local s = math.floor(roll(12, 19))
        local length = math.floor(roll(8, 20))
        particle.TextSize = s
        particle.Size = Vector2.new(s + 6, s * length)
        particle.VY = roll(160, 360) * (s / 15)
        particle.VX, particle.Sway, particle.Spin, particle.Rotation = 0, 0, 0, 0
        -- Smaller columns read as further away: dimmer.
        particle.Alpha = roll(0, 0.25) + (19 - s) * 0.04
        particle.X = math.floor(roll(0, width) / 18) * 18 + 9
        particle.Y = anywhere and roll(-particle.Size.Y / 2, height) or -particle.Size.Y / 2 - roll(0, 240)
        particle.Chars = {}
        for index = 1, length do
            particle.Chars[index] = list[math.random(#list)]
        end
        particle.Shuffle = roll(0.05, 0.2)
    else
        local s = roll(4, 12)
        particle.Size = Vector2.new(s, s)
        particle.VY = -roll(60, 170)
        particle.VX = roll(-12, 12)
        particle.Sway = roll(8, 28)
        particle.Frequency = roll(1, 2.4)
        particle.Spin = roll(-140, 140)
        particle.Rotation = roll(0, 360)
        particle.Alpha = roll(0, 0.3)
        particle.Color = Color3.fromRGB(255, 70, 20):Lerp(Color3.fromRGB(255, 190, 70), roll(0, 1))
        particle.X = roll(0, width)
        particle.Y = anywhere and roll(height * 0.2, height + 10) or height + roll(10, 80)
    end
    local label = particle.Label
    if kind == "Rain" then
        label.Size = UDim2.fromOffset(particle.Size.X / RAIN_STREAK.X, particle.Size.Y / RAIN_STREAK.Y)
    else
        label.Size = UDim2.fromOffset(particle.Size.X, particle.Size.Y)
    end
    if kind == "Matrix" then
        label.TextSize = particle.TextSize
        label.Text = table.concat(particle.Chars, "\n")
    elseif kind == "Sakura" then
        label.BackgroundColor3 = particle.Color
    else
        label.ImageColor3 = particle.Color
            or (kind == "Rain" and Color3.fromRGB(190, 210, 245) or Color3.new(1, 1, 1))
    end
end

function Window:_buildBackdrop(opts)
    local layer = create("Frame", {
        Name = "Backdrop",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = self.Gui,
    })
    local tint = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = layer,
    })
    -- Darker towards the top and bottom edges.
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = tint,
    })
    -- Heat rising from the bottom of the screen, hell fire only.
    local heat = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 0.5),
        BackgroundColor3 = Color3.fromRGB(255, 60, 15),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = layer,
    })
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(1, 0),
        Parent = heat,
    })
    -- Holds the heat and the particles so both move together between the
    -- screen and the window.
    local field = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = layer,
    })
    heat.Parent = field
    self._backdrop = layer
    self._backdropTintFrame = tint
    self._backdropHeat = heat
    self._weatherField = field
    self._weatherParticles = {}
    self._backdropFade = 0
    self._weatherKick = 0
    self._backdropShown = false
    self._backdropEnabled = opts.Enabled ~= false
    self._backdropTint = math.clamp(tonumber(opts.Tint) or 0.45, 0, 1)
    self._backdropDim = opts.Dim ~= false
    self._dimLevel = self._backdropDim and 1 or 0
    self._weatherDensity = math.clamp(tonumber(opts.Density) or 1, 0, 3)
    self._weatherSpeed = math.clamp(tonumber(opts.Speed) or 1, 0.1, 3)
    self.Weather = weatherName(opts.Weather == nil and "Snow" or opts.Weather)
    self.WeatherMode = "Screen"
    self:SetWeatherMode(opts.Mode)
    self:_rebuildWeather()
    table.insert(self._frameSteps, function(deltaTime)
        self:_stepBackdrop(deltaTime)
    end)
end

-- The area the particles cover, in the field's own (unscaled) units.
function Window:_weatherSize()
    if self.WeatherMode == "UI" then
        return Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
    end
    return self.Gui.AbsoluteSize
end

function Window:_rebuildWeather()
    for _, particle in ipairs(self._weatherParticles) do
        particle.Label:Destroy()
    end
    self._weatherParticles = {}
    local definition = WEATHER[self.Weather]
    if not definition then
        return
    end
    -- The glow along the bottom: red heat for hell fire, a soft tint for the
    -- others that ask for one.
    self._backdropHeat.BackgroundColor3 = definition.Glow or Color3.fromRGB(255, 60, 15)
    local size = self:_weatherSize()
    -- The window is a fraction of the screen, so it gets fewer particles.
    local count = definition.Count * self._weatherDensity * (self.WeatherMode == "UI" and 0.45 or 1)
    for _ = 1, math.floor(count + 0.5) do
        local instance, property
        if definition.Text then
            property = "TextTransparency"
            instance = create("TextLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = Color3.fromRGB(90, 255, 140),
                TextTransparency = 1,
                FontFace = Font.fromEnum(Enum.Font.Code),
                TextXAlignment = Enum.TextXAlignment.Center,
                TextYAlignment = Enum.TextYAlignment.Top,
                LineHeight = 1,
                ZIndex = 2,
                Parent = self._weatherField,
            })
            -- A fading tail and a pale leading glyph.
            create("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(0.88, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 255, 240)),
                }),
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(0.6, 0.45),
                    NumberSequenceKeypoint.new(1, 0),
                }),
                Parent = instance,
            })
        elseif definition.Petal then
            property = "BackgroundTransparency"
            instance = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Color3.fromRGB(255, 190, 210),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 2,
                Parent = self._weatherField,
            })
            corner(instance, UDim.new(1, 0))
            create("UIGradient", {
                Rotation = 35,
                Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(235, 200, 215)),
                Parent = instance,
            })
        else
            property = "ImageTransparency"
            instance = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Image = definition.Image,
                ImageTransparency = 1,
                ScaleType = definition.Stretch and Enum.ScaleType.Stretch or Enum.ScaleType.Fit,
                ZIndex = 2,
                Parent = self._weatherField,
            })
        end
        local particle = { Label = instance, Property = property }
        seedParticle(self.Weather, particle, size.X, size.Y, true)
        table.insert(self._weatherParticles, particle)
    end
end

function Window:_stepBackdrop(deltaTime)
    local target = self._backdropShown and 1 or 0
    local fade = self._backdropFade
    if fade == target and target == 0 then
        return
    end
    if fade < target then
        fade = math.min(fade + deltaTime / 0.45, target)
    elseif fade > target then
        fade = math.max(fade - deltaTime / 0.25, target)
    end
    self._backdropFade = fade
    if fade <= 0 then
        self._backdrop.Visible = false
        self._weatherField.Visible = false
        return
    end
    local eased = 1 - (1 - fade) ^ 3
    local kind = self.Weather
    -- The dim eases on its own so turning it off doesn't touch the weather.
    local dim = self._dimLevel
    if self._backdropDim then
        dim = math.min(dim + deltaTime / 0.3, 1)
    else
        dim = math.max(dim - deltaTime / 0.3, 0)
    end
    self._dimLevel = dim
    self._backdropTintFrame.BackgroundTransparency = 1 - self._backdropTint * eased * dim
    local definition = WEATHER[kind]
    self._backdropHeat.BackgroundTransparency = kind == "Ember"
        and 1 - (0.22 + math.sin(os.clock() * 2.1) * 0.05) * eased
        or definition and definition.GlowAmount and 1 - (definition.GlowAmount + math.sin(os.clock() * 0.8) * definition.GlowAmount * 0.25) * eased
        or 1

    -- The gust on restore: particles rush in fast and settle back.
    local kick = self._weatherKick
    self._weatherKick = math.max(kick - deltaTime * 1.3, 0)
    local speed = self._weatherSpeed * (1 + kick * kick * 2.5)
    local size = self:_weatherSize()
    local width, height = size.X, size.Y
    for _, particle in ipairs(self._weatherParticles) do
        particle.Time += deltaTime
        particle.X += particle.VX * deltaTime * speed
        particle.Y += particle.VY * deltaTime * speed
        particle.Rotation += particle.Spin * deltaTime * speed
        local margin = math.max(particle.Size.X, particle.Size.Y)
        if particle.Life then
            particle.Age += deltaTime
        end
        if (particle.Life and particle.Age > particle.Life)
            or (not particle.Life and ((particle.VY > 0 and particle.Y > height + margin) or (particle.VY < 0 and particle.Y < -margin))) then
            seedParticle(kind, particle, width, height, false)
        elseif particle.X > width + margin * 4 then
            particle.X -= width + margin * 6
        elseif particle.X < -margin * 4 then
            particle.X += width + margin * 6
        end
        local x = particle.X
        local alpha = 1 - particle.Alpha
        if particle.Sway ~= 0 then
            x += math.sin(particle.Time * particle.Frequency + particle.Phase) * particle.Sway
        end
        local y = particle.Y
        local label = particle.Label
        if kind == "Ember" then
            -- Flicker, and burn out on the way up.
            alpha *= math.clamp(particle.Y / (height * 0.85), 0, 1) ^ 0.6
            alpha *= 0.75 + math.sin(particle.Time * 9 + particle.Phase) * 0.25
        elseif kind == "Sakura" then
            -- Flip: the petal narrows and widens as it turns over.
            local turn = math.abs(math.cos(particle.Time * particle.Flutter + particle.Phase))
            label.Size = UDim2.fromOffset(particle.Size.X * (0.3 + turn * 0.7), particle.Size.Y)
        elseif kind == "Fireflies" then
            y += math.cos(particle.Time * particle.Frequency * 1.3 + particle.Phase) * particle.SwayY
            local age, life = particle.Age, particle.Life
            alpha *= math.clamp(math.min(age / 1.2, (life - age) / 1.2), 0, 1)
            alpha *= 0.5 + math.sin(particle.Time * particle.Pulse + particle.Phase) * 0.5
        elseif kind == "Matrix" then
            particle.Shuffle -= deltaTime * speed
            if particle.Shuffle <= 0 then
                particle.Shuffle = roll(0.05, 0.2)
                local list = WEATHER.Matrix.List
                local chars = particle.Chars
                chars[math.random(#chars)] = list[math.random(#list)]
                chars[#chars] = list[math.random(#list)]
                label.Text = table.concat(chars, "\n")
            end
        end
        label.Position = UDim2.fromOffset(x, y)
        label.Rotation = particle.Rotation
        label[particle.Property or "ImageTransparency"] = 1 - alpha * eased
    end
end

function Window:_refreshBackdrop(gust)
    if not self._backdrop then
        return
    end
    local shown = self._backdropEnabled and self._introDone and self.Open and not self.Minimized and not self._destroyed
    if shown and not self._backdropShown then
        self._backdrop.Visible = true
        self._weatherField.Visible = true
        if self._backdropFade <= 0 then
            local size = self:_weatherSize()
            for _, particle in ipairs(self._weatherParticles) do
                seedParticle(self.Weather, particle, size.X, size.Y, true)
            end
        end
        if gust then
            self._weatherKick = 1
        end
    end
    self._backdropShown = shown == true
end

function Window:SetBackdrop(enabled)
    if not self._backdrop then
        return
    end
    self._backdropEnabled = enabled ~= false
    self:_refreshBackdrop(true)
end

function Window:SetBackdropTint(amount)
    if not self._backdrop then
        return
    end
    self._backdropTint = math.clamp(tonumber(amount) or 0.45, 0, 1)
end

-- Turns the black tint on or off, leaving the weather running.
function Window:SetDim(enabled)
    if not self._backdrop then
        return
    end
    self._backdropDim = enabled ~= false
end

function Window:SetWeatherMode(mode)
    if not self._backdrop then
        return
    end
    mode = weatherMode(mode)
    local field = self._weatherField
    if mode == "UI" then
        -- Under everything else in the body: sidebar, content and glows.
        field.ZIndex = 0
        field.Parent = self.Body
    else
        field.ZIndex = 2
        field.Parent = self._backdrop
    end
    if mode == self.WeatherMode then
        return
    end
    self.WeatherMode = mode
    self:_rebuildWeather()
    if self._backdropShown then
        self._weatherKick = 1
    end
end

function Window:SetWeather(name)
    if not self._backdrop then
        return
    end
    local kind = weatherName(name)
    if kind == self.Weather then
        return
    end
    self.Weather = kind
    self:_rebuildWeather()
    if self._backdropShown then
        self._weatherKick = 1
    end
end

function Window:SetWeatherDensity(density)
    if not self._backdrop then
        return
    end
    self._weatherDensity = math.clamp(tonumber(density) or 1, 0, 3)
    self:_rebuildWeather()
end

function Window:SetWeatherSpeed(speed)
    if not self._backdrop then
        return
    end
    self._weatherSpeed = math.clamp(tonumber(speed) or 1, 0.1, 3)
end

-- Minimize: the window folds into a Dynamic Island style pill hanging from
-- the top of the screen. Compact, it shows the logo and a live meter of
-- running toggles. Hovering springs it open into a session card: the
-- player, the game and session time, frame rate and ping meters, the server
-- and running counts, and the key that reopens the window. A
-- notification while minimized opens it briefly to show it. Click or tap
-- restores.

-- One table, not separate locals: the main chunk is at Luau's 200 local limit.
local Mini = {
    -- Sized after the iPhone 18 island: a slimmer, shorter pill sitting close
    -- to the top edge, opening into a wide card with deep rounded corners.
    Top = 8, -- gap from the top of the screen
    Width = TOUCH and 176 or 168, -- compact
    Height = TOUCH and 36 or 32,
    Wide = 340, -- expanded and activity
    Radius = 34, -- corner of the expanded and activity cards
    Bars = 4,
    Pinned = 6,
}

-- The morph is carried by a plain "ghost" panel drawn over the window. The
-- window body itself never moves or fades, so nothing has to be laid out
-- again mid-animation: the ghost covers it, the window is hidden underneath,
-- and on the way back the window is shown under the ghost before it clears.
local function makeGhost(window, position, size, radius)
    if window._ghost then
        window._ghost:Destroy()
    end
    local ghost = create("Frame", {
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 29,
        Parent = window.Gui,
    })
    local ghostCorner = Library._fixedCorner(ghost, UDim.new(0, radius))
    local ghostStroke = stroke(ghost, Theme.Stroke, 1)
    window._ghost = ghost
    return ghost, ghostStroke, ghostCorner
end

local function morphGhost(ghost, ghostCorner, position, size, radius, duration)
    tween(ghost, {
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
    }, duration, Enum.EasingStyle.Quint)
    tween(ghostCorner, { CornerRadius = UDim.new(0, radius) }, duration, Enum.EasingStyle.Quint)
end

local function dissolve(window, ghost, ghostStroke, duration)
    tween(ghost, { BackgroundTransparency = 1 }, duration, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 1 }, duration, Enum.EasingStyle.Quad)
    task.delay(duration + 0.02, function()
        if window._ghost == ghost then
            window._ghost = nil
        end
        ghost:Destroy()
    end)
end

function Window:_buildMiniBar()
    if self.MiniBar then
        return self.MiniBar
    end
    local gui = self.Gui

    -- The island itself: a themed pill hanging from the top of the screen. It
    -- is a canvas so its rounded shape clips whatever layer is showing.
    local island = create("CanvasGroup", {
        Name = "Island",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, Mini.Top),
        Size = UDim2.fromOffset(Mini.Width, Mini.Height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    local islandCorner = Library._fixedCorner(island, UDim.new(0, Mini.Height / 2))
    local islandScale = create("UIScale", { Parent = island })
    self._miniScale = islandScale
    -- How far the split bubble is out of the pill: drawn back in while the
    -- island is open, budded off again once it settles to the pill.
    local merge = create("NumberValue", { Value = 1 })
    local mergeTween
    self._miniOrb = island

    -- The wide layers keep a fixed width, so nothing reflows while the island
    -- grows around them.
    local function layer(name)
        return create("CanvasGroup", {
            Name = name,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0, Mini.Wide, 0, 400),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            Parent = island,
        })
    end

    -- Compact: the logo leading, a live meter of running toggles trailing.
    -- A raised theme surface, lit from the top, so the pill isn't a flat
    -- slab; it fades with the layer, leaving the open card on Background.
    local compact = create("CanvasGroup", {
        Name = "Compact",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Parent = island,
    })
    create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 120, 120)),
        Parent = compact,
    })
    -- The logo sits in a soft accent disc, like an app glyph.
    local logoDisc = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 5, 0.5, 0),
        Size = UDim2.fromOffset(Mini.Height - 10, Mini.Height - 10),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Parent = compact,
    })
    corner(logoDisc, UDim.new(1, 0))
    local logo = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = logoDisc,
    })
    applyIcon(logo, self._logoIcon, true)
    -- The script's name beside the logo, so the pill reads at a glance.
    local miniTitle = label({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, Mini.Height + 2, 0.5, 0),
        Size = UDim2.new(1, -Mini.Height - 2 - 72, 0, 18),
        Text = self.Title,
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextColor3 = Theme.Text,
        Parent = compact,
    })
    local meter = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = compact,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
        Parent = meter,
    })
    local barsHolder = create("Frame", {
        Size = UDim2.fromOffset(Mini.Bars * 3 + (Mini.Bars - 1) * 2, 16),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 1,
        Parent = meter,
    })
    local bars = {}
    for index = 1, Mini.Bars do
        local bar = create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, (index - 1) * 5, 0.5, 0),
            Size = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            Parent = barsHolder,
        })
        corner(bar, UDim.new(1, 0))
        bars[index] = bar
    end
    local countLabel = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "",
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        LayoutOrder = 2,
        Parent = meter,
    })
    -- Idle (nothing running): a health dot tinted by frame rate and the
    -- session clock, so the pill never sits empty.
    local idleDot = create("Frame", {
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        LayoutOrder = -1,
        Parent = meter,
    })
    corner(idleDot, UDim.new(1, 0))
    local idleLabel = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "0s",
        TextSize = 12,
        FontFace = Fonts.Bold,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 0,
        Parent = meter,
    })

    -- Expanded, on hover: the player's session.
    local expanded = layer("Expanded")
    local expandedList = create("Frame", {
        Position = UDim2.fromOffset(16, 14),
        Size = UDim2.new(1, -32, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = expanded,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = expandedList,
    })
    -- The open card is the player's session, like a now-playing card: who
    -- and where on top with the session clock, two wide meters for frame
    -- rate and ping, then chips for the server and what's running.
    local top = create("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = expandedList,
    })
    local face = create("ImageLabel", {
        Size = UDim2.fromOffset(48, 48),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Parent = top,
    })
    corner(face, UDim.new(0, 12))
    local facePlaceholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = face,
    })
    applyIcon(facePlaceholder, "user")
    self:_trackAvatar(face, facePlaceholder)
    local nameLabel = label({
        Position = UDim2.fromOffset(60, 5),
        Size = UDim2.new(1, -150, 0, 20),
        TextSize = 15,
        FontFace = Fonts.Bold,
        TextColor3 = Theme.Text,
        Parent = top,
    })
    self:_trackName(nameLabel, "Display")
    local tabLabel = label({
        Position = UDim2.fromOffset(60, 26),
        Size = UDim2.new(1, -150, 0, 15),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = top,
    })
    task.spawn(function()
        tabLabel.Text = detectGameName()
    end)
    local sessionLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 3),
        Size = UDim2.fromOffset(90, 24),
        Text = "0s",
        TextSize = 20,
        FontFace = Fonts.Bold,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = top,
    })
    label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 27),
        Size = UDim2.fromOffset(90, 14),
        Text = "session",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = top,
    })

    -- Two readouts: a large number with its unit, a caption, and a thin
    -- line under them that fills and tints with how healthy it is.
    local meters = create("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = expandedList,
    })
    local function meterPill(position, caption)
        local cell = create("Frame", {
            Position = position,
            Size = UDim2.new(0.5, -10, 1, 0),
            BackgroundTransparency = 1,
            Parent = meters,
        })
        local value = label({
            Size = UDim2.new(1, -70, 0, 24),
            Text = "",
            TextSize = 20,
            FontFace = Fonts.Bold,
            TextColor3 = Theme.Text,
            RichText = true,
            Parent = cell,
        })
        label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 6),
            Size = UDim2.fromOffset(70, 14),
            Text = caption,
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = cell,
        })
        local track = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, -4),
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = Theme.Surface3,
            BorderSizePixel = 0,
            Parent = cell,
        })
        corner(track, UDim.new(1, 0))
        local fill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = Theme.Success,
            BorderSizePixel = 0,
            Parent = track,
        })
        corner(fill, UDim.new(1, 0))
        return fill, value
    end
    local fpsFill, fpsValue = meterPill(UDim2.fromScale(0, 0), "FRAME RATE")
    local pingFill, pingValue = meterPill(UDim2.new(0.5, 10, 0, 0), "PING")

    -- Chips: a muted name and a bold value, the running count in accent.
    local chips = create("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = expandedList,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = chips,
    })
    local function chipOf(order, name, color)
        local chipFrame = create("Frame", {
            Size = UDim2.fromOffset(0, 30),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            LayoutOrder = order,
            Parent = chips,
        })
        corner(chipFrame, UDim.new(1, 0))
        padding(chipFrame, 14, 14)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 7),
            Parent = chipFrame,
        })
        label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = name,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = chipFrame,
        })
        return label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 12,
            FontFace = Fonts.Bold,
            TextColor3 = color or Theme.Text,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = chipFrame,
        })
    end
    local playersValue = chipOf(1, "Players")
    local bigCount = chipOf(2, "Running", Theme.Accent)
    local tabValue = chipOf(3, "Tab")

    -- Pinned statuses are no longer shown here; the holder stays so the
    -- refresh below has somewhere to keep its rows.
    local rowsHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 4,
        Parent = expandedList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = rowsHolder,
    })
    -- What's running, by name, so the count above has something behind it.
    local runningNames = label({
        Size = UDim2.new(1, 0, 0, 15),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        RichText = true,
        Visible = false,
        LayoutOrder = 4,
        Parent = expandedList,
    })
    local hint = label({
        Size = UDim2.new(1, 0, 0, 14),
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        LayoutOrder = 5,
        Parent = expandedList,
    })

    -- Frame rate is counted every frame; the card's values refresh twice a
    -- second while it's open.
    local sessionStart = self._sessionStart or os.clock()
    local frames, frameClock, fps = 0, os.clock(), 60
    self:_listen("Render", function()
        frames += 1
        local now = os.clock()
        if now - frameClock >= 0.5 then
            fps = math.floor(frames / (now - frameClock) + 0.5)
            frames, frameClock = 0, now
        end
    end)
    local function refreshSession()
        sessionLabel.Text = formatDuration(os.clock() - sessionStart)
        idleLabel.Text = sessionLabel.Text
        tween(idleDot, { BackgroundColor3 = Library._healthColor(fps, 50, 30) }, 0.4)
        local unit = '<font size="12" color="#8A8A93"> %s</font>'
        fpsValue.Text = fps .. string.format(unit, "fps")
        tween(fpsFill, {
            Size = UDim2.fromScale(math.clamp(fps / 60, 0.05, 1), 1),
            BackgroundColor3 = Library._healthColor(fps, 50, 30),
        }, 0.4, Enum.EasingStyle.Quint)
        local okPing, ping = pcall(function()
            return math.floor(LocalPlayer:GetNetworkPing() * 1000)
        end)
        ping = okPing and ping or 0
        pingValue.Text = ping .. string.format(unit, "ms")
        -- Lower ping fills more: 40ms or less is full, 400ms and up is low.
        tween(pingFill, {
            Size = UDim2.fromScale(math.clamp(1 - (ping - 40) / 360, 0.05, 1), 1),
            BackgroundColor3 = Library._healthColor(ping, 90, 180, true),
        }, 0.4, Enum.EasingStyle.Quint)
        playersValue.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
        local tab = self.CurrentTab
        tabValue.Text = tab and tab.Name or "-"
    end
    task.spawn(function()
        while island.Parent do
            if island.Visible and self.Minimized then
                refreshSession()
            end
            task.wait(0.5)
        end
    end)

    -- Activity: a notification that arrives while minimized drops in here.
    local activity = layer("Activity")
    local activityList = create("Frame", {
        Position = UDim2.fromOffset(16, 13),
        Size = UDim2.new(1, -32, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = activity,
    })
    local activityChip = create("Frame", {
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        Parent = activityList,
    })
    corner(activityChip, UDim.new(1, 0))
    local activityIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = activityChip,
    })
    local activityText = create("Frame", {
        Position = UDim2.fromOffset(46, 0),
        Size = UDim2.new(1, -46, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = activityList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
        Parent = activityText,
    })
    local activityTitle = label({
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 14,
        FontFace = Fonts.Bold,
        LayoutOrder = 1,
        Parent = activityText,
    })
    local activityBody = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        MaxVisibleGraphemes = 140,
        LayoutOrder = 2,
        Parent = activityText,
    })

    local hit = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,
        Parent = island,
    })

    -- Morphing between shapes: the island springs to its new size while the
    -- old layer fades out and the new one fades in just behind it.
    local layers = { Compact = compact, Expanded = expanded, Activity = activity }
    local mode = "Compact"
    local modeToken = 0
    local sizeTween, cornerTween
    local hovered, pressed = false, false
    local hoverToken = 0
    local dragFrom, dragAnchor, dragging, dragged = nil, nil, false, false
    local activityToken = 0
    local activityLive = false

    local function shapeFor(name)
        if name == "Expanded" then
            return Vector2.new(Mini.Wide, math.floor(expandedList.AbsoluteSize.Y + 28 + 0.5)), Mini.Radius
        elseif name == "Activity" then
            return Vector2.new(Mini.Wide, math.floor(math.max(activityList.AbsoluteSize.Y, 34) + 26 + 0.5)), Mini.Radius
        end
        return Vector2.new(Mini.Width, Mini.Height), Mini.Height / 2
    end

    -- Where the island hangs: the top centre of its shape, as fractions of
    -- the screen so it keeps its spot across resolutions. Dragging moves it;
    -- each shape is clamped on screen, so the wide card slides in from an edge
    -- and the pill goes back to its spot when it folds.
    local saved = self:_readConfigSettings().IslandPosition
    if type(saved) == "table" and tonumber(saved.X) and tonumber(saved.Y) then
        self._islandAnchor = Vector2.new(math.clamp(tonumber(saved.X), 0, 1), math.clamp(tonumber(saved.Y), 0, 1))
    end
    local positionTween
    local function anchorPixels()
        local view = gui.AbsoluteSize
        local anchor = self._islandAnchor
        if not anchor then
            return Vector2.new(view.X / 2, Mini.Top)
        end
        return Vector2.new(anchor.X * view.X, anchor.Y * view.Y)
    end
    local function islandSpot(size, from)
        local view = gui.AbsoluteSize
        local spot = from or anchorPixels()
        local margin = 6
        local x = math.clamp(spot.X, size.X / 2 + margin, math.max(view.X - size.X / 2 - margin, size.X / 2 + margin))
        local y = math.clamp(spot.Y, margin, math.max(view.Y - size.Y - margin, margin))
        return Vector2.new(x, y)
    end
    local function placeIsland(size, duration, style)
        local spot = islandSpot(size)
        if positionTween then
            positionTween:Cancel()
            positionTween = nil
        end
        if duration and duration > 0 then
            positionTween = tween(island, { Position = UDim2.fromOffset(spot.X, spot.Y) }, duration, style or Enum.EasingStyle.Quint)
        else
            island.Position = UDim2.fromOffset(spot.X, spot.Y)
        end
    end
    self._islandReset = function()
        self._islandAnchor = nil
        if island.Visible then
            placeIsland(Vector2.new(island.Size.X.Offset, island.Size.Y.Offset), 0.35)
        end
    end

    local function setMode(name, instant)
        local size, radius = shapeFor(name)
        local changed = name ~= mode
        mode = name
        modeToken += 1
        local token = modeToken
        local current = Vector2.new(island.Size.X.Offset, island.Size.Y.Offset)
        local growing = size.X > current.X + 1 or size.Y > current.Y + 1
        local duration = instant and 0 or (growing and 0.5 or 0.38)
        -- A snap must stop a morph still in flight, or it keeps writing the
        -- old shape over the new one.
        if sizeTween then
            sizeTween:Cancel()
        end
        if cornerTween then
            cornerTween:Cancel()
        end
        placeIsland(size, duration)
        sizeTween = tween(island, { Size = UDim2.fromOffset(size.X, size.Y) }, duration, growing and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
        cornerTween = tween(islandCorner, { CornerRadius = UDim.new(0, radius) }, duration, Enum.EasingStyle.Quint)
        -- The iOS island gives a soft squeeze as it swells open, then springs
        -- back, so the morph reads as one elastic body rather than a resize.
        if changed and not instant and not pressed and not dragging then
            islandScale.Scale = growing and 0.96 or 1.03
            tween(islandScale, { Scale = 1 }, growing and 0.55 or 0.4, Enum.EasingStyle.Back)
        end
        if changed or instant then
            if mergeTween then
                mergeTween:Cancel()
                mergeTween = nil
            end
            if instant then
                merge.Value = name == "Compact" and 1 or 0
            elseif name == "Compact" then
                -- Wait for the pill to shrink most of the way, then bud off.
                task.delay(duration * 0.55, function()
                    if modeToken == token then
                        mergeTween = tween(merge, { Value = 1 }, 0.6, Enum.EasingStyle.Back)
                    end
                end)
            else
                mergeTween = tween(merge, { Value = 0 }, 0.2, Enum.EasingStyle.Quint)
            end
        end
        if not changed and not instant then
            -- A refit (same shape, new height) bumps the token, which cancels
            -- a fade-in still waiting from the morph; finish it here or the
            -- card stays black until the next hover.
            local target = layers[name]
            if target.GroupTransparency > 0 then
                tween(target, { GroupTransparency = 0 }, 0.22, Enum.EasingStyle.Quad)
            end
            if target ~= compact and target.Position ~= UDim2.fromScale(0.5, 0) then
                tween(target, { Position = UDim2.fromScale(0.5, 0) }, 0.32, Enum.EasingStyle.Quint)
            end
            return
        end
        for key, group in pairs(layers) do
            if key ~= name then
                tween(group, { GroupTransparency = 1 }, instant and 0 or 0.14, Enum.EasingStyle.Quad)
            end
        end
        local target = layers[name]
        if instant then
            target.GroupTransparency = 0
            -- Compact fills the island from its corner; only the wide
            -- layers hang from the centre.
            if target ~= compact then
                target.Position = UDim2.fromScale(0.5, 0)
            end
        else
            -- The new layer rises a few pixels into place as it fades in, so
            -- the content reads as arriving with the shape, not popping in.
            if target ~= compact then
                target.Position = UDim2.new(0.5, 0, 0, 6)
            end
            task.delay(0.1, function()
                if modeToken == token then
                    tween(target, { GroupTransparency = 0 }, 0.22, Enum.EasingStyle.Quad)
                    if target ~= compact then
                        tween(target, { Position = UDim2.fromScale(0.5, 0) }, 0.32, Enum.EasingStyle.Quint)
                    end
                end
            end)
        end
    end

    local function settleMode()
        if hovered and not TOUCH and not dragging then
            setMode("Expanded")
        elseif activityLive then
            setMode("Activity")
        elseif self.IslandStyle == "Always Show" and not dragging then
            self:_refreshMini()
            refreshSession()
            setMode("Expanded")
        else
            setMode("Compact")
        end
    end

    self._islandSettle = function()
        if self.Minimized and island.Visible and not dragging then
            settleMode()
        end
    end

    -- Called by Minimize once the window is out of the way: the island is
    -- reset to its compact pill and its spot handed back for the ghost.
    function self:_miniLand()
        hovered, activityLive = false, false
        activityToken += 1
        islandScale.Scale = 1
        setMode("Compact", true)
        local size = Vector2.new(Mini.Width, Mini.Height)
        local spot = islandSpot(size)
        return Vector2.new(spot.X - size.X / 2, spot.Y), size
    end

    hit.MouseEnter:Connect(function()
        if usingTouch() or dragging then
            return
        end
        hovered = true
        hoverToken += 1
        local token = hoverToken
        -- Already open (the pointer left and came back within the grace):
        -- just stay. Otherwise lean in a touch, and only open once the
        -- pointer rests, so sweeping past the island doesn't burst it open.
        if mode == "Expanded" then
            return
        end
        if not pressed then
            tween(islandScale, { Scale = 1.04 }, 0.18, Enum.EasingStyle.Quint)
        end
        task.delay(0.12, function()
            if hoverToken == token and hovered and self.Minimized and not dragging then
                self:_refreshMini()
                refreshSession()
                setMode("Expanded")
            end
        end)
    end)
    hit.MouseLeave:Connect(function()
        hovered = false
        hoverToken += 1
        local token = hoverToken
        if not pressed then
            tween(islandScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
        end
        -- A grace period: the card shifts while it morphs and clamps on
        -- screen, so a pointer grazing its edge shouldn't snap it shut.
        task.delay(mode == "Expanded" and 0.28 or 0.1, function()
            if hoverToken == token and not hovered and self.Minimized then
                settleMode()
            end
        end)
    end)
    -- Press and pull to move the island anywhere on screen. It folds to the
    -- pill while carried, lifts a little, and a drop near its home at the top
    -- centre snaps back there. A drag never counts as the click that restores.
    hit.InputBegan:Connect(function(input)
        if not isPress(input) then
            return
        end
        pressed = true
        dragged = false
        tween(islandScale, { Scale = 0.95 }, 0.12, Enum.EasingStyle.Quad)
        if not self._islandLocked then
            dragFrom = Vector2.new(input.Position.X, input.Position.Y)
            dragAnchor = islandSpot(Vector2.new(Mini.Width, Mini.Height))
        end
    end)
    self:_listen("Changed", function(input)
        if not dragFrom or not isMove(input) or not self.Minimized then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragFrom
        if not dragging then
            if delta.Magnitude < (TOUCH and 10 or 6) then
                return
            end
            dragging, dragged = true, true
            hovered = false
            setMode("Compact")
            tween(islandScale, { Scale = 1.06 }, 0.2, Enum.EasingStyle.Quint)
        end
        local spot = islandSpot(Vector2.new(Mini.Width, Mini.Height), dragAnchor + delta)
        local view = gui.AbsoluteSize
        self._islandAnchor = Vector2.new(spot.X / math.max(view.X, 1), spot.Y / math.max(view.Y, 1))
        if positionTween then
            positionTween:Cancel()
            positionTween = nil
        end
        island.Position = UDim2.fromOffset(spot.X, spot.Y)
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not isPress(input) then
            return
        end
        dragFrom = nil
        if pressed then
            pressed = false
            tween(islandScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
        end
        if dragging then
            dragging = false
            local home = Vector2.new(gui.AbsoluteSize.X / 2, Mini.Top)
            local spot = islandSpot(Vector2.new(Mini.Width, Mini.Height))
            if (spot - home).Magnitude < 28 then
                self._islandAnchor = nil
                placeIsland(Vector2.new(Mini.Width, Mini.Height), 0.35, Enum.EasingStyle.Back)
            end
            local anchor = self._islandAnchor
            self:_writeConfigSettings({ IslandPosition = anchor and { X = anchor.X, Y = anchor.Y } or false })
            hovered = not usingTouch() and pointInside(pointerPosition(), island)
            task.delay(0.1, function()
                if self.Minimized and not dragging then
                    settleMode()
                end
            end)
        end
    end))
    -- Keeps the island on screen when the viewport changes size.
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if island.Visible and not dragging then
            placeIsland(Vector2.new(island.Size.X.Offset, island.Size.Y.Offset), 0)
        end
    end))
    hit.MouseButton1Click:Connect(function()
        if dragged then
            dragged = false
            return
        end
        if self.Minimized then
            self:Restore()
        end
    end)
    -- Restore hides the island under the pointer, so MouseLeave never fires.
    self._miniUnhover = function()
        hovered, pressed, activityLive = false, false, false
        dragFrom, dragging = nil, false
        activityToken += 1
        islandScale.Scale = 1
        -- Clicked open while expanded: once the island has faded out, fold it
        -- back to the pill so the next minimize starts from it.
        task.delay(0.15, function()
            if not self.Minimized then
                setMode("Compact", true)
            end
        end)
    end

    -- A notification while minimized: the island opens to show it for a few
    -- seconds, then folds back.
    self._islandActivity = function(opts)
        if not self.Minimized or not island.Visible then
            return
        end
        local color = NOTIFY_COLORS[opts.Type] or Theme.Accent
        activityTitle.Text = tostring(opts.Title or "Notification")
        activityTitle.TextColor3 = NOTIFY_COLORS[opts.Type] or Theme.Text
        activityBody.Text = tostring(opts.Content or "")
        activityBody.Visible = activityBody.Text ~= ""
        local icon = opts.Icon
        if icon == nil then
            icon = ({ Success = "circle-check", Warning = "triangle-alert", Error = "circle-x" })[opts.Type] or "bell"
        end
        applyIcon(activityIcon, icon)
        if not activityIcon:GetAttribute("CustomIcon") then
            activityIcon.ImageColor3 = color
        end
        activityChip.BackgroundColor3 = color
        activityLive = true
        activityToken += 1
        local token = activityToken
        task.defer(function()
            if activityToken == token and not hovered and not dragging then
                setMode("Activity")
                islandScale.Scale = 0.96
                tween(islandScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            end
        end)
        task.delay(math.clamp(tonumber(opts.Duration) or 3, 1.5, 5), function()
            if activityToken == token then
                activityLive = false
                if self.Minimized and not hovered then
                    settleMode()
                end
            end
        end)
    end

    -- The meter dances while anything runs and lies flat when nothing does.
    local running = 0
    self:_listen("Render", function()
        if island.Visible and running > 0 and mode == "Compact" then
            local now = os.clock()
            for index, bar in ipairs(bars) do
                local wave = 0.5 + 0.5 * math.sin(now * (6 + index * 1.4) + index * 1.9)
                bar.Size = UDim2.fromOffset(3, math.floor(4 + wave * 11 + 0.5))
            end
        end
    end)

    -- Split, like iOS with two Live Activities: when toggles are running and
    -- a status is pinned, the pill keeps the status (logo leading, value
    -- trailing) and the running meter buds off into its own little circle
    -- beside it. One activity alone stays in the single pill.
    local pinValue = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.new(1, -52, 0, 18),
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextXAlignment = Enum.TextXAlignment.Right,
        RichText = true,
        TextTransparency = 1,
        Parent = compact,
    })
    local bubble = create("TextButton", {
        Name = "IslandBubble",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(bubble, UDim.new(1, 0))
    local split = create("NumberValue", { Value = 0 })
    local splitOn = false
    local pinnedLead = nil
    local function setSplit(on)
        if on == splitOn then
            return
        end
        splitOn = on
        barsHolder.Parent = on and bubble or meter
        barsHolder.AnchorPoint = on and Vector2.new(0.5, 0.5) or Vector2.new(0, 0)
        barsHolder.Position = on and UDim2.fromScale(0.5, 0.5) or UDim2.new()
        meter.Visible = not on
        tween(pinValue, { TextTransparency = on and 0 or 1 }, 0.2, Enum.EasingStyle.Quad)
        -- Buds off with a spring, and is drawn back in quicker.
        tween(split, { Value = on and 1 or 0 }, on and 0.55 or 0.3, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
        if on then
            islandScale.Scale = 0.96
            tween(islandScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
        end
    end
    self:_listen("Render", function()
        local t = split.Value * merge.Value
        local shown = island.Visible and t > 0.02 and island.GroupTransparency < 0.5
        bubble.Visible = shown
        if not shown then
            return
        end
        local origin = gui.AbsolutePosition
        local pos, size = island.AbsolutePosition - origin, island.AbsoluteSize
        local d = math.min(size.Y, Mini.Height)
        local gap = 6
        -- Buds off the side with room to spare: the right, or the left near
        -- the right edge of the screen.
        local right = pos.X + size.X + gap + d <= gui.AbsoluteSize.X
        local edge = right and pos.X + size.X or pos.X
        local dir = right and 1 or -1
        local inner = edge - dir * d * 0.6
        local outer = edge + dir * (gap + d / 2)
        local x = inner + (outer - inner) * t
        local scale = math.clamp(0.35 + 0.65 * t, 0, 1.2)
        -- Liquid: mid-flight the drop stretches along its path and thins,
        -- then rounds back into a circle as it settles.
        local stretch = math.sin(math.clamp(t, 0, 1) * math.pi)
        bubble.Position = UDim2.fromOffset(x, pos.Y + d / 2)
        bubble.Size = UDim2.fromOffset(d * scale * (1 + 0.4 * stretch), d * scale * (1 - 0.18 * stretch))
        bubble.BackgroundTransparency = island.GroupTransparency
    end)
    bubble.MouseButton1Click:Connect(function()
        if self.Minimized then
            self:Restore()
        end
    end)

    local cardRows = {}
    function self:_refreshMini()
        local count = 0
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true then
                count += 1
            end
        end
        if count ~= running then
            local rising = count > running
            running = count
            countLabel.Text = tostring(count)
            for _, bar in ipairs(bars) do
                tween(bar, { BackgroundColor3 = count > 0 and Theme.Accent or Theme.Muted }, 0.25)
                if count == 0 then
                    tween(bar, { Size = UDim2.fromOffset(3, 3) }, 0.25)
                end
            end
            -- A small bump, like a live activity updating.
            if rising and mode == "Compact" and island.Visible then
                islandScale.Scale = 1.06
                tween(islandScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            end
        end
        bigCount.Text = tostring(count)
        local names = {}
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true and element._searchName ~= "" then
                table.insert(names, element._searchName)
            end
        end
        table.sort(names)
        local shownNames = {}
        for index = 1, math.min(#names, 3) do
            shownNames[index] = Library._rich(names[index])
        end
        local extra = #names - #shownNames
        runningNames.Text = '<font color="#8A8A93">Running </font>' .. table.concat(shownNames, '<font color="#8A8A93"> · </font>')
            .. (extra > 0 and string.format('<font color="#8A8A93">  +%d</font>', extra) or "")
        runningNames.Visible = #names > 0
        pinnedLead = nil
        for _, handle in ipairs(self._pinned) do
            if not handle._isShown or handle:_isShown() then
                pinnedLead = handle
                break
            end
        end
        if pinnedLead then
            local text = tostring(pinnedLead:Text() or "")
            -- A status with nothing to show yet doesn't take the pill.
            if text:gsub("<[^>]*>", ""):match("%S") then
                pinValue.Text = text
                local color = pinnedLead._shownColor and pinnedLead._shownColor() or Theme.Text
                -- Too dark to read on the black pill: fall back to text colour.
                local _, _, value = color:ToHSV()
                pinValue.TextColor3 = value < 0.35 and Theme.Text or color
            else
                pinnedLead = nil
            end
        end
        setSplit(running > 0 and pinnedLead ~= nil)
        -- The pill's own meter: the clock when idle or when the bars budded
        -- off without a status to keep, the bars and count otherwise.
        local barsHere = running > 0 and not splitOn
        idleDot.Visible = not barsHere
        idleLabel.Visible = not barsHere
        countLabel.Visible = barsHere
        barsHolder.Visible = running > 0
        meter.Visible = not splitOn
        miniTitle.Visible = not splitOn
        local key = typeof(self.Keybind) == "EnumItem" and keyName(self.Keybind)
        hint.Text = TOUCH and "Tap to open" or (key and ("Click or press " .. key .. " to open") or "Click to open")

        local list = {}
        for _, handle in ipairs(self._pinned) do
            if (not handle._isShown or handle:_isShown()) and #list < Mini.Pinned then
                table.insert(list, handle)
            end
        end
        rowsHolder.Visible = false
        for index = 1, math.max(#list, #cardRows) do
            local handle = list[index]
            local row = cardRows[index]
            if handle then
                if not row then
                    local frame = create("Frame", {
                        Size = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        LayoutOrder = index,
                        Parent = rowsHolder,
                    })
                    row = {
                        Frame = frame,
                        Key = label({
                            Size = UDim2.new(0.5, -4, 1, 0),
                            TextSize = 12,
                            FontFace = Fonts.Regular,
                            TextColor3 = Theme.Muted,
                            RichText = true,
                            Parent = frame,
                        }),
                        Value = label({
                            AnchorPoint = Vector2.new(1, 0),
                            Position = UDim2.fromScale(1, 0),
                            Size = UDim2.new(0.5, -4, 1, 0),
                            TextSize = 12,
                            TextXAlignment = Enum.TextXAlignment.Right,
                            RichText = true,
                            Parent = frame,
                        }),
                    }
                    cardRows[index] = row
                end
                row.Frame.Visible = true
                row.Key.Text = Library._rich(handle.Name)
                row.Value.Text = handle:Text()
                -- Carries the status's own colour: its Color, or its tone
                -- for the tinted styles (badge, dot, bar).
                local color = handle._shownColor and handle._shownColor() or Theme.Text
                if row.Value.TextColor3 ~= color then
                    tween(row.Value, { TextColor3 = color }, 0.2)
                end
            elseif row then
                row.Frame.Visible = false
            end
        end
        -- Rows coming and going change the expanded height.
        if mode == "Expanded" and (hovered or self.IslandStyle == "Always Show") then
            task.defer(function()
                if mode == "Expanded" and (hovered or self.IslandStyle == "Always Show") and self.Minimized then
                    local size = shapeFor("Expanded")
                    if math.abs(size.Y - island.Size.Y.Offset) > 1 then
                        setMode("Expanded")
                    end
                end
            end)
        end
    end

    self.MiniBar = island
    self.Island = island
    return island
end

function Window:Minimize()
    if self.Minimized or not self._introDone or not self.Open or self._destroyed then
        return
    end
    self.Minimized = true
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    self:_closePopups()
    self:_refreshToggleButton()
    self:_refreshBackdrop()
    local bar = self:_buildMiniBar()
    self:_refreshMini()
    local gui = self.Gui

    -- Starts from whatever is on screen: the window, or a ghost still
    -- mid-flight if a restore was interrupted.
    local fromPosition = self.Root.AbsolutePosition - gui.AbsolutePosition
    local fromSize = self.Root.AbsoluteSize
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    end

    -- 1. The ghost fades in over the window while it eases back a touch.
    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, Library._radius(10))
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Scale, { Scale = (self._fitScale or 1) * 0.985 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
    bar.Visible = true
    bar.GroupTransparency = 1

    task.delay(0.11, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        -- 2. Covered by the ghost, the window is hidden and the ghost folds
        -- down into the island.
        self.Root.Visible = false
        self.Scale.Scale = self._fitScale or 1
        local target, size = self:_miniLand(fromPosition + fromSize / 2)
        morphGhost(ghost, ghostCorner, target, size, math.floor(size.Y / 2), 0.36)
        task.delay(0.3, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            -- 3. The island fades in on top as the ghost lands.
            self._miniScale.Scale = 0.9
            tween(self._miniScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(bar, { GroupTransparency = 0 }, 0.18, Enum.EasingStyle.Quad)
            dissolve(self, ghost, ghostStroke, 0.2)
            -- Always Show: once landed as the pill, swell open into the card.
            if self.IslandStyle == "Always Show" then
                task.delay(0.22, function()
                    if self._minimizeGeneration == generation and self._islandSettle then
                        self._islandSettle()
                    end
                end)
            end
        end)
    end)

    task.spawn(function()
        while self.Minimized and self._minimizeGeneration == generation and not self._destroyed do
            self:_refreshMini()
            task.wait(0.5)
        end
    end)
end

function Window:Restore()
    if not self.Minimized or self._destroyed then
        return
    end
    self.Minimized = false
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    self:_refreshToggleButton()
    self:_refreshBackdrop(true)
    local gui = self.Gui
    local bar = self.MiniBar
    local fit = self._fitScale or 1
    local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset) * fit
    local centre = self.Root.AbsolutePosition + self.Root.AbsoluteSize / 2 - gui.AbsolutePosition
    local target = centre - size / 2

    -- Picks up from whatever is on screen: a ghost still mid-flight if
    -- minimize was interrupted, otherwise the island.
    local fromPosition, fromSize = target, size
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    elseif bar and bar.Visible then
        fromPosition = self._miniOrb.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._miniOrb.AbsoluteSize
    end
    if bar and bar.Visible then
        if self._miniUnhover then
            self._miniUnhover()
        end
        tween(bar, { GroupTransparency = 1 }, 0.12, Enum.EasingStyle.Quad)
        task.delay(0.12, function()
            if self._minimizeGeneration == generation then
                bar.Visible = false
            end
        end)
    end

    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, math.floor(math.min(fromSize.X, fromSize.Y) / 2))
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    morphGhost(ghost, ghostCorner, target, size, Library._radius(10), 0.4)
    tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.45)

    -- Shown under the ghost a little early so its first frames are drawn
    -- while still covered, then the ghost clears to reveal it.
    task.delay(0.3, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        self.Scale.Scale = fit
        self.BodyStroke.Transparency = 0
        self.Root.Visible = true
    end)
    task.delay(0.4, function()
        if self._ghost == ghost and self._minimizeGeneration == generation then
            dissolve(self, ghost, ghostStroke, 0.22)
        end
    end)
end

-- The minimized island can be dragged anywhere; its spot is remembered in
-- the config folder. These lock it in place or send it back to the top.
function Window:SetIslandDraggable(enabled)
    self._islandLocked = enabled == false
end

function Window:ResetIslandPosition()
    self._islandAnchor = nil
    if self._islandReset then
        self._islandReset()
    end
    self:_writeConfigSettings({ IslandPosition = false })
end

function Window:SetMinimized(minimized)
    if minimized then
        self:Minimize()
    else
        self:Restore()
    end
end

function Window:Toggle(open)
    if not self._introDone then
        return
    end
    if self.Minimized then
        if open ~= false then
            self:Restore()
        end
        return
    end
    if open == nil then
        open = not self.Open
    end
    if open == self.Open then
        return
    end
    self.Open = open
    self:_refreshToggleButton()
    self:_refreshBackdrop(open)
    -- Like minimize, a plain ghost panel carries the scale and fade. The body
    -- is never reparented into the fader or rescaled, which relaid out the
    -- whole window and stuttered on the keypress frame.
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    local gui = self.Gui
    local fit = self._fitScale or 1
    local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset) * fit
    local centre = self.Root.AbsolutePosition + self.Root.AbsoluteSize / 2 - gui.AbsolutePosition
    local shrunk = size * 0.94
    local fromPosition, fromSize, fromAlpha
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    end
    if open then
        local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition or centre - shrunk / 2, fromSize or shrunk, Library._radius(10))
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        morphGhost(ghost, ghostCorner, centre - size / 2, size, Library._radius(10), 0.3)
        tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.3)
        -- Shown under the ghost once it covers the spot, then revealed.
        task.delay(0.2, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            self.Scale.Scale = fit
            self.BodyStroke.Transparency = 0
            self.Root.Visible = true
        end)
        task.delay(0.3, function()
            if self._ghost == ghost and self._minimizeGeneration == generation then
                dissolve(self, ghost, ghostStroke, 0.18)
            end
        end)
    else
        self:_closePopups()
        local position = fromPosition or self.Root.AbsolutePosition - gui.AbsolutePosition
        local current = fromSize or self.Root.AbsoluteSize
        local ghost, ghostStroke, ghostCorner = makeGhost(self, position, current, Library._radius(10))
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.08, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.08, Enum.EasingStyle.Quad)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.16)
        task.delay(0.08, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            self.Root.Visible = false
            morphGhost(ghost, ghostCorner, centre - shrunk / 2, shrunk, Library._radius(10), 0.2)
            dissolve(self, ghost, ghostStroke, 0.16)
        end)
    end
end

function Window:SetKeepOnScreen(enabled)
    self.KeepOnScreen = enabled ~= false
    if self.KeepOnScreen then
        self:_clampToScreen()
    end
end

function Window:SetKeybind(keyCode)
    self.Keybind = keyCode
    if self._keyChipLabel then
        self._keyChipLabel.Text = keyName(keyCode)
    end
end

function Window:Notify(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content", Image = "Icon" })
    if self.Minimized and self._islandActivity then
        self._islandActivity(opts)
    end
    local duration = opts.Duration or 4
    local titleColor = NOTIFY_COLORS[opts.Type] or Theme.Text

    self._notifyOrder = self._notifyOrder + 1
    local outer = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = self._notifyOrder,
        Parent = self.NotifyHolder,
    })
    local slide = create("Frame", {
        Position = UDim2.fromOffset(320, 0),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = outer,
    })
    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-20, -20),
        Size = UDim2.new(1, 40, 1, 40),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = slide,
    })
    local toast = create("CanvasGroup", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Parent = slide,
    })
    corner(toast, UDim.new(0, 10))
    local toastStroke = stroke(toast, Theme.Stroke)
    edgeHighlight(toast)
    glow(toast, UDim2.fromOffset(260, 120), UDim2.new(1, -10, 0, -10), 0.86, 90)

    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = toast,
    })
    padding(inner, 16, 16, 14, 24)

    local titleOffset = 0
    if opts.Icon then
        glowIcon(inner, opts.Icon, titleColor == Theme.Text and Theme.Accent or titleColor, UDim2.new(0, 0, 0, 8))
        titleOffset = 24
    end
    label({
        Position = UDim2.fromOffset(titleOffset, 0),
        Size = UDim2.new(1, -28 - titleOffset, 0, 16),
        Text = opts.Title or "Notification",
        TextSize = 14,
        TextColor3 = titleColor,
        Parent = inner,
    })
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 6, 0, -5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 22,
        FontFace = Fonts.Bold,
        AutoButtonColor = false,
        Parent = inner,
    })
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Text }, 0.15)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Muted }, 0.2)
    end)
    if opts.Content then
        label({
            Position = UDim2.fromOffset(titleOffset, 21),
            Size = UDim2.new(1, -titleOffset, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = inner,
        })
    end

    local track = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, -8),
        Size = UDim2.new(1, -32, 0, 3),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = toast,
    })
    corner(track, UDim.new(1, 0))
    local progress = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(progress, UDim.new(1, 0))

    task.defer(function()
        if outer.Parent then
            tween(outer, { Size = UDim2.new(1, 0, 0, toast.AbsoluteSize.Y) }, 0.3, Enum.EasingStyle.Quint)
        end
    end)
    tween(slide, { Position = UDim2.fromOffset(0, 0) }, 0.5, Enum.EasingStyle.Back)
    tween(toast, { GroupTransparency = 0 }, 0.3)
    tween(shadow, { ImageTransparency = 0.6 }, 0.4)
    tween(progress, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)

    local dismissed = false
    local function dismiss()
        if dismissed then
            return
        end
        dismissed = true
        for index, entry in ipairs(self._toasts) do
            if entry == dismiss then
                table.remove(self._toasts, index)
                break
            end
        end
        tween(slide, { Position = UDim2.fromOffset(320, 0) }, 0.3, Enum.EasingStyle.Quint)
        tween(toast, { GroupTransparency = 1 }, 0.2)
        tween(toastStroke, { Transparency = 1 }, 0.15)
        tween(shadow, { ImageTransparency = 1 }, 0.2)
        task.delay(0.22, function()
            outer.ClipsDescendants = true
            tween(outer, { Size = UDim2.new(1, 0, 0, -4) }, 0.22, Enum.EasingStyle.Quint)
            task.delay(0.24, function()
                outer:Destroy()
            end)
        end)
    end

    task.delay(duration, dismiss)
    closeButton.MouseButton1Click:Connect(dismiss)

    table.insert(self._toasts, dismiss)
    while #self._toasts > self.MaxNotifications do
        local oldest = table.remove(self._toasts, 1)
        oldest()
    end

    return { Dismiss = dismiss }
end

function Window:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    for index, entry in ipairs(Library.Windows) do
        if entry == self then
            table.remove(Library.Windows, index)
            break
        end
    end
    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self._connections = {}
    self._inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} }
    self._frameSteps = {}
    if self._pendingFlags then
        self._pendingFlags = {}
    end
    -- Switch this window's toggles off so their feature loops stop with it,
    -- instead of running on beside a re-executed copy.
    for _, element in pairs(Library.Flags) do
        if element._window == self and element._type == "Toggle" and element.Value == true then
            task.spawn(pcall, element.Set, element, false)
        end
    end
    local registry = Library._registry()
    if registry and registry[self._registryKey] == self then
        registry[self._registryKey] = nil
    end

    local gui = self.Gui
    local removed = false
    local function remove()
        if removed then
            return
        end
        removed = true
        if not pcall(gui.Destroy, gui) then
            pcall(function()
                gui.Enabled = false
            end)
        end
    end
    -- The fade out is decoration only. Input is already cut at this point, so
    -- if any of it fails the gui is removed straight away instead of being
    -- left frozen on screen.
    local ok, err = pcall(function()
        if self._dialog then
            self._dialog.Close()
        end
        self:_closePopups()
        local fit = self._fitScale or 1
        tween(self.Scale, { Scale = fit * 0.92 }, 0.22, Enum.EasingStyle.Quint)
        self:_fade(1, 0.2)
        tween(self.BodyStroke, { Transparency = 1 }, 0.12)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
        if self.MiniBar and self.MiniBar.Visible then
            tween(self.MiniBar, { GroupTransparency = 1 }, 0.18)
        end
        if self._backdrop then
            -- Frame steps are already cut, so the weather stops where it is.
            self._weatherField.Visible = false
            tween(self._backdropTintFrame, { BackgroundTransparency = 1 }, 0.2)
            tween(self._backdropHeat, { BackgroundTransparency = 1 }, 0.2)
        end
        for _, button in ipairs({ self.ToggleButton, self.OpenButton }) do
            if typeof(button) == "Instance" and button:IsA("GuiObject") then
                tween(button, { Size = UDim2.fromOffset(0, 0) }, 0.2, Enum.EasingStyle.Quint)
            end
        end
    end)
    if not ok then
        warn("[AirFlow] unload animation failed, removing the window directly: " .. tostring(err))
        remove()
        return
    end
    task.delay(0.24, remove)
end

Window.Unload = Window.Destroy

-- Unloads every window the library created.
function Library:Destroy()
    for index = #Library.Windows, 1, -1 do
        local window = Library.Windows[index]
        if window then
            window:Destroy()
        end
    end
end

Library.Unload = Library.Destroy

-- A script thread that yielded inside an engine call (InvokeServer and the
-- like) resumes at game identity and can no longer touch the GUI in CoreGui.
-- Every public call checks for that: it raises the thread back to the identity
-- the library loaded at, or, when the executor cannot, runs the call on a
-- trusted Heartbeat thread and waits for its result.
local getIdentity = getthreadidentity or getidentity or get_thread_identity or (syn and syn.get_thread_identity)
local setIdentity = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
local loadIdentity = nil
if getIdentity then
    local ok, identity = pcall(getIdentity)
    if ok and type(identity) == "number" then
        loadIdentity = identity
    end
end

local function threadLowered()
    local window = Library.Windows[#Library.Windows]
    local probe = window and window.Gui
    if typeof(probe) ~= "Instance" then
        return false
    end
    return not pcall(function()
        return probe.Name
    end)
end

local trustedQueue = {}
RunService.Heartbeat:Connect(function()
    if #trustedQueue == 0 then
        return
    end
    local queue = trustedQueue
    trustedQueue = {}
    for _, job in ipairs(queue) do
        job()
    end
end)

local function runTrusted(fn, ...)
    local args = table.pack(...)
    local result = nil
    table.insert(trustedQueue, function()
        result = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    end)
    while result == nil do
        task.wait()
    end
    if not result[1] then
        error(result[2], 0)
    end
    return table.unpack(result, 2, result.n)
end

local guardedObjects = setmetatable({}, { __mode = "k" })
local guardObject

local function guarded(fn)
    return function(...)
        if threadLowered() then
            if setIdentity then
                pcall(setIdentity, loadIdentity or 8)
            end
            if threadLowered() then
                return guardObject(runTrusted(fn, ...))
            end
        end
        return guardObject(fn(...))
    end
end

-- Elements carry their methods as closures, so each returned object gets its
-- public functions wrapped too; windows and tabs share the guarded metatables.
function guardObject(...)
    for index = 1, select("#", ...) do
        local object = select(index, ...)
        if type(object) == "table" and not guardedObjects[object] then
            local meta = getmetatable(object)
            if meta ~= Window and meta ~= Tab then
                guardedObjects[object] = true
                for key, value in pairs(object) do
                    if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
                        object[key] = guarded(value)
                    elseif type(key) == "number" and type(value) == "table" then
                        guardObject(value)
                    end
                end
            end
        end
    end
    return ...
end

for _, class in ipairs({ Library, Window, Tab }) do
    for key, value in pairs(class) do
        if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
            class[key] = guarded(value)
        end
    end
end

return Library
end)()

--[[
    Example script

    A reference build that shows every part of the library in a realistic
    layout. Each section is self-contained: copy the parts you need.

    Structure
      Window      the main frame, Home tab and global options
      Main        a typical feature tab: sub tabs, groupboxes and controls
      Status      live readouts: statuses, status lists and dependent controls
      Elements    one of every element as a full-width card
      Popups      notifications, confirms and dialogs
      Settings    interface options, config manager and theme manager
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

Library:LoadFont({ Name = "ValleySans" }) -- downloaded once and used everywhere
-- Library:SetDefaultTheme("Nebula") -- any preset name or a colour table; a theme the player picks wins

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local Window = Library:CreateWindow({
    Name = "Example",
    LoadingSubtitle = "Loading",
    ToggleUIKeybind = "RightControl", -- a KeyCode name or Enum.KeyCode
    ConfigurationSaving = { Enabled = true, FolderName = "Example" },
    ToggleButton = { Platform = "Mobile", Icon = "layout-grid" }, -- "Both" also shows it on PC
    Backdrop = { Weather = "None", Tint = 0.45 }, -- "Snow", "Rain", "Hell Fire", "Sakura", "Fireflies", "Matrix" or "None"
    -- UIScale = 1,           -- 0.6 to 1.5, on top of the automatic fit
    -- Density = "Default",   -- "Compact", "Default" or "Comfortable"
    -- SidebarWidth = 188,    -- starting sidebar width; players can drag the divider
    -- Disclaimer = { Title = "Terms", Text = "By continuing you accept the terms.", Id = "terms-v1" },
    Home = {
        Tier = "Free",
        Expiry = os.time() + 30 * 86400, -- a timestamp, a string, or a function returning either
        Discord = "discord.gg/example",
        Website = "example.com",
        Stats = { "Players", "Execs", "Session", "FPS", "Ping" },
        -- Features = { List = { { Name = "Main", Items = { "Automation", { Name = "Targeting", Tag = "New" } } } } },
    },
})

--------------------------------------------------------------------------------
-- Main: tabs hold sub tabs, sub tabs hold groupboxes, groupboxes hold elements
--------------------------------------------------------------------------------

local Main = Window:CreateTab({ Name = "Main", Icon = "zap" })

local General = Main:CreateSubTab({ Name = "General" })

local Automation = General:AddLeftGroupbox({ Name = "Automation", Icon = "repeat" })

Automation:CreateToggle({
    Name = "Enabled",
    Desc = "Runs the selected tasks on a loop",
    CurrentValue = false,
    Flag = "AutomationEnabled",
    Callback = function(Value)
        print("[Example] automation", Value)
    end,
})

Automation:CreateDropdown({
    Name = "Tasks",
    Options = { "Collect", "Upgrade", "Sell", "Claim Rewards" },
    MultipleOptions = true,
    CurrentOption = { "Collect" },
    Flag = "AutomationTasks",
    Callback = function(Options)
        print("[Example] tasks", table.concat(Options, ", "))
    end,
})

Automation:CreateSlider({
    Name = "Interval",
    Range = { 1, 60 },
    Increment = 1,
    Suffix = "s",
    CurrentValue = 5,
    Flag = "AutomationInterval",
    Callback = function(Value)
        print("[Example] interval", Value)
    end,
})

local Targeting = General:AddRightGroupbox({ Name = "Targeting", Icon = "crosshair" })

Targeting:CreateDropdown({
    Name = "Mode",
    Options = { "Nearest", "Lowest Health", "Highest Value" },
    CurrentOption = "Nearest",
    Flag = "TargetMode",
    Callback = function(Option)
        print("[Example] target mode", Option)
    end,
})

Targeting:CreateSlider({
    Name = "Range",
    Range = { 0, 500 },
    Increment = 10,
    Suffix = " studs",
    CurrentValue = 150,
    Flag = "TargetRange",
    Callback = function(Value)
        print("[Example] range", Value)
    end,
})

Targeting:CreateToggle({
    Name = "Ignore Friends",
    CurrentValue = true,
    Flag = "IgnoreFriends",
    Callback = function(Value)
        print("[Example] ignore friends", Value)
    end,
})

local Controls = General:AddRightGroupbox({ Name = "Controls", Icon = "sliders-horizontal", Collapsed = true })

Controls:CreateStepper({
    Name = "Speed",
    Range = { 1, 10 },
    Increment = 1,
    CurrentValue = 5,
    Flag = "Speed",
    Callback = function(Value)
        print("[Example] speed", Value)
    end,
})

Controls:CreateKeybind({
    Name = "Stop",
    CurrentKeybind = "X",
    Flag = "StopKey",
    Callback = function()
        print("[Example] stop")
    end,
})

local Advanced = Main:CreateSubTab({ Name = "Advanced" })

local Profiles = Advanced:AddLeftGroupbox({ Name = "Profile", Icon = "user-cog" })

Profiles:CreateInput({
    Name = "Webhook URL",
    PlaceholderText = "https://",
    Flag = "WebhookUrl",
    Callback = function(Text)
        print("[Example] webhook", Text)
    end,
})

Profiles:CreateColorPicker({
    Name = "Highlight Color",
    Color = Color3.fromRGB(128, 160, 246),
    Flag = "HighlightColor",
    Callback = function(Color)
        print("[Example] color", Color)
    end,
})

Profiles:CreateButton({
    Name = "Apply",
    Style = "Primary",
    Callback = function()
        print("[Example] applied")
    end,
})

-- Order lists are always open: drag a row (by its grip on touch) or use the arrows.
local Priority = Advanced:AddRightGroupbox({ Name = "Priority", Icon = "list-ordered" })

Priority:CreateOrderList({
    Name = "Task Order",
    Desc = "The top task runs first",
    Items = { "Collect", "Upgrade", "Sell", "Claim Rewards" },
    Flag = "TaskOrder",
    Callback = function(Order)
        print("[Example] order", table.concat(Order, " > "))
    end,
})

local Steps = {}
for Index = 1, 12 do
    Steps[Index] = "Step " .. Index
end
Priority:CreateOrderList({
    Name = "Steps",
    Items = Steps,
    MaxRows = 5, -- more rows than MaxRows scroll inside the list
    Flag = "StepOrder",
})

-- Tabboxes: a groupbox with tabs in its header; each tab holds its own rows
local Filters = Advanced:AddLeftTabbox({ Name = "Filters" })
local Include = Filters:AddTab({ Name = "Include", Icon = "plus" })
Include:CreateToggle({ Name = "Rare Items", CurrentValue = true, Flag = "IncludeRare" })
Include:CreateToggle({ Name = "Event Items", CurrentValue = false, Flag = "IncludeEvent" })
local Exclude = Filters:AddTab({ Name = "Exclude", Icon = "minus" })
Exclude:CreateToggle({ Name = "Common Items", CurrentValue = false, Flag = "ExcludeCommon" })
Exclude:CreateSlider({ Name = "Below Value", Range = { 0, 1000 }, Increment = 10, CurrentValue = 100, Flag = "ExcludeBelow" })

Main:CreateSubTab({ Name = "Queue" }) -- an empty sub tab shows the empty state

--------------------------------------------------------------------------------
-- Status: live readouts. Pin = true also shows a value on the minimized island
--------------------------------------------------------------------------------

local Status = Window:CreateTab({ Name = "Status", Icon = "activity" })

local Session = Status:AddLeftGroupbox({ Name = "Session", Icon = "timer" })
local Cycles = 0
Session:CreateStatuses({
    { Name = "Cycles", Pin = true, Update = function()
        Cycles += 1
        return Cycles
    end },
    { Name = "Collected", Value = 0 },
    { Name = "Errors", Value = 0 },
    { Name = "Region", Value = "-" },
}, { Style = "Plain" })

local Progress = Status:AddRightGroupbox({ Name = "Progress", Icon = "trending-up" })
Progress:CreateStatus({ Name = "Level", Value = 42, Style = "Stat" })
Progress:CreateStatus({ Name = "Experience", Value = "6200/10000", Style = "Bar" })
Progress:CreateStatus({ Name = "Balance", Value = 125000, Style = "Row", Pin = true })

local Health = Status:AddLeftGroupbox({ Name = "Health", Icon = "heart-pulse" })
local States = { { "Running", "Success" }, { "Waiting", "Warning" }, { "Stopped", "Error" } }
Health:CreateStatus({ Name = "State", Style = "Dot", Update = function()
    local State = States[math.floor(os.clock() / 3) % #States + 1]
    return State[1], State[2] -- a second string return sets the tone
end })
Health:CreateStatus({ Name = "Service", Value = "Online", Style = "Badge", Tone = "Success" })
Health:CreateStatus({ Name = "Load", Style = "Bar", Tone = "Warning", UpdateRate = 0.5, Update = function()
    return (os.clock() * 100) % 100, 100 -- a number second return sets the max
end })
-- Coloured text: theme tags follow the theme, Colorize wraps any colour.
Health:CreateStatus({ Name = "Ping", Style = "Row", Pin = true, Update = function()
    local Ms = math.floor(LocalPlayer:GetNetworkPing() * 1000)
    local Tone = Ms < 90 and "Success" or Ms < 180 and "Warning" or "Error"
    return Library.Colorize(Ms .. " ms", Tone)
end })
Health:CreateStatus({ Name = "Summary", Style = "Row", Value = "<Accent>3</Accent> active · <Muted>9 idle</Muted>" })

-- Status lists grow with their rows up to MaxRows, then scroll inside.
local Jobs = Status:AddRightGroupbox({ Name = "Jobs", Icon = "list-checks" })
Jobs:CreateStatusList({
    Name = "Queue",
    MaxRows = 5,
    EmptyText = "Nothing queued",
    UpdateRate = 0.5,
    Update = function()
        local Rows = {}
        for Index = 1, 8 do
            local Remaining = math.floor((os.clock() + Index * 3) % 15)
            Rows[Index] = {
                Text = "Job " .. Index,
                Value = Remaining == 0 and "done" or (Remaining .. "s left"),
                Tone = Remaining == 0 and "Success" or nil,
            }
        end
        return Rows
    end,
})

-- Dependent controls: the slider only shows while the toggle is on.
local Limit -- declared first so the toggle's callback can reach it
Jobs:CreateToggle({
    Name = "Limit Jobs",
    CurrentValue = false,
    Flag = "LimitJobs",
    Callback = function(Value)
        Limit:SetVisible(Value)
    end,
})
Limit = Jobs:CreateSlider({
    Name = "Max Jobs",
    Range = { 1, 20 },
    Increment = 1,
    CurrentValue = 5,
    Visible = false, -- hidden at start, still saved with the config
    Flag = "MaxJobs",
})

--------------------------------------------------------------------------------
-- Elements: added straight to a tab, every element is a full-width card
--------------------------------------------------------------------------------

local Elements = Window:CreateTab({ Name = "Elements", Desc = "Every element, full width", Icon = "layout-grid" })

Elements:CreateSection("Controls")

Elements:CreateButton({
    Name = "Button",
    Desc = "With a description and a tooltip",
    Icon = "mouse-pointer-click",
    Tooltip = "Any element accepts a Tooltip", -- a string, or { Title, Text, Icon }
    Callback = function()
        print("[Example] button")
    end,
})

Elements:CreateToggle({
    Name = "Toggle",
    Desc = "Tooltips can carry a title and an icon",
    Tooltip = { Title = "Toggle", Text = "Saved with the config through its Flag.", Icon = "info" },
    CurrentValue = false,
    Flag = "ElementToggle",
})

Elements:CreateSlider({
    Name = "Slider",
    Range = { 0, 100 },
    Increment = 1,
    Suffix = "%",
    CurrentValue = 50,
    Flag = "ElementSlider",
})

Elements:CreateProgress({ Name = "Progress", CurrentValue = 0.65 })

Elements:CreateParagraph({
    Title = "Paragraph",
    Content = "Longer text wraps across as many lines as it needs.",
})

Elements:CreateSection("Media and tables")

Elements:CreateImage({
    Name = "Image",
    Image = "Deep Violet", -- an asset id, rbxassetid:// or rbxthumb:// link, a web link, a background preset or "Avatar"
    Height = 140,
    Caption = "Images fade in once loaded",
})

Elements:CreateViewport({
    Name = "Viewport",
    Desc = "Drag to rotate",
    Model = "Avatar", -- any Model or part (copied), a Player, or "Avatar"
    Height = 200,
    SpinSpeed = 25,
})

do
    local Board = Elements:CreateTable({
        Name = "Leaderboard",
        Rank = true, -- a # column with medals for the top three
        Columns = {
            "Player",
            { Name = "Score", Align = "Right", Width = 0.2 },
            { Name = "Balance", Align = "Right", Width = 0.25, Format = function(Value) return "$" .. Value end },
        },
        Rows = {
            { "Player One", 42, 12500 },
            { "Player Two", 57, 9800 },
            { LocalPlayer.DisplayName, 31, 15200, Highlight = true },
            { "Player Four", 12, 300 },
            { "Player Five", 5, 150 },
        },
        SortBy = "Score", -- click a header to sort, again to flip, a third time to reset
        MaxRows = 6,
        Callback = function(Row, Index)
            print("[Example] row", Row[1], Index)
        end,
    })
    task.spawn(function()
        while task.wait(3) do
            local Row = Board.Rows[3]
            if not Row or not Window.Gui.Parent then
                break
            end
            Board:UpdateRow(3, { Row[1], Row[2] + math.random(0, 2), Row[3] + math.random(0, 400), Highlight = true })
        end
    end)
end

local Activity = Elements:CreateLog({
    Name = "Activity",
    MaxEntries = 50, -- the oldest lines drop off past this
    MaxRows = 5,
})

local Rules = Elements:CreateTable({
    Name = "Price Rules",
    Desc = "Typed columns make a table editable",
    Columns = {
        { Name = "Item", Type = "Text", Placeholder = "Item name" },
        { Name = "Sell", Type = "Number", Min = 0, Integer = true, Align = "Right", Width = 0.22 },
        { Name = "Buy", Type = "Toggle", Align = "Center", Width = 0.14 },
        { Name = "Mode", Type = "Dropdown", Options = { "Market", "Auction", "Trade" }, Searchable = true, Width = 0.24 },
    },
    Rows = {
        { Item = "Golden Egg", Sell = 500, Buy = false, Mode = "Market" },
    },
    Flag = "PriceRules", -- saved with the config like any other flag
    OnChanged = function(Rows)
        Activity:Push(("%d price rule(s)"):format(#Rows), "Muted")
    end,
})

Activity:Push("Bought <Accent>Golden Egg</Accent> for 480", "Success")
Activity:Push("Listed Silver Egg for 1,200")
Activity:Push("Trade declined", "Warning")

Elements:CreateDropdown({
    Name = "Price Mode",
    Options = { "Fixed", "Undercut" },
    CurrentOption = "Fixed",
    AllowNone = false,
    Flag = "PriceMode",
})

Elements:CreateSlider({
    Name = "Undercut %",
    Range = { 1, 50 },
    Increment = 1,
    Suffix = "%",
    CurrentValue = 5,
    Flag = "UndercutPercent",
    DependsOn = { Flag = "PriceMode", Value = "Undercut" }, -- only shown in Undercut mode
})

Elements:CreateToggle({ Name = "Auto Bid", CurrentValue = false, Flag = "AutoBid" })

Elements:CreateSlider({
    Name = "Max Bid",
    Range = { 100, 10000 },
    Increment = 100,
    CurrentValue = 1000,
    Flag = "MaxBid",
    DependsOn = "AutoBid",
    DependsMode = "Disable", -- dimmed instead of hidden while Auto Bid is off
})

Elements:CreateButton({
    Name = "Clear All Rules",
    Icon = "trash-2",
    Confirm = true, -- first click arms it, the second runs it
    Callback = function()
        Rules:SetRows({})
        Activity:Push("Cleared every price rule", "Warning")
    end,
})

Elements:CreateButton({
    Name = "Spend 1,000 Gold",
    Icon = "coins",
    HoldToConfirm = 1.5, -- seconds to hold
    Callback = function()
        Activity:Push("Spent 1,000 gold", "Accent")
    end,
})

--------------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------------

local Popups = Window:CreateTab({ Name = "Popups", Desc = "Notifications and dialogs", Icon = "bell" })

local Notifications = Popups:AddLeftGroupbox({ Name = "Notifications", Icon = "bell" })

for _, Kind in ipairs({ "Success", "Warning", "Error" }) do
    Notifications:CreateButton({
        Name = Kind,
        Callback = function()
            Library:Notify({
                Title = Kind,
                Content = "This is a " .. Kind:lower() .. " notification.",
                Type = Kind,
                Duration = 3,
            })
        end,
    })
end

local Dialogs = Popups:AddRightGroupbox({ Name = "Dialogs", Icon = "message-square" })

Dialogs:CreateButton({
    Name = "Confirm",
    Callback = function()
        Library:Confirm({
            Title = "Reset progress?",
            Content = "This cannot be undone.",
            ConfirmText = "Reset",
            CancelText = "Cancel",
            Callback = function()
                print("[Example] confirmed")
            end,
        })
    end,
})

Dialogs:CreateButton({
    Name = "Dialog",
    Callback = function()
        Library:Dialog({
            Title = "Choose a mode",
            Content = "You can change this later in Settings.",
            Buttons = {
                { Title = "Basic", Callback = function() print("[Example] basic") end },
                { Title = "Balanced", Callback = function() print("[Example] balanced") end },
                { Title = "Full", Variant = "Primary", Callback = function() print("[Example] full") end },
            },
        })
    end,
})

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local Settings = Window:CreateTab({ Name = "Settings", Icon = "settings" })

local Menu = Settings:AddLeftGroupbox({ Name = "Menu", Icon = "monitor" })

Menu:CreateKeybind({
    Name = "Toggle UI",
    CurrentKeybind = "RightControl",
    OnChanged = function(Key)
        Window:SetKeybind(Key)
    end,
})

Menu:CreateMinimizeOnStart()

Menu:CreateDropdown({
    Name = "Toggle Button",
    Options = { "Mobile only", "Mobile & PC" },
    CurrentOption = "Mobile only",
    AllowNone = false,
    Flag = "ToggleButtonPlatform",
    Callback = function(Option)
        Window:SetToggleButtonPlatform(Option == "Mobile & PC" and "Both" or "Mobile")
    end,
})

Menu:CreateToggle({
    Name = "Backdrop",
    CurrentValue = true,
    Flag = "Backdrop",
    Callback = function(Value)
        Window:SetBackdrop(Value)
    end,
})

Menu:CreateSlider({
    Name = "Backdrop Tint",
    Range = { 0, 90 },
    Increment = 5,
    Suffix = "%",
    CurrentValue = 45,
    Flag = "BackdropTint",
    Callback = function(Value)
        Window:SetBackdropTint(Value / 100)
    end,
})

Menu:CreateButton({
    Name = "Unload",
    Icon = "power",
    Callback = function()
        Library:Confirm({
            Title = "Unload Example?",
            ConfirmText = "Unload",
            Callback = function()
                Window:Destroy()
            end,
        })
    end,
})

Settings:CreateConfigManager({ Name = "Configs", Side = "Left" }) -- builds its own groupbox
Settings:CreateThemeManager({ Name = "Themes", Side = "Right" })

Window:LoadAutoload() -- loads the config marked as autoload, if any
