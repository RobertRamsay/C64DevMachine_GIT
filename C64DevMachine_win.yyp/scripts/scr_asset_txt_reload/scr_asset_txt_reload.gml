/// scr_asset_txt_reload(_asset)
function scr_asset_txt_reload(_asset) {
    if (!variable_struct_exists(_asset, "file") || _asset.file == "") exit;
    if (!file_exists(_asset.file)) {
        show_debug_message("TXT RELOAD: File not found — " + _asset.file);
        exit;
    }
    var _f = file_text_open_read(_asset.file);
    if (_f < 0) {
        show_debug_message("TXT RELOAD: Could not open file");
        exit;
    }
    global.asset_reload_in_progress = true;
    var _str = "";
    while (!file_text_eof(_f)) {
        _str += file_text_read_string(_f);
        if (!file_text_eof(_f)) file_text_readln(_f);
    }
    file_text_close(_f);
    _str = string_replace_all(_str, "\r", "");
    _str = string_replace_all(_str, "\n", "");
    while (string_length(_str) > 0 && string_char_at(_str, string_length(_str)) == " ")
        _str = string_delete(_str, string_length(_str), 2);
    _asset.meta.text = _str;
    scr_asset_text_flush(_asset);
    show_debug_message("TXT RELOAD: OK — " + filename_name(_asset.file)
        + "  chars=" + string(string_length(_str)));
    global.asset_reload_in_progress = false;
}