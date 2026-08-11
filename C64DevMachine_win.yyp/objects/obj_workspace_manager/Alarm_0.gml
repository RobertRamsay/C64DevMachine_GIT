/// @desc Alarm 0: Relaunch VICE after the requested build output exists

if (!vice_launch_pending) {
    exit;
}

// The build path arms vice_launch_target only after the synchronous PRG/D64
// save has completed.  From this point on, the output file is the source of
// truth: post-build asset flags must not be allowed to suppress VICE forever.
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
    vice_launch_retry = 0;
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
    vice_launch_retry = 0;
    exit;
}

// Phase 0: the exact requested output exists.  Only now terminate any old
// VICE instance, then give Windows/macOS a short window to release the process.
if (vice_launch_phase == 0) {
    show_debug_message("VICE deferred launch: output ready: " + vice_launch_target);
    show_debug_message("VICE deferred launch: terminating old VICE.");
    scr_kill_vice();

    vice_launch_phase = 1;
    alarm[0] = max(1, vicedelay);
    exit;
}

// Phase 1: launch exactly once with the finished PRG/D64.  Do not gate this on
// trigger_build or asset_reload_in_progress; those can legitimately change as
// large MAP/METAMAP/H-scroll data settles after the completed build.
show_debug_message("VICE deferred launch: starting " + vice_launch_target);

var _vice_started = scr_launch_vice(global.vice_path_cache, vice_launch_target);
if (!_vice_started) {
    scr_show_message("VICE launch failed.\n\nBuild output:\n" + vice_launch_target);
}

vice_launch_pending = false;
vice_launch_phase = 0;
vice_launch_retry = 0;
