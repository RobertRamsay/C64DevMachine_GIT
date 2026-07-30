/// @desc Writes a SPRITE_SET asset to a Spred64 decimal .txt file at _path
///       Compositor block is written in V1 cell format so that
///       scr_spred64_v2_import_v1_compositor can read it back.
///
///       V1 cell line: //<L><SSS><xoff><yoff><xpand><ypand>
///         L     — layer digit 0..4
///         SSS   — 3-char space-padded slot ("999" = empty)
///         xoff  — chr(offset + 136)
///         yoff  — chr(offset + 136)
///         xpand — "0"/"1"
///         ypand — "0"/"1"
///       Stream order: layer 0 cells 0..499, layer 1 cells 0..499, ...
///       Cell index n → frame = n div 16, row = (n mod 16) div 4, col = n mod 4
function scr_asset_spr_export_spred64(_asset, _path) {

    var _bg_col  = 12;
    var _mc1_col = 0;
    var _mc2_col = 1;
    var _mcs     = array_create(64, 0);
    var _ucs     = array_create(64, 1);

    if (variable_struct_exists(_asset.meta, "bg_col")) {
        _bg_col = _asset.meta.bg_col;
    }
    if (variable_struct_exists(_asset.meta, "mc1_col")) {
        _mc1_col = _asset.meta.mc1_col;
    }
    if (variable_struct_exists(_asset.meta, "mc2_col")) {
        _mc2_col = _asset.meta.mc2_col;
    }
    if (variable_struct_exists(_asset.meta, "sprite_mcs")) {
        _mcs = _asset.meta.sprite_mcs;
    }
    if (variable_struct_exists(_asset.meta, "sprite_ucs")) {
        _ucs = _asset.meta.sprite_ucs;
    }

    var _buf_size = 0;
    if (buffer_exists(_asset.buffer)) {
        _buf_size = buffer_get_size(_asset.buffer);
    }

    // Meta arrays may be trimmed to used_count, so read defensively per slot.
    var _mcs_len = array_length(_mcs);
    var _ucs_len = array_length(_ucs);

    // ----- BUILD V1 CELL GRID FROM V2 COMPOSITOR -----
    // 5 layers x 500 cells, pre-filled with the empty sentinel.
    var _cells_per_layer = 500;
    var _cells_per_frame = 16;
    var _v1_layers       = 5;

    var _grid = array_create(_v1_layers * _cells_per_layer, -1);

    if (variable_struct_exists(_asset.meta, "compositor")) {
        var _comp   = _asset.meta.compositor;
        var _frames = _comp.frames;
        var _fcount = array_length(_frames);

        for (var _fi = 0; _fi < _fcount; _fi++) {
            var _cells  = _frames[_fi].cells;
            var _ccount = array_length(_cells);

            for (var _ci = 0; _ci < _ccount; _ci++) {
                var _cell = _cells[_ci];

                // V1 only holds 5 layers — drop anything above layer 4.
                if (_cell.layer < 0 || _cell.layer >= _v1_layers) {
                    continue;
                }

                var _n = (_fi * _cells_per_frame) + (_cell.row * 4) + _cell.col;
                if (_n < 0 || _n >= _cells_per_layer) {
                    continue;
                }

                var _idx = (_cell.layer * _cells_per_layer) + _n;
                _grid[_idx] = _cell;
            }
        }
    }

    // ----- WRITE FILE -----
    var _f = file_text_open_write(_path);

    // Header
    file_text_write_string(_f, "// Spred 0.1.4.8.Test - Decimal"); file_text_writeln(_f);
    file_text_write_string(_f, "// Background Colour :" + string(_bg_col));  file_text_writeln(_f);
    file_text_write_string(_f, "// Global MC Colour1 :" + string(_mc1_col)); file_text_writeln(_f);
    file_text_write_string(_f, "// Global MC Colour2 :" + string(_mc2_col)); file_text_writeln(_f);

    for (var _si = 0; _si < 64; _si++) {
        var _slot_mc = 0;
        var _slot_uc = 1;
        if (_si < _mcs_len) {
            _slot_mc = _mcs[_si];
        }
        if (_si < _ucs_len) {
            _slot_uc = _ucs[_si];
        }

        file_text_write_string(_f, "// Sprite ID :" + string(_si) + ";"); file_text_writeln(_f);
        file_text_write_string(_f, "// HR(0) MC(1) :" + string(_slot_mc)); file_text_writeln(_f);
        file_text_write_string(_f, "// Sprite Unique Colour :" + string(_slot_uc)); file_text_writeln(_f);

        // Build .byte line — 64 values, 3-digit zero-padded
        var _base = _si * 64;
        var _line = ".byte ";
        for (var _bi = 0; _bi < 64; _bi++) {
            var _val = 0;
            if (_buf_size >= _base + _bi + 1) {
                buffer_seek(_asset.buffer, buffer_seek_start, _base + _bi);
                _val = buffer_read(_asset.buffer, buffer_u8);
            }
            if (_bi == 63) {
                _val = 0; // mode byte — zeroed, carried by HR line
            }
            var _str = string(_val);
            while (string_length(_str) < 3) {
                _str = "0" + _str;
            }
            _line += _str;
            if (_bi < 63) {
                _line += ", ";
            }
        }
        file_text_write_string(_f, _line);
        file_text_writeln(_f); // end of .byte line
        file_text_writeln(_f); // blank line — doLoad reads this as skip line 1
                               // next loop's "// Sprite ID" = doLoad's skip line 2
    }

    // ----- COMPOSITOR — 5 x 500 cell lines, layer-major -----
    file_text_write_string(_f, "// Compositing Data (mainly for Spred but can be used elsewhere)");
    file_text_writeln(_f);

    for (var _l = 0; _l < _v1_layers; _l++) {
        for (var _n = 0; _n < _cells_per_layer; _n++) {
            var _idx  = (_l * _cells_per_layer) + _n;
            var _cell = _grid[_idx];

            var _line_out = "";

            if (_cell == -1) {
                // Empty cell — slot 999, zero offsets, no expand.
                // chr(136) encodes offset 0 under the byte-136 scheme.
                _line_out = "//" + string(_l) + "999" + chr(136) + chr(136) + "00";
            } else {
                // Slot — 3-char space-padded (matches V1's string_format style).
                var _slot_str = string(_cell.slot);
                while (string_length(_slot_str) < 3) {
                    _slot_str = " " + _slot_str;
                }

                // Offsets clamped to the byte range the encoding allows.
                var _xo_b = clamp(_cell.xo + 136, 32, 255);
                var _yo_b = clamp(_cell.yo + 136, 32, 255);

                var _xpand = "0";
                var _ypand = "0";
                if (_cell.expand == "x") {
                    _xpand = "1";
                }
                if (_cell.expand == "y") {
                    _ypand = "1";
                }
                if (_cell.expand == "both") {
                    _xpand = "1";
                    _ypand = "1";
                }

                _line_out = "//" + string(_l) + _slot_str
                          + chr(_xo_b) + chr(_yo_b)
                          + _xpand + _ypand;
            }

            file_text_write_string(_f, _line_out);
            file_text_writeln(_f);
        }
    }

    // Labels — one per sprite
    for (var _si2 = 0; _si2 < 64; _si2++) {
        file_text_write_string(_f, "//"); file_text_writeln(_f);
    }

    file_text_close(_f);

    show_debug_message("SPRED64 export: written '" + string(_path) + "'");
}