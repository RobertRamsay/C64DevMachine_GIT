
   var _gui_x = device_mouse_x_to_gui(0);
    var _gui_y = device_mouse_y_to_gui(0);
obj_workspace_manager.hideui=false;
if (point_in_rectangle(_gui_x, _gui_y, x - 20, y - 20, x + 20, y + 20)) {
        obj_workspace_manager.hideui=true;
}


if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
    // Get the mouse position relative to the GUI layer
 

    // Hit area centered on x, y (using the 40x40 size from your original bounds)
    if (point_in_rectangle(_gui_x, _gui_y, x - 20, y - 20, x + 20, y + 20)) {
        // Prompt the user for a save location
        var _filepath = get_save_filename("PNG Image (*.png)|*.png", "C64DM_screenshot_");
        // A native file dialog takes focus, so the key-up that ends the keypress is
        // delivered to the dialog and not to the game. GameMaker is left thinking the
        // key is still held, and keyboard_check_pressed() needs an up->down edge — so
        // ESC silently stops working until the input state is reset. This is why ESC
        // only failed after SOME asset operations: scr_asset_sid_import already did
        // this, every other importer did not.
        io_clear();

        // Check if the user selected a path
        if (_filepath != "") {
            
            // Ensure the file ends with .png
            if (filename_ext(_filepath) != ".png") {
                _filepath += ".png";
            }
            
            // Bake application surface to a clean surface with alpha forced to 1.0
            var _w = surface_get_width(application_surface);
            var _h = surface_get_height(application_surface);
            var _bake_surf = surface_create(_w, _h);
            surface_set_target(_bake_surf);
            draw_clear_alpha(c_black, 1);

            // Pass 1 — draw colour normally
            gpu_set_blendmode_ext_sepalpha(
                bm_src_alpha, bm_inv_src_alpha,
                bm_src_alpha, bm_inv_src_alpha
            );
            draw_surface(application_surface, 0, 0);

            // Pass 2 — slam entire alpha channel to 1.0
            gpu_set_colorwriteenable(false, false, false, true);
            gpu_set_blendmode_ext_sepalpha(
                bm_one, bm_zero,
                bm_one, bm_zero
            );
            draw_set_alpha(1);
            draw_rectangle_colour(0, 0, _w, _h, c_white, c_white, c_white, c_white, false);
            gpu_set_colorwriteenable(true, true, true, true);

            gpu_set_blendmode(bm_normal);
            draw_set_alpha(1);
            surface_reset_target();
            surface_save(_bake_surf, _filepath);
            surface_free(_bake_surf);
        }
    }
}