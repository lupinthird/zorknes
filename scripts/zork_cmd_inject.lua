-- NES Zork I — inject a typed command when the Z-machine is waiting on aread.
-- Used by smoke/win Lua scripts. Parses build/neszork.lbl for symbol addresses.
--
-- Strategy: write uppercase ASCII into z_line_buf, set z_line_len, then pulse
-- key_ready + key_ascii=$0D so main.s takes the same Enter path as the FBK.

local M = {}

local mem = emu.memType.nesMemory
local labels = {}
local repo = nil

local function find_repo()
  -- Prefer cwd; fall back to common project path.
  local candidates = {
    "build/neszork.lbl",
    "../build/neszork.lbl",
    "E:/GemmaProjects/NESZork1/build/neszork.lbl",
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then
      f:close()
      return p
    end
  end
  return nil
end

function M.load_labels(lbl_path)
  lbl_path = lbl_path or find_repo()
  if not lbl_path then
    error("neszork.lbl not found — build the ROM first")
  end
  labels = {}
  for line in io.lines(lbl_path) do
    local addr, name = line:match("^al (%x+) %.(%S+)")
    if addr and name then
      labels[name] = tonumber(addr, 16)
    end
  end
  local need = {
    "z_waiting_input", "z_line_buf", "z_line_len",
    "key_ready", "key_ascii", "title_active",
  }
  for _, n in ipairs(need) do
    if not labels[n] then
      error("missing label " .. n .. " in " .. lbl_path)
    end
  end
  emu.log(string.format("zork_cmd_inject: loaded labels from %s", lbl_path))
  return labels
end

function M.addr(name)
  local a = labels[name]
  if not a then error("unknown label " .. tostring(name)) end
  return a
end

function M.rd(name)
  return emu.read(M.addr(name), mem)
end

function M.wr(name, val)
  emu.write(M.addr(name), val & 0xFF, mem)
end

function M.waiting()
  -- Line inject only while aread is active (not read_char / HINT).
  return M.rd("z_waiting_input") == 1
end

function M.waiting_char()
  return M.rd("z_waiting_input") == 2
end

function M.waiting_any()
  return M.rd("z_waiting_input") ~= 0
end

function M.on_title()
  return M.rd("title_active") ~= 0
end

function M.inject_char(ch)
  -- Deliver one ZSCII char to read_char (HINT). Prefer host_char when present.
  local ok, addr = pcall(function() return M.addr("host_char") end)
  if ok and addr then
    M.wr("host_char", type(ch) == "string" and string.byte(ch) or ch)
  else
    M.wr("key_ascii", type(ch) == "string" and string.byte(ch) or ch)
    M.wr("key_ready", 1)
  end
end

-- Hold Start for a few frames via inputPolled (title dismiss / pad submit).
local pad_hold = nil
local pad_frames = 0

function M.hold_pad(buttons, frames)
  pad_hold = buttons
  pad_frames = frames or 3
end

local function on_input_polled()
  if pad_hold and pad_frames > 0 then
    -- Mesen 2: setInput(inputTable, port [, subPort])
    emu.setInput(pad_hold, 0)
    pad_frames = pad_frames - 1
    if pad_frames <= 0 then
      pad_hold = nil
    end
  end
end

emu.addEventCallback(on_input_polled, emu.eventType.inputPolled)

function M.skip_title()
  -- Prefer Enter so title locks INPUT_MODE_KB; inject commits via key_ready.
  -- (Start would lock pad mode and block keyboard injection.)
  M.wr("key_ascii", 0x0D)
  M.wr("key_ready", 1)
end

-- Queue: list of command strings (uppercase preferred).
local queue = {}
local busy_until = 0
local settle_frames = 45  -- wait after commit for VM to print + re-enter aread

function M.enqueue(cmds)
  for _, c in ipairs(cmds) do
    queue[#queue + 1] = c
  end
end

function M.queue_len()
  return #queue
end

local function inject_now(cmd)
  cmd = cmd:upper():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #cmd > 64 then
    emu.log("inject: truncating long command")
    cmd = cmd:sub(1, 64)
  end
  local buf = M.addr("z_line_buf")
  for i = 0, 63 do
    emu.write(buf + i, 0, mem)
  end
  for i = 1, #cmd do
    emu.write(buf + i - 1, string.byte(cmd, i), mem)
  end
  M.wr("z_line_len", #cmd)
  M.wr("key_ascii", 0x0D)
  M.wr("key_ready", 1)
  emu.log(string.format("inject> %s  (len=%d)", cmd, #cmd))
end

-- Call once per endFrame from the test script.
function M.tick()
  local st = emu.getState()
  local frame = st["frameCount"] or 0

  if M.on_title() then
    if frame % 30 == 0 then
      M.skip_title()
    end
    return "title"
  end

  if frame < busy_until then
    return "busy"
  end

  -- [MORE] / HINT / any read_char: dismiss with Space so the queue can proceed.
  if M.waiting_char() then
    M.inject_char(0x20)
    busy_until = frame + 8
    return "more"
  end

  if #queue == 0 then
    return "idle"
  end

  if not M.waiting() then
    return "wait_prompt"
  end

  local cmd = table.remove(queue, 1)
  inject_now(cmd)
  busy_until = frame + settle_frames
  return "injected"
end

function M.set_settle(frames)
  settle_frames = frames
end

return M
