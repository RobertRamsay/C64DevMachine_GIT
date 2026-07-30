function ptr_to_hex(_val) {
    var _str = "";
    var _hex = "0123456789ABCDEF";
    repeat(4) {
        _str = string_char_at(_hex, (_val & 0xf) + 1) + _str;
        _val = _val >> 4;
    }
    return _str;
}