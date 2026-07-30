/// @function scr_strip_key_ghosts(_str)
/// @desc Strips control characters that navigation/arrow keys can leak into
///       keyboard_string (observed on Windows too, not just macOS) so they
///       never get typed as literal characters into a text field. Anything
///       below ASCII 32 (space) is a control code, not printable text — arrow
///       keys, tab, escape, etc. Leaves everything else untouched.
function scr_strip_key_ghosts(_str) {
    var _out = "";
    var _len = string_length(_str);
    for (var _i = 1; _i <= _len; _i++) {
        var _ch = string_char_at(_str, _i);
        if (ord(_ch) >= 32) {
            _out += _ch;
        }
    }
    return _out;
}