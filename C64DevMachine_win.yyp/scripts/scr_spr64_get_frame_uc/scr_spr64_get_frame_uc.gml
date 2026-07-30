function scr_spr64_get_frame_uc(_spr_node, _frame_idx) {
    var _json = string(_spr_node.instructions[0][1]);
    if (_json == "" || _json == "0") return 1;
    var _found = 0; var _depth = 0; var _obj_start = -1;
    for (var _ci = 1; _ci <= string_length(_json); _ci++) {
        var _ch = string_char_at(_json, _ci);
        if (_ch == "{") { if (_depth == 0) _obj_start = _ci; _depth++; }
        else if (_ch == "}") {
            _depth--;
            if (_depth == 0 && _obj_start > 0) {
                if (_found == _frame_idx) {
                    var _obj_str = string_copy(_json, _obj_start, _ci - _obj_start + 1);
                    var _uc_pos = string_pos("\"uc\":", _obj_str);
                    return (_uc_pos > 0) ? real(string_char_at(_obj_str, _uc_pos + 5)) : 1;
                }
                _found++; _obj_start = -1;
            }
        }
    }
    return 1;
}