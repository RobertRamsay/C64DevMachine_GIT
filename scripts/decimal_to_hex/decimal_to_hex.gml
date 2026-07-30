/// @function decimal_to_hex(dec)
function decimal_to_hex(dec) {
    var hex = "";
    var digits = "0123456789ABCDEF";
    if (dec == 0) return "00";
    while (dec > 0) {
        hex = string_char_at(digits, (dec & 0x0F) + 1) + hex;
        dec = dec >> 4;
    }
    if (string_length(hex) % 2 != 0) hex = "0" + hex;
    return hex;
}