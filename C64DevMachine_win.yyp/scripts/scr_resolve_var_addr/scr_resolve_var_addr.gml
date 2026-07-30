/// @desc scr_resolve_var_addr(_name)
/// Resolves a named var to its address using the same two-stage lookup
/// as MACRO_VWAIT: named_loc_map first, then a NAMED_LOC node scan.
/// Returns 0 when unresolved.
function scr_resolve_var_addr(_name) {
    if (_name == "") {
        return 0;
    }
    var _addr = 0;
    if (ds_map_exists(global.named_loc_map, _name)) {
        _addr = ds_map_find_value(global.named_loc_map, _name);
    }
    if (_addr == 0) {
        var _find = _name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _find) {
                _addr = pc_address;
                break;
            }
        }
    }
    return _addr;
}