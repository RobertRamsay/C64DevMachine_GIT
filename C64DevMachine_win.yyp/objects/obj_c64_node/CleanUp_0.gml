if (variable_instance_exists(id, "spr_surface") && surface_exists(spr_surface)) {
    surface_free(spr_surface);
}
// NODE IMAGE CACHE surface
if (surface_exists(nc_surf)) surface_free(nc_surf);
