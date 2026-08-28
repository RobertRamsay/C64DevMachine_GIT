/// @desc Import a CharPad CTM (v9) project file into a new CHAR_SET asset
///       + a new META_TILESET asset (auto-linked). Single-file alternative
///       to scr_import_charpad_raw — user picks ONE .ctm and everything
///       (charset, attribs, tiles, map) is parsed from it.
///
///       NEW: if the project has no tile system (TILESYS off), the map stores
///       raw char indices (1x1 chars). In that case we divert to
///       scr_charpad_ctm_build_map, which produces a CHAR_SET + a single
///       MAP_DATA asset for the old (flat) map system.
///
/// CTM9 layout (see Subchrist CTM v9 spec):
///   header 19 bytes -> DISP_MODE, COLR_METH, TILESYS flag, VIC colours
///   block $da,$b0   -> char images (8 bytes each, CHARCNT+1 images)
///   block $da,$b1   -> char materials (1 byte each)  [high nibble unused here]
///   block $da,$bn   -> per-char colours (only if COLR_METH==2)
///   block $da,$bn   -> tile data (16 bits/cell, TILEWID*TILEHEI*TILECNT)  [if TILESYS]
///   block $da,$bn   -> per-tile colours (if TILESYS && COLR_METH==1)
///   block $da,$bn   -> tile tags  (if TILESYS)
///   block $da,$bn   -> tile names (if TILESYS, zero-terminated strings)
///   block $da,$bn   -> map data (16 bits/cell, MAPWID*MAPHEI)
function scr_import_charpad_ctm() {

    if (!instance_exists(obj_asset_manager)) { scr_show_message("CTM import: asset manager not found"); exit; }
    var _am = obj_asset_manager;

    // ---- Defaults, overwritten below from the v9 header's VIC colours
    // (bytes 12-15) once the file is loaded and parsed. v7/v8 CTM files have
    // a shorter header without this block, so they keep these fallbacks. ----
    var _imp_mc_bg   = 0;
    var _imp_mc_col1 = 1;
    var _imp_mc_col2 = 10;
    var _imp_ecm_bg3 = 3;

    // ---- 1) Pick the .ctm file ----
    var _path = get_open_filename("CharPad CTM|*.ctm", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. This is why ESC
    // only failed after SOME asset operations: scr_asset_sid_import already did
    // this, every other importer did not.
    io_clear();
    if (_path == "") exit;
    if (!file_exists(_path)) { scr_show_message("CTM import: file not found"); exit; }

    var _buf = buffer_load(_path);
    if (!buffer_exists(_buf)) { scr_show_message("CTM import: load failed"); exit; }
    var _sz = buffer_get_size(_buf);

    // Clean stem for naming.
    var _name_stem = filename_name(_path);
    var _dp = string_last_pos(".", _name_stem);
    if (_dp > 0) _name_stem = string_copy(_name_stem, 1, _dp - 1);
    _name_stem = string_replace_all(_name_stem, " ", "_");
    _name_stem = string_replace_all(_name_stem, "-", "");
    while (string_pos("__", _name_stem) > 0) _name_stem = string_replace_all(_name_stem, "__", "_");
    if (_name_stem == "" || _name_stem == "_") _name_stem = "charpad";

    // ---- cursor-based readers over the loaded buffer ----
    var _pos = 0;
    var _rd_u8 = function(_b, _p) { return buffer_peek(_b, _p, buffer_u8); };

    // ---- 2) Parse header (19 bytes) ----
    if (_sz < 19) { buffer_delete(_buf); scr_show_message("CTM import: file too small"); exit; }
    var _id0 = _rd_u8(_buf, 0);
    var _id1 = _rd_u8(_buf, 1);
    var _id2 = _rd_u8(_buf, 2);
    var _ver = _rd_u8(_buf, 3);
    // "CTM" = 67,84,77
    if (_id0 != 67 || _id1 != 84 || _id2 != 77) {
        buffer_delete(_buf);
        scr_show_message("CTM import: not a CTM file");
        exit;
    }
    if (_ver != 9 && _ver > 8) {
        show_debug_message("CTM import: version " + string(_ver) + " (expected 9) — attempting anyway");
    }

    var _disp_mode = _rd_u8(_buf, 4);   // 0=Text_HR,1=Text_MC,2=Text_EC,3=Bmp_HR,4=Bmp_MC
    var _colr_meth = _rd_u8(_buf, 5);   // 0=per-project,1=per-tile,2=per-char
    var _flags     = _rd_u8(_buf, 6);
    var _tilesys   = (_flags & 0x01);   // low nibble bit0

    var _is_bmp_hr = (_disp_mode == 3);
    var _is_bmp_mc = (_disp_mode == 4);

    // ---- v9 header VIC colours (bytes 12-15): BG0/d021, BG1/d022(mc1),
    // BG2/d023(mc2), BG3/d024 — confirmed by hex-comparing a known project
    // against its saved Colours panel values. Only present in the v9 19-byte
    // header; v7/v8 have shorter headers without this block.
    if (_ver == 9) {
        _imp_mc_bg   = _rd_u8(_buf, 12);
        _imp_mc_col1 = _rd_u8(_buf, 13);
        _imp_mc_col2 = _rd_u8(_buf, 14);
        _imp_ecm_bg3 = _rd_u8(_buf, 15);
    }

    _pos = 19;   // start of first block

    // ---- helper: read & verify a block marker ($da, $bn) ----
    var _read_marker = function(_b, _p) {
        var _m0 = buffer_peek(_b, _p,     buffer_u8);
        var _m1 = buffer_peek(_b, _p + 1, buffer_u8);
        if (_m0 != 0xDA || ((_m1 & 0xF0) != 0xB0)) return -1;
        return _p + 2;
    };

    // v7/v8 (older CharPad) use a shorter header and a raw 1x1 map with no tile
    // system. Divert to the legacy reader — placed HERE so both _rd_u8 and
    // _read_marker (var-scoped function locals) are already defined before we
    // pass them across. It reuses the same two 1x1 builders.
    if (_ver <= 8) {
        scr_import_charpad_ctm_legacy(
            _buf, _sz, _name_stem, _am, _ver,
            _rd_u8, _read_marker,
            _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3
        );
        buffer_delete(_buf);
        exit;
    }

    // ---- 3) Char image data block ($da,$b0) ----
    _pos = _read_marker(_buf, _pos);
    if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad charset marker"); exit; }
    var _charcnt = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);
    _pos += 2;
    var _char_count = _charcnt + 1;             // stored as count-minus-one
    var _chars_arr = array_create(_char_count * 8, 0);
    for (var _bi = 0; _bi < _char_count * 8; _bi++) {
        _chars_arr[_bi] = _rd_u8(_buf, _pos + _bi);
    }
    _pos += _char_count * 8;

    // ---- 4) Char materials block ($da,$b1) ----
    var _mat_arr = -1;
    _pos = _read_marker(_buf, _pos);
    if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad materials marker"); exit; }
    _mat_arr = array_create(_char_count, 0);
    for (var _mi = 0; _mi < _char_count; _mi++) {
        _mat_arr[_mi] = _rd_u8(_buf, _pos + _mi) & 0x0F;
    }
    _pos += _char_count;

    // ---- 5) Per-char colours block (only if COLR_METH==2) ----
    var _charcol_arr = -1;
    if (_colr_meth == 2) {
        _pos = _read_marker(_buf, _pos);
        if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad char-colour marker"); exit; }
        // bytes per char: HR bmp=2 (Sm lo/hi), MC bmp=2, else 1 (Cm lo)
        var _cbpc = (_is_bmp_hr || _is_bmp_mc) ? 2 : 1;
        _charcol_arr = array_create(_char_count, 1);
        for (var _ci = 0; _ci < _char_count; _ci++) {
            // first byte is the colour-matrix (or screen-lo) low nibble — what we want
            _charcol_arr[_ci] = _rd_u8(_buf, _pos + (_ci * _cbpc)) & 0x0F;
        }
        _pos += _char_count * _cbpc;
    }

    // ---- 6) BRANCH: no tile system -> 1x1 map. Ask which system to build. ----
    // TILESYS off means CharPad exported char images + a direct char-index map
    // with no metatiles (1x1 chars). Two valid targets:
    //   MAP_DATA      — per-cell colour freedom (classic flexi map)
    //   META_TILESET  — 1x1 metatiles, chars hold colour via char_lut (cheaper
    //                   colour RAM on C64: colour comes from a per-char table)
    if (!_tilesys) {
        // show_question returns a boolean: YES = MAP_DATA, NO = 1x1 metatile.
        var _use_mapdata = scr_show_question_bool(
	        "CharPad v" + string(_ver) + " map has no tiles (1x1 chars).\n\n"
	      + "Build as MAP_DATA?\n"
	      + "  YES = MAP_DATA (per-cell colour freedom)\n"
	      + "  NO  = 1x1 META_TILESET (chars hold colour)"
	    );
        if (_use_mapdata) {
            scr_charpad_ctm_build_map(
                _buf, _sz, _pos, _name_stem, _am,
                _char_count, _chars_arr, _mat_arr, _charcol_arr,
                _disp_mode, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3
            );
        } else {
            scr_charpad_ctm_build_meta1x1(
                _buf, _sz, _pos, _name_stem, _am,
                _char_count, _chars_arr, _mat_arr, _charcol_arr,
                _disp_mode, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3
            );
        }
        buffer_delete(_buf);
        exit;
    }

    // ---- Tile set blocks (TILESYS on) ----
    var _stamp_w = 2;
    var _stamp_h = 2;
    var _stamp_count = 0;
    var _tile_arr = -1;     // 16-bit cell values, low byte used
    var _tile_col_arr = -1; // per-stamp colour override (COLR_METH==1), or -1 if none

    if (_tilesys) {
        // tile data block
        _pos = _read_marker(_buf, _pos);
        if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad tile marker"); exit; }
        var _tilecnt = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);
        _pos += 2;
        _stamp_count = _tilecnt + 1;
        _stamp_w = _rd_u8(_buf, _pos);     _pos += 1;
        _stamp_h = _rd_u8(_buf, _pos);     _pos += 1;
        var _cells_per = _stamp_w * _stamp_h;
        _tile_arr = array_create(_stamp_count * _cells_per, 0);
        for (var _ti = 0; _ti < _stamp_count * _cells_per; _ti++) {
            // 16-bit LSBF, keep low byte
            _tile_arr[_ti] = _rd_u8(_buf, _pos + (_ti * 2)) & 0xFF;
        }
        _pos += _stamp_count * _cells_per * 2;

        // per-tile colours (if COLR_METH==1) — one colour nibble per stamp,
        // maps directly onto our stamp_override mechanism (forces one colour
        // across the whole metatile).
        if (_colr_meth == 1) {
            _pos = _read_marker(_buf, _pos);
            if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad tile-colour marker"); exit; }
            var _tbpc = (_is_bmp_hr || _is_bmp_mc) ? 2 : 1;
            _tile_col_arr = array_create(_stamp_count, 0);
            for (var _tci = 0; _tci < _stamp_count; _tci++) {
                _tile_col_arr[_tci] = _rd_u8(_buf, _pos + (_tci * _tbpc)) & 0x0F;
            }
            _pos += _stamp_count * _tbpc;
        }
        // tile tags — skip
        _pos = _read_marker(_buf, _pos);
        if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad tile-tags marker"); exit; }
        _pos += _stamp_count;

        // tile names — variable length, zero-terminated strings, skip
        _pos = _read_marker(_buf, _pos);
        if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad tile-names marker"); exit; }
        for (var _ni = 0; _ni < _stamp_count; _ni++) {
            while (_pos < _sz && _rd_u8(_buf, _pos) != 0) { _pos += 1; }
            _pos += 1;   // skip the terminator
        }
    } else {
        buffer_delete(_buf);
        scr_show_message("CTM import: project has no tile system (TILESYS off) — nothing to import as metatiles");
        exit;
    }

    if (_stamp_count <= 0) { buffer_delete(_buf); scr_show_message("CTM import: no tiles"); exit; }

    // ---- 7) Map data block ($da,$bn) ----
    _pos = _read_marker(_buf, _pos);
    if (_pos < 0) { buffer_delete(_buf); scr_show_message("CTM import: bad map marker"); exit; }
    var _map_w = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);     _pos += 2;
    var _map_h = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);     _pos += 2;
    var _map_cells = _map_w * _map_h;
    var _map_arr = array_create(_map_cells, 0);
    for (var _mc = 0; _mc < _map_cells; _mc++) {
        _map_arr[_mc] = _rd_u8(_buf, _pos + (_mc * 2)) & 0xFF;   // 16-bit LSBF, low byte
    }
    _pos += _map_cells * 2;

    buffer_delete(_buf);

    var _cells_per = _stamp_w * _stamp_h;

    // ---- 8) Build CHAR_SET asset ----
    var _cs_base = scr_clamp_asset_name(_name_stem + "_chars", 15);
    var _cs_name = _cs_base;
    var _cs_k = 2;
    while (true) {
        var _clash = false;
        for (var _uci = 0; _uci < ds_list_size(_am.asset_list); _uci++) {
            if (ds_list_find_value(_am.asset_list, _uci).name == _cs_name) { _clash = true; break; }
        }
        if (!_clash) break;
        // Re-clamp so the "_N" counter still fits inside 15 chars.
        _cs_name = scr_clamp_asset_name(_cs_base, 15 - (string_length(string(_cs_k)) + 1)) + "_" + string(_cs_k);
        _cs_k++;
    }

    // ECM (Text_EC) only has 64 real chars — CharPad's 256-entry export is 4
    // duplicate preview bands (one per BG0-3 register), so only store the
    // first 64 char images. Map/tile cell values keep the full 0-255 range
    // untouched (bits 6-7 = BG select, bits 0-5 = real char), matching real
    // ECM hardware — only the CHAR_SET bitmap data shrinks.
    var _store_char_count = (_disp_mode == 2) ? min(64, _char_count) : _char_count;

    var _cs_buf = buffer_create(_store_char_count * 8, buffer_fixed, 1);
    for (var _cbi = 0; _cbi < _store_char_count * 8; _cbi++) {
        buffer_poke(_cs_buf, _cbi, buffer_u8, _chars_arr[_cbi]);
    }

    var _tile_types = array_create(256, 0);
    for (var _tti = 0; _tti < _store_char_count; _tti++) {
        _tile_types[_tti] = _mat_arr[_tti] & 0x0F;
    }

    var _chr_mode = (_disp_mode == 1 || _disp_mode == 4) ? 1 : (_disp_mode == 2 ? 2 : 0);
    var _is_mc    = (_chr_mode == 1) ? 1 : 0;   // kept for existing MC-only checks below

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

    // ---- 9) Build META_TILESET asset ----
    var _ts_base = scr_clamp_asset_name(_name_stem + "_tiles", 15);
    var _ts_name = _ts_base;
    var _ts_k = 2;
    while (true) {
        var _tclash = false;
        for (var _uti = 0; _uti < ds_list_size(_am.asset_list); _uti++) {
            if (ds_list_find_value(_am.asset_list, _uti).name == _ts_name) { _tclash = true; break; }
        }
        if (!_tclash) break;
        // Re-clamp so the "_N" counter still fits inside 15 chars.
        _ts_name = scr_clamp_asset_name(_ts_base, 15 - (string_length(string(_ts_k)) + 1)) + "_" + string(_ts_k);
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

    _tm.stamp_w     = _stamp_w;
    _tm.stamp_h     = _stamp_h;
    _tm.stamp_count = _stamp_count;
    _tm.chr_asset   = _cs_name;
    // ECM has no map-level BG override concept (BG0-3 live directly on the
    // linked CHAR_SET) — -1 means "inherit", so BG0 correctly reads whatever
    // the charset's mc_bg is set to instead of being locked to _imp_mc_bg (0).
    _tm.map_mc_bg   = (_chr_mode == 2) ? -1 : _imp_mc_bg;
    _tm.map_mc_col1 = _imp_mc_col1;
    _tm.map_mc_col2 = _imp_mc_col2;
    _tm.map_mixed   = _is_mc;

    _tm.stamp_data = array_create(_stamp_count * _cells_per, 0);
    for (var _si = 0; _si < _stamp_count * _cells_per; _si++) {
        _tm.stamp_data[_si] = _tile_arr[_si] & 0xFF;
    }
    _tm.stamp_mc       = array_create(_stamp_count, 0);
    _tm.stamp_override = array_create(_stamp_count, 0x80);
    if (_tile_col_arr != -1) {
        for (var _tsi = 0; _tsi < _stamp_count; _tsi++) {
            _tm.stamp_override[_tsi] = _tile_col_arr[_tsi];
        }
    }

    _tm.char_lut     = array_create(256, 1);
    _tm.char_lut_len = _char_count;
    if (_charcol_arr != -1) {
        for (var _li = 0; _li < _char_count; _li++) {
            var _col = _charcol_arr[_li] & 0x0F;
            // "colour>=8 implies MC" is a real C64 convention, but ONLY for
            // true MC charsets, where colour RAM bit3 doubles as the MC flag.
            // ECM has no such overload — colour RAM is a genuine unrestricted
            // 0-15 nibble — so never infer the MC bit there, or downstream
            // rendering/emission wrongly treats the char as MC and masks its
            // colour to 3 bits.
            var _mc2 = (_chr_mode == 1 && _col >= 8) ? 1 : 0;
            _tm.char_lut[_li] = (_mc2 << 4) | (_col & 0x0F);
        }
    }

    // ---- 10) Slice the single LRTB map into screen-sized rooms ----
    // CharPad stores one big MAPWID x MAPHEI grid. We cut it into rooms of
    // _room_w x _room_h metatiles (a C64 screen), stacked top-to-bottom.
    // 2x2 metas -> 20x13 metatiles == 40x26 char cells (last char-row clipped
    // by the 25-row screen, as in the RAW path).
    var _room_w = _map_w;                    // full source width = one room wide
    var _room_h = floor(25 / _stamp_h);      // 12 for 2x2... but CharPad uses 13
    // CharPad's vertical room unit is 13 metatiles (26 char rows) for 2x2.
    // Use 13 when stamp_h is 2, else fall back to the screen-derived count.
    if (_stamp_h == 2) { _room_h = 13; }

    // If the whole map is SHORTER than one room, there's nothing to slice —
    // import it as a single room at its own height. The 13-row assumption
    // above only applies when the map is actually tall enough to contain at
    // least one full room; otherwise `_map_h div _room_h` truncates to 0 and
    // silently drops the entire map (e.g. a 12-row map against a 13-row room).
    if (_map_h < _room_h) {
        _room_h = _map_h;
    }

    _tm.maps      = [];
    _tm.map_count = 0;
    _tm.map_bytes = [];
    var _imported = 0;
    var _skipped  = 0;

    var _room_cells = _room_w * _room_h;
    var _num_rooms  = max(1, _map_h div _room_h);    // whole rooms only; trailing partial dropped

    for (var _r = 0; _r < _num_rooms; _r++) {
        var _room = array_create(_room_cells, 0);
        var _maxidx = 0;
        for (var _ry = 0; _ry < _room_h; _ry++) {
            var _src_row = (_r * _room_h) + _ry;
            for (var _rx = 0; _rx < _room_w; _rx++) {
                var _v = _map_arr[(_src_row * _map_w) + _rx] & 0xFF;
                _room[(_ry * _room_w) + _rx] = _v;
                if (_v > _maxidx) { _maxidx = _v; }
            }
        }
        if (_maxidx >= _stamp_count) {
            show_debug_message("CTM import: room " + string(_r)
                + " max idx " + string(_maxidx)
                + " >= stamp_count " + string(_stamp_count) + " — skipped");
            _skipped++;
        } else {
            array_push(_tm.maps, _room);
            array_push(_tm.map_bytes, 0);
            _tm.map_count++;
            _imported++;
        }
    }
    if (_tm.map_count > 0) { _tm.active_map = 0; }

    // Pre-stamp the viewer's size-guard key so its "stamp size changed -> clear
    // all maps" check does NOT fire on first open and wipe the imported maps.
    // Must match what the viewer computes: string(stamp_w) + "x" + stamp_h.
    _tm.map_size_key = string(_tm.stamp_w) + "x" + string(_tm.stamp_h);

    ds_list_add(_am.asset_list, _ts_asset);
    global.undo_dirty = true;

    scr_show_message("CTM import OK: " + string(_char_count) + " chars, "
        + string(_stamp_count) + " tiles, "
        + string(_imported) + " map"
        + (_skipped > 0 ? " (" + string(_skipped) + " skipped)" : ""));
}
