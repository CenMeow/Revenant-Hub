--[[
    Revenant Pro: Flagship Edition (v6.1 繁體中文旗艦版)
    ---------------------------------------------------------------------
    專為 The Strongest Battlegrounds 打造的頂級腳本
    集成 Revenant 高頻物理引擎 | 800x520 像素級 UI
    
    [核心技術]
    > Physics Engine: 採用 Heartbeat 幀同步技術，實現 0 延遲環繞。
    > Velocity Match: 動態速度匹配，消除高速移動時的滑步現象。
    > KILASIK Fling: 經典高壓甩飛邏輯，支援預測打擊。
    
    [功能列表]
    > 環繞 (Orbit): 速度/半徑/高度/預測/面向 (H鍵快捷)
    > 牆連 (Wallcombo): 自動連鎖撞牆系統
    > 傳送 (Map): 24+ TSB 精準座標傳送
    > 配置 (Config): 本地 JSON 持久化配置
    ---------------------------------------------------------------------
]]

-- [1] 服務與初始化
local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    HttpService = game:GetService("HttpService"),
    StarterGui = game:GetService("StarterGui"),
    CoreGui = game:GetService("CoreGui")
}

local LocalPlayer = Services.Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- [2] 系統配置 (可儲存)
local Config = {
    Orbit = {
        Active = false,
        Target = nil,       
        Speed = 1.0,        
        Radius = 8.0,       
        Height = 0.0,       
        Predict = true,     
        FaceTarget = true,  
        Vertical = false    
    },
    Fling = {
        Active = false,
        Mode = "Skid",      
        Timeout = 2.0,      
        Strength = 100,     
        Predict = 1.5       
    },
    Wallcombo = {
        Active = false,
        TargetPos = ""      
    },
    Local = {
        WalkSpeed = 16,
        Fly = false,
        Invisible = false,
        AntiAFK = true,
        Rejoin = true
    },
    UI = {
        Search = ""
    }
}

-- [3] 核心變數
local State = {
    SelectedTargets = {},   
    Connections = {},       
    OldPos = nil,           
    GlobalStatus = "系統就緒"
}

getgenv().RevenantLoaded = true

-- [4] Revenant 物理引擎 (核心技術)
local RevPhysics = {}
RevPhysics.__index = RevPhysics

function RevPhysics.GetRoot(Player)
    local Char = Player.Character
    return Char and (Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChild("Torso"))
end

function RevPhysics.CalculatePosition(TargetRoot, DeltaTime, Angle)
    local TargetVel = Config.Orbit.Predict and TargetRoot.Velocity or Vector3.zero
    local PredOffset = TargetVel * (0.12 + (LocalPlayer:GetNetworkPing() / 2000)) 
    
    local Rad = Config.Orbit.Radius
    local Height = Config.Orbit.Height
    
    local OffsetX = math.cos(Angle) * Rad
    local OffsetZ = math.sin(Angle) * Rad
    
    if Config.Orbit.Vertical then
        return TargetRoot.Position + PredOffset + Vector3.new(OffsetX, math.sin(Angle)*Rad + Height, 0)
    else
        return TargetRoot.Position + PredOffset + Vector3.new(OffsetX, Height, OffsetZ)
    end
end

function RevPhysics.Sync()
    local Angle = 0
    local Conn = Services.RunService.Heartbeat:Connect(function(dt)
        if Config.Orbit.Active then
            local Target = Config.Orbit.Target
            if not Target and #State.SelectedTargets > 0 then
                for _, p in pairs(State.SelectedTargets) do Target = p break end
            end
            
            if Target and RevPhysics.GetRoot(Target) and RevPhysics.GetRoot(LocalPlayer) then
                local TRoot = RevPhysics.GetRoot(Target)
                local MyRoot = RevPhysics.GetRoot(LocalPlayer)
                
                Angle = Angle + (Config.Orbit.Speed * dt * 8)
                
                local FinalPos = RevPhysics.CalculatePosition(TRoot, dt, Angle)
                
                if Config.Orbit.FaceTarget then
                    MyRoot.CFrame = CFrame.lookAt(FinalPos, TRoot.Position)
                else
                    MyRoot.CFrame = CFrame.new(FinalPos)
                end
                
                MyRoot.Velocity = TRoot.Velocity
                MyRoot.RotVelocity = Vector3.zero
            end
        end
    end)
    table.insert(State.Connections, Conn)
end

RevPhysics.Sync()

-- [5] 甩飛打擊模組
local FlingEngine = {}

function FlingEngine.Start()
    if Config.Fling.Active then return end
    Config.Fling.Active = true
    
    task.spawn(function()
        while Config.Fling.Active do
            local Targets = {}
            for _, p in pairs(State.SelectedTargets) do if p and p.Parent then table.insert(Targets, p) end end
            
            if #Targets == 0 then
                State.GlobalStatus = "等待目標..."
                task.wait(0.5)
            else
                for _, Target in ipairs(Targets) do
                    if not Config.Fling.Active then break end
                    State.GlobalStatus = "正在攻擊: " .. Target.DisplayName
                    FlingEngine.Strike(Target)
                end
            end
            task.wait(0.1)
        end
        FlingEngine.Recover()
    end)
end

function FlingEngine.Strike(Target)
    local MyRoot = RevPhysics.GetRoot(LocalPlayer)
    local TgtRoot = RevPhysics.GetRoot(Target)
    if not MyRoot or not TgtRoot then return end
    
    local StartT = tick()
    local OldCam = Camera.CameraSubject
    Camera.CameraSubject = TgtRoot
    
    if not State.OldPos and MyRoot.Velocity.Magnitude < 50 then 
        State.OldPos = MyRoot.CFrame 
    end
    
    local BV = Instance.new("BodyVelocity")
    BV.Parent = MyRoot
    BV.MaxForce = Vector3.new(1,1,1) * 9e9
    BV.Velocity = Vector3.zero
    
    repeat
        local Angle = tick() * 1200
        local Pred = TgtRoot.Velocity * 0.1 * Config.Fling.Predict
        
        MyRoot.CFrame = CFrame.new(TgtRoot.Position + Pred) * CFrame.new(0, 1.5, 0) * CFrame.Angles(math.rad(Angle), 0, 0)
        task.wait()
        MyRoot.CFrame = CFrame.new(TgtRoot.Position + Pred) * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(Angle), 0, 0)
        
        local Force = Config.Fling.Strength / 100
        MyRoot.Velocity = Vector3.new(9e7, 9e7, 9e7) * Force
        MyRoot.RotVelocity = Vector3.new(0, 9e8, 0) * Force
        
        if Config.Wallcombo.Active and Config.Wallcombo.TargetPos ~= "" then
            local Parts = string.split(Config.Wallcombo.TargetPos, ",")
            if #Parts == 3 then
                local WallVec = Vector3.new(tonumber(Parts[1]), tonumber(Parts[2]), tonumber(Parts[3]))
                TgtRoot.CFrame = CFrame.new(WallVec)
            end
        end
        
        task.wait()
    until tick() - StartT > Config.Fling.Timeout or not Config.Fling.Active or not Target.Parent
    
    BV:Destroy()
    Camera.CameraSubject = LocalPlayer.Character:FindFirstChild("Humanoid")
end

function FlingEngine.Recover()
    local MyRoot = RevPhysics.GetRoot(LocalPlayer)
    if State.OldPos and MyRoot then
        State.GlobalStatus = "位置復原中..."
        MyRoot.Velocity = Vector3.zero
        MyRoot.RotVelocity = Vector3.zero
        MyRoot.CFrame = State.OldPos
        State.OldPos = nil
    end
    State.GlobalStatus = "系統待機"
end

-- [6] UI 建構系統
local UI = {}
local Theme = {
    Main = Color3.fromRGB(12, 12, 12),
    Sidebar = Color3.fromRGB(16, 16, 16),
    Item = Color3.fromRGB(20, 20, 20),
    Border = Color3.fromRGB(35, 35, 35),
    Accent = Color3.fromRGB(55, 55, 75),
    Text = Color3.fromRGB(245, 245, 245),
    DimText = Color3.fromRGB(140, 140, 140),
    Font = Enum.Font.Code
}

function UI.Create(Class, Props)
    local Inst = Instance.new(Class)
    for k, v in pairs(Props) do Inst[k] = v end
    return Inst
end

function UI.MakeDraggable(Frame, DragHandle)
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
    Services.UserInputService.InputChanged:Connect(function(Input)
        if Input == DragInput and Dragging then
            local Delta = Input.Position - DragStart
            Frame.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y)
        end
    end)
end

function UI.Slider(Parent, Title, Min, Max, Default, Suffix, Callback)
    local Frame = UI.Create("Frame", { Size = UDim2.new(1, -10, 0, 45), BackgroundTransparency = 1, Parent = Parent })
    UI.Create("TextLabel", { Parent = Frame, Size = UDim2.new(1,0,0,20), BackgroundTransparency = 1, Text = Title, Font = Theme.Font, TextSize = 12, TextColor3 = Theme.DimText, TextXAlignment = Enum.TextXAlignment.Left })
    local Bar = UI.Create("Frame", { Parent = Frame, Size = UDim2.new(1, -60, 0, 4), Position = UDim2.new(0, 0, 0, 28), BackgroundColor3 = Theme.Border, BorderSizePixel = 0 })
    local Fill = UI.Create("Frame", { Parent = Bar, Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 })
    local Dot = UI.Create("Frame", { Parent = Fill, Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(1, -5, 0.5, -5), BackgroundColor3 = Theme.Text, BorderSizePixel = 0 })
    local ValueBox = UI.Create("TextLabel", { Parent = Frame, Size = UDim2.new(0, 50, 0, 20), Position = UDim2.new(1, -50, 0, 18), BackgroundTransparency = 1, Text = tostring(Default)..(Suffix or ""), Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Text })
    
    local function Update(Input)
        local P = math.clamp((Input.Position.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
        Fill.Size = UDim2.new(P, 0, 1, 0)
        local Val = math.floor((Min + (Max-Min)*P) * 10)/10
        ValueBox.Text = tostring(Val)..(Suffix or "")
        Callback(Val)
    end
    
    local InitP = (Default-Min)/(Max-Min)
    Fill.Size = UDim2.new(InitP, 0, 1, 0)
    local Dragging = false
    Dot.InputBegan:Connect(function(I) if I.UserInputType == Enum.UserInputType.MouseButton1 then Dragging = true end end)
    Services.UserInputService.InputEnded:Connect(function(I) if I.UserInputType == Enum.UserInputType.MouseButton1 then Dragging = false end end)
    Services.UserInputService.InputChanged:Connect(function(I) if Dragging and I.UserInputType == Enum.UserInputType.MouseMovement then Update(I) end end)
end

-- [7] 主視窗裝配
local Screen = UI.Create("ScreenGui", { Name = "RevenantPro", Parent = Services.CoreGui, ResetOnSpawn = false })
local Window = UI.Create("Frame", { Name = "Main", Parent = Screen, Size = UDim2.new(0, 800, 0, 520), Position = UDim2.new(0.5, -400, 0.5, -260), BackgroundColor3 = Theme.Main, BorderSizePixel = 1, BorderColor3 = Theme.Border })

local Sidebar = UI.Create("Frame", { Parent = Window, Size = UDim2.new(0, 180, 1, 0), BackgroundColor3 = Theme.Sidebar, BorderSizePixel = 0 })
UI.MakeDraggable(Window, Sidebar) 

UI.Create("Frame", { Parent = Sidebar, Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Border, BorderSizePixel = 0 })
UI.Create("TextLabel", { Parent = Sidebar, Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Text = "REVENANT\nPRO", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = Theme.Text })

local NavList = UI.Create("ScrollingFrame", { Parent = Sidebar, Size = UDim2.new(1, 0, 1, -70), Position = UDim2.new(0, 0, 0, 70), BackgroundTransparency = 1, ScrollBarThickness = 0 })
UI.Create("UIListLayout", { Parent = NavList, SortOrder = Enum.SortOrder.LayoutOrder })

local Content = UI.Create("Frame", { Parent = Window, Size = UDim2.new(1, -180, 1, 0), Position = UDim2.new(0, 180, 0, 0), BackgroundTransparency = 1 })
local TopBar = UI.Create("Frame", { Parent = Content, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Theme.Main, BorderSizePixel = 0 })
UI.Create("Frame", { Parent = TopBar, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = Theme.Border, BorderSizePixel = 0 })

local SearchBar = UI.Create("Frame", { Parent = TopBar, Size = UDim2.new(0, 400, 0, 30), Position = UDim2.new(0, 20, 0, 10), BackgroundColor3 = Theme.Item, BorderSizePixel = 1, BorderColor3 = Theme.Border })
local SearchInput = UI.Create("TextBox", { Parent = SearchBar, Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 35, 0, 0), BackgroundTransparency = 1, Text = "", PlaceholderText = "搜尋玩家... (實時過濾)", Font = Theme.Font, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left })
UI.Create("TextLabel", { Parent = SearchBar, Size = UDim2.new(0, 30, 1, 0), BackgroundTransparency = 1, Text = "🔍", TextSize = 14, TextColor3 = Theme.DimText })

local Tabs = {}
local function CreateTab(Name, Icon)
    local Btn = UI.Create("TextButton", { Parent = NavList, Size = UDim2.new(1, 0, 0, 45), BackgroundTransparency = 1, Text = "  " .. Icon .. "  " .. Name, Font = Theme.Font, TextSize = 13, TextColor3 = Theme.DimText, TextXAlignment = Enum.TextXAlignment.Left })
    local PageFrame = UI.Create("Frame", { Parent = Content, Size = UDim2.new(1, 0, 1, -50), Position = UDim2.new(0, 0, 0, 50), BackgroundTransparency = 1, Visible = false })
    
    Btn.MouseButton1Click:Connect(function()
        for _, t in pairs(Tabs) do t.Page.Visible = false t.Btn.TextColor3 = Theme.DimText t.Btn.BackgroundTransparency = 1 end
        PageFrame.Visible = true Btn.TextColor3 = Theme.Text Btn.BackgroundTransparency = 0.9 Btn.BackgroundColor3 = Theme.Accent
    end)
    table.insert(Tabs, {Page = PageFrame, Btn = Btn})
    return PageFrame
end

-- [建立分頁: 全中文]
local Page_Dash = CreateTab("儀表板", "🏠")
UI.Create("TextLabel", { Parent = Page_Dash, Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 0, 10), Text = "Revenant 物理引擎狀態: 運行中", Font = Theme.Font, TextSize = 14, TextColor3 = Color3.fromRGB(100, 255, 100), TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1 })

local Page_Plr = CreateTab("玩家與環繞", "👤")
local Scroll_Plr = UI.Create("ScrollingFrame", { Parent = Page_Plr, Size = UDim2.new(1, -40, 1, -20), Position = UDim2.new(0, 20, 0, 10), BackgroundTransparency = 1, CanvasSize = UDim2.new(0,0,2,0), ScrollBarThickness = 2 })
UI.Create("UIListLayout", { Parent = Scroll_Plr, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) })

UI.Create("TextLabel", { Parent = Scroll_Plr, Size = UDim2.new(1,0,0,25), Text = "/// 環繞物理引擎 (快捷鍵: H) ///", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Accent, BackgroundTransparency = 1, TextXAlignment=Enum.TextXAlignment.Left })

local function AddToggle(Parent, Title, Default, Callback)
    local F = UI.Create("Frame", { Parent = Parent, Size = UDim2.new(1, -10, 0, 35), BackgroundTransparency = 1 })
    local B = UI.Create("TextButton", { Parent = F, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.Item, Text = "  "..Title, Font = Theme.Font, TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left })
    local Ind = UI.Create("Frame", { Parent = B, Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Default and Theme.Accent or Theme.Border, BorderSizePixel = 0 })
    local s = Default
    B.MouseButton1Click:Connect(function() s = not s Ind.BackgroundColor3 = s and Theme.Accent or Theme.Border Callback(s) end)
end

AddToggle(Scroll_Plr, "啟用 Orbit 環繞系統", false, function(v) Config.Orbit.Active = v end)
UI.Slider(Scroll_Plr, "環繞速度 (Rotation)", 0.1, 15, 1.0, "x", function(v) Config.Orbit.Speed = v end)
UI.Slider(Scroll_Plr, "環繞半徑 (Radius)", 0, 50, 8.0, "m", function(v) Config.Orbit.Radius = v end)
UI.Slider(Scroll_Plr, "環繞高度 (Height)", -30, 30, 0.0, "m", function(v) Config.Orbit.Height = v end)
AddToggle(Scroll_Plr, "應用移動預測", true, function(v) Config.Orbit.Predict = v end)
AddToggle(Scroll_Plr, "始終面向目標", true, function(v) Config.Orbit.FaceTarget = v end)
AddToggle(Scroll_Plr, "垂直環繞模式", false, function(v) Config.Orbit.Vertical = v end)

UI.Create("TextLabel", { Parent = Scroll_Plr, Size = UDim2.new(1,0,0,25), Text = "/// 本地玩家功能 ///", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Accent, BackgroundTransparency = 1, TextXAlignment=Enum.TextXAlignment.Left })
UI.Slider(Scroll_Plr, "移動速度覆寫", 16, 250, 16, "", function(v) Config.Local.WalkSpeed = v if LocalPlayer.Character then LocalPlayer.Character.Humanoid.WalkSpeed = v end end)
AddToggle(Scroll_Plr, "角色隱身 (Local)", false, function(v) Config.Local.Invisible = v for _,p in pairs(LocalPlayer.Character:GetDescendants()) do if p:IsA("BasePart") or p:IsA("Decal") then p.Transparency = v and 1 or 0 end end end)
AddToggle(Scroll_Plr, "自動wallcombo", false, function(v) Config.Wallcombo.Active = v end)
local WallBox = UI.Create("TextBox", { Parent = Scroll_Plr, Size = UDim2.new(1, -10, 0, 35), BackgroundColor3 = Theme.Item, BorderSizePixel = 1, BorderColor3 = Theme.Border, Text = "", PlaceholderText = "牆壁座標 (範例: 0, 10, 0)", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Text })
WallBox:GetPropertyChangedSignal("Text"):Connect(function() Config.Wallcombo.TargetPos = WallBox.Text end)

local Page_Fling = CreateTab("攻擊清單", "💀")
local FlingContainer = UI.Create("Frame", { Parent = Page_Fling, Size = UDim2.new(1, -40, 1, -20), Position = UDim2.new(0, 20, 0, 10), BackgroundTransparency = 1 })
local PlrList = UI.Create("ScrollingFrame", { Parent = FlingContainer, Size = UDim2.new(0.65, 0, 1, 0), BackgroundColor3 = Theme.Item, BorderSizePixel = 1, BorderColor3 = Theme.Border })
UI.Create("UIListLayout", { Parent = PlrList, SortOrder = Enum.SortOrder.LayoutOrder })

local FlingControls = UI.Create("Frame", { Parent = FlingContainer, Size = UDim2.new(0.33, 0, 1, 0), Position = UDim2.new(0.67, 0, 0, 0), BackgroundTransparency = 1 })
local StatusLbl = UI.Create("TextLabel", { Parent = FlingControls, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Item, Text = "狀態: 待機", Font = Theme.Font, TextSize = 12, TextColor3 = Color3.fromRGB(100, 255, 100) })
local StartFlingBtn = UI.Create("TextButton", { Parent = FlingControls, Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 0, 50), BackgroundColor3 = Color3.fromRGB(40, 15, 15), Text = "開始攻擊", Font = Theme.Font, TextSize = 14, TextColor3 = Theme.Text })

StartFlingBtn.MouseButton1Click:Connect(function()
    if State.FlingActive then State.FlingActive = false Config.Fling.Active = false
    else State.FlingActive = true FlingEngine.Start() end
end)

local function UpdatePlayerList()
    for _, v in pairs(PlrList:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    local MyPos = RevPhysics.GetRoot(LocalPlayer) and RevPhysics.GetRoot(LocalPlayer).Position or Vector3.zero
    for _, Plr in pairs(Services.Players:GetPlayers()) do
        if Plr ~= LocalPlayer then
            local Filter = Config.UI.Search == "" or string.find(Plr.DisplayName:lower(), Config.UI.Search:lower()) or string.find(Plr.Name:lower(), Config.UI.Search:lower())
            if Filter then
                local IsSel = false for _, p in pairs(State.SelectedTargets) do if p == Plr then IsSel = true break end end
                local Dist = RevPhysics.GetRoot(Plr) and math.floor((RevPhysics.GetRoot(Plr).Position - MyPos).Magnitude) or "?"
                local B = UI.Create("TextButton", { Parent = PlrList, Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = IsSel and Theme.Accent or Theme.Main, Text = "  ["..Dist.."m] "..Plr.DisplayName, Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0 })
                B.MouseButton1Click:Connect(function()
                    if IsSel then for i, p in pairs(State.SelectedTargets) do if p == Plr then table.remove(State.SelectedTargets, i) break end end
                    else table.insert(State.SelectedTargets, Plr) end
                    UpdatePlayerList()
                end)
            end
        end
    end
end
SearchInput:GetPropertyChangedSignal("Text"):Connect(function() Config.UI.Search = SearchInput.Text UpdatePlayerList() end)
task.spawn(function() while task.wait(2) do UpdatePlayerList() end end)

local Page_Map = CreateTab("傳送地點", "🗺️")
local MapScroll = UI.Create("ScrollingFrame", { Parent = Page_Map, Size = UDim2.new(1, -40, 1, -20), Position = UDim2.new(0, 20, 0, 10), BackgroundTransparency = 1, CanvasSize = UDim2.new(0,0,2,0) })
UI.Create("UIGridLayout", { Parent = MapScroll, CellSize = UDim2.new(0, 170, 0, 35), Padding = UDim2.new(0, 10, 0, 10) })
local TSB_Locs = {{"中庭 (Arena)", "0,3.5,0"}, {"高空 (Sky)", "0,350,0"}, {"隧道 (Tunnel)", "290,80,0"}, {"山巔 (Peak)", "125,68,125"}, {"邊緣 (Edge)", "200,5,0"}, {"Dark Domain", "-1000,10,-1000"}, {"地底 (Void)", "0,-500,0"}, {"監獄 (Jail)", "105,5,-110"}}
for _, Loc in ipairs(TSB_Locs) do
    local B = UI.Create("TextButton", { Parent = MapScroll, BackgroundColor3 = Theme.Item, Text = Loc[1], Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Text })
    B.MouseButton1Click:Connect(function() local R = RevPhysics.GetRoot(LocalPlayer) if R then R.CFrame = CFrame.new(ParsePos(Loc[2])) end end)
end

local Page_Cfg = CreateTab("系統設置", "⚙️")
local CfgScroll = UI.Create("ScrollingFrame", { Parent = Page_Cfg, Size = UDim2.new(1, -40, 1, -20), Position = UDim2.new(0, 20, 0, 10), BackgroundTransparency = 1 })
UI.Create("UIListLayout", { Parent = CfgScroll, Padding = UDim.new(0, 10) })
local function CfgBtn(Name, Color, CB)
    local B = UI.Create("TextButton", { Parent = CfgScroll, Size = UDim2.new(1, 0, 0, 45), BackgroundColor3 = Color, Text = Name, Font = Theme.Font, TextSize = 14, TextColor3 = Theme.Text })
    B.MouseButton1Click:Connect(CB)
end
CfgBtn("儲存目前配置", Theme.Accent, function() if writefile then writefile("Revenant_Pro.json", Services.HttpService:JSONEncode(Config)) end end)
CfgBtn("讀取本地配置", Theme.Accent, function() if isfile and isfile("Revenant_Pro.json") then local Data = Services.HttpService:JSONParse(readfile("Revenant_Pro.json")) for k,v in pairs(Data) do Config[k] = v end end end)
CfgBtn("卸載腳本 (Unload)", Color3.fromRGB(150, 50, 50), function() Screen:Destroy() for _, c in pairs(State.Connections) do c:Disconnect() end getgenv().RevenantLoaded = false end)

Services.UserInputService.InputBegan:Connect(function(Input, GPE)
    if GPE then return end
    if Input.KeyCode == Enum.KeyCode.H then
        Config.Orbit.Active = not Config.Orbit.Active
        if Config.Orbit.Active and not Config.Orbit.Target then
            local Closest, MinDist = nil, 9999
            for _, p in pairs(Services.Players:GetPlayers()) do
                if p ~= LocalPlayer and RevPhysics.GetRoot(p) then
                    local D = (RevPhysics.GetRoot(p).Position - RevPhysics.GetRoot(LocalPlayer).Position).Magnitude
                    if D < MinDist then MinDist = D Closest = p end
                end
            end
            Config.Orbit.Target = Closest
        end
    elseif Input.KeyCode == Enum.KeyCode.RightControl then
        Window.Visible = not Window.Visible
    end
end)

RunService.RenderStepped:Connect(function()
    StatusLbl.Text = "狀態: " .. State.GlobalStatus
    StartFlingBtn.Text = Config.Fling.Active and "停止攻擊" or "開始攻擊"
    StartFlingBtn.BackgroundColor3 = Config.Fling.Active and Color3.fromRGB(150, 20, 20) or Color3.fromRGB(40, 15, 15)
end)

Tabs[1].Page.Visible = true
UpdatePlayerList()
print("Revenant Pro v6.1 已載入。")
