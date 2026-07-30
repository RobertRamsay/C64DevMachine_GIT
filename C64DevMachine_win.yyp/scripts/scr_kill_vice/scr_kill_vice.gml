/// @function scr_kill_vice()
/// @description Kills any running VICE x64sc process. Cross-platform.
///              Safe to call when no VICE is running. Releases any file
///              lock VICE holds on the previously emitted .prg/.d64.

function scr_kill_vice()
{
    if (os_type == os_macosx) {
        // ProcessExecute is synchronous - this is intentional so the kill
        // completes before we save the new .prg/.d64.
        ProcessExecute("killall -9 x64sc");
    } else {
        execute_shell_simple("taskkill", "/f /im x64sc.exe");
    }
}
