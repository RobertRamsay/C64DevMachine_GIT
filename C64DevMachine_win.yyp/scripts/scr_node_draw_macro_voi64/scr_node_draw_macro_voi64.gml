/// @desc Draw for both Voi64 nodes.
///
/// MACRO_VOI64_MASTER instructions[0]:
///   ["macro_voi64_master", 1 pitch, 2 speed, 3 throat, 4 mouth, 5 zp_base]
///
/// MACRO_VOI64_SAY instructions[0]:
///   ["macro_voi64_say", 1 -, 2 -, 3 mode(0=TEXT,1=PHONEME),
///    4 src(0=INLINE,1=TEXT_DATA), 5 inline_text, 6 asset_name,
///    7 pitch, 8 speed, 9 throat, 10 mouth]     -1 in 7-10 means inherit

function scr_node_draw_macro_voi64_master(_draw_x, _y) {
    var _ins = instructions[0];

    var _pitch  = 120; if (array_length(_ins) > 1 && is_real(_ins[1])) { _pitch  = real(_ins[1]); }
    var _speed  = 128; if (array_length(_ins) > 2 && is_real(_ins[2])) { _speed  = real(_ins[2]); }
    var _throat = 128; if (array_length(_ins) > 3 && is_real(_ins[3])) { _throat = real(_ins[3]); }
    var _mouth  = 128; if (array_length(_ins) > 4 && is_real(_ins[4])) { _mouth  = real(_ins[4]); }
    var _zp     = 0xFB; if (array_length(_ins) > 5 && is_real(_ins[5])) { _zp    = real(_ins[5]) & 0xFF; }

    var _lh = 14;
    var _ly = _y + 28;
    var _px = _draw_x + 8;

    var _c_lbl = make_color_rgb(140, 160, 200);
    var _c_val = make_color_rgb(230, 210, 120);
    var _c_dim = make_color_rgb(90, 90, 100);

    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_left);

    draw_set_color(_c_lbl); draw_text(_px, _ly, "PITCH:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, string(_pitch) + " HZ");
    _ly += _lh;

    draw_set_color(_c_lbl); draw_text(_px, _ly, "SPEED:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, string(_speed));
    _ly += _lh;

    draw_set_color(_c_lbl); draw_text(_px, _ly, "THROAT:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, string(_throat));
    _ly += _lh;

    draw_set_color(_c_lbl); draw_text(_px, _ly, "MOUTH:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, string(_mouth));
    _ly += _lh;

    // Show the CLAMPED base, because that is what the build uses. A node
    // still holding $FB from before the block grew would otherwise read
    // $FB while the emitted code used $F7.
    _zp = clamp(_zp, 0x02, 0xF7);
    var _zh = string_upper(decimal_to_hex(_zp));
    while (string_length(_zh) < 2) { _zh = "0" + _zh; }
    draw_set_color(_c_lbl); draw_text(_px, _ly, "ZP:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, "$" + _zh + " (9)");
    _ly += _lh;

    // The player is blocking. Say it on the face of the node — a user who
    // finds this out from a stalled raster split has already lost an hour.
    draw_set_color(make_color_rgb(220, 110, 90));
    draw_text(_px, _ly, "BLOCKS: NO IRQ / NO MUSIC");
    _ly += _lh;

    draw_set_color(_c_dim);
    draw_text(_px, _ly, "SETS UP SID + PLAYER");
}

function scr_node_draw_macro_voi64_say(_draw_x, _y) {
    var _ins = instructions[0];

    var _mode = 0; if (array_length(_ins) > 3 && is_real(_ins[3])) { _mode = real(_ins[3]); }
    var _src  = 0; if (array_length(_ins) > 4 && is_real(_ins[4])) { _src  = real(_ins[4]); }
    var _text = ""; if (array_length(_ins) > 5) { _text = string(_ins[5]); }
    var _asset = ""; if (array_length(_ins) > 6) { _asset = string(_ins[6]); }

    var _lh = 14;
    var _ly = _y + 28;
    var _px = _draw_x + 8;

    var _c_lbl = make_color_rgb(140, 160, 200);
    var _c_val = make_color_rgb(230, 210, 120);
    var _c_dim = make_color_rgb(90, 90, 100);

    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_left);

    draw_set_color(_c_lbl); draw_text(_px, _ly, "MODE:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, (_mode == 1) ? "PHONEME" : "TEXT");
    _ly += _lh;

    draw_set_color(_c_lbl); draw_text(_px, _ly, "SRC:");
    draw_set_color(_c_val); draw_text(_px + 62, _ly, (_src == 1) ? "TEXT DATA" : "INLINE");
    _ly += _lh;

    var _shown = (_src == 1) ? _asset : _text;
    if (_shown == "") { _shown = (_src == 1) ? "<CLICK TO PICK>" : "<CLICK TO TYPE>"; }
    if (string_length(_shown) > 22) { _shown = string_copy(_shown, 1, 21) + "*"; }
    draw_set_color(_c_lbl); draw_text(_px, _ly, "SAY:");
    draw_set_color((_shown == "<CLICK TO PICK>" || _shown == "<CLICK TO TYPE>") ? _c_dim : _c_val);
    draw_text(_px + 32, _ly, _shown);
    _ly += _lh;

    // LINES range — TEXT DATA mode only. One phrase per line turns a single
    // asset into a phrase bank several SAY nodes can share.
    if (_src == 1) {
        var _lf = 0;
        var _lt = 0;
        if (array_length(_ins) > 11 && is_real(_ins[11])) { _lf = real(_ins[11]); }
        if (array_length(_ins) > 12 && is_real(_ins[12])) { _lt = real(_ins[12]); }
        var _lc = scr_voi64_asset_line_count(id);

        var _fmode = 0;
        var _tmode = 0;
        var _fvar  = "";
        var _tvar  = "";
        if (array_length(_ins) > 13 && is_real(_ins[13])) { _fmode = real(_ins[13]); }
        if (array_length(_ins) > 14) { _fvar = string(_ins[14]); }
        if (array_length(_ins) > 15 && is_real(_ins[15])) { _tmode = real(_ins[15]); }
        if (array_length(_ins) > 16) { _tvar = string(_ins[16]); }

        // VAR / LIT button on the right of each row, same shape as the one
        // on MACRO_SID_SOUND's index row.
        var _vbw = 30;
        var _vbx = _draw_x + width - 8 - _vbw;

        var _rows = [
            { lab: "LINE FROM:", mode: _fmode, vname: _fvar, lit: _lf, dflt: "1 (START)" },
            { lab: "LINE TO:",   mode: _tmode, vname: _tvar, lit: _lt,
              dflt: (_lc > 0) ? (string(_lc) + " (END)") : "END" }
        ];
        for (var _ri = 0; _ri < 2; _ri++) {
            var _rw = _rows[_ri];
            draw_set_color(_c_lbl); draw_text(_px, _ly, _rw.lab);
            if (_rw.mode == 1) {
                if (_rw.vname == "") {
                    draw_set_color(make_color_rgb(220, 110, 90));
                    draw_text(_px + 78, _ly, "<PICK VAR>");
                } else if (scr_resolve_var_addr(_rw.vname) == 0) {
                    draw_set_color(make_color_rgb(220, 110, 90));
                    draw_text(_px + 78, _ly, _rw.vname + " ?");
                } else {
                    draw_set_color(make_color_rgb(180, 230, 140));
                    draw_text(_px + 78, _ly, _rw.vname);
                }
            } else if (_rw.lit <= 0) {
                draw_set_color(_c_dim); draw_text(_px + 78, _ly, _rw.dflt);
            } else {
                draw_set_color(_c_val); draw_text(_px + 78, _ly, string(_rw.lit));
            }
            draw_set_color((_rw.mode == 1) ? make_color_rgb(60, 110, 60) : make_color_rgb(40, 40, 55));
            draw_rectangle(_vbx, _ly + 1, _vbx + _vbw, _ly + 11, false);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_vbx + (_vbw / 2), _ly - 1, (_rw.mode == 1) ? "VAR" : "LIT");
            draw_set_halign(fa_left);
            _ly += _lh;
        }
    }

    // Per-say voice overrides. A dash means "inherit from the master",
    // which is the default and by far the common case — showing an actual
    // number here would imply this node is setting one when it is not.
    var _lbls = ["PITCH", "SPEED", "THROAT", "MOUTH"];
    for (var _k = 0; _k < 4; _k++) {
        var _v = -1;
        if (array_length(_ins) > (7 + _k) && is_real(_ins[7 + _k])) { _v = real(_ins[7 + _k]); }
        draw_set_color(_c_lbl); draw_text(_px, _ly, _lbls[_k] + ":");
        if (_v < 0) {
            draw_set_color(_c_dim); draw_text(_px + 62, _ly, "-");
        } else {
            draw_set_color(_c_val); draw_text(_px + 62, _ly, string(_v));
        }
        _ly += _lh;
    }

    // Preview button. Plays through the GML synth using the same phoneme
    // string the compiler will emit, so what you hear here is what the
    // build will say.
    var _bx1 = _draw_x + 8;
    var _by1 = _ly + 1;
    var _bx2 = _draw_x + width - 8;
    var _by2 = _by1 + 12;
    var _hov = point_in_rectangle(mouse_x, mouse_y, _bx1, _by1, _bx2, _by2);
    draw_set_color(_hov ? make_color_rgb(60, 140, 90) : make_color_rgb(24, 70, 48));
    draw_rectangle(_bx1, _by1, _bx2, _by2, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_bx1 + _bx2) / 2, _by1 -2, "PREVIEW VOICE");
    draw_set_halign(fa_left);
    _ly += _lh;

    // No master, no player routine and no default voice, so the build
    // emits nothing for this node. Flag it here rather than in the log.
    if (!instance_exists(scr_voi64_find_master())) {
        draw_set_color(make_color_rgb(220, 110, 90));
        draw_text(_px, _ly, "NO VOI64 MASTER CONNECTED");
    } else if (_src == 1 && string_trim(scr_voi64_say_source_text(id)) == "") {
        // Named asset missing, renamed, or empty. Without this the only
        // symptom is a node reading 0 BYTES and a silent build.
        draw_set_color(make_color_rgb(220, 110, 90));
        draw_text(_px, _ly, (_asset == "") ? "NO ASSET PICKED" : "ASSET EMPTY OR MISSING");
    }
}
