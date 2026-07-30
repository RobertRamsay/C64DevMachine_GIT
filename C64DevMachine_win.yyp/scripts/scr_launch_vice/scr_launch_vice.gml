/// @function scr_launch_vice(_vice_path, _file_path)
/// @description Launches VICE x64sc with the given .prg or .d64 file using
///              -autostart so it loads and runs immediately. Cross-platform.
///              Returns true on launch attempt, false if path resolution
///              failed.
/// @param {string} _vice_path  Absolute path to x64sc executable
/// @param {string} _file_path  Absolute path to .prg or .d64 to autoload

function scr_launch_vice(_vice_path, _file_path)
{
	show_debug_message("scr_launch_vice: path=" + _vice_path + " file=" + _file_path);
	
    if (_vice_path == "" || !file_exists(_vice_path)) {
        show_debug_message("scr_launch_vice: VICE path invalid: " + _vice_path);
        return false;
    }
    if (_file_path == "" || !file_exists(_file_path)) {
        show_debug_message("scr_launch_vice: target file missing: " + _file_path);
        return false;
    }

    var _args = "-autostart \"" + _file_path + "\"";

    show_debug_message("VICE LAUNCH: " + _vice_path);
    show_debug_message("VICE ARGS:   " + _args);

    if (os_type == os_macosx) {
        // Launch the inner Mach-O binary directly via ProcessExecuteAsync.
        // This is more reliable than `open -a` because:
        //   - It works whether _vice_path points to the .app or the inner
        //     binary (we resolved to the binary in scr_resolve_vice_path).
        //   - Arguments pass cleanly without `--args` quirks.
        //   - VICE runs detached so the IDE stays responsive.
        var _cmd = "\"" + _vice_path + "\" " + _args;
        ProcessExecuteAsync(_cmd);
    } else {
        // Windows path - execute_shell_simple takes exe + args separately
        execute_shell_simple(_vice_path, _args);
    }
    return true;
}