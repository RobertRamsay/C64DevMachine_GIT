/// @desc Returns true if this conflict has been user-suppressed.
function scr_is_conflict_ignored(_range_start, _range_end, _owner_a, _owner_b) {
    if (!variable_global_exists("ignored_conflicts")) return false;

    var _root_a = _owner_a;
    var _root_b = _owner_b;
    if (instance_exists(_owner_a) && _owner_a.org_parent != noone && instance_exists(_owner_a.org_parent)) {
        _root_a = _owner_a.org_parent;
    }
    if (instance_exists(_owner_b) && _owner_b.org_parent != noone && instance_exists(_owner_b.org_parent)) {
        _root_b = _owner_b.org_parent;
    }

    var _uid_a      = scr_get_node_uid(_owner_a);
    var _uid_b      = scr_get_node_uid(_owner_b);
    var _root_uid_a = scr_get_node_uid(_root_a);
    var _root_uid_b = scr_get_node_uid(_root_b);

    // Only log pairs in the conflicting region
    var _verbose = (_range_start >= 0x0800 && _range_start < 0x0830);

    if (_verbose) {
        show_debug_message("CHECK pair: a_inst=" + string(_owner_a) +
            " a_type=" + (instance_exists(_owner_a) ? _owner_a.node_type : "?") +
            " a_uid=" + string(_uid_a) +
            " a_root_uid=" + string(_root_uid_a) +
            " | b_inst=" + string(_owner_b) +
            " b_type=" + (instance_exists(_owner_b) ? _owner_b.node_type : "?") +
            " b_uid=" + string(_uid_b) +
            " b_root_uid=" + string(_root_uid_b) +
            " range=$" + string_upper(decimal_to_hex(_range_start)) +
            "-$" + string_upper(decimal_to_hex(_range_end)));
    }

    var _len = array_length(global.ignored_conflicts);
    for (var _i = 0; _i < _len; _i++) {
        var _ig = global.ignored_conflicts[_i];
        if (_ig.range_start == _range_start && _ig.range_end == _range_end) {
            if (_verbose) show_debug_message("  -> SUPPRESSED by range");
            return true;
        }
        if (_uid_a != -1 && _uid_b != -1) {
            if ((_ig.owner_a_uid == _uid_a && _ig.owner_b_uid == _uid_b) ||
                (_ig.owner_a_uid == _uid_b && _ig.owner_b_uid == _uid_a)) {
                if (_verbose) show_debug_message("  -> SUPPRESSED by direct pair");
                return true;
            }
        }
        if (_root_uid_a != -1 && _root_uid_b != -1) {
            if ((_ig.owner_a_uid == _root_uid_a && _ig.owner_b_uid == _root_uid_b) ||
                (_ig.owner_a_uid == _root_uid_b && _ig.owner_b_uid == _root_uid_a)) {
                if (_verbose) show_debug_message("  -> SUPPRESSED by root pair");
                return true;
            }
        }
        if (_uid_a != -1 && _root_uid_b != -1) {
            if ((_ig.owner_a_uid == _uid_a && _ig.owner_b_uid == _root_uid_b) ||
                (_ig.owner_a_uid == _root_uid_b && _ig.owner_b_uid == _uid_a)) {
                if (_verbose) show_debug_message("  -> SUPPRESSED by cross a/root_b");
                return true;
            }
        }
        if (_uid_b != -1 && _root_uid_a != -1) {
            if ((_ig.owner_a_uid == _uid_b && _ig.owner_b_uid == _root_uid_a) ||
                (_ig.owner_a_uid == _root_uid_a && _ig.owner_b_uid == _uid_b) ) {
                if (_verbose) show_debug_message("  -> SUPPRESSED by cross b/root_a");
                return true;
            }
        }
    }
    if (_verbose) show_debug_message("  -> NOT SUPPRESSED");
    return false;
}