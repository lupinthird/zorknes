-- Double HINT, hold pad Down via setInput, verify cursor moves.
local inject = dofile("E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua")
local labels = inject.load_labels("E:/GemmaProjects/NESZork1/build/neszork.lbl")
inject.set_settle(55)
local mem = emu.memType.nesMemory
local ppu = emu.memType.nesPpuDebug
local out = assert(io.open("E:/GemmaProjects/NESZork1/build/hint_diag.txt", "w"))
local function log(msg) emu.log(msg); out:write(msg.."\n"); out:flush() end
local function rd(name) return emu.read(labels[name], mem) end
local function rows()
  local t={}
  for row=4,7 do
    local line={}
    for col=0,31 do
      local tile=emu.read(0x2000+row*32+col,ppu)
      line[#line+1]=(tile>=32 and tile<127) and string.char(tile) or " "
    end
    t[#t+1]=table.concat(line)
  end
  return table.concat(t,"|")
end

inject.enqueue({"HINT","HINT"})
local start_frame, phase, downs, cool = nil, "w", 0, 0

emu.addEventCallback(function()
  local frame = emu.getState()["frameCount"] or 0
  if not start_frame then start_frame = frame end
  inject.tick()
  local wait = rd("z_waiting_input")
  if phase == "w" and wait == 2 then
    log("start "..rows())
    phase = "d"
  elseif phase == "d" and wait == 2 and cool <= 0 and downs < 3 then
    inject.hold_pad({ down = true }, 4)
    downs = downs + 1
    cool = 20
    log("Down #"..downs.." edge will fire")
  elseif phase == "d" then
    if cool > 0 then cool = cool - 1 end
    if downs >= 3 and cool <= 0 then
      log("final "..rows())
      log(string.format("pad1=%02X edge=%02X", rd("pad1"), rd("pad1_pressed")))
      out:close()
      emu.stop(0)
    end
  end
  if frame - start_frame > 60 * 90 then log("TO"); out:close(); emu.stop(1) end
end, emu.eventType.endFrame)
