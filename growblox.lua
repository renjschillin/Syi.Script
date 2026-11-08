--[[
    Growblox | Delta Safe Build v4
    absolute ollie -- built by olivia
    discord.gg/ojailbreaks

    FIX: wrapped entire script in pcall
         no game:GetDescendants() on load (too heavy for Delta)
         PlayerGui parent always (no CoreGui test crash)
         all heavy work deferred with task.spawn / task.wait
]]--

-- wrap everything so a single error never kills the script
local ok, err = pcall(function()

-- ── SERVICES ──────────────────────────────────
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local WS           = workspace

-- ── PLAYER ────────────────────────────────────
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

-- ── SAFE CALL ─────────────────────────────────
local function safe(fn, ...)
    local ok2, e = pcall(fn, ...)
    if not ok2 then print("[GB] "..tostring(e)) end
    return ok2
end

-- ── STATE ─────────────────────────────────────
local S = {
    noclip     = false,
    fly        = false,
    immortal   = false,
    antiDanger = true,
    autoTake   = false,
    autoBreak  = false,
    autoPlant  = false,
    autoFarm   = false,
    autoTele   = false,
    telePos    = nil,
    lastFarm   = 0,
    lastDanger = 0,
    safePos    = nil,
    lastSafe   = 0,
    flyBV      = nil,
}

-- ── REMOTES ───────────────────────────────────
-- LIGHTWEIGHT scan: only RS children + 2 levels
-- NOT game:GetDescendants() — that freezes Delta
local R = {}

local function scanLight(root2, name)
    -- level 1
    for _, v in ipairs(root2:GetChildren()) do
        if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction"))
        and v.Name:lower():find(name:lower()) then
            return v
        end
        -- level 2
        for _, v2 in ipairs(v:GetChildren()) do
            if (v2:IsA("RemoteEvent") or v2:IsA("RemoteFunction"))
            and v2.Name:lower():find(name:lower()) then
                return v2
            end
            -- level 3
            for _, v3 in ipairs(v2:GetChildren()) do
                if (v3:IsA("RemoteEvent") or v3:IsA("RemoteFunction"))
                and v3.Name:lower():find(name:lower()) then
                    return v3
                end
            end
        end
    end
    return nil
end

local function bindRemotes()
    local names = {
        world   = "WorldRemote",
        break_  = "Break",
        collect = "Collect",
        plant   = "Plant",
        place   = "Place",
    }
    for key, name in pairs(names) do
        local found = scanLight(RS, name) or scanLight(WS, name)
        if found then R[key] = found end
    end
    -- if no specific break found, use world
    if not R.break_  and R.world then R.break_  = R.world end
    if not R.collect and R.world then R.collect = R.world end
    if not R.plant   and R.world then R.plant   = R.world end
end

-- defer remote bind — don't block execution
task.spawn(function()
    task.wait(1)
    bindRemotes()
    task.spawn(function()
        while true do
            task.wait(8)
            bindRemotes()
        end
    end)
end)

-- lightweight spy — only RS and WS, max 3 levels
local function spyRemotes()
    print("\n===== GROWBLOX SPY =====")
    local n = 0
    local function scan3(parent, depth)
        depth = depth or 0
        if depth > 3 then return end
        for _, v in ipairs(parent:GetChildren()) do
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") or v:IsA("BindableEvent") then
                print("[" .. v.ClassName .. "] " .. v:GetFullName())
                n = n + 1
            end
            safe(function() scan3(v, depth+1) end)
        end
    end
    safe(function() scan3(RS) end)
    safe(function() scan3(WS) end)
    print("===== " .. n .. " found =====\n")
end

-- ── WORLD HELPERS ─────────────────────────────
local BPATS = {"block","tile","wall","wood","stone","rock","ore",
               "tree","bush","crop","plant","dirt","grass","log","gem","barrel"}
local SPATS = {"soil","dirt","plot","empty","farm","bed","ground","patch"}
local DPATS = {"lava","spike","thorn","cactus","acid","fire",
               "magma","void","instakill","trap","saw","hazard","kill"}

local function getNear(pats, range)
    local out = {}
    if not root then return out end
    for _, v in ipairs(WS:GetDescendants()) do
        if v:IsA("BasePart") and not v:IsDescendantOf(char) then
            if (v.Position - root.Position).Magnitude <= range then
                local n = v.Name:lower()
                for _, p in ipairs(pats) do
                    if n:find(p) then table.insert(out, v) break end
                end
            end
        end
    end
    return out
end

local function getDrops(range)
    local out = {}
    if not root then return out end
    for _, v in ipairs(WS:GetDescendants()) do
        if v:IsA("BasePart") and not v:IsDescendantOf(char) then
            if (v.Position - root.Position).Magnitude <= range then
                local hasTag = v:FindFirstChildWhichIsA("BillboardGui")
                           or v:FindFirstChildWhichIsA("Highlight")
                local n = v.Name:lower()
                if hasTag or n:find("drop") or n:find("gem") or n:find("seed")
                or n:find("loot") or n:find("fruit") or n:find("item")
                or n:find("pickup") or n:find("coin") then
                    table.insert(out, v)
                end
            end
        end
    end
    return out
end

-- ── ANTI-DANGER HEARTBEAT ─────────────────────
RunService.Heartbeat:Connect(function()
    if not getChar() then return end
    local now = tick()

    -- save safe pos every 2s
    if (now - S.lastSafe) >= 2 then
        S.lastSafe = now
        local nearDanger = false
        for _, v in ipairs(WS:GetDescendants()) do
            if v:IsA("BasePart") then
                local n2 = v.Name:lower()
                for _, dp in ipairs(DPATS) do
                    if n2:find(dp) then
                        if (v.Position - root.Position).Magnitude <= 8 then
                            nearDanger = true
                            break
                        end
                    end
                end
            end
            if nearDanger then break end
        end
        if not nearDanger then
            S.safePos = root.Position
        end
    end

    -- escape danger
    if S.antiDanger and (now - S.lastDanger) >= 0.25 then
        for _, v in ipairs(WS:GetDescendants()) do
            if v:IsA("BasePart") then
                local n2 = v.Name:lower()
                local isDanger = false
                for _, dp in ipairs(DPATS) do
                    if n2:find(dp) then isDanger = true break end
                end
                if isDanger and (v.Position - root.Position).Magnitude <= 8 then
                    S.lastDanger = now
                    safe(function()
                        if S.safePos then
                            root.CFrame = CFrame.new(S.safePos + Vector3.new(0, 8, 0))
                        else
                            root.CFrame = root.CFrame + Vector3.new(0, 10, 0)
                        end
                        if hum then hum.Health = hum.MaxHealth end
                    end)
                    break
                end
            end
        end
    end

    -- immortal
    if S.immortal and hum and hum.Health < hum.MaxHealth then
        safe(function() hum.Health = hum.MaxHealth end)
    end
end)

-- ── NOCLIP ────────────────────────────────────
RunService.Stepped:Connect(function()
    if not S.noclip then return end
    if not getChar() then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end)

-- ── FLY ───────────────────────────────────────
local function enableFly()
    if not getChar() then return end
    safe(function()
        local existing = root:FindFirstChild("GBFly")
        if existing then existing:Destroy() end
        local bv = Instance.new("BodyVelocity")
        bv.Name     = "GBFly"
        bv.Velocity  = Vector3.new(0,0,0)
        bv.MaxForce  = Vector3.new(0,1e5,0)
        bv.Parent    = root
        S.flyBV      = bv
    end)
end

local function disableFly()
    safe(function()
        if root then
            local bv = root:FindFirstChild("GBFly")
            if bv then bv:Destroy() end
        end
        S.flyBV = nil
    end)
end

RunService.Heartbeat:Connect(function()
    if not S.fly then return end
    if not getChar() then return end
    if not S.flyBV then enableFly() end
    safe(function()
        if S.flyBV then
            local v = root.AssemblyLinearVelocity
            S.flyBV.Velocity = Vector3.new(v.X, 0, v.Z)
        end
    end)
end)

-- ── AUTO TAKE ─────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not S.autoTake then return end
    if not getChar() then return end
    for _, item in ipairs(getDrops(25)) do
        local pos = item:IsA("BasePart") and item.Position
            or (function()
                local pp = item:FindFirstChildWhichIsA("BasePart")
                return pp and pp.Position
            end)()
        if pos then
            safe(function() root.CFrame = CFrame.new(pos + Vector3.new(0,2.5,0)) end)
            if R.collect then safe(function() R.collect:FireServer(item) end) end
        end
        task.wait(0.06)
    end
end)

-- ── AUTO BREAK ────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not S.autoBreak then return end
    if not getChar() then return end
    for _, b in ipairs(getNear(BPATS, 20)) do
        if R.break_ then safe(function() R.break_:FireServer(b) end) end
        task.wait(0.09)
    end
end)

-- ── AUTO PLANT ────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not S.autoPlant then return end
    if not getChar() then return end
    for _, s in ipairs(getNear(SPATS, 15)) do
        if R.plant then safe(function() R.plant:FireServer(s) end) end
        task.wait(0.14)
    end
end)

-- ── AUTO TELE ─────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not S.autoTele then return end
    if not getChar() then return end
    if not S.telePos then return end
    safe(function() root.CFrame = CFrame.new(S.telePos) end)
end)

-- ── AUTO FARM ─────────────────────────────────
local function farmCycle()
    if not getChar() then return end
    for _, b in ipairs(getNear(BPATS, 20)) do
        if R.break_ then safe(function() R.break_:FireServer(b) end) end
        task.wait(0.08)
    end
    task.wait(0.2)
    for _, item in ipairs(getDrops(25)) do
        local pos = item:IsA("BasePart") and item.Position
            or (function()
                local pp = item:FindFirstChildWhichIsA("BasePart")
                return pp and pp.Position
            end)()
        if pos then
            safe(function() root.CFrame = CFrame.new(pos + Vector3.new(0,2.5,0)) end)
            if R.collect then safe(function() R.collect:FireServer(item) end) end
        end
        task.wait(0.06)
    end
    task.wait(0.2)
    if R.plant then
        for _, s in ipairs(getNear(SPATS, 15)) do
            safe(function() R.plant:FireServer(s) end)
            task.wait(0.12)
        end
    end
end

RunService.Heartbeat:Connect(function()
    if not S.autoFarm then return end
    local now = tick()
    if (now - S.lastFarm) >= 0.4 then
        S.lastFarm = now
        task.spawn(farmCycle)
    end
end)

-- ── RESPAWN ───────────────────────────────────
lp.CharacterAdded:Connect(function(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    task.wait(0.3)
    bindRemotes()
    if S.fly then task.wait(0.2) enableFly() end
end)

-- ═══════════════════════════════════════════════
-- GUI
-- Uses lp.PlayerGui — safest on Delta, no test crash
-- ═══════════════════════════════════════════════

-- destroy old
safe(function()
    local o = lp.PlayerGui:FindFirstChild("GrowbloxHub")
    if o then o:Destroy() end
end)
safe(function()
    local o = game.CoreGui:FindFirstChild("GrowbloxHub")
    if o then o:Destroy() end
end)

local sg = Instance.new("ScreenGui")
sg.Name           = "GrowbloxHub"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = false
sg.DisplayOrder   = 999
sg.Parent         = lp.PlayerGui      -- always PlayerGui on Delta

-- drag helper
local function makeDrag(frame, handle)
    handle = handle or frame
    local d, sp, sf = false, nil, nil
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            d=true sp=Vector2.new(inp.Position.X,inp.Position.Y) sf=frame.Position
        end
    end)
    handle.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch
        or inp.UserInputType==Enum.UserInputType.MouseButton1 then d=false end
    end)
    handle.InputChanged:Connect(function(inp)
        if not d or not sp then return end
        if inp.UserInputType==Enum.UserInputType.Touch
        or inp.UserInputType==Enum.UserInputType.MouseMovement then
            local dv=Vector2.new(inp.Position.X,inp.Position.Y)-sp
            frame.Position=UDim2.new(sf.X.Scale,sf.X.Offset+dv.X,sf.Y.Scale,sf.Y.Offset+dv.Y)
        end
    end)
end

-- open button top-right
local openBtn = Instance.new("TextButton")
openBtn.Size             = UDim2.new(0, 60, 0, 60)
openBtn.Position         = UDim2.new(1, -75, 0, 80)
openBtn.BackgroundColor3 = Color3.fromRGB(22, 185, 85)
openBtn.BorderSizePixel  = 0
openBtn.Text             = "GB"
openBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
openBtn.TextSize         = 18
openBtn.Font             = Enum.Font.GothamBold
openBtn.ZIndex           = 100
openBtn.Active           = true
openBtn.Parent           = sg
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(1, 0)
local os2 = Instance.new("UIStroke")
os2.Color = Color3.fromRGB(255,255,255) os2.Thickness = 2 os2.Parent = openBtn
makeDrag(openBtn)

-- glow
local glow = Instance.new("Frame")
glow.Size             = UDim2.new(0, 316, 0, 652)
glow.Position         = UDim2.new(0.5,-158,0.5,-326)
glow.BackgroundColor3 = Color3.fromRGB(0,0,0)
glow.BorderSizePixel  = 0
glow.ZIndex           = 98
glow.Visible          = false
glow.Parent           = sg
Instance.new("UICorner", glow).CornerRadius = UDim.new(0,18)
local gg = Instance.new("UIGradient")
gg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(22,200,85)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12,110,48)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(22,200,85)),
})
gg.Rotation=135 gg.Parent=glow

-- panel
local panel = Instance.new("Frame")
panel.Size             = UDim2.new(0,312,0,648)
panel.Position         = UDim2.new(0.5,-156,0.5,-324)
panel.BackgroundColor3 = Color3.fromRGB(10,13,20)
panel.BorderSizePixel  = 0
panel.ZIndex           = 99
panel.Visible          = false
panel.Active           = true
panel.Parent           = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16)
local pg = Instance.new("UIGradient")
pg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(14,20,32)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(8,11,18)),
})
pg.Rotation=130 pg.Parent=panel
makeDrag(panel)

openBtn.MouseButton1Click:Connect(function()
    panel.Visible=not panel.Visible
    glow.Visible=panel.Visible
end)

-- header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1,0,0,52)
header.BackgroundColor3 = Color3.fromRGB(0,0,0)
header.BorderSizePixel  = 0
header.ZIndex           = 100
header.Parent           = panel
Instance.new("UICorner",header).CornerRadius = UDim.new(0,16)
local hg = Instance.new("UIGradient")
hg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,  Color3.fromRGB(16,155,68)),
    ColorSequenceKeypoint.new(.5, Color3.fromRGB(10,95,44)),
    ColorSequenceKeypoint.new(1,  Color3.fromRGB(16,155,68)),
})
hg.Rotation=90 hg.Parent=header

local titleL = Instance.new("TextLabel")
titleL.Size=UDim2.new(.72,0,1,0) titleL.Position=UDim2.new(0,14,0,0)
titleL.BackgroundTransparency=1 titleL.Text="GROWBLOX HUB"
titleL.TextColor3=Color3.fromRGB(215,255,215) titleL.TextSize=16
titleL.Font=Enum.Font.GothamBold titleL.TextXAlignment=Enum.TextXAlignment.Left
titleL.ZIndex=101 titleL.Parent=header

local closeBtn = Instance.new("TextButton")
closeBtn.Size=UDim2.new(0,36,0,36) closeBtn.Position=UDim2.new(1,-44,.5,-18)
closeBtn.BackgroundColor3=Color3.fromRGB(185,48,48) closeBtn.Text="X"
closeBtn.TextColor3=Color3.fromRGB(255,255,255) closeBtn.TextSize=13
closeBtn.Font=Enum.Font.GothamBold closeBtn.BorderSizePixel=0
closeBtn.ZIndex=102 closeBtn.Parent=header
Instance.new("UICorner",closeBtn).CornerRadius=UDim.new(0,8)
closeBtn.MouseButton1Click:Connect(function()
    panel.Visible=false glow.Visible=false
end)

local subL = Instance.new("TextLabel")
subL.Size=UDim2.new(1,0,0,16) subL.Position=UDim2.new(0,0,0,52)
subL.BackgroundTransparency=1
subL.Text="absolute ollie  built by olivia  discord.gg/ojailbreaks"
subL.TextColor3=Color3.fromRGB(38,145,68) subL.TextSize=9
subL.Font=Enum.Font.Gotham subL.ZIndex=100 subL.Parent=panel

-- spy button
local spyBtn = Instance.new("TextButton")
spyBtn.Size=UDim2.new(1,-18,0,36) spyBtn.Position=UDim2.new(0,9,0,72)
spyBtn.BackgroundColor3=Color3.fromRGB(0,0,0)
spyBtn.Text="SPY REMOTES  (check Delta console)"
spyBtn.TextColor3=Color3.fromRGB(255,210,55) spyBtn.TextSize=11
spyBtn.Font=Enum.Font.GothamSemibold spyBtn.BorderSizePixel=0
spyBtn.ZIndex=100 spyBtn.Parent=panel
Instance.new("UICorner",spyBtn).CornerRadius=UDim.new(0,10)
local spyG = Instance.new("UIGradient")
spyG.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(75,60,8)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(48,38,5)),
})
spyG.Rotation=90 spyG.Parent=spyBtn
spyBtn.MouseButton1Click:Connect(function()
    spyBtn.Text="Spying..."
    task.spawn(function()
        spyRemotes()
        task.wait(1.2)
        spyBtn.Text="SPY REMOTES  (check Delta console)"
    end)
end)

local remL = Instance.new("TextLabel")
remL.Size=UDim2.new(1,-18,0,16) remL.Position=UDim2.new(0,9,0,112)
remL.BackgroundTransparency=1 remL.Text="remotes: binding..."
remL.TextColor3=Color3.fromRGB(180,180,60) remL.TextSize=10
remL.Font=Enum.Font.Gotham remL.TextXAlignment=Enum.TextXAlignment.Left
remL.ZIndex=100 remL.Parent=panel

-- scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size=UDim2.new(1,-14,1,-192) scroll.Position=UDim2.new(0,7,0,132)
scroll.BackgroundTransparency=1 scroll.BorderSizePixel=0
scroll.ScrollBarThickness=3
scroll.ScrollBarImageColor3=Color3.fromRGB(22,180,85)
scroll.CanvasSize=UDim2.new(0,0,0,0)
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
scroll.ZIndex=100 scroll.Parent=panel

local listL = Instance.new("UIListLayout")
listL.Padding=UDim.new(0,7) listL.SortOrder=Enum.SortOrder.LayoutOrder
listL.Parent=scroll
local listP = Instance.new("UIPadding")
listP.PaddingLeft=UDim.new(0,2) listP.PaddingRight=UDim.new(0,2)
listP.PaddingTop=UDim.new(0,3) listP.PaddingBottom=UDim.new(0,6)
listP.Parent=scroll

local TI = TweenInfo.new(0.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)

-- section header
local function sec(txt, ord)
    local l=Instance.new("TextLabel")
    l.Size=UDim2.new(1,0,0,20) l.BackgroundTransparency=1
    l.Text="  "..txt l.TextColor3=Color3.fromRGB(55,160,75)
    l.TextSize=10 l.Font=Enum.Font.GothamBold
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.LayoutOrder=ord l.ZIndex=100 l.Parent=scroll
end

-- toggle row
local function tog(tag,label,desc,key,ord,onCol,cb)
    onCol=onCol or Color3.fromRGB(22,190,85)
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,0,0,62) row.BackgroundColor3=Color3.fromRGB(0,0,0)
    row.BorderSizePixel=0 row.LayoutOrder=ord row.ZIndex=101 row.Parent=scroll
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,12)
    local rg=Instance.new("UIGradient")
    rg.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(17,23,36)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(11,15,24)),
    })
    rg.Rotation=90 rg.Parent=row
    local acc=Instance.new("Frame")
    acc.Size=UDim2.new(0,3,.6,0) acc.Position=UDim2.new(0,0,.2,0)
    acc.BackgroundColor3=Color3.fromRGB(48,52,72)
    acc.BorderSizePixel=0 acc.ZIndex=102 acc.Parent=row
    Instance.new("UICorner",acc).CornerRadius=UDim.new(1,0)
    local bub=Instance.new("TextLabel")
    bub.Size=UDim2.new(0,36,0,36) bub.Position=UDim2.new(0,10,.5,-18)
    bub.BackgroundColor3=Color3.fromRGB(0,0,0) bub.Text=tag
    bub.TextSize=11 bub.Font=Enum.Font.GothamBold
    bub.TextColor3=Color3.fromRGB(200,220,200)
    bub.BorderSizePixel=0 bub.ZIndex=102 bub.Parent=row
    Instance.new("UICorner",bub).CornerRadius=UDim.new(0,9)
    local bg=Instance.new("UIGradient")
    bg.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(20,26,42)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(13,17,28)),
    })
    bg.Rotation=90 bg.Parent=bub
    local ml=Instance.new("TextLabel")
    ml.Size=UDim2.new(.57,0,0,20) ml.Position=UDim2.new(0,54,0,10)
    ml.BackgroundTransparency=1 ml.Text=label
    ml.TextColor3=Color3.fromRGB(225,242,225) ml.TextSize=13
    ml.Font=Enum.Font.GothamBold ml.TextXAlignment=Enum.TextXAlignment.Left
    ml.ZIndex=102 ml.Parent=row
    local dl=Instance.new("TextLabel")
    dl.Size=UDim2.new(.6,0,0,15) dl.Position=UDim2.new(0,54,0,32)
    dl.BackgroundTransparency=1 dl.Text=desc
    dl.TextColor3=Color3.fromRGB(70,120,80) dl.TextSize=10
    dl.Font=Enum.Font.Gotham dl.TextXAlignment=Enum.TextXAlignment.Left
    dl.ZIndex=102 dl.Parent=row
    local track=Instance.new("Frame")
    track.Size=UDim2.new(0,50,0,26) track.Position=UDim2.new(1,-58,.5,-13)
    track.BackgroundColor3=Color3.fromRGB(36,42,58)
    track.BorderSizePixel=0 track.ZIndex=102 track.Parent=row
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)
    local dot=Instance.new("Frame")
    dot.Size=UDim2.new(0,20,0,20) dot.Position=UDim2.new(0,3,.5,-10)
    dot.BackgroundColor3=Color3.fromRGB(255,255,255)
    dot.BorderSizePixel=0 dot.ZIndex=103 dot.Parent=track
    Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,1,0) btn.BackgroundTransparency=1
    btn.Text="" btn.ZIndex=104 btn.Parent=row
    local function ref()
        local on=S[key]
        TweenService:Create(track,TI,{BackgroundColor3=on and onCol or Color3.fromRGB(36,42,58)}):Play()
        TweenService:Create(dot,TI,{Position=on and UDim2.new(0,27,.5,-10) or UDim2.new(0,3,.5,-10)}):Play()
        acc.BackgroundColor3=on and onCol or Color3.fromRGB(48,52,72)
    end
    ref()
    btn.MouseButton1Click:Connect(function()
        S[key]=not S[key] ref()
        if cb then cb(S[key]) end
    end)
end

-- tele row
local function teleRow(ord)
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,0,0,74) row.BackgroundColor3=Color3.fromRGB(0,0,0)
    row.BorderSizePixel=0 row.LayoutOrder=ord row.ZIndex=101 row.Parent=scroll
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,12)
    local rg=Instance.new("UIGradient")
    rg.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(17,20,38)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(11,14,26)),
    })
    rg.Rotation=90 rg.Parent=row
    local acc=Instance.new("Frame")
    acc.Size=UDim2.new(0,3,.6,0) acc.Position=UDim2.new(0,0,.2,0)
    acc.BackgroundColor3=Color3.fromRGB(48,52,72)
    acc.BorderSizePixel=0 acc.ZIndex=102 acc.Parent=row
    Instance.new("UICorner",acc).CornerRadius=UDim.new(1,0)
    local bub=Instance.new("TextLabel")
    bub.Size=UDim2.new(0,36,0,36) bub.Position=UDim2.new(0,10,.5,-18)
    bub.BackgroundColor3=Color3.fromRGB(0,0,0) bub.Text="TP"
    bub.TextSize=11 bub.Font=Enum.Font.GothamBold
    bub.TextColor3=Color3.fromRGB(160,195,255)
    bub.BorderSizePixel=0 bub.ZIndex=102 bub.Parent=row
    Instance.new("UICorner",bub).CornerRadius=UDim.new(0,9)
    local ml=Instance.new("TextLabel")
    ml.Size=UDim2.new(.42,0,0,20) ml.Position=UDim2.new(0,54,0,6)
    ml.BackgroundTransparency=1 ml.Text="Teleport"
    ml.TextColor3=Color3.fromRGB(160,195,255) ml.TextSize=13
    ml.Font=Enum.Font.GothamBold ml.TextXAlignment=Enum.TextXAlignment.Left
    ml.ZIndex=102 ml.Parent=row
    local cl=Instance.new("TextLabel")
    cl.Size=UDim2.new(.52,0,0,14) cl.Position=UDim2.new(0,54,0,28)
    cl.BackgroundTransparency=1 cl.Text="tap Set to lock coords"
    cl.TextColor3=Color3.fromRGB(70,100,155) cl.TextSize=9
    cl.Font=Enum.Font.Gotham cl.TextXAlignment=Enum.TextXAlignment.Left
    cl.ZIndex=102 cl.Parent=row
    local setB=Instance.new("TextButton")
    setB.Size=UDim2.new(0,44,0,22) setB.Position=UDim2.new(0,54,0,46)
    setB.BackgroundColor3=Color3.fromRGB(45,85,195) setB.Text="Set"
    setB.TextColor3=Color3.fromRGB(255,255,255) setB.TextSize=11
    setB.Font=Enum.Font.GothamSemibold setB.BorderSizePixel=0
    setB.ZIndex=103 setB.Parent=row
    Instance.new("UICorner",setB).CornerRadius=UDim.new(0,7)
    local goB=Instance.new("TextButton")
    goB.Size=UDim2.new(0,44,0,22) goB.Position=UDim2.new(0,102,0,46)
    goB.BackgroundColor3=Color3.fromRGB(22,180,85) goB.Text="Go"
    goB.TextColor3=Color3.fromRGB(255,255,255) goB.TextSize=11
    goB.Font=Enum.Font.GothamSemibold goB.BorderSizePixel=0
    goB.ZIndex=103 goB.Parent=row
    Instance.new("UICorner",goB).CornerRadius=UDim.new(0,7)
    local track=Instance.new("Frame")
    track.Size=UDim2.new(0,50,0,26) track.Position=UDim2.new(1,-58,.5,-13)
    track.BackgroundColor3=Color3.fromRGB(36,42,58)
    track.BorderSizePixel=0 track.ZIndex=102 track.Parent=row
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)
    local dot=Instance.new("Frame")
    dot.Size=UDim2.new(0,20,0,20) dot.Position=UDim2.new(0,3,.5,-10)
    dot.BackgroundColor3=Color3.fromRGB(255,255,255)
    dot.BorderSizePixel=0 dot.ZIndex=103 dot.Parent=track
    Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
    local tBtn=Instance.new("TextButton")
    tBtn.Size=UDim2.new(0,50,0,26) tBtn.Position=UDim2.new(1,-58,.5,-13)
    tBtn.BackgroundTransparency=1 tBtn.Text="" tBtn.ZIndex=105 tBtn.Parent=row
    local tCol=Color3.fromRGB(80,125,255)
    local function ref2()
        local on=S.autoTele
        TweenService:Create(track,TI,{BackgroundColor3=on and tCol or Color3.fromRGB(36,42,58)}):Play()
        TweenService:Create(dot,TI,{Position=on and UDim2.new(0,27,.5,-10) or UDim2.new(0,3,.5,-10)}):Play()
        acc.BackgroundColor3=on and tCol or Color3.fromRGB(48,52,72)
    end
    setB.MouseButton1Click:Connect(function()
        if getChar() then
            S.telePos=root.Position
            cl.Text=string.format("X%.0f Y%.0f Z%.0f",root.Position.X,root.Position.Y,root.Position.Z)
            setB.BackgroundColor3=Color3.fromRGB(22,175,80)
            task.delay(.6,function() setB.BackgroundColor3=Color3.fromRGB(45,85,195) end)
        end
    end)
    goB.MouseButton1Click:Connect(function()
        if getChar() and S.telePos then
            safe(function() root.CFrame=CFrame.new(S.telePos) end)
            goB.BackgroundColor3=Color3.fromRGB(180,220,60)
            task.delay(.4,function() goB.BackgroundColor3=Color3.fromRGB(22,180,85) end)
        end
    end)
    tBtn.MouseButton1Click:Connect(function() S.autoTele=not S.autoTele ref2() end)
    ref2()
end

-- build layout
sec("PROTECTION",1)
tog("AD","Anti-Lava/Spike","Escape danger tiles instantly","antiDanger",2,Color3.fromRGB(230,90,40))
tog("HP","Immortal",       "Lock health at max",           "immortal",  3,Color3.fromRGB(220,60,60))
sec("MOVEMENT",4)
tog("NC","Noclip",  "Walk through walls",         "noclip",5,Color3.fromRGB(230,95,45))
tog("FY","Fly",     "Float, no fall damage",      "fly",   6,Color3.fromRGB(80,160,240),
    function(on) if on then enableFly() else disableFly() end end)
teleRow(7)
sec("FARMING",8)
tog("TK","Auto Take", "Collect nearby drops",    "autoTake",  9, Color3.fromRGB(22,195,85))
tog("BK","Auto Break","Break nearby blocks",     "autoBreak", 10,Color3.fromRGB(220,75,55))
tog("PL","Auto Plant","Plant on empty soil",     "autoPlant", 11,Color3.fromRGB(75,205,75))
tog("FM","Auto Farm", "Break+collect+plant loop","autoFarm",  12,Color3.fromRGB(220,175,38))

-- status bar
local sBar=Instance.new("Frame")
sBar.Size=UDim2.new(1,0,0,30) sBar.Position=UDim2.new(0,0,1,-30)
sBar.BackgroundColor3=Color3.fromRGB(0,0,0) sBar.BorderSizePixel=0
sBar.ZIndex=100 sBar.Parent=panel
Instance.new("UICorner",sBar).CornerRadius=UDim.new(0,16)
local sbG2=Instance.new("UIGradient")
sbG2.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,  Color3.fromRGB(9,68,32)),
    ColorSequenceKeypoint.new(.5, Color3.fromRGB(13,90,44)),
    ColorSequenceKeypoint.new(1,  Color3.fromRGB(9,68,32)),
})
sbG2.Rotation=90 sbG2.Parent=sBar
local sL=Instance.new("TextLabel")
sL.Size=UDim2.new(1,-10,1,0) sL.Position=UDim2.new(0,10,0,0)
sL.BackgroundTransparency=1 sL.Text="ready"
sL.TextColor3=Color3.fromRGB(55,195,95) sL.TextSize=10
sL.Font=Enum.Font.Gotham sL.TextXAlignment=Enum.TextXAlignment.Left
sL.ZIndex=101 sL.Parent=sBar

-- ticker
task.spawn(function()
    while true do
        task.wait(1)
        local rc=0 for _ in pairs(R) do rc=rc+1 end
        remL.Text = rc>0 and ("remotes: "..rc.." locked  OK") or "no remotes — tap SPY"
        remL.TextColor3 = rc>0 and Color3.fromRGB(55,200,95) or Color3.fromRGB(220,155,45)
        local a={}
        if S.antiDanger then table.insert(a,"AD") end
        if S.immortal   then table.insert(a,"HP") end
        if S.noclip     then table.insert(a,"NC") end
        if S.fly        then table.insert(a,"FY") end
        if S.autoTake   then table.insert(a,"TK") end
        if S.autoBreak  then table.insert(a,"BK") end
        if S.autoPlant  then table.insert(a,"PL") end
        if S.autoFarm   then table.insert(a,"FM") end
        if S.autoTele   then table.insert(a,"TP") end
        sL.Text = #a>0 and ("on: "..table.concat(a," ")) or "all off"
        sL.TextColor3 = #a>0 and Color3.fromRGB(55,195,95) or Color3.fromRGB(85,95,115)
    end
end)

-- deferred spy on load
task.spawn(function()
    task.wait(3)
    spyRemotes()
end)

print("[GB] v4 loaded -- discord.gg/ojailbreaks")

end) -- end pcall

if not ok then
    print("[GB LOAD ERROR] " .. tostring(err))
end
