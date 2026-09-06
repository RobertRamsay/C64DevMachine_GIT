/// @function scr_asset_vbmp_import(_asset, [_path])
/// @description Load a shared .vbm file into an existing VECTOR_BITMAP asset,
///              replacing its pages. Written by scr_asset_vbmp_export.
///
/// A .vbm is somebody else's file, so nothing in it is trusted. Every command
/// is rebuilt field by field against a per-op whitelist rather than being
/// adopted wholesale: unknown ops are dropped, unknown fields are ignored, and
/// every value is coerced with real() and clamped. That is not paranoia for
/// its own sake - MACRO_VECTOR_BMP's emitter reads _cmd.x0 and friends with no
/// existence check, so one command missing a field would throw during compile
/// rather than simply drawing wrong.
///
/// Ranges are the editor's hi-res space (x 0-319, y 0-199) even in MC mode;
/// the compiler narrows x further to a single byte and snaps to even columns.
/// Note that `col` means a colour selector on SETCOL and a character column on
/// the recolour ops, which is why validation is per-op and not per-field-name.
///
/// The asset's address, fill_stack, stream_addr and name are left alone - they
/// belong to this project, not to the file.
///
/// @param {Struct} _asset  the VECTOR_BITMAP asset to load into
/// @param {String} [_path] source file; omit to open a file dialog
function scr_asset_vbmp_import(_asset, _path = "") {

    if (_asset.type != "VECTOR_BITMAP")
    {
        scr_show_message("VBMP IMPORT: not a vector bitmap asset.");
        return false;
    }

    if (_path == "")
    {
        _path = get_open_filename("C64 Vector Bitmap (*.vbm)|*.vbm", "");
        // Native dialogs eat the key-up, which leaves ESC dead afterwards.
        io_clear();
    }
    if (_path == "")
    {
        return false;
    }
    if (!file_exists(_path))
    {
        scr_show_message("VBMP IMPORT: file not found.");
        return false;
    }

    // buffer_load + one buffer_text read, the same way scr_load_workspace_from_path
    // reads a project. The file_text_* family is line-based and caps a single
    // read, so on json_stringify output - which is one enormous line with no
    // newlines in it at all - a read-until-eof loop never reaches the end and
    // spins forever. That is what made IMPORT appear to hang rather than fail.
    var _jbuf = buffer_load(_path);
    if (_jbuf == -1)
    {
        scr_show_message("VBMP IMPORT: could not open " + filename_name(_path));
        return false;
    }
    var _raw = "";
    if (buffer_get_size(_jbuf) > 0)
    {
        // buffer_read(buffer_text) runs to the terminator, so guarantee one:
        // a .vbm written by the exporter has no trailing null of its own.
        var _jsz = buffer_get_size(_jbuf);
        var _tbuf = buffer_create(_jsz + 1, buffer_fixed, 1);
        buffer_copy(_jbuf, 0, _jsz, _tbuf, 0);
        buffer_poke(_tbuf, _jsz, buffer_u8, 0);
        buffer_seek(_tbuf, buffer_seek_start, 0);
        _raw = buffer_read(_tbuf, buffer_text);
        buffer_delete(_tbuf);
    }
    buffer_delete(_jbuf);

    // json_parse throws on malformed input, and a shared file is exactly where
    // malformed input comes from.
    var _root = undefined;
    try
    {
        _root = json_parse(_raw);
    }
    catch (_e)
    {
        scr_show_message("VBMP IMPORT: " + filename_name(_path) + " is not valid JSON.");
        return false;
    }

    if (!is_struct(_root)
     || !variable_struct_exists(_root, "kind")
     || string(_root.kind) != "C64DEVMACHINE_VECTOR_BITMAP")
    {
        scr_show_message("VBMP IMPORT: not a C64 Dev Machine vector bitmap file.");
        return false;
    }

    var _ver = 0;
    if (variable_struct_exists(_root, "vbmp_version"))
    {
        _ver = real(_root.vbmp_version);
    }
    if (_ver > 1)
    {
        scr_show_message("VBMP IMPORT: file is version " + string(_ver)
            + ", this build understands version 1. Update C64 Dev Machine.");
        return false;
    }

    if (!variable_struct_exists(_root, "pages") || !is_array(_root.pages) || array_length(_root.pages) == 0)
    {
        scr_show_message("VBMP IMPORT: file contains no pages.");
        return false;
    }

    var _mode = 1;
    if (variable_struct_exists(_root, "mode"))
    {
        _mode = clamp(floor(real(_root.mode)), 0, 1);
    }

    var _dropped   = 0;
    var _new_pages = [];

    for (var _pi = 0; _pi < array_length(_root.pages); _pi++)
    {
        var _src = _root.pages[_pi];
        if (!is_struct(_src))
        {
            _dropped++;
            continue;
        }

        var _bg = 0;
        var _c1 = 1;
        var _c2 = 2;
        var _c3 = 3;
        if (variable_struct_exists(_src, "bg"))   { _bg = clamp(floor(real(_src.bg)),   0, 15); }
        if (variable_struct_exists(_src, "col1")) { _c1 = clamp(floor(real(_src.col1)), 0, 15); }
        if (variable_struct_exists(_src, "col2")) { _c2 = clamp(floor(real(_src.col2)), 0, 15); }
        if (variable_struct_exists(_src, "col3")) { _c3 = clamp(floor(real(_src.col3)), 0, 15); }

        var _src_cmds = [];
        if (variable_struct_exists(_src, "commands") && is_array(_src.commands))
        {
            _src_cmds = _src.commands;
        }

        var _cmds = [];
        for (var _ci = 0; _ci < array_length(_src_cmds); _ci++)
        {
            var _c = _src_cmds[_ci];
            if (!is_struct(_c) || !variable_struct_exists(_c, "op"))
            {
                _dropped++;
                continue;
            }

            var _op    = string(_c.op);
            var _clean = scr_vbmp_sanitise_cmd(_c, _op);
            if (_clean == undefined)
            {
                _dropped++;
                continue;
            }
            array_push(_cmds, _clean);
        }

        array_push(_new_pages, {
            commands : _cmds,
            bg       : _bg,
            col1     : _c1,
            col2     : _c2,
            col3     : _c3
        });
    }

    if (array_length(_new_pages) == 0)
    {
        scr_show_message("VBMP IMPORT: every page in the file was unreadable.");
        return false;
    }

    // ── Commit ────────────────────────────────────────────────────────────
    var _m = _asset.meta;

    _m.mode        = _mode;
    _m.pages       = _new_pages;
    _m.active_page = 0;

    // Volatile editor state must not survive a content swap: the undo stacks
    // describe commands that no longer exist, and the preview surface holds
    // the old picture. This mirrors what scr_load_workspace_from_path rebuilds.
    _m.vbmp_undo_stack = [];
    _m.vbmp_redo_stack = [];
    if (variable_struct_exists(_m, "preview_surf") && surface_exists(_m.preview_surf))
    {
        surface_free(_m.preview_surf);
    }
    _m.preview_surf  = -1;
    _m.draw_x1       = -1;
    _m.draw_y1       = -1;
    _m.bg_mask       = array_create(64000, 0);
    _m.dither_mode   = "NONE";
    _m.dither_invert = false;
    _m.brush_size    = 0;
    _m.vbmp_dirty    = true;

    // Pull page 0 up into the top-level editor fields the same way a page
    // switch does, so the editor opens on the imported picture.
    scr_vbmp_page_load(_asset, 0);

    global.autosave_dirty = true;
    global.undo_dirty     = true;

    var _total = 0;
    for (var _ti = 0; _ti < array_length(_new_pages); _ti++)
    {
        _total += array_length(_new_pages[_ti].commands);
    }
    show_debug_message("VBMP IMPORT: " + filename_name(_path) + " -> " + _asset.name
        + "  " + string(array_length(_new_pages)) + " page(s), "
        + string(_total) + " primitives, " + string(_dropped) + " dropped");

    if (_dropped > 0)
    {
        scr_show_message("VBMP IMPORT: loaded " + string(_total) + " primitives. "
            + string(_dropped) + " unreadable entries were skipped.");
    }
    return true;
}

/// @function scr_vbmp_sanitise_cmd(_c, _op)
/// @description Rebuild one command struct from a whitelist of fields for its
///              op, coercing and clamping every value. Returns undefined if
///              the op is not one this build can draw and compile.
///
/// setpat, polyline and polyfill exist in the editor's replay but are not
/// emitted by MACRO_VECTOR_BMP, so they are carried through unchanged in shape
/// but still range-checked - a file using them will preview correctly and
/// simply contribute nothing to the byte stream, which is the existing
/// behaviour for locally drawn ones.
///
/// @param {Struct} _c   the untrusted command
/// @param {String} _op  its op string
/// @return {Struct|Undefined}
function scr_vbmp_sanitise_cmd(_c, _op) {

    var _out = { op : _op };

    switch (_op)
    {
        case "setcol":
            _out.col = scr_vbmp_num(_c, "col", 1, 0, 3);
        break;

        case "setpat":
            _out.pat = scr_vbmp_num(_c, "pat", 0, 0, 255);
        break;

        case "plot":
            _out.x = scr_vbmp_num(_c, "x", 0, 0, 319);
            _out.y = scr_vbmp_num(_c, "y", 0, 0, 199);
        break;

        case "line":
        case "rect":
        case "rectfill":
            _out.x0 = scr_vbmp_num(_c, "x0", 0, 0, 319);
            _out.y0 = scr_vbmp_num(_c, "y0", 0, 0, 199);
            _out.x1 = scr_vbmp_num(_c, "x1", 0, 0, 319);
            _out.y1 = scr_vbmp_num(_c, "y1", 0, 0, 199);
        break;

        case "ellipse":
        case "ellipsefill":
            _out.cx = scr_vbmp_num(_c, "cx", 0, 0, 319);
            _out.cy = scr_vbmp_num(_c, "cy", 0, 0, 199);
            // rx is in MC units - the replay reconstructs a bounding box of
            // rx*2 hi-res pixels either side of cx.
            _out.rx = scr_vbmp_num(_c, "rx", 1, 0, 160);
            _out.ry = scr_vbmp_num(_c, "ry", 1, 0, 199);
        break;

        case "fill":
            _out.x       = scr_vbmp_num(_c, "x",       0, 0, 319);
            _out.y       = scr_vbmp_num(_c, "y",       0, 0, 199);
            _out.pattern = scr_vbmp_num(_c, "pattern", 0, 0, 255);
            _out.colb    = scr_vbmp_num(_c, "colb",    0, 0, 3);
        break;

        case "copyregion":
            _out.sc = scr_vbmp_num(_c, "sc", 0, 0, 39);
            _out.sr = scr_vbmp_num(_c, "sr", 0, 0, 24);
            _out.dc = scr_vbmp_num(_c, "dc", 0, 0, 39);
            _out.dr = scr_vbmp_num(_c, "dr", 0, 0, 24);
            _out.w  = scr_vbmp_num(_c, "w",  1, 1, 40);
            _out.h  = scr_vbmp_num(_c, "h",  1, 1, 25);
        break;

        case "recolor_sram":
        case "recolor_cram":
            // Here `col` is a character column, not a colour selector.
            _out.col = scr_vbmp_num(_c, "col", 0, 0, 39);
            _out.row = scr_vbmp_num(_c, "row", 0, 0, 24);
            _out.w   = scr_vbmp_num(_c, "w",   1, 1, 40);
            _out.h   = scr_vbmp_num(_c, "h",   1, 1, 25);
            _out.c1  = scr_vbmp_num(_c, "c1",  0, 0, 15);
            _out.c2  = scr_vbmp_num(_c, "c2",  0, 0, 15);
            _out.c3  = scr_vbmp_num(_c, "c3",  0, 0, 15);
        break;

        case "polyline":
        case "polyfill":
            var _pts = [];
            if (variable_struct_exists(_c, "pts") && is_array(_c.pts))
            {
                for (var _pi = 0; _pi < array_length(_c.pts); _pi++)
                {
                    var _p = _c.pts[_pi];
                    if (!is_array(_p) || array_length(_p) < 2)
                    {
                        continue;
                    }
                    if (!is_real(_p[0]) || !is_real(_p[1]))
                    {
                        continue;
                    }
                    array_push(_pts, [ clamp(floor(_p[0]), 0, 319),
                                       clamp(floor(_p[1]), 0, 199) ]);
                }
            }
            if (array_length(_pts) < 2)
            {
                return undefined;
            }
            _out.pts = _pts;
        break;

        default:
            return undefined;
    }

    return _out;
}

/// @function scr_vbmp_num(_c, _field, _default, _lo, _hi)
/// @description Read one numeric field off an untrusted command struct.
///              Missing, non-numeric and out-of-range all resolve to something
///              safe rather than reaching the emitter.
function scr_vbmp_num(_c, _field, _default, _lo, _hi) {
    if (!variable_struct_exists(_c, _field))
    {
        return _default;
    }
    var _v = _c[$ _field];
    if (is_string(_v))
    {
        // JSON round-trips numerics as strings on some paths, but real() on a
        // string that is not a number throws rather than returning 0.
        try
        {
            _v = real(_v);
        }
        catch (_e)
        {
            return _default;
        }
    }
    if (!is_real(_v))
    {
        return _default;
    }
    return clamp(floor(_v), _lo, _hi);
}
