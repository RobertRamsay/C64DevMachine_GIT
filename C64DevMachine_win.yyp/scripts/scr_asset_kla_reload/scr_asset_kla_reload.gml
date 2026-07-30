function scr_asset_kla_reload(_asset) {
    show_debug_message("KLA RELOAD: called file=" + _asset.file);
    if (_asset.file == "") exit;
    if (!file_exists(_asset.file)) {
        show_debug_message("KLA RELOAD: File missing - " + _asset.file);
        exit;
    }
    global.asset_reload_in_progress = true;
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    var _buf = buffer_load(_asset.file);
    var _expected_size = scr_asset_bmp_is_hires(_asset) ? 9002 : 10003;
    show_debug_message("KLA RELOAD: buf exists=" + string(buffer_exists(_buf)) + " size=" + string(buffer_exists(_buf) ? buffer_get_size(_buf) : -1) + " expected=" + string(_expected_size));
    if (!buffer_exists(_buf) || buffer_get_size(_buf) != _expected_size) {
        if (buffer_exists(_buf)) buffer_delete(_buf);
        global.asset_reload_in_progress = false;
        exit;
    }
    _asset.buffer = _buf;
    scr_asset_bmp_build_preview(_asset);
    // Seed pixel_backup immediately so F11 surface loss can restore without ever opening the viewer
    if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
        if (!variable_struct_exists(_asset.meta, "pixel_backup")) _asset.meta.pixel_backup = -1;
        if (!buffer_exists(_asset.meta.pixel_backup)) {
            _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
        }
        buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
    }
    show_debug_message("KLA RELOAD: OK");
    global.asset_reload_in_progress = false;
}