/// LINE_COLL support — normalizes user-authored line segments (x1,y1,x2,y2,type)
/// into the byte-packed runtime LUT record format used by MACRO_LINE.
///
/// RECORD FORMAT (6 bytes per line):
///   byte 0: axis_flag   (0 = X-major, 1 = Y-major)
///   byte 1: major_start (X0 if X-major, Y0 if Y-major)
///   byte 2: minor_start (Y0 if X-major, X0 if Y-major)
///   byte 3: major_end   (X1 if X-major, Y1 if Y-major)
///   byte 4: slope_byte  (bit 6 = direction, bits 1-5 = gradient magnitude 0-31)
///   byte 5: type        (0-7)
///
/// Runtime walks the major axis from major_start to major_end; at each step
/// the minor axis moves by slope_byte's gradient/16, direction per bit 6.
/// This is X-major or Y-major depending on which axis has the larger span,
/// so any line direction (including vertical) is representable exactly.
///
/// Block terminator: three bytes of $FF ($FF,$FF,$FF). A normal record's
/// byte 0 is always 0 or 1, so a single $FF check on byte 0 is sufficient
/// to detect the sentinel at runtime — the extra two $FF bytes exist only
/// to keep the terminator visually/structurally distinct in raw memory.

/// @desc scr_line_coll_normalize(x1, y1, x2, y2, type)
/// Converts one raw authored line into its 6-byte packed record.
/// Returns an array of 6 bytes.
function scr_line_coll_normalize(_x1, _y1, _x2, _y2, _type) {
    var _dx = _x2 - _x1;
    var _dy = _y2 - _y1;
    var _adx = abs(_dx);
    var _ady = abs(_dy);

    var _axis_flag = 0;
    var _major_start = 0;
    var _minor_start = 0;
    var _major_end = 0;
    var _span = 0;
    var _delta = 0;

    if (_ady > _adx) {
        // Y-major: walk Y, derive X per step.
        _axis_flag = 1;
        if (_y1 <= _y2) {
            _major_start = _y1; _minor_start = _x1; _major_end = _y2; _delta = _dx;
        } else {
            _major_start = _y2; _minor_start = _x2; _major_end = _y1; _delta = -_dx;
        }
        _span = _major_end - _major_start;
    } else {
        // X-major: walk X, derive Y per step. Ties (|dx|==|dy|) default X-major.
        _axis_flag = 0;
        if (_x1 <= _x2) {
            _major_start = _x1; _minor_start = _y1; _major_end = _x2; _delta = _dy;
        } else {
            _major_start = _x2; _minor_start = _y2; _major_end = _x1; _delta = -_dy;
        }
        _span = _major_end - _major_start;
    }

    // Gradient magnitude scaled to a 5-bit field (0-31), representing
    // minor-axis movement per major-axis step in 1/16ths of a pixel.
    var _direction_bit = (_delta < 0) ? 0x40 : 0x00;
    var _gradient = (_span == 0) ? 0 : round((abs(_delta) * 16) / _span);
    _gradient = clamp(_gradient, 0, 31);
    var _slope_byte = _direction_bit | (_gradient & 0x1F);

    return [
        _axis_flag & 0xFF,
        _major_start & 0xFF,
        _minor_start & 0xFF,
        _major_end & 0xFF,
        _slope_byte & 0xFF,
        _type & 0x07
    ];
}

/// @desc scr_line_coll_compile(_lines)
/// _lines is an array of structs: {x1, y1, x2, y2, type}
/// Returns a byte array: all normalized records concatenated, followed by
/// the 3-byte $FF,$FF,$FF sentinel.
function scr_line_coll_compile(_lines) {
    var _out = [];
    var _n = array_length(_lines);
    for (var _i = 0; _i < _n; _i++) {
        var _ln = _lines[_i];
        var _rec = scr_line_coll_normalize(_ln.x1, _ln.y1, _ln.x2, _ln.y2, _ln.type);
        for (var _b = 0; _b < 6; _b++) array_push(_out, _rec[_b]);
    }
    array_push(_out, 0xFF);
    array_push(_out, 0xFF);
    array_push(_out, 0xFF);
    return _out;
}

/// @desc scr_line_coll_save(_asset)
/// Commits the shared inline text editor's working text (meta.inline_edit_text,
/// one "x1,y1,x2,y2,type" row per line) into meta.lines[] and the compiled
/// buffer. Called when the LINE_COLL editor panel is closed/saved — mirrors
/// scr_asset_byte_data_save's role for BYTE_DATA.
function scr_line_coll_save(_asset) {
    _asset.meta.line_string = _asset.meta.inline_edit_text;
    scr_line_coll_flush(_asset);
}

/// @desc scr_line_coll_flush(_asset)
/// Parses the LINE_COLL asset's inline text (meta.line_string) into
/// meta.lines[] structs and recompiles the buffer. Same "tolerant text
/// editor" pattern as scr_asset_byte_data_flush — one line record per
/// text row: "x1,y1,x2,y2,type". Invalid rows are skipped and logged.
function scr_line_coll_flush(_asset) {
    var _str = "";
    if (variable_struct_exists(_asset, "meta") && variable_struct_exists(_asset.meta, "line_string")) {
        _str = string(_asset.meta.line_string);
    }

    _str = string_replace_all(_str, "\r\n", "\n");
    _str = string_replace_all(_str, "\r",   "\n");

    var _text_lines = string_split(_str, "\n");
    var _out_lines  = [];
    var _lines      = [];
    var _skipped    = 0;

    for (var _li = 0; _li < array_length(_text_lines); _li++) {
        var _row = string_trim(_text_lines[_li]);
        if (_row == "") continue;

        var _parts = string_split(_row, ",");
        if (array_length(_parts) != 5) {
            _skipped += 1;
            show_debug_message("scr_line_coll_flush: skipped row (need 5 values) \"" + _row + "\"");
            continue;
        }

        var _vals  = [0, 0, 0, 0, 0];
        var _valid = true;
        for (var _pi = 0; _pi < 5; _pi++) {
            var _tok = string_trim(_parts[_pi]);
            if (_tok == "" || !scr_str_is_decimal(_tok)) { _valid = false; break; }
            _vals[_pi] = floor(real(_tok));
        }
        if (!_valid) {
            _skipped += 1;
            show_debug_message("scr_line_coll_flush: skipped row (invalid number) \"" + _row + "\"");
            continue;
        }

        var _x1 = clamp(_vals[0], 0, 255);
        var _y1 = clamp(_vals[1], 0, 255);
        var _x2 = clamp(_vals[2], 0, 255);
        var _y2 = clamp(_vals[3], 0, 255);
        var _tp = clamp(_vals[4], 0, 7);

        array_push(_lines, { x1: _x1, y1: _y1, x2: _x2, y2: _y2, type: _tp });
        array_push(_out_lines, string(_x1) + "," + string(_y1) + "," + string(_x2) + "," + string(_y2) + "," + string(_tp));
    }

    var _serialised = string_join_ext("\n", _out_lines);
    if (variable_struct_exists(_asset, "meta")) {
        _asset.meta.line_string      = _serialised;
        _asset.meta.inline_edit_text = _serialised;
        _asset.meta.lines            = _lines;
    }

    var _bytes = scr_line_coll_compile(_lines);
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer = buffer_create(max(1, array_length(_bytes)), buffer_fixed, 1);
    for (var _bi = 0; _bi < array_length(_bytes); _bi++) {
        buffer_write(_asset.buffer, buffer_u8, _bytes[_bi]);
    }
    _asset.size = array_length(_bytes);

    if (_skipped > 0) {
        show_debug_message("scr_line_coll_flush: " + string(_skipped) + " invalid row(s) skipped.");
    }
}

/// @desc scr_line_coll_find_asset(_name)
/// Looks up a LINE_COLL asset by name in the asset manager.
function scr_line_coll_find_asset(_name) {
    if (!instance_exists(obj_asset_manager)) return undefined;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "LINE_COLL" && _a.name == _name) return _a;
    }
    return undefined;
}
