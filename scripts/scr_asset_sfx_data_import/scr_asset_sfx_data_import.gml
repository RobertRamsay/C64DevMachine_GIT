/// scr_asset_sfx_data_import(_asset)
/// Imports a GoatTracker 2 .sng file as an SFX_DATA asset.
/// Parses all instruments and the full wavetable natively.
/// No binary conversion — the .sng is the source of truth.
///
/// _asset.meta layout after import:
///   .song_name    string
///   .sfx_count    integer
///   .instruments  array of structs — see below
///   .wavetable    { left[], right[] }
///
/// Instrument struct:
///   .index          0-based
///   .name           string (up to 16 chars from GT)
///   .ad .sr         byte
///   .wave_pos       byte (1-based GT pointer; 0 = no wavetable)
///   .wavetable_rows array of { left, right, row } — sliced from full table

function scr_asset_sfx_data_import(_asset, _force_file = "") {

    var _file = _force_file;
    if (_file == "") _file = get_open_filename("GoatTracker Song|*.sng", "");
    if (_file == "" || !file_exists(_file)) exit;

    var _buf = buffer_load(_file);
    if (!buffer_exists(_buf)) exit;
    var _sz = buffer_get_size(_buf);

    // ── Header check ──────────────────────────────────────────────────────
    var _hdr = "";
    for (var _i = 0; _i < 4; _i++) _hdr += chr(buffer_peek(_buf, _i, buffer_u8));
    if (_hdr != "GTS5") {
        scr_show_message("Not a GoatTracker v2 song (expected GTS5 header).");
        buffer_delete(_buf);
        exit;
    }

    // ── Song name ─────────────────────────────────────────────────────────
    var _song_name = "";
    for (var _i = 4; _i < 36; _i++) {
        var _c = buffer_peek(_buf, _i, buffer_u8);
        if (_c == 0) break;
        _song_name += chr(_c);
    }

    // ── Skip orderlists ───────────────────────────────────────────────────
    var _num_subtunes = buffer_peek(_buf, 100, buffer_u8);
    var _offset = 101;
    for (var _sub = 0; _sub < _num_subtunes; _sub++) {
        for (var _ch = 0; _ch < 3; _ch++) {
            if (_offset >= _sz) break;
            var _n = buffer_peek(_buf, _offset, buffer_u8);
            _offset += 1 + _n + 1; // length byte + n entries + RST restart byte
        }
    }

    if (_offset >= _sz) {
        scr_show_message("SNG parse error: file truncated before instrument block.");
        buffer_delete(_buf);
        exit;
    }

    // ── Instruments ───────────────────────────────────────────────────────
    var _num_instr = buffer_peek(_buf, _offset, buffer_u8);
    _offset++;

    var _instruments = [];
    for (var _ii = 0; _ii < _num_instr; _ii++) {
        if (_offset + 25 > _sz) break;

        var _name = "";
        for (var _ni = 0; _ni < 16; _ni++) {
            var _nc = buffer_peek(_buf, _offset + 9 + _ni, buffer_u8);
            if (_nc == 0) break;
            _name += chr(_nc);
        }
        if (_name == "") _name = "SFX" + string(_ii + 1);

        array_push(_instruments, {
            index         : _ii,
            name          : _name,
            ad            : buffer_peek(_buf, _offset + 0, buffer_u8),
            sr            : buffer_peek(_buf, _offset + 1, buffer_u8),
            wave_pos      : buffer_peek(_buf, _offset + 2, buffer_u8),
            pulse_pos     : buffer_peek(_buf, _offset + 3, buffer_u8),
            filt_pos      : buffer_peek(_buf, _offset + 4, buffer_u8),
            vib_param     : buffer_peek(_buf, _offset + 5, buffer_u8),
            vib_delay     : buffer_peek(_buf, _offset + 6, buffer_u8),
            gate_timer    : buffer_peek(_buf, _offset + 7, buffer_u8),
            first_wave    : buffer_peek(_buf, _offset + 8, buffer_u8),
            wavetable_rows: []
        });
        _offset += 25; // 9 param bytes + 16 name bytes
    }

    // ── Tables (wavetable, pulsetable, filtertable, speedtable) ──────────
    var _table_keys = ["wavetable", "pulsetable", "filtertable", "speedtable"];
    var _tables = {};
    for (var _ti = 0; _ti < 4; _ti++) {
        if (_offset >= _sz) break;
        var _n = buffer_peek(_buf, _offset, buffer_u8);
        _offset++;
        var _left  = array_create(_n, 0);
        var _right = array_create(_n, 0);
        for (var _ri = 0; _ri < _n; _ri++) {
            if (_offset + _ri < _sz) _left[_ri]  = buffer_peek(_buf, _offset + _ri, buffer_u8);
        }
        _offset += _n;
        for (var _ri = 0; _ri < _n; _ri++) {
            if (_offset + _ri < _sz) _right[_ri] = buffer_peek(_buf, _offset + _ri, buffer_u8);
        }
        _offset += _n;
        variable_struct_set(_tables, _table_keys[_ti], { left: _left, right: _right });
    }

    buffer_delete(_buf);

    // ── Slice wavetable rows per instrument ───────────────────────────────
    var _wt = variable_struct_exists(_tables, "wavetable") ? _tables.wavetable : noone;
    for (var _ii = 0; _ii < array_length(_instruments); _ii++) {
        var _instr  = _instruments[_ii];
        if (_wt == noone || _instr.wave_pos == 0) continue;
        var _pos    = _instr.wave_pos - 1; // 0-based
        var _wt_len = array_length(_wt.left);
        var _seen   = ds_map_create();
        while (_pos >= 0 && _pos < _wt_len) {
            if (ds_map_exists(_seen, _pos)) break;
            ds_map_add(_seen, _pos, true);
            var _L = _wt.left[_pos];
            var _R = _wt.right[_pos];
            array_push(_instr.wavetable_rows, { left: _L, right: _R, row: _pos + 1 });
            if (_L == 0xFF) break;
            _pos++;
        }
        ds_map_destroy(_seen);
    }

    // ── Commit ────────────────────────────────────────────────────────────
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer           = buffer_create(1, buffer_fixed, 1);
    _asset.file             = _file;
    _asset.meta.song_name   = _song_name;
    _asset.meta.instruments = _instruments;
    _asset.meta.wavetable   = _wt;
    _asset.meta.sfx_count   = array_length(_instruments);
    if (_asset.address == 0) _asset.address = 0x3000;

// Keep file pointing at source — no local copy needed
    _asset.file = _file;

    show_debug_message("SFX_DATA imported: '" + _song_name
        + "'  " + string(array_length(_instruments)) + " instruments");
    for (var _ii = 0; _ii < array_length(_instruments); _ii++) {
        var _ins = _instruments[_ii];
        show_debug_message("  [" + string(_ii) + "] '" + _ins.name
            + "'  AD=$" + string_upper(decimal_to_hex(_ins.ad))
            + "  SR=$"  + string_upper(decimal_to_hex(_ins.sr))
            + "  wpos=" + string(_ins.wave_pos)
            + "  rows=" + string(array_length(_ins.wavetable_rows)));
    }
	
	if (variable_struct_exists(_asset, "meta")) _asset.meta._mtime = md5_file(_asset.file);
}


