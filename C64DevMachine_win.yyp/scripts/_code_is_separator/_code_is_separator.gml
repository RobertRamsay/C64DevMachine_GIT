/// @function _code_is_separator(_char)
/// @description Returns true if character is a word separator.
function _code_is_separator(_char) {
    return (_char == " " || _char == "\n" || _char == "\t" || 
            _char == "," || _char == ";" || _char == "(" || 
            _char == ")" || _char == "#" || _char == "$" ||
            _char == ":" || _char == "");
}