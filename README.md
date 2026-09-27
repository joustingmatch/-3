# Airflow UI

> A UI library for Roblox. Windows, tabs, sub tabs, collapsible groupboxes and thirteen elements with lucide icons and eased motion.

```lua
local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"))()
```

Every constructor also works without the `Create` prefix. `Tab:Toggle` is the same as `Tab:CreateToggle`. Every element handle also has `Destroy()`, which removes the card, its listeners and its flag.

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
    Profile = true,
    Search = true,
    Loading = {
        Enabled = true,
        Title = "Airflow",
        Text = "Starting",
        Steps = { "Preparing interface", "Loading icons", "Almost there" },
        Duration = 1.6,
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

Drag any empty area to move it and the grip in the bottom-right corner to resize it. While resizing, the top-left corner stays put and the size follows the pointer through a spring, so it glides and settles instead of snapping. It scales itself down on small screens and stays inside the viewport.

The bottom of the sidebar shows the player's headshot, display name and the current game. Clicking it opens the home tab.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Airflow"` | Title in the sidebar header. Also names the ScreenGui. |
| `LoadingSubtitle` | string | — | Small line under the title. |
| `Icon` | string \| table | bird logo | Lucide name, `rbxassetid://` string, or `{ Image, RectOffset, RectSize }`. |
| `ToggleUIKeybind` | string \| KeyCode | `"RightControl"` | Hides and shows the window. `"RightShift"`, `"LeftAlt"`, `"Insert"`, `"F1"`, or an `Enum.KeyCode`. |
| `Size` | UDim2 | `760 × 520` | Starting size. |
| `MinSize` | Vector2 | `480 × 360` | Smallest size the resize grip allows. |
| `MaxSize` | Vector2 | unlimited | Largest size the resize grip allows. |
| `MaxNotifications` | number | `4` | Oldest toast is dismissed past this. |
| `KeepOnScreen` | boolean | `true` | Nudge the window back inside the viewport after a drag, resize or screen change. |
| `OpenButton` | boolean \| table | touch-only devices | Floating pill that reopens the window. `true` / `false` to force, `{ Title, Icon }` to customise. |
| `Profile` | boolean | `true` | Player card at the bottom of the sidebar. |
| `Search` | boolean | `true` | Search box in the top-right of the content area. See [Search](#search). |
| `Loading` | boolean \| table | `true` | Loading card before the window morphs in. `false` skips it. |
| `Loading.Title` | string | `Name` | Title on the card. |
| `Loading.Text` | string | `LoadingSubtitle` | First status line. |
| `Loading.Steps` | table | 3 built-in lines | Status lines cycled over the duration. |
| `Loading.Duration` | number | `1.6` | Seconds before the window appears. |
| `ConfigurationSaving` | table | — | See [Configs](#configs). |
| `Home` | boolean \| table | `{}` | The built-in first tab. `false` removes it. See [Home](#home). |
| `Parent` | Instance | `gethui()` / CoreGui | Where the ScreenGui goes. Falls back to PlayerGui. |

### Handle

| Member | Description |
| --- | --- |
| `.Open` | Whether the window is shown. |
| `.CurrentTab` | The selected tab. |
| `.Tabs` | Array of tabs. |
| `.Home` | The home tab, unless `Home = false`. |
| `.SearchBox` | The search TextBox. |
| `Toggle(open?)` | Show, hide, or flip. |
| `SetKeybind(keyCode)` | Change the hide key. Updates the chip on the home tab. |
| `SetKeepOnScreen(enabled)` | Turn the viewport clamp on or off. |
| `SetHideName(hidden)` / `SetHideAvatar(hidden)` | Hide the player's name or headshot everywhere, same as the home switches. |
| `SelectTab(tab)` | Switch tabs from code. |
| `CreateTab(opts)` | See [Tab](#tab). |
| `Rejoin()` / `ServerHop()` / `JoinLowestServer()` | Teleport to this server, a random open one, or the emptiest one. |
| `CopyToClipboard(text, what?)` | Copy and show a toast. |
| `Notify(opts)` | See [Notification](#notification). |
| `Confirm(opts)` / `Dialog(opts)` | See [Confirm](#confirm). |
| `SaveConfig / LoadConfig / DeleteConfig / ListConfigs` | See [Configs](#configs). |
| `Destroy()` | Fade out, disconnect everything, remove the gui. |

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

The first tab created is selected automatically. An empty tab shows its icon with `EmptyText`. Elements added straight to a tab stack as full-width cards. Groupboxes go into two columns underneath them.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Tab"` | Sidebar label and page title. |
| `PageTitle` | string | `Name` | Page heading when it should differ from the sidebar label. |
| `Desc` | string | — | Muted line under the page title. |
| `Icon` | string \| table | — | Sidebar and page icon, accent-tinted. |
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

The first sub tab is selected automatically. Once a tab has sub tabs, add elements and groupboxes to the sub tabs, not the tab. The pill row scrolls sideways when it overflows.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Page n"` | Pill label. |
| `Icon` | string \| table | — | Optional icon in the pill. |
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

Inside a groupbox, elements are compact rows without their own card. Dropdowns and inputs take the same share of the row so their boxes line up, and buttons fill the width. Click the header or the `−` to collapse it. Without `Side`, each new groupbox goes to the column with fewer boxes.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Groupbox"` | Header title. |
| `Icon` | string \| table | — | Accent icon on the right of the header. |
| `Side` | `"Left"` \| `"Right"` \| 1 \| 2 | balanced | Column. |
| `Collapsed` | boolean | `false` | Start collapsed. |

### Handle

| Member | Description |
| --- | --- |
| every element constructor | Adds a row to the groupbox. |
| `Collapse()` / `Expand()` / `SetCollapsed(bool)` | Animate closed or open. |
| `IsCollapsed()` | Current state. |
| `SetTitle(text)` | Rename the header. |
| `Destroy()` | Remove the groupbox and its elements. |

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

> A 1px line.

```lua
Tab:CreateDivider()
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
| `Icon` | string \| table | — | Leading icon. |
| `Style` | string | — | `"Primary"` fills the card with the accent colour. |
| `Callback` | function | — | Runs on click. |

### Handle

| Member | Description |
| --- | --- |
| `SetText(text)` | Replace the label. |

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

### Handle

| Member | Description |
| --- | --- |
| `.Value` | The current value. |
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

> Pick one option, or several.

```lua
local Dropdown = Tab:CreateDropdown({
    Name = "Camera mode",
    Desc = "Applied to the current camera",
    Options = { "Classic", "Follow", "Orbital", "Track" },
    CurrentOption = "Classic",
    MultipleOptions = false,
    SearchAfter = 6,
    Flag = "CameraMode",
    Callback = function(Option)
        print("Camera mode:", Option)
    end,
})

Dropdown:Set("Follow")
```

Clicking the selected row unchecks it. Lists longer than `SearchAfter` get a search box.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Name` | string | `"Dropdown"` | The label. |
| `Desc` | string | — | Hint text under the label. |
| `Options` | table | `{}` | The rows. |
| `CurrentOption` | string \| table | — | The initial selection. A table in multi mode. |
| `MultipleOptions` | boolean | `false` | Rows toggle independently and the callback receives a list. |
| `SearchAfter` | number | `6` | Row count that turns the search box on. |
| `Flag` | string | — | The save key. |
| `Callback` | function | — | Runs with the selection on every change. `nil` when unchecked. |

### Handle

| Member | Description |
| --- | --- |
| `.Open` | Whether the list is expanded. |
| `Set(value, skipCallback?)` | Select a value, or a list in multi mode. |
| `Refresh(options, keepSelection?)` | Replace the rows. |
| `SetOpen(open)` | Expand or collapse. |
| `Get()` | The current selection. |

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
| `Icon` | string \| table | — | Icon inside the box. |
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
| `Icon` | string \| table | — | Icon before the title. |
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
| `Icon` | string \| table | — | Icon before the heading. |
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

> Save every flagged element to a file and load it back.

```lua
local Window = Airflow:CreateWindow({
    Name = "Airflow",
    ConfigurationSaving = { Enabled = true, FolderName = "MyHub", FileName = "default" },
})

-- create tabs and elements

Window:LoadConfig()
```

Requires `writefile` / `readfile`. Keybinds are stored by key name, colours as RGB components. Call `LoadConfig` after every element exists.

### Properties

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `Enabled` | boolean | `true` | Auto-save 0.5 s after any flagged element changes. |
| `FolderName` | string | `"AirflowUI"` | Folder in the executor workspace. |
| `FileName` | string | `"default"` | Config used when no name is given. |

### Handle

| Member | Description |
| --- | --- |
| `Window:SaveConfig(name?)` | Write `<folder>/<name>.json`. Returns `ok, err`. |
| `Window:LoadConfig(name?, skipCallbacks?)` | Apply a saved config. |
| `Window:DeleteConfig(name)` | Remove the file. |
| `Window:ListConfigs()` | Sorted list of saved names. |
| `Tab:CreateConfigManager({ Name })` | Name input, saved-config dropdown, Save / Load / Delete and an auto-save toggle. Returns `Save / Load / Delete / Refresh`. |

---

## Icons

> Any lucide icon, anywhere an `Icon` is accepted.

```lua
Airflow:PreloadIcons()

Window:CreateTab({ Name = "Main", Icon = "zap" })
Tab:CreateButton({ Name = "Rejoin", Icon = "refresh-cw" })
Tab:CreateInput({ Name = "Key", Icon = "lucide:key-round" })
Window:CreateTab({ Name = "Custom", Icon = "rbxassetid://103859712365480" })
Tab:CreateButton({
    Name = "Sprite",
    Icon = { Image = "rbxassetid://122605056588923", RectOffset = Vector2.new(325, 775), RectSize = Vector2.new(24, 24) },
})
```

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

> Colours, fonts and assets. Change them before creating a window.

```lua
Airflow.Theme.Background = Color3.fromRGB(20, 16, 20)
Airflow.Theme.Surface = Color3.fromRGB(24, 19, 24)
Airflow.Theme.Surface2 = Color3.fromRGB(28, 22, 28)
Airflow.Theme.Surface3 = Color3.fromRGB(42, 36, 43)
Airflow.Theme.Stroke = Color3.fromRGB(40, 32, 41)
Airflow.Theme.StrokeHover = Color3.fromRGB(88, 70, 90)
Airflow.Theme.Accent = Color3.fromRGB(235, 199, 246)
Airflow.Theme.AccentDark = Color3.fromRGB(24, 18, 26)
Airflow.Theme.Text = Color3.fromRGB(233, 229, 234)
Airflow.Theme.Muted = Color3.fromRGB(125, 115, 126)
Airflow.Theme.Success = Color3.fromRGB(150, 220, 170)
Airflow.Theme.Warning = Color3.fromRGB(240, 176, 108)
Airflow.Theme.Error = Color3.fromRGB(240, 120, 120)

local Family = "rbxasset://fonts/families/BuilderSans.json"
Airflow.Fonts.Regular = Font.new(Family, Enum.FontWeight.Regular)
Airflow.Fonts.Medium = Font.new(Family, Enum.FontWeight.Medium)
Airflow.Fonts.Bold = Font.new(Family, Enum.FontWeight.SemiBold)

Airflow.Assets.Logo = "rbxassetid://103859712365480"
Airflow.Assets.Glow = "rbxassetid://8992230677"
Airflow.Assets.Shadow = "rbxassetid://6014261993"
```

### Properties

| Name | Used for |
| --- | --- |
| `Background` | Window, toast and dialog fill. |
| `Surface` | Chips, text boxes, option rows. |
| `Surface2` | Element cards, selected tab. |
| `Surface3` | Toggle pill off, tracks. |
| `Stroke` | Outlines at rest. |
| `StrokeHover` | Outlines on hover, focus, open. |
| `Accent` | Highlights, primary buttons, indicator, progress bars. |
| `AccentDark` | Text on accent surfaces. |
| `Text` / `Muted` | Primary and secondary text. |
| `Success` / `Warning` / `Error` | Notification title tints. |
| `Fonts.Regular` / `Medium` / `Bold` | Body text / titles and chips / emphasis. |
| `Assets.Logo` / `Glow` / `Shadow` | Header mark, glow decal, drop shadow. |

`Airflow.Touch` is `true` on touch-only devices; cards, chips and hit areas are larger there automatically.
