-- Scroll Call: a gold log for a Mage's Comprehension on WoW: Forever. Written from scratch (MIT).
--
-- Untranslated scrolls ("A Mage can decipher this with their Comprehension skill.") pile up in bags. This box counts the
-- unread ones and logs what each read turned into, priced from your own PriceLog scans ("before AH cut") through the Kenny
-- hub, or "soulbound" when the result is bound. It never reads, casts or sells anything for you.
--
-- How a read is seen (picked at runtime; /frost scroll debug prints it):
--   "cast"  = your own Comprehend Scroll cast (UNIT_SPELLCAST_SUCCEEDED, plain spell ID). The next bag updates are compared
--             with the bags before the cast; whatever appeared is the result.
--   "bags"  = cast events hidden or not seen: a read is logged when exactly one untranslated scroll leaves your bags and
--             something new appears in the same bag update. Marked "(from bags)".
--   Results come from the bags, never from a guess; "nothing new in your bags" is logged when a read leaves nothing.
local ADDON, ns = ...
local C, Core, FS = ns.Compat, ns.Core, ns.FrostSuite
local L = Core.L

local SC = {}
KennyScrollCall = SC
ns.SC = SC
local KEY = "ScrollCall"
local SCHEMA = 1
local WAIT = 5 -- seconds to wait for the result to land after a cast
local LOG_MAX = 50

-- IDs from the game's tables, build 70862: ItemSparse (description "A Mage can decipher this…") and SpellName.
SC.SCROLLS = {}
for _, id in ipairs({ 211780, 211784, 211785, 211786, 211787, 211853, 211854, 211855, 213543, 213544, 213545, 213546, 213547,
  281015, 281016, 281017, 281018 }) do SC.SCROLLS[id] = true end
SC.COMPREHEND = { [1296017] = true, [1309965] = true, [1309973] = true, [1310029] = true, [1310030] = true }
-- Comprehension is a Mage-only skill line (3012). Its trainer level isn't in the client data (SpellLevels.BaseLevel 0 for
-- 1296017, build 1.60.1.71037), so the line names no level.
SC.NEEDS = { { name = L["Comprehension"], spells = SC.COMPREHEND, text = L["Learn Comprehension to read scrolls"] } }

local db, row
local migrations = {}
SC.snapshot, SC.pending, SC.unread, SC.asked = nil, nil, 0, false
SC.hiddenCasts, SC.plainCasts = 0, 0

local function newSession() return { reads = 0, worth = 0, unpriced = 0, bound = 0, since = C.Now() } end

function SC.Money(c)
  if not c then return "-" end
  c = math.floor(c + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return ("%ds %dc"):format(s, cp) end
  return ("%dc"):format(cp)
end

-- { counts = {itemID = n}, bound = {itemID = true}, names = {} } or nil when bags can't be read
function SC.ReadBags()
  local CC = C_Container
  if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return nil end
  local snap = { counts = {}, bound = {}, names = {} }
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (FS.Call(CC.GetContainerNumSlots, bag) or 0) do
      local info = FS.Call(CC.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and C.SafeNumber(info.itemID)
      if id then
        snap.counts[id] = (snap.counts[id] or 0) + (C.SafeNumber(info.stackCount) or 1)
        if info.isBound == true then snap.bound[id] = true end
        snap.names[id] = snap.names[id] or info.itemName
      end
    end
  end
  return snap
end
function SC.Unread(snap)
  local n = 0
  for id in pairs(SC.SCROLLS) do n = n + ((snap and snap.counts[id]) or 0) end
  return n
end
-- gained = { {itemID, count} }, scrollsUsed = n, otherLeft = true when a non-scroll item also left the bags
function SC.Diff(before, after)
  local gained, used, otherLeft = {}, 0, false
  for id, n in pairs(after.counts) do
    local d = n - (before.counts[id] or 0)
    if d > 0 and not SC.SCROLLS[id] then gained[#gained + 1] = { id, d } end
  end
  for id, n in pairs(before.counts) do
    if not SC.SCROLLS[id] and (after.counts[id] or 0) < n then otherLeft = true end
  end
  for id in pairs(SC.SCROLLS) do
    local d = (before.counts[id] or 0) - (after.counts[id] or 0)
    if d > 0 then used = used + d end
  end
  table.sort(gained, function(a, b) return a[1] < b[1] end)
  return gained, used, otherLeft
end

function SC.Price(id)
  local hub = ns.Hub
  if not (hub and hub.GetPrice) then return nil end
  local rec = hub.GetPrice(id)
  if type(rec) == "table" then return C.SafeNumber(rec.p) end
  return nil
end
local function itemName(id, snap)
  local n = snap and snap.names[id]
  if not n and C_Item and C_Item.GetItemInfo then local ok, nm = pcall(C_Item.GetItemInfo, id); if ok then n = nm end end
  return n or ("item " .. id)
end

-- One logged read. how = "cast" or "bags". uncertain = the bag change wasn't only "one scroll out, one item in" (other
-- loot or items moved in the same window): the entry is flagged and kept out of the gold total.
function SC.Log(gained, after, how, uncertain)
  local e = { t = C.Now(), how = how, items = {}, uncertain = uncertain or nil }
  local s = db.session
  s.reads = s.reads + 1
  for _, g in ipairs(gained) do
    local id, n = g[1], g[2]
    local it = { itemID = id, count = n, name = itemName(id, after) }
    if after.bound[id] then it.bound = true; if not uncertain then s.bound = s.bound + 1 end
    else
      local p = SC.Price(id)
      if p then it.price = p * n; if not uncertain then s.worth = s.worth + it.price end
      elseif not uncertain then s.unpriced = s.unpriced + 1 end
    end
    e.items[#e.items + 1] = it
  end
  table.insert(db.log, 1, e)
  while #db.log > LOG_MAX do table.remove(db.log) end
  SC.last = e
  return e
end

function SC.EntryText(e)
  if not e then return nil end
  if #e.items == 0 then return L["nothing new in your bags"] end
  local pre = e.uncertain and (L["uncertain, other loot mixed in:"] .. " ") or ""
  local parts = {}
  for _, it in ipairs(e.items) do
    local v = it.bound and L["soulbound"] or (it.price and ("~" .. SC.Money(it.price) .. " " .. L["before AH cut"]) or L["no price scan"])
    parts[#parts + 1] = ("%s%s: %s"):format(it.name, it.count > 1 and (" x" .. it.count) or "", v)
  end
  return pre .. table.concat(parts, ", ") .. (e.how == "bags" and (" " .. L["(from bags)"]) or "")
end

function SC.Mode()
  if SC.plainCasts > 0 then return "cast" end
  return "bags"
end

local function mixed(gained, used, otherLeft) return used ~= 1 or #gained ~= 1 or otherLeft end

-- Bag update. While a cast is pending, or after a scroll left with nothing new yet ("held"), the pre-read snapshot is
-- kept, so the result is always compared with the bags from before the read.
function SC.OnBags()
  local after = SC.ReadBags()
  if not after then return end
  local before = SC.snapshot
  SC.lastBags = nil -- only the bag update right before a cast event can be that cast's read
  if SC.pending and before then
    local gained, used, otherLeft = SC.Diff(before, after)
    if #gained > 0 and used > 0 then SC.Log(gained, after, "cast", mixed(gained, used, otherLeft)); SC.pending = nil; SC.held = nil; SC.snapshot = after
    elseif C.Clock() - SC.pending > WAIT then
      if used > 0 then SC.Log({}, after, "cast") end
      SC.pending = nil; SC.held = nil; SC.snapshot = after
    end -- else: keep the pre-cast snapshot and wait for the result to land
  elseif before then
    local gained, used, otherLeft = SC.Diff(before, after)
    if used == 1 and #gained > 0 then
      SC.lastBags = { e = SC.Log(gained, after, "bags", mixed(gained, used, otherLeft)), at = C.Clock() }
      SC.held = nil; SC.snapshot = after
    elseif used == 1 and #gained == 0 and not otherLeft and (not SC.held or C.Clock() - SC.held <= WAIT) then
      -- a scroll left before its result (or before the cast event): hold the pre-read bags
      if not SC.held then
        SC.held = C.Clock()
        C_Timer.After(WAIT + 0.5, function() if SC.held then Core.SafeCall("bags", SC.OnBags) end end)
      end
    else SC.held = nil; SC.snapshot = after end
  else SC.snapshot = after end
  SC.unread = SC.Unread(after)
  SC.Update()
end

function SC.OnCast(spellID)
  if C.IsSecret(spellID) then SC.hiddenCasts = SC.hiddenCasts + 1; return end
  if not SC.COMPREHEND[spellID] then return end
  SC.plainCasts = SC.plainCasts + 1
  -- the bag update came first and already logged this read from the bags: it was this cast
  if SC.lastBags and C.Clock() - SC.lastBags.at < 2 then SC.lastBags.e.how = "cast"; SC.lastBags = nil; SC.Update(); return end
  SC.snapshot = SC.snapshot or SC.ReadBags()
  SC.pending = C.Clock()
  C_Timer.After(WAIT + 0.5, function() if SC.pending then Core.SafeCall("bags", SC.OnBags) end end)
end

function SC.Showing() return not C.InCombat() and (SC.unread > 0 or SC.asked) end

function SC.Update()
  if not row then return end
  if not SC.Showing() or not SC.known then FS.State(KEY, "hidden"); return end
  if SC.need then FS.NotYet(KEY, SC.need); return end
  local s = db.session
  FS.Headline(KEY, SC.unread > 0 and ("%d %s"):format(SC.unread, SC.unread == 1 and L["unread scroll"] or L["unread scrolls"]) or L["No unread scrolls."], "Snow")
  FS.ClearLines(KEY)
  FS.Line(KEY, 1, "|cffffd100" .. L["Last:"] .. "|r " .. (SC.EntryText(SC.last) or L["none read yet"]))
  FS.Status(KEY, ("%s %d · ~%s %s"):format(L["read"], s.reads, SC.Money(s.worth), L["before AH cut"]), "Mist")
  FS.State(KEY, "active")
end

function SC.Tooltip(tooltip, itemID)
  if not SC.SCROLLS[itemID] or not FS.IsMage() or SC.need then return end -- no READ prompt before Comprehension is learned
  tooltip:AddLine("Scroll Call: " .. L["unread: READ"], 0.85, 0.95, 1)
end

function SC.DetectionLines()
  local s = db and db.session or newSession()
  return {
    ("mode: %s  (cast = Comprehend Scroll casts seen, bags = only bag changes); plain casts %d, hidden cast events %d"):format(SC.Mode(), SC.plainCasts, SC.hiddenCasts),
    ("unread scrolls: %d; waiting for a result: %s; knows Comprehend Scroll: %s"):format(SC.unread, tostring(SC.pending ~= nil), tostring(SC.need == nil)),
    ("session: %d read, ~%s before AH cut (uncertain reads left out), %d soulbound, %d without a price scan"):format(s.reads, SC.Money(s.worth), s.bound, s.unpriced),
  }
end

function SC.Slash(msg)
  local cmd = (msg or ""):lower():match("^(%S*)")
  if cmd == "log" then
    if #db.log == 0 then Core.Print(L["nothing logged yet"]) end
    for i = 1, math.min(10, #db.log) do Core.Print(date("%m-%d %H:%M ", db.log[i].t) .. SC.EntryText(db.log[i])) end
  elseif cmd == "reset" then db.session = newSession(); db.log = {}; SC.last = nil; Core.Print(L["log cleared"]); SC.Update()
  elseif cmd == "debug" then for _, l in ipairs(SC.DetectionLines()) do Core.Print(l) end
  elseif C.InCombat() then Core.Print(L["Scroll Call waits until combat ends."])
  else SC.asked = not SC.asked; SC.Update() end
end

-- ---------- wiring ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
SC.known = true
-- Not a Mage: hidden. A Mage without Comprehend Scroll yet: SC.need (the box, when it shows, says to learn it).
function SC.CheckKnown()
  SC.known = FS.IsMage()
  SC.need = SC.known and FS.Missing(SC.NEEDS) or nil
  if SC.known and not SC.need then FS.Learned(KEY) end
end
local function refresh()
  SC.CheckKnown()
  SC.snapshot = SC.ReadBags(); SC.unread = SC.Unread(SC.snapshot); SC.Update()
end
local handlers = {
  PLAYER_LOGIN = refresh, SPELLS_CHANGED = function() if not C.InCombat() then SC.CheckKnown(); SC.Update() end end,
  BAG_UPDATE_DELAYED = SC.OnBags,
  PLAYER_REGEN_DISABLED = function() FS.State(KEY, "hidden") end,
  PLAYER_REGEN_ENABLED = function() SC.Update() end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID) if unit == "player" then SC.OnCast(spellID) end end,
}
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyScrollCallDB, migrations, SCHEMA)
    db.session = db.session or newSession()
    db.log = db.log or {}
    KennyScrollCallDB = db
    SC.last = db.log[1]
    row = FS.Register(KEY, db, { title = L["Scroll Call"], slash = SC.Slash, help = "(toggle) | log | reset | debug", debug = Core.PrintDebug,
      refresh = function() if not C.InCombat() then SC.CheckKnown(); SC.Update() end end })
    if ns.Hub and ns.Hub.AddTooltip then ns.Hub.AddTooltip(ADDON, 61, SC.Tooltip) end
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = "/frost scroll",
  required = { "C_Container.GetContainerItemInfo", "C_Timer.After" },
  optional = { "C_Item.GetItemInfo" },
  db = function() return db end,
  firstRun = { L["Scroll Call is ready: it counts your untranslated scrolls and logs what each Comprehension read turns into."] },
  debugLines = function() return SC.DetectionLines() end })
