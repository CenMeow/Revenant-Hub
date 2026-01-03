--[[
    Revenant Fling Panel (Fates Edition v2)
    修復：
    1. 增加 Network Ownership 鎖定 (解決畫面抖動/目標不飛問題)
    2. 優化瞬移邏輯 (Pre-TP)
    3. 增強物理接觸判定
]]

local Services = setmetatable({}, {
    __index = function(self, key)
        return game:GetService(key)
    end
})

local Players = Services.Players
local RunService = Services.RunService
local UserInputService = Services.UserInputService
local LocalPlayer = Players.LocalPlayer

-- [UI 設定] Fates Admin 風格配色
local Theme = {
    Background = Color3.fromRGB(32, 33, 36),
    TabBackground = Color3.fromRGB(45, 45, 48),
    Text = Color3.fromRGB(220, 224, 234),
    Button = Color3.fromRGB(50, 50, 55),
    ButtonSelected = Color3.fromRGB(70, 130, 180),
    Accent = Color3.fromRGB(0, 120, 215)
}

-- 核心變數
local FlingActive = false
local AegisActive = false
local VoidWalkActive = false
local CurrentTarget = nil
local ManualMode = false
local SelectedPlayers = {}
local FlingLoopConnection = nil
local AegisLoop = nil
local VoidLoop = nil

local function GetRoot(Player)
    local Char = Player.Character
    return Char and (Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChild("Torso") or Char:FindFirstChild("UpperTorso"))
end

local function IsSafe(Player)
    local Char = Player.Character
    if not Char then return true end
    if Char:FindFirstChildOfClass("ForceField") then return true end
    local Root = GetRoot(Player)
    if Root and (Root.Position.Y < -50 or Root.Position.Y > 500) then return true end
    return false
end

local function GetTargets()
    local Targets = {}
    local Mountain = {}
    local Ground = {}
    local CandidatePlayers = {}
    
    if ManualMode then
        for _, Plr in pairs(Players:GetPlayers()) do
            if SelectedPlayers[Plr.UserId] and Plr ~= LocalPlayer then table.insert(CandidatePlayers, Plr) end
        end
    else
        for _, Plr in pairs(Players:GetPlayers()) do
            if Plr ~= LocalPlayer then table.insert(CandidatePlayers, Plr) end
        end
    end
    
    for _, Plr in ipairs(CandidatePlayers) do
        if not IsSafe(Plr) then
            local Root = GetRoot(Plr)
            if Root then
                local Y = Root.Position.Y
                if ManualMode then
                    if Y > 30 then table.insert(Mountain, Plr) else table.insert(Ground, Plr) end
                else
                    if Y > 30 then table.insert(Mountain, Plr) else table.insert(Ground, Plr) end
                end
            end
        end
    end
    for _, v in ipairs(Mountain) do table.insert(Targets, v) end
    for _, v in ipairs(Ground) do table.insert(Targets, v) end
    return Targets
end

-- [系統] 物理邏輯
local function SetupFlingPhysics(Root)
    for _, v in pairs(Root:GetChildren()) do
        if v.Name == "FlingGyro" or v.Name == "FlingMover" then v:Destroy() end
    end
    
    -- [關鍵修復] 奪取物理權限，防止被伺服器拉回或抖動
    if Root:CanSetNetworkOwnership() then
        Root:SetNetworkOwnership(LocalPlayer)
    end
    
    -- 使用 BodyAngularVelocity 製造旋轉動量
    local BAV = Instance.new("BodyAngularVelocity")
    BAV.Name = "FlingGyro"
    BAV.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    BAV.P = math.huge
    BAV.AngularVelocity = Vector3.new(0, 100000, 0) -- 提高轉速
    BAV.Parent = Root

    -- 使用 BodyVelocity 保持懸浮並抵消慣性
    local BV = Instance.new("BodyVelocity")
    BV.Name = "FlingMover"
    BV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    BV.Velocity = Vector3.new(0, 0, 0) 
    BV.P = math.huge
    BV.Parent = Root
    
    -- 讓角色進入 PlatformStand 狀態，避免動畫干擾物理
    local Hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
    if Hum then 
        Hum.PlatformStand = true 
    end
    
    return BAV, BV
end

local function ApplyPhysics(Root, TargetRoot, Step)
    -- [物理微調] 持續重設權限
    if Root:CanSetNetworkOwnership() then
        Root:SetNetworkOwnership(LocalPlayer)
    end
    
    -- 貼在目標中心，並加上微量抖動以觸發物理碰撞
    local Offset = Vector3.new(math.random()-0.5, 0, math.random()-0.5) * 2
    Root.CFrame = CFrame.new(TargetRoot.Position) * CFrame.Angles(0, stats().Network.ServerStatsPing, 0) + Offset
    Root.Velocity = Vector3.new(0, 0, 0) 
    Root.RotVelocity = Vector3.new(0, 20000, 0)
end

-- [系統] 功能開關
local function StopFling()
    FlingActive = false
    if FlingLoopConnection then FlingLoopConnection:Disconnect() end
    local Root = GetRoot(LocalPlayer)
    local Hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
    if Root then
        for _, v in pairs(Root:GetChildren()) do
            if v.Name == "FlingGyro" or v.Name == "FlingMover" then v:Destroy() end
        end
        Root.Velocity = Vector3.new(0,0,0)
        Root.RotVelocity = Vector3.new(0,0,0)
    end
    if Hum then Hum.PlatformStand = false end
    for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = true end
    end
end

local function StartFlingLoop(StatusLabel)
    if FlingActive then return end
    FlingActive = true
    
    local Root = GetRoot(LocalPlayer)
    if not Root then StatusLabel.Text = "錯誤：角色異常" FlingActive = false return end

    local Noclip = RunService.Stepped:Connect(function()
        if not FlingActive then return end
        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
        end
    end)

    local BAV, BV = SetupFlingPhysics(Root)

    task.spawn(function()
        while FlingActive and Root.Parent do
            local Targets = GetTargets()
            
            if #Targets == 0 then
                StatusLabel.Text = ManualMode and "狀態：無選取目標" or "狀態：搜尋目標 (全圖)"
                StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 0)
                if Root:FindFirstChild("FlingMover") then
                    Root.FlingMover:Destroy()
                    Root.FlingGyro:Destroy()
                    Root.Velocity = Vector3.new(0,0,0)
                end
                task.wait(0.5)
            else
                for _, Target in ipairs(Targets) do
                    if not FlingActive then break end
                    if IsSafe(Target) then
                        -- Skip
                    else
                        CurrentTarget = Target
                        StatusLabel.Text = "攻擊中: " .. Target.Name
                        StatusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
                        
                        local TargetRoot = GetRoot(Target)
                        if TargetRoot then
                            local StartTime = tick()
                            local Loop
                            if not Root:FindFirstChild("FlingGyro") then SetupFlingPhysics(Root) end
                            
                            -- [Pre-TP] 先瞬移過去再開始 Loop，避免看起來像飛很遠
                            Root.CFrame = TargetRoot.CFrame + Vector3.new(0,2,0)
                            task.wait(0.1)

                            Loop = RunService.Stepped:Connect(function(t, step)
                                if not TargetRoot.Parent then return end
                                ApplyPhysics(Root, TargetRoot, step)
                            end)
                            
                            while FlingActive and TargetRoot.Parent and tick() - StartTime < 2.5 do
                                if IsSafe(Target) then break end
                                RunService.RenderStepped:Wait()
                            end
                            if Loop then Loop:Disconnect() end
                        end
                    end
                end
            end
        end
        Noclip:Disconnect()
        StopFling()
        StatusLabel.Text = "狀態：待命"
        StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    end)
end

-- [防禦] Revenant Aegis
local function ToggleAegis(Enabled)
    AegisActive = Enabled
    if AegisLoop then AegisLoop:Disconnect() end
    if AegisActive then
        AegisLoop = RunService.Stepped:Connect(function()
            if FlingActive then return end 
            local Root = GetRoot(LocalPlayer)
            for _, Plr in pairs(Players:GetPlayers()) do
                if Plr ~= LocalPlayer and Plr.Character then
                    for _, Part in pairs(Plr.Character:GetDescendants()) do
                        if Part:IsA("BasePart") and Part.CanCollide then Part.CanCollide = false end
                    end
                end
            end
            if Root then
                Root.AssemblyAngularVelocity = Vector3.new(0,0,0)
                if Root.AssemblyLinearVelocity.Magnitude > 100 then
                   Root.AssemblyLinearVelocity = Vector3.new(0,0,0)
                end
            end
        end)
    end
end

-- [防禦] Void Walker
local function ToggleVoidWalk(Enabled)
    VoidWalkActive = Enabled
    if VoidLoop then VoidLoop:Disconnect() end
    if VoidWalkActive then
        VoidLoop = RunService.Stepped:Connect(function()
            local Root = GetRoot(LocalPlayer)
            if Root then
                if Root.Position.Y < -400 or (Root.Position.Y < -20 and Root.Velocity.Y < -50) then
                    Root.Velocity = Vector3.new(Root.Velocity.X, 0, Root.Velocity.Z)
                    local CurrentPos = Root.Position
                    local SafeY = -20
                     if CurrentPos.Y < SafeY - 5 then
                       Root.CFrame = CFrame.new(CurrentPos.X, SafeY, CurrentPos.Z) * Root.CFrame.Rotation
                    end
                end
            end
        end)
    end
end

-- [UI 建構] Fates 介面
local Library = {}
function Library:Create(Class, Properties)
    local Inst = Instance.new(Class)
    for k, v in pairs(Properties) do Inst[k] = v end
    return Inst
end

local ScreenGui = Library:Create("ScreenGui", { Name = "RevenantFlingPanel", ResetOnSpawn = false, Parent = game:GetService("CoreGui") })
if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end

local MainFrame = Library:Create("Frame", {
    Name = "MainFrame", Size = UDim2.new(0, 450, 0, 350),
    Position = UDim2.new(0.5, -225, 0.5, -175), BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Parent = ScreenGui
})
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = MainFrame})

local TitleBar = Library:Create("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Background, Parent = MainFrame })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = TitleBar})
Library:Create("TextLabel", { Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = "Revenant 外掛面板", TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = TitleBar })
local CloseBtn = Library:Create("TextButton", { Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -30, 0, 0), BackgroundTransparency = 1, Text = "X", TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.GothamBold, Parent = TitleBar })
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() StopFling() end)

local TabContainer = Library:Create("Frame", { Size = UDim2.new(1, 0, 0, 35), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = Theme.TabBackground, BorderSizePixel = 0, Parent = MainFrame })
local function CreateTabBtn(Name, PosScale)
    local Btn = Library:Create("TextButton", { Size = UDim2.new(0.333, 0, 1, 0), Position = UDim2.new(PosScale, 0, 0, 0), BackgroundTransparency = 1, Text = Name, TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.Gotham, Parent = TabContainer })
    return Btn
end
local Tab1Btn = CreateTabBtn("甩飛功能", 0)
local Tab2Btn = CreateTabBtn("傳送功能", 0.333)
local Tab3Btn = CreateTabBtn("防禦系統", 0.666)

local ContentFrame = Library:Create("Frame", { Size = UDim2.new(1, -20, 1, -75), Position = UDim2.new(0, 10, 0, 70), BackgroundTransparency = 1, Parent = MainFrame })

local Page1 = Library:Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = true, Parent = ContentFrame })
local StatusLabel = Library:Create("TextLabel", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "狀態：待命", TextColor3 = Color3.fromRGB(100, 255, 100), TextSize = 14, Font = Enum.Font.Gotham, Parent = Page1 })
local ModeBtn = Library:Create("TextButton", { Size = UDim2.new(0.48, 0, 0, 30), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = Theme.Button, Text = "模式：自動", TextColor3 = Theme.Text, TextSize = 12, Font = Enum.Font.GothamBold, Parent = Page1 })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = ModeBtn})
local StartBtn = Library:Create("TextButton", { Size = UDim2.new(0.48, 0, 0, 30), Position = UDim2.new(0.52, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(200, 60, 60), Text = "開始甩飛", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 12, Font = Enum.Font.GothamBold, Parent = Page1 })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = StartBtn})
local ListBg = Library:Create("Frame", { Size = UDim2.new(1, 0, 1, -110), Position = UDim2.new(0, 0, 0, 70), BackgroundColor3 = Color3.fromRGB(25, 25, 28), Parent = Page1 })
local PlayerScroll = Library:Create("ScrollingFrame", { Size = UDim2.new(1, -5, 1, -5), Position = UDim2.new(0, 2, 0, 2), BackgroundTransparency = 1, ScrollBarThickness = 2, Parent = ListBg })
Library:Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = PlayerScroll })
local SelectAllBtn = Library:Create("TextButton", { Size = UDim2.new(0.48, 0, 0, 25), Position = UDim2.new(0, 0, 1, -30), BackgroundColor3 = Theme.Button, Text = "全選", TextColor3 = Theme.Text, TextSize = 12, Font = Enum.Font.Gotham, Parent = Page1 })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = SelectAllBtn})
local ClearBtn = Library:Create("TextButton", { Size = UDim2.new(0.48, 0, 0, 25), Position = UDim2.new(0.52, 0, 1, -30), BackgroundColor3 = Theme.Button, Text = "全不選", TextColor3 = Theme.Text, TextSize = 12, Font = Enum.Font.Gotham, Parent = Page1 })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = ClearBtn})

local Page2 = Library:Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, Parent = ContentFrame })
local TPCorners = {
    { text = "傳送至山角 1", pos = Vector3.new(150, 60, 150) },
    { text = "傳送至山角 2", pos = Vector3.new(-150, 60, 150) },
    { text = "傳送至山角 3", pos = Vector3.new(150, 60, -150) },
    { text = "傳送至山角 4", pos = Vector3.new(-150, 60, -150) },
    { text = "傳送至中心 (高空)", pos = Vector3.new(0, 200, 0) }
}
for i, Data in ipairs(TPCorners) do
    local Btn = Library:Create("TextButton", {
        Size = UDim2.new(1, 0, 0, 35), Position = UDim2.new(0, 0, 0, (i-1)*40),
        BackgroundColor3 = Theme.Button, Text = Data.text, TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.Gotham, Parent = Page2
    })
    Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = Btn})
    Btn.MouseButton1Click:Connect(function()
        local Root = GetRoot(LocalPlayer)
        if Root then Root.CFrame = CFrame.new(Data.pos) end
    end)
end

local Page3 = Library:Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, Parent = ContentFrame })
local AegisBtn = Library:Create("TextButton", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Theme.Button, Text = "防甩飛: 關閉", TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.GothamBold, Parent = Page3 })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = AegisBtn})
local VoidBtn = Library:Create("TextButton", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 50), BackgroundColor3 = Theme.Button, Text = "虛空行走: 關閉", TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.GothamBold, Parent = Page3 })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = VoidBtn})

local function SwitchTab(Page)
    Page1.Visible = (Page == 1)
    Page2.Visible = (Page == 2)
    Page3.Visible = (Page == 3)
    Tab1Btn.TextColor3 = (Page == 1) and Theme.Accent or Theme.Text
    Tab2Btn.TextColor3 = (Page == 2) and Theme.Accent or Theme.Text
    Tab3Btn.TextColor3 = (Page == 3) and Theme.Accent or Theme.Text
end
Tab1Btn.MouseButton1Click:Connect(function() SwitchTab(1) end)
Tab2Btn.MouseButton1Click:Connect(function() SwitchTab(2) end)
Tab3Btn.MouseButton1Click:Connect(function() SwitchTab(3) end)
SwitchTab(1)

AegisBtn.MouseButton1Click:Connect(function()
    ToggleAegis(not AegisActive)
    AegisBtn.Text = AegisActive and "防甩飛: 已啟動 (甩飛時自動暫停)" or "防甩飛: 關閉"
    AegisBtn.TextColor3 = AegisActive and Theme.Accent or Theme.Text
end)

VoidBtn.MouseButton1Click:Connect(function()
    ToggleVoidWalk(not VoidWalkActive)
    VoidBtn.Text = VoidWalkActive and "虛空行走: 已啟動" or "虛空行走: 關閉"
    VoidBtn.TextColor3 = VoidWalkActive and Theme.Accent or Theme.Text
end)

StartBtn.MouseButton1Click:Connect(function()
    if FlingActive then StopFling() StartBtn.Text = "開始甩飛" StartBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60) StatusLabel.Text = "狀態：已停止"
    else StartBtn.Text = "停止甩飛" StartBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 0) StartFlingLoop(StatusLabel) end
end)

ModeBtn.MouseButton1Click:Connect(function()
    ManualMode = not ManualMode
    ModeBtn.Text = ManualMode and "模式：手動選取" or "模式：自動"
end)

SelectAllBtn.MouseButton1Click:Connect(function() for _, Plr in pairs(Players:GetPlayers()) do if Plr ~= LocalPlayer then SelectedPlayers[Plr.UserId] = true end end UpdatePlayerList() end)
ClearBtn.MouseButton1Click:Connect(function() SelectedPlayers = {} UpdatePlayerList() end)

function UpdatePlayerList()
    for _, v in pairs(PlayerScroll:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    local Plrs = Players:GetPlayers()
    table.sort(Plrs, function(a,b) return a.Name < b.Name end)
    for _, Plr in ipairs(Plrs) do
        if Plr ~= LocalPlayer then
            local IsSelected = SelectedPlayers[Plr.UserId]
            local Btn = Library:Create("TextButton", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = IsSelected and Theme.Accent or Theme.Button, Text = "  " .. Plr.Name, TextColor3 = Theme.Text, TextSize = 12, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Parent = PlayerScroll })
            Library:Create("UICorner", {CornerRadius = UDim.new(0, 3), Parent = Btn})
            Btn.MouseButton1Click:Connect(function()
                if SelectedPlayers[Plr.UserId] then SelectedPlayers[Plr.UserId] = nil Btn.BackgroundColor3 = Theme.Button
                else SelectedPlayers[Plr.UserId] = true Btn.BackgroundColor3 = Theme.Accent end
            end)
        end
    end
    PlayerScroll.CanvasSize = UDim2.new(0, 0, 0, #Plrs * 27)
end
Players.PlayerAdded:Connect(UpdatePlayerList) Players.PlayerRemoving:Connect(UpdatePlayerList) UpdatePlayerList()

local function MakeDraggable(Frame, DragHandle)
    local Dragging, DragInput, DragStart, StartPos
    DragHandle.InputBegan:Connect(function(Input) if Input.UserInputType == Enum.UserInputType.MouseButton1 then Dragging = true DragStart = Input.Position StartPos = Frame.Position Input.Changed:Connect(function() if Input.UserInputState == Enum.UserInputState.End then Dragging = false end end) end end)
    DragHandle.InputChanged:Connect(function(Input) if Input.UserInputType == Enum.UserInputType.MouseMovement then DragInput = Input end end)
    UserInputService.InputChanged:Connect(function(Input) if Input == DragInput and Dragging then local Delta = Input.Position - DragStart Frame.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y) end end)
end
MakeDraggable(MainFrame, TitleBar)
UserInputService.InputBegan:Connect(function(Input) if Input.KeyCode == Enum.KeyCode.RightControl then MainFrame.Visible = not MainFrame.Visible end end)

print("Revenant Fling Panel (Physics Fix v2) Loaded.")
