/// @function scr_desugar_scopes(_text)
/// @description Rewrites ordinary labels inside non-repeat { } scope blocks to unique
///              prefixed names so the same label can be reused across scopes, then
///              strips the scope braces. Leaves `repeat N { }` braces intact for the
///              repeat expander. MUST run BEFORE repeat-expansion.
function scr_desugar_scopes(_text) {
    var _lines    = string_split(_text, "\n");
    var _n        = array_length(_lines);
    var _out      = "";
    var _scope_id = 0;
    var _stack    = [];   // structs: { kind: "repeat"|"scope", prefix: "..." }

    // branch/jump mnemonics whose operand may be a scope-local label
    var _flow = ",jmp,jsr,bne,beq,bcc,bcs,bpl,bmi,bvc,bvs,";

    for (var _i = 0; _i < _n; _i++) {
        var _raw = _lines[_i];
        var _t   = string_trim(_raw);
        var _low = string_lower(_t);

        var _is_repeat_open = (string_pos("repeat", _low) == 1 && string_pos("{", _t) > 0);
        var _ends_brace     = (string_char_at(_t, string_length(_t)) == "{");
        var _opens_scope    = (!_is_repeat_open && _t != "" && _ends_brace);
        var _is_close       = (_t == "}");

        // current active scope prefix (innermost scope frame)
        var _prefix = "";
        for (var _s = array_length(_stack) - 1; _s >= 0; _s--) {
            if (_stack[_s].kind == "scope") {
                _prefix = _stack[_s].prefix;
                break;
            }
        }

        if (_is_repeat_open) {
            array_push(_stack, { kind: "repeat", prefix: _prefix });
            _out += _raw + "\n";
            continue;
        }

        if (_opens_scope) {
            _scope_id++;
            var _new_prefix = _prefix + "__s" + string(_scope_id) + "_";
            // keep any label/content before the '{' in the OUTER scope
            var _brace_pos = string_last_pos("{", _raw);
            var _before    = string_trim(string_copy(_raw, 1, _brace_pos - 1));
            if (_before != "") {
                var _line_no_brace = string_copy(_raw, 1, _brace_pos - 1);
                _out += scr_scope_apply_prefix(_line_no_brace, _prefix, _flow) + "\n";
            }
            array_push(_stack, { kind: "scope", prefix: _new_prefix });
            continue;
        }

        if (_is_close) {
            if (array_length(_stack) > 0) {
                var _frame = array_pop(_stack);
                if (_frame.kind == "repeat") {
                    _out += _raw + "\n";   // keep repeat close brace for the expander
                }
                // scope close brace is dropped
            } else {
                _out += _raw + "\n";       // unbalanced — leave as-is
            }
            continue;
        }

        // ordinary line
        _out += scr_scope_apply_prefix(_raw, _prefix, _flow) + "\n";
    }

    // trim the trailing newline we appended
    if (string_char_at(_out, string_length(_out)) == "\n") {
        _out = string_copy(_out, 1, string_length(_out) - 1);
    }
    return _out;
}