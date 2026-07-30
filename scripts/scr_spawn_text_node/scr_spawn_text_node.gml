function scr_spawn_text_node(_x, _y) {
    var inst = instance_create_depth(_x, _y, -500, obj_c64_node);
    
    with(inst) {
        node_type = "DATA_TEXT";
        node_title = "ASCII STRING";
        
        //  THE INJECTION 
        // Default to $1200 for data nodes
        pc_address = 0x1200; 
        // Ensure the manager doesn't overwrite it back to $080E on frame 1
        is_address_manually_set = false; 

        instructions = [
            ["TEXT: ", "HELLO WORLD", "HELLO WORLD"]
        ];
        
        // Force a recalculation so the UI reflects the $1200 immediately
        scr_c64_update_addresses();
    }
    return inst;
}