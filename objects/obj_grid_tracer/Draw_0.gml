/// @desc Draw gradient trail

draw_set_alpha(alpha);

var _len = array_length(trail_x);

// Draw the committed trail segments
for(var i = 0; i < _len - 1; i++) {
    // Calculate 0.0 to 1.0 ratio based on how far this segment is along the max distance
    var _ratio1 = clamp((i * grid_size) / max_dist, 0, 1);
    var _ratio2 = clamp(((i + 1) * grid_size) / max_dist, 0, 1);
    
    // Get the exact interpolated colors
    var _c1 = merge_color(color_start, color_end, _ratio1);
    var _c2 = merge_color(color_start, color_end, _ratio2);
    
    draw_line_width_color(trail_x[i], trail_y[i], trail_x[i+1], trail_y[i+1], 2, _c1, _c2);
}

// Draw the active segment currently moving to the target
if (dist_travelled < max_dist) {
    var _ratio_start = clamp(((_len - 1) * grid_size) / max_dist, 0, 1);
    var _ratio_end   = clamp(dist_travelled / max_dist, 0, 1);
    
    var _c_start = merge_color(color_start, color_end, _ratio_start);
    var _c_end   = merge_color(color_start, color_end, _ratio_end);
    
    draw_line_width_color(trail_x[_len - 1], trail_y[_len - 1], x, y, 2, _c_start, _c_end);
    
    // Draw the bright leading dot matching the very tip's current color
    draw_set_color(_c_end);
    draw_rectangle(x - 1, y - 1, x + 1, y + 1, false);
}

// Always reset
draw_set_alpha(1.0);
draw_set_color(c_white);