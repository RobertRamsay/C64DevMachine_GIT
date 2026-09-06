/// @function scr_asset_vbmp_export(_asset, [_path])
/// @description Write one VECTOR_BITMAP asset to a shareable .vbm file.
///
/// A vector bitmap has no binary payload - asset.buffer is -1 and the picture
/// is a replayable command list - so the file IS the data, not a rendering of
/// it. That makes these the one asset type that can travel between projects
/// losslessly as plain JSON.
///
/// What travels is only the picture:
///   mode   - 0 HR / 1 MC, because the command coords mean different things
///   pages  - the per-page command lists and their four colour selectors
///
/// What deliberately does NOT travel:
///   fill_stack / stream_addr - these are memory-map decisions belonging to
///       the project doing the importing. Carrying them would let a shared
///       picture silently move someone else's flood-fill stack.
///   active_page / active_col / active_pat / tool / zoom - editor UI state.
///   preview_surf / bg_mask / undo stacks - rebuilt on load, never serialised.
///   address / name - the importing project decides where it lives.
///
/// @param {Struct} _asset  the VECTOR_BITMAP asset
/// @param {String} [_path] target file; omit to open a save dialog
function scr_asset_vbmp_export(_asset, _path = "") {

    if (_asset.type != "VECTOR_BITMAP")
    {
        scr_show_message("VBMP EXPORT: not a vector bitmap asset.");
        return false;
    }

    // The editor keeps the page it is working on in the top-level meta fields
    // and only writes it down into pages[] on a page switch, so flush first or
    // the visible page exports as whatever it looked like last switch. This is
    // the same call scr_save_workspace_as_path makes for the same reason.
    scr_vbmp_page_store(_asset);

    if (_path == "")
    {
        _path = get_save_filename("C64 Vector Bitmap (*.vbm)|*.vbm", _asset.name + ".vbm");
        // A native file dialog takes focus, so the key-up that ends the
        // keypress goes to the dialog and not to the game. Without this ESC
        // silently stops working afterwards.
        io_clear();
    }
    if (_path == "")
    {
        return false;
    }

    var _m = _asset.meta;

    var _mode = 1;
    if (variable_struct_exists(_m, "mode"))
    {
        _mode = real(_m.mode);
    }

    var _src_pages = [];
    if (variable_struct_exists(_m, "pages") && is_array(_m.pages))
    {
        _src_pages = _m.pages;
    }

    var _out_pages = [];
    for (var _pi = 0; _pi < array_length(_src_pages); _pi++)
    {
        var _pg = _src_pages[_pi];

        var _cmds = [];
        if (is_struct(_pg) && variable_struct_exists(_pg, "commands") && is_array(_pg.commands))
        {
            _cmds = _pg.commands;
        }

        var _bg = 0;
        var _c1 = 1;
        var _c2 = 2;
        var _c3 = 3;
        if (is_struct(_pg))
        {
            if (variable_struct_exists(_pg, "bg"))   { _bg = real(_pg.bg);   }
            if (variable_struct_exists(_pg, "col1")) { _c1 = real(_pg.col1); }
            if (variable_struct_exists(_pg, "col2")) { _c2 = real(_pg.col2); }
            if (variable_struct_exists(_pg, "col3")) { _c3 = real(_pg.col3); }
        }

        array_push(_out_pages, {
            commands : _cmds,
            bg       : _bg,
            col1     : _c1,
            col2     : _c2,
            col3     : _c3
        });
    }

    if (array_length(_out_pages) == 0)
    {
        scr_show_message("VBMP EXPORT: nothing to export - this asset has no pages.");
        return false;
    }

    // The version field is the whole point of doing this now rather than
    // later. The workspace loader still carries a migration for vector
    // bitmaps saved before pages[] existed, purely because that format
    // shipped without a version to test.
    var _root = {
        kind         : "C64DEVMACHINE_VECTOR_BITMAP",
        vbmp_version : 1,
        name         : _asset.name,
        mode         : _mode,
        pages        : _out_pages
    };

    var _f = file_text_open_write(_path);
    if (_f < 0)
    {
        scr_show_message("VBMP EXPORT: could not write " + filename_name(_path));
        return false;
    }
    file_text_write_string(_f, json_stringify(_root));
    file_text_close(_f);

    var _total = 0;
    for (var _ti = 0; _ti < array_length(_out_pages); _ti++)
    {
        _total += array_length(_out_pages[_ti].commands);
    }
    show_debug_message("VBMP EXPORT: " + _asset.name + " -> " + _path
        + "  " + string(array_length(_out_pages)) + " page(s), "
        + string(_total) + " primitives");
    return true;
}
