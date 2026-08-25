/// REU image/manifest support. LOAD_REU owns the exported placement of assets;
/// MACRO_REU uses scr_reu_resolve() when it is in ASSET mode.

function scr_reu_find_asset(_name) {
    if (!instance_exists(obj_asset_manager)) return undefined;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.name == _name) return _a;
    }
    return undefined;
}

function scr_reu_manifest_count() {
    if (!instance_exists(obj_asset_manager)) return 0;
    var _count = 0;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        if (ds_list_find_value(_am.asset_list, _i).type == "LOAD_REU") _count++;
    }
    return _count;
}

function scr_reu_get_manifest() {
    if (!instance_exists(obj_asset_manager)) return undefined;
    var _found = undefined;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _asset = ds_list_find_value(_am.asset_list, _i);
        if (_asset.type != "LOAD_REU") continue;
        if (!is_undefined(_found)) return undefined; // More than one is invalid.
        _found = _asset;
    }
    return _found;
}

/// Size/address only — same rules as scr_reu_asset_payload() but WITHOUT
/// building the byte buffer. Callers that only need placement (repack,
/// resolve, the REU memory bar, the asset panel row) must use this: the
/// payload builder allocates and fills a ~10KB buffer per bitmap, and at
/// draw-event frequency that dominates the frame.
function scr_reu_asset_size(_asset) {
    if (is_undefined(_asset)) return { size: 0, c64_address: 0 };

    // Text is edited as source text, so make sure its byte buffer is current.
    if (_asset.type == "TEXT_DATA") scr_asset_text_flush(_asset);

    if (_asset.type == "SFX_DATA") {
        var _sfx_total = 0;
        var _ins = variable_struct_exists(_asset.meta, "instruments") ? _asset.meta.instruments : [];
        for (var _ii = 0; _ii < array_length(_ins); _ii++) {
            _sfx_total += array_length(scr_sfx_data_instrument_blob(_ins[_ii]));
        }
        return { size: max(1, _sfx_total), c64_address: _asset.address };
    }

    if (!buffer_exists(_asset.buffer)) return { size: 0, c64_address: _asset.address };
    var _src      = _asset.buffer;
    var _src_size = buffer_get_size(_src);
    var _start    = 0;
    var _size     = _src_size;

    if (_asset.type == "SID_MUSIC" && _src_size >= 10) {
        var _header = (buffer_peek(_src, 6, buffer_u8) << 8) | buffer_peek(_src, 7, buffer_u8);
        if (_header != 0x76 && _header != 0x7C) _header = 0x76;
        var _raw_load = (buffer_peek(_src, 8, buffer_u8) << 8) | buffer_peek(_src, 9, buffer_u8);
        _start = (_raw_load == 0) ? _header + 2 : _header;
        _size = max(0, _src_size - _start);
    } else if (_asset.type == "SID_SFX" && _src_size > 2) {
        if (buffer_peek(_src, 0, buffer_u8) == (_asset.address & 0xFF)
        &&  buffer_peek(_src, 1, buffer_u8) == ((_asset.address >> 8) & 0xFF)) {
            _size -= 2;
        }
    } else if (_asset.type == "CHAR_SET") {
        _size = min(_size, 2048);
    } else if (_asset.type == "BITMAP" || _asset.type == "BITMAP_KLA") {
        var _br = scr_bmp_regions(_asset.address);
        var _span_end = max(_br.bmp_addr + 8000, max(_br.scr_addr + 1000, _br.col_addr + 1000));
        return { size: _span_end - _asset.address, c64_address: _asset.address };
    }

    return { size: _size, c64_address: _asset.address };
}

function scr_reu_asset_payload(_asset) {
    if (is_undefined(_asset)) return { buffer: -1, size: 0, c64_address: 0 };

    // Text is edited as source text, so make sure its runtime byte buffer is current.
    if (_asset.type == "TEXT_DATA") scr_asset_text_flush(_asset);

    if (_asset.type == "SFX_DATA") {
        var _bytes = [];
        var _ins = variable_struct_exists(_asset.meta, "instruments") ? _asset.meta.instruments : [];
        for (var _ii = 0; _ii < array_length(_ins); _ii++) {
            var _blob = scr_sfx_data_instrument_blob(_ins[_ii]);
            for (var _bi = 0; _bi < array_length(_blob); _bi++) array_push(_bytes, _blob[_bi]);
        }
        var _out_sfx = buffer_create(max(1, array_length(_bytes)), buffer_fixed, 1);
        buffer_fill(_out_sfx, 0, buffer_u8, 0, max(1, array_length(_bytes)));
        for (var _i = 0; _i < array_length(_bytes); _i++) buffer_poke(_out_sfx, _i, buffer_u8, _bytes[_i]);
        return { buffer: _out_sfx, size: max(1, array_length(_bytes)), c64_address: _asset.address };
    }

    if (!buffer_exists(_asset.buffer)) return { buffer: -1, size: 0, c64_address: _asset.address };
    var _src = _asset.buffer;
    var _src_size = buffer_get_size(_src);
    var _start = 0;
    var _size = _src_size;

    if (_asset.type == "SID_MUSIC" && _src_size >= 10) {
        var _header = (buffer_peek(_src, 6, buffer_u8) << 8) | buffer_peek(_src, 7, buffer_u8);
        if (_header != 0x76 && _header != 0x7C) _header = 0x76;
        var _raw_load = (buffer_peek(_src, 8, buffer_u8) << 8) | buffer_peek(_src, 9, buffer_u8);
        _start = (_raw_load == 0) ? _header + 2 : _header;
        _size = max(0, _src_size - _start);
    } else if (_asset.type == "SID_SFX" && _src_size > 2) {
        if (buffer_peek(_src, 0, buffer_u8) == (_asset.address & 0xFF)
        &&  buffer_peek(_src, 1, buffer_u8) == ((_asset.address >> 8) & 0xFF)) {
            _start = 2;
            _size -= 2;
        }
    } else if (_asset.type == "CHAR_SET") {
        _size = min(_size, 2048);
    } else if (_asset.type == "BITMAP" || _asset.type == "BITMAP_KLA") {
        // Store the same three runtime regions as the PRG injector. The buffer
        // is a C64-addressed span so one FETCH recreates their final layout.
        var _br = scr_bmp_regions(_asset.address);
        var _span_end = max(_br.bmp_addr + 8000, max(_br.scr_addr + 1000, _br.col_addr + 1000));
        var _span_size = _span_end - _asset.address;
        var _out_bmp = buffer_create(max(1, _span_size), buffer_fixed, 1);
        buffer_fill(_out_bmp, 0, buffer_u8, 0, max(1, _span_size));
        for (var _i = 0; _i < 8000; _i++) buffer_poke(_out_bmp, (_br.bmp_addr - _asset.address) + _i, buffer_u8, (_i + 2 < _src_size) ? buffer_peek(_src, _i + 2, buffer_u8) : 0);
        for (var _i = 0; _i < 1000; _i++) buffer_poke(_out_bmp, (_br.scr_addr - _asset.address) + _i, buffer_u8, (_i + 8002 < _src_size) ? buffer_peek(_src, _i + 8002, buffer_u8) : 0);
        for (var _i = 0; _i < 1000; _i++) buffer_poke(_out_bmp, (_br.col_addr - _asset.address) + _i, buffer_u8, (_i + 9002 < _src_size) ? buffer_peek(_src, _i + 9002, buffer_u8) : 0);
        return { buffer: _out_bmp, size: _span_size, c64_address: _asset.address };
    }

    var _out = buffer_create(max(1, _size), buffer_fixed, 1);
    buffer_fill(_out, 0, buffer_u8, 0, max(1, _size));
    if (_size > 0) buffer_copy(_src, _start, _size, _out, 0);
    return { buffer: _out, size: _size, c64_address: _asset.address };
}

function scr_reu_repack(_manifest) {
    if (is_undefined(_manifest)) return;
    if (!variable_struct_exists(_manifest, "linked_assets")) _manifest.linked_assets = [];
    var _links = _manifest.linked_assets;
    var _sizes = array_create(array_length(_links), 0);
    var _placed = [];

    // Manual ranges reserve their positions first. Automatic entries then use
    // the first aligned gap that does not intersect a reservation.
    for (var _i = 0; _i < array_length(_links); _i++) {
        var _asset = scr_reu_find_asset(_links[_i].asset_name);
        _sizes[_i] = scr_reu_asset_size(_asset).size;
        if (!variable_struct_exists(_links[_i], "auto_pack")) _links[_i].auto_pack = true;
        if (!variable_struct_exists(_links[_i], "reu_address")) _links[_i].reu_address = 0x100;
        _links[_i].reu_conflict = false;
        if (!_links[_i].auto_pack) array_push(_placed, { s: real(_links[_i].reu_address), e: real(_links[_i].reu_address) + _sizes[_i], index: _i });
    }

    var _cursor = 0x100;
    for (var _i = 0; _i < array_length(_manifest.linked_assets); _i++) {
        var _link = _links[_i];
        if (_link.auto_pack) {
            var _candidate = ((_cursor + 0xFF) div 0x100) * 0x100;
            var _retry = true;
            while (_retry) {
                _retry = false;
                for (var _pi = 0; _pi < array_length(_placed); _pi++) {
                    var _r = _placed[_pi];
                    if (_candidate < _r.e && _candidate + _sizes[_i] > _r.s) {
                        _candidate = ((_r.e + 0xFF) div 0x100) * 0x100;
                        _retry = true;
                        break;
                    }
                }
            }
            _link.reu_address = _candidate;
            array_push(_placed, { s: _candidate, e: _candidate + _sizes[_i], index: _i });
        }
        _cursor = max(_cursor, real(_link.reu_address) + _sizes[_i]);
    }

    // Manual/manual overlaps are retained by design, but flagged so export
    // and the viewer can report the invalid manifest instead of hiding it.
    for (var _a = 0; _a < array_length(_links); _a++) {
        for (var _b = _a + 1; _b < array_length(_links); _b++) {
            var _as = real(_links[_a].reu_address), _ae = _as + _sizes[_a];
            var _bs = real(_links[_b].reu_address), _be = _bs + _sizes[_b];
            if (_as < _be && _ae > _bs) { _links[_a].reu_conflict = true; _links[_b].reu_conflict = true; }
        }
    }
    _manifest.reu_used = _cursor;
}

function scr_reu_resolve(_manifest_name, _asset_name) {
    var _none = { found: false, c64_address: 0, reu_address: 0, size: 0, manifest: undefined, asset: undefined };
    var _manifest = scr_reu_find_asset(_manifest_name);
    if (is_undefined(_manifest) || _manifest.type != "LOAD_REU") return _none;
    scr_reu_repack(_manifest);
    var _links = variable_struct_exists(_manifest, "linked_assets") ? _manifest.linked_assets : [];
    for (var _i = 0; _i < array_length(_links); _i++) {
        if (_links[_i].asset_name != _asset_name) continue;
        var _asset = scr_reu_find_asset(_asset_name);
        if (is_undefined(_asset)) return _none;
        var _info = scr_reu_asset_size(_asset);
        return { found: true, c64_address: _info.c64_address, reu_address: real(_links[_i].reu_address), size: _info.size, manifest: _manifest, asset: _asset };
    }
    return _none;
}

function scr_reu_asset_is_external(_asset_name) {
    if (!instance_exists(obj_asset_manager)) return false;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _m = ds_list_find_value(_am.asset_list, _i);
        if (_m.type != "LOAD_REU" || !variable_struct_exists(_m, "linked_assets")) continue;
        for (var _j = 0; _j < array_length(_m.linked_assets); _j++) {
            if (_m.linked_assets[_j].asset_name == _asset_name) return true;
        }
    }
    return false;
}

function scr_reu_build_images(_out_dir) {
    global.reu_last_image = "";
    global.reu_last_used  = 0;
    global.reu_build_error = "";

    if (!instance_exists(obj_asset_manager)) return [];
    var _manifest_count = scr_reu_manifest_count();
    if (_manifest_count > 1) {
        global.reu_build_error = "Only one LOAD_REU asset is supported per project.";
        show_debug_message("LOAD_REU: build blocked because the project contains " + string(_manifest_count) + " manifests");
        return [];
    }
    var _paths = [];
    var _am = obj_asset_manager;
    for (var _mi = 0; _mi < ds_list_size(_am.asset_list); _mi++) {
        var _m = ds_list_find_value(_am.asset_list, _mi);
        if (_m.type != "LOAD_REU") continue;
        scr_reu_repack(_m);
        var _image_size = variable_struct_exists(_m, "reu_size") ? real(_m.reu_size) : 0x1000000;
        _image_size = clamp(_image_size, 0x20000, 0x1000000);
        var _img = buffer_create(_image_size, buffer_fixed, 1);
        buffer_fill(_img, 0, buffer_u8, 0, _image_size);
        var _sig = "C64DMREU";
        for (var _si = 1; _si <= string_length(_sig); _si++) buffer_poke(_img, _si - 1, buffer_u8, ord(string_char_at(_sig, _si)));
        buffer_poke(_img, 8, buffer_u8, 1); // format version
        var _links = variable_struct_exists(_m, "linked_assets") ? _m.linked_assets : [];
        var _invalid = false;
        for (var _vi = 0; _vi < array_length(_links); _vi++) {
            if (variable_struct_exists(_links[_vi], "reu_conflict") && _links[_vi].reu_conflict) _invalid = true;
        }
        if (_invalid) {
            global.reu_build_error = "LOAD_REU contains overlapping manual ranges.";
            show_debug_message("LOAD_REU: not exporting " + _m.name + " because manual ranges overlap");
            buffer_delete(_img);
            continue;
        }
        buffer_poke(_img, 9, buffer_u8, array_length(_links) & 0xFF);
        buffer_poke(_img, 10, buffer_u8, (array_length(_links) >> 8) & 0xFF);
        var _checksum = 0;
        for (var _li = 0; _li < array_length(_links); _li++) {
            var _asset = scr_reu_find_asset(_links[_li].asset_name);
            var _payload = scr_reu_asset_payload(_asset);
            var _at = real(_links[_li].reu_address);
            if (_payload.size > 0 && _at >= 0x100 && _at + _payload.size <= _image_size) {
                buffer_copy(_payload.buffer, 0, _payload.size, _img, _at);
                for (var _bi = 0; _bi < _payload.size; _bi++) _checksum = (_checksum + buffer_peek(_payload.buffer, _bi, buffer_u8)) & 0xFFFFFFFF;
            } else {
                show_debug_message("LOAD_REU: skipped " + _links[_li].asset_name + " (outside image or empty)");
            }
            if (buffer_exists(_payload.buffer)) buffer_delete(_payload.buffer);
        }
        buffer_poke(_img, 12, buffer_u32, _image_size);
        buffer_poke(_img, 16, buffer_u32, _checksum);
        var _name = variable_struct_exists(_m, "reu_filename") ? string(_m.reu_filename) : string(_m.name) + ".reu";
        if (string_length(_name) < 4 || string_lower(string_copy(_name, string_length(_name) - 3, 4)) != ".reu") _name += ".reu";
        var _path = _out_dir + _name;
        buffer_save(_img, _path);
        buffer_delete(_img);
        array_push(_paths, _path);
        global.reu_last_image = _path;
        global.reu_last_used  = clamp(real(_m.reu_used), 0x100, _image_size);
        show_debug_message("LOAD_REU: wrote " + _path);
    }
    return _paths;
}
