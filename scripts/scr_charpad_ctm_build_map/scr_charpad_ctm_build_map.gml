/// @desc Build a CHAR_SET + MAP_DATA pair from a TILESYS-off CharPad CTM.
///       Called by scr_import_charpad_ctm when the project has no tile system,
///       i.e. the map stores raw char indices (1x1 chars). Produces one big
///       MAP_DATA covering the whole CharPad map — no screen slicing.
///
/// @param {Id.Buffer} _buf          the loaded CTM buffer (caller owns/deletes it)
/// @param {Real}      _sz           buffer size
/// @param {Real}      _pos          cursor sitting at the map marker ($da,$b3)
/// @param {String}    _name_stem    cleaned filename stem for asset naming
/// @param {Id.Instance} _am         obj_asset_manager instance
/// @param {Real}      _char_count   number of chars parsed
/// @param {Array}     _chars_arr    char image bytes (char_count * 8)
/// @param {Array}     _mat_arr      per-char material low nibbles (may be unused)
/// @param {Any}       _charcol_arr  per-char colour low nibbles, or -1 if none
/// @param {Real}      _disp_mode    CTM display mode (0=TxtHR,1=TxtMC,...)
/// @param {Real}      _imp_mc_bg    default MC background colour
/// @param {Real}      _imp_mc_col1  default MC shared colour 1
/// @param {Real}      _imp_mc_col2  default MC shared colour 2
function scr_charpad_ctm_build_map(
    _buf, _sz, _pos, _name_stem, _am,
    _char_count, _chars_arr, _mat_arr, _charcol_arr,
    _disp_mode, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3 = 3) {

    // Local reader — mirrors the parent script's cursor style.
    var _rd_u8 = function(_b, _p) { return buffer_peek(_b, _p, buffer_u8); };

    // ---- Verify + read the map block marker ($da,$bn) ----
    var _m0 = _rd_u8(_buf, _pos);
    var _m1 = _rd_u8(_buf, _pos + 1);
    if (_m0 != 0xDA || ((_m1 & 0xF0) != 0xB0)) {
        scr_show_message("CTM map import: bad map marker");
        exit;
    }
    _pos += 2;

    var _map_w = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);   _pos += 2;
    var _map_h = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);   _pos += 2;
    var _map_cells = _map_w * _map_h;

    if (_map_w <= 0 || _map_h <= 0) {
        scr_show_message("CTM map import: bad map dimensions "
            + string(_map_w) + "x" + string(_map_h));
        exit;
    }
    // Guard against a truncated file (16 bits per cell).
    if (_pos + _map_cells * 2 > _sz) {
        scr_show_message("CTM map import: map block truncated");
        exit;
    }

    // ---- Read the 16-bit LSBF map, keep the low byte (char index) ----
    var _map_idx = array_create(_map_cells, 0);
    for (var _mc = 0; _mc < _map_cells; _mc++) {
        _map_idx[_mc] = _rd_u8(_buf, _pos + (_mc * 2)) & 0xFF;
    }
    _pos += _map_cells * 2;

    // ---- Is this a multicolour charset? (Text MC = disp_mode 1, ECM = disp_mode 2) ----
    var _chr_mode = (_disp_mode == 1 || _disp_mode == 4) ? 1 : (_disp_mode == 2 ? 2 : 0);
    var _is_mc    = (_chr_mode == 1) ? 1 : 0;   // kept for existing MC-only checks below

    // ECM only has 64 real chars — CharPad's 256-entry export is 4 duplicate
    // preview bands (BG0-3). Only CHAR_SET bitmap storage shrinks to 64;
    // char_grid keeps the full virtual 0-255 screen-code values as-is (the
    // MAP_DATA viewer already resolves real_char = value mod 64, band = div 64).
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

    // Carry CharPad char materials across as tile_types (0..15).
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
    // 2) BUILD MAP_DATA ASSET
    // ================================================================
    var _mp_base = scr_clamp_asset_name(_name_stem + "_map", 15);
    var _mp_name = _mp_base;
    var _mp_k    = 2;
    while (true) {
        var _mclash = false;
        for (var _umi = 0; _umi < ds_list_size(_am.asset_list); _umi++) {
            if (ds_list_find_value(_am.asset_list, _umi).name == _mp_name) {
                _mclash = true;
                break;
            }
        }
        if (!_mclash) break;
        _mp_name = scr_clamp_asset_name(_mp_base, 15 - (string_length(string(_mp_k)) + 1))
                 + "_" + string(_mp_k);
        _mp_k++;
    }

    // Char grid = raw char indices. Colour grid = per-char colour lookup.
    var _grid_sz    = _map_w * _map_h;
    var _char_grid  = array_create(_grid_sz, 0);
    var _colour_grid = array_create(_grid_sz, 1);
    for (var _gi = 0; _gi < _grid_sz; _gi++) {
        var _ch = _map_idx[_gi];
        _char_grid[_gi] = _ch;
        if (_charcol_arr != -1 && _ch < _char_count) {
            _colour_grid[_gi] = _charcol_arr[_ch] & 0x0F;
        } else {
            _colour_grid[_gi] = 1;
        }
    }

    var _mp_asset = {
        type          : "MAP_DATA",
        name          : _mp_name,
        file          : "",
        address       : scr_asset_default_address("MAP_DATA"),
        buffer        : buffer_create(1, buffer_fixed, 1),
        meta          : {
            map_w             : _map_w,
            map_h             : _map_h,
            grid_w            : _map_w,
            grid_h            : _map_h,
            char_grid         : _char_grid,
            colour_grid       : _colour_grid,
            override_grid     : array_create(_grid_sz, 0),
            chr_asset         : _cs_name,
            scroll_x          : 0,
            scroll_y          : 0,
            zoom              : 2,
            active_char       : 0,
            active_colour     : 1,
            tool              : "CHAR",
            char_strip_offset : 0,
            preview_surf      : -1,
            mc_mode           : _is_mc ? 2 : 0,
            paint_mc          : 0,
            map_mixed         : _is_mc,
            map_mc_bg         : _is_mc ? _imp_mc_bg   : -1,
            map_mc_col1       : _is_mc ? _imp_mc_col1 : -1,
            map_mc_col2       : _is_mc ? _imp_mc_col2 : -1
        },
        load_later    : false,
        d64_filename  : "",
        linked_assets : [],
    };

    // Buffer is the single source of truth — build it via flush.
    scr_asset_map_flush(_mp_asset);
    ds_list_add(_am.asset_list, _mp_asset);

    global.undo_dirty = true;

    scr_show_message("CTM map import OK: " + string(_char_count) + " chars, "
        + string(_map_w) + "x" + string(_map_h) + " map ("
        + string(_map_cells) + " cells)");
}
