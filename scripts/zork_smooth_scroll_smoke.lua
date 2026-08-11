local inject = dofile('E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua')
inject.load_labels('E:/GemmaProjects/NESZork1/build/neszork.lbl')
local out = 'E:/GemmaProjects/NESZork1/build/smooth_scroll_smoke.txt'
local f=io.open(out,'w'); f:write('start\n'); f:close()
local function report(m) local f=io.open(out,'a'); f:write(m..'\n'); f:close(); emu.log(m) end
inject.set_settle(200)
inject.enqueue({'OPEN MAILBOX','TAKE LEAFLET','READ LEAFLET','READ LEAFLET','LOOK','LOOK','DIAGNOSE','SCORE'})
local saw_busy, max_y, settled, start, done = false, 0, false, nil, false
emu.addEventCallback(function()
  if done then return end
  local st = emu.getState()
  local fr = st['frameCount'] or 0
  if not start then start = fr end
  local phase = inject.tick()
  local busy, sy = inject.rd('scroll_busy'), inject.rd('scroll_y')
  if busy ~= 0 then saw_busy = true end
  if sy > max_y then max_y = sy end
  -- Camera may stay at scroll_y after a lazy settle (no Y=0 compact).
  if saw_busy and busy == 0 and inject.rd('scroll_queue') == 0 and not settled then
    settled = true
    report(string.format('settle ok max_y=%d', max_y))
  end
  if phase == 'idle' and inject.queue_len() == 0 then
    done = true
    if not saw_busy then report('FAIL no busy'); emu.stop(1); return end
    if max_y < 8 then report('FAIL y='..max_y); emu.stop(1); return end
    if not settled then report('FAIL no settle'); emu.stop(1); return end
    report('SMOOTH PASS'); emu.stop(0); return
  end
  if fr - start > 60*60*3 then report('FAIL timeout'); emu.stop(1) end
end, emu.eventType.endFrame)
