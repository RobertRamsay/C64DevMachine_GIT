/// @desc Free GPU Memory
if (surface_exists(grid_surface)) {
    surface_free(grid_surface);
    grid_surface = -1; // Reset to -1 for safety
}