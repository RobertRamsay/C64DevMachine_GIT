/// @desc Handle LMB clicks for BANK_SWITCH nodes
function scr_node_step_bank_switch(_draw_x) {

    var _header_h = 24;
    var _line_h   = 16;
    var _inst     = instructions[0];
    var _lx       = _draw_x + 8;
    var _rx       = _draw_x + width - 6;
    var _cy       = y + _header_h + 4;

   // Named mode $01 values, index 0..7 = modes 24..31 ($30-$37)
    var _mode_vals = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37];

    // Row 0: MODE dropdown — cycle to next named mode
    var _mode_bx1 = _lx + 44;
    var _mode_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _mode_bx1, _cy + 4, _mode_bx2, _cy + 10)) {
        var _cur = real(_inst[4]);
        // From RAW (-1) or last slot, cycle to 0; otherwise advance
        var _next = _cur + 1;
        if (_next > 7 || _cur < 0) {
            _next = 0;
        }
        instructions[0][4] = _next;
        instructions[0][1] = _mode_vals[_next];
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;

    // Row 1: RAW $01 value — text entry
    var _val_bx1 = _lx + 44;
    var _val_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _val_bx1, _cy + 4, _val_bx2, _cy + 10)) {
        with (obj_workspace_manager) {
            is_entering_text   = true;
            input_target_node  = other.id;
            input_target_index = 1;
            var _v = real(other.instructions[0][1]);
            var _vh = decimal_to_hex(_v);
            while (string_length(_vh) < 2) {
                _vh = "0" + _vh;
            }
            current_input_string = "$" + string_upper(_vh);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _cy += _line_h;

    // Row 2: KEEP IRQ OFF toggle
    var _irq_bx1 = _lx;
    var _irq_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _irq_bx1, _cy + 4, _irq_bx2, _cy + 10)) {
        if (real(_inst[2]) == 1) {
            instructions[0][2] = 0;
        } else {
            instructions[0][2] = 1;
        }
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;

    // Row 3: WRITE DDR toggle
    var _ddr_bx1 = _lx;
    var _ddr_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _ddr_bx1, _cy + 4, _ddr_bx2, _cy + 10)) {
        if (real(_inst[3]) == 1) {
            instructions[0][3] = 0;
        } else {
            instructions[0][3] = 1;
        }
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;

    // Row 4: WIKI button
    var _wiki_bx1 = _lx;
    var _wiki_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _wiki_bx1, _cy + 4, _wiki_bx2, _cy + 10)) {
        url_open("https://www.c64-wiki.com/wiki/Bank_Switching");
        exit;
    }
    _cy += _line_h;

}