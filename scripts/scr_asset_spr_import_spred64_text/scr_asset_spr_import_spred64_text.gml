/// @desc Reimports a Spred64 decimal text file directly into an asset struct.
function scr_asset_spr_import_spred64_text(_asset, _path) {

    if (!file_exists(_path)) exit;

    var _file    = file_text_open_read(_path);
    var _content = "";
    while (!file_text_eof(_file)) {
        _content += file_text_read_string(_file) + "\n";
        file_text_readln(_file);
    }
    file_text_close(_file);

    var _lines = string_split(_content, "\n");

    var _sprites    = array_create(64, "");
    var _sprite_mcs = array_create(64, 0);
    var _sprite_ucs = array_create(64, 1);
    var _bg_col     = 0;
    var _mc1_col    = 1;
    var _mc2_col    = 2;

    // Read global colours from header
    for (var _li = 0; _li < min(array_length(_lines), 10); _li++) {
        var _line = string_trim(_lines[_li]);
        if (string_pos("Background Colour :", _line) > 0) {
            var _p  = string_last_pos(":", _line);
            _bg_col = real(string_trim(string_delete(_line, 1, _p)));
        }
        if (string_pos("Global MC Colour1 :", _line) > 0) {
            var _p   = string_last_pos(":", _line);
            _mc1_col = real(string_trim(string_delete(_line, 1, _p)));
        }
        if (string_pos("Global MC Colour2 :", _line) > 0) {
            var _p   = string_last_pos(":", _line);
            _mc2_col = real(string_trim(string_delete(_line, 1, _p)));
        }
    }

    // Read per-sprite blocks
    var _curr_id    = -1;
    var _curr_mc    = 0;
    var _curr_uc    = 1;
    var _curr_bytes = "";

    for (var _li = 0; _li < array_length(_lines); _li++) {
        var _line = string_trim(_lines[_li]);

        if (string_pos("// Sprite ID :", _line) > 0 && string_pos(";", _line) > 0) {
            if (_curr_id >= 0 && _curr_id < 64 && _curr_bytes != "") {
                _sprites[_curr_id]    = _curr_bytes;
                _sprite_mcs[_curr_id] = _curr_mc;
                _sprite_ucs[_curr_id] = _curr_uc;
            }
            var _p1  = string_pos("// Sprite ID :", _line) + 14;
            var _p2  = string_pos(";", _line);
            _curr_id = real(string_trim(string_copy(_line, _p1, _p2 - _p1)));
            _curr_mc    = 0;
            _curr_uc    = 1;
            _curr_bytes = "";
            continue;
        }

        if (_curr_id >= 0) {
            if (string_pos("HR(0) MC(1) :", _line) > 0) {
                var _p   = string_last_pos(":", _line);
                _curr_mc = real(string_trim(string_delete(_line, 1, _p)));
            }
            if (string_pos("Sprite Unique Colour :", _line) > 0) {
                var _p   = string_last_pos(":", _line);
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
    // Save last sprite
    if (_curr_id >= 0 && _curr_id < 64 && _curr_bytes != "") {
        _sprites[_curr_id]    = _curr_bytes;
        _sprite_mcs[_curr_id] = _curr_mc;
        _sprite_ucs[_curr_id] = _curr_uc;
    }

    // Auto-detect used count
    var _used_count = 0;
    for (var _si = 63; _si >= 0; _si--) {
        if (_sprites[_si] == "") continue;
        var _vals     = string_split(_sprites[_si], ",");
        var _has_data = false;
        for (var _vi = 0; _vi < array_length(_vals); _vi++) {
            var _t = string_trim(_vals[_vi]);
            if (_t != "" && real(_t) != 0) { _has_data = true; break; }
        }
        if (_has_data) { _used_count = _si + 1; break; }
    }
    if (_used_count == 0) _used_count = 1;

    // Trim meta arrays so no blank-slot state is carried past used_count
    array_resize(_sprite_mcs, _used_count);
    array_resize(_sprite_ucs, _used_count);

    // Build buffer
    var _sprite_buf = buffer_create(_used_count * 64, buffer_fixed, 1);
    buffer_seek(_sprite_buf, buffer_seek_start, 0);
    for (var _si = 0; _si < _used_count; _si++) {
        var _s_data = _sprites[_si];
        if (_s_data == "") {
            repeat(64) buffer_write(_sprite_buf, buffer_u8, 0);
        } else {
            var _vals = string_split(_s_data, ",");
            for (var _vi = 0; _vi < 64; _vi++) {
                var _v = (_vi < array_length(_vals)) ? real(string_trim(_vals[_vi])) : 0;
                buffer_write(_sprite_buf, buffer_u8, _v);
            }
        }
    }

    // Build hex blob
    var _hex_blob = "";
    buffer_seek(_sprite_buf, buffer_seek_start, 0);
    repeat(_used_count * 64) {
        _hex_blob += decimal_to_hex(buffer_read(_sprite_buf, buffer_u8));
    }

    // Build JSON
    // Meta arrays resized to _used_count above, so bound the loop to that length.
    var _json = "[";
    var _json_count = array_length(_sprite_mcs);
    for (var _si = 0; _si < _json_count; _si++) {
        if (_si > 0) _json += ",";
        _json += "{\"b\":\"" + _sprites[_si] + "\",\"mc\":" + string(_sprite_mcs[_si]) + ",\"uc\":" + string(_sprite_ucs[_si]) + "}";
    }
    _json += "]";

   // Clean up old cache
    if (variable_struct_exists(_asset.meta, "spr_sprites")) {
        var _old_len = array_length(_asset.meta.spr_sprites);
        for (var _si = 0; _si < _old_len; _si++) {
            if (_asset.meta.spr_sprites[_si] != -1 &&
                sprite_exists(_asset.meta.spr_sprites[_si]))
                sprite_delete(_asset.meta.spr_sprites[_si]);
        }
    }
    if (variable_struct_exists(_asset.meta, "preview_surf") &&
        surface_exists(_asset.meta.preview_surf))
        surface_free(_asset.meta.preview_surf);
    if (buffer_exists(_asset.buffer))
        buffer_delete(_asset.buffer);

    // Store
    _asset.buffer = _sprite_buf;
    _asset.meta = {
        format      : "spred64",
        has_colour  : true,
        bg_col      : _bg_col,
        mc1_col     : _mc1_col,
        mc2_col     : _mc2_col,
        sprite_json : _json,
        sprite_mcs  : _sprite_mcs,
        sprite_ucs  : _sprite_ucs,
        found_count : _used_count,
        used_count  : _used_count,
        hex_blob    : _hex_blob,
        total_size  : _used_count * 64
    };

    // Parse and import the V1 compositor block, if present.
    // The parser writes to _asset.meta.compositor and seeds _asset.meta.anim.
    // No-op if the file has no compositor section, so safe to always call.
    scr_spred64_v2_import_v1_compositor(_asset, _path);

    scr_asset_spr_cache_sprites(_asset, true);
}