function scr_asset_sfx_reload(_asset) {
    show_debug_message("SFX RELOAD: called file=" + _asset.file);
    if (!variable_struct_exists(_asset, "file") || _asset.file == "") exit;
    if (!file_exists(_asset.file)) {
        show_debug_message("SFX RELOAD: File not found — " + _asset.file);
        exit;
    }
	global.asset_reload_in_progress = true;
    scr_asset_sfx_data_import(_asset, _asset.file);
    show_debug_message("SFX RELOAD: OK — " + filename_name(_asset.file));
	global.asset_reload_in_progress = false;
}