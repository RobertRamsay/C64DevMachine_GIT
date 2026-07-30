/// @function c64_string_to_data(str, color)
function c64_string_to_data(_str, _color) {
    var _len = string_length(_str);
    var _char_array = [];
    var _color_array = [];
    
    _str = string_upper(_str);
    
    for (var i = 1; i <= _len; i++) {
        var _char = ord(string_char_at(_str, i));
        
        // Convert ASCII to C64 Screen Codes
        if (_char >= 65 && _char <= 90) _char -= 64; // A-Z
        else if (_char == 32) _char = 32;           // Space
        // Add more mapping here as needed (numbers, symbols)
        
        array_push(_char_array, _char);
        array_push(_color_array, _color);
    }
    
    return {
        chars: _char_array,
        colors: _color_array,
        length: _len
    };
}