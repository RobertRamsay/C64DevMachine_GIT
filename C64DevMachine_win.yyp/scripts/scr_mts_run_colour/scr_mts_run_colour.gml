/// META_TILESET "as it will run" colour model.
///
/// MACRO_METASCROLL has three colour modes:
///   0 FIXED      one colour-RAM nibble for the whole screen, written at init
///   2 SHIFT C64U colour plane shifted with the chars (per-char colour)
///   3 ROW BANDS  one nibble per MAP row, written per screen row. Horizontal
///                coarse steps cost nothing; a vertical step rewrites only
///                the screen rows whose band colour actually changed.
///
/// These helpers give the tileset editor the same numbers the compiler
/// uses, so the RUN view shows what the C64 will show.
///
/// A colour byte ("co") is what lands in colour RAM:
///   ECM or HR ONLY : the full nibble, hires
///   MIXED          : bit 3 = multicolour, bits 0-2 = the cell's own colour

/// The per-char colour byte of one cell, exactly as the compiler bakes it.
/// @param {struct} _tm     META_TILESET meta
/// @param {real}   _mt     Metatile (stamp) index, for the stamp override
/// @param {real}   _ch     Char index (virtual index in ECM)
/// @param {bool}   _mixed  Workspace MIXED mode
/// @param {bool}   _ecm    Linked charset is ECM
function scr_mts_char_co(_tm, _mt, _ch, _mixed, _ecm) {
    var _col = 0;
    var _mc  = 0;
    if (_ch < array_length(_tm.char_lut)) {
        _col = _tm.char_lut[_ch] & 0x0F;
        _mc  = (_tm.char_lut[_ch] >> 4) & 0x01;
    }
    if (_mt >= 0 && _mt < array_length(_tm.stamp_override)) {
        if (_tm.stamp_override[_mt] != 0x80) { _col = _tm.stamp_override[_mt]; }
    }
    if (_ecm)    { return _col & 0x0F; }
    if (!_mixed) { return _col & 0x0F; }
    if (_mc == 1) { return (_col & 0x07) | 0x08; }
    return _col & 0x07;
}

/// Is a colour byte a multicolour cell?
function scr_mts_co_is_mc(_co, _mixed, _ecm) {
    if (_ecm)    { return false; }
    if (!_mixed) { return false; }
    return ((_co & 0x08) != 0);
}

/// The ink colour (HR ink / MC %11) a colour byte shows.
function scr_mts_co_fg(_co, _mixed, _ecm) {
    if (_ecm)    { return _co & 0x0F; }
    if (!_mixed) { return _co & 0x0F; }
    return _co & 0x07;
}

/// Tally one map's placed cells.
/// Returns { total, tally[16], bands[], band_miss, maph }
///   tally[c]  cells whose colour byte is c        (FIXED auto = argmax)
///   bands[r]  commonest colour byte of map row r  (ROW BANDS)
///   band_miss cells that differ from their row's band
/// @param {struct} _tm
/// @param {real}   _map_index
/// @param {bool}   _mixed
/// @param {bool}   _ecm
function scr_mts_colour_plan(_tm, _map_index, _mixed, _ecm) {
    var _plan = {
        total     : 0,
        tally     : array_create(16, 0),
        bands     : [],
        band_miss : 0,
        maph      : 0
    };
    if (_map_index < 0 || _map_index >= _tm.map_count) { return _plan; }
    if (_map_index >= array_length(_tm.maps)) { return _plan; }

    var _grid  = _tm.maps[_map_index];
    var _sw    = _tm.stamp_w;
    var _sh    = _tm.stamp_h;
    var _cells = _sw * _sh;
    var _lit_w = 40;
    if (_map_index < array_length(_tm.map_w)) { _lit_w = _tm.map_w[_map_index]; }
    var _cols_g = floor(_lit_w / _sw);
    if (_cols_g < 1) { _cols_g = 1; }
    var _rows_g = floor(array_length(_grid) / _cols_g);
    var _maph   = _rows_g * _sh;
    _plan.maph  = _maph;

    // Per map row tallies, 16 slots each
    var _row_tally = array_create(_maph * 16, 0);
    var _row_total = array_create(_maph, 0);

    for (var _gy = 0; _gy < _rows_g; _gy++) {
        for (var _gx = 0; _gx < _cols_g; _gx++) {
            var _mt = _grid[_gy * _cols_g + _gx];
            if (_mt < 0) { continue; }
            if (_mt >= _tm.stamp_count) { continue; }
            for (var _cy = 0; _cy < _sh; _cy++) {
                var _r = _gy * _sh + _cy;
                for (var _cx = 0; _cx < _sw; _cx++) {
                    var _db = _mt * _cells + _cy * _sw + _cx;
                    if (_db >= array_length(_tm.stamp_data)) { continue; }
                    var _co = scr_mts_char_co(_tm, _mt, _tm.stamp_data[_db], _mixed, _ecm) & 0x0F;
                    _plan.tally[_co] += 1;
                    _plan.total      += 1;
                    _row_tally[_r * 16 + _co] += 1;
                    _row_total[_r]            += 1;
                }
            }
        }
    }

    _plan.bands = array_create(_maph, 0);
    for (var _br = 0; _br < _maph; _br++) {
        var _best = 0;
        for (var _bc = 1; _bc < 16; _bc++) {
            if (_row_tally[_br * 16 + _bc] > _row_tally[_br * 16 + _best]) { _best = _bc; }
        }
        _plan.bands[_br]  = _best;
        _plan.band_miss  += _row_total[_br] - _row_tally[_br * 16 + _best];
    }
    return _plan;
}

/// FIXED auto nibble: the commonest colour byte in the plan.
function scr_mts_plan_auto_nib(_plan) {
    var _best = 0;
    for (var _i = 1; _i < 16; _i++) {
        if (_plan.tally[_i] > _plan.tally[_best]) { _best = _i; }
    }
    return _best;
}

/// The live MACRO_METASCROLL (on the spine or inside an ORG) that scrolls
/// this tileset, or noone.
/// @param {string} _ts_name
function scr_mts_find_scroller(_ts_name) {
    var _found = noone;
    with (obj_c64_node) {
        if (node_type != "MACRO_METASCROLL") { continue; }
        var _live = is_connected;
        if (org_parent != noone) {
            if (instance_exists(org_parent)) { _live = true; }
        }
        if (!_live) { continue; }
        if (array_length(instructions[0]) < 2) { continue; }
        if (string(instructions[0][1]) != _ts_name) { continue; }
        _found = id;
        break;
    }
    return _found;
}
