/// @desc scr_note_name_to_freq(_name)
/// Parses a note name ("A-4", "C#3", "Bb5", "G7") into a PAL SID 16-bit
/// frequency register value. Returns -1 if not a valid note name.
/// C-4 is middle C (MIDI 60). Accidentals: # or S = sharp, B = flat.
/// Optional '-' separator before the octave digit. Octaves 0-7.

function scr_note_name_to_freq(_name) {
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
    var _nc = (_p <= _len) ? string_char_at(_s, _p) : "";
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

    // freq_hz = 440 * 2^((midi-69)/12) ; PAL freg = hz * 16777216 / 985248
    var _hz   = 440 * power(2, (_midi - 69) / 12);
    var _freg = round(_hz * 16777216 / 985248);
    return clamp(_freg, 0, 65535);
}