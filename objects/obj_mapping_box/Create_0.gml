/// @desc Mapping Box - Create
box_w         = 200;
box_h         = 150;
box_name      = "BOX";
box_col_idx   = 0;
is_resizing   = false;
resize_ox     = 0;
resize_oy     = 0;
resize_ow     = 0;
resize_oh     = 0;
is_dragging   = false;
drag_ox       = 0;
drag_oy       = 0;
dbl_click_timer = 0;

drag_floats   = [];
drag_float_ox = [];
drag_float_oy = [];

box_colours = [
    make_color_rgb(220, 60,  60),
    make_color_rgb(220, 140, 40),
    make_color_rgb(220, 220, 40),
    make_color_rgb(100, 220, 60),
    make_color_rgb(40,  180, 80),
    make_color_rgb(40,  200, 180),
    make_color_rgb(40,  140, 220),
    make_color_rgb(60,  80,  220),
    make_color_rgb(140, 60,  220),
    make_color_rgb(220, 60,  180),
    make_color_rgb(220, 60,  120),
    make_color_rgb(180, 100, 60),
    make_color_rgb(30,  30,  30),
    make_color_rgb(80,  80,  80),
    make_color_rgb(160, 160, 160),
    make_color_rgb(240, 240, 240),
];

is_dragging     = false;
drag_ox         = 0;
drag_oy         = 0;
drag_start_x    = 0;
drag_start_y    = 0;
drag_nodes      = [];
drag_offsets    = [];
dbl_click_timer = 0;
depth=-50
