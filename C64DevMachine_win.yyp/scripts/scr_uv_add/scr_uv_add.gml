/// scr_uv_add(name, size, encoding)
function scr_uv_add(_name, _size, _encoding) {
	
	
    // Guard against duplicates (case-insensitive)
    var _name_key = string_upper(_name);
    if (ds_map_exists(global.named_loc_map, _name_key)) {
        show_debug_message("UV ADD: '" + _name + "' already exists, skipping.");
        return;
    }
    // Find next free address by scanning existing UV meta
    var _next_addr = global.start_pc;
    for (var _i = 0; _i < array_length(global.named_loc_meta); _i++) {
        var _m = global.named_loc_meta[_i];
        if (_m.type == "UV") {
            var _end = _m.addr + _m.size;
            if (_end > _next_addr) _next_addr = _end;
        }
    }
    
    // Add to map and meta (map key canonical uppercase; display name preserved in meta/node)
    ds_map_add(global.named_loc_map, _name_key, _next_addr);
    array_push(global.named_loc_meta, {
        name:     _name,
        addr:     _next_addr,
        size:     _size,
        encoding: _encoding,
        type:     "UV",
        chip:     "RAM"
    });
    global.named_loc_meta_dirty = true;
    
    // Find VARIABLES ORG and spawn a child NAMED_LOC
	with (obj_c64_node) {
	    if (node_type == "ORG" && node_title == "VARIABLES") {
	        // Find the lowest child Y so we stack below it
	        var _spawn_y = y + 60;
	        with (obj_c64_node) {
	            if (org_parent == other.id && node_type == "NAMED_LOC") {
	                if (y + height > _spawn_y) _spawn_y = y + height + 4;
	            }
	        }
	        var _n          = instance_create_layer(x + 10, _spawn_y, "Layer_Nodes", obj_c64_node);
	        _n.node_title   = "UV VAR";
	        _n.node_type    = "NAMED_LOC";
	        _n.instructions = [["named_loc", _name]];
	        _n.pc_address   = _next_addr;
	        _n.org_parent   = id;
	        _n.is_connected = true;
	        with (_n) { event_user(0); }
	        global.addresses_dirty = true;
	        scr_c64_do_update_addresses();
	        break;
	    }
	}
}