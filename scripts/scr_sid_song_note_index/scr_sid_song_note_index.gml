/// @desc scr_sid_song_note_index(_name)
/// Maps a note name ("C-4", "C#3", "Bb5") to an index into the 96-entry
/// chromatic table MACRO_SID_SONG emits. Returns -1 if not a valid note.
///
/// Deliberately mirrors scr_note_name_to_freq / scr_note_name_to_hz rather
/// than deriving the index back out of a frequency: all three then share one
/// definition of what a note name means, so the editor's preview and the
/// compiled table can't drift apart on octave numbering.
///
/// Index 0 is C-0 and index 95 is B-7, i.e. index = midi - 12.
function scr_sid_song_note_index(_name) {
    var _s   = string_upper(string_trim(_name));
    var _len = string_length(_s);
    if (_len < 2) return -1;

    var _p      = 1;
    var _letter = string_char_at(_s, _p);
    var _base   = -1;
    switch (_letter) {
        case "C": _base = 0;  break;
        case "D": _base = 2;  break;
        case "E": _base = 4;  break;
        case "F": _base = 5;  break;
        case "G": _base = 7;  break;
        case "A": _base = 9;  break;
        case "B": _base = 11; break;
        default:  return -1;
    }
    _p += 1;

    // Optional accidental
    var _nc = "";
    if (_p <= _len) {
        _nc = string_char_at(_s, _p);
    }
    if (_nc == "#" || _nc == "S") {
        _base += 1;
        _p += 1;
    } else if (_nc == "B") {
        _base -= 1;
        _p += 1;
    }

    // Optional '-' separator
    if (_p <= _len && string_char_at(_s, _p) == "-") {
        _p += 1;
    }

    // Octave digit(s)
    var _oct_str = "";
    while (_p <= _len) {
        var _ch = string_char_at(_s, _p);
        if (_ch >= "0" && _ch <= "9") {
            _oct_str += _ch;
            _p += 1;
        } else {
            return -1;
        }
    }
    if (_oct_str == "") return -1;

    var _oct = real(_oct_str);
    if (_oct < 0 || _oct > 7) return -1;

    var _midi = 12 * (_oct + 1) + _base;
    if (_midi < 0 || _midi > 127) return -1;

    var _idx = _midi - 12;
    if (_idx < 0 || _idx > 95) return -1;

    return _idx;
}