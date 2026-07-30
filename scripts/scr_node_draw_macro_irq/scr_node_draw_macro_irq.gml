function scr_node_draw_macro_irq(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {
// instructions[0] layout:
//   [0]="macro_irq" [1]=raster_line [2]=play_music [3]=asset_name
//   [4]=alias (string — user-editable JSR label)

    var _raster     = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0x60;
    var _play_music = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    var _asset_name = (array_length(instructions[0]) > 3) ? string(instructions[0][3]) : "";
    var _alias      = (array_length(instructions[0]) > 4 && string(instructions[0][4]) != "") ? string(instructions[0][4]) : ("irq" + string(real(id)));
    if (string(instructions[0][4]) == "") {
        if (!variable_instance_exists(id, "irq_auto_assigned") || !irq_auto_assigned) {
            var _taken = [];
            with (obj_c64_node) {
                if (id != other.id && node_type == "MACRO_IRQ") {
                    var _n = (array_length(instructions[0]) > 4) ? string(instructions[0][4]) : "";
                    if (_n != "") array_push(_taken, _n);
                }
            }
            var _n = 0;
            var _candidate = "";
            do {
                _candidate = "irq_" + string(_n);
                _n++;
            } until (!array_contains(_taken, _candidate) || _n > 32);
            instructions[0][4]  = _candidate;
            irq_auto_assigned   = true;
            _alias              = _candidate;
        }
    }

    var _sid_present = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID") { _sid_present = true; break; }
    }

    var _px = _draw_x + 8;
    var _ly = _y + 24 + 4;
    var _lh = 12;
       draw_set_font(fnt_c64_tiny);

    // ROW 0 — RASTER LINE
    draw_set_color(c_gray);
    draw_text(_px, _ly, "RASTER:");
    draw_set_color(c_aqua);
    draw_text(_px + 80, _ly, "$" + string_upper(decimal_to_hex(_raster)) + "  (" + string(_raster) + ")");
    _ly += _lh;

    // ROW 1 — requirement note
 
    var _handler_mode = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ_HANDLER" && is_connected) {
            _handler_mode = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0;
            break;
        }
    }
    if (_handler_mode == 1) {
        if (!global.kernal_unlocked) { var _kfl2 = (current_time mod 600 < 300) ? make_color_rgb(255, 80, 80) : make_color_rgb(223, 180, 40); draw_set_color(_kfl2); draw_text(_px, _ly, "!REQ: UNLOCK KERNAL"); }
        if (global.kernal_unlocked)  { draw_set_color(make_color_rgb(100, 240, 150)); draw_text(_px, _ly, "KERNAL IS UNLOCKED."); }
    } else {
        draw_set_color(make_color_rgb(100, 240, 150));
        draw_text(_px, _ly, "KERNAL MODE - OK.");
    }
    _ly += _lh+_lh;

    // ROW 2 — CALL LABEL (user subroutine to JSR into handler)
    var _call_label = (array_length(instructions[0]) > 5 && string(instructions[0][5]) != "") ? string(instructions[0][5]) : "";
    draw_set_color(c_gray);
    draw_text(_px, _ly, "JSR:");
    if (_call_label != "") {
        draw_set_color(c_white);
        draw_text(_px + 52, _ly, _call_label);
    } else {
        draw_set_color(c_yellow);
        draw_text(_px + 52, _ly, "(none)");
    }
    _ly += _lh;

    // Placement validation
    var _is_invalid_pos = false;
    if (is_connected) {
        if (org_parent != noone) {
            if (org_parent.node_type != "INIT") {
                _is_invalid_pos = true;
            }
        } else {
            with (obj_c64_node) {
                if (is_connected && org_parent == noone && id != other.id && y < other.y && node_type != "INIT" && node_type != "LABEL" && node_type != "COMMENT" && node_type != "MACRO_SID" && node_type != "MACRO_IRQ" && node_type != "MACRO_IRQ_HANDLER" && node_title != "KERNAL RAM UNLOCK" && node_title != "BASIC ROM UNLOCK") {
                    _is_invalid_pos = true;
                }
            }
        }
    }

    // Draw Status Text
    if (is_connected) {
        draw_set_halign(fa_center);

        var _handler_present = false;
        with (obj_c64_node) {
            if (node_type == "MACRO_IRQ_HANDLER" && is_connected) { _handler_present = true; break; }
        }
		draw_set_font(fnt_c64_nano);
        if (!_sid_present && !_handler_present) {
            var _flash_col = (current_time mod 600 < 300) ? c_white : c_black;
            draw_set_color(_flash_col);
			_ly+=6
            draw_text(_draw_x + (width / 2), _ly, "REQUIRES SID OR IRQ HANDLER NODE");
            _ly += _lh;
        } else {
            draw_set_color(make_color_rgb(80, 200, 80));
            draw_text(_draw_x + (width / 2), _ly+8, "NODE IN PLACE");
            _ly += _lh;
        }
        draw_set_halign(fa_left);
		draw_set_font(fnt_c64_tiny);
    }

    var _has_sid_irq = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER") && is_connected && org_parent == noone)
            { _has_sid_irq = true; break; }
    }
	

}