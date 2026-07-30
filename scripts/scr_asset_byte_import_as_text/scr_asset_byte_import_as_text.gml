/// @desc Import a .txt file into a BYTE_DATA asset (treated as raw text until compile)
function scr_asset_byte_import_as_text(_asset) {
    var _path = get_open_filename("Text File|*.txt;*.text;*.csv;*.dat", "");
    if (_path == "") {
        exit;
    }
    var _f = file_text_open_read(_path);
    if (_f < 0) {
        scr_show_message("BYTE IMPORT: Could not open file.");
        exit;
    }
    var _str = "";
    while (!file_text_eof(_f)) {
        _str += file_text_read_string(_f);
        if (!file_text_eof(_f)) {
            file_text_readln(_f);
        }
    }
    file_text_close(_f);
    _asset.file                    = _path;
    _asset.meta.byte_string        = _str;
    _asset.meta.inline_edit_text   = _str;
    scr_asset_byte_data_save(_asset);
    show_debug_message("BYTE IMPORT: OK — " + filename_name(_path)
        + "  chars=" + string(string_length(_str))
        + "  bytes=" + string(buffer_get_size(_asset.buffer)));
    global.undo_dirty = true;
    if (variable_struct_exists(_asset, "meta")) {
        _asset.meta._mtime = md5_file(_asset.file);
    }
}