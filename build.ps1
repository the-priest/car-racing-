# Builds Velocity Heat for Windows and Linux on a Windows PC.
#   Double-click build.bat, or run:  powershell -ExecutionPolicy Bypass -File build.ps1 [all|windows|linux]
# Needs Godot 4.7. If it isn't found (set $env:GODOT to use your own), Godot and the
# export templates are downloaded once into .godot-tools\ (about 1 GB).
param([string]$Target = "all")
# "Continue": Godot prints progress on stderr, which "Stop" would treat as a failure.
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
Set-Location $PSScriptRoot

$Version = "4.7"
$Release = "$Version-stable"
$Url = "https://github.com/godotengine/godot/releases/download/$Release"
$Tools = Join-Path $PSScriptRoot ".godot-tools"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "Error: $m" -ForegroundColor Red; exit 1 }
function Test-Godot($exe) {
	if (-not $exe -or -not (Test-Path $exe)) { return $false }
	$v = & $exe --headless --version 2>$null | Select-Object -First 1
	return ($v -like "$Version.stable*")
}

# ---------------------------------------------------------------- Godot editor
$Godot = $env:GODOT
if ($Godot -and -not (Test-Godot $Godot)) { Die "GODOT=$Godot is not Godot $Version." }
if (-not $Godot) {
	$local = Join-Path $Tools "Godot_v${Release}_win64_console.exe"
	if (Test-Godot $local) { $Godot = $local }
}
if (-not $Godot) {
	New-Item -ItemType Directory -Force $Tools | Out-Null
	Say "Downloading Godot $Release..."
	$zip = Join-Path $Tools "godot.zip"
	Invoke-WebRequest "$Url/Godot_v${Release}_win64.exe.zip" -OutFile $zip -ErrorAction Stop
	Expand-Archive $zip -DestinationPath $Tools -Force -ErrorAction Stop
	Remove-Item $zip
	$Godot = Join-Path $Tools "Godot_v${Release}_win64_console.exe"
	if (-not (Test-Path $Godot)) { Die "Godot download looks incomplete." }
}
Say ("Using " + (& $Godot --headless --version 2>$null | Select-Object -First 1))

# ---------------------------------------------------------------- export templates
$TplDir = [System.IO.Path]::Combine($env:APPDATA, "Godot", "export_templates", "$Version.stable")
$need = @("windows_release_x86_64.exe", "linux_release.x86_64", "version.txt")
if (-not (Test-Path (Join-Path $TplDir "windows_release_x86_64.exe")) -or -not (Test-Path (Join-Path $TplDir "linux_release.x86_64"))) {
	New-Item -ItemType Directory -Force $Tools, $TplDir | Out-Null
	$tpz = Join-Path $Tools "templates.tpz"
	if (-not (Test-Path $tpz)) {
		Say "Downloading export templates (one time, ~1 GB)..."
		Invoke-WebRequest "$Url/Godot_v${Release}_export_templates.tpz" -OutFile "$tpz.part" -ErrorAction Stop
		Move-Item "$tpz.part" $tpz
	}
	Say "Installing the Windows and Linux templates..."
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$z = [System.IO.Compression.ZipFile]::OpenRead($tpz)
	try {
		foreach ($e in $z.Entries) {
			if ($need -contains $e.Name) {
				[System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $TplDir $e.Name), $true)
			}
		}
	} finally { $z.Dispose() }
	Remove-Item $tpz # the templates we need are installed now
}

# ---------------------------------------------------------------- build
# Stamp the build so the main menu shows which version you're running.
$rev = (& git rev-parse --short HEAD 2>$null); if (-not $rev) { $rev = "local" }
Set-Content "version.txt" ("$rev  " + (Get-Date -Format "yyyy-MM-dd"))
Say "Importing assets..."
& $Godot --headless --path . --import 2>&1 | Out-Null

function Export-One($preset, $folder, $bin) {
	$dir = Join-Path "build" $folder
	Say "Exporting $preset..."
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force $dir | Out-Null
	$log = Join-Path "build" "export-$folder.log"
	& $Godot --headless --path . --export-release $preset (Join-Path $dir $bin) *> $log
	if (-not (Test-Path (Join-Path $dir $bin))) { Get-Content $log -Tail 30; Die "$preset export failed (full log: $log)." }
	$radio = Join-Path $dir "Radio"
	New-Item -ItemType Directory -Force $radio | Out-Null
	Set-Content (Join-Path $radio "README.txt") @"
Put your own MP3 / OGG / WAV files in this folder.
In the game press Q (keyboard) or L3 (controller) while driving to turn the radio on or skip a song.
Hold the button to switch back to the game's soundtrack.
Name files "Artist - Title.mp3" (or tag them) so the game shows the right song name.
"@
	$zipOut = Join-Path "build" "VelocityHeat-$folder.zip"
	if (Test-Path $zipOut) { Remove-Item $zipOut }
	Compress-Archive -Path $dir -DestinationPath $zipOut
	Say "$preset build ready: $dir\$bin"
}

New-Item -ItemType Directory -Force "build" | Out-Null
switch ($Target) {
	"all" { Export-One "Windows" "windows" "VelocityHeat.exe"; Export-One "Linux" "linux" "VelocityHeat.x86_64" }
	"windows" { Export-One "Windows" "windows" "VelocityHeat.exe" }
	"linux" { Export-One "Linux" "linux" "VelocityHeat.x86_64" }
	default { Die "Unknown target '$Target' (use all, windows or linux)." }
}
Say ("Done. Run " + [System.IO.Path]::Combine("build", "windows", "VelocityHeat.exe"))
