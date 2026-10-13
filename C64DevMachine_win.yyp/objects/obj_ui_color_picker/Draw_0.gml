// Draw a subtle dark border/shadow behind the bar
draw_set_color(make_color_rgb(15, 15, 20));
draw_rectangle(x - 2, y - 2, x + width + 1, y + height + 1, false);

// Draw the 16 colors (8 solid, 8 split)
var _split_y = y + (height / 2);

for (var i = 0; i < 16; i++) {
    var _sx = x + (i * 16);
    
    // Rounded colour tiles (scr_editor_colour_tile); hover is a rounded ring.
    if (i < 8) {
        // --- FIRST 8: FULL HEIGHT ---
        scr_editor_colour_tile(_sx, y, _sx + 15, y + height, scr_c64_pepto_colour(i));
    } else {
        // --- SECOND 8: SPLIT (Upper 8 on top, Lower 8 on bottom) ---
        scr_editor_colour_tile(_sx, y, _sx + 15, _split_y, scr_c64_pepto_colour(i));
        scr_editor_colour_tile(_sx, _split_y + 1, _sx + 15, y + height, scr_c64_pepto_colour(i - 8));
    }
    
    // Draw highlight for the column
    if (point_in_rectangle(mouse_x, mouse_y, _sx, y, _sx + 14, y + height - 1)) {
        scr_editor_colour_ring(_sx - 2, y - 2, _sx + 17, y + height + 2, c_white);
    }
}

// Guided tours point at the open picker.
if (global.tour_active) {
    scr_tour_capture_world("PICKER:COLOUR", x - 2, y - 2, x + width + 1, y + height + 1);
}
