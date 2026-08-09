-- Troll fight stats: attacks issued vs hits you took (from on-screen text).
-- Uses nametable scanning so we don't depend on WRAM banking.
--
-- IMPORTANT: lockstep scripted runs always hit RANDOM on the same frames, so the
-- PRNG sequence is identical unless we reseed from wall-clock before combat.

local inject = dofile("E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua")
local labels = inject.load_labels("E:/GemmaProjects/NESZork1/build/neszork.lbl")
inject.set_settle(55)

local ppu = emu.memType.nesPpuDebug
local cpu = emu.memType.nesMemory
local MAX_ATTACKS = 30
local fight_seed = nil

local function reseed_rng()
  local addr = labels["z_rng"]
  if not addr then
    emu.log("WARN: z_rng label missing — rebuild ROM; combat may be identical every run")
    return
  end
  -- Wall-clock entropy so successive Mesen Script Window runs differ.
  local t = os.time() or 0
  local c = math.floor((os.clock() or 0) * 1000000)
  local lo = (t + c) % 256
  local hi = math.floor(t / 256 + c / 257) % 256
  if lo == 0 and hi == 0 then
    lo = 1
  end
  emu.write(addr, lo, cpu)
  emu.write(addr + 1, hi, cpu)
  fight_seed = lo + hi * 256
  emu.log(string.format("reseeded z_rng=$%04X from wall clock (time=%d)", fight_seed, t))
end

local function read_screen()
  local t = {}
  -- Skip status rows 0–1; read the rest of the nametable as ASCII tiles.
  for row = 2, 29 do
    for col = 0, 31 do
      local tile = emu.read(0x2000 + row * 32 + col, ppu)
      if tile >= 32 and tile < 127 then
        t[#t + 1] = string.char(tile)
      else
        t[#t + 1] = " "
      end
    end
    t[#t + 1] = "\n"
  end
  return table.concat(t):upper()
end

-- Phrases that mean the troll landed a damaging blow on you.
local PLAYER_HIT_PATTERNS = {
  "LIGHT WOUND",
  "SERIOUS WOUND",
  "SEVERAL WOUND",
  "FATAL WOUND",
  "NEAR DEATH",
  "CRASHES AGAINST YOUR BODY",
  "STRIKES A GLANCING BLOW",
  "CRASHES INTO YOUR SKULL",
  "DROPS YOU TO YOUR KNEES",
  "CONKS YOU",
  "AXE LANDS",
  "AXE CUTS",
  "AXE SLICES",
  "KNICKS YOU",  -- some builds use this spelling
  "NICKS YOU",
  "HITS YOU",
  "WOUNDS YOU",
  "SLASHES YOU",
}

-- Phrases that mean the troll is dead / gone.
local TROLL_DEAD_PATTERNS = {
  "TROLL DIES",
  "BLACK FOG",
  "CARCASS HAS DISAPPEARED",
  "BREATHES HIS LAST",
  "CAN'T SEE ANY TROLL",
  "CAN'T SEE THE TROLL",
  "WHAT TROLL",
}

local function screen_has(screen, patterns)
  for _, pat in ipairs(patterns) do
    if screen:find(pat, 1, true) then
      return pat
    end
  end
  return nil
end

inject.enqueue({
  "OPEN MAILBOX",
  "TAKE LEAFLET",
  "SOUTH",
  "EAST",
  "OPEN WINDOW",
  "ENTER",
  "WEST",
  "TAKE ALL",
  "MOVE RUG",
  "OPEN TRAP DOOR",
  "TURN ON LAMP",
  "DOWN",
  "NORTH",
  "DIAGNOSE",  -- baseline health before fight
})

local phase = "setup"
local attacks = 0
local hits_taken = 0
local prev_screen = ""
local death_pat = nil
local start_frame = nil
local timeout = 60 * 60 * 15

local function note_new_hits(screen)
  local new_hits = 0
  for _, pat in ipairs(PLAYER_HIT_PATTERNS) do
    local now = screen:find(pat, 1, true)
    local was = prev_screen:find(pat, 1, true)
    if now and not was then
      new_hits = new_hits + 1
      emu.log("  player hit detected: " .. pat)
    end
  end
  hits_taken = hits_taken + new_hits
  prev_screen = screen
  return new_hits
end

local function finish(reason)
  phase = "post"
  emu.log("---- TROLL FIGHT SUMMARY ----")
  if fight_seed then
    emu.log(string.format("  fight_seed     : $%04X", fight_seed))
  end
  emu.log(string.format("  attacks_issued : %d", attacks))
  emu.log(string.format("  hits_taken     : %d  (distinct on-screen wound/blow phrases)", hits_taken))
  emu.log(string.format("  end_reason     : %s", reason))
  if death_pat then
    emu.log(string.format("  death_text     : %s", death_pat))
  end
  emu.log("  note: expect different attack/hit counts across runs after reseed")
  emu.log("-----------------------------")
  emu.displayMessage("zork", string.format("troll: %d swings, %d hits on you", attacks, hits_taken))
  inject.enqueue({ "DIAGNOSE", "SCORE" })
end

emu.addEventCallback(function()
  local st = emu.getState()
  local frame = st["frameCount"] or 0
  if not start_frame then start_frame = frame end

  local p = inject.tick()

  if phase == "setup" and p == "idle" then
    phase = "fight"
    reseed_rng()
    local screen = read_screen()
    note_new_hits(screen)  -- should be 0 if perfect health
    emu.log("troll phase start — beginning combat")
  end

  if phase == "fight" and p == "idle" then
    local screen = read_screen()
    note_new_hits(screen)

    death_pat = screen_has(screen, TROLL_DEAD_PATTERNS)
    if death_pat then
      finish("troll dead (" .. death_pat .. ")")
    elseif attacks >= MAX_ATTACKS then
      phase = "fail"
      emu.log("---- TROLL FIGHT SUMMARY ----")
      emu.log(string.format("  attacks_issued : %d", attacks))
      emu.log(string.format("  hits_taken     : %d", hits_taken))
      emu.log("  end_reason     : FAIL — no death text after max attacks")
      emu.log("-----------------------------")
      emu.displayMessage("zork", "troll fight failed")
    else
      attacks = attacks + 1
      inject.enqueue({ "KILL TROLL WITH SWORD" })
      emu.log(string.format("attack %d/%d (hits_taken so far=%d)", attacks, MAX_ATTACKS, hits_taken))
    end
  end

  if phase == "post" and p == "idle" then
    -- Final diagnose may add wound phrases; recount once.
    note_new_hits(read_screen())
    emu.log(string.format(
      "EARLY WIN-PATH PASS — killed in %d attack(s), took %d hit(s)",
      attacks, hits_taken))
    phase = "done"
  end

  if phase ~= "fail" and phase ~= "done" and frame - start_frame > timeout then
    emu.log("FAIL: timeout")
    phase = "fail"
  end
end, emu.eventType.endFrame)
