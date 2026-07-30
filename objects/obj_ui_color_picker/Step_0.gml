// If the user clicks anywhere, handle it and destroy the modal
if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
    // Did they click inside the color bar?
    if (point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
        // Calculate exactly which of the 16 blocks they clicked (now divided by 16px)
        var _col_idx = clamp(floor((mouse_x - x) / 16), 0, 15);
        
        // Apply it to the node!
        if (instance_exists(target_node)) {
            target_node.instructions[target_row][target_col] = _col_idx;
            global.addresses_dirty = true;
        }
    }
    
    // Destroy the modal whether they picked a color or clicked away
    instance_destroy();
}