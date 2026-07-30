/// @function scr_safe_num(_str)
/// @description Parse a signed integer from a string, tolerating a leading
///              minus and ignoring any trailing garbage ("0-4" -> 0, "-4x" -> -4).
///              Returns 0 for empty / non-numeric input. Never throws.
function scr_safe_num(_str) {
    var _s = string_trim(string(_str));
    if (_s == "") return 0;

    var _neg = false;
    if (string_char_at(_s, 1) == "-") {
        _neg = true;
        _s   = string_delete(_s, 1, 1);
    }

    var _digits = "";
    for (var _i = 1; _i <= string_length(_s); _i++) {
        var _c = string_char_at(_s, _i);
        if (_c >= "0" && _c <= "9") {
            _digits += _c;
        } else {
            break;
        }
    }

    if (_digits == "") return 0;

    var _num = real(_digits);
    if (_neg) _num = -_num;
    return _num;
}