/// @function scr_str_is_hex(_s)
/// @description Returns true if every char in _s is 0-9 or A-F (case-insensitive). Empty string returns false.
function scr_str_is_hex(_s) {
    var _len = string_length(_s);
    if (_len == 0) {
        return false;
    }
    for (var _i = 1; _i <= _len; _i++) {
        var _c = string_upper(string_char_at(_s, _i));
        var _ok = false;
        if (_c >= "0" && _c <= "9") {
            _ok = true;
        } else if (_c >= "A" && _c <= "F") {
            _ok = true;
        }
        if (!_ok) {
            return false;
        }
    }
    return true;
}

/// @function scr_str_is_decimal(_s)
/// @description Returns true if _s is a pure decimal integer (optional leading "-"). Empty string returns false.
function scr_str_is_decimal(_s) {
    var _len = string_length(_s);
    if (_len == 0) {
        return false;
    }
    var _start = 1;
    if (string_char_at(_s, 1) == "-") {
        if (_len == 1) {
            return false;
        }
        _start = 2;
    }
    for (var _i = _start; _i <= _len; _i++) {
        var _c = string_char_at(_s, _i);
        if (_c < "0" || _c > "9") {
            return false;
        }
    }
    return true;
}