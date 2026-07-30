function scr_node_draw_macro_irq_handler(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {
    // instructions[0] layout:
    //   [0]="macro_irq_handler"
    //   [1]=vector_mode  (0=$0314, 1=$FFFE direct)
    var _mode     = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0;
    var _px       = _draw_x + 8;
    var _ly       = _y + 28; // Shifted up slightly
    var _lh       = 12;     // Tightened line height for better fit

    // Count connected MACRO_IRQ nodes on main spine
    var _irq_count = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone)
            _irq_count++;
    }

    // Count connected handlers
    var _handler_count = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ_HANDLER" && is_connected && org_parent == noone)
            _handler_count++;
    }

    var _has_sid = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) { _has_sid = true; break; }
    }

    draw_set_font(fnt_c64_tiny);

    // ROW 0 — VECTOR MODE
    draw_set_color(c_gray);
    draw_text(_px, _ly, "VECTOR:");
    var _mode_col = (_mode == 0) ? c_aqua : c_yellow;
    draw_set_color(_mode_col);
    draw_text(_px + 80, _ly, (_mode == 0) ? "$0314 KERNAL" : "$FFFE DIRECT");
    _ly += _lh;
    // ROW 0b — kernal unlock status

    if (_mode == 1) {
        if (!global.kernal_unlocked) {
            var _kfl = (current_time mod 600 < 300) ? make_color_rgb(255, 80, 80) : make_color_rgb(223, 180, 40);
            draw_set_color(_kfl);
            draw_text(_px, _ly, "!REQ: UNLOCK KERNAL");
        } else {
            draw_set_color(make_color_rgb(100, 240, 150));
            draw_text(_px, _ly, "KERNAL IS UNLOCKED.");
        }
    } else {
        draw_set_color(make_color_rgb(100, 240, 150));
		draw_set_font(fnt_c64_nano);
        draw_text(_px+10, _ly+2, "KERNAL MODE - NO UNLOCK NEEDED");
    }
    draw_set_font(fnt_c64_tiny);
    _ly += _lh;
    // ROW 1 — IRQ slot count
    var _pulse_slots = abs(sin(current_time / 200));
    draw_set_color(c_gray);
    draw_text(_px, _ly, "SLOTS:");
    var _slot_col = (_irq_count > 16) ? merge_color(c_red, c_white, _pulse_slots) : (_irq_count > 0 ? c_lime : make_color_rgb(120, 80, 80));
    draw_set_color(_slot_col);
    draw_text(_px + 60, _ly, string(_irq_count) + " / 16" + (_irq_count > 16 ? " !" : ""));
    _ly += _lh;

    // ROW 2 — SID status
    draw_set_color(c_gray);
    draw_text(_px, _ly, "SID:");
    draw_set_color(_has_sid ? c_lime : make_color_rgb(120, 60, 60));
    // Aligned to 60 to match SLOTS row
    draw_text(_px + 36, _ly, _has_sid ? "PLAY ON LAST SLOT" : "NOT PRESENT");
    _ly += _lh;

    // Row 3 spacing adjustment
    _ly += 4; 

    // ROW 4 — status
    if (is_connected) {
        draw_set_halign(fa_center);
		draw_set_font(fnt_c64_nano);
        if (_irq_count == 0) {
            var _pulse_status = abs(sin(current_time / 250));
            draw_set_color(merge_color(c_black, c_white, _pulse_status));
            draw_text(_draw_x + (width / 2), _ly, "ADD MACRO_IRQ NODES");
        } else {
            draw_set_color(make_color_rgb(80, 200, 80));
            draw_text(_draw_x + (width / 2), _ly, "NODE IN PLACE");
        }
        draw_set_halign(fa_left);
    }

    // Warnings
draw_set_font(fnt_c64_tiny);
    _ly += 16; // Compacted gap
    var _warn_pulse = abs(sin(current_time / 150));
    var _warn_col = merge_color(c_red, c_yellow, _warn_pulse);

    if (_handler_count > 1) {
        draw_set_color(_warn_col);
        draw_text(_px, _ly, "! ONLY 1 HANDLER ALLOWED !");
        _ly += _lh;
    }
    if (_irq_count > 16) {
        draw_set_color(_warn_col);
        draw_text(_px, _ly, "! MAX 16 IRQs REMOVE " + string(_irq_count - 16) + " !");
    }
}