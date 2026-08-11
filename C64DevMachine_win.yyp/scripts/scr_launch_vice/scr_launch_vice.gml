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

    var _args = "";
    if (variable_global_exists("reu_last_image") &&
        global.reu_last_image != "" &&
        file_exists(global.reu_last_image)) {
        _args += "-reu -reusize 16384 -reuimage \"" + global.reu_last_image + "\" ";
        show_debug_message("VICE REU IMAGE: " + global.reu_last_image);
    }
    _args += "-autostart \"" + _file_path + "\"";

    show_debug_message("VICE LAUNCH: " + _vice_path);
    show_debug_message("VICE ARGS:   " + _args);

    if (os_type == os_macosx) {
        var _cmd = "\"" + _vice_path + "\" " + _args;
        show_debug_message("VICE MAC CMD: " + _cmd);
        ProcessExecuteAsync(_cmd);
    } else {
        // Windows: launch VICE directly. Do not route through cmd.exe or a
        // helper batch file, otherwise a console window can remain visible.
        execute_shell_simple(_vice_path, _args);
    }
    return true;
}
