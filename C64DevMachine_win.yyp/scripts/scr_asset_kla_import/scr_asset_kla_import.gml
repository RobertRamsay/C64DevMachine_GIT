function scr_asset_kla_import(_asset) {
    var _path = get_open_filename("Supported Formats (*.kla;*.koa;*.png;*.jpg;*.jpeg)|*.kla;*.koa;*.png;*.jpg;*.jpeg|Koala Painter (*.kla;*.koa)|*.kla;*.koa|Image Files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. This is why ESC
    // only failed after SOME asset operations: scr_asset_sid_import already did
    // this, every other importer did not.
    io_clear();
    if (_path == "") exit;
    
    // Image conversion path (PNG / JPG / JPEG) — enter conversion mode instead of direct import
    var _ext_lower = string_lower(filename_ext(_path));
    show_debug_message("IMPORT: ext=" + _ext_lower + "  path=" + _path);
    if (_ext_lower == ".png" || _ext_lower == ".jpg" || _ext_lower == ".jpeg") {
        show_debug_message("IMAGE CONVERSION MODE ENTERED (" + _ext_lower + ")");
        
        // Wipe every piece of state left over from a PREVIOUSLY committed
        // import before starting a new one. Without this, stale undo/redo
        // buffers, mask arrays, and the old preview_surf all stick around —
        // and if anything (surface loss, alt-tab, etc.) ever triggers the
        // top-of-case "surface missing -> reload from disk" logic mid-import,
        // it reloads the OLD committed file over whatever the new conversion
        // was building, with mismatched mode/mask/undo state alongside it.
        // Starting completely clean means there's nothing stale left for
        // that (or anything else) to collide with.
        if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
            surface_free(_asset.meta.preview_surf);
        }
        _asset.meta.preview_surf = -1;
        
        if (variable_struct_exists(_asset.meta, "pixel_backup") && buffer_exists(_asset.meta.pixel_backup)) {
            buffer_delete(_asset.meta.pixel_backup);
        }
        _asset.meta.pixel_backup = -1;
        
        if (variable_struct_exists(_asset.meta, "undo_stack")) {
            for (var _ui = 0; _ui < array_length(_asset.meta.undo_stack); _ui++) {
                var _ue = _asset.meta.undo_stack[_ui];
                if (is_struct(_ue) && buffer_exists(_ue.buf)) buffer_delete(_ue.buf);
                else if (buffer_exists(_ue)) buffer_delete(_ue);
            }
        }
        _asset.meta.undo_stack = [];
        
        if (variable_struct_exists(_asset.meta, "redo_stack")) {
            for (var _ri = 0; _ri < array_length(_asset.meta.redo_stack); _ri++) {
                var _re = _asset.meta.redo_stack[_ri];
                if (is_struct(_re) && buffer_exists(_re.buf)) buffer_delete(_re.buf);
                else if (buffer_exists(_re)) buffer_delete(_re);
            }
        }
        _asset.meta.redo_stack = [];
        
        _asset.meta.bg_mask         = array_create(64000, 0);
        _asset.meta.clash_grid      = array_create(1000, false);
        _asset.meta.needs_mask_init = false;
        _asset.meta.hr_role_mask    = array_create(64000, 0);
        _asset.meta.hr_cell_fg_col  = array_create(1000, 0);
        _asset.meta.hr_cell_bg_col  = array_create(1000, 0);
        
        // Also clear stale size/scale so the fit-to-canvas defaults recompute
        // fresh for the NEW image rather than inheriting the old one's dims.
        // MUST fully remove the struct members (not set to undefined) — the
        // slider code and fit-scale math do arithmetic on these values before
        // they're ever repopulated, and undefined still passes
        // variable_struct_exists checks, so arithmetic on it crashes.
        // Removing them makes those checks correctly report "absent".
        if (variable_struct_exists(_asset.meta, "png_src_w")) variable_struct_remove(_asset.meta, "png_src_w");
        if (variable_struct_exists(_asset.meta, "png_src_h")) variable_struct_remove(_asset.meta, "png_src_h");
        if (variable_struct_exists(_asset.meta, "png_scale"))  variable_struct_remove(_asset.meta, "png_scale");
        
        _asset.meta.png_import_path    = _path;
        _asset.meta.png_import_mode    = true;
        _asset.meta.png_hue            = 0.0;
        _asset.meta.png_saturation     = 1.0;
        _asset.meta.png_contrast       = 1.0;
        _asset.meta.png_brightness     = 0.0;
        _asset.meta.png_dither         = "BAYER";
        _asset.meta.png_dither_amount  = 0.1;
        _asset.meta.png_conv_dirty     = true;  // force first conversion
        _asset.meta.png_source_surf    = -1;
        _asset.meta.is_editing         = true;
        exit;
    }
    
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    var _buf = buffer_load(_path);
    if (!buffer_exists(_buf)) {
        show_message("Invalid file — could not load.");
        exit;
    }
    // Byte size alone identifies the format — MC (10003) and HiRes (9002)
    // never collide — but a mismatch against the asset's CURRENT mode is a
    // downstream-affecting change (draw tools, save, clash-check all key off
    // bmp_mode), so confirm with the user rather than silently flipping it.
    var _loaded_size    = buffer_get_size(_buf);
    var _detected_hires = -1; // -1 = unrecognised, 0 = MC, 1 = HiRes
    if (_loaded_size == 10003) _detected_hires = 0;
    else if (_loaded_size == 9002) _detected_hires = 1;
    if (_detected_hires == -1) {
        show_message("Invalid file — expected 10003 bytes (Multicolour/Koala format) or 9002 bytes (HiRes format), got " + string(_loaded_size) + ".");
        buffer_delete(_buf);
        exit;
    }
    var _asset_is_hires = scr_asset_bmp_is_hires(_asset);
    var _file_is_hires  = (_detected_hires == 1);
    if (_file_is_hires != _asset_is_hires) {
        var _mode_msg = _file_is_hires
            ? "This file looks like a HiRes bitmap (9002 bytes), but this asset is set to Multicolour mode. Switch this asset to HiRes mode?"
            : "This file looks like a Multicolour bitmap (10003 bytes), but this asset is set to HiRes mode. Switch this asset to Multicolour mode?";
        if (!scr_show_question_bool(_mode_msg)) {
            buffer_delete(_buf);
            exit;
        }
        _asset.meta.bmp_mode = _file_is_hires ? "HIRES" : "MC";
    }
    _asset.buffer = _buf;
    _asset.file   = _path;
    // ---------------------------------------------------
// AUTO-NAME FROM IMPORTED FILE
// ---------------------------------------------------
if (_asset.file != "") {
    var _old_name = _asset.name;
    var _filename_only = filename_name(_asset.file);
    var _extension = filename_ext(_asset.file);
    var _clean_name = string_replace(_filename_only, _extension, "");

    // Only overwrite if it currently has a generic name (e.g., "BITMAP_2")
    if (string_pos(_asset.type, _old_name) == 1) { 
        _asset.name = _clean_name;
        
        // Sweep nodes to update any that might be holding the generic name
        with (obj_c64_node) {
            if (array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
                if (is_string(instructions[0][1]) && instructions[0][1] == _old_name) {
                    instructions[0][1] = _clean_name;
                }
            }
        }
    }
}
// ---------------------------------------------------
    
// Source file stays where the user loaded it from
    var _bmp_dir = filename_dir(_path);
    _asset.meta.source_file = _path;
    
    // Always make a working copy regardless of workspace state
    var _orig_ext  = filename_ext(_path);
    var _orig_base = string_copy(filename_name(_path), 1, string_length(filename_name(_path)) - string_length(_orig_ext));
    // Strip double _imported_ if somehow re-importing a copy
    if (string_pos("_imported_", _orig_base) > 0) {
        _orig_base = string_copy(_orig_base, 1, string_pos("_imported_", _orig_base) - 1);
    }
    var _work_path = _bmp_dir + "/" + _orig_base + "_imported_" + _orig_ext;
    if (!file_exists(_work_path)) file_copy(_asset.meta.source_file, _work_path);
    
    // Point asset at the working copy — original is never touched again
    _asset.file = _work_path;
    
    scr_asset_bmp_build_preview(_asset);
    scr_asset_kla_heal_palette(_asset);      // snap off-palette RGB to exact Pepto first
    _asset.meta.needs_mask_init = true;
    scr_asset_kla_process_surface(_asset, false, -1);
    global.undo_dirty = true;
    
    if (variable_struct_exists(_asset, "meta")) _asset.meta._mtime = md5_file(_asset.file);
    
}