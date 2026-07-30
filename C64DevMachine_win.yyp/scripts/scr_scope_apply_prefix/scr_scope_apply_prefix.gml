/// @function scr_scope_apply_prefix(_raw, _prefix, _flow)
/// @description Prefixes a scope-local label declaration or flow-control operand.
///              Leaves multi-labels (lines starting with !) untouched for the later pass.
function scr_scope_apply_prefix(_raw, _prefix, _flow) {
    if (_prefix == "") return _raw;

    var _t = string_trim(_raw);
    if (_t == "") return _raw;
    if (string_char_at(_t, 1) == "!") return _raw;   // multi-label, handled later

    var _indent = string_copy(_raw, 1, string_length(_raw) - string_length(string_trim_start(_raw)));

    // Label declaration: "name:" with no space before colon
    var _ci = string_pos(":", _t);
    if (_ci > 1 && string_pos(" ", string_copy(_t, 1, _ci - 1)) == 0) {
        var _name = string_copy(_t, 1, _ci - 1);
        var _fc   = string_char_at(_name, 1);
        if (_fc != "." && _fc != "*") {
            var _rest = string_delete(_t, 1, _ci);
            return _indent + _prefix + _name + ":" + _rest;
        }
    }

    // Flow-control operand: prefix a bare-identifier target
    var _sp = string_pos(" ", _t);
    if (_sp > 0) {
        var _mnem    = string_lower(string_copy(_t, 1, _sp - 1));
        var _operand = string_trim(string_delete(_t, 1, _sp));
        if (string_pos("," + _mnem + ",", _flow) > 0 && _operand != "") {
            var _oc = string_char_at(_operand, 1);
            // skip literals / immediates / multi-labels / indirect / numbers
            var _is_digit = (_oc >= "0" && _oc <= "9");
            if (_oc != "$" && _oc != "#" && _oc != "!" && _oc != "%"
            &&  _oc != "(" && !_is_digit) {
                // base = operand up to any +/- offset
                var _base = _operand;
                var _pp   = string_pos("+", _base);
                var _mp   = string_pos("-", _base);
                if (_pp > 1) {
                    _base = string_trim(string_copy(_base, 1, _pp - 1));
                } else if (_mp > 1) {
                    _base = string_trim(string_copy(_base, 1, _mp - 1));
                }
                if (_base != "") {
                    var _new_operand = string_replace(_operand, _base, _prefix + _base);
                    return _indent + _mnem + " " + _new_operand;
                }
            }
        }
    }

    return _raw;
}