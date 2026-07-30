function scr_spawn_comment_node(tx, ty) {
    var _n = instance_create_layer(tx, ty, "Layer_Nodes", obj_c64_node);
    _n.node_type    = "COMMENT";
    _n.node_title   = "COMMENT";
    _n.instructions = [["Comment", ""]];
    _n.width        = 240;
    _n.pc_address   = 0x0000;
    _n.is_dragging  = false;
    _n.is_connected = false;
    _n.org_parent   = noone;
    _n.height_dirty = true;
    with (_n) { event_user(0); }
    return _n;
}