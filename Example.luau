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
    element._listeners = element._listeners or {}
    local window = tab and tab.Window
    local searchText = opts.Name or opts.Text or opts.Title
    element._searchKey = type(searchText) == "string" and string.lower(searchText) or ""
    if tab and tab._items then
        table.insert(tab._items, element)
    end
    if opts.Flag then
        Library.Flags[opts.Flag] = element
        if window then
            window:_flagCreated(opts.Flag, element)
        end
    end
    -- What the script asked for, kept apart from what search is currently hiding.
    element._userVisible = opts.Visible ~= false
    function element:IsVisible()
        return element._userVisible
    end
    function element:_isShown()
        return element._userVisible and not (tab and tab._userVisible == false)
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
            frame.Visible = visible and element._searchMatch ~= false
        end
        if window then
            window._controlsDirty = true
            if window._filtered and window.SearchBox then
                window:_applySearch(window.SearchBox.Text)
            end
        end
    end
    if frame and not element._userVisible then
        frame.Visible = false
    end
    function element:Destroy()
        if element._destroyed then
            return
        end
        element._destroyed = true
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
    Background = Color3.fromRGB(20, 16, 20),
    Surface = Color3.fromRGB(24, 19, 24),
    Surface2 = Color3.fromRGB(28, 22, 28),
    Surface3 = Color3.fromRGB(42, 36, 43),
    Stroke = Color3.fromRGB(40, 32, 41),
    StrokeHover = Color3.fromRGB(88, 70, 90),
    Accent = Color3.fromRGB(235, 199, 246),
    AccentDark = Color3.fromRGB(24, 18, 26),
    Text = Color3.fromRGB(233, 229, 234),
    Muted = Color3.fromRGB(125, 115, 126),
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
        Muted = rgb(table.unpack(muted)),
    }
end

Library.ThemePresets = {
    Airflow = preset({ 20, 16, 20 }, { 24, 19, 24 }, { 28, 22, 28 }, { 42, 36, 43 }, { 40, 32, 41 }, { 88, 70, 90 }, { 235, 199, 246 }, { 24, 18, 26 }, { 233, 229, 234 }, { 125, 115, 126 }),
    Midnight = preset({ 15, 18, 26 }, { 18, 22, 31 }, { 22, 26, 37 }, { 37, 44, 60 }, { 34, 40, 55 }, { 70, 84, 112 }, { 128, 160, 246 }, { 14, 18, 30 }, { 228, 232, 242 }, { 116, 126, 148 }),
    Ocean = preset({ 12, 20, 24 }, { 15, 24, 29 }, { 18, 29, 35 }, { 31, 48, 56 }, { 29, 44, 52 }, { 58, 92, 104 }, { 110, 214, 222 }, { 10, 24, 28 }, { 226, 238, 240 }, { 108, 134, 140 }),
    Rose = preset({ 22, 15, 18 }, { 27, 18, 22 }, { 32, 21, 26 }, { 48, 34, 40 }, { 45, 30, 37 }, { 98, 64, 78 }, { 246, 160, 186 }, { 30, 14, 20 }, { 240, 228, 232 }, { 138, 112, 120 }),
    Emerald = preset({ 13, 20, 17 }, { 16, 24, 20 }, { 20, 29, 24 }, { 33, 47, 40 }, { 30, 44, 37 }, { 62, 96, 78 }, { 132, 226, 170 }, { 12, 26, 18 }, { 228, 240, 233 }, { 110, 136, 122 }),
    Amber = preset({ 22, 18, 13 }, { 27, 22, 16 }, { 32, 26, 19 }, { 49, 41, 31 }, { 46, 38, 28 }, { 100, 82, 58 }, { 246, 196, 120 }, { 30, 22, 10 }, { 242, 236, 226 }, { 140, 126, 106 }),
    Mono = preset({ 16, 16, 17 }, { 20, 20, 21 }, { 25, 25, 26 }, { 40, 40, 42 }, { 38, 38, 40 }, { 84, 84, 88 }, { 236, 236, 240 }, { 20, 20, 22 }, { 234, 234, 236 }, { 122, 122, 128 }),
    -- Colours here must not be pure white, pure black or any other colour the
    -- library hard-codes, or those objects would get bound to the theme.
    Obsidian = preset({ 12, 11, 16 }, { 16, 15, 21 }, { 20, 18, 27 }, { 34, 31, 45 }, { 31, 28, 41 }, { 76, 66, 104 }, { 167, 139, 250 }, { 18, 12, 34 }, { 236, 233, 245 }, { 118, 112, 138 }),
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
}

Library.ThemeName = "Airflow"

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
local EMBEDDED_LOGO = "iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAACDfklEQVR42u29eXhdV3ku/q219nRmzYNtybLlIY4zxwmZSeDCpUCAQm3GlgZa4Eeh0IF720Jruy3QWy4tXChDuW2BtlBsegulFCiQhCGj4ySO7Xi2bNmWNRwNZ9zzWr8/stdmaXnvI9mWZMne63nOo+no6Oic/U3v937vB5Cc5CQnOclJTnKSk5zkJCc5yUlOcpKTnOQkJznJSU5yLs+DkpfgyjuMsdj3HSHEklcoOclZ4gbOGMOMMfLQQw8pjDHSyOhjHgM/9NBDSvD7+Hx/PzlJBpCchY3o/MYQQrTR/QcGBoy+vr4cAKQsyyKMMW9iYqI+NTVVueaaa5xGToH/jeDvJNlC4gCSc6mNHiHkSz9L2bbdU6lUrrIsqyudTucYY9f7vr/M8zyEEMqk0+k8xjgdZAeu67o1hFAZAGxN00xd1583TXMglUpNaZq2HwBOIoSmpL9DAIAmjiBxAMlZOMPHstEzxrRqtbqOEHKNaZp32bZ9k6Zpa3Vdb8tms+D7PjDGgBACCCHxsXjd3/BvWpZVNk1zUFXVnxuG8ePJycnnOjo6DkvPCWbKPJKTOIDkXHi0x2J6zxhLnz179mpd119KCPkly7JubGlpyRNCwPdf8A2UUoYx9gMDR8EBjPG0959SChhjOYoz3/cZACCMMRGdhGVZRULIzxlj3yyXyw+1t7cPJY4gOcmZHzCPSN9bWyqVfn94ePjnQ0NDTqVSYaZpslqtxizL8nzf9/wXDmWMUTY3hzLGfMaYF3wMj2mag7Ztf4Ixdg1/jjt27CAJaJhkAMm5yIjP03zGmOJ53osnJyffgBB6fVNTUydjDHzfB4wxRQgBIQRhjBfq/WTBDYLMBGzbLvq+/+V0Ov1FhNBRnhEk2UDiAJJznjW+kOY3TUxMvMx13XcihF7e0tKCPM8DxhhVFAVUVUWL4D3kzoA7gtO2bX8qn89/GSE0zjOBBChMHEByZm/42ZGRkdchhH47nU7fgjEGSikoiuKrqooxxmgm4O5SOwLP8570PO8PU6nUg0k2kDiA5MzQzuPGMTExcb/neR9WVfVFmqYBQohhjJmiKIgQgubob077XPxaYgWKgOH5OAIKAMT3/bplWR/LZDJ/gRDyEyeQOIDkxER927avGxsb+z2M8dsMw8CMMZrJZEDTNDwX0Z4xBpTS8KNo/LIDEP8eISRsH57n86A8G6hWq/9GCPmddDp9MnECiQNIDF+I+pOTk02O47wHY/w/DcNocl0XAICmUims6zpcjPH7vj/N6MXPGWOAEAqdgRz15b+rKAooijLNEcziuYVlged5+1zXfU86nX4kcQKJA0iiPgCMjo7e4/v+x3Vdv0NVVdA0jSKEMMYYCCEX9PgBSAiUUvA8DzzP45yA0Ni5A+BZADdk/nlUtA9Ax7AkQAiBoijnkIvifBEAEM/zhgHgN1RV/W4CDi6OoyQvwcKdHTt2kKAWTp85c+Z3TNP8n4VCIccYoyiwfEW5sLeEUgqu657jADgLUE7542p/2QGIzsH3fSCEhE7A8zwghIBhGDM5AQIAvqIoXbZtf91xnP+JEPp8Ag4mDuCKSfm3bduGtmzZ4heLxauPHDnyyebm5lcEhkoVRcFidL2Qut7zvGkOgBssvw9CaNr34wBAnv7z5yKWChjj0AlwxqHneYAQglmUK4RSSnVdz7mu+zeVSmVlNpvdhhCykpmCpAS47GfvEUJsaGjoDZZl/ZWqqr2KolBd15FhGIin1+cb8XmE59FYjvhi3R/lAOSOQFwGwO+DMQ4dA3cUAQkJDMMATdNmLF0CejIAAKpUKt/J5XIfQggdEoaLkknDJAO4PM7WrVvD9PbMmTPbfd//I1VVFYwxNQwD67oOhBCYbdovgng84vOvOeAnGrzv+9Mcgpg1RGUAUcYv4wEijsBxAP53bNsGXddB1/XYbCZgKzLf91kmk7m/XC7fNjk5+ZdNTU1/gxAyheepCCBi4hCSDGBpgn2MsfThw4c/pmnaBwKjoLlcDuu6HgJrs0H6xejOU37HcaYBetwBiGVBVBYgfi8yVw+cklwOyOUHf0x+f+4QUqkUGIbRMBsIMhEKANi2bajX649nMpl/TKfTP0EI7Y+6VoNho6RUSBzAkjH+zsHBwc+pqvp627aZqqqg6zrSdR2Cz2dl/Ly2F5F8ngGI9TyPxNy4+c8RQiE2gDGmQbnAxPSePw+e5iuKgjDGmNf7vDPBIz9/LtxBCL8HmqaFTmAmXINSyoLniBhjUK1WJ33ff5QQcsAwjD0AcBIATqTT6VPJ+HHiAJaM8Y+Pj/eMjY39E8b4HkVRaCqVQgGbL0yTZ6qXGWPgOA5YlhUatpjG89Qf4IWev+u6odHzn/m+T13XBYwxY4xhjDESBomA04xVVQ2zER7dg3qdBhwAhBDC3ODl8oE/FkIIDMMAXdchIDLNGtYIni/m2YfrulCv1x2M8Yiqqk9ijP9T07T/QgidThxB4gAWo/EThJA/MTHROzY29nVVVe+o1WpU0zTc1NQUpvw8A4iK/tw4ecrPoz83arkt5zhOWA54nge2bfPePwsiLOJR3LIswBiPOo5zslgsnvA8zzEMw1dV1cxkMkjX9ZTneSSTyXS5rrteUZTluVwOEEIQEJSYqqpIxgZE/gAAhP+jYRiQTqdnXeZIVGLm+z4JCFNhJkEpPYEx/gYA/IMIHsqqSMlJHMAlifynT5/uMU3znzRNu8eyLJ8QQlKpFOi6DvxjFNNOjPiO40yL4mJNL0RnME0TLMsC13XBtm0wTRNc1+WDQ+B5HiiKcqSpqWk/IeTxycnJp3O53J4777xzdKb/5/Dhw/lyuXxdNpu9zjTNOx3HuTWVSq1RFAUopWFZEMcMVBRlmhM4j0wgyiFwajEXRgEAGAWALwPAlxBCRxNiUeIAFkPN33vgwIF/xhjfRSn1FUUhhmFAKpUCTdPCVlkcyCcav9zL51GYp/iWZUGlUgHTNKFer0O1Wg1/lxBiNTc371UU5ccbNmx4PJPJnEylUrZhGJnJycmVpmku932/nTGW5iUApZSVSiVmWZadzWatdDo96nneacuyRl3XdXVdX2/b9mt1XX9NJpPJKorCFEVBYmkiH1VVQ+NPpVKzZQ3OZsaABeQioJSewRj/EULoqwmxKHEAl6TPjxBixWIxXywWv4YQepVt2z4hZJrx67oOmqad4wA4g89xHLBte1qdL4J8vu9DvV4Pjb1Wq4URPwD3gDEGHR0dsHLlykqhUDhuWRbxfb83lUpldF1HqVQK83Rcxh/E7AMhBNVqFSqVChSLRRgbG/NHR0ftarU6pet6q6Ioend3N2zcuBFUVQ3bknJJoChK6PS4A5zDMeZw6jB4HT+DMf4wQqjC35Pk6oSEB7AQDD/GGD506NCfMcZe5TgOZYwRMUUWkXSQhnXE2p0j9iK5h6f2tm2DZVmhgRYKBVi9ejXk8/nQwXDUHWOcUxTlevHv8Mf1PI8BAHMch3Fj5JiD1OdHhmGg1tZWhBAizc3Nadu20+Pj4zA2NgaHDx+GI0eOwLp16+Cqq64CwzDCToVYGvDH5szBC6U6xwQvwksDjPH7ASDDGPtthFAtcQJJBgALQfTZvn073bVr1/80DOMvKKWMg24cCTcMI7zxqAgAYTrPHQCP9mI2YFlWyK7TdR1aW1vDtDqOOSjw/FkE4QdFkXpk2jDHHLiDchyH1Wo1qNVqYNs24uXHyMgInD17Fpqbm+H222+HZcuWhZmFOFWIMQ47H3yqcB7ESHg28GkA+N2EPJQ4gAWp+w8cOHD/1NTU11RVzQAAaJqGNE0LkXB+4w6AR0VerzuOA67rQrlcDgE/jDHk83lIpVKQyWQglUo1NPY4oo48/x81/Sff+H15r5+TjTzPA8uywtKjUqnA+Pg4DA8Pw+TkJAAAXHfddXDHHXdMcy68NFFVFQzDCB3AbKcdxeczQ/nAQUIfAN6MEPpmkgUkJcC8UnwPHTp0Q7Va/aJhGFnf9yl+4YRgl3iRB220EMwzTTOM9I7jQDabhUwmA7lcLhIolCm7IPTfxfagSO6Rqbtxqj8iS5BHbf49TdNCpwSCQIjoTHK5HFQqFdi7dy/UajW45557wtaf+HzkWYTZ8CBk5yY6MOngwAkojuN8qFwuP4wQKiZOIHEA8wL6nTx5srlSqfwvVVW7bdumgYpveHGKiLcYiW3bDm+KokBTUxNks1kwDCPSABqJb8S1EqPGfWVDjHMGcY6CEBKWHel0etrzSqfTkMvlIJ1Ow8DAADiOA3fddRcUCoVppYCcYcwkOVatVmHfvn1QKBQgl8tBZ2fnTO1EBAAMY3xLKpW6FwC+KawyS07iAOasbKLDw8MfMgzj5aZpUkIIFqMZv7A5R54xFqbOhBDIZrPQ1dV1zsUsR7fZIuZiSi8bPDcwDgSKFF758aP+Pn8MngXI9TvGeNoUIMYYisUi/Pu//zu8+tWvhu7u7hAAFJ2SOKYc939mMhl4+umn4ejRo7Bu3TpobW2F9vZ2uPPOO+McAQIAqigKBoCXM8b+X2L8jQ9OXoLzr/v379//UkLIe23bZjKwxj/nBB3TNEPD7+zshL6+Pmhrawsv4LjU/mK0/+IyAPHvRQ0FibhBI2cj8v0zmQxks1nI5/OQz+ehUChAc3Mz1Ot1+MEPfgClUinMhuRJxEbGzx3PunXrAAAglUrB3XffDV1dXbB79+6QFNXg3AcAvS+MGCRLShIHMDd1P6tUKh2lUunjjLFCUNcjceyWU245ym8YBnR2dkJnZydks9lZpfHna+jikJBsyCKdWDQaGSSMu8Wl7ZzWLHY5eCnQ1tYG/f394DgO/PjHP4ZarRYOJHFAUXQEjcoR/ljVahUeeeQRUFUVjh8/Dj/+8Y8bYQEMANYAwCuTKzdxAHOaBBw4cOB9lNJb6vU6FSMLN7RarQa5XA56enqgp6cHmpubp6nrzHFGEhqpnF7LgiByRiA7j6j0vFE2IZc5fAw4k8lAJpOBdDoNXV1dMDExAQ899BA4jgO6rof0ZnmaMUY7AK6++mpYv349ZDIZmJqagu9973tw+vRp+K//+i8YGhqKe135HMQbGGPZJAtIMIA5Sf337NlzW6lUem9wgSEe1TgQls/nob29HXK5XMNafc7ACAnxb/T9OHBvtj+XW3F8+o87AJmXwFN4TdPg2LFjoOs6vPzlLw8zJNGxiEpD8mPoug633norEELg6aefBowxeJ4Hk5OTMDg4CMuWLYvqDGAAoBjje33f3wIAf5+AgYkDuCgfgDEGx3HenU6nW2u1GqWU4kqlAi0tLdDe3g5dXV2RSP5cR/yoSC6m6GLXISqCy621mfYCyF+LwCAhBBhjIZ4hComIDqO3txeGhobgRz/6Edx9992Qz+dhcnIy1BcIhpZiHUmhUIC7774bWlpaYN++fTA+Pg6bNm0KX+8oxxqAlpgQ8ibG2DcSdmBCBLqo6H/w4MGXjIyM/BtCKOc4Dqiqirq6uqCvr28aoDdfK7uiUvSoqB33PSmtZwghJs7+i2my8D9g8e/KmYUoQyaqEjuOE4KfAXsQarUajI2NQUtLC2zatAl6enqmTTsKRhuKiVzMEbQHLQD4ZYTQD5JBoSQDOO+zbds2YIyhJ5544m2Msfzk5CRbs2YN6uvrg0wmMytEe66ivgz0xWEB0vMIV3kLLUrC14xxZiIHDHkk5pgGY8wXEHy+tXia4YqqQDwT4AQi+XWZmpqCBx98EHp6emDjxo2wfPlyUBQF6vV6qGhUq9WgWq0CxhjS6XRYSsyUqURoD/oAkKKUvhwAfpCUAIkDOK/z0EMPKffdd5/38pe//JqJiYlfWrZsGbv22muhpaVlwQw/SsAzqr4XnUMQ/RghhAKAQghBXLSzXC5DuVymCKETvu+bGOMKY2wq0OdTMMZ5jHEWIZRxXXdVV1cXSaVSIaWXUkoDZ4IQQjhq5wBvFYpsQM6HQAiBbdtw4sQJOHPmDCxbtgy6u7th/fr1kM1mwylInj2MjY2FWgqtra0N5wj44w8ODgIhBJYvX86JQdcHYGA1KQMSB3A+6j4eY0zZs2fP7/X19XV1dXWxILLMC6gXhfDLziCK9COk4RQAKCFE8X0fVatVPD4+bmOMn3cc5zBC6JlKpbLftu1JQsjxe+65xwQAFwBsDmwCgA4AyrPPPpsdHh5ejRDqBIDbTNO8WlXV67q6upbzqUP6wmG+7xOxK8B3B/B6XqQa825BKpUCy7Lg7NmzcPToUXj66aehp6cHent7IZPJQHNzM3R2doYdAz6HoGlamBHEYRWtra0wPj7Onwfyfd8lhCSKQQkGMLuan0+SHTt27NpCofCn2Wz2tbquc2VamO/V3HKNHwf+CeO8lDGGPM9DlFI4ffr0lGVZT4+Njf0EAH7wqle96iBCqHQxzwljDI8//vjqUql0e3Nz88sRQne1tLSszmazvITwKaUEXlh0GpYVHBPg+ACfduQfOV4wNTUV6iFks1koFArQ0tICHR0d0NbWBtlsNiwHeLnAyUgNdipQy7JwqVT63a6urr/m05vJVZ44gIaafowxcvr06d8oFAofyeVyK4I6Gi2E4YuRPs4BCO0zGqTMuFKpQKlUOjQ+Pv4dQsjX7rjjjmfFVJcxhnfu3IkAADZv3sy2bdsG27ZtYw2wD7Rt2zbYuXMn2rx5M5PBs+eff757fHz8Nbqub9F1/d62tjauigSe52GRHCU6Af59TpTiN9M0Q4KQ67pQrVbB9/2wjEin09DR0QGFQgGamppCfoVlWaEAKRdardVqYFmWTyklvu9/p6en580AYCYjwokDaLS9ByOE/AMHDizL5XL/u7u7+81cxz9Ajxck6suIe0w7jzHGKGOMlEolOHPmzHPlcvkzfX19/75mzZpRWT57ri78rVu34o0bN6LNmzeH2vyMMfW73/3uy1VVfV9XV9cr2tragDFGPc8LMxJxdRlH/kV2osgQrNfr4HleuIZMJA7xjIEQAu3t7bB69Wro6OiAVCoFCCGo1WrhiLVlWfTgwYNYUZRHNm/evAUhNPTQQw8p9957rz+b1+JK0RhECcX3F2nh8PDwSzVN+4vm5uZN4mrrBXJC5zDy5KGZoN6nGGNsmiYcP358wLbtLy1fvvwLK1eunAR4YQFpVMSeD6e5c+dOvGXLFp87m0ceeeQdCKH3dXZ2Xp9Op8E0Ter7PhbHgPmNKx1z4xf3F/ASQmwxir8D8Iu9CB0dHdDd3Q2ZTAZaW1uhpaUlHGMeHx9ne/fuRYVC4ec33njjBxFCu4UVZJELRsTV7QkIeOWIeSojIyO/3dTUtF3X9SwA+EE5gBbK8KNafPIsv6IoFCGEjx8/bpXL5S+lUqm/vPnmm08Lhk8XSh47MB4fANCOHTtw8Hf/78DAwDdPnDjxoUKh8N6Ojo4my7IopRSLewR5u5ETgERj5/MFYrkg3kSwj3cXarUauK4bqibxlmFrayu64YYb2PHjx+/at2/ff5qmudUwjH9ACNli5gcA8PDDD6OHH36YBobPxsbGljHGsh0dHYeTDAAuz1XdW7Zs8Q8dOrQ8n8//ZVdX11sEZRm8EIYv1vxy1JfuQymlqFQqoZMnTz6JMf7I7bff/sOZotlCl1FiRvDzn//8dk3TPlkoFG5XFIX6vs8j67RBJZGDEDWbwKO+OGzFW5LcofCuQC6Xg6amJmhvb58mamJZFj127BgGAGhtbf1RV1fXXwLAYwihasT/kTt9+vRdlmXdgRD6xpo1a/Zdzq1DdCWDfQMDAxtaWlq+ks/nbxEkpeb9NZEn4cQUWHYAnudRSimemJiAkZGRzzDGtt1xxx0TW7duxQAAiw3VFh3Bvn37WsbGxv6subn5vZlMBoJsC8sMRdkhyjsQxfVnomGLN0IIpNPpcCaDLzQRuiXs5MmTUCwWUSqVoqtWrdpjWdbjpVLpZ6Zp2oqidGCMby6Xyz3pdPoxVVW/0N/fP3K58waUK1HFFyHk79u3766mpqYv5PP5jULKDwsV+aNSfbH3H8zQ+4wxcuLEiZFarfYnd911198Gv79oKa28NNixYwe55pprJhhj73/wwQfHfN//vY6OjqzruixgFIazALJegSg5xkuGKCqyqCgkMhHr9ToAvCAoIgi1oJUrV0JnZyc9evQo3rt3740AcCOl9P9TFGWYUnognU7vm5qa+vBNN920W1R/SkqAywzpHx4efgsh5G/a2tqaFirlB4k/HyXOAdP1A6lt23hwcPCIZVlvv+uuux4TeAhsCb3mgBBijz322BtTqdTnW1tbm23bpgghLI5Ji/qBYjYU1RmRyT+iDDnXLCSEQCaTCYVIJe4Em5qaYoODg7RcLuNCofD4tdde+8sIoVGZCwJJG/CyMX4ItPx+vamp6XP5fD7FEfWFjPpRYhjihR2g3dSyLDw4OLiPUvrW22+//bkgQ6FLjc8ulgSPPvroKxhj/9zb29vC26vyhuEoRWF5piAuCxBLAg4mcqBQpBCLJKpKpcJGRkZQpVI5msvl3rd27dofXEkbhtCVYvwYYzY+Pv7+dDr9Cf0FWt+8R37RqKN6/VETfhhjv16vkzNnzjzR09PzQFtb2wEOWF4OoOtTTz31Kt/3v9zT09Pm+z4lhGB5v6C8slw0bPk1lTcT898RjZ7vSlRV9RxxFp4ReJ6HRkZGSrVa7aOtra1fbGtrK18JTgBdCQq+jDEyNTX1J9ls9k+Ci2JejV80bFGEU+7xy33/YJU3HhwcfDCTyfza+vXrz1xO9FXuBH7+85+/VtO0f1ixYkUzQogSQnDccJWY4jfaF8C1CaKchihiwvUKxMcLfi+8Jmq12o8xxu9Ip9ODl7sTQJd55EcAgEdHR7cWCoWP6LrOgiiL5hPhj5rai6LySjr5rFKpoOPHj+/q6el5Y19f38DlePFxJ/DTn/70bc3NzV/s7u5OBXwAJEblKEcgqxJxsVF50YmYLcjlgbitKAL0FclfzwDAexFCj1/OTgBfxnP8CCFES6XSh5uamj6s6zoT5sTnndTDa31R9IL3s2WBDowxq9VqaHBwsG4Yxv/o6+sb2LFjB7kcL7rNmzfTzZs3k3vuueefpqamPj4xMYFEI5UNVEzvZcQ/qhWoqmqoTMQ3NPH0n3/eYEsxCnAJCgA3ep7379Vq9VUIIbpjxw4CSRtw6UR+hBAdGRl5r6ZpfyhoyKOFBPxEw5dxAXE81nEcOjk5STKZzLPXXnvtM8H/cFlGnKAkowghRAj55Pj4+HXpdHqzqqpUURQsGrn4UdYOlLMFuRyIWqgymzZv8BgYAHxFUdpd1/1KuVx+Zz6f//blgMVc9hnAzp07MUKIDg8P/2Y2m/2rVCqlz7fxi6l8I2lt8XOeIdi2DadOnQLTNKG5uXkQAGqXfe8ZIbZ161Z0xx13mIVC4QODg4OPBWAgizJoXruLKb/c/hNbgHJmcIGiLQQA/FQq1app2v8dHR195ZYtW3yRyJRgAIuU4Tc4OPimfD7/d4VCIb2QgJ9IWRV5/I0kuUdGRmBoaIitXLkSZTKZP1qxYsXHKaVXhGoNr61//vOf397a2vqtnp6edt/3AWOMZMOVPxezA/75PKkzUQDAlmWddBznzYVC4bHLCRPAl5vxHzhw4L5MJvPZhTJ+sc4/H91/hBBMTU3ByMhIuB9Q07RJLt0HV8AJqMHkrrvuesxxnO3Dw8Oc5MQagYHy9+bR+EOJccMwViKE/vno0aM3X06YAL6MIom/Z8+e9e3t7f+npaWldaH6/HEpf9yqLWFABUZHR8Nlm4H4xZW4qIVu3boVd3R0fKVcLv+H53mYEMLk9D6qnpfLgHm2Ez+Xy61qa2v77L59+3qDcgAlIOAiSSOLxeJyxtjft7a2XhOMqZKFAPxms2hDlhHzfR/Onj0L1WoVWltbw+WblNIrTq2Gy5EjhGqDg4MfHh4evmbVqlV9CCEqio7KLb+YNt58HgIAfqFQuM3zvM8Vi8W3IISWPFkIXw4sP8aYVq/XP97W1nYHH+xZiIk+OepHCV/IICBCCMrlMoyMjICmaSFXXdM0cF33ipzO5Cl1b2/vXtd1v1Cv11EUt1/cRrTAxg/C6LXf1NT0qmq1+id8IjMpAS7h80cI0bNnz76/o6PjVwN+OblEF8es7ue6LoyOjgJCCHK5HKiqCul0mmUyGdA07aogGtIrbZfd5s2bKWMMdXR0fLlYLD4WDAvRKLT/EjoqAABMCGGtra3ve+CBB94ijzgnDgAWdFuvf/Lkyf+Wz+c/HKj2LohUd6ObOO0nlwCMMRgdHYUzZ85AOp3mwJ+4aPM2AGi6QrMAtm3bNtTd3T06Pj7+2ZGREZcQgpjgWS+l8UudM5bNZvWmpqZPHjly5F6EEF2q2QBeyjp+ExMTvdls9pOZTKZ5Icd6o/bpNVrXJa67PnbsGNTrdUilUqDrOncAOBgBvr5arW66UsVatm3bxhhjqLm5+Tujo6M/8n0fYYzZIjL+aaBgoVDoQAh9cnh4uHP79u1L0gngpbqu66mnnlJd1/1YS0vLdQtl/HKUFz+XF3nIwyyEECgWi1AsFiGTyYRy1xhjUFUVGGNU13UNAN7A59GvxCwAANCGDRsqvu9/fnBw0MYYh05gsbWdAcDv6+u7qVqtfmKplgF4qaL+TU1ND6TT6TcJG20uyWbe2Yz4UkqhXq/DwYMHAQCgubk5LAk4f53PKBBCfsV13U0BOo6vTMU2hlatWvVwqVT6aaAlyBahswrxgI6OjrccPXr0HUsxC8BL0fj37t17faFQ+HA2myULlS5HAVDy+GqUaAXnsA8NDcHw8DBks9lwdJW3twJ0GzmOQ1OpVCsA/B5jTOfGcCVmAe3t7RXbtj83Ojpa53X3YmXS5nI5kslk/vzo0aM3LzUngJdgy4+0t7f/SVtbW68g5LlgG3tE2m8j5J//DiEEbNuGQ4cOAaUUdF2fhhOIrS2MMarX6xQh9Cumaf4+N4YrzQlwxzc4OPifxWLxwUXsALgT8Lu6ujp93//Y2bNnM+L1mjiAOQ0OiB47duzXmpubX7lQqb+M8keBgBGbe6aVAKOjozAyMgKGYYCu6+eQWMT1257nIdu2EWNsq+d5vxmQTK4oJ8Ad35YtWxzXdb9hmqbH9RAXczs6n8+/bHJy8je3b99Ot23bljgAmNuWHz148OBVhUJhq6ZpxkI4gDit/plqfvH3XNeFo0ePguM4kM1mz6Gw8jKAT7txYQyEkOp53v/xPO8dnGl2hWUCDAAgk8l8f2ho6OkgACzmLAC6urpQOp3+3SNHjmxcKqUAXiJS3owxhlpaWv6wra1t5ULx/ONuUZmA+Dlv+SGEYGxsDAYGBsAwjJDBxo2fOwtFUUDX9bAtqCgK8n2fMcYMSunnPM/7rWBU9ooBBoORYXzVVVcVLcv6RtAmhcWcBQCAv3z58h7TNLczxhR+3SYO4OJTfzY4OPjqXC63eb4jv0znldt+Mu1X/FpuA7quC2fOnAGEEBQKBVGjPvwbfDkmxwP4fRBC3AnojLHPuK77ecZYC2eeXQmOYOPGjQgAkGEY/zU2Nja8GHf2ScGBKIpCW1pa7t+9e/cv81ImcQAXB/yxHTt2aNls9n2GYaQuVep/vr+DMQbTNGF0dBQKhQJkMplpu+xFdqBt29OyB13XOV6AKKUs2KX3Hsuyvmua5n3BoEzoCC7X0uCNb3yjzxiD/v7+A1NTUz9YhNfnNOfPA0Bra6tmGMYfnjhxonux07rxUkgFr7/++l9PpVIvvRQ9/6g3WRb5EKf9RP3/8fFxcF03XFChadq02l/MLhzHmQYK8gEYRVEQQgg5jkMNw7jNcZwfWJb1T4yxW7gj4MrHl5sjYIxxhSffdd1/LZVKXLCTLSYHIOo92raNCSG0s7PzxrGxsfcvQhbj0nAAAfDHDh8+3N7c3PzeVCpFFsoBXAxXQHQAJ06cCHfWaZoW9vz5BeF5HliWFa66lmnEfKlF4DiwZVk0nU6ruq6/1XGcB03T/HK9Xr+Li6Hw0drAGVwWmcHmzZspAEC9Xn96cnLygAgQLqLUf5oT8DwPBVnfO5988slrFjOfAy9mXjgAgKqqv9bc3Hx98CLiS/HGyjhAXIYgevuJiQmo1+shuMcjOhcoFZdfOo4Dvu/zlWCRJ3AE2Pd9Zts21TQtaxjG233f/69arfZDx3HeU6vVlgVgoS9kBlhwCHipgoG333770KlTp34YCKxe8pZg1HvPcR3HcZDjOLSjo6Mjm82+T+CwoMQBzJLxBwBQLBaXFwqFdwbLPNh8p1Jyms+Nnm+obeQAZJ5AsVgExhik02kxnT8nymOMQzDQdd1ppcA5bxbGoOs60nUdB9gATafTqUwmcx9j7POU0sempqb+/uzZs29kjG1kjKmBI/AF3IBnCER0DIs5W9i2bRsghJiqqt8tlUpW4ADYpTJ6/n4JET987/hH0zS52MkbDhw4cCOfdoREEWh2rzVCiB0/fvwtPT09GxYi9ZfFPOM8fCMNAN76syyLTUxMgK7riLf/eP0vClmKzsNxnHAXHgCAIGUe5wyQwJCjiqJgTdN6AeABXdcfqFarEwih4/V6/Weapj1FCDkAACMIoaFAMSnO8Yo1dpSRsQjSzoJwAoaHh3etWrXqaQC4IxgQQpfKAYhMUJ7FSRkjxhjTTCbTNjQ09B7G2LsXI49BWazrvJ599tkOXdffxqP/fGUr3OBl7X7+BotvdJS+H0Tw/sfGxpDjOGHvn5N8ZAxAvGBEByAuuJwlCYUEjoUBANU0DRuG0QIALQCwCQDAsqyy67pjExMTJ3VdH8YYP0IpPTU1NXVEVdVSe3u7iRCaOt99BIwxRXBETHQefO/eXJUBv/zLvzz11FNPPdTa2nqHQJi6pMIvMvlLYo4iQghTFOX1TzzxxBcBYPdiW/WmLFJWFevs7Ly/paWFAyh4od5oOZ2PWkkdd/iQT6lUKgEA0jQtr6oq6LoeLqoUN9yIzgYhFKb/4s9n6QRkZ8Akg0SGYeQNw8gDQH9w37dQSqGlpWUMIWRSSqfK5fLzhJAKIWSQEHJAUZSSII1dBYAiAIwDgBsYuIkQ8mAW68Da29vRvffeS8UMD86fEwCe5+2q1WpOoVDQFqLPLhq4PAbOyVycx8EdkuAQEKWUtra2to6MjDyAENq9fft2roHIEgcQHf3p1q1bNd/3f0XTNAwAFM2z9Ysz/XH7/GYZESilFBcKhZ0Ioacty/osQggFpQEf9z2na8AvJv4zflHxf/s8nYA4HYki9t4xoYzAhmG0B1/25nK56yBeyqyOEJoEgCkAcBlj1DTNIQA4SCk1CSG2ruvHXNc9zhhzNE0rAsAQQohGbdMJyo0wc5jJIHg3oFAo7KrX6wOFQmF9sOdx3gMCzwLla0H+vigPz68nhBBSFIUhhN60d+/er15zzTVPLqZWprIYo/+v/dqv3dPU1HT3fNf+svc+X/JP1PMfGxtjp06devT1r3/9Pzz44IMbKaW/5bouRQhBKpVC4ixA1IXm+35IGXZdN3wuiqJcbLqLYl5LFlHzI/n+qqqmASANAMuF790EAK+WHIXteZ5fq9VGKKWnK5VKrVqtPkkpPdzW1va8pmkTAFBECNVkh7Bz5060f/9+tm3btliHsGHDhrMnT558BADWLzQOEKcFwZ0BBwOlchF5nkebm5tbJyYm3s4Y27WYsAC02MZ9AQBGRka+3NnZ+WvzyfnnLThe+0ch+nKNH0UAEv0JQgifOHFi1DCMl1133XXPMcbUhx9++B9SqdRbEUK+YRiEr7mK0rfnGAEhBAzDCJ0EBxH54stLRCyJAgZD5xFkUYTX5mKqTAgB3/ehXC5XFEWpep53ynXd/QDwsOd5z/X19R1HCJUjFHemZQd8N98jjzzyjk2bNv1dAJTOixOQo7o8FSryNvjXfN2bvCqOj60Xi8XT7e3tL9uwYcOhxVIG4MXG+X/++eevJoS8fD435MjtvKjPZxr1jQOrVFV9vKmp6UjwtXvvvfd+AGP8H/l8nmCMfUIIEzfZcqMWl16KBCGOMFuWBfV6Pfx+I/3BeQwWKLhm+I0EWaRCCFFUVUUIIYYxZhhjFrQdqeM4nu/7vmEYOcZYt6qqtxqG8YBhGF8hhPz8xIkTDx05cuTzp0+f3jw5ObkqMA6ZyxBeq6VS6Vi1Wq3BAo6CR3FCZAcRVQ4EN+x5HrS2tvaUy+XXBQNuKCkBIrKAY8eOvapQKHQJCyPmDdSRd8o3IgPJP5c/apoG9Xodmab5o97eXpMxhoP+9Thj7Neee+65zxmG8Sbf9yn3duJUoKwPEBBKwtRf7Du7rguKooQ/EzX0F0tWyVWOVFUF3/dx8LwZY4y5rstrZYYQyiiKcpNhGDc5jvOe8fHxscnJyV1Hjhz5Xmtr60+am5sHEEJVXiYwxsipU6f2+r6/HwBunY8MQEztxcwvjgYe1yGSggZTVRVZlnX/5OTkF7Zv315aDFkAXizEn23btgEAgK7rd6qqyuaL+CMCN/L2nkZCHzNwuhlCCJdKpUqpVHqKf5PPhCOEJru6un7TsqzPU0qxqqqIvnDOySrkNVgiY1DMCGzbBtu2w++5rht+vdhGZnm2YxgG0nUdK4qCVVXFqqoShBDzfZ/W63XfdV1KCGlXVfWVAPCZoaGhJwcGBh48cuTIH5ZKpXWc1NTb2zthmuYT81XGxnFAZI5I3AJYMSMQ7o8CZuimffv23Q0AsBiyALRYdP4AAJ544olX9/X1faWjo6OFUsq4UOZ8pHTi11GyX/LnUZ0BwTFQjDE+efLkY2vWrHl1U1PThOjdee83yHB+HyH0x7qu5yzL8hFCGL1wIjfeRu3EE9dkBYKi034myYwtmmEU/pq6rgs8C7BtO/w8AGWZ53nU8zzEdyVSSsE0zVFd1/+jp6dnZ6FQ+NGuXbteu379+p35fB7NZRYgIvniKncACJ2rSATizpmDf+IIufw4vu9TwzBwqVT6h7vuuutdAOBf0RkAV/p59tlnM3v27PmIqqpfy+fzLQLTbc7AnCiPHmXocay/qMggioAGdfveQqEwKZcu3PgRQrBmzZpPaJr25lqttl9RFBLckUbtspeHTGQmGs8GeEbAP+dU1Gq1CrVaDRzHmXGJ6XxmDXIU5UNOHBAVGZLBanBCKcWWZTHTNKlpmhQAOgDgHcPDw987duzYv1JKry+Xy+58Ln2Jo3zLa+Ci2KPy1ujgc2RZFqiq+ooDBw5cxQlOVyQGwBHdSqWy8dSpU58pl8v3IYRA07R5a+1EvZFRhhAFBs6EXYyOjoLjOM8JbyqNWoK5c+dO0tPT893Dhw8/6XneVs/z3pnJZAzGGMcGMOcHzEZ0VHRE3DGIgCIATMMS4lZtxa3dEjOIKFXkqJHouPvJGRfv4yuKErIo+f8eZAVhK9LzPOY4DvV9H6fT6de4rvsa0zSZwB+Z87S/kfhLVMkYxQiUBGSR53kUIdRdr9fvB4B927dvZ1eUAwjafQgh5A8PD7/m7Nmzn6OULh8bG6Pr1q1Dc532i7P3omePAvVEnKBR71f+HiEETU1Nuc8888zuWYhd+kHZMwYA7xsYGPhn3/c/rqrqi4O/zbMBHMdEjClDps0jiP8fT7vFdqPYTuTgYRSphpOUZmJFztYBRGVhhJCQ+MQfB2M8Dc8IBFOJ67qsVCpRAEC5XA7Nl7CHHOHl0iAq8suOQG4x858RQlilUvlvjLHPIISqlxIMVC5Frx8hRAcGBt5y9uzZz6qq2lwsFqmiKLi1tTVynfbFHrk/KzuFOGR/tpttVVXFmUxm75o1awb4KPP27dsb/o7gCB9jjL3y6NGj72CMvS+bza4nhIDjOFwDEGGMUSOwUFQX4rco5WF5uxE3etd1Y7ECOUsQHU7U57IjiZuYFGtq0Vj4dGQU8BZkOAhjjFzXhbNnz8JVV10FfC/kfGeLUZFeHhKKUpCWfg/Zto1s2775pz/96XUA8GgABl72DgABACKE0BMnTvxWqVT6JADolUqFOo6D0+k05PP5OV8CGUXoaRTFGk38xS0GCRD5Z17zmteMn6f0NZ9zqAPAZxljXx8cHHyb7/vvUlX16iDqAcbYp5Ri9IJHmDY1KBpflCipeF/RoPnPZ+pyNPqe6FRExypTZONarI0UlrgzEEs1kXzj+z5Uq1WwbRt0Xb/goBFn6NwRRUX6OG1ImTMgYh5CBoEopVTX9YLjOC8BgEeviBJgx44dGCHk79u373cdx/m4qqpatVpltm3jyclJuO666/iOPJiLek4cyohK2xvRfs9nAIgxxoGdYwghjwOb5+EIxGxgHAA+zRj76qlTp15vmuYDmqbdkk6ntWDWnAb0V8yzgjgeQNTWItEByJTk81m9Hded4Be7aDRRjxlFxIpywPw5ySk0v5mmCcViMQwccyn/BjMoQ8cZv6wnIXYGRKeg6zrzff/Ow4cP6+vWrbMvVRmgLNQiRYSQv3///ndQSv+cMaZRShkAINd1oVarQTabnTciR1yEj0rTZur5S9p/DCGESqUSZYwdvMhFGExwBJMA8HeMsX88c+bMJsuyfh0AXpdOp9t56uz7PhUuVBSg57GZy2wAv9kYvhghRQMVnQkH9sS6Ocr4Z+pA8MeUcQixM/LC4OXcpvzccKPKw0Y3cTowysEJTE9ECEGe590wNDR0NQA8c6nKAGWBJvz8wcHBe6ampv5CVdWUZVnUdV3s+z7U63VIp9OQTqdhrgk/Yroblf5fTOuLX/gYY7Btu3748OHn52gjjugInCBFfJQx9vFyufy68fHxlwPAbdlstkmkDjPG/LhBnqjo3+j/l52DyFEQQUax1o/qLnBjEqXOZCxitpgLbxXy3+HZTrVanRNWqPxcosDUuOsnilsSld3wnyGEkGVZVFXVrtHR0RcDwDN83BkuJx4AT2tOnjzZPzU19QVVVdtd16UAgDkZhDuAi6njotLLqN5ulKLLhfbCg+fKlan2rFixYkTUMrxYRyDId+HgdRwoFAp/vWrVqldnMplbGGPvcBznW77vH7Usi2azWZLJZIhhGBhjjCilHiHEEzn1lFIWnMhyIOqC512DqBZiVKouv5aBjFl4MwwjVEkW+/+N5i1khyPep1KphB2Oi+n7i6Qe2bBlRxGHW8QxS0U+h1AaMQCAdDp91+HDh/UtW7b4l0KWTVmAZZ7qoUOHPp7JZDYEXg97ngeqqoJt22BZFjQ1NV30lFscQNNog08jfKCRMxCfp+d5QAg5cO+995bnGsDkGQF/PblENgAcBYCjCKF/oJS2nzhxot80zRdblnUbQmi9qqqrDcPQubHySTWeTjPG/GBgJ8wUeJ9aZCXKcwpilOQGyW9ShDvHWMXH5ApJmqaFGnr8FtXtiCNJYYyhUqlAvV6HQqEwqwAyE7cibhnsbK4JGfdoVDr4vo8CAHljpVLpAoCTlxsIiBBCdN++fW8DgF8GAIoxRnw0lL9YlUoFVq1aNa2WvFgm1/mg/Bfj44KV3mDb9l6+qGO+NtcIHAIEAGjnzp1oy5YtfsAnGAOAx4P/sdV13avOnj27Udf1Pl3Xb6rX61lKaY+u652e52nZbJZwZyB3CzzPY4FxMcYY404kSL+RMMiEOJFHzABEMk8cqCq+D9wZqKoaOitZGLURtlGpVMCyLCgUCheU9oufizRemQosy8TJWYM0/TetxRlDK0cB1rC6XC5vAICTlwIHUOZT0//IkSM9pmn+vq7rCmOMcpKPyFyzLGtabXe+DiBqICNuUqsRw26murjRBZVOp8sLvDmXiVnWzp07McALqjlBJ+GR4AaMMdTU1KQCQHetVms2TbOlWq1uchynHWO8XNf1tZRS3XVd4vt+B0KoLdhRiPiospDpAABwA/U5ocjzPO4MQjCSG3SUA4jCAfhEpbw3kTsVEVzkzEGeRZZKJejs7Jx1lhgV5WWjj1r4GsUGjGIHxrUIpc1RiFJKC4WCViwW7wKA719uGQAzTfN9uq5fHUR/zA1fUZRwiIXXb57nTaOrnk/aH8f1n0vQL8b5oEqlUs3n88fg0q3RBlHll2cIDz/8ML733ntpkJE4QYrJ08wHhftnxsfHyeTkJNF1vSudTnenUinieV6753mbKpVKq2maWFGUbk3TehBCqXq93m4YhpHNZkOD5VEPY+wxxhBHujl3QU7do7gBImbAf+44Tjj0JC5TpZSGUmkTExPnda1EGW0j0c8LKScazULIeFVzc/NtBw4cyG3YsKGy0O1AZb6m+44dO7auXC6/RYgM02pHRVEglUqFxs9n3MUFmTO96FHtpKgSoBHYNxMTMM4ZYYyZpmmoVCpVBwcHj8Mi2VgjZAg0Qm0JAQA8/PDDGADgvvvu8yVprkkAOCB8/TVJ/bfl6NGjuud5Kz3PW2Hbdnu1Wr3Ltu0VhJBVqqq25fN51XGccFAJY0wDViMWW5UiuCiDjpRS0DQtjMo8SMjKSTxTKJfLMxLIZGC4kbpvo17/TFE+rsSIuj5930eBg7umUqmsuRTtQGW+pKNc132zpmkrgjoSiYARr6symQzk8/lwmk2MDFFOII6o0SgDiLpfI5LKBUy5jUxMTFgAi3u7juSgqJgtwC8WcCCuy7Bz5060efNm/jkE6r+jwV1PCQ//GcaYYllWT7FY7BsdHb0+k8ncYtv21aqq9mqa1qJpGpimySnHPqUUIYSwPJMgT0FyfMD3fQiERTiXPiwrCCFg23YoPTYTGzRqmi8O3Y9zCPJegDhlJvmajFAOQo7jMEVROj3P2wAAzyxpPQAe/cfGxpadOnXqQcMw1iOEqKZpmHttRVHC2p9SCnv37oVsNgvr1q0L20NcRlt+QxuxxqIWe8zUnuGpa1y6FuckgguPKoqCh4aGvrxhw4Z3Bqk2Wixqr/Oo2chxBxTgDiwK+GSMaY7jXFUsFu9xXfdu3/dvwRivyuVyIeIftCjDtEBuLfLoz0VPbNsOHUmtVoN6vQ7lchnS6TS86lWvgkwmM6MEnMjQk8d1o+i8orGLDD+uERClASDqG4iPJxOEgmvMV1WV1Ov1v9myZcv7hMlGtuQyAB49RkZGXq0oylrP88AwDMRRXjH14y/oypUrYXJyEiqVCqiqGuIDInAnt6GiMgCxBTVbltnFThkGZKNJwQAuS+OPySLOmfAUMgcakJieC26frVQqndVq9dbJycnXp1Kpeyilq7PZLDFNEyilPqUvwERR5CVCSFgWcOPieoqqqoJpmlCv1yGTycQCybPRe4gj+ERlAOLkpegcZEWmKLJQTCnaEwTQJdsFQFwCizF2T5DiUUIIFnfj8XYTB4O6urqgWq1CpVIJt+jy6bRGhno+YM18RcTJyUmYmJg4KKr+wBV4xM5EhFPggicjAPAdAPhOpVLpnJqautM0zQcwxi9VFCUVqAPRYMbhHOBQrv9VVQVN07gWI5imOeu2nzhdKHcB5HIhiiY8W5wgLmOVPkee50GhUFh1+vTpZQBwej60MGG+mYD8H3rve9/bYVnW7YHRI3FQhaf1iqJA0GqCQqEQtnPq9fq0TbmytloUWHMxkT2KvtqIFSfhHMj3fep53oiY/SRnOptRWluOGWM4l8uN9PT0/L+VK1fe39ra+t9N0/yy4zjj2WwWY4yR7/uUUsrEtBoEfUERSNY0DQzDiHQAszHURlF+NgIxYnYa9TuNylC+Piwob1YUi8WVC60VOGcOgPeiS6XSnaqq9nCjFzXqeAuQp/mcCNLS0hI6AF7j8TpLrJtmQvij2FdzLS4ikmYwxl4ul3MScz8vhzCN4pxOp3+2evXqBzRNu7Narf4f27ZHU6kUVhQFUcFqeBbAy0kxkOi6HusAYIbFHo0EQBsZfpyKlJxdRJWu8ksTqEE1l8vla2GpzgLs37+fAQDUarUNGGPV8zwmMMempXBiJuD7PnR0dICmaVCr1cCyrGk6djwbELfkROiuxy7vmEvDFyiuLOhmjELQW08ygAtyBowxhrdu3YpXrFhxqL+//wOGYdzpuu5nXdet6rqO2S/OORoD4m4F27angYfi9SGP5s6knByH9Iuz/bKDmEkwRP6ZLE6jqirUarXeuZonWVAMgO/0Y4yhw4cPbwiMlXESiNjjFbfiALzAMDMMA5YvXw6HDx8G0zTD1I5nDOILJ/Z/L4accSH6AuJN0zSoVCoTU1NTZ2ajApSceD0EjqEAAPT29h4FgPfv3bv3XwHgjwkhLwEAsG2bBkBhGDi4A1AUBWzbDjUGG4HFM5UIjaL8TMBiI6B6pscKJmNvfuihhxSEkLdQhKC55gEgjLEqyjrFRVNuwBzsW7ZsGZw6dQpqtRroug61Wk1suU3jmEdp18my2rPNAs4HM5C9er1ep6lUiiZmfPGHA6hbt27FwW7Ahxljj508efI3Lcv6SCqV6qzVajQYokGcDsyDRBTQJy9+mY0OQdw8iah2FEclFp9DlDJSI31JxhhYlpUKbNKDJToOrHqel5mN0fEygE+FpdNpWLt2LbiuG7Z16vV6KHct4gEyoSJuCvBCUvyZ7iOJUljHjx9PHMAcOwJeGiCE7L6+vs+6rnvfxMTEDwUqIeNdAF5KBopJ5yxUieL4N5L9FvdFynTlqOtOdhpiizDKGUFMe9B1XchkMsu6uroWFAicUwfw7LPPpiilzbNp0XF+NwcDEUKwYsUK6OrqglKpFOkExAWMs7ldyDjxbJyEUGdOTE5OeonZzk9pwBhDO3bsINdee+2Bm2666XWKonyUUuoGrULKywEuJWdZViQPJG5SNKo70IjDH6X1H1c6yMFEfmxpUAoxxiCVSrX7vt8OS3UYyDRNTAhRZsvlF6Wl+Iu2du1aqNVqMDU1BQAwjSrK6aC8DIgSp5iN44EIZZ+oufVGjiCYXhuemJhw51oHIDnTR6CD6dI6AHzk6aefPswY+xQhpNnzPF9VVaKqauSm57hZkajxcbnlHLUAVFzRJi9uiboOZaXmmUpi27bV06dPZ2EJKwKZADARJyk1k/YbQghSqRRcd911gDEOhzz4dlzeHhRnrkWk90LLAFHcohEnQB5vxRhP8q0/lzMLcDGUBYwxtHXrVnzTTTd9NZfLbfE876SqqoRnAhz8i9rNF5Xyy1qFccShKCpwXMZwPiUlTN+diACABoSom5asA7j99tttXdfL8pSXaLRxL7xoWJlMBm699VZQFAUmJiZCHri8GjvqjZ0NetuI7CO2++StOBGiJWZinguXDXCmaX9//48A4HWmaT4b7A/0GWNQq9ViR25nIpJFlQKiFJrcCo67duSp16jrSrymhMdiiqKA67qZpZwBsECyKhzkEYcneD9fHKSIS9Gbm5vhhhtuANu2YWpqChhj04ZBZNRVTNkups8/WwXdQAgkscxLkw2QG2+88dnW1tZfRwjtzefzBCFE6/X6NCBwttdEo8zgQrpE55sBiH9HUZQMQmjBuAB4rrwz71tWKpXDQU2ExCjN03X+cTZvTGtrK9x0003AGIPx8XFwXTckClmWFU6VydNYcbveZuME4oCaqE08Ue3I5CxINuAzxsjq1av39PX1vRUAjqTTaWxZFhV3E4jZYqPFsFE4QNyyj6iZ/7j7yivmxOwiAsPiqkobh4aGMtymllIGgAEACoXCQc/zfD4aKxqn2MabjVEyxqC1tRWuvfbacAkEbwly7Tgxq5A12cXM4HyWfc7WWfi+n9T9l9gJ5HK5va2tre9xXbcYlAOMA3Wyrl+UDHlUOSC3EuNG0WeSAjufLhOnl1uW1fnYY48ZS7EEoEEK8zhjbFhcIiFHZtk7zqS939raCnfffTek02kol8vh+mvTNKe1B8WV2VEzBHErsmcjSS3XgIEwRQL9X2InsGPHDtLd3f0gxviDruuWHMdBruuyuNbwTHp+Mqg80yagODZhnHT6TACzaZrs4MGDsOQcAP8HnnzyyUHDMJ7SNA2YYFEygUds28zGCeTzebjtttugUCjA+Pg42LYNnudN6w6I4hHiRGEU0ysOQJwlarvg48fJiT6bN2+mjDF09913/zNj7MkgyLA4zn0jCa+Z1oPNBkRstGmqES4gTDjiG264AS9FHgDHAfxjx449YVnWa2XFIY7m8xdCVJqdjRNQVRVuvvlmOHLkCJw+fRps2w6BOM4N59FZ3CAjG+yFSpBH7cJLzqXvDnAiTaVSmZyJtx9l9HFr5KCBUtSFzJLEEYZEx2AYRtPatWs74AWp9yXXBeAW8h+2bY+oqsrRwWkqr3xwQ571no3xIYRg3bp1cOONNwLGGEZGRqBWq4XMQVnbPSBYnJPaxdV5cSWBzAKU12An59IfTdPqMvlmNnv95GGzKC0/8RaXMURdU3HksgjjR4HSUauiKL2MMbQQdGA8D5NdqL+/f6+iKN+O2pbCI7+on3YhWvzNzc1w1113QW9vL5TLZahWq+EcgUwYcl0XbNsOAUOOEcQRiOI4BTJizJI6ABaZbmEtCqiTR8fjNvnyayLuPZ9Jdj6O9huXEcQQz7Rg4IktxL5AZb72AWYyma/Ytv0ruq63BGg5El+gQDIaMMbTdgKcz2JOhBBcd9110NbWBkePHoVSqRTqwvExUV4C8P4w/zui1LT8ZvAoINdsER4/AQEX0VFVtR4g/kjM1OLS/tkMk3GHwPUH5P2BFzJhGjPNigCA2baNx8fHX84YewghZM7ntql5kwUP+pePDQwMfI8Q8la+Rlv0fnwPgCyKcCH1+LJly6CjowOOHz8Op06dAs/zIJVKhepDoiah53nTmH5i2ieuwYpTBRY3x861qnJy4ELFaBEAsHq97vJFInECnLNtP8sOoNFOgQtdty4zAoMygDHGPjA+Pt7FGHsPQmhqPrUB8DwNcCCEECsUCn/jOM44vEByYHKaJPfxGzEEZ3rDFEWBdevWwS233AJNTU0wOTkJU1NTYVvQNM2wYyC2DKPUY6I2CcutzABsTEqAxeEAeGR1o7QBZurRx20LEgeA+HUatTZcvmainEEjpqmYcTLGkOM4VFGUN1qW9UXGmMHHo5fMenA+ytnW1vaYqqrf1HUdBZnBtAkpboic0XehTkAEX/L5PFx33XVw7bXXgqZpUCwWoVqthi3DKO4AN3z+9zmG0KjNwz12Yn6LxwEQQlij7T5xdbzs/GW8YC7a47MVpzUMAwAAF4tFaprmlomJiU8wxlJCZr34HYBoNKlU6hO2bR9TFAVHZQHc6HiU5o7gQvA1se7r7u6GO++8EzZs2AAYY5iYmADLssD3fTBNcxqdWAR/5GxAjh78+4G+YdIHXEQOgDFGxS6QvM48auCnkXZEVJtupo7CTDJjcaPl4rZkz/OgXq+j0dFR6jjO+8rl8keWTAkg9WdxZ2fnMd/3P+Z5HtU0LRTUFB0AT8fFYR8Zkb2QbAAAYMWKFXD77bfD1VdfDZZlwcjISCg/bllWqEQsMgvFTTS8bODdCp6xeJ4HlUolyQAW0XFdl0ZFc7njI4KDUaPDs43ks9ESjJolkduCYgaAMYZ6vQ5TU1PIcRxUq9VoqVT6ULFYfDtCiHHtxKWwHRj4E167du2XDx48eKOmae/DGPuMMSIruIrlAUIoXA/GVV8ulLTDH4+rDQ0MDMDQ0FC4iUjX9bAjwOXJNE0L/zavz8QsQNd1vhY7sTpYtC3BWEON0w2YibQDsxSejQD3GmpYyuPFtVqNb1pGGGPI5/Oq53kftW37GV3Xn5tLUHC+mSwsEHik3d3df2Lb9s90XSeMMSq33MSpQR555Ym/i6nBOFC4du1auO2222Dt2rUAAFCpVKZdEPxvcxkyTlwSgUqhNMgkpgaLiRWIoiJ2I/FPeTCIG78oIy7eVxwsissY5OAT1fMXl+VyJ8EXoUoyeKhardJ8Pr/cNM3tjDFd2tW4qB1AWAo0NTVNKory7mq1ekjXdYwQovKLIoov8hRdTM9d171oMIZH8JUrV8Kdd94J/f394Ps+lEqlECzkpQh3BCIoyPfUBW9+WyBXxRJAcFF0AZQovj4X3ZT3BMSt7orS/IsTFp2VkUkcE96WFgVH+Pf54lzbtsObZVlodHSUep53f6VSedtc4gF4oQQed+zYQVatWnWAUvr+ycnJMVVVsaqqjPP35XRI3rYqKgJdDAFPzghWr14NN998M6xatQowxlAsFqFUKoVvgogByDff91te9KIXqZdiN2FypjkAFrwH+kwScY0mBMVt0XE1/0zIflSUlx1BXLkgA9kBrgGWZaF6vY5s2yb1ev0jlmWtm6vW4IKR2bds2eLv2LGDrFu37of5fP4jlFKHDwJx7xdHuhE5/WIb70LLAtkRGIYB/f39cNddd8FVV10F6XQaqtUqmKYZKhGJNGLuFBhjTYQQJTHBRXMMuZ0r9u5nctIzofZzIQQTJTknEtairtHgf0D1ep0ihPrK5fIDc7WNGl+K0c3JyclvP/roowdrtRpSFIVFLf8QEVpRBFSMyrMdKZ6tIyCEQH9/P9x8882wZs0aUFUVxsfHQ6cjYgHBx2xvb28yEbRIju/72SAtZ3H8Dfm6imL9ySIi8szATFyD2WgANLoPVxkWl+DwgTbHcZhlWW8zTXPNXKgG4QUGaQAhxB577LGJs2fPju3evRuq1SoTdwOIyDvHA7hH53wBDgryry9koGgmjGD16tVwyy23wPr160FRlJA3IKoPAQA5duxYkgEsDvlwYIw1i4YT17+P6v/LrcBGrcK5soUoYNDzPDBNc1pg45u2HMfBtm0zwzBWTE5OvmkucKdLEr1+9KMf0a6uLt+yLHjiiSegWCyCYRjn8Paj5MQ5oMM7BJzUw0HCuWJucYygr68PbrrpJujr6wOMMZRKJSiXy6her4Ou6+3t7e0LvtI5ObFDaBkRP5Kl4UTwTtTjFzknsnp13LDQTDsFZyICiTMl8sapWq0Gvu9PKzU4xTnIBBgh5PWMsbaLzQIuhQNAO3fu9HO53JF0Og2macJzzz0Hk5OTkMlkwDAMEDe+RIEu3AnwDcKc5luv18MoPZeOwDAMWL16NWzatAlWrVoFruvC2NgYIIRaTdPsCWa3Eyu8hAdjzFKpFJENVzTeKMHYKObgbI0+zshn6hBElQA88+XZrGEYYBgG6Lo+jZsCAKhSqaB6vX792bNnb5F0OBa9A2A7duzgf/OQpmnQ0tIClFJ49NFHYc+ePVwV5ZxV4nFOQBzokfn+ojDkXDmCtWvXwh133AFtbW0wPj6ODxw44AcpaIIFXMJDKUWpVOq8qLry/P75UnkbsQGj9AEayc3z0qVer4OiKJDJZCCVSoFhGOEYcvA7iDFGCSG4Xq+/KugEsCVVAgRGXk6lUjSbzaJsNguEEHj++efh0UcfhVqtFno8TdPCHYKcnSdPYsk7A3nbUNQHnEuMIJvNohtvvJG95CUvwa985StfwRjTEULe1q1b8UJIOSdneuoPAPDkk0+2MMZaZmrNNVryOZM8mMxXme1ocdT4sFjmii1Iy7KAEAKZTAbS6fQ0roBIbQ5W1N8OAB0XUwYol0DEkQEAFAqFfbZtjyKEuhRFYRhjpOs6nD17FkZGRuD6668Pe/NxiqxRGu48c+CkIU3TwscQOQcX4wiCNxS1tbUxxtj7KaUbGWPbEEI/2759O8y3iENyzpGhY6qqdiKEOoNAgOQloVGrv6P2B4qMQO4oZCzqfGjBsgMRW95RDqVUKoGiKFAoFEDXdZAFTQJeDLZtm+Xz+Q2nT5/eAADDO3fuxADgL5kMoLe3t5rJZBzDMCCVSkE2mwVN06C1tRU0TYN9+/bBrl27wLbt0IgDrwe6rocZgfgi8jKAcwTkCUOBwDMnewE4Jxtj/BIA+I7neX80OTnZFIxDJ9nAApydO3ei4L3PGYaR4/hPlJHLTEAZGBQzgzgsIU5STIz0Yo+fG3xUCcDvxx0CYwzK5TLk83koFArn8AXEAOZ5HgMAA2N8HQDA/v372VIpARgAQFtb2whj7KRhGKBpGjMMAzKZDKiqCrlcDnRdhzNnzsBDDz0EBw4cAM/zQNf1MF3iZQEvFeRUSSSD8LkCsSy4WEahUBagYCdCgRDy0Xw+/z3TNF+OEKLzKeSQnOnn9OnTAADhqvCZlH9nIxraKJrz+8QtlZWkvqcFK7GE5deu+Hc7OjqmOQdu+FEDTpqm3QDwiwWqi94BCGvEpizLOsuZUIZhQKFQgJaWFshkMlAoFKCzszPEBn72s5/B2bNnIZVKhRkB7xSIOIHoJWW9Ac6tlod8LjYjCF5HBgAUY3ybqqr/7jjOVsZYimcDiYnOz+GRD2NcYIwpsoJT1BhwnMZ/nHKQHN2jaL4zAYJRU3/yjECpVAJCCCxfvjzMclVVDR0BF9ERuQ71el27mExTuZQaboVC4YyiKBAoBoXrwQ3DCAeAeB1vWRY8+uijsHr1ali9ejXk8/lwB4AY+cX0LW63G3cS8mBGFB3zPGtRBACUEKITQrb5vn+TaZq/hxA6muAC83uWLVu2EgBStm1DnA5gnPDnbKP+TKO/jX4m348HK+4IDMOAkydPwooVK6Cvr2+atBhCCBzHmVYq8I+O4zQNDQ2lAKC+ZBwAlztuamp6wnVd0DQNeZ7HKKWIUgqpVOqcNcq8A8CXgqxcuRL6+vpCRyAavUwnFlNAUdFHrKswxuGbcpGOIMwGCCGvoZReV6lU3oUQ+iFv2cyXusuVfDKZTIeqqrharUYi4iL6Pxt1nvNdLhvV3weI3iLFMwfRkCuVCvi+H86i1Ov1aWrE4nUq7sH0fb9LUZT8knIAvBOAEBoEgGIqlWqTKb9cdMMwjJDkgzEGTdPANE04fPgwnDlzBlauXAmrVq2CQqHAPeK06S5xU5As8SWmUqIw4xw4AgQABAB8VVX7CCHfNE3zfyCEvhhssUGJE5jbY5qmcT4dnjj2nqwRIP4sSv03bpV4FB4gGj8PQhzkHh8fh97eXujv7w83ZgmAX2TWEjiYtKqq2lIrAfiLcJQxdlJRlDZKKdM0DSmKEvL75Tq/Xq9DrVYDRVEglUqBZVlw8OBBOHXqFKxevRqWLVsG2WwWVFWd9qKJjkDuAYttH/6miJ6X//0LdASEUkoxxnlVVf+mXq93AsBHg822iROYg7N9+3a6efNmUiwWr02n0xDVE2+0Lkz8eRQWJI8Az2alnFjX8ywgCgDk9Xy5XIZ6vQ633XYbpNNp8DwvxLniHIBwqGEYbEk5AAGxHD9w4MDzhULhZo7eyuoo3BHw7yuKEs4BcEOv1+uwZ88eOH78OPT29kJvby+k0+lpb6y82VdGiMVWIscJRBBRXDRynhRVDACMEEJSqdT2er2uM8b+WNilmDgBuLglNF1dXQrGeCU3FjnNb7QFeqY0P26YqNGSz7hJv7jHLJVKsHr1amhtbZ2W/cpOSeQ28IBFKa35vu8sOSbgzp07MUKI2rZ9JtA/C1Mkjn7quh6CgvxzzhnI5XIhWyqXy0E2m4V6vQ779u2Dn/70p7B//36YmpoKuQPy7LWo+SeWAFGpndhK5CXGhZBVAIBqmvZH5XL5ozKTLTkXft7+9rcb6XRakTkAM5UAomCo2Pc/H5JP1ONGkX3iWITj4+PQ0dEB1113XVjyqqraEJMQh9UIIcN79+4tL6kMQGIEPuZ5nqtpmkopDTcIBYMPYSTmtGCuB8DTc75hiH/N23v79++HgYEB6O7uhp6eHmhtbQ0nqsT2i9g1iBIi4U5JbMFwFPc8hUpRkGmwdDr9B7Vazcxms38aEIYgyQTgglmAmUxmI0JoWeCc+esc2aaT0+m41mAUlz+KCdgoI4zbGMQn/UzTBE3TYOPGjaBp2rTMM2oyUVxTxndsMsYqt99+u7XkHADHAWzbfk5V1QFCyDrRwKJeOJFUwaf+xBFi7iA4sOL7Phw8eBCef/55WLZsGWzYsAGam5un1VciGMhLhajZcbEM4W/A+VKLMcY8E2Ce5/1xrVabRAh95mIHOuAKZwFOTEy05HK5jDgFKht7VPuv0QrxmbY/zwT4ideI7FBUVYVqtQoAALfffjvkcrnwvnL7UKD/TgtAAC9s2jYMw4Glpgcg6rjVarUziqLsDVIaJhMsRDCOs6l0XQ/Tfl4GZLPZ8GM+n4d8Pg/ZbBY6Ojogn8/DyMgI/OQnP4Gf/OQncPz4cTBNcxo5I+qNlCfGOLOQE4guUIwEAQAzDEPBGG8bGxt7KUKIzrXe+5V0bNvWNU3Ds9kK3MgZyGq98uNF1fNx68CjaMTcoCcmJoAxBi960YugpaXlHHFQeeRdVsWWsIC9XH7/QrJI5VKquDDGCELIPXr06BPpdPoNfFloI9SW9/x5VOYZAAdPeAYgindqmgaGYUCtVoOxsTE4e/YsNDc3Q19fH/T09EA+nw/LidnUjdwjc6yCbzc+j4wAU0qpYRgtjLG/rtVqr8xkMqcTshCcr84kDa6l61zXVWu1GvM8D/FIOtNC0EZ7/OQOQaNyT+SURKkQidG8UqlAOp2GW2+9FXK5XHgdy39fnmURR4oDO0AAQF3XPQDwC27NknEA4lwAY+zn9Xp9slAoNHMcIE7XnXtnHpHlTIEQAqqqThPx5Btjg1VlYFkWlMtl2L17Nxw6dAi6urpg5cqV0N3dHU4SihdA1JvP1Vl4z1ZsV87GCSCEsOd51DCMa4vF4p8zxh5IOgPnXf8DAICu621Bt4ZxDCAK/Y/r/zdyElG9/Jk0/zg2IHacfN+HiYkJ6O7uhhtuuAGy2ey07lNUoOG0dR79BSdAU6kUdl33cHt7+/Ncb3PJOoBUKnXYcZzDAPCiKGZWo9HKYCAirIk4eMgRf03TwixAVVWwbRswxqDrOjiOA/V6HY4cOQInT56E7u5uWLFiBSxbtiwcPGrUPxbbTqLizGydQLAOmhqG8ebR0dH/6Ozs/GZQCiQOYBZoe5D6pm3bvjZYqhmunBe19GZDCBLJYaI4rXwdyjz+Ro/LDdZ1XRgeHoarrroKbrnlFnnBbCRIyMFuuVwRN1Pbtr23ubn5LCzW1WCz9eQrVqwYP3jw4DOe571IURTm+z6KetGjKJXiui6eOvFUjIMmIpWSR2nuLFRVhVQqBbVaDQ4cOADHjx+HZcuWwbJly6Cnpwey2ew5Gm5ydiBuNZJxixkQYkQpZYZhaLZtf7Rer+9Kp9Mnkyxg9sdxnIxt2/1BmowuZE7/Yrf8RvX5+TXBiWsvfvGLobe3d8bH46l/vV6ftoVKnD5kjCHXdRHG+GGEkHMx14tyqdVcAxzA9zzvp6ZpvjuVSiGEEONvpmz8skCI+EIahhHW6FxfTZQOlzkGvDxwHAc0TYNMJgO1Wg1Onz4NQ0NDcOzYMejv74fe3t5wKiuOIioObfDnIrLAGlxU2PM8mslk1rmu+5sA8JHErGcPpr7nPe9ZPz4+nq3VatNabI00+eKyurhyIKpGb4QR8TKyUqnAypUrYf369ZDP52f8h7giMI/84k14jkzTNEQpHclkMj8Wh+suqo661GyuiYmJXtu2v18oFDZ4nkcBAMfxr+NqPJ4BcIIHvyD4ODBvC4ltFREn4PfhbwIHYAqFAqxduxZWrVoFhmFM0xKIqv94icH13ERRiKg33fM8yhhDjuMMFwqF/4YQej4BBBufHTt2kC1btvi7d+/+VV3XvzI8PIyC9fMoSsYtarSXG6u4E2A2iz/EMkFeAso7Q9lsFtauXQsrVqyYNYWYq1uLW6lk3oKiKDSXy+FarfadjRs3vhEhZC7ZDEDUdG9paRk8ceLEE5TSDY1AF1HZNQorkHcLcMYfISRk8vGSgJcIYmkgdg34WHK5XIZHH30UBgYG4JZbboF8Pt9wASRP4zgewGmdUSVB8ObioBTonpiY2AIA2xIcAGZcMgMAUCqVepuampDv+xxAjRXllFF+0Sk34p9AjNCn+Pue5wHPQtavXw9r164NVa1nY/zc4HkQ4uCfiP5z8dOA//I9hJAZtP/oRSOpi8Gbnzhx4q2qqv5jLpcTiTPTjFuWdo5Cc+WNQfy+Yg+ff59HfnFQiGcHfA0YH0Kq1WpACIH169dDX18fpFKp8E2WxSI4CCl2CPg8QUQGAJRSqmkampqa2pdKpf57Nps9m2ABjbNGxhjZvXv3NwDgDSMjI5QQguOwo0bfg5iBoSgmodwV4BmkruuwbNkyWLduHWQymVkbPgcJ+X4LMQvlGIBwTTFVVYFSenTVqlX3ZTKZMxd7jSiLyZubpvmQ7/v78/n8NUEZgOKWJjbq3Yodgmn/rEAvFgUfOWjDX3w+/SfeOG5QrVZh7969cOLECdi4cSP09vZOy0LEaUKeWvKbnD5KtE7sui7DGF9rmub9APC3ialDQ0GZ7373u+2ZTOa64L1EIutORNnjDF1E6uMyAPE+vMNAKQ2jNZeKX7169TmGPxvjF0vOqOgvYl9Bmxj7vv/tTCZzJrAPttS7AOII59mjR48+SCm9BmOMRAOV6ZEzOQMRLJS/z1M3/oZy3gAhJMwQREPlNGNe19dqNSiXy/DMM8+A4ziwdu3aSK623CXg35PlzflHx3FYKpWCarX64q1bt/49QshLsoBoGvn27dtB1/VVlNJeUQOiEZgXNQIcxeCLovXyLg/PFnO5HGzYsAF6e3unGf75lBGctFav16dlndwRSM+BapqGPc8rptPpr4uZ0JyQKRZBWocRQnRgYOCViqJ8u1AoKL7vTyvqohhaUW9s3KIHWdVVpvny0oG/ASLZh/8ur9Vs24ZKpQKu68KyZcvg2muvDet9GRAUl5yIQqYiZhA8Ls1kMti27YF0Ov3SVCo1kDiA+Gvl6aef/oDneZ8aGRmZNuQFDdh6YlARU2yePfDPRfINlxnLZDKwbNkyaG5uhu7u7mk1/vniB2LNb1lWCEzzJaAyxoUxZplMBmGMP9rf3/+RQPr8oq+LxbTYkgEAWJb1M03THmWM3SNOB8alZ1HTXI3oxKJhxmUYuq5Powbzi8X3/XAKkNf39Xodzp49C6ZpwrXXXguFQmFa6snpymImwFtVclmDEELBSvK+8fHxWwFgQBglTs60t56hXbt2bdQ0DTzPYwGnIlaaS8zAosBlzgvBGIe1OGMMMpkMtLW1wfr166G9vX0ahnO+hs9LQtM0w+jPjV8sQeVNQkL0P9rT0/MFxthFtf4WpQPgEtoIocpzzz33r7qu36NpGpJHd+eC3BF1IfCygNOAxXXlXIdNXDjCV4VxbGBqagp2794NN910U6jpzt9wecsrzwjkiMXXPimKgj3Pu50xtiNpBUYDgF/5ylda161bd3NA82YAgOLo23J7TxaH4S3jSqUCXJMym83CunXroLe3F/jKsbgtQTD79WXTjJ9vAWaMTcs0xe3GQYcKeZ7HVFX9VDAzgubqulAWqcDjtyqVyvvb2trW8N6OmLKL9X0UJjDbnW4yYCOCeCJoJ6b1svYA7yWnUik4c+YMPPbYY3DPPfdAIE81zQnInAGucyBNqDGEENi2vWF0dDQDANWkDIBpQjIA4DuOc9XU1NTVwXWBZK3+qPKQZwGcaAMAUK1WQVEU8DwPVq1aBX19fdDW1jZnRi92pji3P8745YwiuM6oYRi4Vqv9aP369V+Z67JdWWR73mlwsQ+eOnXq+4SQ94mGL76RUZ2Bi10EGpUdiJNlPILwdh4vEzh+sGrVKti9ezf89Kc/hTvuuANyuVz4O1GbaXmtKaoaBygvmKZ5ned5XQBwNDF7OGcPwPXXX3+HbdtGsVhkMh9EDhb88Jqb369QKMDGjRuhra0N2traQjDvYlL8qKjPl9ZykpBt26HD50GEOy3+/aDzRDVNw7ZtD6fT6T9ACFUvtu+/FDIABABM07RvVCqVtxYKhWbf95nYEoxTapHJObNpG4qz22KnQJzUkok+3KOLJCNeEvT09MChQ4dg+fLlsHr16nDTsWjksuYAdwQiUEkIMTRN0xOTPyf9p4wxY9euXS/JZDJw5swZRgjBIu2aO2tubIQQME0TUqkU9Pf3Q1NTE7S2tkJzc/M5vIyLjfby9clBPh7l+dfiVmtRdEbYJsQwxty5/cWaNWt2b926FW/fvp1ethmAyAz83Oc+9+hb3vKW/2xubn4r7wbMNJk3x8/jnL49j+LisBHPEHRdB8/zYO3atTA8PAwnTpyA9vb2aa1HfrFxlqAMDnHvH3ARjHw+3wUA+xMgcHpw+Na3vnVVU1PTzcFrj3g5xdNq/lqmUino6uqC9vb20OjF1F4sC86XCdgo3Re1KMTtUxz951Ff/FuiJqamaYAQYqlUipim+XdXXXXV54M2Odu+fTtc1g6Akx0QQvSd73znN0ul0uZUKqWyFw660KGO2fSHG3UNZGCJjyCLToBSCoVCAa666irYv38/nD59Gvr6+qaNFvOaX+zzyn+XUgq6ruuKonQmNg+iAAhijKHPfOYz1wFAOyGE8aEb13UhnU5Da2srLF++HPL5PLS0tEBzc3NDHf+L3RYtPi7nCIjr6XlbT9T5iysvOMakqqpPCCG1Wu3BdDr9+xc78bfkQED+j/b09Pzg2LFjP0mn0y97wS4oavRmNmoLXmw2IPaRxb0BPHXnZKF6vQ6rVq2CI0eOwJkzZ6C9vT0UfIRfCFiEdV8UISj4PrJt20jMHmDr1q2YK94ghNi//du/3Vav16FUKrHOzk68fPlyaG1thd7eXmhqamqYIV5shI+K9vwa47W9OGwmUs0blaV8IQ0A+IqikHq9vldRlN9YtWrV1FzX/YveAQhZgHn06NEv1Gq1e1OplBKkwQ1Lgdm2C2erG9+Ig8B7/KIQiGVZ0NTUBJ2dnTA8PAzj4+PhYBHnA3C6MecFiF0NfqE4juNrmla9kuv9nTt34s2bNwNCKOyl7tmzZ73jOK9wHAdaW1tRf39/bB0/1wYfVd+LLETbtsPsjovWiupSYr0vCs0K2649RVGUSqVysqOj4ze6u7sH5nsqVFnsZI8jR458t16vP5jJZP47feGguAULs+UI8EgetSE2jhsehwiL6T9XJ6KUwtq1a2F0dBSKxSJkMhlobW0Na01RtERWIuatwVqtVtc07STALxSUrwSj57sVg4veBwAol8vtjLFbCSH367r+MgBYFRg9iqrl58voxfFy3/enkXhERJ/PCjQKLOJeiuBz3zAMxXGcU6lU6u3d3d1PLsRI+KJ1AJwYtG7dOvvo0aNfnJycvDebzWqiZmAUih83yBGnAS93DOIyiCj2mOgEOMrPJ8S6u7shk8lAuVyGarUK6XQ6khAk05L583Fd1y+VSiWuoDzX4M9iM/pt27ZNM/pKpdKBMb4dAF5HCLmLMbaGi6xEOeS5quXjRD5A4O+LWhLcGfBygJcAfNlNVGAJNmJzZ8UwxtQwDFKv1/fmcrnfWCjjX+wZQDgktHv37v9oamr6nu/7r2OM0aiOgAjSNVKDmamFKBOBZCBRbBNG0YvFunDFihXw/PPPh8wvzh3gGYD4nIXnwR3cKcMwSpex0fOaPjR6xljr6Ojofbqu348xvgMhtEZC7f3g9/B8Rnl5XyCv4XnaLy+yFbNIzuaTJxHFmRA+Gk4ppYQQVCgUyMjIyPcQQu/t7u4+sZBiMMpiv1YAAG/atMk9ceLEZ0zT/G+ZTCbDlV/k1DluViBqT/zFthCjSgOR9FOr1WDlypXw/PPPh/RPXdfDqUM56suOJp/P71+5cuXYZWj0KKjpuSJ0bmxs7B5FUV5XrVbvzmQy66XpOm70fOPyvBk8vzbETTwc0BO/L2g4xGaZYqovitRwvIIx5mcyGeI4jl8ul/86lUp9dNWqVVMLrQSlLJXBDwB46MCBA/+WTqd/NSAGTRv7lR1AnHFHLYWYDb8gTh9epiVzcNDzPGhqaoKenh4ol8vTuN6cRCSOCUdstNmDEPLmEwFe4Lqe8v+DMaadPHnymtbW1te5rvvqdDp9QyaTQYJz9gNHgefT6OVdD/w6EqXjRC0HcWpU1uyTGaTy3klh8w+llKJcLkcmJyeHGWNbN2zY8LfilONCvj+LfhsNQoht27YNIYRYU1PTZ6ampkYCOW0WtTgxTv9NRF8vNOLPRhlW7i1v2LAhVBXi6SOPKmJkCZ4fC/YF1Aghjy1lAJAxhnbs2EGCksZHCLGpqanVo6OjH5iYmPhRPp//STab/WNVVW9Mp9MoMHoWvHZkPq5NcSGoyMozTXOaDqT4NZ/YE7+Wo78YgPhwGL8ZhsEl6RnG2Nd1Heu6jkzT/Laqqi/fsGHD3zLG0FwO+FxuGQBs376dbt26FS9btmzXnj17PmtZ1p+pqgpcB06u0eMWP0Z1AOL2wl2slDTGGGzbhra2NmhtbQ0vID5qLEYPIYtgwe6Cp3p6ep4Wx6SXWOuOBlwOv1gs5nVd/yVK6Wbbtu9MpVJdXBeBUupjjPkWGDKftbwIzvH3WNSGEDMA8Xe4s4gLBKIClCg/zz9ijBlCiCKECEKIVCqV45qmfbxYLH5l06ZN7qUWf1Vg6ajAsG3btqEDBw583nXd16bT6U2O49BAGOGiDXamPfFwYZr1kM1mYc2aNbBv374ZeQW8TqaU/gQhVIkTuVyshh/U9hzQ6xsZGXm967pvMwzjxnw+H2ofBoYyL0Yvq/6KBi6n+vJNnNUQf7+RyIic4gtj3hQhxAghJJ1Ok1KpNOW67j97nvfJNWvWDFyqlH/JOgDeFrz66qvH9+/f/4lqtfplXdd1EXE9HxJQIwxALiOilj3O5vH5Yohly5bBwMDAOTMA0g54hhCCqampYjqd/neB+06XiuEzxvDExMRtnuf9erFYfGUmk1nOo6DneRRjjBVFwfNh8KIkW5T6k+wAopyAjOVEDQZFzYjwOY8gG2CKooQDSvV6vVStVr+lquqnV65c+Qw3fIHrAIkDOI/3e+vWrfjqq6/euWfPnl9KpVK/Hmjq46h1TXFrxeI+j8IPRICn0U75uMeq1+uQy+Vg2bJlMDw8PE0bQHQUlFKm6zpGCH19zZo1u+dC8HEBDT81NDT0ioGBgXdlMpmXNDc3a0HaTIOIiAkhZK6ymajILSL44uciB19M8UVAuJG4rIjriOu75RXgws8RpRQ5jjNaq9X+M5VKfXbVqlW7BUAUFhOou6QcQJAFAEKIHTt27OO1Wu3udDrdz5dCNtojeDHp/fmWB+L9Pc+DSqUCq1atCnfCi6IVAeLMAAB5njeRz+e/CgCwdetWNNejn3OpxxcYvj4wMPCmgYGBd6mqekdLSwuXvPI1TcOapuGLJejImo5RqL1o9CIoJ2YA8tRfo+lPkVgkjOdGKgoJehHM8zwolUoWAPyvXC731f7+/gGxBboYuznKkpsHDXah9/f3H37mmWf+GmP8GVVVWcDCQ5KMcqQjaCQaGtUilLOKRpmA/DnGGKrVKuRyOejq6oKA3DdNa5BSylKpFKaUfqmvr++pS4UIz2T4PG1ljClnzpx55fHjxz+UzWbvCoZYGCGEKYqCVFUlXDvxQqN71HsjG7i40WemjpBovFHRXpSNj5JtF1e88ZQfIQSmaUKpVILh4WFar9eJ4zj/fP/9928HeGHfxebNm3mqvyizuSXnADggCAC4q6vry6Ojo/cQQrbw/qrIt5/tvECj6D7TGPFMm2E5PbharYYOgNOAg/tSTdMwAOzv6+v77HzpG1xMuh+0YSkAwKlTp37p+PHjf6Dr+j1NTU18WQXTNA2pqnreDL2oNm2UQxYls8SNOWIaH1Wzi4YbJfstC3DKab5I3xUXzIyPj0OpVIKJiQm+2o1Uq9X911xzzZ9z7oM4xLRYz5J0AEEWgLq7u2tnzpz50Pj4+NWGYVwT0ITxbGv9OCXhRtnATB+j1jkH4B5ks1nI5XLiEAlVFAXX6/WJrq6u92YymdOLifgjpPtsaGhok6qqv1er1X6lUCgoQVpMEUJYVVXUaBPyTE5SrsnliB+l7isTb+QlreKglpwRijRd/rw5PZtLfYvZgeM4MDo6ChMTE1CpVEJuQND3Z+l0Gvm+b61cuXLbxo0bTwbKPf5SUVgBWOL68AcPHtzs+/5XCSG6uFJMputGjWXGpY2NaJ7n6wDgF/ReMAwDBgYGIJ/Ps2w2C77vg6Zp77v++us/Nx+STxdp+DAyMtJVKpX+kBDy6/l8Pu95Hui6TnVdxyK9Na6+FvUTxNclDoyTwTo5QsuvcVS5FjXJKc5xxEm9AbygCs2JP/V6HSYnJ6FUKkG9Xg9l4XkJEGhAUMMwMGNs67333vuni+U9vCIcgFhnHTp06K8A4AO+74c74mZK56McgHyRRe0YnGkXQRwWQCmFZcuWQaVSgfHxcdbU1ITS6fSnr7322t/dtm0bBBNxbLEY/5kzZ15rWdbHDcPYEKTBlBCCgnQ/NBruAKLaaHFZV9QItozSi10Y0ZjF9yTO2XDnBNLEJjd2Ls3F9/JVKhWoVCpgmiZUq1WwLCsUf+UyXXyhC1d48jzPV1WV+L7/43vvvfe1CKE6B6mXiv0ocBlsiUUIsVKp9GeDg4PX6Lr+UsdxKH7hxC6DnInxdz617Gw6BDydnZiYYM3NzTA1NUVt2/7bF73oRX8kqCGzS8zZB4QQHRkZWWNZ1l+apvnadDqNMcYUIYRUVcXikhNxtba4TSfudZYje1RmJhs8d5xRSL/chhOBPi7bzsd2uRQ3V+ctlUowOTkZGjr/OxhjMAwDmpqawk1O4o5I7gwYY9T3fWKa5kB3d/cHEUK1pTi3seQdAO8KFAqF8YMHD/6m67rf1XV9g+M4oZBolDHPBhyUiDrn1bKKyhIwxlCpVMAwDJTL5eqKonwtiBqX9MIJOPs+AMDJkyffPT4+/if5fH5Z8NwpIQQrisIv/Mg1bXGdlZlKrLjHk5eryu8BB/f4iC7f0stT+Hq9DuVyGUqlUrjVmT8edxaapkEmk5m2rk1m9InTfAKmwAzDwK7rWoqifOjqq6/etxhYfVdkCSCnro888sirCoXCP2uaVhDVhKOot1HIs2zwnD8eNbsvA1ayzDNEUEeDFVS0v78fF4vF7/X19b2ptbW1ImohwgLr7W3fvp0yxjqPHj36Mc/zHkin04gDlNwwAqVaiCJcReErcaBeAxCWMcaY7/tYrM1FsY1yuRyyKR3HgWKxCJVK5RxFZa7RKC5yEdN5cdsU12gQqb088ovju8L/zBRFYcFW3z+68847/9e//Mu/kC1btvhL0W6Uy8UBIITojh07yJ133vndQ4cO/bnv+58QxoZRVB94Nul8FLh1Ia06cTOw7/u4UqnQQqHwS4ODgw+0tbV9euvWrXghe8UiOeXEiRMvOXLkyF+pqno9j/qGYYQllIjwy7V1o5aePE4rlQAMAGjwehNCCCKEIK6txyf1xsfHYWJiItRUsCwrdMY8OmuaFkbobDY7bZOT+D+I1F2R3CPeX3RyXMdR2hBFCSFkYmLiK5ZlfZJSipaq8V9WGYAkOqEePnz4rxRFeW+9XqcIISy2hESgT45Kcu0q72mXgSyJzjvt96IIKEI7i65YsQLX6/VBxthrbrrppj0LhSCLf+fAgQPv1jTt4xjjZsdxfF3XsWEYSDQg3hrjhhL1WnJwTjZ88fVjjFFKKaOUIkII5jp6gX7CSQA4tHfv3psrlUqraZrM933EN/nwPYwchOMgpGjAUavXI6bzpmUH4jIOMdLz/5uLtwYlnA8AZGJi4mFFUd54ww03jC411P+ydgDi8shisZg/ffr0/9V1fbPv+zQQl5jG8hJT97jUNGqll9y/Ph8HIJYaiqLQnp4eXK/Xv7tx48bNAGDNdynASyXGWG5gYOBj9Xr9Pel0WvF930+lUkRs6cnRkhs+/5/E/5lr44ljt8Hrx1zXpQCAFEUJW4fVanWSUvq0aZo/T6VSP924ceOz3/rWt15x8ODBLxBCsqlUCgJWYSi5zp9bXDovfi0atGj0IotPvK/4kd9PcgBUURQ8MjLyHCHkDddcc83RpW78l1UJIIOCbW1t5bGxsQ+ePn16eSqVusP3fZ9SSs53NiDKOTRaRholUhkFkgXCn7hYLNJsNvuqXbt2/c6tt976sfksBTjYNzExUTh27Nj/JYT8CtdVMAxjmvHLxBnRMPjyC274/PXgQFzwcxpEYGwYBnFdF2q12lmM8XOGYfw7IeShDRs2HEUIuQAATz755Opyuby9r68vxwFc8e9yHQXujLhDiprOi3IGHNiL6hyI7D+5ZOCjvaqq4rGxsTFK6Qevv/76ozt27CBLOfW/bDMAOdKdPn16/fj4+Dd0Xb/edV0fY0wa9fXlr/kGH7l91YhJGMduk+/LR2WDvfMmIeRNGzZs+M58IMr8MYeGhtrHxsb+Lp/P32/bNgUApKoqCiLutNSZ38Q6mG/XFYUyebbjOA6zbZv6vk+4wVYqlbFcLveo7/vfJIQ8snLlyhNihvPFL35Rfd3rXqf/+Mc//lo2m73fcRz6gu3jac6UZwA8NZeHc6IclVi7c+OX5/dFoE92fMH7TjHGeGJiYgIAfnX9+vX/eTlE/ss2A5BBwRUrVhwaGBh488TExM5cLrfRdV2fUkpmIwUu1+5ilyBurZdMgokqF6RMAo2OjtJly5aly+Xyp48cOXIcIbR/Lp0Af6xarbbi5MmTX02lUvc5juMHKjXhcxbpsGIPnJc0XMaMp/tcGx8AGKWU+r5PDMMgpVIJGGO7UqnUvzQ3N393xYoVh+RMBH6x7svt7OzcVigU7qeUUk3TUFQ05w5AdEhihI9K58X7iNmNjGXEjfkGzwdPTk7WKKXv37Bhw38u1XbfFZcBCBc/QQj5p06dur5YLH5TVdU1jDFfVqOJi+J8mEes7xtRiWVMIIquKi4D4WPBmqbR7u5uXKvVftLS0vLG/v7+kbm42Dgm8vzzz3cjhP7JMIyX1Go1X1EUwiMgr3U52GYYxrSFJ+KWW9d1RYfAfN+nAEA0TYNqtVqmlP6rqqr/0tXV9URLS0tJkgpjvLzZsmUL3rlzp//973//fW1tbZ9wXVcvl8vAdz7Iaju6rp8TsRvV8PL3ZCag6ADkMV8+pMUYw47j1KvV6gdXr179peD9YJfTolblcncACCF/x44dpKenZ8+hQ4feWqlUvpbNZvtt2w4j4GwlwONmx8+3NSi3FoOxUjwyMuIvX778xRMTEx9jjL0bIeRdJEMQBUh/zrKsz+u6/pJ6ve5jjInogHhNzemufGcBZ9LxWp+353gLDwCIruukWq2OY4y/nU6nv9Df379LjPT79++ftvCDf3/nzp3+D37wg/tbWlo+riiKMTo6ygzDQHJUj2rZiV0JMXWPKwFEEDAOKJQ6NIwQgkulkmXb9u+vXr36S0tdnfmKzQDkNHhgYODG8fHxf0qn01c7jkN5O6pRF0De4BPHZ4+bYY/a/it3Bfj9stms39bWRizL+tSmTZs+xKXBL6Tm5M7jmWee+RRC6AMYY0oIwWJ01TQNUqkUaJoWbqsBeGHrMV+3LX7tui6fAIRarVbN5XL/mEqlPtfd3b2PtxgDJePIuQYOnu3atete27a/lsvlusfHx6miKFjARc4h73BDlR2AbPhR0V3OAMT7R5DEKKUUl8tlzzTN3+nr6/ts8D+xpcTxTzKAGExg1apVz+zbt2+zaZpfy+Vy11uW5SOESNSmYTFKiDsIzifiR2EFshyYSH8tl8tYURTa2tr6wWeeeYYyxv4AIeSerxPgEeu55557t+/7/1/QCkXyZJyu61y2elrKz3nzIsDnOA5VVZV4nsd83/96d3f3Jzs6Op4WDR8hROPWmHHj37dv312O4/xdV1dX99jYGE2n09h13ZDQI0b8OHRfju5RNXxcOSB+X3IAlBCCR0dHLcuyfr+vr+9vAm7JZWn8V1QGIF+EpVJp7dGjR/8pk8nc6rou9X2fy1NHEoKi+OtR6jVyxJd3EUThAqLARTBUw/L5PFu+fDl2XfcvN2zY8OGgHJhVGsrvt3///ntKpdK3dV1vCiTHETcgbviZTAYMw5gmtSU6gOD5U67T73ne3kwm8+f9/f07RCXjRs+Li4ps376d7tu37y6M8d/n8/m1Y2Nj1HEcLE4Wii27qAUbYgYQZdDSEo5Iw48q6RhjFGOMJycnq7Va7UMrV678gjAgxS7bwAhwRa6exgghWiwWV5w6depvVFV9je/7LJgGQ7MRCo0ybpk1GBXl5cEWeQ6BZx+e57GmpibW3d2NTdP81OTk5B/ed9991kxOgEuJj4yMdJ48efLbGONbAyluLFJnU6lUuLhCXJjB23qWZYFlWeB5Hg3ESmuKonxmzZo1n0QIFYM17TNKl4np809+8pM3tLS0fL61tbW9WCxOE3OFmLFdGRPg3YlG4pwi0i/P/kdlZIQQHwDIyMjIuOM4v9Hb2/utyw3th6W6GWi+yoGALHS6q6vrLZZlfRFjjBRFQZRSGteyi+sVz7YMiEtRoy5MXddRpVLBZ86cYel0+oOFQuEbjz/++Cr+3Gdw6uz48eO/ixC61XVdSinFIveAp/yc1MPre36r1+tg2zajlLJMJoN933/SMIxXr1279g8RQsXZylqLZcvu3bvf19HR8ZWmpqb2crlM+YJPHtV5i0+k7sp1u6jkM1MJJms8NAB2KQCQoaGhgWq1uiUwfnQlGP8VmwFE0GLJs88++35K6Z/qup7jegJxab0ICsrRnEf4qM00IqFIziTkUVieCTiOA/l8nq5YsQKXy+Xnfd//ndtuu+2/ZAMTQb/nnnvuZbVa7Zu+7+cYY8AluwghYBgGpNPpaZGVp/x80s73fRYMLSGM8ZeuvvrqP0IIFWcLhollwZNPPtmjKMrH2tra3gIAuFKpUEVRMBdEFQVFoiJ+FMgntgHlMkEG/+KcNaWUYYwpY4wMDAz83Pf9d69bt+75KyXyX9EZgJgJBBcrvfHGGz+FMX47Y+ysrus46AOzqN1/cto6mwgfNRMQ1RaULlJQFAVqtRo+fPiw7zjO1YZh7Hj88cffxxhTtm/fTnfs2EG2bt2KeerPGNMqlcrv+r6fZ9wjSGKZPN3nQhm2bYf0XsuyKKUUeZ7HFEX542uuueZdCKHijh07yPbt22kj45f2AdIf/vCHdxFCvrN69eq3McaQbdtMVVUs4hCcMShmADzN59+Lo/Xy+4q/KzL/oqb8+EsbDCCR06dPf+fMmTOvX7du3fPBc6dXlA1AckKiypYtW/znn3/+GsuyPqVp2ktd1w0JIVEjwSINtpHMFY/qUXRiMQuI0hvgPw8uWJrNZnFXVxcQQv6rVCp9+EUvetFTAABPPfWUumnTJnfXrl3vNk3zs5ztSAhBYtrPCTXicxN0+ChCCDuOM5XJZD64fv36rwS1Psxk+Pz1AwD49re/3dnX1/c/MpnMe7LZbLpWq1Hf91GwDizSKcrgnUw/jhrsifp9cUNzTHnmAwCZnJykpVLpo319fX+OEHKutMifOIDG4hjpp59++o8ZYx/SdZ04jjPNCcgjsLIDEKcBo8aMuUOQV09HZQei0EWQrjNCCOrp6QGMcUlV1b+r1Wr/e9OmTWefeOKJrqGhoZ9ks9l1hBDGGEM8knIHoGnaOQ6MKxQTQrCqqmfz+fw7ent7vz8TCi62/gAAvvrVr2bWrFnz3s7Ozne3tLT0B1p7FCGEozQFolJ40ZCjsqoogDCCwhvlADiDD4+Ojp6pVCofWrNmzdfF0umKzIITs48XxXzuuefe5nnen2uattK27fACkkk8sl5dIyXiqAWWcUNDIGndi7sOEEJ+U1MT6ejoAEVRjmGM/+rgwYPd4+PjH+Gz8wAQUnt5qi3Ozgvbb1lAwa0vX778N5YvX/71QGz1nJSfMYZ37tw5TQTj05/+dP6lL33p/blc7rd1Xb9VVVUolUrUdV2k6zoSAUi5dy+z8cQIH9XqE+8rZgJxbE0B6MO+78PY2NgjiqJ8oL29ffeV0OZLHMCF8+cBANj+/fvXVqvVP1NV9Y1BBPYDJ4HidPDiHMBMewkaCWbG6OozTdNYd3c31jQNpqam3MnJSZVr4iGEIJ1OQy6Xg1QqNa2Hzh/DcRwWtD6t5ubm3167du2XeHuOn507d6LNmzdz0Cz8/rFjx9YRQt6oKMqbDcPYkE6noVgsMtM0maIomC/T4H9LFueIku/mRi33+qMWc8rOQ3YAHOgDAFIuly3Lsv5K1/X/3dTUNBnn4BIHkByQSUOMMbx79+5ftSxre3t7+8p6vR6SY6JIPjKBKEq6upHCUBxhKKqkCHTzqKIoKJvNolQqBQAA5XIZpqamwPf9UEWHj/xKXQoW0IA/csMNN3xs165daqVSYffdd58X9ZoMDQ1tsCzrZel0+lWEkJsNw2illEKlUmHBHD+WW3YgCXnKCH1UGi+j+VFlQZQDEBWX+GLCsbGxJyuVykf6+/t/uFjWcicOYAmWBENDQysHBwf/QNf1d2mahi3L4l0ENJt9gVHRPm7tuFjPxm3UEetnPmGIMYZUKhVq4zmOw/v64DhOCPgFZYCfyWQIAHzpxS9+8bvEv/PQQw8ZuVyugxDS09LScg0AvMiyrGvb29tXaprWzrsHjuPQAL/AYn0e1R0RqbeN2HqyFkCU6IcstioS+bkQycTERM1xnE86jvOplStXTl7OnP7EAczz68TJIRhjOHDgwC9Xq9U/IITcSggBy7Jo8FqimVaRi4YfBxTGSZfPpEMg8vm5UXDGH5/yI4SAbdtQr9fB8zye/j8LACeCDgDLZrO4vb29S1GUbkppq6qqKU4aqtVqYFkWDUBJhDFGjSJ3HOovU3/FxxCdRJziTwTBh2GMGQDgoAR6GCH0Jy0tLT9Lon7iAOZcTJMx1nT48OHfsCzr/aqq9tq2Df4LFo0xxigqcouRX9bBn02632i9NX/MKGPifAJeAvD5f0GLIOwOOI4DmqaFvIBAa98P/h+EMQ7bebJxy4M6cWm77ABmSuejfl947RhCiPF0f2Rk5IjjOH/R09OzEyFUEViLSdRPHMDcymkDABw6dGi153nvqlQq70yn022BgfuBvj2SJ/9ExxAXzaPmDmRjaKQvIFOW5Q1JIhDH+/9c5CLYVQiBofOV60iO1HIJErV3LyriRzkCsTyYCdjjv+f7PsMYUy7xVq1Wx0ul0hcB4AsrVqw4lUT9xAEsqCM4cuTIxlKp9FsY47fkcrlCoJ4TdgyiloWI9OAoRHy2Y8dRI7JRwiXiOHNUL12+j5xJRA3aRMlpy06qUStPdlBRz11yBiGyDwBQqVRqlmV9hVL6ha6urr3CvkiaRP3EASxIWSCSYQYHB28plUq/5TjO6zRNK3AGX1Az46i0PcrQ5Z14M0X7KCrxTOuy5ajciM4s1uViKzEKvItSPBIzBTHSxxl7xHObZvgTExM2Y+z7tm3/7+XLl/+cR/wk3U8cwCVzBAAAHCPYs2fPtb7v/ypC6E2GYfQAANi2DQihaVlB1M6AqO9FZQJxstiNBE3lfYdRzDvZOEUHEoXYRyH98vdlem6coYu3YCiJBtgDBgAoFotV13W/AwBf6O7u/hmXgRedcHISB3BJ24ZiFDpz5kzv8PDwa9Pp9Js9z7vdMAzejqMBgIUv5H2Iq8XjsgLZKEUV4EZTc3EU3agpvUYGLT921HMNniNjL+wKYyRIWVzXhUqlMlCtVv+VMfb1vr6+p6PatMmBRBJsMUwYihnB8uXLBwHgM4yxvzt27NgrarXaAwihOwzDaNE0Der1OgRa+KFDxhgjsVPARTplQxXbfVHpfJyAaVxfXqbkRhm1bNwyZhDVAYh7HtP95gtoPkKIqKqKAABqtZpTr9efqlQq/woA3+zv7x+UVsCxxPiTDGDJTBpyAzhy5Mha13Vf4/v+ZozxRkJIlm8O5ug235LL0fioyC5iCFEGLkfXqPtwAJI7GVGII+5vyK2/KP3EmVSQufEGnRLM25CmadJ6vX6kVqv9KJfLfeP48eOPb9q0yRWyqyTVTxzA0ncE3BAOHz58k23b97qu+xqM8Q2pVKqQSqXCHjxjjKPZYVsxbvBFNNa4AZkoRyCCc6K0ViOgMapsiOs+8Jcg2KwLAED4YJLjOGDbtlsul085jvP9lpaW71BKH+M7BfhuBwBIUP3EAVwejmDbtm1o48aN56yVPn78+HrTNG9FCL3McZwXZzKZZZlMRuHKQFygM0iVQ4ZiYHhI1A6IchRR6XrcTH2U04gqFSKMnQWZAR8cQnwcWNd1CFJ7qNfrUwihp2zb/oGmabtGR0d3X3PNNVXJ6FmC6icO4LLnEggjqeGF/o//+I/5W2+99fpcLneP7/svqlarN3qe153NZkk6nQ7HgwPREhaImoZjjIGxIsFYp5UScWBfnHCmUEqwwFkwwXGwAMDDhBAkqvVQSqFUKoHjOCVN0/abpvksY+xnpVLpsY0bNw6K/7MwhZgYfeIA4IpsJQaZAZXXTz322GOdmUymp6mp6QbLsm7BGF/HGFvhOM5ywzBQLpeDQMcvVCcOVnSzQIyDcWWfuCm8KE1CYVkHeiH5eAGX4FRibux8b2BAiZ5ijJ20bftkOp1+QtO03QMDA4eeffbZ4QceeMCK6JokRp84gOQ0yA5oVLvx6NGjy48dO9bd0dHR2tbWdrPv+52O41xDCOlVFEWllLYghDJcCYgbLOf/i3r84ihzlOCJ7/tg2zafPPQYY0XP80zG2ISqqrsVRRk3TXPfqVOnThiGMXnTTTedRAjV44hTgcHD5bRnL3EAyZlPZwAAgHbu3In279/P4rYEBbWzXi6XU0NDQ321Wq0bANRsNttSKBRWEkLaHcfJIISQqqosiMCq53kKIYQCgAcALkIIEUJA0zS3VqtN1uv105ZlnZmamnLS6fRUNps9tmbNmnEA8BBCzkxOLInyyUnOHDuFrVu34h07dpAdO3YQxhiWlXwWsnThf194LkhwXMlJTnIW0jkEN26QRJQPj7pF/G54Eww8fKyo301OcpKTnOQkJznJSU5ykpOc5CQnOclJTnKSk5zkJCc5yUlOcpKTnOQkJznJSU5ykpOc5CQnOclJTnKSk5zkJCc5yUlOcpKTnOQkJznJSU5ykpOc5CQnOclJTnKSk5zkJCc5yUlOcpKTnOQkJznJSc7szv8PwUr1/caIJhAAAAAASUVORK5CYII="

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

local SIDEBAR_WIDTH = 92
local HEADER_HEIGHT = 66
local TAB_TILE_HEIGHT = 52
local CARD_HEIGHT = TOUCH and 54 or 48
local CARD_HEIGHT_DESC = TOUCH and 70 or 64
local DROPDOWN_OPTION_HEIGHT = TOUCH and 40 or 34
local CHIP_HEIGHT = TOUCH and 34 or 28
local PROFILE_HEIGHT = 96
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

local function corner(parent, radius)
    return create("UICorner", {
        CornerRadius = radius or UDim.new(0, 8),
        Parent = parent,
    })
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
        ImageTransparency = transparency,
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
        BackgroundTransparency = 0.93,
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
            TextSize = 11,
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
    local text_ = label({
        Size = UDim2.new(1, 0, 0, 18),
        Text = opts.Text or "",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = opts.Color or Theme.Muted,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    if metricsOf(self).Compact then
        text_.TextSize = 12
        padding(text_, 14, 14)
    else
        padding(text_, 2)
    end
    local handle = {
        Set = function(_, value)
            text_.Text = tostring(value)
        end,
        Get = function()
            return text_.Text
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
                    text_.Text = tostring(value)
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
        Text = opts.Content or "",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
        Parent = frame,
    })
    return finishElement(self, opts, {
        Set = function(_, value)
            content.Text = value
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
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
end

function Tab:Button(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
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
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.2)
            tween(knobGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.2)
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
    local ROW = TOUCH and 40 or 30
    local MAX_ROWS = opts.MaxRows or 6
    -- Stacked: the chip spans the whole row, with the name (if any) above it.
    local stacked = compact and opts.Stacked == true
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
        BackgroundColor3 = Theme.Surface,
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
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 120),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    padding(inner, 8, 8, 8, 8)

    local searchHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.Surface,
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
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand: AutomaticCanvasSize under the window's UIScale
        -- sometimes leaves the canvas short, so the list would not scroll.
        CanvasSize = UDim2.new(),
        Parent = inner,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = list,
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
    local optionButtons = {}
    local filter = ""

    local function matches(option)
        return filter == "" or string.find(string.lower(tostring(option)), filter, 1, true) ~= nil
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

    local function paintOption(button, animate)
        local on = selected[button.Option] == true
        if button.On == on and animate then
            return
        end
        button.On = on
        local duration = animate and 0.18 or 0
        tween(button.Box, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
        tween(button.BoxStroke, { Color = on and Theme.Accent or Theme.Stroke }, duration)
        tween(button.Check, { ImageTransparency = on and 0 or 1 }, duration)
        tween(button.Label, { TextColor3 = on and Theme.Text or Theme.Muted }, duration)
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
            fullText = #value > 0 and table.concat(value, ", ") or (opts.NoneText or "None")
        else
            fullText = value ~= nil and tostring(value) or (opts.NoneText or "None")
        end
        valueLabel.Text = trimmed()
        for _, button in pairs(optionButtons) do
            paintOption(button, animate)
        end
    end

    local function visibleCount()
        local count = 0
        for _, option in ipairs(options) do
            if matches(option) then
                count += 1
            end
        end
        return count
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
        local bodyHeight = window.Body.AbsoluteSize.Y / scale
        local chipTop = (chip.AbsolutePosition.Y - window.Body.AbsolutePosition.Y) / scale
        local room = math.max(bodyHeight - (chipTop + chip.AbsoluteSize.Y / scale) - 14, chipTop - 14) - top - 16
        if room >= ROW then
            listHeight = math.min(listHeight, room)
        end
        list.Position = UDim2.fromOffset(0, top)
        list.Size = UDim2.new(1, 0, 0, listHeight)
        local width = math.max(math.floor(chip.AbsoluteSize.X / scale), opts.PopupWidth or 210)
        local bodyWidth = window.Body.AbsoluteSize.X / scale
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
        for option, button in pairs(optionButtons) do
            button.Frame.Visible = matches(option)
        end
    end

    local scroller = nil
    local function place()
        local body = window.Body
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
        local below = chipPosition.Y + chipSize.Y + 6
        -- Opening upward pins the content to the bottom edge so it unfolds from the chip.
        if below + targetSize.Y > bodySize.Y - 8 and chipPosition.Y - 6 - targetSize.Y >= 8 then
            popup.AnchorPoint = Vector2.new(1, 1)
            popup.Position = UDim2.fromOffset(right, chipPosition.Y - 6)
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
        for index, option in ipairs(options) do
            if option == value then
                list.CanvasPosition = Vector2.new(0, math.max(0, (index - 2) * (ROW + 2)))
                return
            end
        end
    end
    local function setOpen(open)
        if open == self_.Open then
            return
        end
        self_.Open = open
        arrow:Set(open)
        tween(chipStroke, { Color = open and Theme.StrokeHover or Theme.Stroke }, 0.2)
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
            filter = ""
            searchBox.Text = ""
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
            tween(popupShadow, { ImageTransparency = 0.55 }, 0.3)
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

    local function buildOptions()
        local keep = {}
        for index, option in ipairs(options) do
            keep[option] = index
        end
        for option, button in pairs(optionButtons) do
            if not keep[option] then
                button.Frame:Destroy()
                optionButtons[option] = nil
            end
        end
        for index, option in ipairs(options) do
            local existing = optionButtons[option]
            if existing then
                existing.Frame.LayoutOrder = index
                continue
            end
            local row = create("TextButton", {
                Size = UDim2.new(1, -6, 0, ROW),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = list,
            })
            corner(row, UDim.new(0, 7))
            local box = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 8, 0.5, 0),
                Size = UDim2.fromOffset(18, 18),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Parent = row,
            })
            corner(box, UDim.new(0, 5))
            local boxStroke = stroke(box, Theme.Stroke)
            local check = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.AccentDark,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = box,
            })
            applyIcon(check, "check")
            local checkScale = create("UIScale", { Parent = check })
            local text_ = label({
                Position = UDim2.fromOffset(36, 0),
                Size = UDim2.new(1, -44, 1, 0),
                Text = tostring(option),
                TextSize = 13,
                TextColor3 = Theme.Muted,
                Parent = row,
            })
            local entry = { Option = option, Frame = row, Box = box, BoxStroke = boxStroke, Check = check, CheckScale = checkScale, Label = text_, On = nil }
            local isTap = tapGuard(row, function()
                return list
            end)
            row.MouseEnter:Connect(function()
                -- Touch fires enter without a matching leave; skip the hover.
                if usingTouch() then
                    return
                end
                tween(row, { BackgroundTransparency = 0.55 }, 0.15)
                tween(text_, { TextColor3 = Theme.Text }, 0.15)
                if not selected[option] then
                    tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
                end
            end)
            row.MouseLeave:Connect(function()
                tween(row, { BackgroundTransparency = 1 }, 0.25)
                tween(text_, { TextColor3 = selected[option] and Theme.Text or Theme.Muted }, 0.25)
                if not selected[option] then
                    tween(boxStroke, { Color = Theme.Stroke }, 0.25)
                end
            end)
            row.MouseButton1Click:Connect(function()
                if not isTap() then
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
            optionButtons[option] = entry
            paintOption(entry, false)
        end
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end

    selectAll.MouseButton1Click:Connect(function()
        for _, option in ipairs(options) do
            if matches(option) then
                selected[option] = true
            end
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
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        filter = string.lower(searchBox.Text)
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
            local number = tonumber(box.Text)
            if not number then
                box.Text = ""
                return
            end
        end
        safeCall(opts.Callback, box.Text, enterPressed)
    end)

    return finishElement(self, opts, {
        Set = function(_, value)
            box.Text = tostring(value)
            flashStroke(frameStroke)
        end,
        Get = function()
            return box.Text
        end,
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
    local PANEL_HEIGHT = 168
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
    titleDesc(header, opts.Name or "Color", opts.Desc, 90, metrics)

    local swatch = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -38 or -34, 0.5, 0),
        Size = UDim2.fromOffset(36, 20),
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(swatch, UDim.new(0, 6))
    stroke(swatch, Theme.Stroke)
    local arrow = arrowIndicator(header, 1, compact and -14 or -12)

    local panel = create("Frame", {
        Position = UDim2.fromOffset(14, height + 2),
        Size = UDim2.new(1, -28, 0, PANEL_HEIGHT - 12),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = frame,
    })

    local svBox = create("TextButton", {
        Size = UDim2.new(1, -30, 0, 110),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = panel,
    })
    corner(svBox, UDim.new(0, 6))
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
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90,
        Parent = svDark,
    })
    local svCursor = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
        ZIndex = 3,
        Parent = svBox,
    })
    corner(svCursor, UDim.new(1, 0))
    stroke(svCursor, Color3.new(1, 1, 1), 0, 2)

    local hueBar = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(14, 110),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(hueBar, UDim.new(0, 6))
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
        Rotation = 90,
        Parent = hueBar,
    })
    local hueCursor = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(18, 5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = hueBar,
    })
    corner(hueCursor, UDim.new(1, 0))
    stroke(hueCursor, Theme.AccentDark, 0.4)

    local hexHolder = create("Frame", {
        Position = UDim2.fromOffset(compact and 0 or 6, 122),
        Size = UDim2.fromOffset(compact and 96 or 118, 28),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = panel,
    })
    corner(hexHolder, UDim.new(0, 6))
    local hexStroke = stroke(hexHolder)
    local hexBox = create("TextBox", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -24, 1, 0),
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
        Position = UDim2.fromOffset(compact and 104 or 134, 122),
        Size = UDim2.new(1, compact and -104 or -134, 0, 28),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = compact and 12 or 13,
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
        svHueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
        tween(svCursor, { Position = UDim2.fromScale(sat, 1 - val) }, duration, Enum.EasingStyle.Linear)
        tween(hueCursor, { Position = UDim2.new(0.5, 0, hue, 0) }, duration, Enum.EasingStyle.Linear)
        if not hexBox:IsFocused() then
            hexBox.Text = toHex(color)
        end
        rgbLabel.Text = string.format("RGB %d, %d, %d",
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
        hue = math.clamp((position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 0.999)
        commit(0.04)
    end

    svBox.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "sv"
            tween(svCursor, { Size = UDim2.fromOffset(14, 14) }, 0.15, Enum.EasingStyle.Back)
            updateSV(pointerPosition())
        end
    end)
    hueBar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "hue"
            tween(hueCursor, { Size = UDim2.fromOffset(20, 7) }, 0.15, Enum.EasingStyle.Back)
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
            tween(svCursor, { Size = UDim2.fromOffset(10, 10) }, 0.2)
            tween(hueCursor, { Size = UDim2.fromOffset(18, 5) }, 0.2)
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
        TextColor3 = Theme.Accent,
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
        BackgroundColor3 = opts.Color or Theme.Accent,
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
            valueLabel.Text = tostring(formatter(frac))
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
        tween(fill, { BackgroundColor3 = color }, 0)
    end
    render(0)
    return finishElement(self, opts, self_, frame, "Progress")
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
    }, Window)
    local saving = type(opts.ConfigurationSaving) == "table" and opts.ConfigurationSaving or {}
    self.ConfigFolder = saving.FolderName or "AirflowUI"
    self.ConfigName = saving.FileName or "default"
    self._configListeners = {}
    self._pendingFlags = {}

    local startTheme = opts.DefaultTheme or opts.Theme
    if startTheme ~= nil then
        Library.DefaultTheme = startTheme
    end
    self:_applyDefaultTheme()
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

    glow(body, UDim2.fromOffset(500, 180), UDim2.new(0.5, 0, 1, 8), 0.86, 270)
    glow(body, UDim2.fromOffset(130, 60), UDim2.new(0, 60, 1, -16), 0.75, 90)
    glow(body, UDim2.fromOffset(520, 240), UDim2.new(1, -80, 0, 30), 0.92, 90)

    -- The sidebar is an inset rail with its own rounded panel and a soft
    -- top-lit gradient.
    local sidebar = create("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(0, SIDEBAR_WIDTH - 8, 1, -16),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = body,
    })
    corner(sidebar, UDim.new(0, 12))
    stroke(sidebar, Theme.Stroke)
    local railGradient = create("UIGradient", { Rotation = 90, Parent = sidebar })
    onTheme(railGradient, function()
        railGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Surface3),
            ColorSequenceKeypoint.new(0.3, Theme.Surface2),
            ColorSequenceKeypoint.new(1, Theme.Surface2),
        })
    end)

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
        Parent = sidebar,
    })
    local logo = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 2),
        Size = UDim2.fromOffset(42, 42),
        BackgroundTransparency = 1,
        Image = "",
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = header,
    })
    applyIcon(logo, opts.Icon or Assets.Logo, true)

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
    corner(indicator, UDim.new(0, 10))
    stroke(indicator, Theme.Stroke)
    -- An accent wash that fades out to the right, and a small accent pill in
    -- the gutter beside the tile, both gliding with the highlight.
    local sheen = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Parent = indicator,
    })
    corner(sheen, UDim.new(0, 10))
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = sheen,
    })
    local pill = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(0, -3, 0.5, 0),
        Size = UDim2.fromOffset(3, 20),
        BackgroundColor3 = Theme.Accent,
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
        Padding = UDim.new(0, 4),
        Parent = stack,
    })
    self._tabStack = stack

    -- Soft fades at the ends of the tab list while there is more to scroll.
    local function scrollFade(top)
        local fade = create("Frame", {
            AnchorPoint = Vector2.new(0, top and 0 or 1),
            Position = top and tabList.Position or UDim2.new(0, 0, tabList.Size.Y.Scale, tabList.Position.Y.Offset + tabList.Size.Y.Offset),
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 3,
            Parent = sidebar,
        })
        create("UIGradient", {
            Rotation = top and 90 or 270,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = fade,
        })
        return fade
    end
    local topFade, bottomFade = scrollFade(true), scrollFade(false)
    local function refreshFades()
        local overflow = tabList.AbsoluteCanvasSize.Y - tabList.AbsoluteWindowSize.Y
        local y = tabList.CanvasPosition.Y
        topFade.Visible = overflow > 1 and y > 1
        bottomFade.Visible = overflow > 1 and y < overflow - 1
    end
    tabList:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshFades)
    tabList:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refreshFades)
    tabList:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refreshFades)

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
    corner(minimizeButton, UDim.new(0, 8))
    local minimizeStroke = stroke(minimizeButton, Theme.Stroke, 1)
    local minimizeGlyph = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(12, 2),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = minimizeButton,
    })
    corner(minimizeGlyph, UDim.new(1, 0))
    minimizeButton.MouseEnter:Connect(function()
        tween(minimizeButton, { BackgroundTransparency = 0 }, 0.15)
        tween(minimizeStroke, { Transparency = 0 }, 0.15)
        tween(minimizeGlyph, { BackgroundColor3 = Theme.Text, Size = UDim2.fromOffset(14, 2) }, 0.2, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseLeave:Connect(function()
        tween(minimizeButton, { BackgroundTransparency = 1 }, 0.2)
        tween(minimizeStroke, { Transparency = 1 }, 0.2)
        tween(minimizeGlyph, { BackgroundColor3 = Theme.Muted, Size = UDim2.fromOffset(12, 2) }, 0.2, Enum.EasingStyle.Quint)
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

    self:_enableDrag()
    self.MaxSize = opts.MaxSize
    self.KeepOnScreen = opts.KeepOnScreen ~= false
    self:_enableResize(opts.MinSize or Vector2.new(480, 360))

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
    local gate = opts.UnsupportedExecutor
    if gate ~= false then
        gate = type(gate) == "table" and gate or {}
        local list = opts.SupportedExecutors or (type(opts.Home) == "table" and opts.Home.SupportedExecutors or nil)
        local executor, supported, message = executorReport({ SupportedExecutors = list })
        if not supported then
            opts._unsupported = {
                Executor = executor,
                Title = gate.Title or "Unsupported executor",
                Text = gate.Text or message,
                Block = gate.Block == true,
            }
        end
    end
    if loading == false and opts._unsupported then
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
    if self._dialog then
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

function Window:_enableDrag()
    local dragging = false
    local grabOffset = Vector2.zero
    local target = nil

    local function centre()
        local root = self.Root
        return root.AbsolutePosition + root.AbsoluteSize * root.AnchorPoint - self.Gui.AbsolutePosition
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
        dragging = true
        grabOffset = point - centre()
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if isPress(input) then
            dragging = false
            target = nil
            self:_clampToScreen()
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not dragging then
            return
        end
        target = pointerPosition() - grabOffset
        local current = centre()
        local alpha = 1 - math.exp(-deltaTime * 45)
        local step = current:Lerp(target, alpha)
        self.Root.Position = UDim2.fromOffset(step.X, step.Y)
    end)
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
    local loader = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 16),
        Size = UDim2.fromOffset(340, 150),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 10,
        Parent = gui,
    })
    local loaderCorner = corner(loader, UDim.new(0, 14))
    local loaderStroke = stroke(loader, Theme.Stroke, 1)
    edgeHighlight(loader)
    glow(loader, UDim2.fromOffset(340, 150), UDim2.new(1, -20, 0, -20), 0.88, 90)
    local loaderScale = create("UIScale", { Scale = 0.92, Parent = loader })
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

    -- Logo on the left, title and status beside it, progress along the bottom.
    local TEXT_X = 104
    local logoHolder = create("Frame", {
        Position = UDim2.fromOffset(24, 22),
        Size = UDim2.fromOffset(64, 64),
        BackgroundTransparency = 1,
        Parent = loader,
    })
    local logo = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.6, 0.6),
        Rotation = -20,
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = logoHolder,
    })
    applyIcon(logo, opts.Icon or Assets.Logo, true)
    -- The logo settles in, then drifts gently while the bar fills.
    local float = TweenService:Create(logo, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Position = UDim2.new(0.5, 0, 0.5, -3),
    })
    task.delay(0.1, function()
        tween(logo, { Size = UDim2.fromScale(1, 1), Rotation = 0, ImageTransparency = 0 }, 0.7, Enum.EasingStyle.Back)
        task.delay(0.7, function()
            if loader.Parent then
                float:Play()
            end
        end)
    end)

    local titleLabel = label({
        Position = UDim2.fromOffset(TEXT_X + 10, 32),
        Size = UDim2.new(1, -TEXT_X - 24, 0, 24),
        Text = opts.LoadingTitle or opts.Title or "Airflow",
        TextSize = 22,
        TextTransparency = 1,
        Parent = loader,
    })
    local statusLabel = label({
        Position = UDim2.fromOffset(TEXT_X + 10, 60),
        Size = UDim2.new(1, -TEXT_X - 24, 0, 16),
        Text = opts.LoadingText or opts.Subtitle or "Loading",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextTransparency = 1,
        Parent = loader,
    })
    -- Title and status slide in a beat after the card.
    task.delay(0.15, function()
        tween(titleLabel, { TextTransparency = 0, Position = UDim2.fromOffset(TEXT_X, 32) }, 0.45, Enum.EasingStyle.Quint)
    end)
    task.delay(0.25, function()
        tween(statusLabel, { TextTransparency = 0, Position = UDim2.fromOffset(TEXT_X, 60) }, 0.45, Enum.EasingStyle.Quint)
    end)

    local track = create("Frame", {
        Position = UDim2.new(0, 24, 1, -34),
        Size = UDim2.new(1, -100, 0, 6),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = loader,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))
    create("UIGradient", {
        Color = ColorSequence.new(Theme.Accent:Lerp(Color3.new(0, 0, 0), 0.25), Theme.Accent:Lerp(Color3.new(1, 1, 1), 0.2)),
        Parent = fill,
    })
    local sheen = create("Frame", {
        Position = UDim2.fromScale(-0.4, 0),
        Size = UDim2.fromScale(0.4, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.65,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = track,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = sheen,
    })
    local percentLabel = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -24, 1, -31),
        Size = UDim2.fromOffset(44, 16),
        Text = "0%",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = loader,
    })

    tween(loader, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.4, Enum.EasingStyle.Quint)
    tween(loaderScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
    tween(loaderShadow, { ImageTransparency = 0.55 }, 0.4)
    local sweep = TweenService:Create(sheen, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), {
        Position = UDim2.fromScale(1, 0),
    })
    sweep:Play()
    tween(fill, { Size = UDim2.fromScale(0.85, 1) }, duration * 0.8, Enum.EasingStyle.Quart)
    -- The percentage simply follows the bar.
    local percentStep
    percentStep = RunService.RenderStepped:Connect(function()
        if not loader.Parent then
            percentStep:Disconnect()
            return
        end
        percentLabel.Text = math.floor(fill.Size.X.Scale * 100 + 0.5) .. "%"
    end)

    task.spawn(loadLucide)

    local steps = opts.LoadingSteps or { "Preparing interface", "Loading icons", "Almost there" }
    for index, text in ipairs(steps) do
        task.delay(duration * (index - 1) / #steps, function()
            if not loader.Parent then
                return
            end
            if index == 1 then
                statusLabel.Text = text
                return
            end
            -- Old step drifts up and out, the new one rises in under it.
            tween(statusLabel, { TextTransparency = 1, Position = UDim2.fromOffset(TEXT_X, 56) }, 0.12)
            task.delay(0.12, function()
                if not loader.Parent then
                    return
                end
                statusLabel.Text = text
                statusLabel.Position = UDim2.fromOffset(TEXT_X, 64)
                tween(statusLabel, { TextTransparency = 0, Position = UDim2.fromOffset(TEXT_X, 60) }, 0.22, Enum.EasingStyle.Quint)
            end)
        end)
    end

    local function finish()
        sweep:Cancel()
        float:Cancel()
        for _, item in ipairs(loader:GetChildren()) do
            if item:IsA("TextLabel") then
                tween(item, { TextTransparency = 1 }, 0.15)
            end
        end
        tween(logo, { ImageTransparency = 1, Size = UDim2.fromScale(0.85, 0.85) }, 0.15)
        tween(track, { BackgroundTransparency = 1 }, 0.15)
        tween(fill, { BackgroundTransparency = 1 }, 0.15)
        tween(sheen, { BackgroundTransparency = 1 }, 0.1)

        local fit = self._fitScale or 1
        local target = self.Root.Size
        tween(loader, {
            Size = UDim2.fromOffset(target.X.Offset * fit, target.Y.Offset * fit),
            Position = UDim2.fromScale(0.5, 0.5),
        }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderCorner, { CornerRadius = UDim.new(0, 10) }, 0.5, Enum.EasingStyle.Quint)
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

    -- Unsupported executor: the bar gives way to a warning card with
    -- Continue (unless blocked) and Exit.
    local function warnUnsupported(info)
        sweep:Cancel()
        float:Cancel()
        tween(titleLabel, { TextTransparency = 1 }, 0.15)
        tween(statusLabel, { TextTransparency = 1 }, 0.15)
        tween(percentLabel, { TextTransparency = 1 }, 0.15)
        tween(logo, { ImageTransparency = 1, Size = UDim2.fromScale(0.85, 0.85) }, 0.15)
        tween(track, { BackgroundTransparency = 1 }, 0.15)
        tween(fill, { BackgroundTransparency = 1 }, 0.15)
        tween(sheen, { BackgroundTransparency = 1 }, 0.1)

        local WIDTH, PAD = 360, 24
        local warnCard = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            ZIndex = 5,
            Parent = loader,
        })
        local badge = create("Frame", {
            Position = UDim2.fromOffset(PAD, PAD),
            Size = UDim2.fromOffset(44, 44),
            BackgroundColor3 = Theme.Warning,
            BackgroundTransparency = 0.86,
            BorderSizePixel = 0,
            Parent = warnCard,
        })
        corner(badge, UDim.new(0, 12))
        stroke(badge, Theme.Warning, 1).Transparency = 0.6
        local badgeIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(22, 22),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Warning,
            ScaleType = Enum.ScaleType.Fit,
            Parent = badge,
        })
        applyIcon(badgeIcon, "shield-alert")
        label({
            Position = UDim2.fromOffset(PAD + 58, PAD + 3),
            Size = UDim2.new(1, -(PAD * 2 + 58), 0, 20),
            Text = info.Title,
            TextSize = 17,
            Parent = warnCard,
        })
        label({
            Position = UDim2.fromOffset(PAD + 58, PAD + 25),
            Size = UDim2.new(1, -(PAD * 2 + 58), 0, 16),
            Text = info.Executor,
            TextSize = 13,
            TextColor3 = Theme.Warning,
            Parent = warnCard,
        })
        local body = label({
            Position = UDim2.fromOffset(PAD, PAD + 60),
            Size = UDim2.new(1, -PAD * 2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = info.Block and (info.Text .. " This script can't run here.") or info.Text,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = warnCard,
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
        button("Exit", info.Block, 1, function()
            tween(loader, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 12) }, 0.25, Enum.EasingStyle.Quint)
            tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
            task.delay(0.25, function()
                self:Destroy()
            end)
        end)
        if not info.Block then
            button("Continue anyway", true, 2, function()
                tween(warnCard, { GroupTransparency = 1 }, 0.15)
                task.delay(0.15, finish)
            end)
        end

        -- The card grows to fit the message, then the warning fades in.
        task.delay(0.15, function()
            if not loader.Parent then
                return
            end
            local height = PAD + 60 + math.max(body.TextBounds.Y, 16) + 18 + 34 + PAD - 4
            tween(loader, { Size = UDim2.fromOffset(WIDTH, height) }, 0.35, Enum.EasingStyle.Quint)
            task.delay(0.12, function()
                tween(warnCard, { GroupTransparency = 0 }, 0.3)
                badge.Size = UDim2.fromOffset(34, 34)
                badge.Position = UDim2.fromOffset(PAD + 5, PAD + 5)
                tween(badge, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(PAD, PAD) }, 0.45, Enum.EasingStyle.Back)
            end)
        end)
    end

    task.delay(duration, function()
        tween(fill, { Size = UDim2.fromScale(1, 1) }, 0.25, Enum.EasingStyle.Quint)
        task.delay(0.25, function()
            if not loader.Parent then
                return
            end
            if opts._unsupported then
                warnUnsupported(opts._unsupported)
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
    local scale = math.min(1, (viewport.X - 24) / math.max(size.X.Offset, 1), (viewport.Y - 24) / math.max(size.Y.Offset, 1))
    self._fitScale = math.max(scale, 0.45)
    if self._introDone and self.Open then
        if instant then
            self.Scale.Scale = self._fitScale
        else
            tween(self.Scale, { Scale = self._fitScale }, 0.2)
        end
    end
end

function Window:_clampToScreen()
    if not self.KeepOnScreen or self._resizeActive then
        return
    end
    local viewport = self.Gui.AbsoluteSize
    local root = self.Root
    local half = root.AbsoluteSize / 2
    local centre = root.AbsolutePosition + half - self.Gui.AbsolutePosition
    local clamped = Vector2.new(
        math.clamp(centre.X, math.min(half.X, viewport.X / 2), math.max(viewport.X - half.X, viewport.X / 2)),
        math.clamp(centre.Y, math.min(half.Y, viewport.Y / 2), math.max(viewport.Y - half.Y, viewport.Y / 2))
    )
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
    local gripImage = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, -16, 0.5, -16),
        Size = UDim2.fromOffset(96, 96),
        BackgroundTransparency = 1,
        Image = "rbxassetid://120997033468887",
        ImageColor3 = Theme.Accent,
        ImageTransparency = 0.8,
        ZIndex = 20,
        Parent = grip,
    })

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
        tween(gripImage, { ImageTransparency = 0.35 }, 0.1)
    end)
    grip.MouseEnter:Connect(function()
        if not resizing then
            tween(gripImage, { ImageTransparency = 0.35 }, 0.1)
        end
    end)
    grip.MouseLeave:Connect(function()
        if not resizing then
            tween(gripImage, { ImageTransparency = 0.8 }, 0.17)
        end
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if resizing and isPress(input) then
            resizing = false
            tween(gripImage, { ImageTransparency = 0.8 }, 0.17)
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
    for flag, element in pairs(Library.Flags) do
        if element._type and type(element.Get) == "function" then
            local ok, entry = pcall(serializeFlag, element)
            if ok then
                data[flag] = entry
            end
        end
    end
    return data
end

function Window:_applyFlags(data, silent)
    silent = silent == true
    self._pendingFlags = {}
    for flag, entry in pairs(data) do
        local element = Library.Flags[flag]
        if element and type(element.Set) == "function" then
            if entryMatches(element, entry) then
                pcall(deserializeFlag, element, entry, silent)
            end
        elseif type(entry) == "table" then
            self._pendingFlags[flag] = { Entry = entry, Silent = silent }
        end
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
    local ok, err = writeConfig(self, name, collectFlags(self))
    if ok then
        self.ConfigName = name
    end
    return ok, err
end

function Window:LoadConfig(name, silent)
    name = name or self.ConfigName
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

function Window:LoadAutoload(silent)
    local name = self:GetAutoload()
    if not name then
        return false, "no autoload config"
    end
    return self:LoadConfig(name, silent)
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

local function statTile(parent, order, icon, title)
    local tile = create("Frame", {
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = parent,
    })
    tile:SetAttribute("NoDrag", true)
    corner(tile, UDim.new(0, 10))
    stroke(tile)
    local holder = glowIcon(tile, icon, Theme.Accent, UDim2.new(0, 12, 0, 20))
    holder.Size = UDim2.fromOffset(14, 14)
    label({
        Position = UDim2.fromOffset(31, 12),
        Size = UDim2.new(1, -37, 0, 16),
        Text = title,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        Parent = tile,
    })
    return label({
        Position = UDim2.fromOffset(12, 33),
        Size = UDim2.new(1, -20, 0, 20),
        Text = "…",
        TextSize = 17,
        FontFace = Fonts.Bold,
        Parent = tile,
    })
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
    padding(list, 24, 24, 2, 24)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = list,
    })
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
    elseif self._searchActive then
        self._emptyCaption.Text = "No matches"
        empty.Visible = (self._searchHits or 0) == 0
    else
        self._emptyCaption.Text = self._emptyText
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
    local layout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = holder,
    })
    local function column(order)
        local frame = create("Frame", {
            Size = UDim2.new(0.5, -5, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = holder,
        })
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            Parent = frame,
        })
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
        if stacked == set.Stacked then
            return
        end
        set.Stacked = stacked
        layout.FillDirection = stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
        local size = stacked and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -5, 0, 0)
        set.Left.Size = size
        set.Right.Size = size
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
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

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = 1,
        Parent = box,
    })
    if opts.Icon then
        local image = create("ImageLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            Parent = header,
        })
        applyIcon(image, opts.Icon)
    end
    local collapseButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, opts.Icon and -36 or -10, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = header,
    })
    corner(collapseButton, UDim.new(0, 6))
    local glyph = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
        Parent = collapseButton,
    })
    local function bar(size)
        local frame = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = size,
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            Parent = glyph,
        })
        corner(frame, UDim.new(1, 0))
        return frame
    end
    local horizontal = bar(UDim2.fromOffset(10, 2))
    local vertical = bar(UDim2.fromOffset(2, 0))
    local reserve = (opts.Icon and 36 or 10) + 30
    local title = label({
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -(14 + reserve), 1, 0),
        Text = opts.Name or "Groupbox",
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
    padding(inner, 0, 0, 6, 8)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = inner,
    })

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
    group._searchKey = string.lower(group.Name)
    table.insert(self._groupboxes, group)

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
        tween(rule, { BackgroundTransparency = value and 1 or 0 }, instant and 0 or 0.2)
        tween(vertical, { Size = UDim2.fromOffset(2, value and 10 or 0) }, motion, Enum.EasingStyle.Back)
        tween(glyph, { Rotation = value and 90 or 0 }, motion, Enum.EasingStyle.Quint)
    end

    local function hover(on)
        tween(collapseButton, { BackgroundTransparency = on and 0.4 or 1 }, on and 0.12 or 0.2)
        tween(horizontal, { BackgroundColor3 = on and Theme.Text or Theme.Muted }, 0.15)
        tween(vertical, { BackgroundColor3 = on and Theme.Text or Theme.Muted }, 0.15)
    end
    collapseButton.MouseEnter:Connect(function()
        hover(true)
    end)
    collapseButton.MouseLeave:Connect(function()
        hover(false)
    end)
    local function flip()
        setCollapsed(not collapsed)
    end
    collapseButton.MouseButton1Click:Connect(flip)

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
        group._searchKey = string.lower(group.Name)
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
        box.Visible = visible and group._searchMatch ~= false
        window._controlsDirty = true
        if window._filtered and window.SearchBox then
            window:_applySearch(window.SearchBox.Text)
        end
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
        window._controlsDirty = true
        box:Destroy()
    end

    if opts.Collapsed then
        setCollapsed(true, true)
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

Tab.CreateGroupbox = Tab.Groupbox
Tab.AddGroupbox = Tab.Groupbox
Tab.AddLeftGroupbox = sideGroupbox("Left")
Tab.AddRightGroupbox = sideGroupbox("Right")

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

-- Managers go in their own groupbox when added straight to a tab.
local function managerHost(tab, opts, name, icon)
    if tab._groupbox then
        return tab
    end
    return tab:Groupbox({ Name = opts.Name or name, Icon = opts.Icon or icon, Side = opts.Side })
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

    local function refreshStatus()
        status:Set(("loaded: %s   |   autoload: %s"):format(window.LoadedConfig or "none", window:GetAutoload() or "none"))
    end

    local function pickedName()
        local name = list:Get()
        if not name then
            notify(false, "No config selected", "Pick one from the list first")
        end
        return name
    end

    local nameInput = actionInput(host, opts.Placeholder or "config name", nil, function(text)
        manager:Create(text)
    end)
    local names = window:ListConfigs()
    local initial = window.LoadedConfig or window:GetAutoload()
    list = host:Dropdown({
        Stacked = true,
        Options = names,
        Default = table.find(names, initial) and initial or nil,
        EmptyText = "--",
        NoneText = "--",
    })
    host:ButtonRow({
        { Name = "Create", Callback = function() manager:Create(nameInput:Get()) end },
        { Name = "Save", Callback = function() manager:Save() end },
    })
    host:ButtonRow({
        { Name = "Load", Callback = function() manager:Load() end },
        { Name = "Delete", Style = "Danger", Callback = function() manager:Delete() end },
    })
    host:ButtonRow({
        { Name = "Set autoload", Callback = function() manager:SetAutoload() end },
        { Name = "Clear autoload", Callback = function() manager:ClearAutoload() end },
    })
    host:ButtonRow({
        { Name = "Rename", Callback = function() manager:Rename(nil, nameInput:Get()) end },
        { Name = "Reset", Style = "Danger", Callback = function() manager:Reset() end },
    })
    status = host:Label("loaded: none   |   autoload: none")
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
    host:Button({ Name = "Refresh list", Callback = function() manager:Refresh() end })
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
        notify(ok, ok and "Autoload set" or "Autoload failed", ok and name or tostring(err))
    end

    function manager:ClearAutoload()
        local current = window:GetAutoload()
        if not current then
            notify(false, "No autoload", "Nothing is set to autoload")
            return
        end
        local ok, err = window:SetAutoload(nil)
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
        if window.LoadedConfig and list:Get() == nil then
            list:Set(window.LoadedConfig, true)
        end
        refreshStatus()
    end)
    status._listeners = status._listeners or {}
    table.insert(status._listeners, disconnect)

    refreshStatus()
    return manager
end

local PRESET_ORDER = {
    "Airflow", "Obsidian", "Nebula", "Synthwave", "Sakura", "Velvet", "Rose", "Crimson", "Sunset", "Amber", "Gold",
    "Cyber", "Toxic", "Matcha", "Emerald", "Aurora", "Ocean", "Frost", "Midnight", "Abyss", "Mono",
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
    if window._backdrop and opts.Weather ~= false then
        local labels = { None = "None", Snow = "Snow", Rain = "Rain", Ember = "Hell Fire" }
        host:Dropdown({
            Name = "Weather",
            Options = { "Snow", "Rain", "Hell Fire", "None" },
            Default = labels[window.Weather] or "None",
            AllowNone = false,
            Callback = function(name)
                if name then
                    window:SetWeather(name)
                end
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

local STATUS_HEIGHT = { Plain = 22, Row = 24, Badge = 28, Dot = 24, Bar = 38, Stat = 46 }

local function toneColor(tone)
    if type(tone) == "string" and typeof(Theme[tone]) == "Color3" then
        return Theme[tone]
    end
    return Theme.Accent
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
    local pad = compact and 0 or 8
    local frame = card(self, "Frame", height + pad * 2, opts)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(14, pad),
        Size = UDim2.new(1, -28, 0, height),
        BackgroundTransparency = 1,
        Parent = frame,
    })

    local handle = { Value = opts.Value, Max = opts.Max, Tone = opts.Tone or "Accent", Name = opts.Name or "" }
    local keyLabel, valueLabel, chip, chipStroke, dot, pulse, fill
    local tinted = false

    local function keyText()
        return style == "Plain" and (handle.Name .. ":") or handle.Name
    end

    if style == "Plain" then
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 5),
            Parent = holder,
        })
        keyLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = holder,
        })
        valueLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = holder,
        })
    elseif style == "Stat" then
        keyLabel = label({
            Position = UDim2.fromOffset(0, 3),
            Size = UDim2.new(1, 0, 0, 14),
            TextSize = 11,
            TextColor3 = Theme.Muted,
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
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = holder,
        })
        if style == "Badge" then
            tinted = true
            chip = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(0, 22),
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
                TextSize = 12,
                TextColor3 = toneColor(handle.Tone),
                TextTruncate = Enum.TextTruncate.None,
                Parent = chip,
            })
        else
            valueLabel = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0.45, 0, 0, rowHeight),
                TextSize = 12,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = holder,
            })
        end
        if style == "Bar" then
            local track = create("Frame", {
                Position = UDim2.fromOffset(0, 25),
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
        keyLabel.Text = keyText()
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
        text = (opts.Prefix or "") .. text .. (opts.Suffix or "")
        local changed = lastText ~= nil and text ~= lastText
        lastText = text
        valueLabel.Text = text
        local tone = toneColor(handle.Tone)
        local duration = animate and 0.25 or 0
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
                    tween(valueLabel, { TextColor3 = Theme.Text }, 0.45)
                end
            end)
        end
    end

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
    function handle:SetName(name)
        handle.Name = tostring(name)
        render(false)
    end
    function handle:Text()
        return valueLabel.Text
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
                    elseif type(extra) == "string" then
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
        TextSize = 11,
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
            return {
                Text = tostring(text == nil and "" or text),
                Value = entry.Value ~= nil and tostring(entry.Value) or nil,
                Tone = type(entry.Tone) == "string" and entry.Tone or nil,
            }
        end
        return { Text = tostring(entry) }
    end

    local function rowKey(entry)
        return entry.Text .. "\0" .. (entry.Value or "\1") .. "\0" .. (entry.Tone or "")
    end

    -- Tone tints the value, or the text when there is no value.
    local function paint(row, entry)
        local key = rowKey(entry)
        if row.Key == key then
            return
        end
        row.Key = key
        row.Text.Text = entry.Text
        local tone = entry.Tone and typeof(Theme[entry.Tone]) == "Color3" and Theme[entry.Tone] or nil
        if entry.Value then
            row.Value.Text = entry.Value
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
        handle._searchKey = string.lower(text)
    end
    local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
    function handle:SetUpdateRate(seconds)
        rate = math.max(tonumber(seconds) or rate, 0.05)
    end

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

-- Search

local function isStructural(element)
    return element._type == "Section" or element._type == "Divider"
end

local function filterContainer(container, query)
    local searching = query ~= ""
    local function hit(key)
        return key ~= nil and string.find(key, query, 1, true) ~= nil
    end
    local hits = 0
    for _, element in ipairs(container._items or {}) do
        local show = not searching or (not isStructural(element) and hit(element._searchKey))
        element._searchMatch = show
        if element._frame then
            element._frame.Visible = show and element._userVisible ~= false
        end
        if show and element._userVisible ~= false then
            hits += 1
        end
    end
    for _, group in ipairs(container._groupboxes or {}) do
        local titleHit = not searching or hit(group._searchKey)
        local any = false
        for _, element in ipairs(group._items) do
            local show = titleHit or (not isStructural(element) and hit(element._searchKey))
            element._searchMatch = show
            if element._frame then
                element._frame.Visible = show and element._userVisible ~= false
            end
            any = any or (show and element._userVisible ~= false)
        end
        local visible = titleHit or any
        group._searchMatch = visible
        group._frame.Visible = visible and group._userVisible ~= false
        if visible and group._userVisible ~= false then
            hits += 1
        end
    end
    container._searchActive = searching
    container._searchHits = hits
    container:_refreshEmpty()
end

function Window:_searchTarget()
    local tab = self.CurrentTab
    if not tab then
        return nil
    end
    return tab.CurrentSubTab or tab
end

function Window:_applySearch(text)
    local query = string.lower(text or "")
    query = query:match("^%s*(.-)%s*$")
    local target = self:_searchTarget()
    if self._filtered and self._filtered ~= target then
        filterContainer(self._filtered, "")
        self._filtered = nil
    end
    if target and not target._noSearch then
        filterContainer(target, query)
        self._filtered = target
    end
end

function Window:_resetSearch()
    if self._filtered then
        filterContainer(self._filtered, "")
        self._filtered = nil
    end
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
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -56, 0, 14),
        Size = UDim2.fromOffset(SEARCH_WIDTH, 34),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = content,
    })
    holder:SetAttribute("NoDrag", true)
    corner(holder, UDim.new(0, 8))
    local holderStroke = stroke(holder)
    local _, icon = glowIcon(holder, "search", Theme.Muted, UDim2.new(0, 11, 0.5, 0))
    icon.Parent.Size = UDim2.fromOffset(14, 14)
    local box = create("TextBox", {
        Position = UDim2.fromOffset(33, 0),
        Size = UDim2.new(1, -41, 1, 0),
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
        Parent = holder,
    })
    self.SearchBox = box
    box.Focused:Connect(function()
        tween(holderStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(icon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    box.FocusLost:Connect(function()
        tween(holderStroke, { Color = Theme.Stroke }, 0.2)
        tween(icon, { ImageColor3 = Theme.Muted }, 0.2)
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        self:_applySearch(box.Text)
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
        Position = UDim2.new(0.5, 0, 1, -6),
        Size = UDim2.new(1, -10, 0, PROFILE_HEIGHT - 12),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = sidebar,
    })
    corner(card)
    local cardStroke = stroke(card, Theme.Stroke, 1)
    local head = avatar(self, card, {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 7),
        Size = UDim2.fromOffset(40, 40),
    }, Theme.Accent, 0.55, 1.5)
    local online = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 1, 1, 1),
        Size = UDim2.fromOffset(11, 11),
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = head,
    })
    corner(online, UDim.new(1, 0))
    stroke(online, Theme.Surface2, 0, 2)
    local name = label({
        Position = UDim2.fromOffset(4, 52),
        Size = UDim2.new(1, -8, 0, 15),
        TextSize = 12,
        FontFace = Fonts.Bold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })
    self:_trackName(name, "Display")
    local gameLabel = label({
        Position = UDim2.fromOffset(4, 67),
        Size = UDim2.new(1, -8, 0, 13),
        Text = "…",
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })
    task.spawn(function()
        gameLabel.Text = detectGameName()
    end)
    card.MouseEnter:Connect(function()
        if usingTouch() then
            return
        end
        tween(card, { BackgroundTransparency = 0.4 }, 0.12)
        tween(cardStroke, { Transparency = 0.5 }, 0.12)
    end)
    card.MouseLeave:Connect(function()
        tween(card, { BackgroundTransparency = 1 }, 0.2)
        tween(cardStroke, { Transparency = 1 }, 0.2)
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

function Window:_homeProfile(list, opts, order)
    local panel = panelCard(list, 122, order)
    avatar(self, panel, {
        Position = UDim2.fromOffset(20, 21),
        Size = UDim2.fromOffset(80, 80),
    }, Theme.Accent, 0.45, 2)
    label({
        Position = UDim2.fromOffset(118, 28),
        Size = UDim2.new(1, -236, 0, 16),
        Text = opts.Welcome or "Welcome back,",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = panel,
    })
    local nameLabel = label({
        Position = UDim2.fromOffset(118, 45),
        Size = UDim2.new(1, -236, 0, 30),
        TextSize = 24,
        FontFace = Fonts.Bold,
        Parent = panel,
    })
    self:_trackName(nameLabel, "Display")
    local userLabel = label({
        Position = UDim2.fromOffset(118, 76),
        Size = UDim2.new(1, -370, 0, 16),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = panel,
    })
    self:_trackName(userLabel, "User")

    local tier = opts.Tier
    if tier == nil then
        tier = "Free"
    end
    if tier then
        local badge = create("Frame", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -16, 0, 16),
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.88,
            BorderSizePixel = 0,
            Parent = panel,
        })
        corner(badge, UDim.new(1, 0))
        stroke(badge, Theme.Accent, 0.55)
        padding(badge, 12, 16)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
            Parent = badge,
        })
        local badgeIcon = create("ImageLabel", {
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = badge,
        })
        applyIcon(badgeIcon, opts.TierIcon or self._logoIcon)
        self.TierLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = tostring(tier),
            TextSize = 14,
            TextColor3 = Theme.Accent,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = badge,
        })
    end
    local expiryLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 55),
        Size = UDim2.fromOffset(160, 14),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = panel,
    })

    local privacy = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -14),
        Size = UDim2.fromOffset(0, 30),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = panel,
    })
    corner(privacy, UDim.new(0, 8))
    stroke(privacy)
    padding(privacy, 12, 12)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = privacy,
    })
    local function privacySwitch(order_, icon, text, initial, callback)
        local item = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            LayoutOrder = order_,
            Parent = privacy,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
            Parent = item,
        })
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = item,
        })
        applyIcon(image, icon)
        label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = text,
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = item,
        })
        create("Frame", { Size = UDim2.fromOffset(4, 1), BackgroundTransparency = 1, LayoutOrder = 3, Parent = item })
        miniSwitch(item, initial, 4, callback)
    end
    privacySwitch(1, "eye-off", "Name", self._hideName, function(on)
        self:SetHideName(on)
    end)
    create("Frame", {
        Size = UDim2.fromOffset(1, 16),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = privacy,
    })
    privacySwitch(3, "user", "Profile", self._hideAvatar, function(on)
        self:SetHideAvatar(on)
    end)
    local function fitUser()
        userLabel.Size = UDim2.new(1, -(118 + privacy.AbsoluteSize.X / self.Scale.Scale + 28), 0, 16)
    end
    privacy:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitUser)
    task.defer(fitUser)

    return function()
        local value = opts.Expiry
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "number" then
            local left = value - os.time()
            expiryLabel.Text = left > 0 and formatDuration(left) or "Expired"
        elseif value ~= nil then
            expiryLabel.Text = tostring(value)
        end
    end
end

function Window:_homeGame(list, order)
    local panel = panelCard(list, 122, order)
    local icon = create("ImageLabel", {
        Position = UDim2.fromOffset(16, 16),
        Size = UDim2.fromOffset(60, 60),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        Parent = panel,
    })
    corner(icon, UDim.new(0, 12))
    stroke(icon)
    local left = create("Frame", {
        Position = UDim2.fromOffset(90, 14),
        Size = UDim2.new(1, -330, 0, 96),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = left })
    local function line(order_, props)
        local defaults = {
            Size = UDim2.new(1, 0, 0, 16),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            LayoutOrder = order_,
            Parent = left,
        }
        for key, value in pairs(props) do
            defaults[key] = value
        end
        return label(defaults)
    end
    local gameName = line(1, { Size = UDim2.new(1, 0, 0, 22), Text = "Loading", TextSize = 16, FontFace = Fonts.Bold, TextColor3 = Theme.Text })
    local creator = line(2, { Text = "" })
    create("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 3, Parent = left })
    line(4, { Text = "Job  " .. shortId(game.JobId) })
    line(5, { Text = "Place  " .. tostring(game.PlaceId) })
    line(6, { Text = "Universe  " .. tostring(game.GameId) })
    task.spawn(function()
        local info = fetchGameInfo()
        gameName.Text = info and info.Name or detectGameName()
        local owner = info and type(info.Creator) == "table" and info.Creator.Name
        creator.Text = owner and ("by " .. owner) or ""
    end)

    local actions = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(216, 96),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    local half = UDim2.new(0.5, -3, 0, 28)
    softButton(actions, "Rejoin", { Size = half }, function()
        self:Rejoin()
    end)
    softButton(actions, "Server Hop", { Position = UDim2.new(0.5, 3, 0, 0), Size = half }, function()
        self:ServerHop()
    end)
    softButton(actions, "Copy Job ID", { Position = UDim2.fromOffset(0, 34), Size = half }, function()
        self:CopyToClipboard(game.JobId, "Job ID")
    end)
    softButton(actions, "Copy Universe", { Position = UDim2.new(0.5, 3, 0, 34), Size = half }, function()
        self:CopyToClipboard(game.GameId, "Universe ID")
    end)
    softButton(actions, "Join Lowest Server", { Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 28) }, function()
        self:JoinLowestServer()
    end)

    -- Narrow windows move the actions under the details.
    local stacked = nil
    local function fit()
        local width = panel.AbsoluteSize.X / self.Scale.Scale
        local stack = width < 470
        if stack == stacked then
            return
        end
        stacked = stack
        if stack then
            actions.AnchorPoint = Vector2.new(0, 0)
            actions.Position = UDim2.fromOffset(16, 122)
            actions.Size = UDim2.new(1, -32, 0, 96)
            left.Size = UDim2.new(1, -106, 0, 96)
            panel.Size = UDim2.new(1, 0, 0, 234)
        else
            actions.AnchorPoint = Vector2.new(1, 0.5)
            actions.Position = UDim2.new(1, -14, 0.5, 0)
            actions.Size = UDim2.fromOffset(216, 96)
            left.Size = UDim2.new(1, -330, 0, 96)
            panel.Size = UDim2.new(1, 0, 0, 122)
        end
    end
    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)
end

function Window:_homeExecutor(list, opts, order)
    local panel = panelCard(list, 64, order)
    local executor, supported, message = executorReport(opts)
    local tone = supported and Theme.Accent or Theme.Warning
    local holder = glowIcon(panel, supported and "shield-check" or "shield-alert", tone, UDim2.new(0, 18, 0.5, 0))
    holder.Size = UDim2.fromOffset(20, 20)
    label({
        Position = UDim2.fromOffset(52, 13),
        Size = UDim2.new(1, -170, 0, 18),
        Text = executor,
        TextSize = 14,
        Parent = panel,
    })
    label({
        Position = UDim2.fromOffset(52, 32),
        Size = UDim2.new(1, -170, 0, 16),
        Text = message,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = supported and Theme.Muted or Theme.Warning,
        Parent = panel,
    })

    local hint = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0.5, 0),
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = panel,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = hint,
    })
    local chip = create("Frame", {
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        LayoutOrder = 1,
        Parent = hint,
    })
    corner(chip, UDim.new(0, 6))
    stroke(chip)
    padding(chip, 8, 8)
    self._keyChipLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = keyName(self.Keybind),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = TOUCH and "or tap the pill" or "to hide",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = hint,
    })
end

function Window:_homeLinks(list, opts, order)
    local links = {}
    if opts.Discord then
        table.insert(links, {
            Icon = opts.DiscordIcon or "message-circle",
            Title = opts.DiscordTitle or "Join the community",
            Text = opts.Discord,
            Button = "Copy Invite",
        })
    end
    if opts.Website then
        table.insert(links, {
            Icon = opts.WebsiteIcon or "monitor",
            Title = opts.WebsiteTitle or "Supported games",
            Text = opts.Website,
            Button = "Copy Website",
        })
    end
    for _, link in ipairs(opts.Links or {}) do
        table.insert(links, link)
    end
    if #links == 0 then
        return
    end
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = list,
    })
    local grid = create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(8, 8),
        CellSize = UDim2.new(1, 0, 0, 64),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = holder,
    })
    local function fit()
        local width = holder.AbsoluteSize.X / self.Scale.Scale
        local columns = (#links > 1 and width >= 470) and 2 or 1
        grid.CellSize = UDim2.new(1 / columns, columns > 1 and -4 or 0, 0, 64)
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)
    for index, link in ipairs(links) do
        local panel = panelCard(holder, 64, index)
        local iconHolder = glowIcon(panel, link.Icon or "link", Theme.Accent, UDim2.new(0, 16, 0.5, 0))
        iconHolder.Size = UDim2.fromOffset(18, 18)
        local button = softButton(panel, link.Button or "Copy", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(0, 30),
            AutomaticSize = Enum.AutomaticSize.X,
        }, function()
            if type(link.Callback) == "function" then
                safeCall(link.Callback)
            else
                self:CopyToClipboard(link.Copy or link.Text, link.Title)
            end
        end)
        local title = label({
            Position = UDim2.fromOffset(46, 13),
            Size = UDim2.new(1, -150, 0, 18),
            Text = link.Title or "",
            TextSize = 14,
            Parent = panel,
        })
        local text_ = label({
            Position = UDim2.fromOffset(46, 32),
            Size = UDim2.new(1, -150, 0, 16),
            Text = link.Text or "",
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = panel,
        })
        local function reserve()
            local width = button.AbsoluteSize.X / self.Scale.Scale + 14 + 58
            title.Size = UDim2.new(1, -width, 0, 18)
            text_.Size = UDim2.new(1, -width, 0, 16)
        end
        button:GetPropertyChangedSignal("AbsoluteSize"):Connect(reserve)
        task.defer(reserve)
    end
end

function Window:_homeStats(list, opts, order, tab)
    local show = opts.Stats or { "Players", "Friends", "Execs", "Session", "FPS", "Ping" }
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = list,
    })
    local grid = create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(8, 8),
        CellSize = UDim2.new(1 / 6, -7, 0, 64),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = holder,
    })
    local values = {}
    local count = 0
    for _, name in ipairs(show) do
        local kind = STAT_TYPES[name]
        if kind and not values[name] then
            count += 1
            values[name] = statTile(holder, count, kind[1], kind[2])
        end
    end
    local function fit()
        local width = holder.AbsoluteSize.X / self.Scale.Scale
        local columns = math.max(math.min(count, width >= 520 and 6 or 3), 1)
        grid.CellSize = UDim2.new(1 / columns, -math.ceil(8 * (columns - 1) / columns), 0, 64)
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)

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
    return function()
        if values.FPS then
            values.FPS.Text = tostring(frames)
        end
        frames = 0
        if values.Ping then
            local ok, ping = pcall(function()
                return math.floor(LocalPlayer:GetNetworkPing() * 1000)
            end)
            values.Ping.Text = (ok and ping or 0) .. "ms"
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
                    TextSize = 11,
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
        PageTitle = opts.Title or ("Welcome to " .. self.Title .. "!"),
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
    self:_homeGame(list, 3)
    self:_homeExecutor(list, opts, 4)
    self:_homeLinks(list, opts, 5)

    if type(pages) == "table" then
        for _, page in ipairs(pages) do
            homePage(tab:SubTab({ Name = page.Name or page.Title or "Page", Icon = page.Icon }), page)
        end
    end

    refreshExpiry()
    refreshStats()
    task.spawn(function()
        while not self._destroyed and tab._page.Parent do
            task.wait(1)
            if self.Open and self.CurrentTab == tab then
                refreshStats()
                refreshExpiry()
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
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
        Parent = self._tabStack,
    })
    corner(button, UDim.new(0, 10))
    local buttonStroke = stroke(button, Theme.Stroke, 1)
    tab._button = button

    local hasIcon = opts.Icon ~= nil
    if hasIcon then
        local iconImage = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 9),
            Size = UDim2.fromOffset(18, 18),
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
        Position = UDim2.fromOffset(2, hasIcon and 31 or 0),
        Size = UDim2.new(1, -4, hasIcon and 0 or 1, hasIcon and 14 or 0),
        Text = tab.Name,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
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
        tween(pressScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
    end
    button.MouseEnter:Connect(function()
        if self.CurrentTab ~= tab and not usingTouch() then
            tween(button, { BackgroundTransparency = 0.4 }, 0.12)
            tween(buttonStroke, { Transparency = 0.5 }, 0.12)
        end
    end)
    button.MouseLeave:Connect(function()
        release()
        if self.CurrentTab ~= tab then
            tween(button, { BackgroundTransparency = 1 }, 0.2)
            tween(buttonStroke, { Transparency = 1 }, 0.2)
        end
    end)
    button.MouseButton1Down:Connect(function()
        tween(pressScale, { Scale = 0.94 }, 0.12)
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

-- A small accent badge on the tab's sidebar tile: a number or short text, or
-- true for a plain dot. nil, false, 0 or "" hides it.
function Tab:SetBadge(value)
    local show = value ~= nil and value ~= false and value ~= 0 and value ~= ""
    local badge = self._badge
    if not badge then
        if not show then
            return
        end
        badge = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -6, 0, 5),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0,
            TextColor3 = Theme.AccentDark,
            TextSize = 10,
            FontFace = Fonts.Bold,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            ZIndex = 3,
            Parent = self._button,
        })
        corner(badge, UDim.new(1, 0))
        padding(badge, 4, 4, 0, 0)
        self._badgeScale = create("UIScale", { Parent = badge })
        self._badge = badge
    end
    local wasShown = badge.Visible and self._badgeShown
    self._badgeShown = show
    badge.Visible = show
    if not show then
        return
    end
    if value == true then
        badge.AutomaticSize = Enum.AutomaticSize.None
        badge.Size = UDim2.fromOffset(8, 8)
        badge.Position = UDim2.new(1, -10, 0, 8)
        badge.Text = ""
    else
        badge.AutomaticSize = Enum.AutomaticSize.X
        badge.Size = UDim2.fromOffset(16, 16)
        badge.Position = UDim2.new(1, -6, 0, 5)
        badge.Text = tostring(value)
    end
    if not wasShown then
        self._badgeScale.Scale = 0.4
        tween(self._badgeScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
    end
end

function Tab:GetBadge()
    return self._badgeShown and (self._badge.Text ~= "" and self._badge.Text or true) or nil
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
        tween(indicator, { BackgroundTransparency = 0.35 }, 0.25)
    end
    tween(indicator, { Position = UDim2.fromOffset(8, targetY) }, 0.4, Enum.EasingStyle.Quint)
    -- The pill stretches while it travels and settles back when it lands.
    local pill = self._indicatorPill
    if pill then
        tween(pill, { Size = UDim2.fromOffset(3, 30) }, 0.16, Enum.EasingStyle.Quad)
        task.delay(0.16, function()
            tween(pill, { Size = UDim2.fromOffset(3, 20) }, 0.35, Enum.EasingStyle.Back)
        end)
    end
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
        tween(previous._label, { TextColor3 = Theme.Muted }, 0.2)
        if previous._icon then
            tintIcon(previous._icon, Theme.Muted, false, 0.2)
        end
        local outLayer = self._outLayer
        previous._page.Parent = outLayer
        self._outPage = previous._page
        outLayer.GroupTransparency = 0
        outLayer.Position = UDim2.fromOffset(0, 0)
        outLayer.Visible = true
        tween(outLayer, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) }, 0.18)
        task.delay(0.18, function()
            if self._transitionGeneration == generation then
                self:_settleOut()
            end
        end)
    end

    tween(tab._button, { BackgroundTransparency = 1 }, 0.2)
    tween(tab._stroke, { Transparency = 1 }, 0.2)
    tween(tab._label, { TextColor3 = Theme.Text }, 0.2)
    if tab._icon then
        tintIcon(tab._icon, Theme.Accent, true, 0.2)
        tab._icon.Size = UDim2.fromOffset(14, 14)
        tween(tab._icon, { Size = UDim2.fromOffset(18, 18) }, 0.4, Enum.EasingStyle.Back)
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
}
local WEATHER_NAMES = {
    rain = "Rain",
    snow = "Snow",
    ember = "Ember",
    embers = "Ember",
    fire = "Ember",
    hellfire = "Ember",
}
local RAIN_STREAK = Vector2.new(7 / 420, 151 / 263)
local weatherRandom = Random.new()

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
    label.ImageColor3 = particle.Color
        or (kind == "Rain" and Color3.fromRGB(190, 210, 245) or Color3.new(1, 1, 1))
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
    local field = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = layer,
    })
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
    self._weatherDensity = math.clamp(tonumber(opts.Density) or 1, 0, 3)
    self._weatherSpeed = math.clamp(tonumber(opts.Speed) or 1, 0.1, 3)
    self.Weather = weatherName(opts.Weather == nil and "Snow" or opts.Weather)
    self:_rebuildWeather()
    table.insert(self._frameSteps, function(deltaTime)
        self:_stepBackdrop(deltaTime)
    end)
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
    local size = self.Gui.AbsoluteSize
    for _ = 1, math.floor(definition.Count * self._weatherDensity + 0.5) do
        local particle = {
            Label = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Image = definition.Image,
                ImageTransparency = 1,
                ScaleType = definition.Stretch and Enum.ScaleType.Stretch or Enum.ScaleType.Fit,
                ZIndex = 2,
                Parent = self._weatherField,
            }),
        }
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
        return
    end
    local eased = 1 - (1 - fade) ^ 3
    local kind = self.Weather
    self._backdropTintFrame.BackgroundTransparency = 1 - self._backdropTint * eased
    self._backdropHeat.BackgroundTransparency = kind == "Ember"
        and 1 - (0.22 + math.sin(os.clock() * 2.1) * 0.05) * eased
        or 1

    -- The gust on restore: particles rush in fast and settle back.
    local kick = self._weatherKick
    self._weatherKick = math.max(kick - deltaTime * 1.3, 0)
    local speed = self._weatherSpeed * (1 + kick * kick * 2.5)
    local size = self.Gui.AbsoluteSize
    local width, height = size.X, size.Y
    for _, particle in ipairs(self._weatherParticles) do
        particle.Time += deltaTime
        particle.X += particle.VX * deltaTime * speed
        particle.Y += particle.VY * deltaTime * speed
        particle.Rotation += particle.Spin * deltaTime * speed
        local margin = math.max(particle.Size.X, particle.Size.Y)
        if (particle.VY > 0 and particle.Y > height + margin) or (particle.VY < 0 and particle.Y < -margin) then
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
        if kind == "Ember" then
            -- Flicker, and burn out on the way up.
            alpha *= math.clamp(particle.Y / (height * 0.85), 0, 1) ^ 0.6
            alpha *= 0.75 + math.sin(particle.Time * 9 + particle.Phase) * 0.25
        end
        local label = particle.Label
        label.Position = UDim2.fromOffset(x, particle.Y)
        label.Rotation = particle.Rotation
        label.ImageTransparency = 1 - alpha * eased
    end
end

function Window:_refreshBackdrop(gust)
    if not self._backdrop then
        return
    end
    local shown = self._backdropEnabled and self._introDone and self.Open and not self.Minimized and not self._destroyed
    if shown and not self._backdropShown then
        self._backdrop.Visible = true
        if self._backdropFade <= 0 then
            local size = self.Gui.AbsoluteSize
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

-- Minimize: the window folds into a floating bar that keeps the essentials in
-- view (current tab, running toggles, pinned statuses) and unfolds back into
-- the window from wherever the bar was dragged.

local MINI_HEIGHT = 46
local MAX_PINNED = 3

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
    local ghostCorner = corner(ghost, UDim.new(0, radius))
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
    local bar = create("CanvasGroup", {
        Size = UDim2.fromOffset(0, MINI_HEIGHT),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(bar, UDim.new(0, 12))
    local barStroke = stroke(bar, Theme.Stroke)
    edgeHighlight(bar)
    -- Thin accent line along the bottom edge that fades out at both ends.
    local accentLine = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.new(0.8, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = bar,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = accentLine,
    })
    local row = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = bar,
    })
    padding(row, 14, 8)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = row,
    })
    local function inline(order, gap)
        local frame = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = row,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap),
            Parent = frame,
        })
        return frame
    end
    local function divider(order)
        return create("Frame", {
            Size = UDim2.fromOffset(1, 18),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            LayoutOrder = order,
            Parent = row,
        })
    end

    local brand = inline(1, 8)
    local logo = create("ImageLabel", {
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = brand,
    })
    applyIcon(logo, self._logoIcon, true)
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = self.Title,
        TextSize = 14,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = brand,
    })

    divider(2)
    local where = inline(3, 6)
    local tabIcon = create("ImageLabel", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = where,
    })
    local tabName = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = where,
    })

    local active = create("Frame", {
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.88,
        BorderSizePixel = 0,
        LayoutOrder = 4,
        Visible = false,
        Parent = row,
    })
    corner(active, UDim.new(1, 0))
    stroke(active, Theme.Accent, 0.65)
    padding(active, 9, 10)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = active,
    })
    local activeDot = create("Frame", {
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        LayoutOrder = 1,
        Parent = active,
    })
    corner(activeDot, UDim.new(1, 0))
    TweenService:Create(activeDot, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        BackgroundTransparency = 0.7,
    }):Play()
    local activeLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 11,
        TextColor3 = Theme.Accent,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = active,
    })

    local pinnedDivider = divider(5)
    local pinned = inline(6, 12)

    -- Reminds PC players which key brings the window back.
    local keyChip = create("Frame", {
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        LayoutOrder = 7,
        Visible = false,
        Parent = row,
    })
    corner(keyChip, UDim.new(0, 6))
    stroke(keyChip, Theme.Stroke, 1)
    padding(keyChip, 7, 7)
    local keyLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 11,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = keyChip,
    })

    local expand = create("Frame", {
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        LayoutOrder = 8,
        Parent = row,
    })
    corner(expand, UDim.new(0, 8))
    local expandIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = expand,
    })
    applyIcon(expandIcon, "maximize-2")

    -- One invisible button over the whole bar: click restores, drag moves.
    local hit = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = bar,
    })
    local barScale = create("UIScale", { Parent = bar })
    self._miniScale = barScale
    hit.MouseEnter:Connect(function()
        tween(barStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(expand, { BackgroundTransparency = 0.1 }, 0.15)
        tween(expandIcon, { ImageColor3 = Theme.Accent }, 0.15)
        tween(barScale, { Scale = 1.02 }, 0.25, Enum.EasingStyle.Quint)
    end)
    -- Also run on restore: the bar hides under the pointer, so MouseLeave
    -- never fires and the hover look would stick for the next minimize.
    local function unhover()
        tween(barStroke, { Color = Theme.Stroke }, 0.25)
        tween(expand, { BackgroundTransparency = 0.5 }, 0.25)
        tween(expandIcon, { ImageColor3 = Theme.Muted }, 0.25)
        tween(barScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
    end
    hit.MouseLeave:Connect(unhover)
    self._miniUnhover = unhover

    local dragging, moved = false, false
    local grab = Vector2.zero
    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - bar.AbsolutePosition
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging or not isMove(input) then
            return
        end
        if not self.Minimized then
            dragging = false
            return
        end
        local point = pointerPosition() - grab - gui.AbsolutePosition
        if (point - (bar.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
            moved = true
        end
        if moved then
            bar.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - bar.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - bar.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if dragging and isPress(input) then
            dragging = false
            if moved then
                self._miniPosition = bar.AbsolutePosition - gui.AbsolutePosition
            elseif self.Minimized then
                self:Restore()
            end
        end
    end))

    local chips = {}
    function self:_refreshMini()
        local tab = self.CurrentTab
        tabName.Text = tab and tab.Name or ""
        where.Visible = tab ~= nil
        if tab and tab._icon then
            tabIcon.Visible = true
            tabIcon.Image = tab._icon.Image
            tabIcon.ImageRectOffset = tab._icon.ImageRectOffset
            tabIcon.ImageRectSize = tab._icon.ImageRectSize
            tween(tabIcon, { ImageColor3 = tab._icon:GetAttribute("CustomIcon") and Color3.new(1, 1, 1) or Theme.Muted }, 0)
            local source = tab._icon:FindFirstChild("CustomIconScale")
            local scaler = tabIcon:FindFirstChild("CustomIconScale")
            if source and not scaler then
                scaler = create("UIScale", { Name = "CustomIconScale", Parent = tabIcon })
            end
            if scaler then
                scaler.Scale = source and source.Scale or 1
            end
        else
            tabIcon.Visible = false
        end
        local running = 0
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true then
                running += 1
            end
        end
        active.Visible = running > 0
        activeLabel.Text = running .. " on"
        keyChip.Visible = not TOUCH and typeof(self.Keybind) == "EnumItem"
        if keyChip.Visible then
            keyLabel.Text = keyName(self.Keybind)
        end

        local list = {}
        for _, handle in ipairs(self._pinned) do
            if not handle._isShown or handle:_isShown() then
                table.insert(list, handle)
            end
        end
        local shown = math.min(#list, MAX_PINNED)
        pinnedDivider.Visible = shown > 0
        pinned.Visible = shown > 0
        for index = 1, math.max(shown, #chips) do
            local handle = list[index]
            local chip = chips[index]
            if index <= shown then
                if not chip then
                    local frame = create("Frame", {
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        BackgroundTransparency = 1,
                        LayoutOrder = index,
                        Parent = pinned,
                    })
                    create("UIListLayout", {
                        FillDirection = Enum.FillDirection.Horizontal,
                        VerticalAlignment = Enum.VerticalAlignment.Center,
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 5),
                        Parent = frame,
                    })
                    local key = label({
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        TextSize = 11,
                        TextColor3 = Theme.Muted,
                        TextTruncate = Enum.TextTruncate.None,
                        LayoutOrder = 1,
                        Parent = frame,
                    })
                    local value = label({
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        TextSize = 12,
                        TextTruncate = Enum.TextTruncate.None,
                        LayoutOrder = 2,
                        Parent = frame,
                    })
                    chip = { Frame = frame, Key = key, Value = value }
                    chips[index] = chip
                end
                chip.Frame.Visible = true
                chip.Key.Text = handle.Name
                chip.Value.Text = handle:Text()
            elseif chip then
                chip.Frame.Visible = false
            end
        end
    end

    -- Keep the bar reachable when the screen shrinks or rotates.
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not bar.Visible then
            return
        end
        local position = bar.AbsolutePosition - gui.AbsolutePosition
        local clamped = Vector2.new(
            math.clamp(position.X, 8, math.max(gui.AbsoluteSize.X - bar.AbsoluteSize.X - 8, 8)),
            math.clamp(position.Y, 8, math.max(gui.AbsoluteSize.Y - bar.AbsoluteSize.Y - 8, 8))
        )
        if clamped ~= position then
            bar.Position = UDim2.fromOffset(clamped.X, clamped.Y)
            self._miniPosition = clamped
        end
    end))

    self.MiniBar = bar
    return bar
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
    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, 10)
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Scale, { Scale = (self._fitScale or 1) * 0.985 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
    -- Laid out now while fully transparent, so the bar's automatic width is
    -- known by the time the ghost needs it.
    bar.Position = UDim2.fromOffset(-10000, -10000)
    bar.Visible = true
    bar.GroupTransparency = 1

    task.delay(0.11, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        -- 2. Covered by the ghost, the window is hidden and the ghost folds
        -- down into the bar's spot.
        self.Root.Visible = false
        self.Scale.Scale = self._fitScale or 1
        local size = bar.AbsoluteSize
        local target = self._miniPosition or fromPosition
        target = Vector2.new(
            math.clamp(target.X, 8, math.max(gui.AbsoluteSize.X - size.X - 8, 8)),
            math.clamp(target.Y, 8, math.max(gui.AbsoluteSize.Y - size.Y - 8, 8))
        )
        bar.Position = UDim2.fromOffset(target.X, target.Y)
        morphGhost(ghost, ghostCorner, target, size, 12, 0.36)
        task.delay(0.3, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            -- 3. The bar fades in on top as the ghost lands.
            self._miniScale.Scale = 0.97
            tween(self._miniScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(bar, { GroupTransparency = 0 }, 0.18, Enum.EasingStyle.Quad)
            dissolve(self, ghost, ghostStroke, 0.2)
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
    -- minimize was interrupted, otherwise the bar.
    local fromPosition, fromSize = target, size
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    elseif bar and bar.Visible then
        fromPosition = bar.AbsolutePosition - gui.AbsolutePosition
        fromSize = bar.AbsoluteSize
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

    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, 12)
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    morphGhost(ghost, ghostCorner, target, size, 10, 0.4)
    tween(self.Shadow, { ImageTransparency = 0.6 }, 0.45)

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
        local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition or centre - shrunk / 2, fromSize or shrunk, 10)
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        morphGhost(ghost, ghostCorner, centre - size / 2, size, 10, 0.3)
        tween(self.Shadow, { ImageTransparency = 0.6 }, 0.3)
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
        local ghost, ghostStroke, ghostCorner = makeGhost(self, position, current, 10)
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
            morphGhost(ghost, ghostCorner, centre - shrunk / 2, shrunk, 10, 0.2)
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

local Airflow = Library

Airflow:LoadFont({ Name = "ValleySans" }) -- downloads the font once into workspace/AirFlowFonts and uses it everywhere
Airflow:SetDefaultTheme("Obsidian") -- starting theme: any preset name or a colour table. A default the player sets in the theme manager wins

local Window = Airflow:CreateWindow({
    Name = "Airflow Hub",
    LoadingSubtitle = "Example",
    -- Icon = 132608042600488, -- leave out for the built-in OuroFlow mark (theme tinted); any asset id (number or "rbxassetid://..."), shown in its own colours
    ToggleUIKeybind = "RightControl", -- key that hides and shows the window
    -- examples: "RightShift", "RightControl", "LeftAlt", "Insert", "Home", "F1", "Backquote"
    -- Enum.KeyCode values also work: ToggleUIKeybind = Enum.KeyCode.RightShift
    ConfigurationSaving = { Enabled = true, FolderName = "AirflowExample", FileName = "default" },
    ToggleButton = { Platform = "Mobile", Icon = "layout-grid" }, -- square button that minimizes / restores. "Both" shows it on PC too
    Backdrop = { Weather = "Snow", Tint = 0.45 }, -- black tint + weather behind the open window: "Rain", "Snow", "Hell Fire" or "None". false turns it off
    Home = {
        Tier = "Free",
        Expiry = os.time() + 12 * 3600, -- countdown under the tier badge. A string or a function also works
        Discord = "dsc.gg/airflowscript",
        Website = "airflowscript.com",
        Stats = { "Players", "Friends", "Execs", "Session", "FPS", "Ping" },
    },
})

-- Tabs hold sub tabs, sub tabs hold groupboxes, groupboxes hold elements.

local Farm = Window:CreateTab({ Name = "Farm", Icon = "swords" })
Farm:SetBadge("New") -- a number, short text, or true for a dot. nil hides it

local MobFarm = Farm:CreateSubTab({ Name = "Mob Farm" })

local Mobs = MobFarm:AddLeftGroupbox({ Name = "Mob Farm", Icon = "crosshair" })

Mobs:CreateToggle({
    Name = "Auto Farm Mobs",
    CurrentValue = false,
    Flag = "AutoFarmMobs",
    Callback = function(Value)
        print("auto farm", Value)
    end,
})

Mobs:CreateDropdown({
    Name = "Mobs",
    Options = { "Bandit", "Wolf", "Demon", "Oni", "Ghoul", "Slayer", "Hashira" },
    MultipleOptions = true,
    CurrentOption = {},
    Flag = "Mobs",
    Callback = function(Options)
        print("mobs", table.concat(Options, ", "))
    end,
})

Mobs:CreateToggle({
    Name = "Farm Nearest Mob",
    CurrentValue = false,
    Flag = "FarmNearest",
    Callback = function(Value)
        print("nearest", Value)
    end,
})

Mobs:CreateSlider({
    Name = "Attack Distance",
    Range = { 0, 30 },
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 8,
    Flag = "AttackDistance",
    Callback = function(Value)
        print("distance", Value)
    end,
})

local Other = MobFarm:AddRightGroupbox({ Name = "Other Features", Icon = "sparkles" })

Other:CreateToggle({
    Name = "Auto Loot Drops",
    CurrentValue = false,
    Flag = "AutoLoot",
    Callback = function(Value)
        print("loot", Value)
    end,
})

Other:CreateToggle({
    Name = "Auto Chests",
    CurrentValue = false,
    Flag = "AutoChests",
    Callback = function(Value)
        print("chests", Value)
    end,
})

Other:CreateSlider({
    Name = "Loot Range",
    Range = { 0, 500 },
    Increment = 10,
    CurrentValue = 250,
    Flag = "LootRange",
    Callback = function(Value)
        print("loot range", Value)
    end,
})

local Movement = MobFarm:AddRightGroupbox({ Name = "Movement", Icon = "move", Collapsed = true })

Movement:CreateStepper({
    Name = "Tween Speed",
    Range = { 1, 10 },
    Increment = 1,
    CurrentValue = 5,
    Flag = "TweenSpeed",
    Callback = function(Value)
        print("speed", Value)
    end,
})

Movement:CreateKeybind({
    Name = "Stop Farming",
    CurrentKeybind = "X",
    Flag = "StopKey",
    Callback = function()
        print("stop")
    end,
})

local BossFarm = Farm:CreateSubTab({ Name = "Boss Farm" })

local Bosses = BossFarm:AddLeftGroupbox({ Name = "Bosses", Icon = "skull" })

Bosses:CreateDropdown({
    Name = "Boss",
    Options = { "Rui", "Akaza", "Doma", "Kokushibo" },
    CurrentOption = "Rui",
    Flag = "Boss",
    Callback = function(Option)
        print("boss", Option)
    end,
})

Bosses:CreateToggle({
    Name = "Auto Farm Boss",
    CurrentValue = false,
    Flag = "AutoBoss",
    Callback = function(Value)
        print("boss farm", Value)
    end,
})

Bosses:CreateLabel("Status: idle")

local BossSettings = BossFarm:AddRightGroupbox({ Name = "Settings", Icon = "settings-2" })

BossSettings:CreateInput({
    Name = "Webhook",
    PlaceholderText = "https://",
    Flag = "BossWebhook",
    Callback = function(Text)
        print("webhook", Text)
    end,
})

BossSettings:CreateColorPicker({
    Name = "Highlight",
    Color = Color3.fromRGB(235, 199, 246),
    Flag = "BossColor",
    Callback = function(Color)
        print("color", Color)
    end,
})

-- Status labels in every style. Pin = true also shows one on the minimized bar.
local Run = Farm:CreateSubTab({ Name = "Run" })

local RunInfo = Run:AddLeftGroupbox({ Name = "Run Info", Icon = "activity" })
local floor = 0
RunInfo:CreateStatuses({
    { Name = "Floor", Pin = true, Update = function()
        floor += 1
        return floor
    end },
    { Name = "Points", Value = "-" },
    { Name = "Hearts", Value = 3 },
    { Name = "EnemiesLeft", Value = "-" },
    { Name = "Map", Value = "Forest" },
}, { Style = "Plain" })

local Progress = Run:AddRightGroupbox({ Name = "Progress", Icon = "trending-up" })
Progress:CreateStatus({ Name = "Level", Value = 179, Style = "Stat" })
Progress:CreateStatus({ Name = "Exp", Value = "7859/10740", Style = "Bar" })
Progress:CreateStatus({ Name = "Wen", Value = 270070, Style = "Row", Pin = true })
Progress:CreateStatus({ Name = "Quests done", Value = 0, Style = "Row" })

local Live = Run:AddLeftGroupbox({ Name = "Live", Icon = "radio" })
local states = { { "Farming", "Success" }, { "Walking", "Warning" }, { "Stuck", "Error" } }
Live:CreateStatus({ Name = "Bot", Style = "Dot", Update = function()
    local state = states[math.floor(os.clock() / 3) % #states + 1]
    return state[1], state[2] -- a second string return sets the tone
end })
Live:CreateStatus({ Name = "Server", Value = "Healthy", Style = "Badge", Tone = "Success" })
Live:CreateStatus({ Name = "Rank", Style = "Bar", Tone = "Warning", Update = function()
    return (os.clock() * 100) % 7000, 7000 -- a number second return sets the max
end, UpdateRate = 0.5 })

-- Status list: grows with its rows up to MaxRows, then scrolls inside itself.
local Hotbar = Run:AddRightGroupbox({ Name = "Hotbar", Icon = "zap" })
local skills = {
    "Z", "X", "C", "V", "B", "N", "M", "F",
}
Hotbar:CreateStatusList({
    Name = "Skills",
    MaxRows = 5,
    EmptyText = "no skills on the hotbar yet",
    UpdateRate = 0.5,
    Update = function()
        local rows = { "Z Compound Eye Hexagon (on target, up to 3s)" } -- a plain string is one wrapped line
        for index = 2, #skills do
            local cooldown = math.floor((os.clock() + index * 3) % 15)
            rows[index] = {
                Text = skills[index] .. " Skill " .. index,
                Value = cooldown == 0 and "ready" or ("cooldown " .. cooldown .. "s"),
                Tone = cooldown == 0 and "Success" or (cooldown > 10 and "Warning" or nil),
            }
        end
        return rows -- 8 rows with MaxRows = 5, so the list scrolls
    end,
})

-- Dependent controls: the slider only shows while the toggle is on.
local Charge -- declared first so the toggle's callback can reach it
Hotbar:CreateToggle({
    Name = "Hold Skills",
    CurrentValue = false,
    Flag = "HoldSkills",
    Callback = function(Value)
        Charge:SetVisible(Value)
    end,
})
Charge = Hotbar:CreateSlider({
    Name = "Charge Distance",
    Range = { 5, 60 },
    Increment = 1,
    CurrentValue = 20,
    Visible = false, -- starts hidden, still saves and loads with the config
    Flag = "ChargeDistance",
})

Farm:CreateSubTab({ Name = "Quests" }) -- an empty sub tab shows the empty state

local Shop = Window:CreateTab({ Name = "Shop", Icon = "store" })

local Weapons = Shop:AddLeftGroupbox({ Name = "Weapons", Icon = "sword" })

Weapons:CreateDropdown({
    Name = "Weapon",
    Options = { "Fancy Katana", "Nichirin Blade", "Kusarigama" },
    CurrentOption = "Fancy Katana",
    Flag = "Weapon",
    Callback = function(Option)
        print("weapon", Option)
    end,
})

Weapons:CreateLabel("Price: 1500 wen (owned)")
Weapons:CreateLabel("Seller: Raze")

Weapons:CreateButton({
    Name = "Buy Weapon",
    Callback = function()
        print("buy weapon")
    end,
})

local Items = Shop:AddRightGroupbox({ Name = "Items", Icon = "shopping-bag" })

Items:CreateToggle({
    Name = "Auto Buy",
    CurrentValue = false,
    Flag = "AutoBuy",
    Callback = function(Value)
        print("auto buy", Value)
    end,
})

Items:CreateButton({
    Name = "Buy Selected",
    Style = "Primary",
    Callback = function()
        print("buy selected")
    end,
})

local Elements = Window:CreateTab({ Name = "Elements", Desc = "One of everything, full width", Icon = "layout-grid" })

Elements:CreateSection("Elements added straight to a tab stack as full width cards")

Elements:CreateButton({
    Name = "Example button",
    Desc = "Example description",
    Icon = "mouse-pointer-click",
    Callback = function()
        print("button")
    end,
})

Elements:CreateToggle({
    Name = "Example toggle",
    Desc = "Example description",
    CurrentValue = false,
    Flag = "ExampleToggle",
    Callback = function(Value)
        print("toggle", Value)
    end,
})

Elements:CreateSlider({
    Name = "Example slider",
    Range = { 0, 100 },
    Increment = 1,
    Suffix = "%",
    CurrentValue = 50,
    Flag = "ExampleSlider",
    Callback = function(Value)
        print("slider", Value)
    end,
})

Elements:CreateProgress({
    Name = "Example progress",
    CurrentValue = 0.65,
})

Elements:CreateParagraph({
    Title = "Example paragraph",
    Content = "Longer text that wraps across several lines.",
})

local Popups = Window:CreateTab({ Name = "Popups", Desc = "Notifications and dialogs", Icon = "bell" })

local Toasts = Popups:AddLeftGroupbox({ Name = "Toasts", Icon = "bell" })

Toasts:CreateButton({
    Name = "Example notification",
    Callback = function()
        Airflow:Notify({
            Title = "Example",
            Content = "Example notification",
            Icon = "bell",
            Type = "Success",
            Duration = 3,
        })
    end,
})

local Dialogs = Popups:AddRightGroupbox({ Name = "Dialogs", Icon = "message-square" })

Dialogs:CreateButton({
    Name = "Example confirm",
    Callback = function()
        Airflow:Confirm({
            Title = "Example confirm",
            Content = "Are you sure?",
            ConfirmText = "Yes",
            CancelText = "No",
            Callback = function()
                print("confirmed")
            end,
        })
    end,
})

Dialogs:CreateButton({
    Name = "Example dialog",
    Callback = function()
        Airflow:Dialog({
            Title = "Example dialog",
            Content = "Pick one.",
            Buttons = {
                { Title = "One", Callback = function() print("one") end },
                { Title = "Two", Callback = function() print("two") end },
                { Title = "Three", Variant = "Primary", Callback = function() print("three") end },
            },
        })
    end,
})

local Settings = Window:CreateTab({ Name = "Settings", Icon = "settings" })

local Interface = Settings:AddLeftGroupbox({ Name = "Interface", Icon = "monitor" })

Interface:CreateKeybind({
    Name = "Toggle UI",
    CurrentKeybind = "RightControl",
    OnChanged = function(Key)
        Window:SetKeybind(Key)
    end,
})

Interface:CreateDropdown({
    Name = "Toggle button",
    Options = { "Mobile only", "Mobile & PC" },
    CurrentOption = "Mobile only",
    AllowNone = false,
    Flag = "ToggleButtonPlatform",
    Callback = function(Option)
        Window:SetToggleButtonPlatform(Option == "Mobile & PC" and "Both" or "Mobile")
    end,
})

Interface:CreateToggle({
    Name = "Backdrop",
    CurrentValue = true,
    Flag = "Backdrop",
    Callback = function(Value)
        Window:SetBackdrop(Value)
    end,
})

Interface:CreateSlider({
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

Interface:CreateSlider({
    Name = "Weather Density",
    Range = { 25, 200 },
    Increment = 25,
    Suffix = "%",
    CurrentValue = 100,
    Flag = "WeatherDensity",
    Callback = function(Value)
        Window:SetWeatherDensity(Value / 100)
    end,
})

Interface:CreateButton({
    Name = "Unload",
    Icon = "power",
    Callback = function()
        Airflow:Confirm({
            Title = "Unload?",
            ConfirmText = "Unload",
            Callback = function()
                Window:Destroy()
            end,
        })
    end,
})

Settings:CreateConfigManager({ Name = "Configs", Side = "Left" }) -- builds its own groupbox
Settings:CreateThemeManager({ Name = "Themes", Side = "Right" })

Window:LoadAutoload() -- loads the config marked with Set Autoload, if there is one
