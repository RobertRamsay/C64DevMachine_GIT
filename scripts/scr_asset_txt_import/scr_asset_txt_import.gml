/// @desc Import a .txt file into a TEXT_DATA asset
function scr_asset_txt_import(_asset) {
var _path = (argument_count > 1 && argument[1] != "") ? argument[1] : get_open_filename("Text File|*.txt", "");
    if (_path == "") exit;

    var _f = file_text_open_read(_path);
    if (_f < 0) {
        scr_show_message("TEXT IMPORT: Could not open file.");
        exit;
    }
    var _str = "";
    while (!file_text_eof(_f)) {
        _str += file_text_read_string(_f);
        if (!file_text_eof(_f)) file_text_readln(_f);
    }
    file_text_close(_f);

    // Strip CR/LF — single line for scroller
	_str = string_replace_all(_str, "\r", "");
    _str = string_replace_all(_str, "\n", "");
    while (string_length(_str) > 0 && string_char_at(_str, string_length(_str)) == " ")
        _str = string_delete(_str, string_length(_str), 2);

    _asset.file          = _path;
    _asset.meta.text     = _str;
    scr_asset_text_flush(_asset);

    show_debug_message("TEXT IMPORT: OK — " + filename_name(_path)
        + "  chars=" + string(string_length(_str))
        + "  bytes=" + string(buffer_get_size(_asset.buffer)));
		global.undo_dirty = true;
		
		if (variable_struct_exists(_asset, "meta")) _asset.meta._mtime = md5_file(_asset.file);
}