/// @desc Import a CharPad project from its RAW exported binaries into a new
///       CHAR_SET asset + a new META_TILESET asset (auto-linked).
///
/// User picks ONE file (the *Chars.bin). All siblings — CharAttribs, Tiles,
/// and every SubMap — are found automatically by scanning that file's folder.
/// No repeated prompting. (A single fallback dialog appears only if Tiles or
/// CharAttribs can't be found in the folder.)
///
/// CharPad names files with spaces/brackets, and the bracketed parts drift
/// between exports, e.g.:
///   burger - Chars.bin              OR  burger - Chars (2x2), 8bpc.bin
///   burger - CharAttribs_L1.bin
///   burger - Tiles.bin              OR  burger - Tiles (2x2), 8bpc.bin
///   burger - Map (20x13), 8bpc.bin                         (single screen)
///   burger - (8bpc, 20x13) [00,00] SubMap.bin ...          (multi screen)
/// so siblings are matched by stable ROLE TOKENS (Chars/Tiles/Map/SubMap/
/// CharAttribs) gated on the " - " separator, NOT by fixed suffixes.
///
/// Model mapping:
///   charset bytes      -> CHAR_SET.buffer
///   attrib low nibble  -> char_lut colour (bits 0-3)
///   attrib colour >= 8 -> char_lut MC bit (bit 4)   [C64 hardware rule]
///   attrib high nibble -> CHAR_SET.meta.tile_types (material 0-15 = T0-T16)
///   tile cells         -> META_TILESET.stamp_data (1 byte/cell)
///   submaps (in-range) -> META_TILESET.maps[0..]
function scr_import_charpad_raw() {

    // Resolve the asset manager instance explicitly — this function may be
    // called from another object's event, so we never rely on ambient scope.
    if (!instance_exists(obj_asset_manager)) { scr_show_message("CharPad import: asset manager not found"); exit; }
    var _am = obj_asset_manager;

    // ---- Tunables (CharPad raw exports don't carry these) ----
    var _imp_stamp_w   = 2;     // CharPad tile width  in chars
    var _imp_stamp_h   = 2;     // CharPad tile height in chars
    var _imp_mc_bg     = 0;     // $D021 background (CharPad Bg 00)
    var _imp_mc_col1   = 1;     // $D022 (M1)  (CharPad M1 01 = white)
    var _imp_mc_col2   = 10;    // $D023 (M2)  (CharPad M2 0A = red)

    // ---- 1) Pick the Chars.bin file ----
    var _chars_path = get_open_filename("CharPad Chars|*Chars*.bin;*.bin", "");
    if (_chars_path == "") exit;

    var _dir = filename_dir(_chars_path) + "/";

    // Clean stem for naming the new assets (display only). Strip from the first
    // " - " onward if present, else from "Chars", so bracketed junk is dropped.
    var _name_stem = filename_name(_chars_path);
    var _np = string_pos(" - ", _name_stem);
    if (_np > 0) {
        _name_stem = string_trim(string_copy(_name_stem, 1, _np - 1));
    } else {
        var _np2 = string_pos("Chars", _name_stem);
        if (_np2 > 0) _name_stem = string_trim(string_copy(_name_stem, 1, _np2 - 1));
    }
    _name_stem = string_replace_all(_name_stem, " ", "_");
    _name_stem = string_replace_all(_name_stem, "-", "");
    while (string_pos("__", _name_stem) > 0) _name_stem = string_replace_all(_name_stem, "__", "_");
    if (_name_stem == "" || _name_stem == "_") _name_stem = "charpad";

    // ---- helper: find a CharPad sibling by ROLE TOKEN, tolerant of the
    //      volatile bracketed junk CharPad injects, e.g.
    //        "proj - Tiles (2x2), 8bpc.bin"   "proj - Map (20x13), 8bpc.bin"
    //      A file qualifies if it: ends in .bin, contains " - " (CharPad's
    //      project-name separator), contains _needle, and does NOT contain
    //      _exclude (pass "" for no exclusion — used to stop "Map" matching
    //      "SubMap"). _prefer, if non-empty, makes a filename containing it win
    //      over a plain match (used to favour CharAttribs_L1 over _M).
    var _find_one = function(_dir, _needle, _exclude, _prefer) {
        var _f = file_find_first(_dir + "*", fa_none);
        var _hit  = "";
        var _pref = "";
        while (_f != "") {
            var _is_bin = (string_pos(".bin", _f) > 0);
            var _has_sep = (string_pos(" - ", _f) > 0);
            var _has_needle = (string_pos(_needle, _f) > 0);
            var _has_excl = (_exclude != "" && string_pos(_exclude, _f) > 0);
            if (_is_bin && _has_sep && _has_needle && !_has_excl) {
                if (_prefer != "" && string_pos(_prefer, _f) > 0) {
                    _pref = _f;            // preferred variant — remember it
                } else if (_hit == "") {
                    _hit = _f;             // first plain match — fallback
                }
            }
            _f = file_find_next();
        }
        file_find_close();
        // Preferred variant wins if we found one, else the first plain match.
        if (_pref != "") return _pref;
        return _hit;
    };

    // ---- helper: load a raw file into a u8 array, prompting if missing ----
    var _load_raw = function(_path, _label) {
        if (!file_exists(_path)) {
            _path = get_open_filename("CharPad " + _label + "|*.bin", "");
            if (_path == "" || !file_exists(_path)) return -1;
        }
        var _b = buffer_load(_path);
        if (!buffer_exists(_b)) return -1;
        var _sz  = buffer_get_size(_b);
        var _arr = array_create(_sz, 0);
        for (var _i = 0; _i < _sz; _i++) _arr[_i] = buffer_peek(_b, _i, buffer_u8);
        buffer_delete(_b);
        return _arr;
    };

    // ---- helper: parse "(8bpc, 20x13)" -> [w,h] from a CharPad filename.
    //      Returns [-1,-1] if no dimension token is present. Used only for a
    //      sanity-check debug warning; map height is taken from the byte count.
    var _parse_dims = function(_fname) {
        var _op = string_pos("(", _fname);
        if (_op == 0) return [-1, -1];
        var _cp = string_pos(")", _fname);
        if (_cp == 0 || _cp <= _op) return [-1, -1];
        var _inner = string_copy(_fname, _op + 1, _cp - _op - 1); // "8bpc, 20x13"
        var _xp = string_pos("x", _inner);
        if (_xp == 0) return [-1, -1];
        // Walk left from the 'x' to collect the width digits.
        var _w_str = "";
        var _wi = _xp - 1;
        while (_wi >= 1) {
            var _ch = string_char_at(_inner, _wi);
            if (_ch >= "0" && _ch <= "9") {
                _w_str = _ch + _w_str;
                _wi--;
            } else {
                break;
            }
        }
        // Walk right from the 'x' to collect the height digits.
        var _h_str = "";
        var _hi = _xp + 1;
        var _inlen = string_length(_inner);
        while (_hi <= _inlen) {
            var _ch2 = string_char_at(_inner, _hi);
            if (_ch2 >= "0" && _ch2 <= "9") {
                _h_str = _h_str + _ch2;
                _hi++;
            } else {
                break;
            }
        }
        if (_w_str == "" || _h_str == "") return [-1, -1];
        return [real(_w_str), real(_h_str)];
    };

    // ---- 2) Load charset, attribs, tiles (siblings found by role token) ----
    var _chars_arr = _load_raw(_chars_path, "Chars");
    if (_chars_arr == -1) { scr_show_message("CharPad import: Chars file failed to load"); exit; }
    var _char_count = array_length(_chars_arr) div 8;
    if (_char_count <= 0) { scr_show_message("CharPad import: charset empty"); exit; }

    // CharAttribs may ship as _L1 (primary colour/material layer) and/or _M.
    // Prefer _L1; fall back to whatever attrib file exists.
    var _attr_name = _find_one(_dir, "CharAttribs", "", "CharAttribs_L1");
    var _attr_arr  = (_attr_name != "") ? _load_raw(_dir + _attr_name, "CharAttribs") : -1;

    // Tiles: match the "Tiles" role token, not "Tiles.bin" — CharPad may insert
    // "(2x2), 8bpc" between the word and the extension.
    var _tiles_name = _find_one(_dir, "Tiles", "", "");
    if (_tiles_name == "") { scr_show_message("CharPad import: Tiles file not found"); exit; }
    var _tiles_arr = _load_raw(_dir + _tiles_name, "Tiles");
    if (_tiles_arr == -1) { scr_show_message("CharPad import: Tiles file failed to load"); exit; }

    var _cells_per = _imp_stamp_w * _imp_stamp_h;
    var _stamp_count = array_length(_tiles_arr) div _cells_per;
    if (_stamp_count <= 0) { scr_show_message("CharPad import: no tiles found"); exit; }

    // ---- 3) Build CHAR_SET asset ----
    var _cs_base = _name_stem + "_chars";
    var _cs_name = _cs_base;
    var _cs_k = 2;
    while (true) {
        var _clash = false;
        for (var _uci = 0; _uci < ds_list_size(_am.asset_list); _uci++) {
            if (ds_list_find_value(_am.asset_list, _uci).name == _cs_name) { _clash = true; break; }
        }
        if (!_clash) break;
        _cs_name = _cs_base + "_" + string(_cs_k);
        _cs_k++;
    }

    var _cs_buf = buffer_create(_char_count * 8, buffer_fixed, 1);
    for (var _bi = 0; _bi < _char_count * 8; _bi++) {
        buffer_poke(_cs_buf, _bi, buffer_u8, _chars_arr[_bi]);
    }

    // tile_types from attrib material nibble (0-15 -> T0-T16, 0 = none)
    var _tile_types = array_create(256, 0);
    if (_attr_arr != -1) {
        for (var _ti = 0; _ti < min(_char_count, array_length(_attr_arr)); _ti++) {
            _tile_types[_ti] = (_attr_arr[_ti] >> 4) & 0x0F;
        }
    }

    var _cs_asset = {
        type          : "CHAR_SET",
        name          : _cs_name,
        file          : "",
        address       : scr_asset_default_address("CHAR_SET"),
        buffer        : _cs_buf,
        meta          : {
            format      : "binary",
            char_count  : _char_count,
            total_size  : _char_count * 8,
            preview_surf: -1,
            mc_mode     : 1,            // multicolour
            mc_fg       : 1,
            mc_bg       : _imp_mc_bg,
            mc_col1     : _imp_mc_col1,
            mc_col2     : _imp_mc_col2,
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

    // ---- 4) Build META_TILESET asset ----
    var _ts_base = _name_stem + "_tiles";
    var _ts_name = _ts_base;
    var _ts_k = 2;
    while (true) {
        var _tclash = false;
        for (var _uti = 0; _uti < ds_list_size(_am.asset_list); _uti++) {
            if (ds_list_find_value(_am.asset_list, _uti).name == _ts_name) { _tclash = true; break; }
        }
        if (!_tclash) break;
        _ts_name = _ts_base + "_" + string(_ts_k);
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

    _tm.stamp_w     = _imp_stamp_w;
    _tm.stamp_h     = _imp_stamp_h;
    _tm.stamp_count = _stamp_count;
    _tm.chr_asset   = _cs_name;        // auto-link the charset
    _tm.map_mc_bg   = _imp_mc_bg;
    _tm.map_mc_col1 = _imp_mc_col1;
    _tm.map_mc_col2 = _imp_mc_col2;
    _tm.map_mixed   = 1;   // CharPad multicolour project -> MIXED mode, not HR

    // stamp_data: 1 byte/cell, direct from Tiles.bin
    _tm.stamp_data = array_create(_stamp_count * _cells_per, 0);
    for (var _si = 0; _si < _stamp_count * _cells_per; _si++) {
        _tm.stamp_data[_si] = _tiles_arr[_si] & 0xFF;
    }
    _tm.stamp_mc       = array_create(_stamp_count, 0);     // dormant legacy
    _tm.stamp_override = array_create(_stamp_count, 0x80);  // none

    // char_lut: colour (bits0-3) + MC bit (bit4) from attrib; default white(1)
    _tm.char_lut     = array_create(256, 1);
    _tm.char_lut_len = _char_count;
    if (_attr_arr != -1) {
        for (var _ci = 0; _ci < min(_char_count, array_length(_attr_arr)); _ci++) {
            var _col = _attr_arr[_ci] & 0x0F;
            var _mc  = (_col >= 8) ? 1 : 0;    // C64 rule: colour bit3 = MC
            _tm.char_lut[_ci] = (_mc << 4) | (_col & 0x0F);
        }
    }

    // ---- 5) Load submaps as maps[], auto-skipping out-of-range ones ----
    _tm.maps      = [];
    _tm.map_count = 0;
    _tm.map_bytes = [];
    var _imported = 0;
    var _skipped  = 0;

    // Collect map files by role token, tolerant of bracketed junk. Multi-screen
    // projects export several "... SubMap.bin"; single-screen exports one
    // "... Map.bin". Match SubMap FIRST; only if none exist, fall back to Map
    // files (excluding SubMap so "Map" doesn't double-catch them).
    var _submap_files = [];
    var _ff = file_find_first(_dir + "*", fa_none);
    while (_ff != "") {
        var _is_bin  = (string_pos(".bin", _ff) > 0);
        var _has_sep = (string_pos(" - ", _ff) > 0);
        if (_is_bin && _has_sep && string_pos("SubMap", _ff) > 0) {
            array_push(_submap_files, _ff);
        }
        _ff = file_find_next();
    }
    file_find_close();

    if (array_length(_submap_files) == 0) {
        var _fm = file_find_first(_dir + "*", fa_none);
        while (_fm != "") {
            var _m_bin  = (string_pos(".bin", _fm) > 0);
            var _m_sep  = (string_pos(" - ", _fm) > 0);
            var _m_map  = (string_pos("Map", _fm) > 0);
            var _m_sub  = (string_pos("SubMap", _fm) > 0);
            if (_m_bin && _m_sep && _m_map && !_m_sub) {
                array_push(_submap_files, _fm);
            }
            _fm = file_find_next();
        }
        file_find_close();
    }
    array_sort(_submap_files, true);  // "[00,00]".."[08,00]" sort lexically in order

    for (var _smi = 0; _smi < array_length(_submap_files); _smi++) {
        var _mname = _submap_files[_smi];
        var _marr  = _load_raw(_dir + _mname, "SubMap");
        if (_marr == -1) continue;
        // Validate: every tile index < stamp_count, else not tilemap data.
        var _maxidx = 0;
        for (var _mk = 0; _mk < array_length(_marr); _mk++) {
            if (_marr[_mk] > _maxidx) _maxidx = _marr[_mk];
        }
        if (_maxidx >= _stamp_count) {
            show_debug_message("CharPad import: skipping '" + _mname
                + "' (max idx " + string(_maxidx) + " >= stamp_count " + string(_stamp_count) + ")");
            _skipped++;
            continue;
        }

        // Sanity check only: if the filename carries a "(WxH)" token, warn when
        // it disagrees with the actual byte count. Width is always a full screen
        // and height derives from length downstream, so we don't store these.
        var _dims = _parse_dims(_mname);
        if (_dims[0] > 0 && _dims[1] > 0 && (_dims[0] * _dims[1] != array_length(_marr))) {
            show_debug_message("CharPad import: '" + _mname + "' filename dim "
                + string(_dims[0]) + "x" + string(_dims[1]) + " (" + string(_dims[0] * _dims[1])
                + ") != bytes " + string(array_length(_marr)) + " — trusting byte count");
        }

        array_push(_tm.maps, _marr);
        array_push(_tm.map_bytes, 0);
        _tm.map_count++;
        _imported++;
    }
    if (_tm.map_count > 0) _tm.active_map = 0;

    ds_list_add(_am.asset_list, _ts_asset);
    global.undo_dirty = true;

    scr_show_message("CharPad import OK: " + string(_char_count) + " chars, "
        + string(_stamp_count) + " tiles, "
        + string(_imported) + " maps"
        + (_skipped > 0 ? " (" + string(_skipped) + " skipped)" : ""));
}