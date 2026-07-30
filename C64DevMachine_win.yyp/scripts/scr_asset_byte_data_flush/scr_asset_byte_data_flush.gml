function scr_asset_byte_data_flush(_asset) {
    var _str = "";
    if (variable_struct_exists(_asset, "meta") && variable_struct_exists(_asset.meta, "byte_string")) {
        _str = string(_asset.meta.byte_string);
    }

    // Strip BOM / control bytes from the head
    while (string_length(_str) > 0 && string_byte_at(_str, 1) < 32) {
        _str = string_delete(_str, 1, 1);
    }

    // Normalise line endings
    _str = string_replace_all(_str, "\r\n", "\n");
    _str = string_replace_all(_str, "\r",   "\n");

    var _lines     = string_split(_str, "\n");
    var _out_lines = [];
    var _all_bytes = [];
    var _skipped   = 0;

    for (var _li = 0; _li < array_length(_lines); _li++) {
        var _line = string_trim(_lines[_li]);
        if (_line == "") {
            array_push(_out_lines, "");
            continue;
        }

        // Treat tabs and semicolons as separators
        _line = string_replace_all(_line, "\t", ",");
        _line = string_replace_all(_line, ";",  ",");

        var _parts      = string_split(_line, ",");
        var _out_tokens = [];

        for (var _i = 0; _i < array_length(_parts); _i++) {
            var _tok = string_trim(_parts[_i]);
            if (_tok == "") continue;

            // Strip any stray internal whitespace ("$ A9" -> "$A9")
            _tok = string_replace_all(_tok, " ", "");
            if (_tok == "") continue;

            var _val   = 0;
            var _style = "dec";
            var _valid = true;

            // Detect prefix and isolate payload
            var _first = string_char_at(_tok, 1);
            var _payload = "";

            if (_first == "$") {
                _style   = "dollar";
                _payload = string_delete(_tok, 1, 1);
                if (string_length(_payload) == 0 || string_length(_payload) > 4) {
                    _valid = false;
                } else {
                    _valid = scr_str_is_hex(_payload);
                    if (_valid) {
                        _val = hex_to_decimal(_payload);
                    }
                }
            } else if (string_length(_tok) >= 2 && string_lower(string_copy(_tok, 1, 2)) == "0x") {
                _style   = "0x";
                _payload = string_copy(_tok, 3, string_length(_tok) - 2);
                if (string_length(_payload) == 0 || string_length(_payload) > 4) {
                    _valid = false;
                } else {
                    _valid = scr_str_is_hex(_payload);
                    if (_valid) {
                        _val = hex_to_decimal(_payload);
                    }
                }
            } else if (_first == "%") {
                _style   = "bin";
                _payload = string_delete(_tok, 1, 1);
                if (string_length(_payload) == 0 || string_length(_payload) > 16) {
                    _valid = false;
                } else {
                    var _bin_val = 0;
                    for (var _b = 1; _b <= string_length(_payload); _b++) {
                        var _bc = string_char_at(_payload, _b);
                        if (_bc == "1") {
                            _bin_val = _bin_val * 2 + 1;
                        } else if (_bc == "0") {
                            _bin_val = _bin_val * 2;
                        } else {
                            _valid = false;
                            break;
                        }
                    }
                    if (_valid) {
                        _val = _bin_val;
                    }
                }
            } else {
                // No prefix: decide hex vs decimal by content
                if (scr_str_is_decimal(_tok)) {
                    _style = "dec";
                    _val   = real(_tok);
                } else if (scr_str_is_hex(_tok)) {
                    _style = "bare_hex";
                    _val   = hex_to_decimal(_tok);
                } else {
                    _valid = false;
                }
            }

            if (!_valid) {
                _skipped += 1;
                show_debug_message("scr_asset_byte_data_flush: skipped invalid token \"" + _tok + "\"");
                continue;
            }

            var _v = clamp(floor(_val), 0, 255);
            array_push(_all_bytes, _v);

            // Re-emit token in the same style the user wrote it
            var _out_tok = "";
            if (_style == "dollar") {
                var _hex_str = decimal_to_hex(_v);
                if (string_length(_hex_str) < 2) {
                    _hex_str = "0" + _hex_str;
                }
                _out_tok = "$" + string_upper(_hex_str);
            } else if (_style == "0x") {
                var _hex_str2 = decimal_to_hex(_v);
                if (string_length(_hex_str2) < 2) {
                    _hex_str2 = "0" + _hex_str2;
                }
                _out_tok = "0x" + string_upper(_hex_str2);
            } else if (_style == "bin") {
                var _bin_out = "";
                var _vv      = _v;
                for (var _b = 7; _b >= 0; _b--) {
                    // Parenthesise carefully: & has lower precedence than == in GML
                    var _bit = (_vv >> _b) & 1;
                    if (_bit == 1) {
                        _bin_out += "1";
                    } else {
                        _bin_out += "0";
                    }
                }
                _out_tok = "%" + _bin_out;
            } else if (_style == "bare_hex") {
                var _hex_str3 = decimal_to_hex(_v);
                if (string_length(_hex_str3) < 2) {
                    _hex_str3 = "0" + _hex_str3;
                }
                _out_tok = string_upper(_hex_str3);
            } else {
                _out_tok = string(_v);
            }

            array_push(_out_tokens, _out_tok);
        }

        if (array_length(_out_tokens) > 0) {
            array_push(_out_lines, string_join_ext(", ", _out_tokens));
        }
    }

    var _serialised = string_join_ext("\n", _out_lines);

    if (variable_struct_exists(_asset, "meta")) {
        _asset.meta.byte_string      = _serialised;
        _asset.meta.inline_edit_text = _serialised;
    }

    var _final_count = array_length(_all_bytes);
    if (buffer_exists(_asset.buffer)) {
        buffer_delete(_asset.buffer);
    }
    _asset.buffer = buffer_create(max(1, _final_count), buffer_fixed, 1);
    for (var _i = 0; _i < _final_count; _i++) {
        buffer_write(_asset.buffer, buffer_u8, _all_bytes[_i]);
    }
    _asset.size = _final_count;

    if (_skipped > 0) {
        show_debug_message("scr_asset_byte_data_flush: " + string(_skipped) + " invalid token(s) skipped.");
    }
}