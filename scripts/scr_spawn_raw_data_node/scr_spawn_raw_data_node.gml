function scr_spawn_raw_data_node(_x, _y) {
    var _n          = instance_create_layer(_x, _y, "Layer_Nodes", obj_c64_node);
    _n.node_type    = "RAW_DATA";
    _n.node_title   = "RAW DATA";
    _n.instructions = [["raw", "80,98,B0,C6,DA,EB,F5,FD,FF,FD,F5,EB,DA,C6,B0,98,80,67,4F,39,25,14,0A,02,00,02,0A,14,25,39,4F,67"]];
    _n.pc_address = global.start_pc;
    _n.is_connected = false;
    _n.org_parent   = noone;
    return _n;
}