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