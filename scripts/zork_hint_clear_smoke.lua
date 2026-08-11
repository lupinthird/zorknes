-- After scrolling, open Invisiclues and check the screen is not still showing
-- the scrolled room description (scroll_y must be 0; no leftover story words).
local inject = dofile("E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua")
inject.load_labels("E:/GemmaProjects/NESZork1/build/neszork.lbl")
inject.set_settle(80)

local ppu = emu.memType.nesPpuDebug
local f = assert(io.open("E:/GemmaProjects/NESZork1/build/hint_clear_smoke.txt", "w"))
local function report(m) f:write(m.."\n"); f:flush(); emu.log(m) end
report("start")

local function row_text(row)
  local t = {}
  for col = 0, 31 do
    local tile = emu.read(0x2000 + row * 32 + col, ppu)
    t[#t + 1] = (tile >= 32 and tile < 127) and string.char(tile) or " "
  end
  return table.concat(t)
end

inject.enqueue({
  "OPEN MAILBOX", "TAKE LEAFLET", "READ LEAFLET", "LOOK", "LOOK",
  "HINT", "HINT",
})

local start, done, saw_hint_ui = nil, false, false
emu.addEventCallback(function()
  if done then return end
  local fr = (emu.getState()["frameCount"] or 0)
  if not start then start = fr end

  local wait = inject.rd("z_waiting_input")
  local split = inject.rd("win_split")
  local sy = inject.rd("scroll_y")

  -- Catch Invisiclues before tick() dismisses read_char.
  if wait == 2 and split >= 10 and not saw_hint_ui then
    saw_hint_ui = true
    for row = 0, 12 do
      report(string.format("r%02d [%s]", row, row_text(row)))
    end
    local junk = 0
    for row = 0, 28 do
      local line = row_text(row)
      if line:find("West of") or line:find("mailbox") or line:find("leaflet")
          or line:find("small mailbox") then
        junk = junk + 1
        report("junk "..row.." ["..line.."]")
      end
    end
    report(string.format("check y=%d split=%d junk=%d", sy, split, junk))
    done = true
    if sy ~= 0 then report("FAIL y"); f:close(); emu.stop(1); return end
    if junk > 0 then report("FAIL junk"); f:close(); emu.stop(1); return end
    report("HINT CLEAR PASS"); f:close(); emu.stop(0); return
  end

  inject.tick()

  if fr % 180 == 0 then
    report(string.format("t=%d wait=%d split=%d y=%d q=%d",
      fr - start, wait, split, sy, inject.queue_len()))
  end
  if fr - start > 60 * 90 then
    report("FAIL timeout")
    for row = 0, 8 do report(string.format("r%02d [%s]", row, row_text(row))) end
    f:close(); emu.stop(1)
  end
end, emu.eventType.endFrame)
