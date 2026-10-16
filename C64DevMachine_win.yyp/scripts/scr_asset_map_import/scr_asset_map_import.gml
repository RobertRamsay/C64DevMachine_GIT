/// @desc Fill in MAP_DATA meta keys added after the original format, so maps
///       built by importers (or older code) never hit an unset variable.
///       Values match scr_asset_default_address / scr_load_workspace_from_path.
function scr_map_meta_defaults(_m) {
    if (!variable_struct_exists(_m, "raw_chars"))          _m.raw_chars          = 0;
    if (!variable_struct_exists(_m, "room_w"))             _m.room_w             = 40;
    if (!variable_struct_exists(_m, "room_h"))             _m.room_h             = 25;
    if (!variable_struct_exists(_m, "room_count"))         _m.room_count         = 0;
    if (!variable_struct_exists(_m, "stream_flag_colour")) _m.stream_flag_colour = -1;
    if (!variable_struct_exists(_m, "room_view"))          _m.room_view          = [];
    if (!variable_struct_exists(_m, "view_y2"))            _m.view_y2            = false;
    if (!variable_struct_exists(_m, "erase_char"))         _m.erase_char         = 0;
}

/// @desc Import a binary map file into a MAP_DATA asset
/// @param {Struct} _asset   The asset struct from obj_asset_manager.asset_list
function scr_asset_map_import(_asset) {

    var _path = get_open_filename("Binary Map|*.bin", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. This is why ESC
    // only failed after SOME asset operations: scr_asset_sid_import already did
    // this, every other importer did not.
    io_clear();
    if (_path == "") exit;

    var _buf = buffer_load(_path);
    if (!buffer_exists(_buf)) {
        scr_show_message("MAP IMPORT: Failed to load file.");
        exit;
    }

    var _sz = buffer_get_size(_buf);
    if (_sz < 1) {
        buffer_delete(_buf);
        scr_show_message("MAP IMPORT: File is empty.");
        exit;
    }

    buffer_delete(_buf);
    scr_prompt_text("Map dimensions (" + string(_sz) + " bytes).\nEnter width,height (e.g. 40,25 or 40x25):", "40,25", scr_asset_map_import_finish, {asset:_asset,path:_path});
}

function scr_asset_map_import_finish(_input, _context) {
    if (_input == "") return;
    var _asset = _context.asset;
    if (!instance_exists(obj_asset_manager) || ds_list_find_index(obj_asset_manager.asset_list,_asset) < 0) return;
    var _buf = buffer_load(_context.path);
    if (!buffer_exists(_buf)) { scr_show_message("MAP IMPORT: Failed to load file."); return; }
    var _sz = buffer_get_size(_buf);
    var _dims = scr_prompt_dimensions(_input,40,25);
    var _w = clamp(_dims.w,1,160);
    var _h = clamp(_dims.h,1,160);
    // Validate file is large enough for the char grid
    var _map_sz = _w * _h;
    if (_map_sz > _sz) {
        scr_show_message(L("MAP IMPORT: File too small for ")
            + string(_w) + "x" + string(_h) + L(" map.\n")
            + L("Expected ") + string(_map_sz) + L(" bytes, got ") + string(_sz));
        buffer_delete(_buf);
        exit;
    }

    // ----------------------------------------------------------------
    // BUILD CHAR GRID from raw file (bytes 0 .. map_sz-1)
    // ----------------------------------------------------------------
    var _char_grid = array_create(_map_sz, 0);
    for (var _i = 0; _i < _map_sz; _i++) {
        _char_grid[_i] = buffer_peek(_buf, _i, buffer_u8);
    }
    buffer_delete(_buf);

    // ----------------------------------------------------------------
    // BUILD COLOUR GRID
    // Preserve existing colour work if the dimensions are compatible,
    // otherwise default everything to colour 1 (white).
    // ----------------------------------------------------------------
    var _colour_grid = array_create(_map_sz, 1);
    if (variable_struct_exists(_asset, "meta") &&
        variable_struct_exists(_asset.meta, "colour_grid") &&
        variable_struct_exists(_asset.meta, "map_w") &&
        variable_struct_exists(_asset.meta, "map_h")) {
        var _old_w  = _asset.meta.map_w;
        var _old_h  = _asset.meta.map_h;
        // Row stride is the physical grid width, which can exceed map_w
        // after the map has been shrunk in the editor.
        var _old_gw = variable_struct_exists(_asset.meta, "grid_w") ? _asset.meta.grid_w : _old_w;
        var _old_cg = _asset.meta.colour_grid;
        var _copy_w = min(_old_w, _w);
        var _copy_h = min(_old_h, _h);
        for (var _row = 0; _row < _copy_h; _row++) {
            for (var _col = 0; _col < _copy_w; _col++) {
                var _oi = _row * _old_gw + _col;
                if (_oi < array_length(_old_cg)) _colour_grid[_row * _w + _col] = _old_cg[_oi];
            }
        }
    }

    // ----------------------------------------------------------------
    // STORE METADATA FIRST so scr_asset_map_flush can read it
    // ----------------------------------------------------------------
    // Preserve chr_asset if one was already assigned
    var _chr_asset = "";
    if (variable_struct_exists(_asset, "meta") &&
        variable_struct_exists(_asset.meta, "chr_asset") &&
        _asset.meta.chr_asset != "") {
        _chr_asset = _asset.meta.chr_asset;
    }

    _asset.file    = _path;
    _asset.address = variable_struct_exists(_asset, "address") ? _asset.address : 0x8000;
// Physical grid is always the max ever loaded — allocate full _w x _h
    var _grid_sz     = _w * _h;
    var _full_char   = array_create(_grid_sz, 0);
    var _full_colour = array_create(_grid_sz, 1);
    // Copy imported data into physical grid
    array_copy(_full_char,   0, _char_grid,   0, _grid_sz);
    array_copy(_full_colour, 0, _colour_grid, 0, _grid_sz);

    if (variable_struct_exists(_asset, "meta") && is_struct(_asset.meta)
        && variable_struct_exists(_asset.meta, "char_grid")) {
        // Re-import onto an existing map: replace only the grids and size.
        // Export mode, rooms, room view, object layer, tile colours, MC
        // colours and the rest of the map's settings stay as they were.
        var _em = _asset.meta;
        _em.map_w          = _w;
        _em.map_h          = _h;
        _em.grid_w         = _w;
        _em.grid_h         = _h;
        _em.char_grid      = _full_char;
        _em.colour_grid    = _full_colour;
        _em.chr_asset      = _chr_asset;
        _em.override_grid  = array_create(_grid_sz, 0);
        // Selection / stamp / undo are indexed by grid position - stale now.
        _em.sel_grid       = array_create(_grid_sz, 0);
        _em.stamp_data     = [];
        _em.stamp_active   = false;
        _em.map_undo_stack = [];
        _em.map_redo_stack = [];
        _em.scroll_x       = 0;
        _em.scroll_y       = 0;
    } else _asset.meta    = {
        map_w             : _w,
        map_h             : _h,
        grid_w            : _w,
        grid_h            : _h,
        char_grid         : _full_char,
        colour_grid       : _full_colour,
        chr_asset         : _chr_asset,
		scroll_x          : 0,
        scroll_y          : 0,
        zoom              : 2,
        active_char       : 0,
        active_colour     : 1,
        tool              : "CHAR",
        char_strip_offset : 0,
        preview_surf      : -1,
		mc_mode           : 2,
        paint_mc          : 0,
        map_mc_bg         : -1,
        map_mc_col1       : -1,
        map_mc_col2       : -1,
        override_grid     : array_create(_w * _h, 0)
    };
    scr_map_meta_defaults(_asset.meta);

    // Auto-assign first available CHAR_SET if none set
    if (_asset.meta.chr_asset == "" && instance_exists(obj_asset_manager)) {
        for (var _ci = 0; _ci < ds_list_size(obj_asset_manager.asset_list); _ci++) {
            var _ca = ds_list_find_value(obj_asset_manager.asset_list, _ci);
            if (_ca.type == "CHAR_SET") {
                _asset.meta.chr_asset = _ca.name;
                break;
            }
        }
    }

    // ----------------------------------------------------------------
    // BUILD BUFFER via flush — single source of truth
    // Layout: char_grid[0..map_sz-1]  colour_grid[map_sz..map_sz*2-1]
    // ----------------------------------------------------------------
    scr_asset_map_flush(_asset);


		global.undo_dirty = true;
		
		if (variable_struct_exists(_asset, "meta")) _asset.meta._mtime = md5_file(_asset.file);
}
