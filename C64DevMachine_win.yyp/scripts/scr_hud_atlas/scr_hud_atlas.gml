/// @function scr_hud_atlas(_asset, _chr)
/// @desc Builds (or refreshes) the three glyph atlases the HUD canvas draws
///       from, and returns true when they are ready to use.
///
/// WHY ATLASES
/// A HUD cell's colour comes from colour RAM, so every cell can be a different
/// colour — the charset's own preview surfaces bake one foreground colour in
/// and can't be reused. Drawing each cell bit-by-bit instead costs 8x8 filled
/// rectangles per cell, which for a 40x25 screen is 64000 draw calls a frame.
///
/// So the glyphs are rendered ONCE into surfaces with a transparent
/// background, and each cell is then one tinted draw_surface_part_ext:
///
///   atlas_hr   hi-res: set bits white, clear bits transparent.
///              Cell = background rect, then the glyph tinted with colour RAM.
///   atlas_mcs  multicolour, the two SHARED colours only ($D022 / $D023).
///              Bit-pairs 01 and 10 in their real colours, 00 and 11 clear.
///   atlas_mcf  multicolour, bit-pair 11 in white, everything else clear.
///              Tinted with colour RAM, drawn over atlas_mcs.
///
/// Splitting multicolour across two surfaces is what makes the tint legal:
/// only the 11 pairs follow colour RAM, and they are the only thing on the
/// surface that gets tinted.
///
/// The atlases are rebuilt when the key below changes — charset identity, its
/// size, the mode, or either shared colour — and when a surface is lost (a
/// resolution change or alt-tab frees them). They are never serialised.
///
/// @param {Struct} _asset  the HUD asset
/// @param {Id}     _chr    the linked CHAR_SET asset, or noone
/// @return {Bool}  true when atlas_hr / atlas_mcs / atlas_mcf are usable
function scr_hud_atlas(_asset, _chr) {

    var _m = _asset.meta;

    if (_chr == noone) {
        return false;
    }
    if (!buffer_exists(_chr.buffer)) {
        return false;
    }

    var _n_chars = buffer_get_size(_chr.buffer) div 8;
    if (_n_chars <= 0) {
        return false;
    }
    if (_n_chars > 256) {
        _n_chars = 256;
    }

    var _col1 = _m.hud_mc_col1;
    if (_col1 < 0) {
        _col1 = 1;
        if (variable_struct_exists(_chr.meta, "mc_col1")) {
            _col1 = _chr.meta.mc_col1;
        }
    }
    var _col2 = _m.hud_mc_col2;
    if (_col2 < 0) {
        _col2 = 2;
        if (variable_struct_exists(_chr.meta, "mc_col2")) {
            _col2 = _chr.meta.mc_col2;
        }
    }

    var _key = _chr.name + "|" + string(buffer_get_size(_chr.buffer)) + "|"
             + string(_col1) + "|" + string(_col2);

    var _have = surface_exists(_m.atlas_hr)
             && surface_exists(_m.atlas_mcs)
             && surface_exists(_m.atlas_mcf);

    if (_have && _m.atlas_key == _key) {
        return true;
    }

    if (surface_exists(_m.atlas_hr))  { surface_free(_m.atlas_hr);  }
    if (surface_exists(_m.atlas_mcs)) { surface_free(_m.atlas_mcs); }
    if (surface_exists(_m.atlas_mcf)) { surface_free(_m.atlas_mcf); }

    var _scale = 2;                       // 8x8 glyph -> 16x16 atlas cell
    var _cell  = 8 * _scale;
    var _rows  = 16;                      // always 16x16 cells = every code 0-255
    var _sw    = 16 * _cell;
    var _sh    = _rows * _cell;

    // ---------------------------------------------------------------
    // HI-RES: set bits white, clear bits transparent
    // ---------------------------------------------------------------
    var _s_hr = surface_create(_sw, _sh);
    surface_set_target(_s_hr);
    draw_clear_alpha(c_black, 0);
    draw_set_color(c_white);
    for (var _c = 0; _c < _n_chars; _c++) {
        var _ax = (_c mod 16) * _cell;
        var _ay = (_c div 16) * _cell;
        for (var _r = 0; _r < 8; _r++) {
            var _byte = buffer_peek(_chr.buffer, (_c * 8) + _r, buffer_u8);
            if (_byte == 0) {
                continue;
            }
            for (var _b = 0; _b < 8; _b++) {
                if ((_byte & (0x80 >> _b)) == 0) {
                    continue;
                }
                var _px = _ax + (_b * _scale);
                var _py = _ay + (_r * _scale);
                draw_rectangle(_px, _py, _px + _scale - 1, _py + _scale - 1, false);
            }
        }
    }
    surface_reset_target();

    // ---------------------------------------------------------------
    // MULTICOLOUR, SHARED PAIRS: 01 -> $D022, 10 -> $D023
    // ---------------------------------------------------------------
    var _s_mcs = surface_create(_sw, _sh);
    surface_set_target(_s_mcs);
    draw_clear_alpha(c_black, 0);
    var _pair_cols = [c_black, scr_c64_pepto_colour(_col1), scr_c64_pepto_colour(_col2), c_black];
    for (var _c = 0; _c < _n_chars; _c++) {
        var _ax = (_c mod 16) * _cell;
        var _ay = (_c div 16) * _cell;
        for (var _r = 0; _r < 8; _r++) {
            var _byte = buffer_peek(_chr.buffer, (_c * 8) + _r, buffer_u8);
            if (_byte == 0) {
                continue;
            }
            for (var _p = 0; _p < 4; _p++) {
                var _bits = (_byte >> (6 - _p * 2)) & 0x03;
                if (_bits == 0 || _bits == 3) {
                    continue;
                }
                draw_set_color(_pair_cols[_bits]);
                var _px = _ax + (_p * 2 * _scale);
                var _py = _ay + (_r * _scale);
                draw_rectangle(_px, _py, _px + (2 * _scale) - 1, _py + _scale - 1, false);
            }
        }
    }
    surface_reset_target();

    // ---------------------------------------------------------------
    // MULTICOLOUR, COLOUR-RAM PAIR: 11 -> white, tinted per cell
    // ---------------------------------------------------------------
    var _s_mcf = surface_create(_sw, _sh);
    surface_set_target(_s_mcf);
    draw_clear_alpha(c_black, 0);
    draw_set_color(c_white);
    for (var _c = 0; _c < _n_chars; _c++) {
        var _ax = (_c mod 16) * _cell;
        var _ay = (_c div 16) * _cell;
        for (var _r = 0; _r < 8; _r++) {
            var _byte = buffer_peek(_chr.buffer, (_c * 8) + _r, buffer_u8);
            if (_byte == 0) {
                continue;
            }
            for (var _p = 0; _p < 4; _p++) {
                var _bits = (_byte >> (6 - _p * 2)) & 0x03;
                if (_bits != 3) {
                    continue;
                }
                var _px = _ax + (_p * 2 * _scale);
                var _py = _ay + (_r * _scale);
                draw_rectangle(_px, _py, _px + (2 * _scale) - 1, _py + _scale - 1, false);
            }
        }
    }
    surface_reset_target();

    _m.atlas_hr  = _s_hr;
    _m.atlas_mcs = _s_mcs;
    _m.atlas_mcf = _s_mcf;
    _m.atlas_key = _key;
    return true;
}


/// @function scr_hud_atlas_char(_asset, _chr, _c)
/// @desc Redraws ONE character's cell in all three atlases — what the inline
///       tile editor needs while a glyph is being painted, where rebuilding
///       every cell on every frame of a drag would be 30k rectangles a frame.
///       Requires the atlases to exist already (scr_hud_atlas returned true).
function scr_hud_atlas_char(_asset, _chr, _c) {

    var _m = _asset.meta;
    if (_chr == noone) { exit; }
    if (!buffer_exists(_chr.buffer)) { exit; }
    if (!surface_exists(_m.atlas_hr) || !surface_exists(_m.atlas_mcs) || !surface_exists(_m.atlas_mcf)) { exit; }
    if (_c < 0 || _c > 255) { exit; }
    if ((_c * 8) + 7 >= buffer_get_size(_chr.buffer)) { exit; }

    var _col1 = _m.hud_mc_col1;
    if (_col1 < 0) {
        _col1 = 1;
        if (variable_struct_exists(_chr.meta, "mc_col1")) { _col1 = _chr.meta.mc_col1; }
    }
    var _col2 = _m.hud_mc_col2;
    if (_col2 < 0) {
        _col2 = 2;
        if (variable_struct_exists(_chr.meta, "mc_col2")) { _col2 = _chr.meta.mc_col2; }
    }

    var _scale = 2;
    var _cell  = 8 * _scale;
    var _ax = (_c mod 16) * _cell;
    var _ay = (_c div 16) * _cell;
    var _pair_cols = [c_black, scr_c64_pepto_colour(_col1), scr_c64_pepto_colour(_col2), c_black];

    // Clearing a cell on a surface that keeps its alpha needs the blend mode
    // that writes the source straight through, otherwise a transparent draw
    // is a no-op and stale pixels survive underneath.
    var _surfs = [_m.atlas_hr, _m.atlas_mcs, _m.atlas_mcf];
    for (var _si = 0; _si < 3; _si++) {
        surface_set_target(_surfs[_si]);
        gpu_set_blendmode_ext(bm_one, bm_zero);
        draw_set_alpha(0);
        draw_set_color(c_black);
        draw_rectangle(_ax, _ay, _ax + _cell - 1, _ay + _cell - 1, false);
        draw_set_alpha(1);
        gpu_set_blendmode(bm_normal);

        for (var _r = 0; _r < 8; _r++) {
            var _byte = buffer_peek(_chr.buffer, (_c * 8) + _r, buffer_u8);
            if (_byte == 0) { continue; }
            var _py = _ay + (_r * _scale);
            if (_si == 0) {
                draw_set_color(c_white);
                for (var _b = 0; _b < 8; _b++) {
                    if ((_byte & (0x80 >> _b)) == 0) { continue; }
                    var _px = _ax + (_b * _scale);
                    draw_rectangle(_px, _py, _px + _scale - 1, _py + _scale - 1, false);
                }
            } else {
                for (var _p = 0; _p < 4; _p++) {
                    var _bits = (_byte >> (6 - _p * 2)) & 0x03;
                    var _want = false;
                    if (_si == 1 && (_bits == 1 || _bits == 2)) {
                        draw_set_color(_pair_cols[_bits]);
                        _want = true;
                    }
                    if (_si == 2 && _bits == 3) {
                        draw_set_color(c_white);
                        _want = true;
                    }
                    if (!_want) { continue; }
                    var _px2 = _ax + (_p * 2 * _scale);
                    draw_rectangle(_px2, _py, _px2 + (2 * _scale) - 1, _py + _scale - 1, false);
                }
            }
        }
        surface_reset_target();
    }
}
