/// @function scr_fix_vice_permissions_mac()
/// @description On Mac only, ensures the bundled VICE binaries have the
///              executable bit set. GameMaker strips Unix permissions
///              when bundling included files. Idempotent - safe to call
///              every launch. Only runs the chmod once per install by
///              checking an INI flag.

function scr_fix_vice_permissions_mac()
{
    if (os_type != os_macosx) return;

    ini_open("c64devmachine.ini");
    var _already_fixed = ini_read_real("vice", "perms_fixed", 0);
    ini_close();
    if (_already_fixed == 1) return;

    var _bins = [
        program_directory + "vice/mac-arm64/x64sc.app/Contents/MacOS/x64sc",
        program_directory + "vice/mac-x86_64/x64sc.app/Contents/MacOS/x64sc"
    ];

    var _any_fixed = false;
    for (var _i = 0; _i < array_length(_bins); _i++) {
        var _b = _bins[_i];
        if (file_exists(_b)) {
            // chmod +x the binary. ProcessExecute is synchronous so we
            // wait for completion before moving on.
            ProcessExecute("chmod +x \"" + _b + "\"");
            // Also strip quarantine attr in case Gatekeeper flagged it
            ProcessExecute("xattr -dr com.apple.quarantine \"" + _b + "\"");
            show_debug_message("Fixed permissions on: " + _b);
            _any_fixed = true;
        }
    }

    if (_any_fixed) {
        ini_open("c64devmachine.ini");
        ini_write_real("vice", "perms_fixed", 1);
        ini_close();
    }
}