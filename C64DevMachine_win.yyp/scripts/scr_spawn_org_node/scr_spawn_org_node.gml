/// @function scr_spawn_org_node(_x, _y)
/// @desc Spawns a secondary spine anchor at a custom C64 address.
///       Nodes connected below it form their own compiled chain.
///       Always spawns offset from the main spine to prevent children
///       being confused with main spine nodes.
function scr_spawn_org_node(_x, _y) {

    var inst = instance_create_depth(_x, _y, -500, obj_c64_node);

    with(inst) {
        node_type    = "ORG";
        node_title   = "ORG BLOCK";
        pc_address    = global.start_pc;
        instructions = [["nop", 0]];
        width        = global.node_display_width;
        is_connected = false;
		proxy		 = true;
		proxy_address = global.start_pc;
    }

    return inst;
}


/// @function scr_chain_tidy_indent(_owner)
/// @desc Tab one chain (_owner: an ORG, or noone for the main spine) the
///       usual way: a LABEL sits at the left, the nodes after it are tabbed
///       in once, and the RTS / RTI / JMP that ends the routine (or loop)
///       sits back at the left. Nodes above the first label keep their tab,
///       and so do nodes a macro owns.
function scr_chain_tidy_indent(_owner) {
    var _list = [];
    with (obj_c64_node) {
        if (is_connected && org_parent == _owner && macro_owner == noone
            && node_type != "ORG" && node_type != "INIT" && node_type != "COMMENT"
            && node_type != "NAMED_LOC" && node_type != "NEW_STR") {
            array_push(_list, id);
        }
    }
    array_sort(_list, function(_a, _b) { return _a.y - _b.y; });
    var _inside = false;
    for (var _i = 0; _i < array_length(_list); _i++) {
        var _n = _list[_i];
        if (_n.node_type == "LABEL") {
            _n.x_indent = 0;
            _inside = true;
            continue;
        }
        if (!_inside) {
            continue;
        }
        var _ends = false;
        if (_n.node_type == "NORMAL" && array_length(_n.instructions) > 0) {
            var _op = string_lower(string(_n.instructions[0][0]));
            _ends = (_op == "rts" || _op == "rti" || _op == "jmp_abs" || _op == "jmp_ind");
        }
        _n.x_indent = _ends ? 0 : 40;
        if (_ends) {
            _inside = false;
        }
    }
}

/// @function scr_tidy_all_indents()
/// @desc scr_chain_tidy_indent on the main spine and every code ORG.
function scr_tidy_all_indents() {
    scr_chain_tidy_indent(noone);
    var _orgs = [];
    with (obj_c64_node) {
        if (node_type == "ORG" && node_title != "VARIABLES" && node_title != "HW REGISTERS") {
            array_push(_orgs, id);
        }
    }
    for (var _i = 0; _i < array_length(_orgs); _i++) {
        scr_chain_tidy_indent(_orgs[_i]);
    }
}
