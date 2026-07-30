/// @function scr_spred64_v2_import_v1_compositor(_asset, _path)
/// @desc Parses the SPRED64 V1 compositor data block from a .txt file
///       and converts it to V2's frame/cell structure.
///
///       V1 format (one line per cell):
///         //<L><SSS><xoff><yoff><xpand><ypand> INFO: <...>
///       Where (post-V1-save-script analysis):
///         L      — layer ID, single char "0".."4"
///         SSS    — 3-char space-padded sprite slot ("999" = empty cell)
///         xoff   — single byte; signed offset = byte_value - 136
///         yoff   — single byte; same encoding
///         xpand  — "0" or "1"
///         ypand  — "0" or "1"
///       V1 layout in storage (from V1 save loop):
///         for (l = 0..4) { for (n = 0..499) { write_cell(); } }
///       So cells stream layer-by-layer (all of layer 0 first, then layer 1...).
///       Each layer's 500 cells split into frames of 16 cells (4x4 grid).
///       Frame index = n div 16, row = (n mod 16) div 4, col = (n mod 16) mod 4.
///       SSS=999 means "no sprite at this cell, this layer" — sparse import.
///
///       V2 conversion notes:
///       - V1 has up to 5 layers; V2 supports 8 — direct copy of layers 0-4.
///       - V1 has 500 cells/layer = up to ~31 frames. V2 supports any count.
///       - We compute the actual frame count by finding the highest frame
///         with any non-empty cell across all layers.
///       - xpand/ypand are per-cell flags in V1, preserved as V2 expand enum.
function scr_spred64_v2_import_v1_compositor(_asset, _path) {

    show_debug_message("V1 compositor import: ENTRY path='" + string(_path) + "' asset='" + string(_asset.name) + "'");

    if (!file_exists(_path)) {
        show_debug_message("V1 compositor import: file not found '" + _path + "'");
        return false;
    }

    // ----- LOAD FILE -----
    var _file    = file_text_open_read(_path);
    var _content = "";
    while (!file_text_eof(_file)) {
        _content += file_text_read_string(_file) + "\n";
        file_text_readln(_file);
    }
    file_text_close(_file);
    var _lines = string_split(_content, "\n");

    // ----- LOCATE COMPOSITOR BLOCK -----
    var _start_idx = -1;
    for (var _li = 0; _li < array_length(_lines); _li++) {
        if (string_pos("Compositing Data", _lines[_li]) > 0) {
            _start_idx = _li + 1;
            break;
        }
    }
    if (_start_idx < 0) {
        show_debug_message("V1 compositor import: no compositor block found");
        return false;
    }

    // ----- PARSE CELLS -----
    // Stream parser: each line is one cell, ordered by V1's nested loops
    // (outer = layer 0..4, inner = cell index 0..499 within layer).
    var _all_cells = [];
    for (var _li = _start_idx; _li < array_length(_lines); _li++) {
        var _raw = _lines[_li];
        // Strip trailing CR if present
        if (string_length(_raw) > 0
        &&  ord(string_char_at(_raw, string_length(_raw))) == 13) {
            _raw = string_copy(_raw, 1, string_length(_raw) - 1);
        }
        // Must start with "//"
        if (string_length(_raw) < 10) continue;
        if (string_copy(_raw, 1, 2) != "//") continue;
        // Body without "//"
        var _body = string_copy(_raw, 3, string_length(_raw) - 2);
        if (string_length(_body) < 8) continue;
        // Char 1 = layer ID (single digit "0".."4")
        var _layer_ch = string_char_at(_body, 1);
        if (_layer_ch < "0" || _layer_ch > "9") continue;
        var _v1_layer = real(_layer_ch);
        // Chars 2-4 = sprite slot (space-padded 3-char)
        var _slot_str = string_copy(_body, 2, 3);
        var _slot_is_numeric = true;
        for (var _ci = 1; _ci <= 3; _ci++) {
            var _c = string_char_at(_slot_str, _ci);
            if (_c != " " && (_c < "0" || _c > "9")) {
                _slot_is_numeric = false;
                break;
            }
        }
        if (!_slot_is_numeric) continue;
        var _slot_clean = string_replace_all(_slot_str, " ", "");
        if (_slot_clean == "") continue;
        var _slot = real(_slot_clean);
        // Char 5 = xoff (signed: byte_value - 136)
        var _xoff_ch = ord(string_char_at(_body, 5));
        var _xo = _xoff_ch - 136;
        // Char 6 = yoff (signed: byte_value - 136)
        var _yoff_ch = ord(string_char_at(_body, 6));
        var _yo = _yoff_ch - 136;
        // Char 7 = xpand, char 8 = ypand
        var _xpand = (string_char_at(_body, 7) == "1") ? 1 : 0;
        var _ypand = (string_char_at(_body, 8) == "1") ? 1 : 0;
        // V2 expand enum
        var _expand_str = "none";
        if (_xpand == 1 && _ypand == 1) {
            _expand_str = "both";
        } else if (_xpand == 1) {
            _expand_str = "x";
        } else if (_ypand == 1) {
            _expand_str = "y";
        }
        array_push(_all_cells, {
            v1_layer : _v1_layer,
            slot     : _slot,
            xo       : _xo,
            yo       : _yo,
            expand   : _expand_str
        });
    }
    show_debug_message("V1 compositor import: parsed " + string(array_length(_all_cells)) + " cells total");
    if (array_length(_all_cells) == 0) {
        return false;
    }

    // ----- SPLIT INTO LAYERS / FRAMES -----
    // V1 writes exactly 500 cells per layer. Cell stream is ordered
    // (layer 0 cells 0-499, then layer 1 cells 0-499, ...).
    var _cells_per_layer = 500;
    var _cells_per_frame = 16;
    var _v1_layer_count = max(1, ceil(array_length(_all_cells) / _cells_per_layer));
    if (_v1_layer_count > 5) _v1_layer_count = 5;
    // Find the highest frame index that has any real (non-999) content
    // across all layers. Trailing frames of all-999 cells are skipped.
    var _max_frame_used = 0;
    var _has_any_content = false;
    for (var _l = 0; _l < _v1_layer_count; _l++) {
        var _layer_base = _l * _cells_per_layer;
        for (var _n = 0; _n < _cells_per_layer; _n++) {
            var _idx = _layer_base + _n;
            if (_idx >= array_length(_all_cells)) break;
            var _cell = _all_cells[_idx];
            if (_cell.slot != 999) {
                _has_any_content = true;
                var _frame_idx = _n div _cells_per_frame;
                if (_frame_idx > _max_frame_used) {
                    _max_frame_used = _frame_idx;
                }
            }
        }
    }
    if (!_has_any_content) {
        show_debug_message("V1 compositor import: only spacer cells found, treating as empty");
        return false;
    }
    var _frame_count = _max_frame_used + 1;
    show_debug_message("V1 compositor import: " + string(_frame_count)
        + " frames across " + string(_v1_layer_count) + " V1 layers");

    // ----- BUILD V2 COMPOSITOR -----
    var _v2_frames = array_create(_frame_count);
    for (var _fi = 0; _fi < _frame_count; _fi++) {
        _v2_frames[_fi] = { cells : [] };
    }
    var _total_placed = 0;
    for (var _l = 0; _l < _v1_layer_count; _l++) {
        var _layer_base = _l * _cells_per_layer;
        for (var _n = 0; _n < _cells_per_layer; _n++) {
            var _idx = _layer_base + _n;
            if (_idx >= array_length(_all_cells)) break;
            var _cell = _all_cells[_idx];
            // Skip 999 sentinels (empty cell on this layer at this position)
            if (_cell.slot == 999) continue;
            // Skip slots beyond V2's 64-slot bank
            if (_cell.slot < 0 || _cell.slot >= 64) continue;
            var _frame_idx = _n div _cells_per_frame;
            if (_frame_idx >= _frame_count) continue;
            var _grid_n = _n mod _cells_per_frame;
            var _row = _grid_n div 4;
            var _col = _grid_n mod 4;
            array_push(_v2_frames[_frame_idx].cells, {
                layer  : _l,
                row    : _row,
                col    : _col,
                slot   : _cell.slot,
                xo     : _cell.xo,
                yo     : _cell.yo,
                expand : _cell.expand
            });
            _total_placed++;
        }
    }
    show_debug_message("V1 compositor import: placed " + string(_total_placed) + " cells into V2 frames");

    // ----- WRITE TO ASSET META -----
    _asset.meta.compositor = {
        frames       : _v2_frames,
        active_layer : 0,
        active_frame : 0,
        active_cell  : -1
    };
    // Seed anim state to match imported frame count
    if (!variable_struct_exists(_asset.meta, "anim")) {
        _asset.meta.anim = {
            playing   : false,
            direction : "fwd",
            speed     : 10,
            start     : 0,
            ender     : max(0, _frame_count - 1)
        };
    } else {
        if (_asset.meta.anim.ender < _frame_count - 1) {
            _asset.meta.anim.ender = _frame_count - 1;
        }
    }
    show_debug_message("V1 compositor import: " + string(_frame_count)
        + " V2 frames written to asset '" + _asset.name + "'");
    return true;
}