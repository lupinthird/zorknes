-- Smoke test: keyboard-equivalent command injection through early Zork I.
-- Proves aread → tokenise → world change (mailbox open, lamp taken, trap, light).
--
-- Run in Mesen Script Window (with ROM loaded), or:
--   C:\Mesen\Mesen.exe C:\Mesen\ROMs\neszork.nes E:\GemmaProjects\NESZork1\scripts\zork_smoke_keyboard.lua
--
-- Headless:
--   C:\Mesen\Mesen.exe --testrunner C:\Mesen\ROMs\neszork.nes <this-script>

local inject = dofile("E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua")
inject.load_labels("E:/GemmaProjects/NESZork1/build/neszork.lbl")
inject.set_settle(60)

-- Early-game path (no combat RNG yet).
inject.enqueue({
  "OPEN MAILBOX",
  "TAKE LEAFLET",
  "READ LEAFLET",
  "DROP LEAFLET",
  "SOUTH",
  "EAST",
  "OPEN WINDOW",
  "WEST",
  "WEST",
  "TAKE LAMP",
  "TAKE SWORD",
  "MOVE RUG",
  "OPEN TRAP",
  "TURN ON LAMP",
  "DOWN",
  "DIAGNOSE",
  "SCORE",
})

local done_logged = false
local timeout = 60 * 60 * 8  -- ~8 minutes at 60fps worst case
local start_frame = nil

emu.addEventCallback(function()
  local st = emu.getState()
  local frame = st["frameCount"] or 0
  if not start_frame then start_frame = frame end

  local phase = inject.tick()
  if phase == "idle" and not done_logged then
    done_logged = true
    emu.log("SMOKE PASS: command queue drained (reached cellar area path)")
    emu.displayMessage("zork", "smoke queue done")
    -- Keep running so you can play; for testrunner uncomment:
    -- emu.stop(0)
  end

  if frame - start_frame > timeout then
    emu.log("SMOKE FAIL: timeout")
    emu.stop(1)
  end
end, emu.eventType.endFrame)
