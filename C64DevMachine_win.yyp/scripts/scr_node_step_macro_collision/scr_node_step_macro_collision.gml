function scr_node_step_macro_collision(_draw_x) {
    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _tbtn_w  = 56;
    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];

    // ---- TYPE buttons (y+42) ----
    for (var _ti = 0; _ti < 3; _ti++) {
        var _bx = _draw_x + 6 + _ti * (_tbtn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, y + 42, _bx + _tbtn_w, y + 42 + _btn_h)) {
            instructions[0][2] = _ti;
            global.addresses_dirty = true;
            exit;
        }
    }

    // ---- SPRITE A (single-select, y+84) ----
    var _ga_val = real(instructions[0][1]);
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _draw_x + 6 + _si * (_btn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, y + 84, _bx + _btn_w, y + 84 + _btn_h)) {
            // Radio behaviour: clicking the active sprite clears it, else select only this one
            if (_ga_val == _bit_values[_si]) {
                instructions[0][1] = 0;
            } else {
                instructions[0][1] = real(_bit_values[_si]);
            }
            global.addresses_dirty = true;
            exit;
        }
    }

    // ---- SPRITE B (single-select, y+126) ----
    var _gb_val = 0;
    if (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) {
        _gb_val = real(instructions[0][5]);
    }
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _draw_x + 6 + _si * (_btn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, y + 126, _bx + _btn_w, y + 126 + _btn_h)) {
            if (_gb_val == _bit_values[_si]) {
                instructions[0][5] = 0;
            } else {
                instructions[0][5] = real(_bit_values[_si]);
            }
            global.addresses_dirty = true;
            exit;
        }
    }

    // ---- MODE toggle (y+152) ----
    var _mbtn_w = 40;
    for (var _mi = 0; _mi < 2; _mi++) {
        var _bx = _draw_x + 60 + _mi * (_mbtn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, y + 152, _bx + _mbtn_w, y + 152 + _btn_h)) {
            instructions[0][4] = _mi;
            global.addresses_dirty = true;
            exit;
        }
    }

    // ---- JSR label picker (y+174) ----
    var _zx1 = _draw_x + 60;
    var _zx2 = _draw_x + width - 4;
    if (point_in_rectangle(mouse_x, mouse_y, _zx1, y + 174, _zx2, y + 190)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_index      = 3;
        label_picker_scroll     = 0;
        label_picker_list       = ["[clear]"];
        label_picker_mode       = "JUMP";
        label_picker_target     = id;
        with (obj_c64_node) {
            if (node_type == "LABEL") {
                array_push(other.label_picker_list, string_replace_all(string(instructions[0][1]), " ", "_"));
            }
            if (node_type == "MACRO_ANIM") {
                if (!variable_instance_exists(id, "anim_alias") || anim_alias == "") {
                    anim_alias = "anim" + string(real(id));
                }
                array_push(other.label_picker_list, anim_alias + "_sub");
                array_push(other.label_picker_list, anim_alias + "_reset");
            }
            if (node_type == "MACRO_SCROLL") {
                    array_push(other.label_picker_list, "Scroller_L");
                    array_push(other.label_picker_list, "Scroller_R");
                }
                if (node_type == "MACRO_SID_SONG") {
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_play");
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_init");
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_seek");
                }
            if (node_type == "MACRO_VSCROLL") {
                array_push(other.label_picker_list, "Scroller_U");
                array_push(other.label_picker_list, "Scroller_D");
            }
        }
        exit;
    }
    exit;
}