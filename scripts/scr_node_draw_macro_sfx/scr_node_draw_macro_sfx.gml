/// scr_node_draw_macro_sfx(_draw_x)
///
/// instructions[0] layout:
///   [0] "macro_sfx"
///   [1] SFX_DATA asset name  (string)
///   [2] instrument index     (integer, 0-based)
///   [3] voice                (integer, 1-3)

function scr_node_draw_macro_sfx(_draw_x) {
    while (array_length(instructions[0]) < 4) array_push(instructions[0], "");
    // Defaults
    if (!is_real(instructions[0][2]) || instructions[0][2] == "") instructions[0][2] = 0;
    if (!is_real(instructions[0][3]) || instructions[0][3] == "") instructions[0][3] = 3;

    var _asset_name = string(instructions[0][1]);
    var _sfx_index  = real(instructions[0][2]);
    var _voice      = real(instructions[0][3]);
    var _asset_set  = (_asset_name != "" && _asset_name != "0");

    var _lbl_x  = _draw_x + 6;
    var _val_x1 = _draw_x + 72;
    var _val_x2 = _draw_x + width - 8;
    var _fld_h  = 16;

    draw_set_font(fnt_c64_tiny);

    // ── Asset field ───────────────────────────────────────────────────────
    var _ay   = y + 30;
    var _ahov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _ay, _val_x2, _ay + _fld_h);

    draw_set_color(make_color_rgb(120, 80, 200));
    draw_text(_lbl_x, _ay, "SFX DATA:");
    draw_set_color(_ahov ? make_color_rgb(100, 60, 180) : make_color_rgb(50, 30, 90));
    draw_rectangle(_val_x1, _ay, _val_x2, _ay + _fld_h, false);
    draw_set_color(_asset_set ? make_color_rgb(160, 100, 255) : make_color_rgb(80, 50, 120));
    draw_rectangle(_val_x1, _ay, _val_x2, _ay + _fld_h, true);
    draw_set_halign(fa_center);
    draw_set_color(_asset_set ? c_white : c_gray);
    draw_text(_val_x1 + (_val_x2 - _val_x1) * 0.5, _ay ,
              _asset_set ? _asset_name : "PICK SFX");
    draw_set_halign(fa_left);

    // ── Instrument field — shows "N: NAME" ────────────────────────────────
    var _iy   = y + 52;
    var _ihov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _iy, _val_x2, _iy + _fld_h);

    // Resolve display name from asset
    var _sfx_count   = 0;
    var _instr_label = "N/A";
    if (_asset_set && instance_exists(obj_asset_manager)) {
        var _a = scr_sfx_data_find_asset(_asset_name);
        if (_a != noone && variable_struct_exists(_a.meta, "instruments")) {
            _sfx_count = array_length(_a.meta.instruments);
            if (_sfx_index >= 0 && _sfx_index < _sfx_count) {
                var _ins = _a.meta.instruments[_sfx_index];
                _instr_label = string(_sfx_index) + ": " + _ins.name;
            }
        }
    }

    draw_set_color(make_color_rgb(180, 140, 110));
    draw_text(_lbl_x, _iy, "INSTR:");
    draw_set_color(_ihov ? make_color_rgb(80, 60, 20) : make_color_rgb(50, 38, 12));
    draw_rectangle(_val_x1, _iy, _val_x2, _iy + _fld_h, false);
    draw_set_color(make_color_rgb(255, 180, 60));
    draw_rectangle(_val_x1, _iy, _val_x2, _iy + _fld_h, true);
    draw_set_halign(fa_center);
    draw_set_color(_sfx_count > 0 ? c_white : c_gray);
    draw_text(_val_x1 + (_val_x2 - _val_x1) * 0.5, _iy , _instr_label);
    draw_set_halign(fa_left);

    // ── Voice field ───────────────────────────────────────────────────────
    var _vy2_   = y + 74;
    // Only need a narrow box for 1/2/3 — put it inline after a label
    var _vlbl_x = _lbl_x;
    var _vbx1   = _draw_x + 50;
    var _vbx2   = _vbx1 + 28;
    var _vhov   = point_in_rectangle(mouse_x, mouse_y, _vbx1, _vy2_, _vbx2, _vy2_ + _fld_h);

    draw_set_color(make_color_rgb(100, 180, 100));
    draw_text(_vlbl_x, _vy2_, "VOICE:");
    draw_set_color(_vhov ? make_color_rgb(40, 100, 40) : make_color_rgb(20, 55, 20));
    draw_rectangle(_vbx1, _vy2_, _vbx2, _vy2_ + _fld_h, false);
    draw_set_color(make_color_rgb(80, 220, 80));
    draw_rectangle(_vbx1, _vy2_, _vbx2, _vy2_ + _fld_h, true);
    draw_set_halign(fa_center);
    draw_set_color(c_white);
    draw_text(_vbx1 + 14, _vy2_ , string(_voice));
	draw_set_halign(fa_left);
	draw_text(_vlbl_x, _vy2_ + 24, "USE THIS TO TRIGGER SFX");
    

// Info: AD/SR of selected instrument
    if (_asset_set && _sfx_count > 0) {
        var _a2 = scr_sfx_data_find_asset(_asset_name);
        if (_a2 != noone) {
            var _ins2 = scr_sfx_data_get_instrument(_a2, _sfx_index);
            if (_ins2 != noone) {
                draw_set_color(make_color_rgb(80, 60, 120));
                draw_text(_vbx2 + 8, _vy2_ + 2,
                    "AD=$" + string_upper(decimal_to_hex(_ins2.ad))
                    + " SR=$" + string_upper(decimal_to_hex(_ins2.sr))
                    + "  " + string(array_length(_ins2.wavetable_rows)) + " rows");
            }
        }
    }

// ── NO SID MACRO overlay ──────────────────────────────────────────────
    // Recompute fresh every frame — don't trust a stale flag
    var _sid_ok = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) {
			_sid_ok = true;
        }
        if (_sid_ok) break;
    }
    if (!_sid_ok) {
        var _pulse = 0.55 + 0.45 * sin(current_time * 0.006);
        draw_set_alpha(1);
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);      
		var _col = merge_colour(c_black,c_white,_pulse)
		draw_set_colour(_col);
        draw_text((x + width * 0.5)+38, (y + height * 0.5)+15, "ADD SID MACRO");
		draw_set_color(c_white);
        draw_set_halign(fa_left);
    }


}


