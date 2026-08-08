/// @desc Draw world-space 20px grid
var _cam_x    = cam_x;
var _cam_y    = cam_y;
var _cam_zoom = cam_zoom;
var _grid     = 20;

// Calculate visible world area
var _view_w = 1920 * _cam_zoom;
var _view_h = 1080 * _cam_zoom;

// Snap start to nearest grid line in world space
var _start_x = floor(_cam_x / _grid) * _grid;
var _start_y = floor(_cam_y / _grid) * _grid;
var _end_x   = _cam_x + _view_w + _grid;
var _end_y   = _cam_y + _view_h + _grid;

if showGrid{
// Set Grid Color
draw_set_color(make_color_rgb(15, 10, 24));
	if bkgImg==1
	draw_set_color(make_color_rgb(20, 20, 20));
	if global.lite draw_set_color(make_color_rgb(40, 10, 11))

	// Calculate alpha: 1.0 at zoom 3, fading to 0.0 at zoom 4
	// The formula: (Target_End - Current) / (Target_End - Target_Start)
	var _alpha = clamp((4 - _cam_zoom) / (4 - 3), 0, 1);
	draw_set_alpha(_alpha);

	// Only execute the loops if the grid is visible
	if (_alpha > 0) {
	    // Vertical Lines
	    for (var _gx = _start_x; _gx < _end_x; _gx += _grid) {
	        draw_line(_gx, _start_y, _gx, _end_y);
	    }
    
	    // Horizontal Lines
	    for (var _gy = _start_y; _gy < _end_y; _gy += _grid) {
	        draw_line(_start_x, _gy, _end_x, _gy);
	    }
	}
}



// --- F5 SCANLINE EFFECT ---
if (scan_active && global.visual_fx) {
    var _scan_h = 200 * _cam_zoom;
    
    var _h1 = scan_y;                       // Bottom edge
    var _h2 = scan_y - (_scan_h * 0.15);    // 15% Bright tip
    var _h3 = scan_y - (_scan_h * 0.40);    // 25% Core color
    var _h4 = scan_y - (_scan_h * 0.70);    // 30% Dark tail
    var _h5 = scan_y - _scan_h;             // 30% Fade to nothing (Black)
    
    var _c5 = c_black; 
    var _c4, _c3, _c2, _c1;
    if (global.lite) {
        _c4 = make_color_rgb(90, 30, 24); 
        _c3 = c_red;
        _c2 = c_orange;
        _c1 = c_white;
    } else {
        _c4 = make_color_rgb(30, 20, 84); 
        _c3 = make_colour_rgb(0, 20, 200);
        _c2 = make_colour_rgb(0, 160, 255);
        _c1 = c_aqua;
    }
    
    gpu_set_blendmode(bm_add);
    
    // 1. Draw glowing vertical line segments ONLY inside the scan area
    for (var _gx = _start_x; _gx < _end_x; _gx += _grid) {
        draw_line_width_color(_gx, _h5, _gx, _h4, 4, _c5, _c4); 
        draw_line_width_color(_gx, _h4, _gx, _h3, 4, _c4, _c3);
        draw_line_width_color(_gx, _h3, _gx, _h2, 4, _c3, _c2);
        draw_line_width_color(_gx, _h2, _gx, _h1, 4, _c2, _c1); 
    }
    
    // 2. Draw glowing horizontal lines that fall within the scan area
    var _h_start_y = floor(_h5 / _grid) * _grid;
    for (var _gy = _h_start_y; _gy <= scan_y; _gy += _grid) {
        var _col = _c5; // Default invisible
        
        if (_gy > _h2) {
            _col = merge_color(_c2, _c1, (_gy - _h2) / (_h1 - _h2));
        } else if (_gy > _h3) {
            _col = merge_color(_c3, _c2, (_gy - _h3) / (_h2 - _h3));
        } else if (_gy > _h4) {
            _col = merge_color(_c4, _c3, (_gy - _h4) / (_h3 - _h4));
        } else if (_gy > _h5) {
            _col = merge_color(_c5, _c4, (_gy - _h5) / (_h4 - _h5));
        }
        
        draw_line_width_color(_start_x, _gy, _end_x, _gy, 6, _col, _col);
    }
    
    gpu_set_blendmode(bm_normal);
}


// Reset alpha to 1.0 so other UI or objects aren't transparent
draw_set_alpha(1.0);

if (flow_overlay_active) {
    scr_draw_flow_overlay(flow_overlay_edges);
}