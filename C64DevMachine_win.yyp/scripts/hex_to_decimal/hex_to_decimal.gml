function hex_to_decimal(_hex) {
    var _dec = 0;
    var _digits = "0123456789ABCDEF";
    _hex = string_upper(_hex);
    
    for (var i = 1; i <= string_length(_hex); i++) {
        var _char = string_char_at(_hex, i);
        var _pos = string_pos(_char, _digits) - 1;
        if (_pos < 0) continue;  // ADD THIS
        _dec = _dec << 4 | _pos;
    }
    
    return _dec;
}