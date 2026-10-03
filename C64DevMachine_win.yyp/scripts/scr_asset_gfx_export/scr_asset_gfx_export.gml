/// Exporters for the CHAR_SET and SPRITE_SET assets, in the formats other C64
/// editors load:
///   scr_asset_chr_export_binary  raw charset, 8 bytes a char (no header)
///   scr_asset_chr_export_ctm     CharPad project, CTM version 5
///   scr_asset_spr_export_spd     SpritePad project, SPD version 1
/// (Raw sprite binaries: scr_asset_spr_export_binary.)

/// Raw character data: char_count x 8 bytes, as it sits in C64 memory.
function scr_asset_chr_export_binary(_asset, _path) {
    var _n = scr_asset_chr_export_count(_asset);
    var _out = buffer_create(max(1, _n * 8), buffer_fixed, 1);
    for (var _i = 0; _i < _n * 8; _i++) {
        buffer_poke(_out, _i, buffer_u8, buffer_peek(_asset.buffer, _i, buffer_u8));
    }
    buffer_save(_out, _path);
    buffer_delete(_out);
}

/// Chars to export: the charset's char_count, limited to what the buffer holds.
function scr_asset_chr_export_count(_asset) {
    var _n = 0;
    if (buffer_exists(_asset.buffer)) {
        _n = buffer_get_size(_asset.buffer) div 8;
    }
    var _cc = _asset.meta[$ "char_count"];
    if (!is_undefined(_cc)) {
        _n = min(_n, real(_cc));
    }
    return clamp(_n, 0, 256);
}

/// CharPad project file, CTM v5 (CharPad 2.x and later load it).
///   "CTM", 5, BG, MC1, MC2, RAM colour, colouring method (0 = global),
///   flags (bit 2 = multicolour; no tile system), chars-1 (16-bit),
///   tiles-1 (16-bit), tile width, tile height, map width, map height (16-bit),
///   char data, 1 attribute byte a char (low nybble = colour), map data (16-bit
///   codes). The map lays the charset out 16 chars wide so it shows as a sheet.
/// ECM charsets go out as hires: CTM v5 has no ECM mode.
function scr_asset_chr_export_ctm(_asset, _path) {
    var _n = max(1, scr_asset_chr_export_count(_asset));
    var _mc = (_asset.meta.mc_mode == 1);
    var _ram = _asset.meta.mc_fg & 15;
    if (_mc) {
        _ram = (_asset.meta.mc_fg & 7) | 8;    // colours 8-15 = multicolour chars
    }
    var _map_w = 16;
    var _map_h = (_n + 15) div 16;
    var _size = 20 + _n * 8 + _n + _map_w * _map_h * 2;
    var _out = buffer_create(_size, buffer_fixed, 1);
    buffer_seek(_out, buffer_seek_start, 0);
    buffer_write(_out, buffer_u8, ord("C"));
    buffer_write(_out, buffer_u8, ord("T"));
    buffer_write(_out, buffer_u8, ord("M"));
    buffer_write(_out, buffer_u8, 5);                            // version
    buffer_write(_out, buffer_u8, _asset.meta.mc_bg & 15);       // BG ($D021)
    buffer_write(_out, buffer_u8, _asset.meta.mc_col1 & 15);     // MC1 ($D022)
    buffer_write(_out, buffer_u8, _asset.meta.mc_col2 & 15);     // MC2 ($D023)
    buffer_write(_out, buffer_u8, _ram);                         // char colour (colour RAM)
    buffer_write(_out, buffer_u8, 0);                            // colouring: global
    if (_mc) {
        buffer_write(_out, buffer_u8, 4);                        // flags: multicolour
    } else {
        buffer_write(_out, buffer_u8, 0);
    }
    buffer_write(_out, buffer_u16, _n - 1);                      // chars - 1
    buffer_write(_out, buffer_u16, 0);                           // tiles - 1
    buffer_write(_out, buffer_u8, 1);                            // tile width
    buffer_write(_out, buffer_u8, 1);                            // tile height
    buffer_write(_out, buffer_u16, _map_w);
    buffer_write(_out, buffer_u16, _map_h);
    for (var _i = 0; _i < _n * 8; _i++) {
        var _v = 0;
        if (_i < buffer_get_size(_asset.buffer)) {
            _v = buffer_peek(_asset.buffer, _i, buffer_u8);
        }
        buffer_write(_out, buffer_u8, _v);
    }
    for (var _c = 0; _c < _n; _c++) {
        buffer_write(_out, buffer_u8, _ram);                     // attribute: colour, material 0
    }
    for (var _m = 0; _m < _map_w * _map_h; _m++) {
        var _code = _m;
        if (_code >= _n) {
            _code = 0;
        }
        buffer_write(_out, buffer_u16, _code);
    }
    buffer_save(_out, _path);
    buffer_delete(_out);
}

/// Sprites to export: used_count, limited to what the buffer holds (max 256).
function scr_asset_spr_export_count(_asset) {
    var _n = 0;
    if (buffer_exists(_asset.buffer)) {
        _n = buffer_get_size(_asset.buffer) div 64;
    }
    var _uc = _asset.meta[$ "used_count"];
    if (!is_undefined(_uc)) {
        _n = min(_n, real(_uc));
    }
    return clamp(_n, 0, 256);
}

/// The SpritePad attribute byte for sprite _si: bit 7 multicolour, bits 0-3 colour.
function scr_asset_spr_export_attr(_asset, _si) {
    var _mc  = 0;
    var _col = 1;
    var _mcs = _asset.meta[$ "sprite_mcs"];
    var _ucs = _asset.meta[$ "sprite_ucs"];
    if (is_array(_mcs) && _si < array_length(_mcs)) {
        _mc = _mcs[_si];
    }
    if (is_array(_ucs) && _si < array_length(_ucs)) {
        _col = _ucs[_si];
    }
    var _attr = round(_col) & 15;
    if (_mc == 1) {
        _attr = _attr | 128;
    }
    return _attr;
}

/// SpritePad project file, SPD version 1 (SpritePad 1.8.1 / 2.x, Spritemate).
///   "SPD", 1, sprites-1, animations-1, BG, MC1, MC2,
///   64 bytes a sprite (63 data + attribute), then the animation table
///   (start, end, timer, flags for each animation; one empty animation).
function scr_asset_spr_export_spd(_asset, _path) {
    var _n = max(1, scr_asset_spr_export_count(_asset));
    var _bg  = 0;
    var _mc1 = 0;
    var _mc2 = 1;
    if (!is_undefined(_asset.meta[$ "bg_col"])) {
        _bg = _asset.meta.bg_col;
    }
    if (!is_undefined(_asset.meta[$ "mc1_col"])) {
        _mc1 = _asset.meta.mc1_col;
    }
    if (!is_undefined(_asset.meta[$ "mc2_col"])) {
        _mc2 = _asset.meta.mc2_col;
    }
    var _out = buffer_create(9 + _n * 64 + 4, buffer_fixed, 1);
    buffer_seek(_out, buffer_seek_start, 0);
    buffer_write(_out, buffer_u8, ord("S"));
    buffer_write(_out, buffer_u8, ord("P"));
    buffer_write(_out, buffer_u8, ord("D"));
    buffer_write(_out, buffer_u8, 1);           // version
    buffer_write(_out, buffer_u8, _n - 1);      // sprites - 1
    buffer_write(_out, buffer_u8, 0);           // animations - 1
    buffer_write(_out, buffer_u8, _bg & 15);
    buffer_write(_out, buffer_u8, _mc1 & 15);
    buffer_write(_out, buffer_u8, _mc2 & 15);
    var _bsz = 0;
    if (buffer_exists(_asset.buffer)) {
        _bsz = buffer_get_size(_asset.buffer);
    }
    for (var _si = 0; _si < _n; _si++) {
        for (var _bi = 0; _bi < 63; _bi++) {
            var _v = 0;
            if (_si * 64 + _bi < _bsz) {
                _v = buffer_peek(_asset.buffer, _si * 64 + _bi, buffer_u8);
            }
            buffer_write(_out, buffer_u8, _v);
        }
        buffer_write(_out, buffer_u8, scr_asset_spr_export_attr(_asset, _si));
    }
    // One (empty) animation: start 0, end 0, timer 1, flags 0.
    buffer_write(_out, buffer_u8, 0);
    buffer_write(_out, buffer_u8, 0);
    buffer_write(_out, buffer_u8, 1);
    buffer_write(_out, buffer_u8, 0);
    buffer_save(_out, _path);
    buffer_delete(_out);
}
