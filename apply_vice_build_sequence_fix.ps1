$ErrorActionPreference = "Stop"

$root = Get-Location
$create = Join-Path $root "C64DevMachine_win.yyp\objects\obj_workspace_manager\Create_0.gml"
$step   = Join-Path $root "C64DevMachine_win.yyp\objects\obj_workspace_manager\Step_0.gml"
$alarm  = Join-Path $root "C64DevMachine_win.yyp\objects\obj_workspace_manager\Alarm_0.gml"

foreach ($p in @($create,$step,$alarm)) {
    if (!(Test-Path $p)) { throw "Missing file: $p" }
}

function Read-Utf8([string]$p) {
    return [System.IO.File]::ReadAllText($p)
}
function Write-Utf8NoBom([string]$p,[string]$s) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($p,$s,$enc)
}
function Replace-Exactly([string]$text,[string]$old,[string]$new,[string]$label) {
    $count = ([regex]::Matches($text,[regex]::Escape($old))).Count
    if ($count -ne 1) { throw "$label: expected exactly 1 match, found $count" }
    return $text.Replace($old,$new)
}

# 1) Create_0.gml: state for deferred VICE launch
$t = Read-Utf8 $create
$old = "vicedelay=200 // >3 seconds"
$new = @"
vicedelay=30 // shutdown settle delay; build time is no longer part of VICE timing
vice_launch_phase = 0;          // 0=idle/waiting, 1=VICE killed and waiting to relaunch
vice_launch_pending = false;
vice_launch_target = "";
vice_launch_retry = 0;
vice_launch_retry_max = 600;    // safety timeout (~10s at 60fps)
"@.TrimEnd()
$t = Replace-Exactly $t $old $new "Create_0 VICE state"
Write-Utf8NoBom $create $t

# 2) Step_0.gml: remove pre-build kill
$t = Read-Utf8 $step
$old = @"
// -------------------------------------------------------------
// VICE pre-build kill (cross-platform)
// Releases any file lock VICE has on the previously emitted .prg/.d64.
// Actual launch happens later via alarm[0] -> scr_launch_vice().
// -------------------------------------------------------------
    if (!silent_build) {
        scr_kill_vice();
    }
"@
$new = @"
// -------------------------------------------------------------
// VICE launch sequencing
// Do NOT kill VICE before a potentially expensive build. Heavy MAP / METAMAP
// / H-scroll compilation can take a while, and an internal rebuild can follow.
// The old VICE is killed only after the final output exists, in Alarm 0.
// -------------------------------------------------------------
"@
# tolerate CRLF/LF by normalising in-memory
$tn = $t -replace "`r`n","`n"
$on = $old -replace "`r`n","`n"
$nn = $new -replace "`r`n","`n"
$tn = Replace-Exactly $tn $on $nn "Step_0 pre-build kill"

# Replace both launch-arm sites, but only exact alarm assignment occurrences.
$needle = "alarm[0] = vicedelay;"
$count = ([regex]::Matches($tn,[regex]::Escape($needle))).Count
if ($count -ne 2) { throw "Step_0 alarm arm: expected exactly 2 matches, found $count" }
$replacement = @"
vice_launch_target  = full_save_path;
                vice_launch_pending = true;
                vice_launch_phase   = 0;
                vice_launch_retry   = 0;
                alarm[0] = 1;
"@.TrimEnd()
$tn = $tn.Replace($needle,$replacement)
Write-Utf8NoBom $step ($tn -replace "`n","`r`n")

# 3) Alarm_0.gml: replace whole tiny event with deterministic two-phase launch
$alarmText = @'
/// @desc Alarm 0: Relaunch VICE only after final build/reload is quiet
if (!vice_launch_pending) exit;

// If another build/reload is queued, keep waiting.  This is the important
// guard for large MAP/METAMAP/H-scroll projects which can need follow-up work.
if (trigger_build || global.asset_reload_in_progress) {
    vice_launch_phase = 0;
    vice_launch_retry = 0;
    alarm[0] = 1;
    exit;
}

// The build path is synchronous, but still require the exact requested output
// to exist before touching VICE.
if (vice_launch_target == "" || !file_exists(vice_launch_target)) {
    vice_launch_retry += 1;
    if (vice_launch_retry < vice_launch_retry_max) {
        alarm[0] = 1;
        exit;
    }

    show_debug_message("VICE launch cancelled: output never appeared: " + vice_launch_target);
    scr_show_message("BUILD FAILED: output file was not created.\n\nVICE was not launched.\n\nExpected:\n" + vice_launch_target);
    vice_launch_pending = false;
    vice_launch_phase = 0;
    exit;
}

if (global.vice_path_cache == "" || !file_exists(global.vice_path_cache)) {
    scr_show_message("VICE not found.\n\nChecked:\n" + global.vice_path_cache
        + "\n\nInstall VICE, drop it in the working directory under /vice/,"
        + "\nor set an override path in c64devmachine.ini under [vice] path=...");
    vice_launch_pending = false;
    vice_launch_phase = 0;
    exit;
}

// Phase 0: the final output is present and the build queue is quiet.
// Kill the OLD VICE only now, then give the OS time to finish shutdown.
if (vice_launch_phase == 0) {
    scr_kill_vice();
    vice_launch_phase = 1;
    alarm[0] = vicedelay;
    exit;
}

// Something may have retriggered during the shutdown window.
if (trigger_build || global.asset_reload_in_progress) {
    vice_launch_phase = 0;
    alarm[0] = 1;
    exit;
}

show_debug_message("VICE launch target ready: " + vice_launch_target);
if (!scr_launch_vice(global.vice_path_cache, vice_launch_target)) {
    scr_show_message("VICE launch failed.\n\nBuild output:\n" + vice_launch_target);
}

vice_launch_pending = false;
vice_launch_phase = 0;
'@
Write-Utf8NoBom $alarm ($alarmText -replace "`n","`r`n")

Write-Host "VICE sequencing patch applied."
Write-Host "Review with: git diff -- C64DevMachine_win.yyp/objects/obj_workspace_manager"
