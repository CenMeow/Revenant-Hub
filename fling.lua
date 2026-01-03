--[[
    暴力甩飛腳本 (TSB 專業版) - v4.0 (終極防禦版)
    新增：Revenant Aegis (絕對防甩)、Smart Stop (安全區智能停止)、全圖攻擊
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

local Library = {}
function Library:Create(Class, Properties)
    local Inst = Instance.new(Class)
    for k, v in pairs(Properties) do Inst[k] = v end
    return Inst
end

function Library:MakeDraggable(Frame, DragHandle)
    local Dragging, DragInput, DragStart, StartPos
    DragHandle.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            Dragging = true
            DragStart = Input.Position
            StartPos = Frame.Position
            Input.Changed:Connect(function() if Input.UserInputState == Enum.UserInputState.End then Dragging = false end end)
        end
    end)
    DragHandle.InputChanged:Connect(function(Input) if Input.UserInputType == Enum.UserInputType.MouseMovement then DragInput = Input end end)
    UserInputService.InputChanged:Connect(function(Input)
        if Input == DragInput and Dragging then
            local Delta = Input.Position - DragStart
            Frame.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y)
        end
    end)
end

-- 核心變數
local FlingActive = false
local AntiFlingActive = false
local CurrentTarget = nil
local ManualMode = false
local SelectedPlayers = {}
-- 儲存原始碰撞狀態
local OriginalCollision = {} 

local function GetRoot(Player)
    local Char = Player.Character
    return Char and (Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChild("Torso") or Char:FindFirstChild("UpperTorso"))
end

local function IsSafe(Player)
    local Char = Player.Character
    if not Char then return true end
    -- 檢查 ForceField (無敵罩 = 安全區/重生點)
    if Char:FindFirstChildOfClass("ForceField") then return true end
    -- 檢查高度 (避免誤判虚空)
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
                -- 全圖攻擊：只要邏輯上不處於安全區，都在攻擊範圍內
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

-- [Anti-Fling] Revenant Aegis: 虛空幽靈技術
-- 這是目前 Roblox 上最強的防甩飛邏輯之一
local AntiFlingLoop
local function ToggleAntiFling(Enabled, StatusLabel)
    AntiFlingActive = Enabled
    
    if AntiFlingActive then
        StatusLabel.Text = "防禦系統：Revenant anti-fling (已啟動)"
        StatusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
        
        AntiFlingLoop = RunService.Stepped:Connect(function()
            local Root = GetRoot(LocalPlayer)
            
            -- 1. 幽靈模式 (Ghost Mode)
            -- 讓除了自己以外的所有玩家變得 "不可觸碰"
            for _, Plr in pairs(Players:GetPlayers()) do
                if Plr ~= LocalPlayer and Plr.Character then
                    for _, Part in pairs(Plr.Character:GetDescendants()) do
                        if Part:IsA("BasePart") and Part.CanCollide then
                            Part.CanCollide = false
                        end
                    end
                end
            end
            
            -- 2. 物理穩定 (Velocity Lock)
            -- 確保自身不會被不知名的力道推走 (除非正在甩人)
            if Root and not FlingActive then
                Root.AssemblyAngularVelocity = Vector3.new(0,0,0)
                -- 只有當外力過大時才強制歸零線性速度，允許正常走路
                if Root.AssemblyLinearVelocity.Magnitude > 100 then
                   Root.AssemblyLinearVelocity = Vector3.new(0,0,0)
                end
            end
        end)
    else
        StatusLabel.Text = "防禦系統：關閉"
        StatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        if AntiFlingLoop then AntiFlingLoop:Disconnect() end
    end
end

local function SetupFlingPhysics(Root)
    for _, v in pairs(Root:GetChildren()) do
        if v.Name == "FlingGyro" or v.Name == "FlingMover" then v:Destroy() end
    end
    local BAV = Instance.new("BodyAngularVelocity")
    BAV.Name = "FlingGyro"
    BAV.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    BAV.P = math.huge
    BAV.AngularVelocity = Vector3.new(0, 50000, 0)
    BAV.Parent = Root

    local BV = Instance.new("BodyVelocity")
    BV.Name = "FlingMover"
    BV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    BV.Velocity = Vector3.new(0, 0, 0) 
    BV.P = math.huge
    BV.Parent = Root
    return BAV, BV
end

local function ApplyPhysics(Root, TargetRoot, Step)
    local Offset = Vector3.new(math.random(-1,1), 0, math.random(-1,1)) * 0.5
    Root.CFrame = TargetRoot.CFrame + Offset
    Root.Velocity = Vector3.new(0, 0, 0) 
    Root.RotVelocity = Vector3.new(0, 50000, 0)
end

local function StopFling()
    FlingActive = false
    if FlingLoopConnection then FlingLoopConnection:Disconnect() end
    
    local Root = GetRoot(LocalPlayer)
    if Root then
        for _, v in pairs(Root:GetChildren()) do
            if v.Name == "FlingGyro" or v.Name == "FlingMover" then v:Destroy() end
        end
        Root.Velocity = Vector3.new(0,0,0)
        Root.RotVelocity = Vector3.new(0,0,0)
        Root.Anchored = false
    end
    
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
                StatusLabel.Text = ManualMode and "狀態：無選取目標" or "狀態：搜尋/等待目標 (安全區暫停)"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
                
                -- [Smart Stop] 安全暫停：暫時移除推力，允許走路
                if Root:FindFirstChild("FlingMover") then
                    Root.FlingMover:Destroy()
                    Root.FlingGyro:Destroy()
                    Root.Velocity = Vector3.new(0,0,0)
                    Root.RotVelocity = Vector3.new(0,0,0)
                end
                
                task.wait(0.5)
            else
                for _, Target in ipairs(Targets) do
                    if not FlingActive then break end
                    
                    -- [Smart Stop] 再確認一次安全狀態
                    if IsSafe(Target) then
                        -- 跳過此人
                    else
                        CurrentTarget = Target
                        StatusLabel.Text = "TARGET: " .. Target.Name
                        StatusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
                        
                        local TargetRoot = GetRoot(Target)
                        if TargetRoot then
                            local StartTime = tick()
                            local Loop
                            if not Root:FindFirstChild("FlingGyro") then SetupFlingPhysics(Root) end
                            Loop = RunService.Stepped:Connect(function(t, step)
                                if not TargetRoot.Parent or (TargetRoot.Position - Root.Position).Magnitude > 300 then return end
                                ApplyPhysics(Root, TargetRoot, step)
                            end)
                            while FlingActive and TargetRoot.Parent and tick() - StartTime < 2.0 do
                                if IsSafe(Target) then break end -- 若目標跑回安全區立刻停止
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

-- UI
local ScreenGui = Library:Create("ScreenGui", { Name = "RevenantFlingPanel", ResetOnSpawn = false, Parent = game:GetService("CoreGui") })
if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end

local MainFrame = Library:Create("Frame", { Name = "MainFrame", Size = UDim2.new(0, 400, 0, 500), Position = UDim2.new(0.5, -200, 0.5, -250), BackgroundColor3 = Color3.fromRGB(20, 20, 20), BorderSizePixel = 0, Parent = ScreenGui })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = MainFrame})

local TitleBar = Library:Create("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(30,30,30), Parent = MainFrame })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = TitleBar})
Library:Create("Frame", { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = Color3.fromRGB(30,30,30), BorderSizePixel = 0, Parent = TitleBar })
Library:Create("TextLabel", { Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 15, 0, 0), BackgroundTransparency = 1, Text = "Revenant甩飛面板 ", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = TitleBar })
local CloseBtn = Library:Create("TextButton", { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -40, 0, 0), BackgroundTransparency = 1, Text = "X", TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 18, Font = Enum.Font.GothamBold, Parent = TitleBar })
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() StopFling() end)
Library:MakeDraggable(MainFrame, TitleBar)

local Container = Library:Create("Frame", { Size = UDim2.new(1, -20, 1, -50), Position = UDim2.new(0, 10, 0, 45), BackgroundTransparency = 1, Parent = MainFrame })

local StatusLabel = Library:Create("TextLabel", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(30,30,30), Text = "狀態：待命", TextColor3 = Color3.fromRGB(100, 255, 100), TextSize = 12, Font = Enum.Font.Gotham, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = StatusLabel})

local AegisStatusLabel = Library:Create("TextLabel", { Size = UDim2.new(1, 0, 0, 25), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(25,35,45), Text = "防禦系統：關閉", TextColor3 = Color3.fromRGB(150, 150, 150), TextSize = 12, Font = Enum.Font.Gotham, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = AegisStatusLabel})

local ModeBtn = Library:Create("TextButton", { Size = UDim2.new(0.48, 0, 0, 35), Position = UDim2.new(0, 0, 0, 65), BackgroundColor3 = Color3.fromRGB(46, 139, 87), Text = "模式：自動", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 14, Font = Enum.Font.GothamBold, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = ModeBtn})

local StartBtn = Library:Create("TextButton", { Size = UDim2.new(0.48, 0, 0, 35), Position = UDim2.new(0.52, 0, 0, 65), BackgroundColor3 = Color3.fromRGB(200, 60, 60), Text = "開始甩飛", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 14, Font = Enum.Font.GothamBold, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = StartBtn})

local AegisBtn = Library:Create("TextButton", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 105), BackgroundColor3 = Color3.fromRGB(40, 70, 100), Text = "開啟絕對防甩 (Revenant anti-fling)", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 14, Font = Enum.Font.GothamBold, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = AegisBtn})

local ListBg = Library:Create("Frame", { Size = UDim2.new(1, 0, 1, -170), Position = UDim2.new(0, 0, 0, 145), BackgroundColor3 = Color3.fromRGB(30, 30, 30), Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = ListBg})
local PlayerScroll = Library:Create("ScrollingFrame", { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ScrollBarThickness = 4, Parent = ListBg })
Library:Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = PlayerScroll })

local SelectAllBtn = Library:Create("TextButton", { Size = UDim2.new(0.3, 0, 0, 25), Position = UDim2.new(0, 0, 1, -25), BackgroundColor3 = Color3.fromRGB(60, 60, 60), Text = "全選", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 12, Font = Enum.Font.Gotham, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = SelectAllBtn})
local ClearBtn = Library:Create("TextButton", { Size = UDim2.new(0.3, 0, 0, 25), Position = UDim2.new(0.35, 0, 1, -25), BackgroundColor3 = Color3.fromRGB(60, 60, 60), Text = "全不選", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 12, Font = Enum.Font.Gotham, Parent = Container })
Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = ClearBtn})

local function UpdatePlayerList()
    for _, v in pairs(PlayerScroll:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    local Plrs = Players:GetPlayers()
    table.sort(Plrs, function(a,b) return a.Name < b.Name end)
    for _, Plr in ipairs(Plrs) do
        if Plr ~= LocalPlayer then
            local IsSelected = SelectedPlayers[Plr.UserId]
            local Btn = Library:Create("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = IsSelected and Color3.fromRGB(46, 139, 87) or Color3.fromRGB(40, 40, 40), Text = "  " .. Plr.Name .. (IsSelected and " [✔]" or ""), TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 14, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Parent = PlayerScroll })
            Library:Create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = Btn})
            Btn.MouseButton1Click:Connect(function()
                if SelectedPlayers[Plr.UserId] then SelectedPlayers[Plr.UserId] = nil Btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40) Btn.Text = "  " .. Plr.Name
                else SelectedPlayers[Plr.UserId] = true Btn.BackgroundColor3 = Color3.fromRGB(46, 139, 87) Btn.Text = "  " .. Plr.Name .. " [✔]" end
            end)
        end
    end
    PlayerScroll.CanvasSize = UDim2.new(0, 0, 0, #Plrs * 34)
end

ModeBtn.MouseButton1Click:Connect(function()
    ManualMode = not ManualMode
    if ManualMode then ModeBtn.Text = "模式：手動選取" ModeBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 0) ListBg.Visible = true
    else ModeBtn.Text = "模式：自動" ModeBtn.BackgroundColor3 = Color3.fromRGB(46, 139, 87) end
end)

StartBtn.MouseButton1Click:Connect(function()
    if FlingActive then StopFling() StartBtn.Text = "開始甩飛" StartBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60) StatusLabel.Text = "狀態：已停止"
    else StartBtn.Text = "停止甩飛" StartBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 0) StartFlingLoop(StatusLabel) end
end)

AegisBtn.MouseButton1Click:Connect(function()
    if AntiFlingActive then ToggleAntiFling(false, AegisStatusLabel) AegisBtn.Text = "開啟絕對防甩 (Revenant anti-fling)" AegisBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 100)
    else ToggleAntiFling(true, AegisStatusLabel) AegisBtn.Text = "關閉絕對防甩" AegisBtn.BackgroundColor3 = Color3.fromRGB(46, 139, 87) end
end)

SelectAllBtn.MouseButton1Click:Connect(function() for _, Plr in pairs(Players:GetPlayers()) do if Plr ~= LocalPlayer then SelectedPlayers[Plr.UserId] = true end end UpdatePlayerList() end)
ClearBtn.MouseButton1Click:Connect(function() SelectedPlayers = {} UpdatePlayerList() end)
Players.PlayerAdded:Connect(UpdatePlayerList) Players.PlayerRemoving:Connect(UpdatePlayerList) UpdatePlayerList()
UserInputService.InputBegan:Connect(function(Input) if Input.KeyCode == Enum.KeyCode.RightControl then MainFrame.Visible = not MainFrame.Visible end end)

print("TSB Fling Pro (Ultimate) Loaded.")
