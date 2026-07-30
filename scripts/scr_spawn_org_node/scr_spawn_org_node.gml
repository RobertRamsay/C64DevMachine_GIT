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


