function Script349(){

}/// @desc scr_node_draw_macro_sid_song(_draw_x, _y)
/// instructions[0]: ["macro_sid_song",
///   1 asset_name, 2 auto_init, 3 zp_base, 4 reserved, 5 reserved]
///
/// One picker drives everything — patterns, instruments, order and speed all
/// come from the SOUND_EDITOR asset's meta at compile time. The node's job is
/// to name the asset and report what it will emit, so a mistyped or emptied
/// asset is caught here rather than at build.
function scr_node_draw_macro_sid_song(_draw_x, _y) {

    var _ins = instructions[0];

    var _asset_name = (array_length(_ins) > 1) ? string(_ins[1]) : "";
    var _auto_init  = (array_length(_ins) > 2 && is_real(_ins[2])) ? real(_ins[2]) : 1;
    var _zp         = (array_length(_ins) > 3 && is_real(_ins[3])) ? (real(_ins[3]) & 0xFF) : 0x3;

    var _lh = 14;
    var _ly = _y + 28;

    var _c_lbl  = make_color_rgb(140, 160, 200);
    var _c_dim  = make_color_rgb(90, 90, 100);
    var _c_ast  = make_color_rgb(255, 190, 90);
    var _c_bad  = make_color_rgb(230, 90, 90);
    var _c_info = make_color_rgb(80, 120, 180);

    draw_set_font(fnt_c64_tiny);

    // ===== SONG (SOUND_EDITOR asset picker) =====
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "SONG:");
    if (_asset_name == "" || _asset_name == "[clear]") {
        draw_set_color(_c_bad);
        draw_text(_draw_x + 62, _ly, "< PICK SONG >");
    } else {
        draw_set_color(_c_ast);
        var _disp = _asset_name;
        if (string_length(_disp) > 14) {
            _disp = string_copy(_disp, 1, 14) + "...";
        }
        draw_text(_draw_x + 62, _ly, _disp);
    }
    _ly += _lh;

    // ===== AUTO INIT checkbox =====
    // On: the spine JSRs <key>_init where the node sits, so the node is
    // drop-and-go. Off: the user calls it themselves, which matters when the
    // song must start at a specific point rather than wherever the node lands.
    var _cbx = _draw_x + 10;
    if (_auto_init == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_auto_init == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text(_cbx + 18, _ly, "AUTO INIT");
    _ly += _lh;

    // ===== ZP base =====
    var _zp_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 3);
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "ZP:");
    if (_zp_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 46, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _zh = decimal_to_hex(_zp);
        while (string_length(_zh) < 2) _zh = "0" + _zh;
        draw_set_color(c_aqua);
        draw_text(_draw_x + 46, _ly, "$" + string_upper(_zh));
    }
    draw_set_color(_c_dim);
    draw_text(_draw_x + 76, _ly, "44 BYTES");

    // ── HARD RESTART ── click cycles 0-8. 0 = off.
    var _hr_val = (array_length(_ins) > 4 && is_real(_ins[4])) ? clamp(real(_ins[4]), 0, 8) : 2;
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 132, _ly, "HR:");
    if (_hr_val == 0) {
        draw_set_color(_c_dim);
        draw_text(_draw_x + 178, _ly, "OFF");
    } else {
        draw_set_color(c_lime);
        draw_text(_draw_x + 154, _ly, string(_hr_val) + " Frms");
    }
    _ly += _lh;

    // ===== Resolve the asset and report what will be emitted =====
    // Everything here is read-only feedback. It exists so an empty song, a
    // renamed asset or a runaway table size is visible on the node rather
    // than only in the debug log at build time.
    var _found    = false;
    var _n_instr  = 0;
    var _n_pat    = 0;
    var _n_ord    = 0;
    var _n_songs  = 0;
    var _speed    = 6;
    var _loops    = true;
    var _bytes    = 0;

    if (_asset_name != "" && _asset_name != "[clear]" && instance_exists(obj_asset_manager)) {
        var _am_sg = obj_asset_manager;
        for (var _sgi = 0; _sgi < ds_list_size(_am_sg.asset_list); _sgi++) {
            var _a_sg = ds_list_find_value(_am_sg.asset_list, _sgi);
            if (_a_sg.type != "MUSIC_MAKER" || _a_sg.name != _asset_name) {
                continue;
            }
            _found = true;
            var _sm = _a_sg.meta;

            if (variable_struct_exists(_sm, "instruments") && is_array(_sm.instruments)) {
                _n_instr = array_length(_sm.instruments);
            }
            if (variable_struct_exists(_sm, "patterns") && is_array(_sm.patterns)) {
                _n_pat = array_length(_sm.patterns);
            }
            // Order rows now live per-song in songs[]; song_order is retired.
            // Total across every song is what the emitter concatenates, so
            // that's the number the footprint estimate needs.
            if (variable_struct_exists(_sm, "songs") && is_array(_sm.songs)) {
                _n_songs = array_length(_sm.songs);
                for (var _sci = 0; _sci < _n_songs; _sci++) {
                    var _sc = _sm.songs[_sci];
                    if (variable_struct_exists(_sc, "order") && is_array(_sc.order)) {
                        _n_ord += array_length(_sc.order);
                    }
                }
                // LOOP/ONCE on the node reflects song 0, the one AUTO INIT starts.
                if (_n_songs > 0 && variable_struct_exists(_sm.songs[0], "loop")) {
                    _loops = _sm.songs[0].loop;
                }
            } else if (variable_struct_exists(_sm, "song_order") && is_array(_sm.song_order)) {
                // Pre-songs[] asset never opened in the editor — the emitter
                // folds this into one song, so report it the same way.
                _n_songs = 1;
                _n_ord   = array_length(_sm.song_order);
                if (variable_struct_exists(_sm, "song_loop")) {
                    _loops = _sm.song_loop;
                }
            }
            if (variable_struct_exists(_sm, "play_speed") && is_real(_sm.play_speed)) {
                _speed = real(_sm.play_speed);
            }

            // Footprint estimate — mirrors what the compile case emits so the
            // number on the node matches the memory bar.
            //   instruments: 4 header + compiled stream, + 2 pointer tables
            //   patterns:    2 bytes/row, + 2 pointer tables + 1 length table
            //   order:       5 bytes/row (v1,v2,v3,len,wrap)
            for (var _bi = 0; _bi < _n_instr; _bi++) {
                var _b_ins = _sm.instruments[_bi];
                var _b_txt = "";
                if (variable_struct_exists(_b_ins, "text")) {
                    _b_txt = string(_b_ins.text);
                }
                _bytes += 4 + array_length(scr_instrument_parse(_b_txt).bytes);
            }
            _bytes += _n_instr * 2;
            for (var _bp = 0; _bp < _n_pat; _bp++) {
                var _bp_len = 64;
                if (variable_struct_exists(_sm.patterns[_bp], "pattern_len")) {
                    _bp_len = real(_sm.patterns[_bp].pattern_len);
                }
                _bytes += _bp_len * 2;
            }
            _bytes += _n_pat * 3;
            _bytes += _n_ord * 5;
            _bytes += _n_songs * 4;   // songstart/songend/songloop/songflag
            break;
        }
    }

    // ===== Footer =====
    draw_set_font(fnt_c64_pico);
    if (_asset_name == "" || _asset_name == "[clear]") {
        draw_set_color(_c_dim);
        draw_text(_draw_x + 8, _ly, "NO SONG SELECTED");
    } else if (!_found) {
        draw_set_color(_c_bad);
        draw_text(_draw_x + 8, _ly, "! SONG NOT FOUND");
    } else if (_n_pat == 0 || _n_ord == 0 || _n_songs == 0) {
        draw_set_color(_c_bad);
        draw_text(_draw_x + 8, _ly, "! EMPTY SONG - NOTHING EMITTED");
    } else {
        draw_set_color(_c_info);
        draw_text(_draw_x + 8, _ly,
            string(_n_songs) + " SNG  " + string(_n_pat) + " PAT  "
            + string(_n_instr) + " INS  " + string(_n_ord) + " ORD");
        _ly += 10;
        draw_set_color(_c_info);
        draw_text(_draw_x + 8, _ly,
            string(_bytes) + "B DATA   SPD " + string(_speed) + (_loops ? "   LOOP" : "   ONCE"));
    }
    _ly += 10;

    // The player banks BASIC out permanently and parks its state in BASIC's
    // floating-point scratch. Worth saying on the node — it's the one thing
    // here with consequences outside this node.
    draw_set_color(make_color_rgb(200, 140, 60));
    draw_text(_draw_x + 8, _ly, "INIT BANKS OUT BASIC ($01=$36)");
    _ly += 10;

    draw_set_color(make_color_rgb(90, 110, 150));
    draw_text(_draw_x + 8, _ly, "JSR " + "sng" + string(stable_uid) + "_play  EACH FRAME");
    _ly += 10;
    draw_set_color(make_color_rgb(90, 110, 150));
    draw_text(_draw_x + 8, _ly, "A=SONG X=ROW  JSR " + "sng" + string(stable_uid) + "_seek");

    draw_set_font(fnt_c64_tiny);
}