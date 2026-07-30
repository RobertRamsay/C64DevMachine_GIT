function scr_node_draw_macro_coll_adv(_draw_x) {

    // Backfill so old nodes don't crash — 26 slots total
    // [0]=op [1]=spr [2]=dx [3]=dy [4]=map
    // [5..12]=T1..T8  [13]=typevar [14]=locvar [15]=colvar [16]=dxvar [17]=dyvar
    // [18..25]=T9..T16
    while (array_length(instructions[0]) < 26) {
        var _len = array_length(instructions[0]);
        if (_len == 1)                    { array_push(instructions[0], 0);  }
        else if (_len == 2)               { array_push(instructions[0], 0);  }
        else if (_len == 3)               { array_push(instructions[0], 0);  }
        else                              { array_push(instructions[0], ""); }
    }
    // [26] DIRECT: the $0400 byte IS the type (bitmap hybrid), skip the scan.
    while (array_length(instructions[0]) < 27) {
        array_push(instructions[0], 0);
    }
    if (!is_real(instructions[0][26])) { instructions[0][26] = 0; }
    var _direct = real(instructions[0][26]);

    var _probe_sprite = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0;
    var _probe_dx     = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _probe_dy     = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
    var _map_name     = string(instructions[0][4]);
    // Display-only truncation so a long map name can't flood past the picker box.
    var _map_disp = _map_name;
    if (string_length(_map_disp) > 18) {
        _map_disp = string_copy(_map_disp, 1, 18) + "...";
    }
    var _dx_vnm       = is_string(instructions[0][16]) ? string(instructions[0][16]) : "";
    var _dy_vnm       = is_string(instructions[0][17]) ? string(instructions[0][17]) : "";
    var _dx_has_var   = (_dx_vnm != "" && _dx_vnm != "[clear]");
    var _dy_has_var   = (_dy_vnm != "" && _dy_vnm != "[clear]");
    var _any_var      = (_dx_has_var || _dy_has_var);

    draw_set_font(fnt_c64_tiny);

    var _type_cols = [
        make_color_rgb(200,  60,  60),
        make_color_rgb( 60, 140, 220),
        make_color_rgb(200, 160,  60),
        make_color_rgb( 80, 200, 120),
        make_color_rgb(200,  80, 200),
        make_color_rgb(220, 220,  80),
        make_color_rgb( 80, 220, 220),
        make_color_rgb(220, 140,  60),
        make_color_rgb(120, 100, 220),
        make_color_rgb( 60, 180,  80),
        make_color_rgb(220, 100, 140),
        make_color_rgb(140, 200, 200),
        make_color_rgb(180, 180,  60),
        make_color_rgb(100, 140, 180),
        make_color_rgb(200, 120,  80),
        make_color_rgb(160, 160, 160)
    ];

    // Slot N (0..15) -> instruction array index. First 8 keep their original
    // positions [5..12]; slots 8..15 (T9..T16) live at [18..25].
    var _slot_arr_idx = function(_slot_idx) {
        if (_slot_idx < 8) { return 5 + _slot_idx; }
        return 18 + (_slot_idx - 8);
    };

    // ---- PROBE SPRITE selector ----
    draw_set_color(make_color_rgb(120, 220, 120));
    draw_text(_draw_x + 6, y + 27, "PROBE SPR:");
    var _sbtn_w     = 22;
    var _sbtn_h     = 18;
    var _sbtn_gap   = 2;
    var _sbtn_sx    = _draw_x + 6;
    var _sbtn_yoffs = 44;
    for (var _si = 0; _si < 8; _si++) {
        var _bx  = _sbtn_sx + _si * (_sbtn_w + _sbtn_gap);
        var _on  = (_probe_sprite == _si);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, y + _sbtn_yoffs, _bx + _sbtn_w, y + _sbtn_yoffs + _sbtn_h);
        if (_on) {
            draw_set_color(make_color_rgb(180, 60, 220));
        } else if (_hov) {
            draw_set_color(make_color_rgb(60, 40, 70));
        } else {
            draw_set_color(make_color_rgb(35, 25, 40));
        }
        draw_rectangle(_bx, y + _sbtn_yoffs, _bx + _sbtn_w, y + _sbtn_yoffs + _sbtn_h, false);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(make_color_rgb(80, 60, 90));
        }
        draw_rectangle(_bx, y + _sbtn_yoffs, _bx + _sbtn_w, y + _sbtn_yoffs + _sbtn_h, true);
        draw_set_halign(fa_center);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(c_gray);
        }
        draw_text(_bx + _sbtn_w * 0.5, y + _sbtn_yoffs + 2, string(_si));
        draw_set_halign(fa_left);
    }

    // ---- OFFSET FROM CENTRE ----
    draw_set_color(make_color_rgb(120, 220, 120));
    draw_text(_draw_x + 6, y + 62, "OFFSET FROM CENTRE:");

    var _h        = 16;
    var _vis_left = _draw_x + width - 58;
    var _pick_x   = _draw_x + 70;
    var _pick_x2  = _draw_x + 140;

    // ---- DX row (y+78) ----
    var _dxm1 = _draw_x + 20;
    var _dxv1 = _draw_x + 35;
    var _dxp1 = _draw_x + 62;

    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 78, "DX:");

    if (point_in_rectangle(mouse_x, mouse_y, _dxm1, y + 78, _dxm1 + 18, y + 78 + _h)) {
        draw_set_color(c_white);
    } else {
        draw_set_color(c_aqua);
    }

    draw_set_halign(fa_center);
    draw_text(_dxm1 + 9, y + 78, "-");
    draw_set_halign(fa_left);

    draw_set_color(make_color_rgb(25, 25, 45));
    draw_rectangle(_dxv1, y + 78, _dxv1 + 20, y + 78 + _h, false);
    draw_set_color(make_color_rgb(80, 60, 120));
    draw_rectangle(_dxv1, y + 78, _dxv1 + 20, y + 78 + _h, true);
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_text(_dxv1 + 9, y + 78, string(_probe_dx));
    draw_set_halign(fa_left);

    if (point_in_rectangle(mouse_x, mouse_y, _dxp1, y + 78, _dxp1 + 18, y + 78 + _h)) {
        draw_set_color(c_white);
    } else {
        draw_set_color(c_aqua);
    }

    draw_set_halign(fa_center);
    draw_text(_dxp1 , y + 78, "+");
    draw_set_halign(fa_left);

    // DX pick box
    var _dx_pick_hov = point_in_rectangle(mouse_x, mouse_y, _pick_x, y + 78, _pick_x2, y + 78 + _h);
    if (_dx_has_var) {
        draw_set_color(_dx_pick_hov ? make_color_rgb(70, 60, 30) : make_color_rgb(45, 38, 18));
    } else {
        draw_set_color(_dx_pick_hov ? make_color_rgb(50, 40, 60) : make_color_rgb(30, 25, 45));
    }
    draw_rectangle(_pick_x, y + 78, _pick_x2, y + 78 + _h, false);
    draw_set_color(_dx_has_var ? make_color_rgb(160, 130, 40) : make_color_rgb(80, 60, 120));
    draw_rectangle(_pick_x, y + 78, _pick_x2, y + 78 + _h, true);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_nano);
    if (_dx_has_var) {
        draw_set_color(c_yellow);
        draw_text(_pick_x + (_pick_x2 - _pick_x) * 0.5, y + 78 + 2, _dx_vnm);
    } else {
        draw_set_color(c_gray);
        draw_text(_pick_x + (_pick_x2 - _pick_x) * 0.5, y + 78 + 2, "<PICK>");
    }
    draw_set_halign(fa_left);
	draw_set_font(fnt_c64_tiny);

    // ---- DY row (y+96) ----
    var _dym1 = _draw_x + 20;
    var _dyv1 = _draw_x + 35;
    var _dyp1 = _draw_x + 62;

    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 96, "DY:");

    if (point_in_rectangle(mouse_x, mouse_y, _dym1, y + 96, _dym1 + 18, y + 96 + _h)) {
        draw_set_color(c_white);
    } else {
        draw_set_color(c_aqua);
    }

    draw_set_halign(fa_center);
    draw_text(_dym1 + 9, y + 96, "-");
    draw_set_halign(fa_left);

    draw_set_color(make_color_rgb(25, 25, 45));
    draw_rectangle(_dyv1, y + 96, _dyv1 + 20, y + 96 + _h, false);
    draw_set_color(make_color_rgb(80, 60, 120));
    draw_rectangle(_dyv1, y + 96, _dyv1 + 20, y + 96 + _h, true);
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_text(_dyv1 + 9, y + 96, string(_probe_dy));
    draw_set_halign(fa_left);

    if (point_in_rectangle(mouse_x, mouse_y, _dyp1, y + 96, _dyp1 + 18, y + 96 + _h)) {
            draw_set_color(c_white);
    } else {
        draw_set_color(c_aqua);
    }

    draw_set_halign(fa_center);
    draw_text(_dyp1 , y + 96, "+");
    draw_set_halign(fa_left);

    // DY pick box
    var _dy_pick_hov = point_in_rectangle(mouse_x, mouse_y, _pick_x, y + 96, _pick_x2, y + 96 + _h);
    if (_dy_has_var) {
        draw_set_color(_dy_pick_hov ? make_color_rgb(70, 60, 30) : make_color_rgb(45, 38, 18));
    } else {
        draw_set_color(_dy_pick_hov ? make_color_rgb(50, 40, 60) : make_color_rgb(30, 25, 45));
    }
    draw_rectangle(_pick_x, y + 96, _pick_x2, y + 96 + _h, false);
    draw_set_color(_dy_has_var ? make_color_rgb(160, 130, 40) : make_color_rgb(80, 60, 120));
    draw_rectangle(_pick_x, y + 96, _pick_x2, y + 96 + _h, true);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_nano);
    if (_dy_has_var) {
        draw_set_color(c_yellow);
        draw_text(_pick_x + (_pick_x2 - _pick_x) * 0.5, y + 96 + 2, _dy_vnm);
    } else {
        draw_set_color(c_gray);
        draw_text(_pick_x + (_pick_x2 - _pick_x) * 0.5, y + 96 + 2, "<PICK>");
    }
    draw_set_halign(fa_left);
	draw_set_font(fnt_c64_tiny);

    // ---- VISUALISER ----
    var _vis_x = _draw_x + width - 56;
    var _vis_y = y + 70;
    var _vis_w = 48;
    var _vis_h = 42;

    draw_set_color(make_color_rgb(20, 20, 30));
    draw_rectangle(_vis_x, _vis_y, _vis_x + _vis_w, _vis_y + _vis_h, false);
    draw_set_color(make_color_rgb(80, 80, 120));
    draw_rectangle(_vis_x, _vis_y, _vis_x + _vis_w, _vis_y + _vis_h, true);

    if (_any_var) {
        // Locked — flash "USING VARS" over the visualiser

        draw_set_color(make_color_rgb(220, 160, 40));
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(_vis_x + _vis_w * 0.5, _vis_y + _vis_h * 0.5 - 4, "USING");
        draw_text(_vis_x + _vis_w * 0.5, _vis_y + _vis_h * 0.5 + 6, "VARS");
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    } else {
        // Normal crosshair visualiser
        draw_set_color(make_color_rgb(60, 60, 90));
        draw_line(_vis_x + _vis_w * 0.5, _vis_y + 2,  _vis_x + _vis_w * 0.5, _vis_y + _vis_h - 2);
        draw_line(_vis_x + 2, _vis_y + _vis_h * 0.5,  _vis_x + _vis_w - 2,   _vis_y + _vis_h * 0.5);
        var _px = _vis_x + _vis_w * 0.5 + _probe_dx * 2;
        var _py = _vis_y + _vis_h * 0.5 + _probe_dy * 2;
        if (_px < _vis_x)          { _px = _vis_x; }
        if (_px > _vis_x + _vis_w) { _px = _vis_x + _vis_w; }
        if (_py < _vis_y)          { _py = _vis_y; }
        if (_py > _vis_y + _vis_h) { _py = _vis_y + _vis_h; }
        draw_set_color(c_yellow);
        draw_line(_px - 4, _py, _px + 4, _py);
        draw_line(_px, _py - 4, _px, _py + 4);
        draw_set_color(c_red);
        draw_rectangle(_px - 1, _py - 1, _px + 1, _py + 1, false);
    }

    // ---- MAP picker row ----
    // Resolve whether the picked map name still maps to a live asset. A name
    // can dangle after a rename/delete/re-import (e.g. CTM import creates a new
    // tileset name and the old reference no longer resolves). When that happens
    // the collision table label won't match the metamap's emitted table and
    // collision silently breaks — so flash the row to make it obvious.
    var _map_exists = false;
    if (_map_name != "" && _map_name != "[clear]" && instance_exists(obj_asset_manager)) {
        var _camx = obj_asset_manager;
        for (var _cai = 0; _cai < ds_list_size(_camx.asset_list); _cai++) {
            var _caa = ds_list_find_value(_camx.asset_list, _cai);
            if ((_caa.type == "MAP_DATA" || _caa.type == "META_TILESET" || _caa.type == "META_MAP")
              && _caa.name == _map_name) {
                _map_exists = true;
                break;
            }
        }
    }
    var _map_missing = (_map_name != "" && _map_name != "[clear]" && !_map_exists);
    var _map_flash   = ((current_time div 400) mod 2 == 0);

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 220, 120));
    draw_text(_draw_x + 6, y + 116, "MAP:");
    var _mx1 = _draw_x + 40;
    var _mx2 = _draw_x + width - 28;
    var _map_hov = point_in_rectangle(mouse_x, mouse_y, _mx1, y + 116, _mx2, y + 132);

    if (_map_missing) {
        // Flashing red fill + border to scream "this reference is broken"
        if (_map_flash) {
            draw_set_color(make_color_rgb(90, 25, 25));
        } else {
            draw_set_color(make_color_rgb(50, 15, 15));
        }
        draw_rectangle(_mx1, y + 116, _mx2, y + 132, false);
        if (_map_flash) {
            draw_set_color(make_color_rgb(220, 60, 60));
        } else {
            draw_set_color(make_color_rgb(120, 40, 40));
        }
        draw_rectangle(_mx1, y + 116, _mx2, y + 132, true);
        draw_set_color(_map_flash ? c_white : make_color_rgb(220, 120, 120));
        draw_set_halign(fa_center);
        draw_text(_mx1 + (_mx2 - _mx1) * 0.5, y + 115, _map_disp + " ?");
        draw_set_halign(fa_left);
    } else {
        if (_map_hov) {
            draw_set_color(make_color_rgb(40, 60, 40));
        } else {
            draw_set_color(make_color_rgb(25, 35, 25));
        }
        draw_rectangle(_mx1, y + 116, _mx2, y + 132, false);
        draw_set_color(make_color_rgb(60, 120, 60));
        draw_rectangle(_mx1, y + 116, _mx2, y + 132, true);
        if (_map_name != "") {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(c_gray);
        }
        draw_set_halign(fa_center);
        if (_map_name != "") {
            draw_text(_mx1 + (_mx2 - _mx1) * 0.5, y + 115, _map_disp);
        } else {
            draw_text(_mx1 + (_mx2 - _mx1) * 0.5, y + 115, "< PICK MAP >");
        }
        draw_set_halign(fa_left);
    }
	
    // ---- 16 TYPE SLOTS ----
    draw_set_color(make_color_rgb(120, 220, 120));
    draw_text(_draw_x + 6, y + 136, "JSR DISPATCH (TILE TYPES 1-16):");

    // DIRECT toggle — right-aligned on this row. When on, the probe reads the
    // byte at $0400 + offset as the collision type outright (that's what
    // MOVE_BMP_BLOCK's WRITE COLL wrote from the source tags) and skips scanning
    // the MAP's TILE_TYPES. The MAP row above becomes advisory in this mode.
    var _dir_bx1 = _draw_x + width - 62;
    var _dir_bx2 = _draw_x + width - 6;
    var _dir_hov = point_in_rectangle(mouse_x, mouse_y, _dir_bx1, y + 134, _dir_bx2, y + 150);
    if (_direct == 1) {
        draw_set_color(_dir_hov ? make_color_rgb(220, 110, 90) : make_color_rgb(150, 55, 40));
        draw_rectangle(_dir_bx1, y + 134, _dir_bx2, y + 150, false);
        draw_set_color(make_color_rgb(255, 190, 170));
        draw_rectangle(_dir_bx1, y + 134, _dir_bx2, y + 150, true);
        draw_set_halign(fa_center);
        draw_text((_dir_bx1 + _dir_bx2) * 0.5, y + 135, "DIRECT");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_dir_hov ? make_color_rgb(70, 70, 95) : make_color_rgb(32, 32, 46));
        draw_rectangle(_dir_bx1, y + 134, _dir_bx2, y + 150, false);
        draw_set_color(make_color_rgb(110, 110, 140));
        draw_rectangle(_dir_bx1, y + 134, _dir_bx2, y + 150, true);
        draw_set_halign(fa_center);
        draw_text((_dir_bx1 + _dir_bx2) * 0.5, y + 135, "SCAN");
        draw_set_halign(fa_left);
    }

    var _slot_h       = 20;
    var _slot_row_y0  = y + 155;
    var _half_w       = (width - 12) * 0.5;
    var _swatch_w     = 14;
    var _label_w      = 20;
    var _picker_btn_w = 0;

    for (var _ri = 0; _ri < 8; _ri++) {
        for (var _ci = 0; _ci < 2; _ci++) {
            var _slot_idx = _ri * 2 + _ci;
            var _arr_idx  = _slot_arr_idx(_slot_idx);
            var _slot_x   = _draw_x + 6 + _ci * _half_w;
            var _slot_y   = _slot_row_y0 + _ri * _slot_h;
            var _val      = string(instructions[0][_arr_idx]);

            draw_set_color(_type_cols[_slot_idx]);
            draw_rectangle(_slot_x, _slot_y, _slot_x + _swatch_w, _slot_y + 16, false);
            draw_set_color(c_black);
            draw_rectangle(_slot_x, _slot_y, _slot_x + _swatch_w, _slot_y + 16, true);

            draw_set_color(make_color_rgb(180, 180, 180));
            draw_set_font(fnt_c64_tiny);
            draw_text(_slot_x + _swatch_w + 2, _slot_y + 2, "T" + string(_slot_idx + 1) + ":");

            var _f_x1 = _slot_x + _swatch_w + _label_w;
            var _f_x2 = _slot_x + _half_w - 6 - _picker_btn_w - 2;
            if (point_in_rectangle(mouse_x, mouse_y, _f_x1, _slot_y, _f_x2, _slot_y + 16)) {
                draw_set_color(make_color_rgb(40, 40, 70));
            } else {
                draw_set_color(make_color_rgb(25, 25, 45));
            }
            draw_rectangle(_f_x1, _slot_y, _f_x2, _slot_y + 16, false);
            draw_set_color(make_color_rgb(80, 60, 120));
            draw_rectangle(_f_x1, _slot_y, _f_x2, _slot_y + 16, true);
            if (_val != "") {
                draw_set_color(c_yellow);
            } else {
                draw_set_color(c_gray);
            }
            draw_set_halign(fa_center);
            draw_set_font(fnt_c64_nano);
            if (_val != "") {
                draw_text(_f_x1 + (_f_x2 - _f_x1) * 0.5, _slot_y + 2, _val);
            } else {
                draw_text(_f_x1 + (_f_x2 - _f_x1) * 0.5, _slot_y + 2, "---");
            }
            draw_set_halign(fa_left);
        }
    }

    // ---- OUTPUT VARS ----
    draw_set_font(fnt_c64_tiny);
    var _out_y0    = _slot_row_y0 + 8 * _slot_h + 6;
    var _out_lbl_w = 44;
    var _out_x1    = _draw_x + 6 + _out_lbl_w;
    var _out_x2    = _draw_x + width - 8;
    var _out_h     = 16;

    // TYPE>
    var _type_var = string(instructions[0][13]);
    draw_set_color(make_color_rgb(120, 220, 120));
	 draw_set_font(fnt_c64_pico);
    draw_text(_draw_x + 2, _out_y0 + 2, "TYPE(B)");
	 draw_set_font(fnt_c64_tiny);
    if (point_in_rectangle(mouse_x, mouse_y, _out_x1, _out_y0, _out_x2, _out_y0 + _out_h)) {
        draw_set_color(make_color_rgb(40, 55, 40));
    } else {
        draw_set_color(make_color_rgb(25, 35, 25));
    }
    draw_rectangle(_out_x1, _out_y0, _out_x2, _out_y0 + _out_h, false);
    draw_set_color(make_color_rgb(60, 120, 60));
    draw_rectangle(_out_x1, _out_y0, _out_x2, _out_y0 + _out_h, true);
    if (_type_var != "" && _type_var != "[clear]") {
        draw_set_color(c_yellow);
        draw_text(_out_x1 + 4, _out_y0 , _type_var);
    } else {
        draw_set_color(c_gray);
        draw_text(_out_x1 + 4, _out_y0 , "(none)");
    }

    // LOC>
    var _out_y1  = _out_y0 + _out_h + 3;
    var _loc_var = string(instructions[0][14]);
    draw_set_color(make_color_rgb(120, 220, 120));
	 draw_set_font(fnt_c64_pico);


    draw_text(_draw_x + 2, _out_y1 + 2, "LOC(W)");
		 draw_set_font(fnt_c64_tiny);
    if (point_in_rectangle(mouse_x, mouse_y, _out_x1, _out_y1, _out_x2, _out_y1 + _out_h)) {
        draw_set_color(make_color_rgb(40, 55, 40));
    } else {
        draw_set_color(make_color_rgb(25, 35, 25));
    }
    draw_rectangle(_out_x1, _out_y1, _out_x2, _out_y1 + _out_h, false);
    draw_set_color(make_color_rgb(60, 120, 60));
    draw_rectangle(_out_x1, _out_y1, _out_x2, _out_y1 + _out_h, true);
    if (_loc_var != "" && _loc_var != "[clear]") {
        draw_set_color(c_yellow);
        draw_text(_out_x1 + 4, _out_y1 , _loc_var);
    } else {
        draw_set_color(c_gray);
        draw_text(_out_x1 + 4, _out_y1 , "(none)");
    }

    // COL>
    var _out_y2  = _out_y1 + _out_h + 3;
    var _col_var = string(instructions[0][15]);
    draw_set_color(make_color_rgb(120, 220, 120));
		 draw_set_font(fnt_c64_pico);
    draw_text(_draw_x + 2, _out_y2 + 2, "COLR(W)");
		 draw_set_font(fnt_c64_tiny);
    if (point_in_rectangle(mouse_x, mouse_y, _out_x1, _out_y2, _out_x2, _out_y2 + _out_h)) {
        draw_set_color(make_color_rgb(40, 55, 40));
    } else {
        draw_set_color(make_color_rgb(25, 35, 25));
    }
    draw_rectangle(_out_x1, _out_y2, _out_x2, _out_y2 + _out_h, false);
    draw_set_color(make_color_rgb(60, 120, 60));
    draw_rectangle(_out_x1, _out_y2, _out_x2, _out_y2 + _out_h, true);
    if (_col_var != "" && _col_var != "[clear]") {
        draw_set_color(c_yellow);
        draw_text(_out_x1 + 4, _out_y2 , _col_var);
    } else {
        draw_set_color(c_gray);
        draw_text(_out_x1 + 4, _out_y2 , "(none)");
    }
    draw_set_halign(fa_left);
}