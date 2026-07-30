function scr_render_c64_grid(_surf, _w, _h, _size) {
    if (!surface_exists(_surf)) {
        _surf = surface_create(_w, _h);
    }
    
    surface_set_target(_surf);
    
    // Use a solid, very dark background
    draw_clear(make_color_rgb(10, 10, 15)); 
    
    // Draw Dots (Dark Gray)
    draw_set_color(make_color_rgb(40, 40, 45));
    for (var i = 0; i < _w; i += _size) {
        for (var j = 0; j < _h; j += _size) {
            draw_point(i, j);
        }
    }
    
    // Draw Major Lines (Slightly lighter Gray)
    draw_set_color(make_color_rgb(25, 25, 35)); 
    for (var i = 0; i <= _w; i += _size * 8) draw_line(i, 0, i, _h);
    for (var j = 0; j <= _h; j += _size * 8) draw_line(0, j, _w, j);
    
    surface_reset_target();
    return _surf;
}