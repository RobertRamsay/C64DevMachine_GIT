/// @function scr_vbmp_label_key(_asset_name)
/// Derives a stable, assembler-safe label root from a VECTOR_BITMAP asset name.
/// Both MACRO_VECTOR_BMP (which emits the page streams) and MACRO_VECTOR_PAGE
/// (which references them) call this, so identical asset names always resolve
/// to identical labels regardless of which node ran. Non-alphanumeric chars
/// collapse to underscore; result is prefixed so it can't start with a digit.
function scr_vbmp_label_key(_asset_name) {
    var _s   = string(_asset_name);
    var _out = "vbmp_";
    var _n   = string_length(_s);
    for (var _i = 1; _i <= _n; _i++) {
        var _ch = string_char_at(_s, _i);
        var _ok = false;
        if (_ch >= "0" && _ch <= "9") _ok = true;
        if (_ch >= "A" && _ch <= "Z") _ok = true;
        if (_ch >= "a" && _ch <= "z") _ok = true;
        _out += _ok ? _ch : "_";
    }
    return _out;
}