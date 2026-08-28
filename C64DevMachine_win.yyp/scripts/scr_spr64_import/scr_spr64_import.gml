function scr_spr64_import(_node_id) {
    var _path = get_open_filename("Spred Export|*.txt;*.spr", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. This is why ESC
    // only failed after SOME asset operations: scr_asset_sid_import already did
    // this, every other importer did not.
    io_clear();
    if (_path == "") exit;
    if (!file_exists(_path)) {
        scr_show_message("SPR64: File not found:\n" + _path);
        exit;
    }

    // Read file
    var _file    = file_text_open_read(_path);
    var _content = "";
    while (!file_text_eof(_file)) {
        _content += file_text_read_string(_file) + "\n";
        file_text_readln(_file);
    }
    file_text_close(_file);
    var _lines = string_split(_content, "\n");

    // Pull global colours from file header
    var _bg_col  = 0;
    var _mc1_col = 0;
    var _mc2_col = 0;
    for (var _li = 0; _li < min(array_length(_lines), 10); _li++) {
        var _line = string_trim(_lines[_li]);
        if (string_pos("Background Colour :", _line) > 0) {
            var _p = string_last_pos(":", _line);
            _bg_col = real(string_trim(string_delete(_line, 1, _p)));
        }
        if (string_pos("Global MC Colour1 :", _line) > 0) {
            var _p = string_last_pos(":", _line);
            _mc1_col = real(string_trim(string_delete(_line, 1, _p)));
        }
        if (string_pos("Global MC Colour2 :", _line) > 0) {
            var _p = string_last_pos(":", _line);
            _mc2_col = real(string_trim(string_delete(_line, 1, _p)));
        }
    }

    // Parse all 64 sprites into JSON array
    var _sprites     = array_create(64, "");
    var _sprite_mcs  = array_create(64, 0);
    var _sprite_ucs  = array_create(64, 1);
    var _found_count = 0;

    var _curr_id    = -1;
    var _curr_mc    = 0;
    var _curr_uc    = 1;
    var _curr_bytes = "";

    for (var _li = 0; _li < array_length(_lines); _li++) {
        var _line = string_trim(_lines[_li]);

        // Detect sprite ID header
        if (string_pos("// Sprite ID :", _line) > 0 && string_pos(";", _line) > 0) {
            // Save previous sprite if we have one
            if (_curr_id >= 0 && _curr_id < 64 && _curr_bytes != "") {
                _sprites[_curr_id]    = _curr_bytes;
                _sprite_mcs[_curr_id] = _curr_mc;
                _sprite_ucs[_curr_id] = _curr_uc;
                _found_count++;
            }
            // Start new block
            var _p1      = string_pos("// Sprite ID :", _line) + 14;
            var _p2      = string_pos(";", _line);
            _curr_id     = real(string_trim(string_copy(_line, _p1, _p2 - _p1)));
            _curr_mc     = 0;
            _curr_uc     = 1;
            _curr_bytes  = "";
            continue;
        }

        if (_curr_id >= 0) {
            if (string_pos("HR(0) MC(1) :", _line) > 0) {
                var _p  = string_last_pos(":", _line);
                _curr_mc = real(string_trim(string_delete(_line, 1, _p)));
            }
            if (string_pos("Sprite Unique Colour :", _line) > 0) {
                var _p  = string_last_pos(":", _line);
                _curr_uc = real(string_trim(string_delete(_line, 1, _p)));
            }
            if (string_lower(string_copy(_line, 1, 5)) == ".byte") {
                var _data = string_trim(string_delete(_line, 1, 5));
                var _vals = string_split(_data, ",");
                for (var _vi = 0; _vi < min(array_length(_vals), 64); _vi++) {
                    if (_curr_bytes != "") _curr_bytes += ",";
                    _curr_bytes += string_trim(_vals[_vi]);
                }
            }
        }
    }

    // Save the last sprite
    if (_curr_id >= 0 && _curr_id < 64 && _curr_bytes != "") {
        _sprites[_curr_id]    = _curr_bytes;
        _sprite_mcs[_curr_id] = _curr_mc;
        _sprite_ucs[_curr_id] = _curr_uc;
        _found_count++;
    }

    if (_found_count == 0) {
        scr_show_message("SPR64: No sprite data found in file.");
        exit;
    }

   // Build JSON string (Keep for legacy/UI display if needed)
    var _json = "[";
    for (var _si = 0; _si < 64; _si++) {
        if (_si > 0) _json += ",";
        _json += "{\"b\":\"" + _sprites[_si] + "\",\"mc\":" + string(_sprite_mcs[_si]) + ",\"uc\":" + string(_sprite_ucs[_si]) + "}";
    }
    _json += "]";

    // ================================================================
    // NEW BINARY BRIDGE LOGIC (SPR64)
    // ================================================================
    if (instance_exists(_node_id)) {
        
        // 1. Initialize/Refresh the persistent buffer (Always 4096 for a full bank)
        if (buffer_exists(_node_id.sprite_buffer)) buffer_delete(_node_id.sprite_buffer);
        _node_id.sprite_buffer = buffer_create(4096, buffer_fixed, 1);
        buffer_seek(_node_id.sprite_buffer, buffer_seek_start, 0);

        // 2. Fill the buffer with raw byte data from the parsed lines
        for (var _si = 0; _si < 64; _si++) {
            var _s_data = _sprites[_si];
            if (_s_data == "") {
                // Fill empty slots with zeros
                repeat(64) buffer_write(_node_id.sprite_buffer, buffer_u8, 0);
            } else {
                var _vals = string_split(_s_data, ",");
                for (var _vi = 0; _vi < 64; _vi++) {
                    var _v = (_vi < array_length(_vals)) ? real(string_trim(_vals[_vi])) : 0;
                    buffer_write(_node_id.sprite_buffer, buffer_u8, _v);
                }
            }
        }

        // 3. Generate the Hex Blob for JSON Workspace saving
        var _hex_blob = "";
        buffer_seek(_node_id.sprite_buffer, buffer_seek_start, 0);
        repeat(4096) {
            _hex_blob += decimal_to_hex(buffer_read(_node_id.sprite_buffer, buffer_u8));
        }
        _node_id.binary_blob = _hex_blob;

        // 4. Update node metadata
        while (array_length(_node_id.instructions[0]) < 8) {
            array_push(_node_id.instructions[0], 0);
        }
        
        _node_id.instructions[0][1] = _json;
        _node_id.instructions[0][2] = _path;
        _node_id.instructions[0][5] = _bg_col;
        _node_id.instructions[0][6] = _mc1_col;
        _node_id.instructions[0][7] = _mc2_col;
        
        // Force size to 4096 (Standard C64 Sprite Bank size)
        _node_id.total_node_size    = 4096;
        _node_id.spr_cached_frame   = -1; // force redraw
        
        // Sync addresses (Pass 3 will now find the buffer and be happy)
        scr_c64_update_addresses();
    }
}