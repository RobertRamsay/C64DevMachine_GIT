/// @desc Setup Grid Tracer

grid_size = 20;
// Snap origin strictly to the grid
x = round(x / grid_size) * grid_size;
y = round(y / grid_size) * grid_size;

dir = 0; // Will be set by the spawner
move_speed = 10; // Must divide cleanly into 20!
max_dist = 200 + irandom(80); // Distance before fading
dist_travelled = 0;

target_x = x + lengthdir_x(grid_size, dir);
target_y = y + lengthdir_y(grid_size, dir);

// Store history for the trail
trail_x = [x];
trail_y = [y];

alpha = 1.0;
fade_speed = 0.03 + random(0.02);

// Define the gradient colors (defaults, can be overridden by the spawner)
color_start = make_color_rgb(0, 255, 255); // Cyan
color_end   = make_color_rgb(0, 50, 255);  // Deep Blue


if global.lite
	{
	color_start = make_color_rgb(255, 200, 0); // Yellow
	color_end   = make_color_rgb(200, 20, 20);  // red
	}
depth=-1