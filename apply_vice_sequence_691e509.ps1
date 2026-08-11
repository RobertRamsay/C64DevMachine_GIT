$ErrorActionPreference = "Stop"

$root   = Get-Location
$create = Join-Path $root "C64DevMachine_win.yyp\objects\obj_workspace_manager\Create_0.gml"
$step   = Join-Path $root "C64DevMachine_win.yyp\objects\obj_workspace_manager\Step_0.gml"
$alarm  = Join-Path $root "C64DevMachine_win.yyp\objects\obj_workspace_manager\Alarm_0.gml"

foreach ($p in @($create,$step,$alarm)) {
    if (!(Test-Path $p)) { throw "Missing file: $p" }
}

function ReadText([string]$p) {
    return [System.IO.File]::ReadAllText($p)
}
function WriteText([string]$p,[string]$s) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($p,$s,$enc)
}

# Backups once.
foreach ($p in @($create,$step,$alarm)) {
    $bak = "$p.vicefix.bak"
    if (!(Test-Path $bak)) { Copy-Item $p $bak }
}

# ------------------------------------------------------------
# 1) Create_0.gml: verify deferred-launch state exists.
# ------------------------------------------------------------
$c = ReadText $create
if ($c -notmatch 'vice_launch_pending\s*=\s*false;') {
    throw "Create_0.gml is missing vice_launch_pending state. Expected current HEAD 691e509."
}
Write-Host "Create_0.gml: deferred VICE state present."

# ------------------------------------------------------------
# 2) Step_0.gml
# ------------------------------------------------------------
$s = ReadText $step
$nl = "`n"
$s = $s -replace "`r`n","`n"

# Remove PRE-BUILD kill block, tolerant of indentation.
$killPattern = '(?ms)// -------------------------------------------------------------\s*\n\s*// VICE pre-build kill \(cross-platform\)\s*\n\s*// Releases any file lock VICE has on the previously emitted \.prg/\.d64\.\s*\n\s*// Actual launch happens later via alarm\[0\] -> scr_launch_vice\(\)\.\s*\n\s*// -------------------------------------------------------------\s*\n\s*if \(!silent_build\) \{\s*\n\s*scr_kill_vice\(\);\s*\n\s*\}\s*\n'
$killMatches = [regex]::Matches($s, $killPattern).Count
if ($killMatches -eq 1) {
    $replacement = @'
// -------------------------------------------------------------
// VICE launch sequencing
// Do NOT kill VICE before an expensive build. The old VICE instance is
// terminated only after the final PRG/D64 exists and the build queue is quiet.
// -------------------------------------------------------------

'@
    $s = [regex]::Replace($s, $killPattern, $replacement, 1)
    Write-Host "Step_0.gml: removed pre-build VICE kill."
} elseif ($killMatches -eq 0 -and $s -match 'VICE launch sequencing') {
    Write-Host "Step_0.gml: pre-build VICE kill already removed."
} else {
    throw "Step_0.gml: expected one pre-build kill block, found $killMatches"
}

# Replace D64 alarm arm.
$d64Old = @'
                alarm[0] = vicedelay;
'@
$d64New = @'
                vice_launch_target  = full_save_path;
                vice_launch_pending = true;
                vice_launch_phase   = 0;
                vice_launch_retry   = 0;
                alarm[0] = 1;
'@

# Replace PRG alarm arm. There are exactly two legacy alarm assignments in current HEAD.
$legacyCount = ([regex]::Matches($s, [regex]::Escape('alarm[0] = vicedelay;'))).Count
if ($legacyCount -eq 2) {
    $s = $s.Replace('alarm[0] = vicedelay;', @'
vice_launch_target  = full_save_path;
                    vice_launch_pending = true;
                    vice_launch_phase   = 0;
                    vice_launch_retry   = 0;
                    alarm[0] = 1;
'@.TrimEnd())
    Write-Host "Step_0.gml: converted both VICE launch arms to deferred launch."
} elseif ($legacyCount -eq 0 -and ([regex]::Matches($s, 'vice_launch_pending\s*=\s*true;')).Count -ge 2) {
    Write-Host "Step_0.gml: deferred launch arms already present."
} else {
    throw "Step_0.gml: expected 2 legacy VICE alarm arms, found $legacyCount"
}

WriteText $step ($s -replace "`n","`r`n")

# ------------------------------------------------------------
# 3) Alarm_0.gml: replace tiny event completely.
# ------------------------------------------------------------
$alarmText = @'
/// @desc Alarm 0: Relaunch VICE only after final build/reload is quiet

if (!vice_launch_pending) {
    exit;
}

// Large MAP/METAMAP/H-scroll projects can schedule follow-up processing.
// Do not touch VICE until the build queue and asset reload pipeline are quiet.
if (trigger_build || global.asset_reload_in_progress) {
    vice_launch_phase = 0;
    vice_launch_retry = 0;
    alarm[0] = 1;
    exit;
}

// The build path is synchronous, but require the exact output file to exist.
// If filesystem visibility is delayed, retry briefly instead of launching stale data.
if (vice_launch_target == "" || !file_exists(vice_launch_target)) {
    vice_launch_retry += 1;

    if (vice_launch_retry < vice_launch_retry_max) {
        alarm[0] = 1;
        exit;
    }

    show_debug_message("VICE launch cancelled: output never appeared: " + vice_launch_target);
    scr_show_message(
        "BUILD FAILED: output file was not created.\n\n"
        + "VICE was not launched.\n\nExpected:\n"
        + vice_launch_target
    );

    vice_launch_pending = false;
    vice_launch_phase = 0;
    exit;
}

if (global.vice_path_cache == "" || !file_exists(global.vice_path_cache)) {
    scr_show_message(
        "VICE not found.\n\nChecked:\n"
        + global.vice_path_cache
        + "\n\nInstall VICE, drop it in the working directory under /vice/,"
        + "\nor set an override path in c64devmachine.ini under [vice] path=..."
    );

    vice_launch_pending = false;
    vice_launch_phase = 0;
    exit;
}

// Phase 0:
// The final output exists and the build pipeline is quiet.
// Only NOW kill the old VICE process.
if (vice_launch_phase == 0) {
    show_debug_message("VICE deferred launch: output ready, terminating old VICE.");
    scr_kill_vice();

    vice_launch_phase = 1;
    alarm[0] = vicedelay;
    exit;
}

// Something may have retriggered while Windows was shutting VICE down.
if (trigger_build || global.asset_reload_in_progress) {
    show_debug_message("VICE deferred launch: build/reload retriggered, waiting again.");
    vice_launch_phase = 0;
    vice_launch_retry = 0;
    alarm[0] = 1;
    exit;
}

// Phase 1:
// Old VICE has had time to terminate. Launch exactly once with the finished file.
show_debug_message("VICE deferred launch: starting " + vice_launch_target);

if (!scr_launch_vice(global.vice_path_cache, vice_launch_target)) {
    scr_show_message("VICE launch failed.\n\nBuild output:\n" + vice_launch_target);
}

vice_launch_pending = false;
vice_launch_phase = 0;
vice_launch_retry = 0;
'@

WriteText $alarm ($alarmText -replace "`n","`r`n")
Write-Host "Alarm_0.gml: installed deferred two-phase VICE launch."

Write-Host ""
Write-Host "VICE sequencing fix applied against HEAD 691e509."
Write-Host "Review:"
Write-Host "  git diff -- C64DevMachine_win.yyp/objects/obj_workspace_manager"
