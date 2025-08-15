-- ============ Load SlightlyBloxyUI ============
local Rayfield = _G.Rayfield or loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/coder20130/SlightlyBloxyUI/main/Source.lua",
  true
))()
_G.Rayfield = Rayfield

-- ============ Services ============
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- ============ Helpers ============
local function getHRP(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function myChar() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function listPlayers()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(out, p.Name .. (p.DisplayName and (" ["..p.DisplayName.."]") or ""))
        end
    end
    table.sort(out)
    return out
end
local function extractName(s) return (s and s:match("^[^%s%[]+")) or s end
local function findByName(name) if not name then return nil end return Players:FindFirstChild(name) end
local function pickRandomPlayer()
    local pool = {}
    for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(pool, p) end end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end
local function tip(title, text, dur) Rayfield:Notify({ Title = title or "Info", Content = text or "", Duration = dur or 3 }) end

-- ============ Window ============
local Window = _G.SlightlyBloxyWindow or Rayfield:CreateWindow({
  Name = "SlightlyBloxyUI – Troll Kit",
  Theme = "Default",
})
_G.SlightlyBloxyWindow = Window

-- =========================================================
-- TAB: Teleport (client-side me→them; server nodig voor them→me)
-- =========================================================
local TPEvent = ReplicatedStorage:FindFirstChild("TPRequest") -- optioneel (eigen game)

local TeleportTab = Window:CreateTab("Teleport", 0)
TeleportTab:CreateSection("TP Tools (client-side me→them)")

local currentTargetTP = nil
local function playerOptions() return listPlayers() end

TeleportTab:CreateDropdown({
  Name = "Kies speler",
  Options = playerOptions(),
  CurrentOption = nil,
  Callback = function(opt) currentTargetTP = extractName(opt) end
})

TeleportTab:CreateInput({
  Name = "Zoek speler (deel van naam)",
  PlaceholderText = "bv. rob, hi, ...",
  CurrentValue = "",
  Callback = function(txt)
    local k = tostring(txt or ""):lower()
    local found
    for _, p in ipairs(Players:GetPlayers()) do
      if p ~= LocalPlayer then
        if p.Name:lower():find(k, 1, true) or (p.DisplayName or ""):lower():find(k, 1, true) then
          found = p; break
        end
      end
    end
    if found then currentTargetTP = found.Name; tip("Teleport","Gevonden: "..found.Name,2) else tip("Teleport","Niet gevonden.",2) end
  end
})

TeleportTab:CreateButton({
  Name = "🔄 Refresh spelerslijst",
  Callback = function()
    TeleportTab:CreateDropdown({
      Name = "Kies speler (refreshed)",
      Options = playerOptions(),
      CurrentOption = currentTargetTP,
      Callback = function(opt) currentTargetTP = extractName(opt) end
    })
    tip("Teleport","Lijst ververst.",2)
  end
})

TeleportTab:CreateButton({
  Name = "TP me → them",
  Callback = function()
    if not currentTargetTP then tip("Teleport","Geen speler geselecteerd.",2) return end
    local t = Players:FindFirstChild(currentTargetTP)
    local tHRP = t and t.Character and getHRP(t.Character)
    if not tHRP then tip("Teleport","Speler niet beschikbaar.",2) return end
    myChar():PivotTo(tHRP.CFrame + Vector3.new(0,4,0))
    tip("Teleport","Jij → "..currentTargetTP,2)
  end
})

TeleportTab:CreateButton({
  Name = "Bring them → me (server vereist)",
  Callback = function()
    if not TPEvent then tip("Teleport","Server-event ontbreekt. Niet beschikbaar.",3) return end
    if not currentTargetTP then tip("Teleport","Geen speler geselecteerd.",2) return end
    TPEvent:FireServer("themToMe", currentTargetTP)
    tip("Teleport","Aangevraagd bij server.",2)
  end
})

-- =========================================================
-- TAB: Main — GHOST TROLL (client-side, tijdelijk)
-- =========================================================
local MainTab = Window:CreateTab("Main", 0)
MainTab:CreateSection("Ghost Troll (client-side)")

local currentTargetMain = nil
local ghostSettings = {
  mode = "Behind",  -- "Behind" | "Orbit"
  distance = 6,
  transparency = 0.35,
  color = Color3.fromRGB(120, 180, 255),
  squeak = false,
}

local ghost, followConn, squeakConn
local function clearGhost()
  if followConn then followConn:Disconnect() followConn = nil end
  if squeakConn then squeakConn:Disconnect() squeakConn = nil end
  if ghost and ghost.Model then ghost.Model:Destroy() end
  ghost = nil
end

local function makeGhostFromTarget(targetPlayer)
  clearGhost()
  local tChar = targetPlayer.Character
  local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
  local tHRP = getHRP(tChar)
  if not (tHum and tHRP) then return false, "Target heeft geen character/hrp" end

  local okU, mdl = pcall(function() return Players:CreateHumanoidModelFromUserId(targetPlayer.UserId) end)
  if not okU or not mdl then
    mdl = Instance.new("Model"); mdl.Name = "GhostDummy"
    local hrp = Instance.new("Part"); hrp.Name="HumanoidRootPart"; hrp.Size=Vector3.new(2,2,1); hrp.Anchored=false; hrp.CanCollide=false; hrp.Transparency=ghostSettings.transparency; hrp.Parent=mdl
    local hum = Instance.new("Humanoid"); hum.Parent=mdl
    mdl.PrimaryPart = hrp; mdl.Parent = Workspace
  else
    mdl.PrimaryPart = mdl:FindFirstChild("HumanoidRootPart") or mdl.PrimaryPart
    mdl.Parent = Workspace
    -- best effort: target look
    pcall(function()
      local desc = tHum:GetAppliedDescription()
      local hum = mdl:FindFirstChildOfClass("Humanoid")
      if hum and desc then hum:ApplyDescription(desc) end
    end)
  end

  for _, p in ipairs(mdl:GetDescendants()) do
    if p:IsA("BasePart") then
      p.CanCollide = false
      p.Transparency = math.clamp(ghostSettings.transparency,0,0.95)
      p.Material = Enum.Material.ForceField
    end
  end
  local hl = Instance.new("Highlight")
  hl.FillTransparency = 1
  hl.OutlineTransparency = 0.2
  hl.OutlineColor = ghostSettings.color
  hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
  hl.Parent = mdl

  ghost = { Model = mdl, Target = targetPlayer }
  mdl:PivotTo(tHRP.CFrame)

  local orbitAngle = 0
  followConn = RunService.RenderStepped:Connect(function(dt)
    local tC = targetPlayer.Character
    local tP = getHRP(tC)
    if not (tC and tP and ghost and ghost.Model and ghost.Model.PrimaryPart) then return end
    local offset
    if ghostSettings.mode == "Behind" then
      offset = tP.Position - tP.CFrame.LookVector * ghostSettings.distance + Vector3.new(0,0.5,0)
    else
      orbitAngle = (orbitAngle + dt*1.2)%(2*math.pi)
      local r = ghostSettings.distance
      offset = tP.Position + Vector3.new(math.cos(orbitAngle)*r, 0.5, math.sin(orbitAngle)*r)
    end
    local goal = CFrame.new(offset, tP.Position)
    local cur = ghost.Model.PrimaryPart.CFrame
    ghost.Model:PivotTo(cur:Lerp(goal, math.clamp(dt*6,0,1)))
  end)

  if ghostSettings.squeak then
    squeakConn = RunService.Stepped:Connect(function()
      local t = targetPlayer.Character; local hrp = getHRP(t); if not hrp then return end
      local v = hrp.AssemblyLinearVelocity
      if v and v.Magnitude > 2 then
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://12222134"
        s.Volume = 0.45; s.PlayOnRemove = true; s.Parent = hrp; s:Destroy()
      end
    end)
  end

  local fx = Instance.new("ParticleEmitter")
  fx.Texture = "rbxassetid://258128463"
  fx.Rate = 80; fx.Lifetime = NumberRange.new(0.3, 0.6); fx.Speed = NumberRange.new(0,0)
  fx.Parent = ghost.Model.PrimaryPart; Debris:AddItem(fx, 1.2)
  return true
end

-- Ghost UI
MainTab:CreateDropdown({
  Name = "Kies speler",
  Options = playerOptions(),
  CurrentOption = nil,
  Callback = function(opt) currentTargetMain = extractName(opt) end
})

MainTab:CreateButton({
  Name = "🔄 Refresh spelerslijst",
  Callback = function()
    MainTab:CreateDropdown({
      Name = "Kies speler (refreshed)",
      Options = playerOptions(),
      CurrentOption = currentTargetMain,
      Callback = function(opt) currentTargetMain = extractName(opt) end
    })
    tip("Main","Lijst ververst.",2)
  end
})

MainTab:CreateDropdown({
  Name = "Mode",
  Options = {"Behind","Orbit"},
  CurrentOption = ghostSettings.mode,
  Callback = function(v) ghostSettings.mode = v end
})
MainTab:CreateSlider({
  Name = "Distance",
  Range = {3, 20},
  Increment = 1,
  CurrentValue = ghostSettings.distance,
  Suffix = " studs",
  Callback = function(v) ghostSettings.distance = math.floor(v) end
})
MainTab:CreateSlider({
  Name = "Transparantie",
  Range = {0, 95},
  Increment = 5,
  CurrentValue = math.floor(ghostSettings.transparency*100),
  Suffix = "%",
  Callback = function(v) ghostSettings.transparency = math.clamp(v/100, 0, 0.95) end
})
MainTab:CreateColorPicker({
  Name = "Highlight kleur",
  CurrentColor = ghostSettings.color,
  Callback = function(c) ghostSettings.color = c end
})
MainTab:CreateToggle({
  Name = "Squeak steps (grapje)",
  CurrentValue = ghostSettings.squeak,
  Callback = function(on) ghostSettings.squeak = on end
})
MainTab:CreateButton({
  Name = "👻 Spawn Ghost bij target",
  Callback = function()
    if not currentTargetMain then tip("Main","Geen speler geselecteerd.",2) return end
    local target = findByName(currentTargetMain); if not target then tip("Main","Speler niet gevonden.",2) return end
    local ok, err = makeGhostFromTarget(target)
    if ok then tip("Main","Ghost actief bij "..target.Name,3) else tip("Main","Mislukt: "..tostring(err),4) end
  end
})
MainTab:CreateButton({
  Name = "🧹 Remove Ghost",
  Callback = function() clearGhost(); tip("Main","Ghost verwijderd.",2) end
})

-- =========================================================
-- TAB: Random — CHAOS DICE + FLASHBANG
-- =========================================================
local RandomTab = Window:CreateTab("Random", 0)
RandomTab:CreateSection("Chaos Dice (client-side, tijdelijk)")

local currentRandomTarget = nil
RandomTab:CreateDropdown({
  Name = "Kies speler (leeg = random)",
  Options = playerOptions(),
  CurrentOption = nil,
  Callback = function(opt) currentRandomTarget = extractName(opt) end
})

RandomTab:CreateButton({
  Name = "🔄 Refresh spelerslijst",
  Callback = function()
    RandomTab:CreateDropdown({
      Name = "Kies speler (leeg = random)",
      Options = playerOptions(),
      CurrentOption = currentRandomTarget,
      Callback = function(opt) currentRandomTarget = extractName(opt) end
    })
    tip("Random","Lijst ververst.",2)
  end
})

-- Effect A: Confetti
local function confettiBurst(targetPlr)
  local ch = targetPlr.Character; local hrp = ch and getHRP(ch); if not hrp then return false,"geen hrp" end
  local emitter = Instance.new("ParticleEmitter")
  emitter.Texture = "rbxassetid://241876582"; emitter.Rate = 0
  emitter.Lifetime = NumberRange.new(1, 1.6); emitter.Speed = NumberRange.new(6, 10)
  emitter.EmissionDirection = Enum.NormalId.Top; emitter.Rotation = NumberRange.new(0, 360)
  emitter.RotSpeed = NumberRange.new(30, 60); emitter.SpreadAngle = Vector2.new(80, 80)
  emitter.Parent = hrp; emitter:Emit(120); Debris:AddItem(emitter, 2.5); return true
end

-- Effect B: Whisper Orbit
local function whisperOrbit(targetPlr, duration)
  duration = duration or 4
  local ch = targetPlr.Character; local hrp = ch and getHRP(ch); if not hrp then return false,"geen hrp" end
  local p = Instance.new("Part"); p.Anchored=true; p.CanCollide=false; p.Transparency=1; p.Size=Vector3.new(1,1,1); p.Parent=Workspace
  local s = Instance.new("Sound"); s.SoundId="rbxassetid://91202544"; s.Volume=0.35; s.Looped=true; s.Parent=p; s:Play()
  Debris:AddItem(p, duration+0.2); Debris:AddItem(s, duration+0.2)
  local t0 = tick(); local conn; conn = RunService.RenderStepped:Connect(function()
    local t = tick()-t0; local angle=t*2.2; local r=6
    if not hrp.Parent then conn:Disconnect() return end
    p.CFrame = CFrame.new(hrp.Position + Vector3.new(math.cos(angle)*r, 1.5, math.sin(angle)*r))
    if t>duration then conn:Disconnect() end
  end); return true
end

-- Effect C: Rainbow Outline
local function rainbowOutline(targetPlr, duration)
  duration = duration or 6
  local ch = targetPlr.Character; if not ch then return false,"geen char" end
  local hl = Instance.new("Highlight"); hl.FillTransparency=1; hl.OutlineTransparency=0; hl.Parent = ch
  Debris:AddItem(hl, duration+0.5)
  local t0 = tick(); local conn; conn = RunService.RenderStepped:Connect(function()
    local t = tick()-t0; local hue = (t*0.3)%1; hl.OutlineColor = Color3.fromHSV(hue, 0.9, 1)
    if t>duration then conn:Disconnect() end
  end); return true
end

-- Effect D: FLASHBANG (rood met zwarte tekst "c00lkidd")
local function flashbangRed(text, duration)
  text = text or "c00lkidd"; duration = duration or 2.5
  -- full-screen ScreenGui
  local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
  if not pg then return false,"geen PlayerGui" end
  local gui = Instance.new("ScreenGui"); gui.Name="FlashbangRed"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=pg
  local frame = Instance.new("Frame"); frame.BackgroundColor3=Color3.fromRGB(220,0,0); frame.Size=UDim2.fromScale(1,1); frame.BackgroundTransparency=1; frame.Parent=gui
  local label = Instance.new("TextLabel")
  label.BackgroundTransparency=1; label.TextScaled=true; label.Font=Enum.Font.GothamBlack
  label.TextColor3=Color3.new(0,0,0); label.TextStrokeTransparency=0.4
  label.Text=text; label.Size=UDim2.fromScale(1,1); label.Parent=frame
  -- fade in/out
  TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundTransparency=0}):Play()
  task.delay(duration, function()
    TweenService:Create(frame, TweenInfo.new(0.35), {BackgroundTransparency=1}):Play()
    Debris:AddItem(gui, 0.4)
  end)
  return true
end

RandomTab:CreateButton({
  Name = "🎲 Chaos Dice",
  Callback = function()
    local target = currentRandomTarget and findByName(currentRandomTarget) or pickRandomPlayer()
    if not target then tip("Random","Geen target beschikbaar.",2) return end
    local roll = math.random(1,4)
    local ok, err
    if roll == 1 then ok, err = confettiBurst(target); tip("Random","Confetti op "..target.Name,2)
    elseif roll == 2 then ok, err = whisperOrbit(target, 4); tip("Random","Whisper orbit bij "..target.Name,2)
    elseif roll == 3 then ok, err = rainbowOutline(target, 6); tip("Random","Rainbow outline bij "..target.Name,2)
    else ok, err = flashbangRed("c00lkidd", 2.5); tip("Random","Flashbang (rood)",2) end
    if not ok then tip("Random","Mislukt: "..tostring(err),3) end
  end
})

RandomTab:CreateButton({
  Name = "⚡️ Flashbang (rood) nu",
  Callback = function() flashbangRed("c00lkidd", 2.5) end
})

-- =========================================================
-- TAB: Glitch — moderatie-acties in EIGEN game + client visuals
-- =========================================================
local GlitchTab = Window:CreateTab("Glitch", 0)
GlitchTab:CreateSection("Admin actions (alleen in je eigen game)")

-- Remote voor admin actions (server script vereist in je eigen game)
local AdminEvent = ReplicatedStorage:FindFirstChild("AdminAction")

local currentGlitchTarget = nil
GlitchTab:CreateDropdown({
  Name = "Kies speler",
  Options = playerOptions(),
  CurrentOption = nil,
  Callback = function(opt) currentGlitchTarget = extractName(opt) end
})

GlitchTab:CreateButton({
  Name = "🔄 Refresh spelerslijst",
  Callback = function()
    GlitchTab:CreateDropdown({
      Name = "Kies speler (refreshed)",
      Options = playerOptions(),
      CurrentOption = currentGlitchTarget,
      Callback = function(opt) currentGlitchTarget = extractName(opt) end
    })
    tip("Glitch","Lijst ververst.",2)
  end
})

-- Health set (server-side, werkt alleen met AdminAction serverscript)
local myHealthValue = 100
GlitchTab:CreateSlider({
  Name = "Set Health waarde",
  Range = {1, 500},
  Increment = 1,
  CurrentValue = myHealthValue,
  Suffix = " hp",
  Callback = function(v) myHealthValue = math.floor(v) end
})

GlitchTab:CreateButton({
  Name = "Set MY Health (server)",
  Callback = function()
    if not AdminEvent then tip("Glitch","Server-event ontbreekt. Plaats serverscript.",3) return end
    AdminEvent:FireServer({ action="SetHealth", target="self", value=myHealthValue })
    tip("Glitch","Aangevraagd: SetHealth "..myHealthValue,2)
  end
})

GlitchTab:CreateButton({
  Name = "Set TARGET Health (server)",
  Callback = function()
    if not AdminEvent then tip("Glitch","Server-event ontbreekt. Plaats serverscript.",3) return end
    if not currentGlitchTarget then tip("Glitch","Geen speler geselecteerd.",2) return end
    AdminEvent:FireServer({ action="SetHealth", target=currentGlitchTarget, value=myHealthValue })
    tip("Glitch","Aangevraagd: "..currentGlitchTarget.." ⇒ "..myHealthValue.." hp",2)
  end
})

GlitchTab:CreateButton({
  Name = "Kick TARGET (server)",
  Callback = function()
    if not AdminEvent then tip("Glitch","Server-event ontbreekt.",3) return end
    if not currentGlitchTarget then tip("Glitch","Geen speler geselecteerd.",2) return end
    AdminEvent:FireServer({ action="Kick", target=currentGlitchTarget, reason="Glitched!" })
  end
})

GlitchTab:CreateButton({
  Name = "Fling TARGET (server)",
  Callback = function()
    if not AdminEvent then tip("Glitch","Server-event ontbreekt.",3) return end
    if not currentGlitchTarget then tip("Glitch","Geen speler geselecteerd.",2) return end
    AdminEvent:FireServer({ action="Fling", target=currentGlitchTarget, power=120 })
  end
})

GlitchTab:CreateParagraph({
  Title = "Let op",
  Content = "Kick/Fling/SetHealth werken ALLEEN in je eigen game met het serverscript hieronder. " ..
            "In andere games doen de knoppen niets."
})

GlitchTab:CreateSection("Client visuals (alleen jij ziet dit)")
GlitchTab:CreateButton({
  Name = "🔴 Flashbang (rood, c00lkidd)",
  Callback = function() flashbangRed("c00lkidd", 2.5) end
})

GlitchTab:CreateButton({
  Name = "📺 CRT / Scanlines 4s",
  Callback = function()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui"); if not pg then return end
    local gui = Instance.new("ScreenGui"); gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=pg
    local lines = Instance.new("Frame"); lines.Size=UDim2.fromScale(1,1); lines.BackgroundTransparency=1; lines.Parent=gui
    for i=1,40 do
      local l = Instance.new("Frame"); l.BackgroundColor3 = Color3.new(0,0,0); l.BackgroundTransparency=0.85
      l.Size = UDim2.new(1,0,0,1); l.Position = UDim2.new(0,0,(i/40),0); l.Parent = lines
    end
    local vign = Instance.new("Frame"); vign.BackgroundColor3=Color3.new(0,0,0); vign.BackgroundTransparency=1; vign.Size=UDim2.fromScale(1,1); vign.Parent=gui
    TweenService:Create(vign, TweenInfo.new(0.25), {BackgroundTransparency=0.8}):Play()
    task.delay(4, function() gui:Destroy() end)
  end
})

GlitchTab:CreateButton({
  Name = "📸 Camera shake (2s)",
  Callback = function()
    local cam = Workspace.CurrentCamera; if not cam then return end
    local t0 = tick(); local baseCF = cam.CFrame
    local conn; conn = RunService.RenderStepped:Connect(function()
      local t = tick()-t0; local mag = (t<2) and (0.2*(2-t)) or 0
      cam.CFrame = baseCF * CFrame.new(math.random(-1,1)*mag, math.random(-1,1)*mag, 0)
      if t>=2 then cam.CFrame = baseCF; conn:Disconnect() end
    end)
  end
})

-- ============ UI Toggle ============
local function bindUIToggle(tab)
  tab:CreateKeybind({
    Name = "Toggle UI",
    CurrentKeybind = Enum.KeyCode.RightShift,
    Pressed = function()
      local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
      local gui = pg and pg:FindFirstChild("SlightlyBloxyUI")
      if gui then gui.Enabled = not gui.Enabled end
    end
  })
end
bindUIToggle(TeleportTab); bindUIToggle(MainTab); bindUIToggle(RandomTab); bindUIToggle(GlitchTab)

-- ============ Scroll-fix (alle tabs) ============
task.defer(function()
  local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
  local root = pg and (pg:FindFirstChild("SlightlyBloxyUI") or pg:WaitForChild("SlightlyBloxyUI", 5))
  if not root then return end
  local function patchScrolling(frame)
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.ScrollBarThickness = 6
    frame.ScrollBarImageTransparency = 0.35
    frame.CanvasSize = UDim2.new(0,0,0,0)
  end
  for _, obj in ipairs(root:GetDescendants()) do
    if obj:IsA("ScrollingFrame") then patchScrolling(obj) end
  end
  root.DescendantAdded:Connect(function(obj)
    if obj:IsA("ScrollingFrame") then patchScrolling(obj) end
  end)
end)
