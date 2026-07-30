/// scr_sfx_wavetable_row_annotation(_L, _R)
/// Returns a human-readable string for a wavetable row pair.
function scr_sfx_wavetable_row_annotation(_L, _R) {
    var _lstr = "";
    if      (_L == 0xFF)                   _lstr = (_R == 0x00) ? "STOP" : "JMP>" + string_upper(decimal_to_hex(_R));
    else if (_L >= 0x01 && _L <= 0x0F)    _lstr = "DLY " + string(_L);
    else if (_L == 0x00)                   _lstr = "NOWAV";
    else if (_L >= 0xE0 && _L <= 0xEF)    _lstr = "INAUD";
    else {
        if (_L & 0x80) _lstr += "N";
        if (_L & 0x40) _lstr += "P";
        if (_L & 0x20) _lstr += "S";
        if (_L & 0x10) _lstr += "T";
        if (_L & 0x08) _lstr += "X";
        if (_L & 0x01) _lstr += "G";
    }

    var _rstr = "";
    if (_R == 0x80) {
        _rstr = "KEEP";
    } else if (_R >= 0x81 && _R <= 0xDF) {
        var _notes  = ["C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-"];
        var _semi   = _R - 0x81;
        var _oct    = (_semi + 1) div 12;
        var _ni     = (_semi + 1) mod 12;
        _rstr = _notes[_ni] + string(_oct);
    } else if (_R <= 0x5F) {
        _rstr = "+" + string(_R);
    } else {
        _rstr = "-" + string(_R - 0x60);
    }

    return _lstr + " / " + _rstr;
}
