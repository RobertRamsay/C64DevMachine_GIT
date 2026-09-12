
/// @function _asm_val(_str)
function _asm_val(_str) {
    _str = string_trim(_str);
    if (_str == "") return 0;

    // Normalize a C-style prefix only at the START of this numeric token.
    // Replacing "0b" across an expression corrupts hex such as $0b/$d0b0.
    if (string_length(_str) > 2) {
        var _prefix = string_lower(string_copy(_str, 1, 2));
        if (_prefix == "0x") {
            _str = "$" + string_delete(_str, 1, 2);
        } else if (_prefix == "0b") {
            _str = "%" + string_delete(_str, 1, 2);
        }
    }
    if (string_char_at(_str, 1) == "$") {
        var _hex = string_upper(string_delete(_str, 1, 1));
        var _val = 0;
        for (var _i = 1; _i <= string_length(_hex); _i++) {
            var _c = string_ord_at(_hex, _i);
            _val = _val << 4;
            if (_c >= 48 && _c <= 57)      _val += (_c - 48);
            else if (_c >= 65 && _c <= 70) _val += (_c - 55);
        }
        return _val;
    }
    if (string_char_at(_str, 1) == "%") {
        var _bin = string_delete(_str, 1, 1);
        var _val = 0;
        for (var _i = 1; _i <= string_length(_bin); _i++)
            _val = (_val << 1) | (string_char_at(_bin, _i) == "1" ? 1 : 0);
        return _val;
    }
    // Safe decimal parse — only if purely numeric
    if (_asm_is_dec(_str)) return real(_str);
    return 0;
}

