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
        // Launch the inner Mach-O binary directly via ProcessExecuteAsync.
        var _cmd = "\"" + _vice_path + "\" " + _args;
        show_debug_message("VICE MAC CMD: " + _cmd);
        ProcessExecuteAsync(_cmd);
    } else {
        // Windows: use a detached CMD launcher instead of launching x64sc.exe
        // directly from the GameMaker runner.  Besides being more robust, this
        // leaves a diagnostic trail outside the runner so we can tell whether
        // Windows actually creates x64sc.exe and whether it survives startup.
        var _vice_dir = filename_dir(_vice_path);
        var _diag_dir = "C:\\C64Temp";
        var _bat_path = _diag_dir + "\\c64dm_launch_vice.cmd";
        var _log_path = _diag_dir + "\\vice_launch_debug.txt";

        var _fh = file_text_open_write(_bat_path);
        if (_fh < 0) {
            show_debug_message("VICE DEBUG: could not create launcher: " + _bat_path);
            return false;
        }

        file_text_writeln(_fh, "@echo off");
        file_text_writeln(_fh, "setlocal");
        file_text_writeln(_fh, "echo ============================================== >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "echo C64DM VICE launch %DATE% %TIME% >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "echo EXE: " + _vice_path + " >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "echo FILE: " + _file_path + " >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "if exist \"" + _vice_path + "\" (echo EXE_EXISTS=YES >> \"" + _log_path + "\") else (echo EXE_EXISTS=NO >> \"" + _log_path + "\")");
        file_text_writeln(_fh, "if exist \"" + _file_path + "\" (echo FILE_EXISTS=YES >> \"" + _log_path + "\") else (echo FILE_EXISTS=NO >> \"" + _log_path + "\")");
        file_text_writeln(_fh, "cd /d \"" + _vice_dir + "\"");
        file_text_writeln(_fh, "echo CWD=%CD% >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "start \"\" /b \"" + _vice_path + "\" " + _args + " >> \"" + _log_path + "\" 2>&1");
        file_text_writeln(_fh, "echo START_ERRORLEVEL=%ERRORLEVEL% >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "timeout /t 2 /nobreak >nul");
        file_text_writeln(_fh, "echo TASKLIST_AFTER_2S: >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "tasklist /FI \"IMAGENAME eq x64sc.exe\" >> \"" + _log_path + "\" 2>&1");
        file_text_writeln(_fh, "echo. >> \"" + _log_path + "\"");
        file_text_writeln(_fh, "endlocal");
        file_text_close(_fh);

        var _cmd_args = "/d /c start \"\" /b \"" + _bat_path + "\"";
        show_debug_message("VICE WIN LAUNCHER: " + _bat_path);
        show_debug_message("VICE WIN LOG:      " + _log_path);
        show_debug_message("VICE WIN CMD:      cmd.exe " + _cmd_args);

        execute_shell_simple("cmd.exe", _cmd_args);
    }
    return true;
}
