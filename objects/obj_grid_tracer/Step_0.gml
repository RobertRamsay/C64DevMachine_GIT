/// @desc Trace and fade

if (dist_travelled >= max_dist) {
    alpha -= fade_speed;
    if (alpha <= 0) {
        instance_destroy();
    }
    exit;
}

// Move towards next 20px intersection
var _dx = sign(target_x - x) * move_speed;
var _dy = sign(target_y - y) * move_speed;

x += _dx;
y += _dy;

// Reached the intersection?
if (point_distance(x, y, target_x, target_y) < 1) {
    x = target_x;
    y = target_y;
    
    array_push(trail_x, x);
    array_push(trail_y, y);
    
    dist_travelled += grid_size;

    // 40% chance to take a random 90-degree turn
    if (random(1) > 0.6) { 
        dir += choose(-90, 90);
    }
    
    target_x = x + lengthdir_x(grid_size, dir);
    target_y = y + lengthdir_y(grid_size, dir);
}