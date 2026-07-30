function scr_check_org_zero_crash() {
    var _bad_orgs = [];

    with (obj_c64_node) {
        if (node_type != "ORG") continue;
        if (node_title == "VARIABLES") continue;
        if (node_title == "HW REGISTERS") continue;
        if (pc_address != 0 && pc_address != -1) continue;

        var _has_kids = false;
        var _self_id = id;
        with (obj_c64_node) {
            if (org_parent == _self_id && is_connected) {
                _has_kids = true;
                break;
            }
        }

        if (_has_kids) {
            array_push(_bad_orgs, id);
        }
    }

    return _bad_orgs;
}
