/// @desc scr_asset_spr_import(_asset)
/// Loads a sprite file into an asset struct.
/// Supports: Spred64 text (.txt/.spr), ByteExample text, SpritePad (.spd), raw binary (.bin)
/// @param {struct} _asset - the asset struct from obj_asset_manager

function scr_asset_spr_import(_asset) {

    var _path = get_open_filename("Sprite Files|*.txt;*.spr;*.spd;*.bin", "");
    if (_path == "") exit;
    if (!file_exists(_path)) {
        scr_show_message("SPRITE IMPORT: File not found:\n" + _path);
        exit;
    }

    // -------------------------------------------------------
    // DETECT FORMAT
    // -------------------------------------------------------
    var _ext    = string_lower(filename_ext(_path));
    var _format = "unknown";

    if (_ext == ".bin") {
        _format = "binary";
    } else if (_ext == ".spd") {
        _format = "spritepad";
    } else {
        // Peek first line to distinguish Spred64 vs ByteExample
        var _f    = file_text_open_read(_path);
        var _peek = file_text_read_string(_f);
        file_text_close(_f);
        if (string_pos("// Spred", _peek) > 0) {
            _format = "spred64";
        } else {
            _format = "byteexample";
        }
    }



    // -------------------------------------------------------
    // SHARED OUTPUT ARRAYS
    // -------------------------------------------------------
    var _sprites     = array_create(64, "");
    var _sprite_mcs  = array_create(64, 0);
    var _sprite_ucs  = array_create(64, 1);
    var _bg_col      = 0;
    var _mc1_col     = 1;
    var _mc2_col     = 2;
    var _found_count = 0;
    var _has_colour  = true;

    // -------------------------------------------------------
    // PARSER: SPRED64
    // -------------------------------------------------------
    if (_format == "spred64") {

        var _file    = file_text_open_read(_path);
        var _content = "";
        while (!file_text_eof(_file)) {
            _content += file_text_read_string(_file) + "\n";
            file_text_readln(_file);
        }
        file_text_close(_file);
        var _lines = string_split(_content, "\n");

        // Global colours from header
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

        // Per-sprite blocks
        var _curr_id    = -1;
        var _curr_mc    = 0;
        var _curr_uc    = 1;
        var _curr_bytes = "";

        for (var _li = 0; _li < array_length(_lines); _li++) {
            var _line = string_trim(_lines[_li]);

            if (string_pos("// Sprite ID :", _line) > 0 && string_pos(";", _line) > 0) {
                // Save previous sprite
                if (_curr_id >= 0 && _curr_id < 64 && _curr_bytes != "") {
                    _sprites[_curr_id]    = _curr_bytes;
                    _sprite_mcs[_curr_id] = _curr_mc;
                    _sprite_ucs[_curr_id] = _curr_uc;
                    _found_count++;
                }
                var _p1     = string_pos("// Sprite ID :", _line) + 14;
                var _p2     = string_pos(";", _line);
                _curr_id    = real(string_trim(string_copy(_line, _p1, _p2 - _p1)));
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
            _found_count++;
        }
    }

    // -------------------------------------------------------
    // PARSER: BYTEEXAMPLE
    // -------------------------------------------------------
    else if (_format == "byteexample") {

        var _file    = file_text_open_read(_path);
        var _content = "";
        while (!file_text_eof(_file)) {
            _content += file_text_read_string(_file) + "\n";
            file_text_readln(_file);
        }
        file_text_close(_file);
        var _lines = string_split(_content, "\n");

        // Global colours from header .byte values
        var _reading_bg = false;
        var _reading_mc = false;
        for (var _li = 0; _li < min(array_length(_lines), 15); _li++) {
            var _line = string_trim(_lines[_li]);
            if (string_pos("Global Background Colour", _line) > 0) {
                _reading_bg = true; continue;
            }
            if (string_pos("Global Sprite colours", _line) > 0) {
                _reading_mc = true; continue;
            }
            if (_reading_bg && string_lower(string_copy(_line, 1, 5)) == ".byte") {
                var _data   = string_trim(string_delete(_line, 1, 5));
                _bg_col     = real(string_trim(_data));
                _reading_bg = false;
            }
            if (_reading_mc && string_lower(string_copy(_line, 1, 5)) == ".byte") {
                var _data  = string_trim(string_delete(_line, 1, 5));
                var _vals  = string_split(_data, ",");
                if (array_length(_vals) >= 1) _mc1_col = real(string_trim(_vals[0]));
                if (array_length(_vals) >= 2) _mc2_col = real(string_trim(_vals[1]));
                _reading_mc = false;
            }
        }

        // Per-sprite blocks
        var _curr_id    = -1;
        var _curr_mc    = 0;
        var _curr_uc    = 1;
        var _curr_bytes = "";
        var _in_sprite  = false;

        for (var _li = 0; _li < array_length(_lines); _li++) {
            var _line = string_trim(_lines[_li]);

            if (string_pos("// Sprite ID :", _line) > 0 && string_pos(";", _line) > 0) {
                if (_curr_id >= 0 && _curr_id < 64 && _curr_bytes != "") {
                    _sprites[_curr_id]    = _curr_bytes;
                    _sprite_mcs[_curr_id] = _curr_mc;
                    _sprite_ucs[_curr_id] = _curr_uc;
                    _found_count++;
                }
                var _p1     = string_pos("// Sprite ID :", _line) + 14;
                var _p2     = string_pos(";", _line);
                _curr_id    = real(string_trim(string_copy(_line, _p1, _p2 - _p1)));
                _curr_mc    = 0;
                _curr_uc    = 1;
                _curr_bytes = "";
                _in_sprite  = true;
                continue;
            }

            if (_in_sprite && _curr_id >= 0) {
                if (string_pos("HR(0) MC(1) :", _line) > 0) {
                    var _p   = string_last_pos(":", _line);
                    _curr_mc = real(string_trim(string_delete(_line, 1, _p)));
                }
                if (string_pos("Sprite Unique Colour :", _line) > 0) {
                    var _p   = string_last_pos(":", _line);
                    _curr_uc = real(string_trim(string_delete(_line, 1, _p)));
                }
                // Skip address label lines
                if (string_pos("spred_sprite_ids_loc", _line) > 0) continue;
                if (string_lower(string_copy(_line, 1, 5)) == ".byte") {
                    var _data = string_trim(string_delete(_line, 1, 5));
                    // Skip address table lines
                    if (string_pos("<spred", _data) > 0 || string_pos(">spred", _data) > 0) continue;
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
            _found_count++;
        }
    }

    // -------------------------------------------------------
    // PARSER: SPRITEPAD (.spd) — native SpritePad Pro project files
    //
    // Layout (verified byte-exact against SpritePad Pro v3 and v5 exports):
    //   0-2  'SPD' magic
    //   3    version (3 or 5 seen in the wild)
    //   4    flags/config
    //   5-6  sprite count (16-bit, little-endian)
    //   ...  header colours (v3 only, see below)
    //   Sprite data begins after the header. The HEADER SIZE differs by
    //   version: v3 = 16 bytes, v5 = 20 bytes. Everything from there is
    //   64 bytes per sprite: 63 pixel bytes (21 rows x 3) + 1 attribute
    //   byte. The attribute byte is identical across versions:
    //       bit 7    = multicolour flag (1 = MC, 0 = hi-res)
    //       bits 0-3 = the sprite's individual colour (C64 pen 0-15)
    //
    //   Global BG/MC1/MC2 colours sit at header bytes [13]/[14]/[15] in v3.
    //   v5 relocates them to fields not yet decoded, so for v5 they default
    //   (1 (MC0), 2 (MC1) etc. shared registers) and the user sets them
    //   in-app — the per-sprite colours, which matter most, still import
    //   correctly from the attribute byte.
    // -------------------------------------------------------
    else if (_format == "spritepad") {

        var _buf = buffer_load(_path);
        if (!buffer_exists(_buf)) {
            scr_show_message("SPRITE IMPORT: Could not load SPD file.");
            exit;
        }

        var _buf_len = buffer_get_size(_buf);
        if (_buf_len < 16) {
            buffer_delete(_buf);
            scr_show_message("SPRITE IMPORT: SPD file too small to be valid.");
            exit;
        }

        // Validate magic bytes S P D
        buffer_seek(_buf, buffer_seek_start, 0);
        var _m0 = buffer_read(_buf, buffer_u8);
        var _m1 = buffer_read(_buf, buffer_u8);
        var _m2 = buffer_read(_buf, buffer_u8);
        if (_m0 != 83 || _m1 != 80 || _m2 != 68) {
            buffer_delete(_buf);
            scr_show_message("SPRITE IMPORT: Not a valid SpritePad file.");
            exit;
        }

        // Version and sprite count (16-bit at [5]/[6]).
        buffer_seek(_buf, buffer_seek_start, 3);
        var _version   = buffer_read(_buf, buffer_u8); // [3]
        buffer_read(_buf, buffer_u8);                  // [4] flags — skip
        var _cnt_lo    = buffer_read(_buf, buffer_u8); // [5]
        var _cnt_hi    = buffer_read(_buf, buffer_u8); // [6]
        var _spd_count = _cnt_lo | (_cnt_hi << 8);

        // Header size and global-colour handling are version-keyed.
        var _data_off      = 16;
        var _read_hdr_cols = true;

        if (_version >= 5) {
            _data_off      = 20;    // v5 header is 4 bytes larger
            _read_hdr_cols = false; // v5 global colour offsets not decoded
        } else {
            _data_off      = 16;    // v3 (and earlier) header
            _read_hdr_cols = true;
        }

        if (_read_hdr_cols) {
            buffer_seek(_buf, buffer_seek_start, 13);
            _bg_col  = buffer_read(_buf, buffer_u8); // [13] VIC screen / BG (d021)
            _mc1_col = buffer_read(_buf, buffer_u8); // [14] VIC sprite MC1  (d025)
            _mc2_col = buffer_read(_buf, buffer_u8); // [15] VIC sprite MC2  (d026)
        } else {
            _bg_col  = 0;
            _mc1_col = 1;
            _mc2_col = 2;
        }

        // Clamp the declared count against the meta arrays (64) and against
        // what the file can actually hold, so a bad header can't overrun.
        if (_spd_count < 0)  _spd_count = 0;
        if (_spd_count > 64) _spd_count = 64;
        var _max_fit = (_buf_len - _data_off) div 64;
        if (_spd_count > _max_fit) _spd_count = _max_fit;

        if (_spd_count <= 0) {
            buffer_delete(_buf);
            scr_show_message("SPRITE IMPORT: SPD header reports no sprite data.");
            exit;
        }

        for (var _si = 0; _si < _spd_count; _si++) {

            var _base  = _data_off + (_si * 64);
            var _bytes = "";

            for (var _bi = 0; _bi < 64; _bi++) {
                buffer_seek(_buf, buffer_seek_start, _base + _bi);
                var _val = buffer_read(_buf, buffer_u8);

                if (_bi == 63) {
                    // Attribute byte: bit 7 = MC flag, bits 0-3 = colour pen.
                    _sprite_mcs[_si] = (_val >> 7) & 1;
                    _sprite_ucs[_si] = _val & 0x0F;
                    _val = 0; // not sprite pixel data on the C64 — zero it
                }

                if (_bytes != "") _bytes += ",";
                _bytes += string(_val);
            }

            _sprites[_si] = _bytes;
            _found_count++;
        }

        buffer_delete(_buf);
    }

    // -------------------------------------------------------
    // PARSER: RAW BINARY (.bin)
    // -------------------------------------------------------
else if (_format == "binary") {

    _has_colour = false;
    var _buf    = buffer_load(_path);

    if (!buffer_exists(_buf)) {
        scr_show_message("SPRITE IMPORT: Could not load binary file.");
        exit;
    }

    var _buf_size    = buffer_get_size(_buf);
    var _max_sprites = min(64, _buf_size div 64);  // only read what's there

    for (var _si = 0; _si < _max_sprites; _si++) {
        var _base  = _si * 64;
        var _bytes = "";

        for (var _bi = 0; _bi < 64; _bi++) {
            buffer_seek(_buf, buffer_seek_start, _base + _bi);
            var _val = buffer_read(_buf, buffer_u8);

            if (_bi == 63) {
                _sprite_mcs[_si] = (_val >> 7) & 1;
                _val = 0;
            }

            if (_bytes != "") _bytes += ",";
            _bytes += string(_val);
        }

        _sprites[_si]    = _bytes;
        _sprite_ucs[_si] = 1;
        _found_count++;
    }

    buffer_delete(_buf);
}

    // -------------------------------------------------------
    // VALIDATE
    // -------------------------------------------------------
    if (_found_count == 0) {
        scr_show_message("SPRITE IMPORT: No sprite data found.");
        exit;
    }

    // -------------------------------------------------------
    // AUTO-DETECT USED SPRITE COUNT
    // Scan from end, find last non-zero block
    // -------------------------------------------------------
	var _used_count = 0;
	for (var _si = 63; _si >= 0; _si--) {
	    if (_sprites[_si] == "") continue; // skip empty slots
	    var _vals     = string_split(_sprites[_si], ",");
	    var _has_data = false;
	    for (var _vi = 0; _vi < array_length(_vals); _vi++) {
	        var _trimmed = string_trim(_vals[_vi]);
	        if (_trimmed != "" && real(_trimmed) != 0) {
	            _has_data = true;
	            break;
	        }
	    }
	    if (_has_data) {
	        _used_count = _si + 1;
	        break;
	    }
	}
	if (_used_count == 0) _used_count = 1;

	
	// new in v069 (limit to detected sprites)
	// -------------------------------------------------------
	// BUILD BINARY BUFFER (sized to actual used sprites only)
	// -------------------------------------------------------
	var _buf_size   = _used_count * 64;  // e.g. 3 sprites = 192 bytes
	var _sprite_buf = buffer_create(_buf_size, buffer_fixed, 1);
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

	// Build hex blob for workspace save/load (only used sprites)
	var _hex_blob = "";
	buffer_seek(_sprite_buf, buffer_seek_start, 0);
	repeat(_buf_size) {
	    _hex_blob += decimal_to_hex(buffer_read(_sprite_buf, buffer_u8));
	}
	// end of new in v069

	// -------------------------------------------------------
	// TRIM META ARRAYS TO USED_COUNT
	// Output arrays were allocated at 64; slice down so meta never
	// carries blank-slot mode/uc state past the last used sprite.
	// -------------------------------------------------------
	array_resize(_sprite_mcs, _used_count);
	array_resize(_sprite_ucs, _used_count);

		/* PREV in V068
    var _sprite_buf = buffer_create(4096, buffer_fixed, 1);
    buffer_seek(_sprite_buf, buffer_seek_start, 0);

    for (var _si = 0; _si < 64; _si++) {
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
	    // Build hex blob for workspace save/load
    var _hex_blob = "";
    buffer_seek(_sprite_buf, buffer_seek_start, 0);
    repeat(4096) {
        _hex_blob += decimal_to_hex(buffer_read(_sprite_buf, buffer_u8));
    }
	
	*/



    // Build JSON string for preview rendering (compatible with existing node renderer)
    // Meta arrays were resized to _used_count above, so the loop must bound to
    // that length, not a hard 64, or _sprite_mcs/_sprite_ucs go out of range.
    var _json = "[";
    var _json_count = array_length(_sprite_mcs);
    for (var _si = 0; _si < _json_count; _si++) {
        if (_si > 0) _json += ",";
        _json += "{\"b\":\"" + _sprites[_si] + "\",\"mc\":" + string(_sprite_mcs[_si]) + ",\"uc\":" + string(_sprite_ucs[_si]) + "}";
    }
    _json += "]";
	
	// -------------------------------------------------------
	// CLEAN UP OLD SPRITE CACHE IF REPLACING
	// -------------------------------------------------------
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

    // -------------------------------------------------------
    // STORE INTO ASSET STRUCT
    // -------------------------------------------------------
    _asset.file   = _path;
    _asset.buffer = _sprite_buf;

    _asset.meta = {
        format      : _format,
        has_colour  : _has_colour,
        bg_col      : _bg_col,
        mc1_col     : _mc1_col,
        mc2_col     : _mc2_col,
        sprite_json : _json,
        sprite_mcs  : _sprite_mcs,
        sprite_ucs  : _sprite_ucs,
        found_count : _found_count,
        used_count  : _used_count,
        hex_blob    : _hex_blob,
        total_size  : _used_count * 64
    };

    // Parse and import the V1 compositor block, if present. Only SPRED64
    // .txt files contain compositor data; SpritePad / binary / ByteExample
    // formats have none. The parser exits early when no compositor block
    // is found in the file, so it's safe to always call.
    if (_format == "spred64") {
        scr_spred64_v2_import_v1_compositor(_asset, _path);
    }

	// Cache sprite previews to disk
	scr_asset_spr_cache_sprites(_asset, true);
    global.undo_dirty = true;
}
