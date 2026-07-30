			if (variable_global_exists("fx_sys") && global.node_destroy_fx && global.visual_fx) {
			    var _p_count = (width * height) / 200; // Density based on size
    
			    // Create a burst across the rectangular area of the node
			    part_emitter_region(global.fx_sys, 0, x, x + width, y, y + height, ps_shape_rectangle, ps_distr_linear);
			    part_emitter_burst(global.fx_sys, 0, global.pt_node_vapor, _p_count);
			}

			// If this ORG is destroyed, orphan all its children
			if (node_type == "ORG") {
			    with (obj_c64_node) {
			        if (org_parent == other.id) {
			            org_parent   = noone;
			            is_connected = false;
			        }
			    }
			}