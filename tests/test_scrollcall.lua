-- Scroll Call: unread count, cast + bag diff, bags-only fallback, soulbound / priced / no scan, never shown in combat.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local S = W.S
local check = W.check
local ns = W.loadAddon(".", "ScrollCall")
local KWYJIBO, UPDOG, COMP = 211780, 213543, 1296017
W.items = { [KWYJIBO] = { name = "Scroll: KWYJIBO", sellPrice = 15 }, [UPDOG] = { name = "Scroll: UPDOG", sellPrice = 15 },
  [900001] = { name = "Spell Notes: A", sellPrice = 0 }, [900002] = { name = "Spell Notes: B", sellPrice = 0 } }
W.bags = { [0] = {} }
W.fire("PLAYER_LOGIN")
local SC, FS = ns.SC, _G.FrostSuite_1_0
local row = FS.rows.ScrollCall
local prices = {}
ns.Hub.RegisterPrices("PriceLog", function(id) return prices[id] end)
local function bags(t) W.bags = { [0] = t }; W.fire("BAG_UPDATE_DELAYED") end

check(row.state == "hidden", "no unread scrolls: hidden")
bags({ { KWYJIBO, 2 }, { UPDOG, 1 } })
check(SC.unread == 3 and row.state == "active" and row.headText == "3 unread scrolls", "3 unread scrolls")

-- 1. Cast seen: the result is whatever appears in the bags after it (here it lands one update late).
prices[900001] = { p = 25000, t = 1 }
S.cast(COMP)
bags({ { KWYJIBO, 1 }, { UPDOG, 1 } })
check(SC.pending ~= nil and #KennyScrollCallDB.log == 0, "scroll gone, result not there yet: keep waiting")
bags({ { KWYJIBO, 1 }, { UPDOG, 1 }, { 900001, 1 } })
check(#KennyScrollCallDB.log == 1 and SC.last.how == "cast" and SC.last.items[1].price == 25000, "result logged with its PriceLog price")
check(row.lineText[1]:find("Spell Notes: A: ~2g 50s before AH cut"), "last result shown before AH cut")
check(SC.Mode() == "cast" and row.statusText:find("read 1"), "cast mode, session count")

-- 2. Soulbound result.
S.cast(COMP)
W.bags = { [0] = { { KWYJIBO, 1 }, { 900002, 1, true }, { 900001, 1 } } }; W.fire("BAG_UPDATE_DELAYED")
check(SC.last.items[1].bound and row.lineText[1]:find("soulbound"), "bound result: soulbound, no price")

-- 3. No price scan: said, not guessed.
S.cast(COMP)
bags({ { 900002, 2, true }, { 900001, 1 } })
check(SC.last.items[1].itemID == 900002, "second copy of B")
prices = {}
S.cast(COMP)
bags({ { 900002, 2, true }, { 900001, 1 }, { 900003, 1 } })
W.advance(6); W.fire("BAG_UPDATE_DELAYED")
check(#KennyScrollCallDB.log == 3 and SC.pending == nil, "no scroll left the bags: loot after a cast is not a read")

-- 4. Hidden casts: bags-only fallback, marked "(from bags)"; two scrolls leaving at once is not a read.
SC.plainCasts = 0
bags({ { UPDOG, 1 } })
S.castSecretInCombat = true; W.combat = true; S.cast(COMP); W.combat = false
check(SC.hiddenCasts == 1 and SC.pending == nil, "secret cast event: not trusted")
bags({ { 900004, 1 } })
check(SC.last.how == "bags" and SC.EntryText(SC.last):find("from bags"), "bags only: one scroll out + something new = a read (from bags)")
local n = #KennyScrollCallDB.log
bags({ { KWYJIBO, 2 } }); bags({ { 900005, 1 } })
check(#KennyScrollCallDB.log == n, "two scrolls leaving at once is not logged as a read")

-- 5. A cast that leaves nothing new: logged honestly after the wait.
bags({ { UPDOG, 1 } })
S.cast(COMP); bags({})
W.advance(6)
check(SC.EntryText(SC.last) == "nothing new in your bags", "nothing appeared: said so")

-- 5b. Review fixes: mixed diffs are flagged and kept out of the gold total; the pre-read snapshot survives a bag update
-- that arrives before the cast event; a read logged from bags just before its cast event isn't counted twice.
prices = { [900006] = { p = 10000, t = 1 }, [900007] = { p = 50000, t = 1 }, [900008] = { p = 30000, t = 1 } }
bags({ { UPDOG, 1 }, { 900001, 1 } })
local worth0, reads0 = KennyScrollCallDB.session.worth, KennyScrollCallDB.session.reads
S.cast(COMP)
bags({ { 900001, 1 }, { 900006, 1 }, { 900007, 1 } })
check(SC.last.uncertain and SC.EntryText(SC.last):find("uncertain"), "two new items in the read window: flagged uncertain")
check(KennyScrollCallDB.session.worth == worth0 and KennyScrollCallDB.session.reads == reads0 + 1, "uncertain read kept out of the gold total")
bags({ { UPDOG, 1 } }); S.cast(COMP)
bags({ { 900008, 1 }, { 900006, 1 } }) -- result + something else left the bags (sold / moved) in the same update
check(SC.last.uncertain, "result with another item leaving: uncertain")
-- bag update (scroll gone) before the cast event; the result lands after
bags({ { KWYJIBO, 1 } })
local n0 = #KennyScrollCallDB.log
bags({})
check(SC.held ~= nil and SC.snapshot.counts[KWYJIBO] == 1, "scroll left first: pre-read bags kept")
S.cast(COMP)
bags({ { 900008, 1 } })
check(#KennyScrollCallDB.log == n0 + 1 and SC.last.how == "cast" and not SC.last.uncertain and SC.last.items[1].itemID == 900008,
  "result after an early bag update: one clean cast read")
check(KennyScrollCallDB.session.worth == worth0 + 30000, "clean read counted in the gold total")
-- result already in the bags when the cast event arrives: logged once, as a cast
bags({ { UPDOG, 1 } }); n0 = #KennyScrollCallDB.log
bags({ { 900006, 1 } })
S.cast(COMP)
check(#KennyScrollCallDB.log == n0 + 1 and SC.last.how == "cast" and SC.pending == nil, "bags-first read not logged twice")
check(row.statusText:find("before AH cut"), "session total says before AH cut")
W.advance(1.1)
check(not row.status.shown and row.statusLine.shown and row.statusSlot == 2 and row.h == 78,
  "r4: session total is too long for the title line, so it moves to body line 2 (box 78)")

-- 6. Combat hides it; /frost scroll toggles; log / reset / debug; tooltip.
bags({ { UPDOG, 1 } })
W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
check(row.state == "hidden", "hidden in combat")
W.prints = {}; SC.Slash("")
check(W.prints[1]:find("waits until combat ends"), "/frost scroll waits in combat")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
check(row.state == "active", "back after combat")
bags({}); check(row.state == "hidden", "no scrolls: hidden")
SC.Slash(""); check(row.state == "active" and row.headText == "No unread scrolls.", "/frost scroll shows it")
SC.Slash(""); check(row.state == "hidden", "and hides it")
W.prints = {}; SC.Slash("log"); check(#W.prints >= 3, "log prints")
W.prints = {}; SC.Slash("debug"); check(#W.prints == 3, "debug prints")
local tt = { lines = {} }; function tt.AddLine(_, t) tt.lines[#tt.lines + 1] = t end
ns.Hub.RunTooltips(tt, { id = UPDOG })
check(tt.lines[1] == "Scroll Call: unread: READ", "tooltip on untranslated scrolls")
SC.Slash("reset"); check(#KennyScrollCallDB.log == 0 and KennyScrollCallDB.session.reads == 0, "reset clears the log")

-- 7. Not a Mage: hidden.
W.class = "WARRIOR"; W.fire("PLAYER_LOGIN"); bags({ { UPDOG, 1 } })
check(row.state == "hidden", "non-Mage: hidden")
W.class = nil

W.done("ScrollCall")
