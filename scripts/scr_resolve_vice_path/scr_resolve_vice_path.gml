/// @function scr_resolve_vice_path()
/// @description Resolves the absolute path to the VICE x64sc executable for
///              the current platform. Checks (in order):
///              1. User override stored in c64devmachine.ini [vice] path
///              2. Bundled copy under the IDE install location
///              3. Standard system install location for the OS
///              Returns "" if nothing is found.

function scr_resolve_vice_path()
{


    var _path = "";


    // 1. User override from INI - this lives in the writable
    //    working_directory regardless of platform
    ini_open("c64devmachine.ini");
    var _override = ini_read_string("vice", "path", "");
    ini_close();
    if (_override != "" && file_exists(_override)) {
        show_debug_message("VICE resolved via INI override: " + _override);
        return _override;
    }

    // 2. Bundled copy. GameMaker handles included files differently per
    //    platform, so the base directory differs:
    //      Windows: working_directory   (alongside the running .exe)
    //      Mac:     program_directory   (inside the read-only .app bundle;
    //                                    working_directory on Mac points to
    //                                    a user-writable sandbox location
    //                                    where bundled files do NOT live)
    if (os_type == os_macosx) {
        // Try arm64 first, then x86_64. On Apple Silicon both are valid
        // (x86_64 runs under Rosetta), but native arm64 is faster.
        var _bundled_arm = program_directory + "vice/mac-arm64/x64sc.app/Contents/MacOS/x64sc";
        if (file_exists(_bundled_arm)) {
            show_debug_message("VICE resolved bundled (arm64): " + _bundled_arm);
            return _bundled_arm;
        }
        var _bundled_x86 = program_directory + "vice/mac-x86_64/x64sc.app/Contents/MacOS/x64sc";
        if (file_exists(_bundled_x86)) {
            show_debug_message("VICE resolved bundled (x86_64): " + _bundled_x86);
            return _bundled_x86;
        }
    } else {
        _path = working_directory + "vice/win/bin/x64sc.exe";
        if (file_exists(_path)) {
            show_debug_message("VICE resolved bundled (win): " + _path);
            return _path;
        }
    }

    // 3. Standard system install locations as a last resort
    if (os_type == os_macosx) {
        var _candidates = [
            "/Applications/vice/x64sc.app/Contents/MacOS/x64sc",
            "/Applications/VICE/x64sc.app/Contents/MacOS/x64sc",
            "/Applications/x64sc.app/Contents/MacOS/x64sc",
            "/Applications/vice-arm64-gtk3-3.9/x64sc.app/Contents/MacOS/x64sc",
            "/Applications/vice-x86-64-gtk3-3.9/x64sc.app/Contents/MacOS/x64sc",
            "/Applications/vice-arm64-gtk3-3.8/x64sc.app/Contents/MacOS/x64sc",
            "/Applications/vice-x86-64-gtk3-3.8/x64sc.app/Contents/MacOS/x64sc"
        ];
        for (var _i = 0; _i < array_length(_candidates); _i++) {
            if (file_exists(_candidates[_i])) {
                show_debug_message("VICE resolved system install: " + _candidates[_i]);
                return _candidates[_i];
            }
        }
    } else {
        var _wcandidates = [
            "C:\\Program Files\\WinVICE\\x64sc.exe",
            "C:\\Program Files (x86)\\WinVICE\\x64sc.exe",
            "C:\\Program Files\\VICE\\x64sc.exe",
            "C:\\Program Files (x86)\\VICE\\x64sc.exe"
        ];
        for (var _i = 0; _i < array_length(_wcandidates); _i++) {
            if (file_exists(_wcandidates[_i])) {
                show_debug_message("VICE resolved system install: " + _wcandidates[_i]);
                return _wcandidates[_i];
            }
        }
    }

    show_debug_message("VICE NOT FOUND - resolver returned empty");
    return "";
}