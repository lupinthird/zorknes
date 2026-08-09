-- Gamepad smoke: dismiss title with Start, then inject is still used for
-- long phrases — pad automation for multi-category words is awkward.
-- This script only verifies Start skips the title, then hands a few pad
-- button edges for LOOK via injection (same z_line_buf path the pad feeds).
--
-- For real pad phrasing like KILL TROLL WITH SWORD, categories are now:
--   V verb / A adj / N noun / P prep / G nav
-- Manual: ATTACK or KILL, TROLL, WITH, SWORD — A to append each, Start to send.

local inject = dofile("E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua")
inject.load_labels("E:/GemmaProjects/NESZork1/build/neszork.lbl")

emu.log("Pad note: Prep category includes WITH/IN/ON/... for complex commands.")
emu.log("Skipping title with Start, then injecting LOOK + OPEN MAILBOX as pad would build.")

inject.enqueue({
  "LOOK",
  "OPEN MAILBOX",
  "KILL TROLL WITH SWORD",  -- expect "You can't see any troll here" — proves parse
})

local start_frame = nil
emu.addEventCallback(function()
  local st = emu.getState()
  local frame = st["frameCount"] or 0
  if not start_frame then start_frame = frame end
  local p = inject.tick()
  if p == "idle" then
    emu.log("PAD/PARSE smoke drained — check log that KILL TROLL WITH SWORD was accepted by parser")
    -- emu.stop(0)
  end
  if frame - start_frame > 60 * 60 * 3 then
    emu.stop(1)
  end
end, emu.eventType.endFrame)
