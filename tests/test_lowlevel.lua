-- ScrollCall: low-level characters (FrostSuite r5). A level 1 Mage (Fireball, Frost Armor), a mid-level Mage with only some
-- spells, and a non-Mage: loads quietly, never shows made-up data, says when to learn what it needs, "Hide until I learn"
-- is saved per character, and the box comes back by itself when the spell is learned.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
W.level, W.known = 1, { [133] = true, [168] = true }   -- level 1: Fireball and Frost Armor
local ns = W.loadAddon(".", "ScrollCall")
W.fire("PLAYER_LOGIN"); W.fire("SPELLS_CHANGED"); W.advance(2)
local FS = _G.FrostSuite_1_0
local row = FS.rows.ScrollCall
local function quiet(label)
  local bad = false
  for _, p in ipairs(W.prints) do if p:find("WARNING") or p:lower():find("error") then bad = true end end
  check(#ns.Core.errors == 0 and not bad, label .. ": no Lua errors, nothing alarming in chat")
end
local function learnLine() return row.state == "learn" and row.learnText and row.learnText.shown and row.learnText.text_ or nil end
local function fight(ids)
  W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
  for _, id in ipairs(ids or { 133, 116 }) do W.S.cast(id) end
  W.advance(3)
end
local function peace() W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(3) end
local function learn(lvl, ids)
  W.level = lvl
  W.fire("PLAYER_LEVEL_UP", lvl)
  for _, id in ipairs(ids) do W.known[id] = true; W.fire("LEARNED_SPELL_IN_SKILL_LINE", id) end
  W.fire("SPELLS_CHANGED"); W.advance(2)
end
quiet("level 1 login")
check(row.state == "hidden", "level 1, no scrolls: nothing to show")
W.items = { [211780] = { name = "Untranslated Scroll" } }
W.bags = { [0] = { { 211780, 1 } } }
W.fire("BAG_UPDATE_DELAYED"); W.advance(1)
local L1 = "Learn Comprehension to read scrolls"
check(learnLine() == L1, "level 1 with a scroll: 'Learn Comprehension to read scrolls'")
local tip = { n = 0, AddLine = function(t) t.n = t.n + 1 end }
ns.SC.Tooltip(tip, 211780)
check(tip.n == 0, "no READ prompt on the scroll before Comprehension is learned")

fight({ 133 }); check(not row.shown, "level 1 in combat: hidden"); quiet("level 1 combat"); peace()
check(learnLine() == L1 and row.learnBtn.shown, "after combat the line and button are back")
row.learnBtn.scripts.OnClick(row.learnBtn)
check(row.state == "hidden" and KennyScrollCallDB.hideUntilLearned["Kenny-TestRealm"] == true, "Hide until I learn: hidden and saved")
learn(10, { 116 })
check(row.state == "hidden", "level 10 without Comprehension: still hidden")
learn(10, { 1296017 })
check(row.state == "active" and row.headText == "1 unread scroll" and KennyScrollCallDB.hideUntilLearned["Kenny-TestRealm"] == nil,
  "Comprehension learned: the box comes back with the count")
ns.SC.Tooltip(tip, 211780)
check(tip.n == 1, "and the READ prompt is back")
quiet("mid level")

-- not a Mage: never a learn line, never an error
W.class = "WARRIOR"; W.known = {}; W.level = 1; W.fire("SPELLS_CHANGED"); W.fire("PLAYER_LEVEL_UP", 2); W.advance(2)
check(row.state == "hidden" and not learnLine(), "non-Mage: hidden, no learn line")
fight({ 78 }); peace()
quiet("non-Mage")
W.class = nil
W.done("ScrollCall low level")
