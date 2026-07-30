/// @desc Formats a value into C64-style Little-Endian Hex strings
function scr_get_hex_val(_val, _bytes) {
    if (is_string(_val)) return "?? ??";
    
    // Internal helper for 2-digit padding
    var _to_hex = function(_num) {
        var _h = decimal_to_hex(_num & 0xFF);
        if (string_length(_h) < 2) _h = "0" + _h;
        return string_upper(_h);
    }

    if (_bytes == 1) return _to_hex(_val);
    
    // C64 Little Endian: Low Byte then High Byte
    var _lo = _to_hex(_val);
    var _hi = _to_hex(_val >> 8);
    return _lo + " " + _hi;
}