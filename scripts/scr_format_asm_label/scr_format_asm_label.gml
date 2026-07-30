/// @function scr_format_asm_label(_mnem, _label)
/// @description  Format a label-bearing instruction back into parser-readable text.
///               Handles _lab_lo (#<lbl), _lab_hi (#>lbl), _rel (branch), and plain _lab / _abs.


function scr_format_asm_label(_mnem, _label) {
    var _m = string_lower(string(_mnem));
    var _lbl = string(_label);

    // Strip trailing _lab_lo / _lab_hi / _rel / _lab / _abs to get the base mnemonic
    var _suffix = "";
    var _base = _m;

    if (string_length(_m) > 7 && string_copy(_m, string_length(_m) - 6, 7) == "_lab_lo") {
        _suffix = "_lab_lo";
        _base = string_copy(_m, 1, string_length(_m) - 7);
    } else if (string_length(_m) > 7 && string_copy(_m, string_length(_m) - 6, 7) == "_lab_hi") {
        _suffix = "_lab_hi";
        _base = string_copy(_m, 1, string_length(_m) - 7);
    } else if (string_length(_m) > 4 && string_copy(_m, string_length(_m) - 3, 4) == "_rel") {
        _suffix = "_rel";
        _base = string_copy(_m, 1, string_length(_m) - 4);
    } else if (string_length(_m) > 4 && string_copy(_m, string_length(_m) - 3, 4) == "_lab") {
        _suffix = "_lab";
        _base = string_copy(_m, 1, string_length(_m) - 4);
    } else if (string_length(_m) > 4 && string_copy(_m, string_length(_m) - 3, 4) == "_abs") {
        _suffix = "_abs";
        _base = string_copy(_m, 1, string_length(_m) - 4);
    } else {
        // Fall back to first 3 chars (existing behaviour, e.g. plain JMP / JSR)
        _base = string_copy(_m, 1, 3);
        _suffix = "";
    }

    var _op = string_upper(_base);

    if (_suffix == "_lab_lo") {
        return _op + " #<" + _lbl;
    }
    if (_suffix == "_lab_hi") {
        return _op + " #>" + _lbl;
    }
    // _rel, _lab, _abs, and the fallback all emit as: OP label
    return _op + " " + _lbl;
}