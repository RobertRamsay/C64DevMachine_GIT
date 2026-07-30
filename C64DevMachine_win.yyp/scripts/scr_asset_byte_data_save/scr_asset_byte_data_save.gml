/// @function scr_asset_byte_data_save(asset)
function scr_asset_byte_data_save(_asset) {
    var _raw = _asset.meta.inline_edit_text;

    // Normalise separators: newlines, tabs, semicolons, spaces -> commas
    var _clean_raw = string_replace_all(_raw, "\n", ",");
    _clean_raw = string_replace_all(_clean_raw, "\r", ",");
    _clean_raw = string_replace_all(_clean_raw, "\t", ",");
    _clean_raw = string_replace_all(_clean_raw, ";",  ",");

    // Split on commas, validate and parse each token
    var _tokens = string_split(_clean_raw, ",");
    var _bytes  = [];
    var _skipped = 0;

    for (var _i = 0; _i < array_length(_tokens); _i++) {
        var _tok = string_trim(_tokens[_i]);
        if (_tok == "") continue;

        // Strip any stray whitespace inside the token (e.g. "$ A9" or "1 0")
        _tok = string_replace_all(_tok, " ", "");
        if (_tok == "") continue;

        var _val   = 0;
        var _valid = true;
        var _first = string_char_at(_tok, 1);

        if (_first == "$") {
            // ── HEX ──────────────────────────────────────────────
            var _hex_str = string_delete(_tok, 1, 1);
            var _hlen    = string_length(_hex_str);
            if (_hlen == 0 || _hlen > 4) {
                _valid = false;
            } else {
                for (var _h = 1; _h <= _hlen; _h++) {
                    var _hc = string_upper(string_char_at(_hex_str, _h));
                    var _ok = false;
                    if (_hc >= "0" && _hc <= "9") {
                        _ok = true;
                    } else if (_hc >= "A" && _hc <= "F") {
                        _ok = true;
                    }
                    if (!_ok) {
                        _valid = false;
                        break;
                    }
                }
                if (_valid) {
                    _val = real("0x" + _hex_str);
                }
            }
        } else if (_first == "%") {
            // ── BINARY ───────────────────────────────────────────
            var _bin_str = string_delete(_tok, 1, 1);
            var _blen    = string_length(_bin_str);
            if (_blen == 0 || _blen > 16) {
                _valid = false;
            } else {
                var _bin_val = 0;
                for (var _b = 1; _b <= _blen; _b++) {
                    var _bc = string_char_at(_bin_str, _b);
                    if (_bc == "0") {
                        _bin_val = _bin_val * 2;
                    } else if (_bc == "1") {
                        _bin_val = _bin_val * 2 + 1;
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
            // ── DECIMAL ──────────────────────────────────────────
            // Allow optional leading "-" but final value will be clamped 0..255
            var _dec_str   = _tok;
            var _start_idx = 1;
            if (string_char_at(_dec_str, 1) == "-") {
                _start_idx = 2;
            }
            var _dlen = string_length(_dec_str);
            if (_dlen < _start_idx) {
                _valid = false;
            } else {
                for (var _d = _start_idx; _d <= _dlen; _d++) {
                    var _dc = string_char_at(_dec_str, _d);
                    if (_dc < "0" || _dc > "9") {
                        _valid = false;
                        break;
                    }
                }
                if (_valid) {
                    _val = real(_dec_str);
                }
            }
        }

        if (_valid) {
            _val = clamp(floor(_val), 0, 255);
            array_push(_bytes, _val);
        } else {
            _skipped += 1;
            show_debug_message("scr_asset_byte_data_save: skipped invalid token \"" + _tok + "\"");
        }
    }

    // Write to buffer
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    var _count = array_length(_bytes);
    _asset.buffer = buffer_create(max(1, _count), buffer_fixed, 1);
    for (var _i = 0; _i < _count; _i++) {
        buffer_poke(_asset.buffer, _i, buffer_u8, _bytes[_i]);
    }

    // Keep byte_string in sync for the preview (original raw text, formatting preserved)
    _asset.meta.byte_string = _raw;

    if (_skipped > 0) {
        show_debug_message("scr_asset_byte_data_save: " + string(_skipped) + " invalid token(s) skipped.");
    }
}