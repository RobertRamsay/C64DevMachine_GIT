/// @desc Build a CHAR_SET + a 1x1 META_TILESET from a TILESYS-off CharPad CTM.
///       Called by scr_import_charpad_ctm when the project has no tile system
///       AND the user chose the "chars hold colour" (metatile) route. Produces
///       one stamp per char (stamp index == char index) so the CharPad map's
///       raw char indices are already valid stamp indices. Colour + mode live
///       in char_lut, exactly as the META_TILESET editor/compiler expect. The
///       whole CharPad map is imported as one big room (no slicing).
///
/// @param {Id.Buffer}   _buf          the loaded CTM buffer (caller owns/deletes it)
/// @param {Real}        _sz           buffer size
/// @param {Real}        _pos          cursor sitting at the map marker ($da,$bn)
/// @param {String}      _name_stem    cleaned filename stem for asset naming
/// @param {Id.Instance} _am           obj_asset_manager instance
/// @param {Real}        _char_count   number of chars parsed
/// @param {Array}       _chars_arr    char image bytes (char_count * 8)
/// @param {Array}       _mat_arr      per-char material low nibbles
/// @param {Any}         _charcol_arr  per-char colour low nibbles, or -1 if none
/// @param {Real}        _disp_mode    CTM display mode (0=TxtHR,1=TxtMC,...)
/// @param {Real}        _imp_mc_bg    default MC background colour
/// @param {Real}        _imp_mc_col1  default MC shared colour 1
/// @param {Real}        _imp_mc_col2  default MC shared colour 2
function scr_charpad_ctm_build_meta1x1(
    _buf, _sz, _pos, _name_stem, _am, _char_count, _chars_arr, _mat_arr, _charcol_arr, _disp_mode, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3) {

    var _rd_u8 = function(_b, _p) { return buffer_peek(_b, _p, buffer_u8); };

    // ---- Verify + read the map block marker ($da,$bn) ----
    var _m0 = _rd_u8(_buf, _pos);
    var _m1 = _rd_u8(_buf, _pos + 1);
    if (_m0 != 0xDA || ((_m1 & 0xF0) != 0xB0)) {
        scr_show_message("CTM meta import: bad map marker");
        exit;
    }
    _pos += 2;

    var _map_w = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);   _pos += 2;
    var _map_h = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);   _pos += 2;
    var _map_cells = _map_w * _map_h;

    if (_map_w <= 0 || _map_h <= 0) {
        scr_show_message("CTM meta import: bad map dimensions "
            + string(_map_w) + "x" + string(_map_h));
        exit;
    }
    if (_pos + _map_cells * 2 > _sz) {
        scr_show_message("CTM meta import: map block truncated");
        exit;
    }

    // ---- Read the 16-bit LSBF map, keep the low byte (char index) ----
    var _map_idx = array_create(_map_cells, 0);
    for (var _mc = 0; _mc < _map_cells; _mc++) {
        _map_idx[_mc] = _rd_u8(_buf, _pos + (_mc * 2)) & 0xFF;
    }
    _pos += _map_cells * 2;

    var _chr_mode = (_disp_mode == 1 || _disp_mode == 4) ? 1 : (_disp_mode == 2 ? 2 : 0);
    var _is_mc    = (_chr_mode == 1) ? 1 : 0;   // kept for existing MC-only checks below

    // ECM only has 64 real chars — CharPad's 256-entry export is 4 duplicate
    // preview bands (BG0-3). Only the CHAR_SET bitmap storage shrinks to 64;
    // stamp_count / stamp_data / char_lut stay at the full virtual 0-255 range
    // (1 stamp per virtual slot, matching the map's raw screen-code values,
    // which already encode band in bits 6-7). real_char = slot mod 64.
    var _store_char_count = (_chr_mode == 2) ? min(64, _char_count) : _char_count;

    // ================================================================
    // 1) BUILD CHAR_SET ASSET
    // ================================================================
    var _cs_base = scr_clamp_asset_name(_name_stem + "_chars", 15);
    var _cs_name = _cs_base;
    var _cs_k    = 2;
    while (true) {
        var _clash = false;
        for (var _uci = 0; _uci < ds_list_size(_am.asset_list); _uci++) {
            if (ds_list_find_value(_am.asset_list, _uci).name == _cs_name) {
                _clash = true;
                break;
            }
        }
        if (!_clash) break;
        _cs_name = scr_clamp_asset_name(_cs_base, 15 - (string_length(string(_cs_k)) + 1))
                 + "_" + string(_cs_k);
        _cs_k++;
    }

    var _cs_buf = buffer_create(_store_char_count * 8, buffer_fixed, 1);
    for (var _cbi = 0; _cbi < _store_char_count * 8; _cbi++) {
        buffer_poke(_cs_buf, _cbi, buffer_u8, _chars_arr[_cbi]);
    }

    // CharPad char materials -> tile_types (COLL_ADV reads these).
    var _tile_types = array_create(256, 0);
    for (var _tti = 0; _tti < _store_char_count; _tti++) {
        _tile_types[_tti] = _mat_arr[_tti] & 0x0F;
    }

    var _cs_asset = {
        type          : "CHAR_SET",
        name          : _cs_name,
        file          : "",
        address       : scr_asset_default_address("CHAR_SET"),
        buffer        : _cs_buf,
        meta          : {
            format      : "binary",
            char_count  : _store_char_count,
            total_size  : _store_char_count * 8,
            preview_surf: -1,
            mc_mode     : _chr_mode,
            mc_fg       : 1,
            mc_bg       : _imp_mc_bg,
            mc_col1     : _imp_mc_col1,
            mc_col2     : _imp_mc_col2,
            ecm_bg1     : _imp_mc_col1,
            ecm_bg2     : _imp_mc_col2,
            ecm_bg3     : _imp_ecm_bg3,
            tile_types  : _tile_types,
            undo_stack  : [],
            redo_stack  : []
        },
        load_later    : false,
        d64_filename  : "",
        linked_assets : [],
    };
    scr_asset_chr_build_preview(_cs_asset);
    ds_list_add(_am.asset_list, _cs_asset);

    // ================================================================
    // 2) BUILD 1x1 META_TILESET ASSET
    // ================================================================
    var _ts_base = scr_clamp_asset_name(_name_stem + "_tiles", 15);
    var _ts_name = _ts_base;
    var _ts_k    = 2;
    while (true) {
        var _tclash = false;
        for (var _uti = 0; _uti < ds_list_size(_am.asset_list); _uti++) {
            if (ds_list_find_value(_am.asset_list, _uti).name == _ts_name) {
                _tclash = true;
                break;
            }
        }
        if (!_tclash) break;
        _ts_name = scr_clamp_asset_name(_ts_base, 15 - (string_length(string(_ts_k)) + 1))
                 + "_" + string(_ts_k);
        _ts_k++;
    }

    var _ts_asset = {
        type          : "META_TILESET",
        name          : _ts_name,
        file          : "",
        address       : scr_asset_default_address("META_TILESET"),
        buffer        : buffer_create(1, buffer_fixed, 1),
        meta          : {},
        load_later    : false,
        d64_filename  : "",
        linked_assets : [],
    };
    scr_asset_meta_tileset_create(_ts_asset);
    var _tm = _ts_asset.meta;

    // 1x1 stamps: one stamp per char, stamp index == char index.
    _tm.stamp_w     = 1;
    _tm.stamp_h     = 1;
    _tm.stamp_count = _char_count;
    _tm.view_w      = 40;   // default C64 view window (changeable in the tileset editor)
    _tm.view_h      = 25;
    _tm.offset_x    = 0;    // view window origin (char cells), top-left by default
    _tm.offset_y    = 0;
    _tm.chr_asset   = _cs_name;
    // ECM has no map-level BG override concept (BG0-3 live directly on the
    // linked CHAR_SET) — -1 means "inherit", so BG0 correctly reads whatever
    // the charset's mc_bg is set to instead of being locked to _imp_mc_bg (0).
    _tm.map_mc_bg   = (_chr_mode == 2) ? -1 : _imp_mc_bg;
    _tm.map_mc_col1 = _imp_mc_col1;
    _tm.map_mc_col2 = _imp_mc_col2;
    _tm.map_mixed   = _is_mc;

    // stamp_data: 1 byte/cell, 1 cell/stamp -> stamp_data[N] = char N.
    _tm.stamp_data = array_create(_char_count, 0);
    for (var _si = 0; _si < _char_count; _si++) {
        _tm.stamp_data[_si] = _si & 0xFF;
    }
    // Legacy dormant per-stamp flag + per-stamp override (no overrides).
    _tm.stamp_mc       = array_create(_char_count, 0);
    _tm.stamp_override = array_create(_char_count, 0x80);

    // char_lut: per-char (mode<<4 | colour). Colour from CharPad, mode from
    // display mode. For Text-HR (disp_mode 0) every char is HR (bit4 = 0).
    _tm.char_lut     = array_create(256, 1);
    _tm.char_lut_len = _char_count;
    for (var _li = 0; _li < _char_count; _li++) {
        var _col = (_charcol_arr != -1) ? (_charcol_arr[_li] & 0x0F) : 1;
        var _mc2 = _is_mc ? 1 : 0;  // whole-project mode; CTM Text mode isn't per-char
        _tm.char_lut[_li] = (_mc2 << 4) | (_col & 0x0F);
    }

    // ================================================================
    // 3) IMPORT THE MAP: SLICE (screen-sized rooms) or BIGMAP (one room)
    // At 1x1, cols == map_w, rows == map_h; each cell's stamp index is the
    // char index directly. -1 means empty; char 0 is a real char (space),
    // so we keep it as stamp 0 rather than treating it as empty.
    //
    // If the map is bigger than one C64 screen (40x25), ask how to handle it:
    //   SLICE  = cut into 40x25 rooms, left-to-right then top-to-bottom
    //   BIGMAP = keep the whole map_w x map_h as a single oversized room
    // A map that already fits one screen skips the prompt and is one room.
    // ================================================================
    var _oversized = (_map_w > 40) || (_map_h > 25);
    var _do_slice  = false;
    if (_oversized) {
        _do_slice = scr_show_question_bool(
            "CharPad map is " + string(_map_w) + "x" + string(_map_h)
          + " (bigger than a 40x25 screen).\n\n"
          + "How should it be imported?\n"
          + "  YES = SLICE into 40x25 rooms\n"
          + "  NO  = BIGMAP (one oversized room)"
        );
    }

    _tm.maps       = [];
    _tm.map_count  = 0;
    _tm.map_bytes  = [];
    _tm.map_w      = [];
    _tm.map_h      = [];

    if (_do_slice) {
        // ---- SLICE: grid of rooms at a user-chosen size (default 40x25) ----
        // Ask for room width and height in char cells. Blank/invalid entries
        // fall back to the C64 screen default. Clamped to at least 1 and no
        // larger than the source map.
        var _room_w = get_integer("Room WIDTH in char cells (default 40):", 40);
        var _room_h = get_integer("Room HEIGHT in char cells (default 25):", 25);
        if (_room_w <= 0) {
            _room_w = 40;
        }
        if (_room_h <= 0) {
            _room_h = 25;
        }
        _room_w = clamp(floor(_room_w), 1, _map_w);
        _room_h = clamp(floor(_room_h), 1, _map_h);
        var _cols_r   = ceil(_map_w / _room_w);
        var _rows_r   = ceil(_map_h / _room_h);
        var _imported = 0;

        for (var _rr = 0; _rr < _rows_r; _rr++) {
            for (var _rc = 0; _rc < _cols_r; _rc++) {
                var _room_cells = _room_w * _room_h;
                var _room = array_create(_room_cells, -1);
                for (var _ry = 0; _ry < _room_h; _ry++) {
                    var _src_y = (_rr * _room_h) + _ry;
                    if (_src_y >= _map_h) {
                        continue;
                    }
                    for (var _rx = 0; _rx < _room_w; _rx++) {
                        var _src_x = (_rc * _room_w) + _rx;
                        if (_src_x >= _map_w) {
                            continue;
                        }
                        var _v = _map_idx[(_src_y * _map_w) + _src_x];
                        if (_v >= _char_count) {
                            _room[(_ry * _room_w) + _rx] = -1;
                        } else if (_v == 0) {
                            _room[(_ry * _room_w) + _rx] = -1;   // char 0 = blank; skip
                        } else {
                            _room[(_ry * _room_w) + _rx] = _v;
                        }
                    }
                }
                array_push(_tm.maps, _room);
                array_push(_tm.map_bytes, 0);
                array_push(_tm.map_w, _room_w);
                array_push(_tm.map_h, _room_h);
                _tm.map_count++;
                _imported++;
            }
        }
        _tm.active_map = 0;
    } else {
        // ---- BIGMAP (or already-fits): one room at full map_w x map_h ----
        var _room = array_create(_map_cells, -1);
        for (var _ci = 0; _ci < _map_cells; _ci++) {
            var _v = _map_idx[_ci];
            if (_v >= _char_count) {
                _room[_ci] = -1;
            } else if (_v == 0) {
                _room[_ci] = -1;   // CharPad char 0 = blank; metamap is a populator, so skip it
            } else {
                _room[_ci] = _v;
            }
        }
        array_push(_tm.maps, _room);
        array_push(_tm.map_bytes, 0);
        array_push(_tm.map_w, _map_w);
        array_push(_tm.map_h, _map_h);
        _tm.map_count  = 1;
        _tm.active_map = 0;
    }

    // Pre-stamp the viewer's size-key so its "stamp size changed -> clear all
    // maps" guard does NOT fire on first open and wipe the imported Map 0. The
    // key must match what the viewer computes: string(stamp_w) + "x" + stamp_h.
    _tm.map_size_key = string(_tm.stamp_w) + "x" + string(_tm.stamp_h);

    ds_list_add(_am.asset_list, _ts_asset);
    global.undo_dirty = true;

    scr_show_message("CTM meta import OK (1x1): " + string(_char_count) + " chars, "
        + string(_char_count) + " stamps, "
        + string(_map_w) + "x" + string(_map_h) + " map");
}
