function scr_asset_chr_import(_asset) {
   var _path = get_open_filename("All Charset Files|*.txt;*.bin;*.ctc;*.ctm|Charset Text|*.txt|Charset Binary|*.bin;*.ctc|CharPad CTM|*.ctm|All Files|*.*", "");
   // A native file dialog takes focus, so the key-up that ends the keypress is
   // delivered to the dialog and not to the game. GameMaker is left thinking the
   // key is still held, and keyboard_check_pressed() needs an up->down edge — so
   // ESC silently stops working until the input state is reset. This is why ESC
   // only failed after SOME asset operations: scr_asset_sid_import already did
   // this, every other importer did not.
   io_clear();
    if (_path == "" || !file_exists(_path)) exit;

    // CharPad CTM: pull ONLY the charset block, ignore materials/colours/tiles/map.
    // Extension check is case-insensitive.
    var _chr_ext = string_lower(filename_ext(_path));
    if (_chr_ext == ".ctm") {
        scr_asset_chr_import_charpad_ctm(_asset, _path);
        exit;
    }
// --- detect text vs binary ---
    var _is_text = false;
    var _text_check = file_text_open_read(_path);
    if (_text_check != -1) {
        var _first = file_text_read_string(_text_check);
        file_text_close(_text_check);
        // if line starts with BYTE / digits / $ / comma it's text data
        var _stripped = string_trim(_first);
        var _fc = string_lower(string_copy(_stripped, 1, 4));
        if (_fc == "byte" || string_char_at(_stripped, 1) == "$"
        ||  (string_char_at(_stripped, 1) >= "0" && string_char_at(_stripped, 1) <= "9"))
            _is_text = true;
    }

    var _buf, _size;
    if (_is_text) {
        // parse decimal / hex text lines
        _buf  = buffer_create(2048, buffer_grow, 1);
        var _f = file_text_open_read(_path);
        while (!file_text_eof(_f)) {
            var _line = string_trim(file_text_read_string(_f));
            file_text_readln(_f);
            if (_line == "") continue;
            // strip optional leading "BYTE" keyword (case-insensitive)
            if (string_lower(string_copy(_line, 1, 4)) == "byte")
                _line = string_trim(string_delete(_line, 1, 4));
            // split by comma
            var _parts = string_split(_line, ",");
            for (var _pi = 0; _pi < array_length(_parts); _pi++) {
                var _tok = string_trim(_parts[_pi]);
                if (_tok == "") continue;
                var _val;
                if (string_char_at(_tok, 1) == "$")
                    _val = real("0x" + string_delete(_tok, 1, 1));
                else
                    _val = real(_tok);
                buffer_write(_buf, buffer_u8, _val & 0xFF);
            }
        }
         file_text_close(_f);
        // Clamp to exactly 256 chars (2048 bytes)
        _size = min(buffer_tell(_buf), 2048);
        buffer_seek(_buf, buffer_seek_start, 0);
    } else {
        _buf  = buffer_load(_path);
        if (!buffer_exists(_buf)) exit;
        _size = buffer_get_size(_buf);
    }
    if (_size < 8) {
        buffer_delete(_buf);
        scr_show_message("File too small (" + string(_size) + " bytes) — minimum 8 bytes (1 char).");
        exit;
    }
    if (variable_struct_exists(_asset, "buffer") && buffer_exists(_asset.buffer))
        buffer_delete(_asset.buffer);
    var _char_count  = _size div 8;
    var _used_size   = _char_count * 8;
    _asset.buffer    = _buf;
    _asset.file      = _path;
    _asset.file_name = filename_name(_path);
    _asset.meta = {
        format      : "binary",
        char_count  : _char_count,
        total_size  : _used_size,
        preview_surf: -1,
        mc_mode     : 0,
        mc_fg       : 1,
        mc_bg       : 0,
        mc_col1     : 1,
        mc_col2     : 2,
        is_dirty    : false,
        flash_timer : 0,
        autosave    : true,
        undo_stack  : [],
        redo_stack  : []
    };

    scr_asset_chr_build_preview(_asset);
    global.undo_dirty = true;
    _asset.meta._mtime = md5_file(_asset.file);
}