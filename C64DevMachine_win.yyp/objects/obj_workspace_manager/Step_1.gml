// Cache drag state for nodes to read (workspace manager begin step event here)

global.drag_claim_taken = false;
	
global.any_node_dragging = false;
with (obj_c64_node) {
    if (is_dragging) { global.any_node_dragging = true; break; }
}

global.gui_mouse_x = device_mouse_x_to_gui(0);
global.gui_mouse_y = device_mouse_y_to_gui(0);
global.gui_w       = display_get_gui_width();

// SHOW CODE panel: decide here, not in Draw, whether the panel owns the pointer
// — Draw runs after every Step, so a flag set there is a frame stale and the
// nodes underneath would still act on the first click. Also resolves which node
// the pointer is over, for the listing highlight.
scr_show_code_hit();

// ---- IDLE DETECTION ----
var _mx = global.gui_mouse_x;
var _my = global.gui_mouse_y;
var _moved   = (_mx != idle_last_mx || _my != idle_last_my);
var _clicked = mouse_check_button(mb_any) || mouse_wheel_up() || mouse_wheel_down();
var _keyed   = keyboard_check(vk_anykey);
idle_last_mx = _mx;
idle_last_my = _my;

// ---- LABEL REFERENCE HIGHLIGHT: drop it once the pointer leaves the node ----
// The highlight is switched ON by the LABEL node's own Step, but it has to be
// switched OFF from here rather than from that node's else branch. That event
// has several early exits above the hover block — asset viewer, info window,
// label search, the SHOW CODE panel — so a pointer that leaves the label by
// crossing onto one of those never reaches the node's own clear.
//
// Only re-tested when the pointer actually MOVES. Pressing Enter cycles the
// camera through the references, which slides a different node under a
// stationary cursor; re-testing on a camera move would kill the highlight
// halfway through the cycle.
if (_moved && global.ref_highlight_source != noone) {
    var _ref_still_hovered = false;

    if (instance_exists(global.ref_highlight_source)) {
        with (global.ref_highlight_source) {
            _ref_still_hovered = point_in_rectangle(mouse_x, mouse_y,
                                                    x + x_indent, y,
                                                    x + x_indent + width, y + height);
        }
    }

    if (!_ref_still_hovered) {
        global.ref_highlight_source = noone;
        global.ref_highlight_name   = "";
    }
}

var _idle_was = global.idle_active;

if (_moved || _clicked || _keyed) {
    idle_timer = 0;
    global.idle_active = false;
} else {
    idle_timer += delta_time / 1000000; // secs
    if (idle_timer >= idle_threshold) global.idle_active = true;
}

// ---- IDLE SNAPSHOT (instant switch instead of a fade) ----
if (global.idle_active && !_idle_was) {
    // Just went idle this step — grab the last fully rendered frame
    if (sprite_exists(idle_snapshot_spr)) {
        sprite_delete(idle_snapshot_spr);
    }
    var _snap_w    = surface_get_width(application_surface);
    var _snap_h    = surface_get_height(application_surface);
    var _snap_surf = surface_create(_snap_w, _snap_h);
    surface_copy(_snap_surf, 0, 0, application_surface);
    idle_snapshot_spr    = sprite_create_from_surface(_snap_surf, 0, 0, _snap_w, _snap_h, false, false, 0, 0);
    surface_free(_snap_surf);
    idle_snapshot_active = true;
}

if (!global.idle_active && _idle_was) {
    // Just woke up this step — drop the snapshot immediately
    if (sprite_exists(idle_snapshot_spr)) {
        sprite_delete(idle_snapshot_spr);
    }
    idle_snapshot_spr    = -1;
    idle_snapshot_active  = false;
}

// idle_fade kept for the node Step/Draw gating logic — set instantly, no lerp
if (global.idle_active) {
    global.idle_fade = 0.0;
} else {
    global.idle_fade = 1.0;
}