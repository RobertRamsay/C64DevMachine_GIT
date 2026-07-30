// Draw a subtle dark border/shadow behind the bar
draw_set_color(make_color_rgb(15, 15, 20));
draw_rectangle(x - 2, y - 2, x + width + 1, y + height + 1, false);

// Draw the 16 colors (8 solid, 8 split)
var _split_y = y + (height / 2);

for (var i = 0; i < 16; i++) {
    var _sx = x + (i * 16);
    
    if (i < 8) {
        // --- FIRST 8: FULL HEIGHT ---
        draw_set_color(scr_c64_pepto_colour(i));
        draw_rectangle(_sx, y, _sx + 14, y + height - 1, false);
    } else {
        // --- SECOND 8: SPLIT (Upper 8 on top, Lower 8 on bottom) ---
        // Top half (Upper color: 8-15)
        draw_set_color(scr_c64_pepto_colour(i));
        draw_rectangle(_sx, y, _sx + 14, _split_y - 1, false);
        
        // Bottom half (Lower color: 0-7)
        draw_set_color(scr_c64_pepto_colour(i - 8));
        draw_rectangle(_sx, _split_y, _sx + 14, y + height - 1, false);
    }
    
    // Draw highlight for the column
    if (point_in_rectangle(mouse_x, mouse_y, _sx, y, _sx + 14, y + height - 1)) {
        draw_set_color(c_white);
        draw_rectangle(_sx - 1, y - 1, _sx + 15, y + height, true);
    }
}