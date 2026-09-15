/// @function scr_hud_screen_code(_ascii)
/// @desc Maps one typed ASCII character to its C64 SCREEN code — what actually
///       goes in screen RAM, which is not PETSCII and not ASCII.
///
///   @ A-Z [ \ ] ^ _   ->  0-31    (letters land at 1-26)
///   space ! " ... ?   ->  32-63   (same value as ASCII)
///   anything else     ->  32      (space)
///
/// Lower case is folded to upper: a HUD is drawn with a game's own charset,
/// where codes 1-26 are whatever glyphs the artist put there.
/// @param {Real} _ascii  ord() of the typed character
/// @return {Real} screen code 0-63
function scr_hud_screen_code(_ascii) {

    var _a = _ascii;

    if (_a >= 97 && _a <= 122) {
        _a -= 32;                 // fold lower case to upper
    }
    if (_a >= 64 && _a <= 95) {
        return _a - 64;           // @ A-Z [ \ ] ^ _
    }
    if (_a >= 32 && _a <= 63) {
        return _a;                // space, punctuation, digits
    }
    return 32;
}
