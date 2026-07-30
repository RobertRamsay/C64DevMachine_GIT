
/// @function _asm_is_dec(_str)
function _asm_is_dec(_str) {
    if (_str == "") return false;
    for (var _i = 1; _i <= string_length(_str); _i++) {
        var _c = string_ord_at(_str, _i);
        if (_c < 48 || _c > 57) return false;
    }
    return true;
}

