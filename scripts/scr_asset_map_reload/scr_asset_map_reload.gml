/// scr_asset_map_reload(_asset)
function scr_asset_map_reload(_asset) {
    if (!variable_struct_exists(_asset, "file") || _asset.file == "") exit;
    if (!file_exists(_asset.file)) {
        show_debug_message("MAP RELOAD: File not found — " + _asset.file);
        exit;
    }
    if (!variable_struct_exists(_asset, "meta") ||
        !variable_struct_exists(_asset.meta, "map_w")) {
        show_debug_message("MAP RELOAD: No meta/dimensions — import first");
        exit;
    }

    var _buf = buffer_load(_asset.file);
    if (!buffer_exists(_buf)) {
        show_debug_message("MAP RELOAD: Buffer load failed");
        exit;
    }

    var _m    = _asset.meta;
    var _w    = _m.map_w;
    var _h    = _m.map_h;
    var _sz   = _w * _h;
    var _bufsz = buffer_get_size(_buf);

    if (_sz > _bufsz) {
        show_debug_message("MAP RELOAD: File too small for "
            + string(_w) + "x" + string(_h)
            + " — expected " + string(_sz) + " got " + string(_bufsz));
        buffer_delete(_buf);
        exit;
    }
	global.asset_reload_in_progress = true;
    // Reload char_grid only — preserve colour_grid, chr_asset, zoom, scroll etc
    for (var _i = 0; _i < _sz; _i++) {
        _m.char_grid[_i] = buffer_peek(_buf, _i, buffer_u8);
    }
    buffer_delete(_buf);

    scr_asset_map_flush(_asset);
    show_debug_message("MAP RELOAD: OK — " + filename_name(_asset.file)
        + "  " + string(_w) + "x" + string(_h));
	global.asset_reload_in_progress = false;
}