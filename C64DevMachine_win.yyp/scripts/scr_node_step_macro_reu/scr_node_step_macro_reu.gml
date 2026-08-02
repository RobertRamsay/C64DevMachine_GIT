/// @desc Handle LMB clicks for MACRO_REU nodes
function scr_node_step_macro_reu(_draw_x) {

    var _header_h = 24;
    var _line_h   = 16;
    var _inst     = instructions[0];
    var _lx       = _draw_x + 8;
    var _rx       = _draw_x + width - 6;
    var _cy       = y + _header_h + 4;

    while (array_length(_inst) < 9) {
        array_push(_inst, 0);
    }

    var _open_hex = function(_idx, _digits) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = _idx;
            var _raw = real(other.instructions[0][_idx]);
            var _h   = string_upper(decimal_to_hex(_raw));
            while (string_length(_h) < _digits) {
                _h = "0" + _h;
            }
            current_input_string = "$" + _h;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
    };
    var _open_num = function(_idx) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = _idx;
            current_input_string = string(real(other.instructions[0][_idx]));
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
    };

    // Row 0: OP dropdown — cycle STASH -> FETCH -> SWAP -> COMPARE -> STASH
    var _op_bx1 = _lx + 30;
    var _op_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _op_bx1, _cy + 4, _op_bx2, _cy + 10)) {
        var _cur  = real(_inst[1]);
        var _next = _cur + 1;
        if (_next > 3) {
            _next = 0;
        }
        instructions[0][1] = _next;
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;

    // Row 1: C64 ADDR
    var _c64_bx1 = _lx + 44;
    var _c64_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _c64_bx1, _cy + 4, _c64_bx2, _cy + 10)) {
        _open_hex(2, 4); exit;
    }
    _cy += _line_h;

    // Row 2: REU ADDR
    var _reu_bx1 = _lx + 44;
    var _reu_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _reu_bx1, _cy + 4, _reu_bx2, _cy + 10)) {
        _open_hex(3, 4); exit;
    }
    _cy += _line_h;

    // Row 3: BANK
    var _bank_bx1 = _lx + 44;
    var _bank_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _bank_bx1, _cy + 4, _bank_bx2, _cy + 10)) {
        _open_num(4); exit;
    }
    _cy += _line_h;

    // Row 4: LEN
    var _len_bx1 = _lx + 44;
    var _len_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _len_bx1, _cy + 4, _len_bx2, _cy + 10)) {
        _open_hex(5, 4); exit;
    }
    _cy += _line_h;

    // Row 5: AUTOLOAD toggle
    var _al_bx1 = _lx;
    var _al_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _al_bx1, _cy + 4, _al_bx2, _cy + 10)) {
        if (real(_inst[6]) == 1) {
            instructions[0][6] = 0;
        } else {
            instructions[0][6] = 1;
        }
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;

    // Row 6: FIX C64 ADDR toggle
    var _fc_bx1 = _lx;
    var _fc_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _fc_bx1, _cy + 4, _fc_bx2, _cy + 10)) {
        if (real(_inst[7]) == 1) {
            instructions[0][7] = 0;
        } else {
            instructions[0][7] = 1;
        }
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;

    // Row 7: FIX REU ADDR toggle
    var _fr_bx1 = _lx;
    var _fr_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _fr_bx1, _cy + 4, _fr_bx2, _cy + 10)) {
        if (real(_inst[8]) == 1) {
            instructions[0][8] = 0;
        } else {
            instructions[0][8] = 1;
        }
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        exit;
    }
    _cy += _line_h;
}
