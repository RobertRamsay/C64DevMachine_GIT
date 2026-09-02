/// @function scr_crash_recovery_check()
/// @desc Once per launch: if the last session died, offer the emergency
///       save back.
///
/// The crash handler in obj_workspace_manager's Create event already wrote
/// a rescue file — but nothing ever told anyone it existed, so it sat in
/// the autosave folder and the session was lost anyway. This is the other
/// half of that feature.
///
/// [autosave] crash_path is written ONLY by the crash handler, never by a
/// routine autosave, so its presence means "the last run ended badly" with
/// no timestamp comparison needed. It is cleared whichever way the user
/// answers, so a declined recovery cannot ask again on every launch.
function scr_crash_recovery_check() {
    ini_open("c64devmachine.ini");
    var _path = ini_read_string("autosave", "crash_path", "");
    var _msg  = ini_read_string("autosave", "crash_msg",  "");
    ini_close();

    if (_path == "") {
        return;
    }

    // Clear first. If the recovery load itself crashes, the next launch
    // must not offer the same poisoned file again and again.
    ini_open("c64devmachine.ini");
    ini_write_string("autosave", "crash_path", "");
    ini_write_string("autosave", "crash_msg",  "");
    ini_close();

    if (!file_exists(_path)) {
        show_debug_message("CRASH RECOVERY: marker pointed at a missing file - " + _path);
        return;
    }

    var _q = "C64 Dev Machine closed unexpectedly last time.\n\n"
           + "An emergency save was written:\n"
           + filename_name(_path) + "\n\n";
    if (_msg != "") {
        _q += "Error: " + _msg + "\n\n";
    }
    _q += "Recover it now?";

    if (show_question(_q)) {
        scr_load_workspace_from_path(_path);
        show_debug_message("CRASH RECOVERY: loaded " + _path);
    } else {
        show_debug_message("CRASH RECOVERY: declined; file kept at " + _path);
    }
}
