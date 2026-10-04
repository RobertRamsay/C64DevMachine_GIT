/// ====================================================================
/// EXOMIZER - BUILD TARGET "PRG EXO"
///
/// The PRG INJECT image (every LOAD_ORG asset baked in, loaders compiled
/// out) is crunched by Exomizer 2 into a self-extracting PRG:
///     exomizer sfx sys -q -o <name>_exo.prg <name>.prg
/// "sys" makes the decruncher jump to the address in the BASIC SYS line,
/// i.e. the INIT node. The decruncher banks all RAM in while it unpacks,
/// so the result loads with a normal KERNAL LOAD even when the image
/// covers $D000-$DFFF - which a plain PRG never can.
///
/// Exomizer (c) Magnus Lind, free software (see exomizer_license.txt),
/// shipped in datafiles/tools/exomizer/win/. Windows only for now.
/// ====================================================================

/// Starts the cruncher. Returns false (and the caller runs the plain PRG)
/// when Exomizer is not available.
function scr_exo_crunch_start(_prg_path, _to_c64u) {
    if (os_type != os_windows) {
        scr_show_message("PRG EXO: Exomizer is Windows-only for now - running the uncrunched PRG.");
        return false;
    }
    var _exe = working_directory + "tools/exomizer/win/exomizer.exe";
    if (!file_exists(_exe)) {
        scr_show_message("PRG EXO: exomizer.exe not found in tools/exomizer/win - running the uncrunched PRG.");
        return false;
    }
    var _out = filename_change_ext(_prg_path, "") + "_exo.prg";
    if (file_exists(_out)) {
        file_delete(_out);
    }
    var _args = "sfx sys -q -o \"" + _out + "\" \"" + _prg_path + "\"";
    show_debug_message("EXO: " + _exe + " " + _args);
    execute_shell_simple(_exe, _args);

    with (obj_workspace_manager) {
        exo_pending   = true;
        exo_out_path  = _out;
        exo_timeout   = 60 * 30;    // 30 s - a full 64K image takes a few
        exo_last_size = -1;
        exo_to_c64u   = _to_c64u;
    }
    return true;
}

/// Called every Step while a crunch is running (obj_workspace_manager).
function scr_exo_crunch_poll() {
    exo_timeout--;
    if (exo_timeout <= 0) {
        exo_pending = false;
        scr_show_message("PRG EXO: Exomizer did not produce " + filename_name(exo_out_path) + " - check the debug log.");
        return;
    }
    if (!file_exists(exo_out_path)) return;

    // Exomizer writes the file in one go at the end, but make sure the
    // size has settled across two polls before handing it to VICE.
    var _f = file_bin_open(exo_out_path, 0);
    if (_f < 0) return;
    var _sz = file_bin_size(_f);
    file_bin_close(_f);
    if (_sz <= 2 || _sz != exo_last_size) {
        exo_last_size = _sz;
        return;
    }

    exo_pending = false;
    var _blocks = ceil(_sz / 254);
    show_debug_message("EXO: crunched to " + string(_sz) + " bytes (" + string(_blocks) + " blocks) -> " + exo_out_path);
    global.exo_last_blocks = _blocks;

    if (exo_to_c64u) {
        exo_to_c64u = false;
        scr_c64u_reu_begin("PRG", exo_out_path, "");
        return;
    }
    global.vice_path_cache = scr_resolve_vice_path();
    if (global.vice_path_cache == "") {
        show_debug_message("VICE not found - check installation or set override path.");
        return;
    }
    vice_launch_target  = exo_out_path;
    vice_launch_pending = true;
    vice_launch_phase   = 0;
    vice_launch_retry   = 0;
    alarm[0] = 1;
}
