# Build neszork.nes (Windows PowerShell)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
New-Item -ItemType Directory -Force -Path build | Out-Null

# Ensure story banks exist
if (-not (Test-Path "build/story_banks/story0.bin")) {
    python -c @"
from pathlib import Path
story=Path('story/zork1.z5').read_bytes()
bank=16384
out=Path('build/story_banks'); out.mkdir(parents=True, exist_ok=True)
n=(len(story)+bank-1)//bank
padded=story+bytes([0xFF])*(n*bank-len(story))
for i in range(n):
    (out/f'story{i}.bin').write_bytes(padded[i*bank:(i+1)*bank])
print('story banks', n)
"@
}

$ca65 = "C:\cc65\bin\ca65.exe"
$cl65 = "C:\cc65\bin\cl65.exe"
$srcs = @(
    "header","story","story_font","mmc1","palette","pads","sfx",
    "keyboard","zmem","ppu_text","zvm","zdecode","zops","ztoken","nmi","main"
)

foreach ($s in $srcs) {
    & $ca65 -g -I src -o "build\$s.o" "src\$s.s"
    if ($LASTEXITCODE -ne 0) { throw "ca65 failed: $s" }
}

$objs = $srcs | ForEach-Object { "build\$_.o" }
& $cl65 -t none -C cfg/sxrom.cfg -o build/neszork.nes -Ln build/neszork.lbl -vm -m build/neszork.map @objs
if ($LASTEXITCODE -ne 0) { throw "cl65 failed" }

Copy-Item build/neszork.nes C:\Mesen\ROMs\neszork.nes -Force
Write-Host "Built build/neszork.nes ($((Get-Item build/neszork.nes).Length) bytes)"
