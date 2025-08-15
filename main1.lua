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

local LocalPlayer = Players.LocalPlayer

-- ============ Helpers ============
local function getHRP(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function myChar() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function myHumanoid() local c = myChar(); return c and c:FindFirstChildOfClass("Humanoid") end
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

-- Beschermde ApplyDescription met R6/R15 fix
local function applyDescriptionToHumanoid(humanoid, desc)
    -- Probeer reset-variant met de rig van de target (werkt tussen R6/R15)
    local okReset, errReset = pcall(function()
        humanoid:ApplyDescriptionReset(desc, humanoid.RigType)
    end)
    if okReset then return true end
    -- Fallback: gewone ApplyDescription
    local okPlain, errPlain = pcall(function()
        humanoid:ApplyDescription(desc)
    end)
    if okPlain then return true end
    return false, (errReset or errPlain or "unknown error")
end

-- ============ Window ============
local Window = _G.SlightlyBloxyWindow or Rayfield:CreateWindow({
  Name = "SlightlyBloxyUI – Tools",
  Theme = "Default",
})
_G.SlightlyBloxyWindow = Window

-- =========================================================
-- TAB: Teleport (client-side me→them; server nodig voor them→me)
-- =========================================================
local TPEvent = ReplicatedStorage:FindFirstChild("TPRequest") -- optioneel; server script nodig

local TeleportTab = Window:CreateTab("Teleport", 0)
TeleportTab:CreateSection("TP Tools (client-side me→them)")

local currentTargetTP = nil
local ddTP

local function playerOptions() return listPlayers() end

ddTP = TeleportTab:CreateDropdown({
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
    local text = tostring(txt or "")
    local found
    local lower = text:lower()
    for _, p in ipairs(Players:GetPlayers()) do
      if p ~= LocalPlayer then
        if p.Name:lower():find(lower, 1, true) or (p.DisplayName or ""):lower():find(lower, 1, true) then
          found = p; break
        end
      end
    end
    if found then
      currentTargetTP = found.Name
      Rayfield:Notify({ Title="Teleport", Content="Gevonden: "..found.Name, Duration=2 })
    else
      Rayfield:Notify({ Title="Teleport", Content="Niet gevonden.", Duration=2 })
    end
  end
})

TeleportTab:CreateButton({
  Name = "🔄 Refresh spelerslijst",
  Callback = function()
    ddTP = TeleportTab:CreateDropdown({
      Name = "Kies speler (refreshed)",
      Options = playerOptions(),
      CurrentOption = currentTargetTP,
      Callback = function(opt) currentTargetTP = extractName(opt) end
    })
    Rayfield:Notify({ Title="Teleport", Content="Lijst ververst.", Duration=2 })
  end
})

TeleportTab:CreateButton({
  Name = "TP me → them",
  Callback = function()
    if not currentTargetTP then
      Rayfield:Notify({ Title="Teleport", Content="Geen speler geselecteerd.", Duration=2 }); return
    end
    local t = Players:FindFirstChild(currentTargetTP)
    if not t or not t.Character then
      Rayfield:Notify({ Title="Teleport", Content="Speler niet beschikbaar.", Duration=2 }); return
    end
    local tHRP = getHRP(t.Character)
    if not tHRP then
      Rayfield:Notify({ Title="Teleport", Content="Doel heeft geen HRP.", Duration=2 }); return
    end
    myChar():PivotTo(tHRP.CFrame + Vector3.new(0,4,0))
    Rayfield:Notify({ Title="Teleport", Content="Jij → "..currentTargetTP, Duration=2 })
  end
})

TeleportTab:CreateButton({
  Name = "Bring them → me (server vereist)",
  Callback = function()
    if not TPEvent then
      Rayfield:Notify({ Title="Teleport", Content="Server-event ontbreekt. Niet beschikbaar.", Duration=3 })
      return
    end
    if not currentTargetTP then
      Rayfield:Notify({ Title="Teleport", Content="Geen speler geselecteerd.", Duration=2 })
      return
    end
    TPEvent:FireServer("themToMe", currentTargetTP)
    Rayfield:Notify({ Title="Teleport", Content="Aangevraagd bij server.", Duration=2 })
  end
})

-- =========================================================
-- TAB: Main — tijdelijk/lokaal avatar wisselen (met R6/R15 fix)
-- =========================================================
local MainTab = Window:CreateTab("Main", 0)
MainTab:CreateSection("Give/Copy Avatars (temporary, local)")

local originalDescByUserId = {} -- UserId -> HumanoidDescription
local currentTargetMain = nil

local ddMain = MainTab:CreateDropdown({
  Name = "Kies speler",
  Options = playerOptions(),
  CurrentOption = nil,
  Callback = function(opt) currentTargetMain = extractName(opt) end
})

MainTab:CreateButton({
  Name = "🔄 Refresh spelerslijst",
  Callback = function()
    ddMain = MainTab:CreateDropdown({
      Name = "Kies speler (refreshed)",
      Options = playerOptions(),
      CurrentOption = currentTargetMain,
      Callback = function(opt) currentTargetMain = extractName(opt) end
    })
    Rayfield:Notify({ Title="Main", Content="Lijst ververst.", Duration=2 })
  end
})

-- Give MY avatar -> target (local, temporary)  [met rig-compat fix]
MainTab:CreateButton({
  Name = "Give MY avatar → target (local/temporary)",
  Callback = function()
    if not currentTargetMain then
      Rayfield:Notify({ Title="Main", Content="Geen speler geselecteerd.", Duration=2 }); return
    end
    local target = findByName(currentTargetMain)
    if not target or not target.Character then
      Rayfield:Notify({ Title="Main", Content="Speler niet beschikbaar.", Duration=2 }); return
    end
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if not hum then
      Rayfield:Notify({ Title="Main", Content="Doel heeft geen Humanoid.", Duration=2 }); return
    end

    -- originele opgeslagen?
    if not originalDescByUserId[target.UserId] then
      local ok, orig = pcall(function() return hum:GetAppliedDescription() end)
      if ok and orig then originalDescByUserId[target.UserId] = orig end
    end

    -- jouw description ophalen
    local okMy, myDesc = pcall(function()
      return Players:GetHumanoidDescriptionFromUserId(LocalPlayer.UserId)
    end)
    if not okMy or not myDesc then
      Rayfield:Notify({ Title="Main", Content="Kon jouw avatar-info niet ophalen.", Duration=3 })
      return
    end

    -- toepassen met R6/R15 fix
    local ok, err = applyDescriptionToHumanoid(hum, myDesc)
    if not ok then
      Rayfield:Notify({ Title="Main", Content="Apply faalde: "..tostring(err), Duration=4 })
      return
    end

    Rayfield:Notify({ Title="Main", Content="Avatar toegepast (lokaal en tijdelijk).", Duration=3 })
  end
})

-- EXTRA: Copy TARGET avatar -> ME (local, temporary)
MainTab:CreateButton({
  Name = "Copy TARGET avatar → ME (local/temporary)",
  Callback = function()
    if not currentTargetMain then
      Rayfield:Notify({ Title="Main", Content="Geen speler geselecteerd.", Duration=2 }); return
    end
    local target = findByName(currentTargetMain)
    if not target or not target.Character then
      Rayfield:Notify({ Title="Main", Content="Speler niet beschikbaar.", Duration=2 }); return
    end
    local tHum = target.Character:FindFirstChildOfClass("Humanoid")
    local myHum = myHumanoid()
    if not tHum or not myHum then
      Rayfield:Notify({ Title="Main", Content="Humanoid ontbreekt bij target of bij jou.", Duration=3 }); return
    end

    -- beschrijving van target ophalen
    local okT, tDesc = pcall(function() return tHum:GetAppliedDescription() end)
    if not okT or not tDesc then
      -- fallback via UserId (kan afwijken van live accessories)
      local okU, userDesc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(target.UserId)
      end)
      tDesc = okU and userDesc or nil
    end
    if not tDesc then
      Rayfield:Notify({ Title="Main", Content="Kon description van target niet ophalen.", Duration=3 })
      return
    end

    local ok, err = applyDescriptionToHumanoid(myHum, tDesc)
    if not ok then
      Rayfield:Notify({ Title="Main", Content="Apply faalde: "..tostring(err), Duration=4 })
      return
    end
    Rayfield:Notify({ Title="Main", Content="Je draagt nu tijdelijk de target-avatar (lokaal).", Duration=3 })
  end
})

-- Revert target -> original (local)
MainTab:CreateButton({
  Name = "Revert target to original (local)",
  Callback = function()
    if not currentTargetMain then
      Rayfield:Notify({ Title="Main", Content="Geen speler geselecteerd.", Duration=2 }); return
    end
    local target = findByName(currentTargetMain)
    if not target or not target.Character then
      Rayfield:Notify({ Title="Main", Content="Speler niet beschikbaar.", Duration=2 }); return
    end
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if not hum then
      Rayfield:Notify({ Title="Main", Content="Doel heeft geen Humanoid.", Duration=2 }); return
    end

    local orig = originalDescByUserId[target.UserId]
    if not orig then
      -- fallback: neem huidige outfits van target (kan afwijken van 'echt' origineel)
      local ok, cur = pcall(function() return Players:GetHumanoidDescriptionFromUserId(target.UserId) end)
      if ok and cur then orig = cur end
    end
    if not orig then
      Rayfield:Notify({ Title="Main", Content="Geen originele description opgeslagen.", Duration=3 })
      return
    end

    local ok, err = applyDescriptionToHumanoid(hum, orig)
    if not ok then
      Rayfield:Notify({ Title="Main", Content="Revert faalde: "..tostring(err), Duration=4 })
      return
    end
    Rayfield:Notify({ Title="Main", Content="Target teruggezet (lokaal).", Duration=3 })
  end
})

MainTab:CreateParagraph({
  Title = "Let op",
  Content = "Avatar-wijzigingen zijn alleen LOKAAL zichtbaar voor jou en tijdelijk. " ..
            "Ze verdwijnen bij respawn, serverwissel of wanneer jij de game verlaat."
})

-- ============ UI Toggle ============
TeleportTab:CreateKeybind({
  Name = "Toggle UI",
  CurrentKeybind = Enum.KeyCode.RightShift,
  Pressed = function()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui = pg and pg:FindFirstChild("SlightlyBloxyUI")
    if gui then gui.Enabled = not gui.Enabled end
  end
})
MainTab:CreateKeybind({
  Name = "Toggle UI",
  CurrentKeybind = Enum.KeyCode.RightShift,
  Pressed = function()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui = pg and pg:FindFirstChild("SlightlyBloxyUI")
    if gui then gui.Enabled = not gui.Enabled end
  end
})

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
