function scr_asset_chr_reload(_asset) {
    if (!variable_struct_exists(_asset, "file") || _asset.file == "") exit;
    if (!file_exists(_asset.file)) {
        show_debug_message("CHR RELOAD: File not found — " + _asset.file);
        exit;
    }
    global.asset_reload_in_progress = true;
    if (variable_struct_exists(_asset, "buffer") && buffer_exists(_asset.buffer)) {
        buffer_delete(_asset.buffer);
    }
    // --- detect text vs binary (same logic as scr_asset_chr_import) ---
    var _is_text = false;
    var _text_check = file_text_open_read(_asset.file);
    if (_text_check != -1) {
        var _first = file_text_read_string(_text_check);
        file_text_close(_text_check);
        var _stripped = string_trim(_first);
        var _fc = string_lower(string_copy(_stripped, 1, 4));
        if (_fc == "byte" || string_char_at(_stripped, 1) == "$"
        ||  (string_char_at(_stripped, 1) >= "0" && string_char_at(_stripped, 1) <= "9"))
            _is_text = true;
    }
    var _buf, _size;
    if (_is_text) {
        _buf = buffer_create(2048, buffer_grow, 1);
        var _f = file_text_open_read(_asset.file);
        while (!file_text_eof(_f)) {
            var _line = string_trim(file_text_read_string(_f));
            file_text_readln(_f);
            if (_line == "") continue;
            if (string_lower(string_copy(_line, 1, 4)) == "byte")
                _line = string_trim(string_delete(_line, 1, 4));
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
        _size = min(buffer_tell(_buf), 2048);
        buffer_seek(_buf, buffer_seek_start, 0);
        show_debug_message("CHR RELOAD: TEXT format");
    } else {
        _buf  = buffer_load(_asset.file);
        if (!buffer_exists(_buf)) {
            show_debug_message("CHR RELOAD: Buffer load failed");
            global.asset_reload_in_progress = false;
            exit;
        }
        _size = min(buffer_get_size(_buf), 2048);
        show_debug_message("CHR RELOAD: BINARY format");
    }
    var _char_count = _size div 8;
    var _used_size  = _char_count * 8;
    _asset.buffer = _buf;
    if (variable_struct_exists(_asset, "meta")) {
        _asset.meta.char_count = _char_count;
        _asset.meta.total_size = _used_size;
    } else {
        _asset.meta = {
            format      : "binary",
            char_count  : _char_count,
            total_size  : _used_size,
            preview_surf: -1,
            undo_stack  : [],
            redo_stack  : []
        };
    }
    scr_asset_chr_build_preview(_asset);
    show_debug_message("CHR RELOAD: OK — " + _asset.file_name + " (" + string(_char_count) + " chars)");
    global.asset_reload_in_progress = false;
}