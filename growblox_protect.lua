--[[
    Growblox | Protection Script
    absolute ollie -- built by olivia
    discord.gg/ojailbreaks

    Dangerous blocks referenced from Growtopia wiki:
    DEADLY  → Death Spikes, Spike, Cave Spikes, Egg Shell Spikes
    PAIN    → Lava, Acid, Fire, Steam Vent, Lava Pinata
    VOID    → falling below world floor

    Delta mobile safe. Pure client. No remotes needed.
    GUI button: big red GB, top-right corner.
]]--

local ok, err = pcall(function()

-- ── Services
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local WS           = workspace

-- ── Refs
local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local root, hum

local function getChar()
    char = lp.Character
    if not char then return false end
    root = char:FindFirstChild("HumanoidRootPart")
    hum  = char:FindFirstChild("Humanoid")
    return root ~= nil and hum ~= nil
end
getChar()

local function safe(fn, ...)
    local ok2, e = pcall(fn, ...)
    if not ok2 then print("[GB] "..tostring(e)) end
    return ok2
end

-- ── State
local S = {
    antiDanger = true,
    immortal   = false,
    noclip     = false,
    autoTele   = false,
    telePos    = nil,
    safePos    = nil,
    lastSafe   = 0,
    lastDanger = 0,
}

-- ── Growtopia-based danger names
-- Exact block names from Growtopia that Growblox replicates
local DEADLY = {
    -- Death Spikes variants
    "DeathSpikes", "Death Spikes", "death_spikes", "DeathSpike",
    "Death Spike", "CaveSpikes", "Cave Spikes", "EggShellSpikes",
    "Egg Shell Spikes", "DangerousBlock", "Deadly", "InstakillBlock",
    -- Spike variants
    "Spike", "Spikes", "SpikeBlock", "SpikeTrap",
    -- other deadly
    "Portcullis", "Saw", "Blade", "Buzzsaw",
}

local PAIN = {
    -- Lava variants (Growtopia pain block)
    "Lava", "LavaBlock", "Lava Block", "LavaTile",
    "MagmaBlock", "Magma", "LavaFlow",
    -- Acid variants
    "Acid", "AcidBlock", "Acid Block", "ToxicWaste",
    "Toxic Waste Barrel", "Toxic",
    -- Fire variants
    "Fire", "FireBlock", "Fire Block", "Flame",
    "EliteFire", "Eldritch",
    -- Steam / Heat
    "SteamVent", "Steam Vent", "Steam", "Vent",
    -- misc pain
    "Lava Pinata", "LavaPinata", "Burn",
}

-- check if a part name matches any danger list
local function matchList(name, list)
    local low = name:lower()
    for _, d in ipairs(list) do
        if low:find(d:lower(), 1, true) then return true end
    end
    return false
end

local function isDanger(part)
    return matchList(part.Name, DEADLY) or matchList(part.Name, PAIN)
end

-- scan only parts within range — no full WS scan on every frame
local function getNearDanger(range)
    if not root then return nil end
    for _, v in ipairs(WS:GetDescendants()) do
        if v:IsA("BasePart") and not v:IsDescendantOf(char) then
            if (v.Position - root.Position).Magnitude <= range then
                if isDanger(v) then return v end
            end
        end
    end
    return nil
end

-- ── Main protection loop
RunService.Heartbeat:Connect(function()
    if not getChar() then return end
    local now = tick()

    -- save safe position every 1.5s when clear of danger
    if (now - S.lastSafe) >= 1.5 then
        S.lastSafe = now
        if not getNearDanger(10) and root.Position.Y > -100 then
            S.safePos = root.Position
        end
    end

    -- anti-danger: escape when touching a dangerous block
    if S.antiDanger and (now - S.lastDanger) >= 0.2 then
        local d = getNearDanger(6)
        if d then
            S.lastDanger = now
            safe(function()
                local escape = S.safePos
                    and CFrame.new(S.safePos + Vector3.new(0, 7, 0))
                    or  (root.CFrame + Vector3.new(0, 12, 0))
                root.CFrame = escape
                if hum then hum.Health = hum.MaxHealth end
            end)
        end
    end

    -- anti-void: Y under -100 means fell out of world
    if S.antiDanger and root.Position.Y < -100 then
        safe(function()
            if S.safePos then
                root.CFrame = CFrame.new(S.safePos + Vector3.new(0, 7, 0))
            else
                root.CFrame = CFrame.new(0, 60, 0)
            end
        end)
    end

    -- immortal
    if S.immortal and hum and hum.Health < hum.MaxHealth then
        safe(function() hum.Health = hum.MaxHealth end)
    end

    -- auto tele
    if S.autoTele and S.telePos then
        safe(function() root.CFrame = CFrame.new(S.telePos) end)
    end
end)

-- noclip
RunService.Stepped:Connect(function()
    if not S.noclip then return end
    if not getChar() then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end)

-- respawn
lp.CharacterAdded:Connect(function(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
end)

-- ══════════════════════════════════════════════
-- GUI
-- ══════════════════════════════════════════════
safe(function()
    local o = lp.PlayerGui:FindFirstChild("GBProtect")
    if o then o:Destroy() end
end)

local sg = Instance.new("ScreenGui")
sg.Name           = "GBProtect"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder   = 999
sg.Parent         = lp.PlayerGui

-- drag helper
local function mkDrag(f, h)
    h = h or f
    local drag, sp, sf = false, nil, nil
    h.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag=true
            sp=Vector2.new(i.Position.X, i.Position.Y)
            sf=f.Position
        end
    end)
    h.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag=false
        end
    end)
    h.InputChanged:Connect(function(i)
        if not drag or not sp then return end
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = Vector2.new(i.Position.X, i.Position.Y) - sp
            f.Position = UDim2.new(
                sf.X.Scale, sf.X.Offset+d.X,
                sf.Y.Scale, sf.Y.Offset+d.Y
            )
        end
    end)
end

-- ── Open button — top right, big red circle
local openBtn = Instance.new("TextButton")
openBtn.Size             = UDim2.new(0, 65, 0, 65)
openBtn.Position         = UDim2.new(1, -78, 0, 72)
openBtn.BackgroundColor3 = Color3.fromRGB(210, 50, 50)
openBtn.BorderSizePixel  = 0
openBtn.Text             = "GB"
openBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
openBtn.TextSize         = 20
openBtn.Font             = Enum.Font.GothamBold
openBtn.ZIndex           = 100
openBtn.Active           = true
openBtn.Parent           = sg
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(1, 0)
local ost = Instance.new("UIStroke")
ost.Color=Color3.fromRGB(255,180,180) ost.Thickness=2.5 ost.Parent=openBtn
mkDrag(openBtn)

-- ── Glow behind panel
local glow = Instance.new("Frame")
glow.Size             = UDim2.new(0, 294, 0, 428)
glow.Position         = UDim2.new(0.5, -147, 0.5, -214)
glow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
glow.BorderSizePixel  = 0
glow.ZIndex           = 98
glow.Visible          = false
glow.Parent           = sg
Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 17)
local gg = Instance.new("UIGradient")
gg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(210, 55, 55)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 25, 25)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(210, 55, 55)),
})
gg.Rotation=135 gg.Parent=glow

-- ── Panel
local panel = Instance.new("Frame")
panel.Size             = UDim2.new(0, 290, 0, 424)
panel.Position         = UDim2.new(0.5, -145, 0.5, -212)
panel.BackgroundColor3 = Color3.fromRGB(11, 12, 20)
panel.BorderSizePixel  = 0
panel.ZIndex           = 99
panel.Visible          = false
panel.Active           = true
panel.Parent           = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local pg = Instance.new("UIGradient")
pg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 18, 32)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8,  10, 18)),
})
pg.Rotation=130 pg.Parent=panel
mkDrag(panel)

openBtn.MouseButton1Click:Connect(function()
    panel.Visible = not panel.Visible
    glow.Visible  = panel.Visible
    if panel.Visible then
        glow.Position = UDim2.new(
            panel.Position.X.Scale, panel.Position.X.Offset-2,
            panel.Position.Y.Scale, panel.Position.Y.Offset-2
        )
    end
end)

-- ── Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
header.BorderSizePixel  = 0
header.ZIndex           = 100
header.Parent           = panel
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)
local hg = Instance.new("UIGradient")
hg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(175, 40, 40)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 22, 22)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(175, 40, 40)),
})
hg.Rotation=90 hg.Parent=header

local titleL = Instance.new("TextLabel")
titleL.Size=UDim2.new(0.76,0,1,0) titleL.Position=UDim2.new(0,14,0,0)
titleL.BackgroundTransparency=1 titleL.Text=" GROWBLOX PROTECT"
titleL.TextColor3=Color3.fromRGB(255,215,215) titleL.TextSize=15
titleL.Font=Enum.Font.GothamBold
titleL.TextXAlignment=Enum.TextXAlignment.Left
titleL.ZIndex=101 titleL.Parent=header

local closeBtn = Instance.new("TextButton")
closeBtn.Size=UDim2.new(0,34,0,34)
closeBtn.Position=UDim2.new(1,-42,0.5,-17)
closeBtn.BackgroundColor3=Color3.fromRGB(55,18,18)
closeBtn.Text="X" closeBtn.TextColor3=Color3.fromRGB(255,160,160)
closeBtn.TextSize=13 closeBtn.Font=Enum.Font.GothamBold
closeBtn.BorderSizePixel=0 closeBtn.ZIndex=102 closeBtn.Parent=header
Instance.new("UICorner",closeBtn).CornerRadius=UDim.new(0,8)
closeBtn.MouseButton1Click:Connect(function()
    panel.Visible=false glow.Visible=false
end)

-- subtitle
local subL = Instance.new("TextLabel")
subL.Size=UDim2.new(1,0,0,14) subL.Position=UDim2.new(0,0,0,52)
subL.BackgroundTransparency=1
subL.Text="absolute ollie  built by olivia  discord.gg/ojailbreaks"
subL.TextColor3=Color3.fromRGB(100,42,42) subL.TextSize=9
subL.Font=Enum.Font.Gotham subL.ZIndex=100 subL.Parent=panel

-- ── danger info box
local infoBox = Instance.new("Frame")
infoBox.Size=UDim2.new(1,-18,0,46) infoBox.Position=UDim2.new(0,9,0,70)
infoBox.BackgroundColor3=Color3.fromRGB(0,0,0)
infoBox.BorderSizePixel=0 infoBox.ZIndex=100 infoBox.Parent=panel
Instance.new("UICorner",infoBox).CornerRadius=UDim.new(0,10)
local ibG=Instance.new("UIGradient")
ibG.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(50,20,10)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(30,12,6)),
})
ibG.Rotation=90 ibG.Parent=infoBox

local infoL=Instance.new("TextLabel")
infoL.Size=UDim2.new(1,-12,1,0) infoL.Position=UDim2.new(0,8,0,0)
infoL.BackgroundTransparency=1
infoL.Text="Detects: Lava  Acid  Fire  Death Spikes  Spike  Steam Vent  Void"
infoL.TextColor3=Color3.fromRGB(220,140,80) infoL.TextSize=10
infoL.Font=Enum.Font.Gotham
infoL.TextXAlignment=Enum.TextXAlignment.Left
infoL.TextWrapped=true infoL.ZIndex=101 infoL.Parent=infoBox

-- ── TI
local TI = TweenInfo.new(0.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)

-- ── Toggle row builder
local function mkRow(icon, label, desc, key, yOff, onCol, cb)
    onCol = onCol or Color3.fromRGB(210,55,55)

    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,-18,0,60) row.Position=UDim2.new(0,9,0,yOff)
    row.BackgroundColor3=Color3.fromRGB(0,0,0)
    row.BorderSizePixel=0 row.ZIndex=100 row.Parent=panel
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,12)
    local rg=Instance.new("UIGradient")
    rg.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(19,22,36)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(12,14,24)),
    })
    rg.Rotation=90 rg.Parent=row

    local acc=Instance.new("Frame")
    acc.Size=UDim2.new(0,3,0.6,0) acc.Position=UDim2.new(0,0,0.2,0)
    acc.BackgroundColor3=Color3.fromRGB(50,45,70)
    acc.BorderSizePixel=0 acc.ZIndex=101 acc.Parent=row
    Instance.new("UICorner",acc).CornerRadius=UDim.new(1,0)

    local iconL=Instance.new("TextLabel")
    iconL.Size=UDim2.new(0,38,0,38) iconL.Position=UDim2.new(0,10,0.5,-19)
    iconL.BackgroundColor3=Color3.fromRGB(0,0,0) iconL.Text=icon
    iconL.TextSize=19 iconL.Font=Enum.Font.GothamBold
    iconL.TextColor3=Color3.fromRGB(255,255,255)
    iconL.BorderSizePixel=0 iconL.ZIndex=101 iconL.Parent=row
    Instance.new("UICorner",iconL).CornerRadius=UDim.new(0,10)
    local ig=Instance.new("UIGradient")
    ig.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(26,22,44)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(16,14,28)),
    })
    ig.Rotation=90 ig.Parent=iconL

    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(0.57,0,0,20) lbl.Position=UDim2.new(0,56,0,9)
    lbl.BackgroundTransparency=1 lbl.Text=label
    lbl.TextColor3=Color3.fromRGB(240,235,255) lbl.TextSize=13
    lbl.Font=Enum.Font.GothamBold
    lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.ZIndex=101 lbl.Parent=row

    local dL=Instance.new("TextLabel")
    dL.Size=UDim2.new(0.6,0,0,14) dL.Position=UDim2.new(0,56,0,31)
    dL.BackgroundTransparency=1 dL.Text=desc
    dL.TextColor3=Color3.fromRGB(85,78,115) dL.TextSize=10
    dL.Font=Enum.Font.Gotham
    dL.TextXAlignment=Enum.TextXAlignment.Left
    dL.ZIndex=101 dL.Parent=row

    local track=Instance.new("Frame")
    track.Size=UDim2.new(0,50,0,26) track.Position=UDim2.new(1,-58,0.5,-13)
    track.BackgroundColor3=Color3.fromRGB(34,30,52)
    track.BorderSizePixel=0 track.ZIndex=101 track.Parent=row
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

    local dot=Instance.new("Frame")
    dot.Size=UDim2.new(0,20,0,20) dot.Position=UDim2.new(0,3,0.5,-10)
    dot.BackgroundColor3=Color3.fromRGB(255,255,255)
    dot.BorderSizePixel=0 dot.ZIndex=102 dot.Parent=track
    Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)

    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,1,0) btn.BackgroundTransparency=1
    btn.Text="" btn.ZIndex=103 btn.Parent=row

    local function ref()
        local on=S[key]
        TweenService:Create(track,TI,{
            BackgroundColor3=on and onCol or Color3.fromRGB(34,30,52)
        }):Play()
        TweenService:Create(dot,TI,{
            Position=on and UDim2.new(0,27,0.5,-10) or UDim2.new(0,3,0.5,-10)
        }):Play()
        acc.BackgroundColor3=on and onCol or Color3.fromRGB(50,45,70)
    end
    ref()

    btn.MouseButton1Click:Connect(function()
        S[key]=not S[key] ref()
        if cb then cb(S[key]) end
    end)
end

-- ── Tele row
local function mkTeleRow(yOff)
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,-18,0,76) row.Position=UDim2.new(0,9,0,yOff)
    row.BackgroundColor3=Color3.fromRGB(0,0,0)
    row.BorderSizePixel=0 row.ZIndex=100 row.Parent=panel
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,12)
    local rg=Instance.new("UIGradient")
    rg.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(16,18,38)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(10,12,24)),
    })
    rg.Rotation=90 rg.Parent=row

    local acc=Instance.new("Frame")
    acc.Size=UDim2.new(0,3,0.6,0) acc.Position=UDim2.new(0,0,0.2,0)
    acc.BackgroundColor3=Color3.fromRGB(50,45,70)
    acc.BorderSizePixel=0 acc.ZIndex=101 acc.Parent=row
    Instance.new("UICorner",acc).CornerRadius=UDim.new(1,0)

    local iconL=Instance.new("TextLabel")
    iconL.Size=UDim2.new(0,38,0,38) iconL.Position=UDim2.new(0,10,0.5,-19)
    iconL.BackgroundColor3=Color3.fromRGB(0,0,0) iconL.Text="TP"
    iconL.TextSize=13 iconL.Font=Enum.Font.GothamBold
    iconL.TextColor3=Color3.fromRGB(150,190,255)
    iconL.BorderSizePixel=0 iconL.ZIndex=101 iconL.Parent=row
    Instance.new("UICorner",iconL).CornerRadius=UDim.new(0,10)

    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(0.5,0,0,20) lbl.Position=UDim2.new(0,56,0,6)
    lbl.BackgroundTransparency=1 lbl.Text="Teleport"
    lbl.TextColor3=Color3.fromRGB(150,190,255) lbl.TextSize=13
    lbl.Font=Enum.Font.GothamBold lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.ZIndex=101 lbl.Parent=row

    local coordL=Instance.new("TextLabel")
    coordL.Size=UDim2.new(0.55,0,0,13) coordL.Position=UDim2.new(0,56,0,27)
    coordL.BackgroundTransparency=1 coordL.Text="tap Set to lock coords"
    coordL.TextColor3=Color3.fromRGB(75,95,155) coordL.TextSize=9
    coordL.Font=Enum.Font.Gotham coordL.TextXAlignment=Enum.TextXAlignment.Left
    coordL.ZIndex=101 coordL.Parent=row

    local setB=Instance.new("TextButton")
    setB.Size=UDim2.new(0,56,0,24) setB.Position=UDim2.new(0,56,0,46)
    setB.BackgroundColor3=Color3.fromRGB(45,80,195) setB.Text="Set Pos"
    setB.TextColor3=Color3.fromRGB(255,255,255) setB.TextSize=11
    setB.Font=Enum.Font.GothamSemibold setB.BorderSizePixel=0
    setB.ZIndex=102 setB.Parent=row
    Instance.new("UICorner",setB).CornerRadius=UDim.new(0,7)

    local goB=Instance.new("TextButton")
    goB.Size=UDim2.new(0,56,0,24) goB.Position=UDim2.new(0,116,0,46)
    goB.BackgroundColor3=Color3.fromRGB(22,175,80) goB.Text="Go Now"
    goB.TextColor3=Color3.fromRGB(255,255,255) goB.TextSize=11
    goB.Font=Enum.Font.GothamSemibold goB.BorderSizePixel=0
    goB.ZIndex=102 goB.Parent=row
    Instance.new("UICorner",goB).CornerRadius=UDim.new(0,7)

    local track=Instance.new("Frame")
    track.Size=UDim2.new(0,50,0,26) track.Position=UDim2.new(1,-58,0.5,-13)
    track.BackgroundColor3=Color3.fromRGB(34,30,52)
    track.BorderSizePixel=0 track.ZIndex=101 track.Parent=row
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

    local dot=Instance.new("Frame")
    dot.Size=UDim2.new(0,20,0,20) dot.Position=UDim2.new(0,3,0.5,-10)
    dot.BackgroundColor3=Color3.fromRGB(255,255,255)
    dot.BorderSizePixel=0 dot.ZIndex=102 dot.Parent=track
    Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)

    local tBtn=Instance.new("TextButton")
    tBtn.Size=UDim2.new(0,50,0,26) tBtn.Position=UDim2.new(1,-58,0.5,-13)
    tBtn.BackgroundTransparency=1 tBtn.Text="" tBtn.ZIndex=103 tBtn.Parent=row

    local tCol=Color3.fromRGB(80,125,255)
    local function refT()
        local on=S.autoTele
        TweenService:Create(track,TI,{
            BackgroundColor3=on and tCol or Color3.fromRGB(34,30,52)
        }):Play()
        TweenService:Create(dot,TI,{
            Position=on and UDim2.new(0,27,0.5,-10) or UDim2.new(0,3,0.5,-10)
        }):Play()
        acc.BackgroundColor3=on and tCol or Color3.fromRGB(50,45,70)
    end

    setB.MouseButton1Click:Connect(function()
        if getChar() then
            S.telePos=root.Position
            coordL.Text=string.format("X%.0f  Y%.0f  Z%.0f",
                root.Position.X,root.Position.Y,root.Position.Z)
            setB.BackgroundColor3=Color3.fromRGB(22,170,75)
            task.delay(0.6,function()
                setB.BackgroundColor3=Color3.fromRGB(45,80,195)
            end)
        end
    end)
    goB.MouseButton1Click:Connect(function()
        if getChar() and S.telePos then
            safe(function() root.CFrame=CFrame.new(S.telePos) end)
            goB.BackgroundColor3=Color3.fromRGB(175,215,55)
            task.delay(0.4,function()
                goB.BackgroundColor3=Color3.fromRGB(22,175,80)
            end)
        end
    end)
    tBtn.MouseButton1Click:Connect(function()
        S.autoTele=not S.autoTele refT()
    end)
    refT()
end

-- ── Status bar
local sBar=Instance.new("Frame")
sBar.Size=UDim2.new(1,0,0,30) sBar.Position=UDim2.new(0,0,1,-30)
sBar.BackgroundColor3=Color3.fromRGB(0,0,0)
sBar.BorderSizePixel=0 sBar.ZIndex=100 sBar.Parent=panel
Instance.new("UICorner",sBar).CornerRadius=UDim.new(0,16)
local sbG=Instance.new("UIGradient")
sbG.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,  Color3.fromRGB(55,15,15)),
    ColorSequenceKeypoint.new(.5, Color3.fromRGB(80,22,22)),
    ColorSequenceKeypoint.new(1,  Color3.fromRGB(55,15,15)),
})
sbG.Rotation=90 sbG.Parent=sBar

local sL=Instance.new("TextLabel")
sL.Size=UDim2.new(1,-10,1,0) sL.Position=UDim2.new(0,10,0,0)
sL.BackgroundTransparency=1 sL.Text="ready"
sL.TextColor3=Color3.fromRGB(220,120,120) sL.TextSize=10
sL.Font=Enum.Font.Gotham
sL.TextXAlignment=Enum.TextXAlignment.Left
sL.ZIndex=101 sL.Parent=sBar

-- ── Build rows
-- y positions: infoBox at 70 (h46), rows from 124
mkRow("🔥","Anti-Lava / Spike","Lava, Acid, Spikes, Fire, Void","antiDanger",124,
    Color3.fromRGB(220,80,35))
mkRow("❤️","Immortal",         "Lock health at max",             "immortal",  192,
    Color3.fromRGB(210,45,45))
mkRow("👻","Noclip",           "Walk through all blocks",        "noclip",    260,
    Color3.fromRGB(115,70,210))
mkTeleRow(328)

-- ── Ticker
task.spawn(function()
    while true do
        task.wait(0.8)
        local a={}
        if S.antiDanger then table.insert(a,"PROTECT") end
        if S.immortal   then table.insert(a,"IMMORTAL") end
        if S.noclip     then table.insert(a,"NOCLIP") end
        if S.autoTele   then table.insert(a,"AUTOTELE") end
        sL.Text = #a>0 and table.concat(a,"  ") or "all off"
        sL.TextColor3 = #a>0
            and Color3.fromRGB(220,120,120)
            or  Color3.fromRGB(80,65,110)
    end
end)

print("[GB] protect v5 loaded -- discord.gg/ojailbreaks")

end) -- end pcall

if not ok then
    print("[GB LOAD ERR] "..tostring(err))
end
