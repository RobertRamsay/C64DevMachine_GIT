function scr_spawn_spr64_node(_x, _y) {
    var _n          = instance_create_layer(_x, _y, "Layer_Nodes", obj_c64_node);
    _n.node_type    = "SPR64";
    _n.node_title   = "SPR64";
    _n.instructions = [["spr", "", "", 0, "SPRITES", 0, 0, 0]];
    _n.pc_address   = 0x7000;
    _n.is_connected = false;
    _n.org_parent   = noone;
    return _n;
}