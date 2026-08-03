/// @desc scr_is_pristine_default_workspace()
/// @return {Bool} true if the workspace is exactly the brand-new-project
///                default: the SYSTEM INIT node with its unmodified default
///                instructions, the empty VARIABLES ORG box, and the empty
///                ORG BLOCK scratch box - nothing else added, nothing
///                connected inside either box.
/// Used purely to gate the "no core loop / no RTS, said No" easter egg in
/// the build trigger; never mutates anything, safe to call anytime.
function scr_is_pristine_default_workspace() {
    if (instance_number(obj_c64_node) != 3) return false;

    var _default_init = [
        ["sei",     0],
        ["lda_imm", 0],
        ["sta_abs", 0xD020],
        ["sta_abs", 0xD021]
    ];

    var _init_ok = false;
    var _vars_ok = false;
    var _org_ok  = false;

    with (obj_c64_node) {
        if (node_type == "INIT") {
            var _match = (array_length(instructions) == array_length(_default_init));
            if (_match) {
                for (var _di = 0; _di < array_length(_default_init); _di++) {
                    if (array_length(instructions[_di]) < 2
                    ||  string_lower(string(instructions[_di][0])) != _default_init[_di][0]
                    ||  real(instructions[_di][1]) != _default_init[_di][1]) {
                        _match = false;
                        break;
                    }
                }
            }
            _init_ok = _match;

        } else if (node_type == "ORG" && !proxy) {
            // The default VARIABLES box - flagged pristine only if nothing
            // is connected as a child of it.
            var _self_vars = id;
            var _has_kids_vars = false;
            with (obj_c64_node) {
                if (org_parent == _self_vars && is_connected) { _has_kids_vars = true; break; }
            }
            _vars_ok = !_has_kids_vars;

        } else if (node_type == "ORG" && proxy) {
            // The default empty scratch ORG BLOCK - same rule.
            var _self_org = id;
            var _has_kids_org = false;
            with (obj_c64_node) {
                if (org_parent == _self_org && is_connected) { _has_kids_org = true; break; }
            }
            _org_ok = !_has_kids_org;
        }
    }

    return _init_ok && _vars_ok && _org_ok;
}
