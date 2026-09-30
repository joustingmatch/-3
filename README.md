# Airflow UI

> A UI library for Roblox. Windows, tabs, sub tabs, collapsible groupboxes and fourteen elements with lucide icons and eased motion.

```lua
local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"))()
```

Every constructor also works without the `Create` prefix. `Tab:Toggle` is the same as `Tab:CreateToggle`. Every element handle also has `Destroy()`, which removes the card, its listeners and its flag, and `SetVisible(bool)` / `IsVisible()`. Every constructor takes `Visible = false` to start hidden (see [Visibility](#visibility)) and `Tooltip` to explain itself on hover (see [Tooltips](#tooltips)).

---

## Window

> The root container. Sidebar with tabs and your profile, a content area with search, the close button and the notification stack.

```lua
local Window = Airflow:CreateWindow({
    Name = "Airflow",
    LoadingSubtitle = "by Pookie",
    Icon = "wind",
    ToggleUIKeybind = "RightControl",
    Size = UDim2.fromOffset(760, 520),
    MinSize = Vector2.new(480, 360),
    MaxSize = Vector2.new(1100, 800),
    MaxNotifications = 4,
    KeepOnScreen = true,
    OpenButton = { Title = "Airflow", Icon = "wind" },
    ToggleButton = { Platform = "Mobile", Icon = "layout-grid" },
    Backdrop = { Weather = "Snow", Tint = 0.45 },
    Profile = true,
    Search = true,
    Loading = {
        Enabled = true,
        Title = "Airflow",
        Text = "Starting",
        Steps = { "Preparing interface", "Loading icons", "Almost there" },
        Duration = 1.6,
    },
    Disclaimer = {
        Title = "Before you start",
        Text = "Use at your own risk. We are not responsible for bans.",
        Id = "risk-v1",
    },
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "MyHub",
        FileName = "default",
    },
    Home = {
        Tier = "Free",
        Discord = "dsc.gg/myhub",
        Website = "myhub.com",
    },
    Parent = game:GetService("CoreGui"),
})

Window:Toggle(false)
```

Drag any empty area to move it and the grip in the bottom-right corner to resize it. While resizing, the top-left corner stays put and the size follows the pointer through a spring, so it glides and settles instead of snapping. The window only renders through a CanvasGroup while it fades in or out, so resizing never re-renders it into a texture. It scales itself down on small screens and stays inside the viewport.

The button in the top-right minimizes the window: it folds into a small orb with the logo, docked to whichever side of the screen the window was nearer. Each running toggle circles the orb as a dot (up to eight), the lead dot bright and the tail fading behind it. Left alone for a couple of seconds it tucks half behind the edge and dims, then slides back out when the cursor comes near. Hover it to see the current tab, how many toggles are on, up to six pinned [statuses](#status) with live values, and the key that reopens the window. Click or tap it (or press the hide key) and it unfolds back into the window. Drag it anywhere and let go: it snaps to the nearer side and remembers where you left it.

The toggle button is a small rounded square floating on the left edge. Tapping it minimizes the window, tapping it again restores it, and it also brings back a window hidden with the hide key. Drag it anywhere. Its border lights up in the accent colour while the window is folded away. By default it only shows on touch devices; `Platform = "Both"` shows it on PC too.

The sidebar is an inset rounded rail: the logo on top, then one tile per tab with its icon over its name, with a highlight that glides to the selected tile, an accent pill beside it, and fades at the ends when the list scrolls. The selected tile scrolls into view. `Tab:SetBadge(value)` puts a small accent badge on a tile: a number or short text, `true` for a dot, `nil` to hide it. The bottom shows the player's headshot, display name and the current game. Clicking it opens the home tab.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Airflow"` | Title in the sidebar header. Also names the ScreenGui. |
| `LoadingSubtitle` | string | — | Small line under the title. |
| `Icon` | string \| number \| table | OuroFlow mark (theme tinted) | Lucide name, asset id, or `{ Image, RectOffset, RectSize, Tint }`. See [Icons](#icons). |
| `ToggleUIKeybind` | string \| KeyCode | `"RightControl"` | Hides and shows the window. `"RightShift"`, `"LeftAlt"`, `"Insert"`, `"F1"`, or an `Enum.KeyCode`. |
| `Size` | UDim2 | `760 × 520` | Starting size. |
| `MinSize` | Vector2 | `480 × 360` | Smallest size the resize grip allows. |
| `MaxSize` | Vector2 | unlimited | Largest size the resize grip allows. |
| `MaxNotifications` | number | `4` | Oldest toast is dismissed past this. |
| `KeepOnScreen` | boolean | `true` | Nudge the window back inside the viewport after a drag, resize or screen change. |
| `Transparent` | boolean | `false` | See-through window body and sidebar. |
| `Background` | string | — | Background image behind the window content. Same sources as `SetBackground`. |
| `BackgroundTransparency` | number | `0.35` | How much of the theme background colour shows through the image, 0 to 1. |
| `DragSkeleton` | boolean | `true` | While dragging, an accent outline follows the pointer and the window glides into it on release. `false` drags the window itself. |
| `OpenButton` | boolean \| table | touch-only devices without a toggle button | Floating pill that reopens the window. `true` / `false` to force, `{ Title, Icon }` to customise. |
| `ToggleButton` | boolean \| table | `{ Platform = "Mobile" }` | Square button that minimizes and restores the window. `false` removes it. |
| `ToggleButton.Platform` | string | `"Mobile"` | `"Mobile"` shows it on touch devices only, `"Both"` on PC and mobile. |
| `ToggleButton.Icon` | string \| number \| table | `"layout-grid"` | Any [icon](#icons). |
| `ToggleButton.Enabled` | boolean | `true` | `false` builds it hidden, to show later with `SetToggleButton(true)`. |
| `ToggleButton.Position` / `Size` | UDim2 / number | left edge / `56` touch, `50` PC | Starting position and side length. |
| `Backdrop` | boolean \| table | `{ Weather = "Snow" }` | Black tint over the game while the window is up, with weather drifting through it. It fades out when the window is minimized or hidden and sweeps back in with a gust on restore. `false` removes it. |
| `Backdrop.Weather` | string | `"Snow"` | `"Snow"`, `"Rain"`, `"Hell Fire"` (embers rising from a red glow), `"Sakura"` (pink petals that flip as they drift down), `"Fireflies"` (glowing specks that wander, pulse and fade), `"Matrix"` (falling columns of shifting green glyphs) or `"None"` for the tint alone. |
| `Backdrop.Tint` | number | `0.45` | Tint strength, `0` to `1`. |
| `Backdrop.Dim` | boolean | `true` | `false` starts with the tint off and only the weather showing. |
| `Backdrop.Mode` | string | `"Screen"` | `"Screen"` drifts the weather across the whole screen, `"UI"` keeps it inside the window behind its content. |
| `Backdrop.Density` / `Speed` | number | `1` / `1` | Particle count and fall speed multipliers. |
| `Backdrop.Enabled` | boolean | `true` | `false` builds it off, to turn on later with `SetBackdrop(true)`. |
| `UIScale` | number | `1` | Size of the whole window, `0.6` to `1.5`. The window still shrinks further when it wouldn't fit the screen. Players can change it in the [theme manager](#theme). |
| `Density` | string | `"Default"` | `"Compact"`, `"Default"` or `"Comfortable"`: the spacing between cards, groupboxes and groupbox rows. Shared by every window, like the theme. |
| `Profile` | boolean | `true` | Player card at the bottom of the sidebar. |
| `Search` | boolean | `true` | Search box in the top-right of the content area. See [Search](#search). |
| `Loading` | boolean \| table | `true` | Loading card before the window morphs in. `false` skips it. |
| `UnsupportedExecutor` | table \| false | on | When the executor is off `SupportedExecutors` (window or `Home` option) or, without a list, lacks the file, clipboard or request functions, the loading card turns into a warning with **Exit** and **Continue anyway** before the window opens. Shown even with `Loading = false`. Ticking **Don't ask again on this executor** before Continue saves the executor's name to `unsupported_skip.txt` in the `ConfigurationSaving` folder, and the warning is skipped while that executor is used (a different executor, or resetting the folder, brings it back). The tick box only shows when the executor can write files. `{ Title, Text, Block = true }` changes the wording or drops Continue (and the tick box); `false` turns it off. |
| `Loading.Title` | string | `Name` | Title on the card. |
| `Loading.Text` | string | `LoadingSubtitle` | First status line. |
| `Loading.Steps` | table | 3 built-in lines | Status lines cycled over the duration. |
| `Loading.Duration` | number | `1.6` | Seconds before the window appears. |
| `Disclaimer` | string \| table | — | Custom notice shown on the loading card after the executor warning, before the window opens; the player must press **I understand** to continue or **Exit** to close the script. Shown even with `Loading = false`. A string is just the text; a list of them shows one card after another. See the fields below. `Disclaimers` works too. |
| `Disclaimer.Title` / `Text` | string | `"Disclaimer"` / — | Heading and body. Long text scrolls inside the card. |
| `Disclaimer.Subtitle` | string | — | Small coloured line under the title. |
| `Disclaimer.Icon` / `Color` | string / Color3 | `"info"` / accent | Badge icon (any Lucide name or asset id) and its tint, e.g. `Color3.fromRGB(240, 176, 108)` for a warning look. |
| `Disclaimer.AcceptText` / `DeclineText` | string | `"I understand"` / `"Exit"` | Button labels. `DeclineText = false` drops Exit so the card can only be acknowledged. |
| `Disclaimer.Remember` | boolean | `true` | Offers a **Don't show again** tick box (when the executor can write files). Ticked, the disclaimer's `Id` is saved to `disclaimers.txt` in the `ConfigurationSaving` folder and it is skipped next time. `false` shows it on every run. |
| `Disclaimer.RememberText` | string | `"Don't show again"` | Tick box label. |
| `Disclaimer.Block` | boolean | `false` | `true` leaves only **Exit** (no accept button, no tick box), for a hard stop such as a missing requirement. It is never remembered. |
| `Disclaimer.Id` | string | hash of title and text | Key saved by the tick box. Without it, rewording the disclaimer shows it again; set an `Id` (and bump it) to control that yourself. |
| `Disclaimer.Callback` | function | — | Called with `true` on accept or `false` on Exit. |
| `ConfigurationSaving` | table | — | See [Configs](#configs). |
| `Home` | boolean \| table | `{}` | The built-in first tab. `false` removes it. See [Home](#home). |
| `Theme` / `DefaultTheme` | string \| table | — | Starting theme, same as `Airflow:SetDefaultTheme`. A default the player saved in the theme manager wins. See [Theme](#theme). |
| `Parent` | Instance | `gethui()` / CoreGui | Where the ScreenGui goes. Falls back to PlayerGui. |

### Handle

| Member | Description |
| --- | --- |
| `.Open` | Whether the window is shown. |
| `.CurrentTab` | The selected tab. |
| `.Tabs` | Array of tabs. |
| `.Home` | The home tab, unless `Home = false`. |
| `.SearchBox` | The search TextBox. |
| `Toggle(open?)` | Show, hide, or flip. Restores the window when minimized. |
| `Minimize()` / `Restore()` / `SetMinimized(bool)` | Fold into the orb and back. |
| `.Minimized` / `.MiniBar` | Whether it's minimized, and the orb itself. |
| `SetToggleButton(enabled)` | Show or hide the toggle button. |
| `SetToggleButtonPlatform(platform)` | `"Mobile"` or `"Both"`. |
| `SetToggleButtonIcon(icon)` | Swap its icon. |
| `.ToggleButton` | The toggle button, when it was built. |
| `SetBackdrop(enabled)` | Turn the tint and weather on or off. |
| `SetWeather(name)` / `.Weather` | `"Snow"`, `"Rain"`, `"Hell Fire"`, `"Sakura"`, `"Fireflies"`, `"Matrix"` or `"None"`. `.Weather` reads `"Ember"` for hell fire. |
| `SetBackdropTint(amount)` | Tint strength, `0` to `1`. |
| `SetDim(bool)` | Turn the tint on or off. The weather keeps running. |
| `SetWeatherDensity(n)` / `SetWeatherSpeed(n)` | Particle count and speed multipliers. |
| `SetKeybind(keyCode)` | Change the hide key. Updates the chip on the home tab. |
| `SetKeepOnScreen(enabled)` | Turn the viewport clamp on or off. |
| `SetDragSkeleton(enabled)` | Turn the drag outline on or off. |
| `SetTransparent(enabled)` / `.Transparent` | See-through window on or off. |
| `SetBackground(source)` / `.Background` | Background image. `source` is a preset name (`Library.BackgroundPresets`: Deep Violet, Blood Red, Cyanic, Amber Glow, Bloomings, Lavender Pink), an image asset id or `rbxassetid://` link (an Image id, not a Decal id), an http(s) image link (downloaded once to `<FolderName>/backgrounds/cache`, needs `writefile` and `getcustomasset`), or an image file dropped into `<FolderName>/backgrounds`. `nil` or `"None"` removes it. Yields while a link downloads; returns `ok, err`. |
| `SetBackgroundTransparency(value)` / `ListBackgrounds()` | Image transparency, 0 to 1; presets plus the files in the backgrounds folder. |
| `SetWeatherMode(mode)` / `.WeatherMode` | `"Screen"` or `"UI"`. |
| `SetHideName(hidden)` / `SetHideAvatar(hidden)` | Hide the player's name or headshot everywhere, same as the home switches. |
| `SetUIScale(n)` / `GetUIScale()` / `.UIScale` | Window size, `0.6` to `1.5`. Eases to the new size and nudges the window back on screen. |
| `SetDensity(mode)` / `GetDensity()` | `"Compact"`, `"Default"` or `"Comfortable"`. Respaces every window live; same as `Airflow:SetDensity(mode)`. Returns the mode it applied. |
| `SelectTab(tab)` | Switch tabs from code. |
| `CreateTab(opts)` | See [Tab](#tab). |
| `Rejoin()` / `ServerHop()` / `JoinLowestServer()` | Teleport to this server, a random open one, or the emptiest one. |
| `CopyToClipboard(text, what?)` | Copy and show a toast. |
| `Notify(opts)` | See [Notification](#notification). |
| `Confirm(opts)` / `Dialog(opts)` | See [Confirm](#confirm). |
| `SaveConfig / LoadConfig / DeleteConfig / ListConfigs` | See [Configs](#configs). |
| `Destroy()` / `Unload()` | Fade out, disconnect everything, remove the gui. `Library:Destroy()` unloads every window. |

---

## Home

> A built-in first tab: the player card with privacy switches, live stats, the current game with server actions, an executor check, and your community links.

```lua
Home = {
    Name = "Home",
    Title = "Welcome to My Hub!",
    Welcome = "Welcome back,",
    Tier = "Premium",
    TierIcon = "crown",
    Expiry = os.time() + 3600 * 12,
    Stats = { "Players", "Friends", "Execs", "Session", "FPS", "Ping" },
    SupportedExecutors = { "Potassium", "Wave", "Volt" },
    Discord = "dsc.gg/myhub",
    Website = "myhub.com",
    Links = {
        { Icon = "youtube", Title = "Showcase", Text = "youtube.com/@myhub", Button = "Copy Link" },
    },
    HideName = false,
    HideAvatar = false,
    Features = true, -- automatic feature list; a table writes your own, false hides it
    Pages = {
        {
            Name = "Changelog",
            Icon = "scroll-text",
            Entries = {
                { Title = "v1.3", Tag = "Latest", Changes = { "Sub tabs", "Groupboxes" } },
                { Title = "v1.2", Date = "Aug 30", Content = "Plain text instead of bullets." },
            },
        },
        { Name = "Info", Icon = "info", Content = "Wrapped text in a card." },
        { Name = "Custom", Icon = "wrench", Build = function(page) page:Button({ Name = "Hi" }) end },
    },
}
```

Stats refresh once a second and pause while the window is hidden or another tab is open. When `Pages` is set, the home tab gets sub tabs: an overview page with the cards above, then one per page.

The **Feature list** card opens a searchable list of the script's features over the window. By default it's automatic: every toggle, slider, dropdown, input, keybind, colour picker, stepper, button and order list, grouped by tab, with the sub tab and groupbox under each name. Hidden elements, hidden tabs and the config and theme managers are left out. Picking a feature closes the list and jumps to it, like search does. To write the list yourself, pass `Features` a table:

```lua
Features = {
    Title = "What's inside",
    List = {
        { Name = "Combat", Icon = "swords", Items = {
            "Auto Parry", -- names that match a control jump to it
            { Name = "Kill Aura", Desc = "Hits everything in range", Tag = "New" },
        } },
        { Name = "Coming soon", Icon = "clock", Items = { { Name = "Auto Raid", Tag = "Soon" } } },
    },
}
```

Bare items (strings or tables without `Items`) gather into one group. `Features = false` removes the card. `Window:ShowFeatures()` opens the list from anywhere.

The game card has Rejoin, Server Hop, Copy Job ID, Copy Universe and Join Lowest Server. The executor card names the executor, says whether it is supported, and shows the hide key. The **Name** and **Profile** switches hide the player's name and headshot on the home tab and in the sidebar.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` / `Desc` / `Icon` | string | `"Home"`, `"house"` | The tab itself. |
| `Title` | string | `"Welcome to <Name>!"` | Page heading. |
| `Welcome` | string | `"Welcome back,"` | Line above the display name. |
| `Tier` | string \| false | `"Free"` | Badge on the player card. `false` hides it. |
| `TierIcon` | string | window icon | Icon in the badge. |
| `Expiry` | number \| string \| function | — | Under the badge. A unix time counts down (`11h 57m`), a string is shown as is, a function is called every second. |
| `Stats` | table | six shown above | Any of `"Players"`, `"Friends"`, `"Execs"`, `"Session"`, `"FPS"`, `"Ping"`, `"Executor"`, `"Game"`, `"Region"`, `"Time"`, `"ServerAge"`, `"Memory"`. |
| `StatsFolder` | string | config folder | Where the execution counter is stored. |
| `TimeFormat` | string | `"%H:%M"` | `os.date` format for the time stat. |
| `SupportedExecutors` | table | — | Names checked against the executor. Without it, the card checks for the file, clipboard and request functions. |
| `Discord` / `Website` | string | — | Link cards with a copy button. |
| `DiscordTitle` / `WebsiteTitle` | string | `"Join the community"` / `"Supported games"` | Card titles. |
| `Links` | table | — | More link cards: `{ Icon, Title, Text, Button, Copy, Callback }`. |
| `HideName` / `HideAvatar` | boolean | `false` | Start with the privacy switches on. |
| `Features` | table \| false | automatic | The feature list card. A table takes `Title`, `Desc` (card text, instead of the count), `Icon`, `Button` and `List`. |
| `Features.List[n]` | table \| string | — | A group `{ Name, Icon, Items }`, or a bare item. |
| `Items[n]` | string \| table | — | `{ Name, Desc, Tag, Icon, Callback }`. `Callback` runs when it's picked. |
| `OverviewName` / `TabIcon` | string | `"Overview"` / `"layout-grid"` | The first sub tab when `Pages` is set. |
| `Pages` | table | — | Extra sub tabs. |
| `Pages[n].Name` / `Icon` | string | — | The sub tab button. |
| `Pages[n].Content` | string | — | Wrapped text in a card. |
| `Pages[n].Entries` | table | — | Cards with `Title`, `Tag` or `Date`, and `Changes` (a list) or `Content`. |
| `Pages[n].Build` | function | — | `function(page, list)`. `page` is a sub tab, so every element constructor and `Groupbox` work on it. |

---

## Tab

> A sidebar button and a page with its icon and title.

```lua
local Tab = Window:CreateTab({
    Name = "Main",
    Desc = "Movement and actions",
    Icon = "zap",
    EmptyText = "Nothing here yet",
})

local Tab = Window:CreateTab("Main", "zap")
```

The first tab created is selected automatically. When there are more tabs than fit in the sidebar, the hidden end fades out and a small chip shows a chevron and how many tabs are past that end. Pressing it scrolls toward them; it leaves once you reach the end. An empty tab shows its icon with `EmptyText`. Elements added straight to a tab stack as full-width cards. Groupboxes go into two columns underneath them.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Tab"` | Sidebar label and page title. |
| `PageTitle` | string | `Name` | Page heading when it should differ from the sidebar label. |
| `Desc` | string | — | Muted line under the page title. |
| `Icon` | string \| number \| table | — | Sidebar and page icon, accent-tinted. |
| `EmptyText` | string | `"Nothing here yet"` | Shown while the tab has no elements. |

### Handle

Every `Create*` element constructor below, `CreateSubTab`, `CreateGroupbox` / `AddLeftGroupbox` / `AddRightGroupbox`, `SelectSubTab(subTab | name | index)`, `.CurrentSubTab`, `.Name` and `.Window`.

---

## Sub Tab

> A row of pills under the page title. Each pill has its own page, and switching slides between them.

```lua
local Farm = Window:CreateTab({ Name = "Farm", Icon = "swords" })

local MobFarm = Farm:CreateSubTab({ Name = "Mob Farm" })
local BossFarm = Farm:CreateSubTab({ Name = "Boss Farm", Icon = "skull" })

MobFarm:CreateToggle({ Name = "Auto Farm", Callback = function(v) end })
Farm:SelectSubTab("Boss Farm")
```

The first sub tab is selected automatically. Once a tab has sub tabs, add elements and groupboxes to the sub tabs, not the tab. The pill row scrolls sideways when it overflows, with the same fade and chip as the sidebar at whichever end has more pills.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Page n"` | Pill label. |
| `Icon` | string \| number \| table | — | Optional icon in the pill. |
| `EmptyText` | string | `"Nothing here yet"` | Shown while the page is empty. |

### Handle

Same as a tab: every element constructor and the groupbox constructors.

---

## Groupbox

> A titled, collapsible card. Groupboxes fill two columns and stack into one when the window is narrow.

```lua
local Mobs = MobFarm:AddLeftGroupbox({ Name = "Mob Farm", Icon = "crosshair" })
local Other = MobFarm:AddRightGroupbox("Other Features", "sparkles")
local Auto = MobFarm:CreateGroupbox({ Name = "Movement", Icon = "move", Collapsed = true })

Mobs:CreateToggle({ Name = "Auto Farm Mobs", Callback = function(v) end })
Mobs:CreateDropdown({ Name = "Mobs", Options = { "Bandit", "Wolf" } })
Mobs:CreateButton({ Name = "Teleport to mob" })
Mobs:CreateLabel("Status: idle")

Auto:Expand()
```

Inside a groupbox, elements are compact rows without their own card. Dropdowns and inputs take the same share of the row so their boxes line up, and buttons fill the width. Click the `−` on the header to collapse it. Without `Side`, each new groupbox goes to the column with fewer boxes.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Groupbox"` | Header title. |
| `Icon` | string \| number \| table | — | Accent icon on the right of the header. |
| `Side` | `"Left"` \| `"Right"` \| 1 \| 2 | balanced | Column. |
| `Collapsed` | boolean | `false` | Start collapsed. |
| `Visible` | boolean | `true` | Start hidden. |

### Handle

| Member | Description |
| --- | --- |
| every element constructor | Adds a row to the groupbox. |
| `Collapse()` / `Expand()` / `SetCollapsed(bool)` | Animate closed or open. |
| `IsCollapsed()` | Current state. |
| `SetTitle(text)` | Rename the header. |
| `SetVisible(bool)` / `IsVisible()` | Hide or show the whole card. Its column closes the gap. |
| `Destroy()` | Remove the groupbox and its elements. |

---

## Visibility

Any element or groupbox can be hidden and shown again. A hidden row takes no space, so its groupbox shrinks and grows with it.

```lua
local Charge -- declared first so the toggle's callback can reach it
local Hold = Box:CreateToggle({ Name = "Hold Skills", Flag = "HoldSkills", Callback = function(v) Charge:SetVisible(v) end })
Charge = Box:CreateSlider({ Name = "Charge Distance", Range = { 5, 60 }, Visible = false, Flag = "ChargeDistance" })
```

- Search never reveals something you hid, and clearing the search leaves it hidden.
- Hidden elements keep their flag. They still save, load and run callbacks, so loading a config with `HoldSkills` on shows `Charge`. Visibility itself is not saved.
- Hiding an open dropdown or colour picker closes it, and hiding a keybind stops a capture.
- A hidden pinned status leaves the orb's hover card until it is shown again.

---

## Tooltips

Every element takes `Tooltip`: a string, or `{ Title, Text, Icon }` for a card with a heading and an icon.

```lua
Box:CreateToggle({ Name = "Kill Aura", Flag = "KillAura", Tooltip = "Hits every mob in range" })
Box:CreateSlider({
    Name = "Range",
    Range = { 5, 50 },
    Tooltip = { Title = "Range", Text = "Studs from your character. Higher can get you flagged.", Icon = "triangle-alert" },
})

Toggle:SetTooltip("New text") -- nil or false removes it
```

The card fades in after a short hover and follows the pointer, flipping to the other side near the screen edge. Moving straight from one element to another swaps the card without the wait. Any click or key press hides it, as does switching tabs or hiding the window. On touch screens a half-second press shows it above the finger and lifting hides it; a finger that starts scrolling doesn't. `GetTooltip()` returns the current value.

---

## Search

The search box in the top-right filters the page you are on as you type. It matches element names and groupbox titles. A groupbox whose title matches stays whole; otherwise only its matching rows stay. Sections and dividers hide while searching. Switching tabs or sub tabs clears it.

---

## Section

> An uppercase heading with a rule to the card edge.

```lua
local Section = Tab:CreateSection("Movement")

Section:Set("Movement (beta)")
```

### Handle

| Member | Description |
| --- | --- |
| `Set(text)` | Replace the heading. |

---

## Divider

> A 1px line, optionally with a caption in the middle.

```lua
Tab:CreateDivider()
Tab:CreateDivider({ Text = "share" })
```

---

## Label

> A single muted line. Can refresh itself.

```lua
local Label = Tab:CreateLabel({
    Text = "Players: 12",
    Color = Airflow.Theme.Muted,
    UpdateRate = 1,
    Update = function()
        return "Players: " .. #game.Players:GetPlayers()
    end,
})

local Label = Tab:CreateLabel("Players: 12")

Label:Set("Players: 13")
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Text` | string | `""` | The line. A bare string works too. |
| `Color` | Color3 | muted | Text colour. |
| `Update` | function | — | Called on a timer; its return value becomes the text. |
| `UpdateRate` | number | `1` | Seconds between `Update` calls. |

### Handle

| Member | Description |
| --- | --- |
| `Set(text)` | Replace the line. |
| `Get()` | The current text. |
| `SetUpdateRate(seconds)` | Change the timer, when `Update` was given. |

---

## Status

> Read-only key and value lines, in six styles. Built for groupboxes.

```lua
local Floor = Group:CreateStatus({ Name = "Floor", Value = 1, Pin = true })
Floor:Set(2)

Group:CreateStatus({ Name = "Exp", Value = "7859/10740", Style = "Bar" })
Group:CreateStatus({ Name = "Server", Value = "Healthy", Style = "Badge", Tone = "Success" })
Group:CreateStatus({ Name = "Bot", Style = "Dot", Update = function()
    return "Farming", "Success"
end })

local Run = Group:CreateStatuses({ "Points", "Hearts", "Map" }, { Style = "Row" })
Run.Hearts:Set(3)
```

| Style | Looks like |
| --- | --- |
| `Plain` | `Floor: 3`, muted key then the value. The default. |
| `Row` | Key on the left, value on the right. |
| `Badge` | Value in a pill tinted by `Tone`. |
| `Dot` | A pulsing dot tinted by `Tone`, then key and value. |
| `Bar` | Key and `current / max` with a progress bar. `"7859/10740"` strings, `Set(current, max)`, or a 0–1 number all work. |
| `Stat` | Small key over a large value. |

A changed value flashes the accent colour briefly. With `Update`, the function runs every `UpdateRate` seconds: its first return is the value, and a second return sets the max (a number) or the tone (a string).

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | The key. |
| `Value` | any | `"-"` shown | The value. `nil` shows `Placeholder`. |
| `Style` | string | `"Plain"` | See above. |
| `Tone` | string | `"Accent"` | Any theme colour name: `"Success"`, `"Warning"`, `"Error"`, `"Muted"`… |
| `Max` | number | — | Max for `Bar`. |
| `Prefix` / `Suffix` | string | — | Text around the value. |
| `Placeholder` | string | `"-"` | Shown while the value is `nil`. |
| `Update` / `UpdateRate` | function / number | — / `1` | Refresh on a timer. |
| `Pin` | boolean | `false` | Also show it on the minimized orb's hover card. |
| `Pulse` / `Flash` | boolean | `true` | The `Dot` pulse and the change flash. |

### Handle

| Member | Description |
| --- | --- |
| `Set(value, max?)` / `Get()` | Change or read the value. |
| `SetTone(tone)` / `SetName(name)` | Recolour or rename. |
| `SetUpdateRate(seconds)` | When `Update` is set. |
| `Tab:CreateStatuses(entries, shared?)` | Several at once. Entries are names or option tables; `shared` fills missing options. Returns the handles by name. |

---

## Status List

> A read-only block of rows that grows up to `MaxRows`, then scrolls inside itself. Built for groupboxes: hotbar skills, boss timers, a queue.

```lua
local Skills = Box:CreateStatusList({
    Name = "Hotbar",
    MaxRows = 5,
    EmptyText = "no skills on the hotbar yet",
    UpdateRate = 0.5,
    Update = function()
        return {
            "Z Compound Eye Hexagon (on target, up to 3s)",
            { Text = "X True Flutter", Value = "charges 3s" },
            { Text = "B Illusory Light", Value = "cooldown 12s", Tone = "Warning" },
        }
    end,
})
Skills:Set({ "one row", "another row" })
```

A plain string is one muted line that wraps. A table `{ Text, Value?, Tone? }` puts `Text` on the left and `Value` on the right, like the `Row` status style. `Tone` is any theme colour name and tints the value, or the text when there is no value.

Rows are reused between refreshes, and unchanged rows are skipped, so it never flickers. The scroll position survives a refresh. The mouse wheel scrolls the list, and at its top or bottom edge the page scrolls instead. `Update` only runs while the list is on screen: not while the window is hidden or minimized, another tab or sub tab is open, or the list or its groupbox is hidden. Search matches the list's `Name`, not its rows.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | Optional small muted heading above the rows. Omit it for no heading. |
| `Rows` | table | `{}` | Initial rows. |
| `MaxRows` | number | `5` | Rows shown before the list scrolls. |
| `EmptyText` | string | `"Nothing yet"` | One muted line shown when there are no rows. |
| `Update` / `UpdateRate` | function / number | — / `1` | Timer refresh. The return value is the row list. Returning `nil` keeps the current rows. |
| `Visible` | boolean | `true` | Start hidden. |

### Handle

| Member | Description |
| --- | --- |
| `Set(rows)` | Replace all rows. |
| `Get()` | The current rows, as a copy. |
| `Clear()` | Remove all rows. The `EmptyText` shows. |
| `SetName(text)` | Change the heading. |
| `SetUpdateRate(seconds)` | When `Update` is set. |
| `SetVisible(bool)` / `IsVisible()` / `Destroy()` | Shared by every element. |

---

## Paragraph

> A card with a heading and wrapped body text.

```lua
local Paragraph = Tab:CreateParagraph({
    Title = "About",
    Content = "Longer text that wraps across several lines.",
})

Paragraph:Set("Updated body")
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Title` | string | `""` | Heading. |
| `Content` | string | `""` | Body. Wraps and grows the card. |

### Handle

| Member | Description |
| --- | --- |
| `Set(text)` | Replace the body. |

---

## Button

> A full-width card that ripples on click.

```lua
local Button = Tab:CreateButton({
    Name = "Reset character",
    Desc = "Respawns at the last spawn point",
    Icon = "refresh-cw",
    Style = "Primary",
    Callback = function()
        print("clicked")
    end,
})

Button:SetText("Respawn")
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Button"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Icon` | string \| number \| table | — | Leading icon. |
| `Style` | string | — | `"Primary"` fills the card with the accent colour. |
| `Callback` | function | — | Runs on click. |

### Handle

| Member | Description |
| --- | --- |
| `SetText(text)` | Replace the label. |

---

## Button Row

> Equal-width buttons side by side.

```lua
Group:CreateButtonRow({
    { Name = "Save", Callback = function() end },
    { Name = "Load", Callback = function() end },
})
```

Each entry takes `Name`, `Callback` and `Style` (`"Primary"` for the accent fill, `"Danger"` for red text). The handle has `SetText(index, text)` and `.Buttons`.

---

## Toggle

> Switch a boolean on and off.

```lua
local Toggle = Tab:CreateToggle({
    Name = "Auto sprint",
    Desc = "Hold shift to run",
    CurrentValue = true,
    Flag = "AutoSprint",
    Callback = function(Value)
        print("Auto sprint:", Value)
    end,
})

Toggle:Set(false)
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Toggle"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `CurrentValue` | boolean | `false` | The initial state. The callback fires once on creation if `true`. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs with the new value on every change. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current state. |
| `Set(value, skipCallback?)` | Set the state. Pass `true` as the second argument to skip the callback. |
| `Get()` | The current state. |

---

## Slider

> Pick a number in a range.

```lua
local Slider = Tab:CreateSlider({
    Name = "Walk speed",
    Desc = "Studs per second",
    Range = { 16, 100 },
    Increment = 1,
    Suffix = " sps",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(Value)
        print("Walk speed:", Value)
    end,
})

Slider:Set(50)
```

Click the value chip to type an exact number.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Slider"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Range` | table | `{ 0, 100 }` | `{ min, max }`. |
| `Increment` | number | `1` | Snap size. Its decimals set how the value is shown. |
| `Suffix` | string | `""` | Appended to the value chip. |
| `CurrentValue` | number | min | The initial value. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs with the new value on every change, including while dragging. |
| `OnRelease` | function | — | Runs with the value when a drag ends. Use it for work too heavy to repeat every frame. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current value. |
| `.Dragging` | Whether the knob is being dragged. |
| `Set(value, skipCallback?)` | Set the value. Slides with a small overshoot. |
| `Get()` | The current value. |

---

## Stepper

> A number with − and + buttons.

```lua
local Stepper = Tab:CreateStepper({
    Name = "Fall threshold",
    Desc = "Distance before damage",
    Range = { 0, 100 },
    Increment = 5,
    Suffix = " studs",
    CurrentValue = 50,
    Flag = "FallThreshold",
    Callback = function(Value)
        print("Threshold:", Value)
    end,
})

Stepper:Set(75)
```

Hold either button to repeat.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Stepper"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Range` | table | `{ 0, 100 }` | `{ min, max }`. |
| `Increment` | number | `1` | Step per press. Its decimals set how the value is shown. |
| `Suffix` | string | `""` | Appended to the value. |
| `CurrentValue` | number | min | The initial value. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs with the new value on every change. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current value. |
| `Set(value, skipCallback?)` | Set the value. Snapped to the increment and clamped to the range. |
| `Get()` | The current value. |

---

## Progress

> A read-only bar from 0 to 1.

```lua
local Progress = Tab:CreateProgress({
    Name = "Health",
    Desc = "Live from the humanoid",
    CurrentValue = 1,
    Color = Airflow.Theme.Success,
    Format = function(Fraction)
        return math.floor(Fraction * 100) .. " hp"
    end,
    Callback = function(Fraction)
        print("Health:", Fraction)
    end,
})

Progress:Set(0.5)
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Progress"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `CurrentValue` | number | `0` | The initial fraction. |
| `Color` | Color3 | accent | Fill colour. |
| `Format` | function | percentage | Returns the label text for a fraction. |
| `Callback` | function | — | Runs on `Set` unless skipped. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current fraction. |
| `Set(value, skipCallback?)` | Set the fraction. Eases the fill. |
| `SetColor(color)` | Change the fill colour. |
| `Get()` | The current fraction. |

---

## Dropdown

> Pick one option, or several, from a searchable popup.

```lua
local Dropdown = Tab:CreateDropdown({
    Name = "Mobs",
    Desc = "Farmed in order",
    Options = { "T1", "T2", "T3" },
    CurrentOption = { "T1" },
    MultipleOptions = true,
    Flag = "Mobs",
    Callback = function(Options)
        print("Mobs:", table.concat(Options, ", "))
    end,
})

Dropdown:Set({ "T1", "T3" })
```

Clicking the chip unfolds a popup out of it, floating over the window under the chip, or above it when there's no room below. It follows the window while open and closes on an outside click, `Esc` or a tab switch. The popup has a search box, **Select all** / **Clear all** in multi mode, and flat rows with square checkboxes that highlight on hover. Select all only picks the rows matching the search. Clicking a selected row unchecks it. The page behind stays put while the popup is open, so wheel and swipe input always scroll the list. A single-select list opens scrolled to its current value, and the list shrinks to fit short windows. On touch, rows are taller and a swipe that scrolls the list never selects a row.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Dropdown"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Options` | table | `{}` | The rows. |
| `CurrentOption` | string \| table | — | The initial selection. A table in multi mode. |
| `MultipleOptions` | boolean | `false` | Rows toggle independently and the callback receives a list. |
| `Searchable` | boolean | `true` | Show the search box. |
| `SearchAfter` | number | `0` | Only show search when there are more rows than this. |
| `MaxRows` | number | `6` | Rows visible before the list scrolls. |
| `NoneText` | string | `"None"` | Chip text with nothing selected. |
| `EmptyText` | string | `"None"` | Chip text when there are no options. |
| `AllowNone` | boolean | `true` | `false` stops a single dropdown from unchecking its value. |
| `PopupWidth` | number | `210` | Minimum popup width. It grows to the chip width. |
| `Stacked` | boolean | `false` | Inside a groupbox: the chip spans the full row with the name above it. Leave `Name` out for a bare chip. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs with the selection on every change. `nil` when unchecked. |

### Handle

| Member | Description |
| --- | --- |
| `.Open` | Whether the popup is showing. |
| `Set(value, skipCallback?)` | Select a value, or a list in multi mode. |
| `Refresh(options, keepSelection?, skipCallback?)` | Replace the rows. A pick only counts while its option is in the list, so if the refresh changes the value (a config's saved picks becoming real options, or picks dropped), the callback runs with the new value. Saving keeps picks whose option is missing right now. |
| `SetOpen(open)` | Show or hide the popup. |
| `Get()` | The current selection. |

---

## Order List

> An always-open list the player puts in order.

```lua
local Order = Tab:CreateOrderList({
    Name = "Boss Order",
    Desc = "Top boss is farmed first",
    Items = { "Rui", "Akaza", "Doma", "Kokushibo" },
    MaxRows = 6,
    Flag = "BossOrder",
    Callback = function(Order)
        print("First:", Order[1])
    end,
})

Order:Set({ "Doma", "Rui" }) -- Doma, Rui, then the rest in their current order
```

There's nothing to click open: the rows sit in the element. Drag a row to move it, and the others slide out of its way. On PC the whole row drags; on touch only the grip on the left does, so a swipe across the rows still scrolls. The up and down arrows on each row move it one place. Past `MaxRows` the list scrolls inside itself, and holding a dragged row near its top or bottom edge scrolls it along. The page behind stays put while a row is held. The callback runs once per drop or arrow press, not while dragging.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | The label above the list. |
| `Desc` | string | — | Hint text under the label. |
| `Items` | table | `{}` | The rows, in their starting order. |
| `MaxRows` | number | `6` | Rows visible before the list scrolls. |
| `Numbered` | boolean | `true` | Show each row's position. |
| `Arrows` | boolean | `true` | Show the up and down buttons. |
| `EmptyText` | string | `"Nothing to order"` | Shown when there are no items. |
| `Flag` | string | — | The save key. Saves the order. |
| `Callback` | function | — | Runs with the new order on every change. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current order. |
| `Set(order, skipCallback?)` | Reorder the items to match `order`. Items it leaves out keep their order after the ones it names. Names not in the list are remembered and applied when `Refresh` brings them in, so a saved order survives a list that fills in later. |
| `Refresh(items, keepOrder?, skipCallback?)` | Replace the items. Items that were already there keep the player's order and new ones go to the end. Pass `keepOrder` as `false` to take `items` as given. |
| `Get()` | The current order, a list. |

---

## Input

> A text box that grows with what you type.

```lua
local Input = Tab:CreateInput({
    Name = "Player name",
    Desc = "Partial names work",
    Icon = "user",
    PlaceholderText = "type here",
    CurrentValue = "",
    Numeric = false,
    Flag = "PlayerName",
    Callback = function(Text, EnterPressed)
        print("Input:", Text, EnterPressed)
    end,
})

Input:Set("Pookie")
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Input"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Icon` | string \| number \| table | — | Icon inside the box. |
| `PlaceholderText` | string | `""` | Shown while empty. |
| `CurrentValue` | string | `""` | The initial text. |
| `Numeric` | boolean | `false` | Clears the box and skips the callback if the text is not a number. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs when focus is lost. The second argument is whether Enter was pressed. |

### Handle

| Member | Description |
| --- | --- |
| `Set(text)` | Replace the text. |
| `Get()` | The current text. |

---

## Keybind

> Bind an action to a key.

```lua
local Keybind = Tab:CreateKeybind({
    Name = "Toggle sprint",
    Desc = "Press to flip the toggle",
    CurrentKeybind = "F",
    Flag = "SprintKey",
    Callback = function(Key)
        print("Pressed:", Key.Name)
    end,
    OnChanged = function(Key)
        print("Rebound to:", Key.Name)
    end,
})

Keybind:Set(Enum.KeyCode.G)
```

Click the chip and press a key to rebind. Escape cancels.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Keybind"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `CurrentKeybind` | string \| KeyCode | — | The initial key. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs when the key is pressed and no text box has focus. |
| `OnChanged` | function | — | Runs when the user rebinds it. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current KeyCode, or `nil`. |
| `.Listening` | Whether the chip is waiting for a key. |
| `Set(keyCode, skipCallback?)` | Rebind. Pass `true` to skip `OnChanged`. |
| `Get()` | The current KeyCode. |

---

## Color Picker

> Pick a colour.

```lua
local ColorPicker = Tab:CreateColorPicker({
    Name = "Highlight colour",
    Desc = "Applied to every highlight",
    Color = Color3.fromRGB(235, 199, 246),
    Flag = "HighlightColor",
    Callback = function(Color)
        print("Colour:", Color)
    end,
})

ColorPicker:Set(Color3.fromRGB(150, 220, 170))
```

The panel has a saturation/value square, a hue bar, a hex box and an RGB readout.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Color"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Color` | Color3 | accent | The initial colour. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs with the new colour on every change, including while dragging. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current colour. |
| `.Open` | Whether the panel is expanded. |
| `Set(color, skipCallback?)` | Set the colour. Animates the cursors. |
| `SetOpen(open)` | Expand or collapse. |
| `Get()` | The current colour. |

---

## Image

> A picture card: an optional title, the image with rounded corners, and an optional caption.

```lua
local Banner = Tab:CreateImage({
    Name = "Map",
    Image = 1234567890, -- asset id, rbxassetid:// or rbxthumb:// link, web link, file, background preset or "Avatar"
    Height = 160,
    Caption = "Spawn island",
})

Banner:SetImage("https://example.com/map.png")
```

A placeholder icon shows until the image has loaded, then the picture fades in. Sources are the same as `SetBackground` on the [window](#handle): an image asset id (an Image id, not a Decal id), an `rbxassetid://` / `rbxthumb://` link, an http(s) link (downloaded once, needs `writefile` and `getcustomasset`), a file in `<FolderName>/backgrounds`, or a background preset name. `"Avatar"` shows the player's headshot.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | Title above the image. Leave out for just the image. |
| `Desc` | string | — | Hint text under the title. |
| `Image` | string \| number | — | The picture. |
| `Height` | number | `160` | Height of the picture, 40 to 600. |
| `Caption` | string | — | Line over the bottom of the picture, on a dark fade. |
| `ScaleType` | string | `"Crop"` | `"Crop"`, `"Fit"`, `"Stretch"`. |
| `Color` | Color3 | white | Tint. |

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current source. |
| `SetImage(source)` / `Set(source)` | Swap the picture. `nil` clears it. Yields while a link downloads; returns `ok, err`. |
| `Get()` | The current source. |
| `SetCaption(text)` / `SetTitle(text)` | Change the caption (`nil` hides it) or the title. |
| `SetScaleType(name)` / `SetColor(color)` | Change how it fills the card, or its tint. |

---

## Viewport

> A 3D preview: a model, a part or the player's avatar, turning slowly.

```lua
local Preview = Tab:CreateViewport({
    Name = "Your character",
    Model = "Avatar", -- or any Model / BasePart (it is copied), a Player, or a function returning one
    Height = 200,
    SpinSpeed = 25,
})

Preview:SetModel(workspace.Sword)
```

The model is copied into the card with its scripts and sounds stripped and every part anchored, so the original is never touched. The camera frames the whole model and faces its front. Drag the card sideways to turn it by hand; the spin picks up again a moment after you let go. It only spins while the window is open. `"Avatar"` waits for the character to spawn if it hasn't yet; call `Refresh()` after a respawn or an outfit change to copy it again.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | Title above the preview. |
| `Desc` | string | — | Hint text under the title. |
| `Model` | Instance \| string \| function | — | What to show. |
| `Height` | number | `180` | Height of the preview, 40 to 600. |
| `Spin` | boolean | `true` | Turn slowly on its own. |
| `SpinSpeed` | number | `25` | Degrees per second. |
| `Angle` / `Pitch` | number | `0` / `10` | Starting turn, and how far above the model the camera sits, in degrees. |
| `Distance` | number | `1` | Camera distance multiplier. Below 1 zooms in. |
| `FieldOfView` | number | `35` | Camera field of view. |
| `Clone` | boolean | `true` | `false` moves the instance itself into the card instead of a copy. |
| `Caption` | string | — | Line over the bottom of the preview. |
| `Ambient` / `LightColor` | Color3 | soft grey / warm white | Lighting. |

### Handle

| Member | Description |
| --- | --- |
| `.Model` | The copy on show. |
| `SetModel(value)` / `Set(value)` | Show something else. `nil` clears it. Yields while waiting for a character; returns `ok, err`. |
| `Refresh()` | Copy the current source again. |
| `SetSpin(enabled)` / `SetSpinSpeed(degrees)` / `SetAngle(degrees)` | Control the turn. |
| `SetCaption(text)` / `SetTitle(text)` | Change the caption or the title. |

---

## Table

> Rows under a header, sortable by column. With `Rank` it is a leaderboard.

```lua
local Board = Tab:CreateTable({
    Name = "Leaderboard",
    Rank = true,
    Columns = {
        "Player",
        { Name = "Kills", Align = "Right", Width = 0.2 },
        { Name = "Cash", Align = "Right", Width = 0.25, Format = function(v) return "$" .. v end },
    },
    Rows = {
        { "Builderman", 42, 12500 },
        { "Roblox", 57, 9800, Highlight = true },
    },
    SortBy = "Kills",
    MaxRows = 8,
    Callback = function(row, index)
        print(row[1], index)
    end,
})

Board:AddRow({ "Guest", 12, 300 })
Board:UpdateRow(2, { "Roblox", 60, 10200, Highlight = true })
```

Click a header to sort by it: numbers go high to low first and text A to Z, a second click flips it, and a third goes back to the order you gave. An arrow marks the sorted column. `Rank = true` adds a `#` column numbered by the order on screen, with gold, silver and bronze badges for the top three. Rows alternate shading and light up on hover. A highlighted row gets an accent tint, accent text and a bar on its left, for marking the player. `UpdateRow` flashes the row it changed. Past `MaxRows` the body scrolls; with fewer rows the card shrinks to fit.

A row is a list of values in column order, or a table keyed by each column's `Key` (its name by default). Numbers get thousands separators unless the column has a `Format`.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | Title above the table. |
| `Desc` | string | — | Hint text under the title. |
| `Columns` | table | — | Column names, or `{ Name, Key, Width, Align, Format, Color, Sortable }`. `Width` above 1 is pixels, up to 1 a share of the width; columns without one split what's left. `Align` is `"Left"`, `"Center"` or `"Right"`. `Format(value, row)` returns the text to show. `Color` is a Color3 or `function(value, row)` returning one. `Sortable = false` locks a column. |
| `Rows` | table | `{}` | The rows. Put `Highlight = true` in a row to mark it. |
| `Rank` | boolean | `false` | Add the `#` column with medals. |
| `Highlight` | function | — | `function(row, index)` returning `true` to mark a row, for example the player's own. |
| `SortBy` / `SortDescending` | string \| number / boolean | — / `true` | Starting sort: a column name, key or number. |
| `Sortable` | boolean | `true` | `false` turns header sorting off for every column. |
| `MaxRows` | number | `8` | Rows shown before the body scrolls. |
| `RowHeight` | number | `26` (`32` touch) | Height of a row. |
| `EmptyText` | string | `"Nothing here yet"` | Shown with no rows. |
| `Callback` | function | — | `function(row, index)` when a row is clicked. `OnRowClick` works too. |

### Handle

| Member | Description |
| --- | --- |
| `.Rows` | The rows, in the order you gave. Indexes below refer to this list, not the sorted view. |
| `SetRows(rows)` / `Set(rows)` | Replace every row. Cheap enough to call every second for a live board. |
| `GetRows()` / `Get()` | The rows. |
| `AddRow(row, index?)` | Add a row at the end or at `index`. Returns its index. |
| `UpdateRow(index, row)` | Replace a row and flash it. |
| `RemoveRow(index)` / `Clear()` | Remove one row or all of them. |
| `Sort(column?, descending?)` | Sort from code. `Sort()` goes back to the given order. |
| `SetColumns(columns)` | Rebuild the header and clear the sort. |
| `SetMaxRows(n)` / `SetTitle(text)` | Change the visible row count or the title. |

---

## Notification

> A toast in the bottom-right corner.

```lua
local Notification = Airflow:Notify({
    Title = "Loaded",
    Content = "5 tabs ready",
    Icon = "check",
    Type = "Success",
    Duration = 4,
})

local Notification = Window:Notify({ Title = "Window specific" })

Notification:Dismiss()
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Title` | string | `"Notification"` | Bold first line. |
| `Content` | string | — | Wrapped body. |
| `Icon` | string \| number \| table | — | Icon before the title. |
| `Duration` | number | `4` | Seconds before it dismisses itself. |
| `Type` | string | `"Info"` | `"Info"`, `"Success"`, `"Warning"` or `"Error"`. Tints the title. |

### Handle

| Member | Description |
| --- | --- |
| `Dismiss()` | Close it now. |

---

## Confirm

> Ask before doing something.

```lua
Tab:CreateButton({
    Name = "Unload",
    Callback = function()
        Airflow:Confirm({
            Title = "Unload?",
            Content = "The window closes and everything is restored.",
            Icon = "power",
            ConfirmText = "Unload",
            CancelText = "Keep",
            Callback = function()
                Window:Destroy()
            end,
            OnCancel = function()
                print("Kept")
            end,
        })
    end,
})

Airflow:Dialog({
    Title = "Choose",
    Content = "Pick one.",
    Icon = "list",
    CloseOnBackdrop = true,
    Buttons = {
        { Title = "Later", Callback = function() end },
        { Title = "Now", Variant = "Primary", Callback = function() end },
    },
})
```

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Title` | string | `"Are you sure?"` | Heading. |
| `Content` | string | — | Wrapped body. |
| `Icon` | string \| number \| table | — | Icon before the heading. |
| `ConfirmText` | string | `"Confirm"` | Primary button. |
| `CancelText` | string | `"Cancel"` | Secondary button. |
| `Callback` | function | — | Runs when confirmed. |
| `OnCancel` | function | — | Runs on cancel or a backdrop click. |

`Dialog` builds the same card with any number of buttons. `Variant = "Primary"` gives a button the accent fill. `CloseOnBackdrop = false` forces a button press.

---

## Flags

> Read and write any element by its save key.

```lua
print(Airflow.Flags.AutoSprint:Get())
Airflow.Flags.WalkSpeed:Set(50)
```

Toggles, sliders, steppers, dropdowns, inputs, keybinds and colour pickers created with a `Flag` are stored on `Airflow.Flags`. Flags are also what configs save.

---

## Configs

> Save every flagged element to a file, load it back, and pick one to autoload.

```lua
local Window = Airflow:CreateWindow({
    Name = "Airflow",
    ConfigurationSaving = { Enabled = true, FolderName = "MyHub", FileName = "default" },
})

local Settings = Window:CreateTab({ Name = "Settings", Icon = "settings" })
Settings:CreateConfigManager({ Name = "Configs", Side = "Left" })

-- create the rest of your tabs and elements

Window:LoadAutoload()
```

The config manager is a groupbox with, from top to bottom:

- a **config name** box and the config picker
- **Create** / **Save**, **Load** / **Delete**, **Set autoload** / **Clear autoload**, **Rename** / **Reset**
- a status line: `loaded: <name> | autoload: <name>`
- **Autoload mode**: *All accounts* or *This account*
- **Refresh list**
- a **share** section: **Copy code** puts the current settings on the clipboard as a code, and **Import code** applies a pasted code and saves it. It's saved under the name in the name box, or else the name inside the code (with ` (2)`, ` (3)`... added rather than overwriting a config you already have).

Save with nothing picked creates a config from the typed name. **Rename** renames the picked config to the typed name and moves the loaded name and autoloads with it. **Reset** puts every flagged element back to the value it was created with and deletes the script's whole `FolderName` folder (configs, saved themes, the default theme, autoload, settings, execution count), after a confirm. Names can't contain `\ / : * ? " < > |`.

`LoadAutoload` can run before every element exists. Values for flags that no element has claimed yet are held and applied as soon as an element with that flag is created, and saving writes them back, so a config never loses settings for elements that only exist some of the time (a game-specific tab, say).

### File format

A config file and a share code are the same readable JSON, so a code is just the file's contents:

```json
{"Folder":"MyHub/Game","Name":"farm","Version":1,"Config":"{\"AutoFarm\":{\"Value\":true,\"Type\":\"Toggle\"},\"Speed\":{\"Value\":40,\"Type\":\"Slider\"},\"EspColor\":{\"Value\":{\"Hex\":\"ff5a5a\"},\"Type\":\"ColorPicker\"},\"Targets\":{\"Value\":[\"Boss\",\"Mob\"],\"Type\":\"Dropdown\"},\"Pick\":{\"Type\":\"Dropdown\"}}"}
```

- `Folder` is the window's `FolderName`. Importing a code made for another folder asks first, and then only applies the flags that match by name and type.
- `Config` is the flags as their own JSON string. Each flag is `{ "Value": ..., "Type": ... }`. Colours are `{ "Hex": "rrggbb" }`, keybinds are key names (`"RightShift"`), and a dropdown with nothing picked has no `Value`.
- Old `airflow:...` base64 codes and older config files (bare flag tables, colours as RGB arrays) still load, and are rewritten in the new format on the next save.

Configs only change when you press **Create** or **Save** (or call `SaveConfig`); nothing is written automatically. The autoload mode lives in `<folder>/configsettings.txt`, apart from the configs, so loading a config never flips it. *This account* keeps the autoload in `autoload_<UserId>.txt`, so other accounts on the same PC don't load it. Switching modes moves the current autoload across.

Requires `writefile` / `readfile`.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `FolderName` | string | `"AirflowUI"` | Folder in the executor workspace. Can be nested, like `"MyHub/Game"`; missing folders are made. |
| `FileName` | string | `"default"` | Config used when `SaveConfig` / `LoadConfig` get no name. |

`CreateConfigManager` takes `Name`, `Icon`, `Side` and `Placeholder`. Called on a groupbox it adds its rows there instead of making its own.

### Handle

| Member | Description |
| --- | --- |
| `Window:SaveConfig(name?)` | Write `<folder>/<name>.json`. Returns `ok, err`. |
| `Window:LoadConfig(name?, skipCallbacks?)` | Apply a saved config and mark it loaded. |
| `Window:DeleteConfig(name)` | Remove the file. |
| `Window:RenameConfig(name, newName)` | Rename a config, carrying the loaded name and autoloads along. Refuses to overwrite. |
| `Window:ConfigExists(name)` | Whether `<folder>/<name>.json` exists. |
| `Window:ResetConfig(skipCallbacks?)` | Put every flagged element back to its starting value. |
| `Window:ClearWorkspace()` | Delete the script's `FolderName` folder and everything in it. Returns `false` if some files could not be removed. |
| `Window:ListConfigs()` | Saved names, sorted without regard to case. |
| `Window.LoadedConfig` | Name of the loaded config, or `nil`. |
| `Window:ExportConfig(name?)` | Share code (the config JSON) for a saved config, or for the current settings when `name` is `nil`. |
| `Window:DecodeConfig(code)` | Read a code without applying it. Returns `flags, { Folder, Name, Version }`, or `nil, err`. |
| `Window:ImportConfig(code, saveAs?, force?)` | Apply a code. `saveAs` is a name, `true` for the name inside the code, or `nil` to only apply it. Codes for another `Folder` fail unless `force`. Returns `ok, err, savedName`. |
| `Window:SetAutoload(name?, scope?)` / `GetAutoload(scope?)` / `LoadAutoload(skipCallbacks?)` | The config loaded on start. `nil` clears it. `scope` is `"Global"` or `"Account"`, defaulting to the current mode. |
| `Window:SetAutoloadMode(mode)` / `GetAutoloadMode()` | `"Global"` (all accounts) or `"Account"` (this account). |
| `Window:OnConfigChanged(fn)` | Runs `fn` after a load, delete, import or autoload change. Returns a disconnect function. |
| `Tab:CreateConfigManager(opts)` | Returns `Create / Save / Load / Delete / Rename / Reset / SetAutoload / ClearAutoload / ToggleAutoload / SetAutoloadMode / Export / Import / Refresh`. |

---

## Cloud Configs

> A tab for browsing, previewing, installing and publishing configs other players shared. The library draws it; your script is the backend.

```lua
local Cloud = Window:CreateCloudConfigs({
    Name = "Cloud",
    Tags = { "Farming", "PvP", "Safe", "Visuals" },
    OnFetch = function(Query)
        -- Query = { Search, Sort, Filter, Tag, Page, PageSize, Folder, UserId }
        local ok, body = pcall(game.HttpGet, game, "https://my.api/configs?page=" .. Query.Page .. "&sort=" .. Query.Sort)
        if not ok then
            return nil, "Server is down" -- shown with a Try again button
        end
        local Data = game:GetService("HttpService"):JSONDecode(body)
        return Data.Configs, Data.HasMore -- a list of configs, and whether there's another page
    end,
    OnPublish = function(Config)
        -- Config = { Name, Description, Tags, Code, Count, Folder, Author, AuthorId, OwnerId, Streamer }
        -- post it; return the stored config (with its Id), or false, "reason"
    end,
    OnFetchCode = function(Config) -- only needed when OnFetch leaves Code out
        return game:HttpGet("https://my.api/configs/" .. Config.Id .. "/code")
    end,
})
```

`CreateCloudConfigs` adds its own sidebar tab, like Home. The page slides between three views: **browse**, a config's **details**, and the **publish** form. The first fetch waits until the tab is opened.

**Browsing**

- A search box (it waits for you to stop typing, or press Enter), a refresh button that spins while a page loads, and **Publish** on top. Press `/` to jump to the search box. Focusing it empty drops down your last six searches. Matches are highlighted in the cards, and a line above them sums up what you are looking at (*3 configs in Favorites, tagged PvP, matching "boss"*) with a **Clear filters** link.
- Filter chips: **All**, **Favorites**, **Mine**, **Installed**, then your `Tags` (one at a time, press again to clear). A sort chip on the right cycles *Popular*, *Newest*, *Top rated* and *Most installed*, and is remembered.
- Configs are cards in one column, or two on a wide window: name, author, when it was updated, how many settings, two lines of description, up to three tags, likes, installs and an **Install** button. A badge marks configs you've **installed**, ones with an **update** since you installed them, **yours**, and ones made for **another script**. A star marks favorites.
- Pulsing placeholder cards while a page loads. The next page loads when you scroll near the bottom (or press **Load more**). A slow reply to an old search is thrown away. Errors show a **Try again** button; no results say why ("No configs match your search") and offer **Clear filters**.
- **Favorites** and **Installed** are kept on this device, so they work without the backend and filter locally.

**A config's page**

- The full description, tags, likes and installs.
- **Install** / **Update** / **Reinstall**, **Like**, **Favorite**, **Copy code**, and **Report** for other people's configs. Your own configs get **Edit** and **Delete** instead.
- Every setting in the config, next to yours: the ones that would change come first with an accent dot, then the ones that match, then flags this script doesn't have. The heading sums it up: *24 settings, 5 different from yours*.

**Installing** asks first, with three buttons: **Install** applies it and saves it as a config (under its own name, with ` (2)`... rather than overwriting), **Apply only** changes the current settings without saving, or **Cancel**. Installing an update overwrites the config the last install saved. A config for another `FolderName` warns that only matching settings apply. Likes show at once and roll back if `OnLike` fails.

**Publishing** takes a name (40 characters), a description with a counter, up to `MaxTags` tags, and which settings to share: *Current settings* or any saved config, with a count of what's in it. It says who you publish as, and follows the Home tab's hide-name switch: with it on, `Author` is *Ouroboros User* and `AuthorId` is `nil`. `OwnerId` is always the player's UserId, so the backend can tell who owns what; keep it private. A draft stays in the form if you back out. **Edit** opens the same form filled in, with *Keep published settings* as the default, and calls `OnUpdate`.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` / `Desc` / `Icon` | string | `"Cloud"`, —, `"cloud"` | The tab. |
| `Tags` | table | `{}` | Tags to filter by and to pick when publishing. |
| `MaxTags` | number | `3` | Tags per config. |
| `PageSize` | number | `20` | Sent to `OnFetch` as `Query.PageSize`. |
| `Sort` | string | `"Popular"` | Starting sort until the player picks one: `"Popular"`, `"New"`, `"Top"`, `"Installs"`. |
| `DescriptionLimit` | number | `300` | Characters in a description. |
| `OnFetch` | function | — | `(query)` returns `configs, hasMore`, or `nil, reason`. `Query.Filter` is `"All"` or `"Mine"`. Leave it out to push results with `SetConfigs`. |
| `OnFetchCode` | function | — | `(config)` returns the code, for lists sent without codes. |
| `OnPublish` | function | — | `(config)` returns the stored config, `true`, or `false, reason`. Hides **Publish** when missing. |
| `OnUpdate` | function | — | `(config, changes)` for **Edit**. `changes.Code` is `nil` when the settings are kept. |
| `OnDelete` | function | — | `(config)` for **Delete**. Return `false, reason` to refuse. |
| `OnLike` | function | — | `(config, liked)`. Return `false` to roll the like back. Hides **Like** when missing. |
| `OnInstall` | function | — | `(config, savedName)` after an install, to count it. |
| `OnReport` | function | — | `(config, reason)`. Hides **Report** when missing. |
| `ReportReasons` | table | `{ "Broken", "Spam", "Inappropriate" }` | Choices in the report dialog. |
| `MineFilter` | boolean | `true` | Show the **Mine** chip. |
| `StreamerName` | string | `"Ouroboros User"` | The author name while the player's name is hidden. |
| `SearchPlaceholder` / `EmptyText` | string | — | Text in the search box and when there are no configs. |

### Configs

What `OnFetch` returns, and what the callbacks get back:

| Field | Description |
| --- | --- |
| `Id` | Unique id. Favorites and installs are kept by it. |
| `Name` / `Description` / `Tags` | Shown on the card and page. |
| `Author` / `AuthorId` | Who published it. A matching `AuthorId` or `OwnerId`, or `Mine = true`, makes it the player's own. |
| `Code` | The config code (`Window:ExportConfig()` format). Can be left out and served by `OnFetchCode`. |
| `Count` | Number of settings, worked out from `Code` when missing. |
| `Folder` | The `FolderName` it was made for. |
| `Installs` / `Likes` / `Liked` | Counts, and whether the player liked it. |
| `Updated` | Unix time of the last change. Newer than when the player installed it shows **Update**. |

### Handle

| Member | Description |
| --- | --- |
| `Refresh()` / `LoadMore()` | Fetch the first page again, or the next one. |
| `SetConfigs(list, hasMore?)` / `AddConfigs(list, hasMore?)` | Show configs pushed by the script instead of `OnFetch`. |
| `UpdateConfig(id, changes)` / `RemoveConfig(id)` | Change or drop one config, like new like counts from a socket. |
| `SetLoading(on)` / `SetError(text?)` | Show the placeholders, or an error with **Try again**. |
| `Open(id)` / `OpenPublish()` / `Back()` | Jump to a config's page, the publish form, or back to the list. |
| `GetQuery()` | The current search, sort, filter and tag. |
| `GetFavorites()` / `GetInstalled()` | What this device kept. |
| `.Tab` | The tab. |

---

## Icons

> Any lucide icon or your own image, anywhere an `Icon` is accepted.

```lua
Airflow:PreloadIcons()

Window:CreateTab({ Name = "Main", Icon = "zap" })
Tab:CreateInput({ Name = "Key", Icon = "lucide:key-round" })

local Window = Airflow:CreateWindow({ Name = "My Hub", Icon = 132608042600488 })
Window:CreateTab({ Name = "Custom", Icon = "rbxassetid://132608042600488" })
Tab:CreateButton({ Name = "Tinted", Icon = { Image = 132608042600488, Tint = true } })
Tab:CreateButton({
    Name = "Sprite",
    Icon = { Image = "rbxassetid://122605056588923", RectOffset = Vector2.new(325, 775), RectSize = Vector2.new(24, 24) },
})
```

| Form | Treated as |
| --- | --- |
| `"zap"` / `"lucide:zap"` | Lucide icon, tinted by the theme. |
| `132608042600488` / `"132608042600488"` / `"rbxassetid://…"` / `"rbxthumb://…"` | Your own image, shown in its own colours. |
| `{ Image, RectOffset, RectSize, Tint }` | Your own image or a sprite. `Tint = true` lets the theme colour it like a lucide icon. |

Custom images keep their colours through theme changes and are drawn 35% larger than their slot, since uploaded images usually carry transparent padding. A table icon can set its own `Scale` (`Scale = 1` for the exact slot size). On tabs and sub tabs, a custom icon shows the selection by going from dimmed to full opacity instead of changing colour. The default bird logo is still tinted with the accent.

Names resolve through the [Footagesus/Icons](https://github.com/Footagesus/Icons) list, fetched once on first use; `Airflow:PreloadIcons()` fetches it up front.

---

## Fonts

> Download a font once and use it everywhere.

```lua
Airflow:LoadFont({ Name = "ValleySans" })

Airflow:LoadFont({
    Name = "MyFont",
    Folder = "AirFlowFonts",
    Weights = {
        Regular = "https://example.com/MyFont-Regular.ttf",
        Medium = "https://example.com/MyFont-Medium.ttf",
        SemiBold = "https://example.com/MyFont-SemiBold.ttf",
    },
})
```

Call it before `CreateWindow`. The TTFs are saved to the folder on first run and reused after that. Needs `writefile`, `isfile` and `getcustomasset`; without them the default Builder Sans stays.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | — | Family name. `"ValleySans"` uses the built-in URLs. |
| `Folder` | string | `"AirFlowFonts"` | Where the TTFs and family file are saved. |
| `Weights` | table | preset | `Regular`, `Medium`, `SemiBold`, `Bold` → TTF URL. |

---

## Theme

> Colours, fonts and assets. Themes switch live: every themed colour in the window fades to the new one.

```lua
Airflow:SetTheme("Midnight")
Airflow:SetTheme({ Accent = Color3.fromRGB(128, 160, 246), Background = "#0F121A" })

Airflow:SetDefaultTheme("Synthwave") -- the script's starting theme
local Window = Airflow:CreateWindow({ Name = "Airflow", DefaultTheme = "Synthwave" }) -- same thing

Settings:CreateThemeManager({ Name = "Themes", Side = "Right" })

Airflow.ThemePresets.Neon = { Accent = Color3.fromRGB(0, 255, 170) }

local Family = "rbxasset://fonts/families/BuilderSans.json"
Airflow.Fonts.Regular = Font.new(Family, Enum.FontWeight.Regular)
Airflow.Fonts.Medium = Font.new(Family, Enum.FontWeight.Medium)
Airflow.Fonts.Bold = Font.new(Family, Enum.FontWeight.SemiBold)

Airflow.Assets.Logo = "rbxassetid://103859712365480"
Airflow.Assets.Glow = "rbxassetid://8992230677"
Airflow.Assets.Shadow = "rbxassetid://6014261993"
```

Presets: `Airflow` (default), `Obsidian`, `Nebula`, `Synthwave`, `Sakura`, `Velvet`, `Rose`, `Crimson`, `Sunset`, `Amber`, `Gold`, `Cyber`, `Toxic`, `Matcha`, `Emerald`, `Aurora`, `Ocean`, `Frost`, `Midnight`, `Abyss`, `Mono`. `SetTheme` takes a preset name or a table of any keys below, as `Color3`, `"#RRGGBB"` or `{ r, g, b }`. Pass `true` as the second argument to skip the fade.

The theme manager is a groupbox with a **Preset** picker, **Weather** and **Weather Mode** pickers, **Dim**, **Transparent** and **Drag Skeleton** switches, a **UI Scale** slider (applied when you let go of it) and a **Density** picker, a name box and **Create** to save the current colours, a **Theme** picker for saved themes, **Save** / **Load**, **Delete** / **Set Default**, the current default, and colour pickers for the main colours (`Customize = false` hides them). On start the window applies the player's default (set with **Set Default**, a preset or a saved theme); without one it applies the script's default from `Airflow:SetDefaultTheme` or the `Theme` window option. Themes are saved in `<config folder>/themes`.

### Properties

| Name | Used for |
| --- | --- |
| `Background` | Window, toast and dialog fill. |
| `Surface` | Chips, text boxes, popups. |
| `Surface2` | Element cards, groupboxes, option rows. |
| `Surface3` | Toggle pill off, tracks, buttons, selected tab. |
| `Stroke` | Outlines at rest. |
| `StrokeHover` | Outlines on hover, focus, open. |
| `Accent` | Highlights, primary buttons, checkboxes, progress bars. |
| `AccentDark` | Text on accent surfaces. |
| `Text` / `Muted` | Primary and secondary text. |
| `Success` / `Warning` / `Error` | Notification title tints. |
| `Fonts.Regular` / `Medium` / `Bold` | Body text / titles and chips / emphasis. |
| `Assets.Logo` / `Glow` / `Shadow` | Sidebar mark, glow decal, drop shadow. |

### Handle

| Member | Description |
| --- | --- |
| `Airflow:SetTheme(nameOrTable, instant?)` | Apply a preset or colours live. |
| `Airflow:GetTheme()` | Copy of the current colours. |
| `Airflow:SetDefaultTheme(nameOrTable)` / `GetDefaultTheme()` | The script's starting theme. Call it before or after `CreateWindow`; it applies right away unless the player saved their own default. |
| `Airflow.ThemePresets` | The presets, by name. Add your own. |
| `Window:SaveTheme(name)` / `LoadTheme(name)` / `DeleteTheme(name)` / `ListThemes()` | Saved themes. `LoadTheme` also accepts a preset name. |
| `Window:SetDefaultTheme(name?)` / `GetDefaultTheme()` | The player's saved default, applied on start. Wins over the script default. |
| `Tab:CreateThemeManager(opts)` | `Name`, `Icon`, `Side`, `Customize`, `Colors = { { key, label } }`, `Weather` (`false` hides the weather dropdown), `Dim` (`false` hides the dim toggle), `Transparent` and `DragSkeleton` (`false` hides those toggles), `Scale` and `Density` (`false` hides the UI scale slider or the density picker), `Background` (`false` hides the background image dropdown, id/link box and opacity slider). The weather dropdowns cover the weather and its mode, screen-wide or inside the window. Configs save the theme (palette, preset or theme name, weather, dim, transparent, drag skeleton, UI scale, density, background image and opacity) under one hidden flag, `__Theme` by default; `Flag` renames it, `Flag = false` leaves the theme out of configs. |

`Airflow.Touch` is `true` on touch-only devices; cards, chips and hit areas are larger there automatically.
