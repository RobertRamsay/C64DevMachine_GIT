/// ====================================================================
/// ORG BLOCK COLLAPSE
///
/// An ORG node (VARS and HW REGISTERS included — they are ORG-typed) gets a
/// [-] / [+] tab just above its header. Folding it hides every node that names
/// it as org_parent.
///
/// WHY IT DOES NOT TOUCH height
/// ----------------------------
/// The obvious implementation is to set each child's height to 0 and remember
/// the old value. That does not survive contact with this codebase: height is
/// DERIVED, not stored. obj_c64_node's Draw event recomputes it from node_type
/// on every height_dirty, and a dozen unrelated things raise that flag — an
/// edit, a mode switch, a picker closing. A collapsed child would spring back
/// to full size the moment any of them fired, mid-fold.
///
/// So height is left alone and the fold lives in one flag on the PARENT. The
/// layout pass gives a hidden child an effective height of zero without
/// altering the real one, which also means there is nothing to cache and
/// nothing to restore: expanding is a single boolean.
///
/// COLLAPSE IS PURELY VISUAL
/// -------------------------
/// Addresses come from total_node_size, not from y. The child loop in
/// scr_c64_do_update_addresses accumulates _chain_pc separately from _child_y,
/// so folding moves nodes on the canvas and changes nothing about the program.
/// A folded block builds byte-for-byte identical to an open one.
/// ====================================================================

/// @function scr_node_is_hidden(_n)
/// @desc Is this node inside a folded ORG block? Every node gets `collapsed`
///       in its Create event, so this never has to test for the variable.
function scr_node_is_hidden(_n) {
    if (!instance_exists(_n))       { return false; }

    // Never swallow the active drag before its mouse release can be handled.
    if (_n.is_dragging && global.active_drag_node == _n) return false;

    // Under a raised CREATOR UI panel facade (a box drag still carries it).
    if (_n.creator_covered && !_n.is_dragging) return true;

    // Headers never hide themselves.
    if (_n.node_type == "INIT")     { return false; }
    if (_n.node_type == "ORG")      { return false; }

    // A DETACHED node belongs to no spine, so no fold owns it.
    //
    // This test used to run straight from org_parent to the INIT fold, and
    // org_parent == noone was taken to mean "main spine member". A node dragged
    // out of the spine has org_parent cleared to noone as well (obj_c64_node
    // Step_0 clears both on the first drag movement), so it was indistinguishable
    // from a spine node and vanished whenever INIT was folded — which reads as
    // the floater remembering the spine it came from. It remembers nothing; it
    // simply could not be told apart.
    //
    // The predicate is the same one scr_load_workspace_from_path uses to build
    // its unattached-node report, so the nodes the loader offers to clean up are
    // exactly the nodes a fold now leaves alone. COMMENT and free nodes are
    // exempt because they are is_connected == false BY DESIGN and are laid out
    // inside the block they annotate, so they should still fold with it; a macro
    // child is exempt because it belongs to its owner, not to a spine.
    if (_n.node_type != "COMMENT" && !_n.is_free_node && _n.macro_owner == noone) {
        if (!_n.is_connected) { return false; }
    }

    if (_n.org_parent != noone) {
        if (!instance_exists(_n.org_parent)) { return false; }
        return _n.org_parent.collapsed;
    }

    // Main spine — folded by the INIT header. Read from a global rather than
    // hunting for the INIT node: this runs for every node in both Draw and
    // Step, and a search per call would make it O(nodes squared) per frame.
    // scr_org_collapse_hit refreshes it once each Begin Step.
    if (!global.init_collapsed) { return false; }

    // Proximity is not attachment. A parked comment must remain visible
    // even when it occupies the same column as a folded INIT.
    if (_n.node_type == "COMMENT") return _n.is_connected;

    return true;
}

/// @function scr_node_mouse_over(_n)
/// @desc Is the pointer over this node, treating a folded one as not there?
///
/// The workspace runs a dozen of these tests directly against x/y/width/height.
/// Folding does not move a node — it only stops it being drawn — so every one
/// of those rectangles was still live under the empty space a fold leaves.
/// The one that bit: the spawn guard blocks N / L / J / A while the pointer is
/// over a connected node, so hovering the gap left by a collapsed block killed
/// every node shortcut with nothing on screen to explain it. The in-place
/// toggles (R / J / S / L) were worse — they would have edited a node you
/// could not see.
function scr_node_mouse_over(_n) {
    if (!instance_exists(_n))   { return false; }
    if (scr_node_is_hidden(_n)) { return false; }
    return point_in_rectangle(mouse_x, mouse_y, _n.x, _n.y, _n.x + _n.width, _n.y + _n.height);
}

/// @function scr_org_has_children(_org)
/// @desc Does this ORG own anything worth folding? Stops on the first hit.
///
/// Note what this does NOT test: is_connected. An ORG node is never connected —
/// scr_spawn_org_node sets it false and nothing sets it true, which is why
/// Draw_0 keeps writing `(is_connected || node_type == "ORG")` wherever it wants
/// "this node is live". Requiring it here disabled the entire fold feature
/// silently: no tab drawn, nothing clickable.
function scr_org_has_children(_org) {
    if (!instance_exists(_org)) { return false; }

    var _found = false;

    // INIT is not a parent the way ORG is — the main spine nodes are its
    // SIBLINGS, sharing org_parent == noone. It heads that run all the same, so
    // it folds it. ORG blocks are left alone: they live in their own columns
    // and have their own tabs.
    if (_org.node_type == "INIT") {
        with (obj_c64_node) {
            if (node_type == "INIT")  { continue; }
            if (node_type == "ORG")   { continue; }
            if (org_parent != noone)  { continue; }
            if (!is_connected)        { continue; }
            _found = true;
            break;
        }
        return _found;
    }

    with (obj_c64_node) {
        if (org_parent == _org && is_connected) {
            _found = true;
            break;
        }
    }
    return _found;
}

/// @function scr_org_collapse_stats(_org)
/// @desc What is behind the fold: how many nodes, how many bytes, and the
///       address span they occupy. Drawn on the header so a folded block is
///       never a black hole.
/// @return {struct} { count, bytes, lo, hi, has_range }
function scr_org_collapse_stats(_org) {
    var _res = { count: 0, bytes: 0, lo: 0, hi: 0, has_range: false };

    if (!instance_exists(_org)) {
        return _res;
    }

    var _init_mode = (_org.node_type == "INIT");

    with (obj_c64_node) {
        if (_init_mode) {
            if (node_type == "INIT") { continue; }
            if (node_type == "ORG")  { continue; }
            if (org_parent != noone) { continue; }
            if (!is_connected)       { continue; }
        } else {
            // is_connected matches the INIT branch above and scr_node_is_hidden:
            // a detached node parked in an ORG column is not part of the block,
            // so it must not be counted in the fold's node/byte totals either.
            if (org_parent != _org)  { continue; }
            if (!is_connected)       { continue; }
        }

        _res.count += 1;
        _res.bytes += total_node_size;

        // NAMED_LOC and NEW_STR are skipped by the address chain in
        // scr_c64_do_update_addresses, so their pc_address is not part of this
        // block's span and would drag the range somewhere meaningless.
        if (node_type == "NAMED_LOC") { continue; }
        if (node_type == "NEW_STR")   { continue; }

        if (!_res.has_range) {
            _res.lo        = pc_address;
            _res.hi        = end_address;
            _res.has_range = true;
        } else {
            if (pc_address  < _res.lo) { _res.lo = pc_address; }
            if (end_address > _res.hi) { _res.hi = end_address; }
        }
    }

    return _res;
}

/// @function scr_org_collapse_rect(_org)
/// @desc The [-] / [+] tab, sitting just ABOVE the header rather than inside
///       it, so it never competes with the ORG's own title row or the address
///       readouts already crowding that strip.
/// @return {struct} { x1, y1, x2, y2 }
function scr_org_collapse_rect(_org) {
    var _r = { x1: 0, y1: 0, x2: 0, y2: 0 };
    if (!instance_exists(_org)) {
        return _r;
    }

    var _w = 26;
    var _h = 16;

    // 20px clear of the header's left edge, so the tab reads as a handle on the
    // block rather than part of its title strip.
    _r.x1 = _org.x + _org.x_indent - 20;
    _r.y1 = _org.y - _h - 2;
    _r.x2 = _r.x1 + _w;
    _r.y2 = _r.y1 + _h;
    return _r;
}

/// @function scr_org_collapse_primary_pressed()
/// @desc Windows uses the raw button; the macOS port swaps the body of this one
///       function for `return scr_primary_pressed();` and nothing else changes.
function scr_org_collapse_primary_pressed() {
    return scr_workspace_mouse_check_button_pressed(mb_left);
}

/// @function scr_org_collapse_hit()
/// @desc BEGIN STEP. Works out whether the pointer owns a fold tab, and does
///       the toggle itself.
///
/// This has to run in Begin Step for the same reason the SHOW CODE panel and
/// the CONVERT button do: Draw runs after every Step, so a flag raised during
/// Draw is a frame stale, and the very click that pressed the tab would first
/// be treated by obj_c64_node as a click on the ORG node — starting a drag —
/// and by the workspace as a click on empty canvas, clearing the selection.
function scr_org_collapse_hit() {
    global.org_collapse_hot = noone;

    // Refreshed BEFORE any early exit below: scr_node_is_hidden reads this every
    // frame from Draw and Step, and a stale value would leave the whole spine
    // hidden (or shown) while a menu happens to be open.
    global.init_collapsed = false;
    global.init_spine_x   = -999999;
    with (obj_c64_node) {
        if (node_type == "INIT") {
            global.init_collapsed = collapsed;
            global.init_spine_x   = x;
            global.init_spine_w   = width;
            break;
        }
    }

    if (!instance_exists(obj_workspace_manager)) { exit; }
    if (!global.canEditNode)                     { exit; }
    if (global.idle_active && global.idle_fade < 0.1) { exit; }
    if (global.showcode_mouse_over)              { exit; }
    if (global.any_picker_open)                  { exit; }
    if (obj_workspace_manager.gui_menu_open != -1) { exit; }
    if (obj_workspace_manager.code_editor_open)  { exit; }
    if (obj_workspace_manager.is_entering_text)  { exit; }
    if (instance_exists(obj_asset_manager)) {
        if (obj_asset_manager.viewer_open) { exit; }
    }

    var _mx  = mouse_x;
    var _my  = mouse_y;
    var _hot = noone;

    with (obj_c64_node) {
        if (node_type != "ORG" && node_type != "INIT") { continue; }
        if (!scr_org_has_children(id))                 { continue; }

        var _r = scr_org_collapse_rect(id);
        if (point_in_rectangle(_mx, _my, _r.x1, _r.y1, _r.x2, _r.y2)) {
            _hot = id;
            break;
        }
    }

    global.org_collapse_hot = _hot;

    if (_hot == noone) { exit; }

    if (scr_org_collapse_primary_pressed()) {
        scr_org_set_collapsed(_hot, !_hot.collapsed);

        // Positions are owned by the layout pass, so ask for one rather than
        // shuffling y here — that is also what keeps a fold from ever touching
        // an address.
        global.addresses_dirty    = true;
        global.autosave_dirty     = true;
        obj_workspace_manager.flow_overlay_dirty = true;

        with (obj_c64_node) {
            overlap_check_dirty = true;
            last_overlap_check  = false;
        }

        // No "consume the click" flag here on purpose: obj_c64_node's Draw
        // event reassigns global.ui_click_consumed from a timer every frame,
        // so it cannot carry anything across events. global.org_collapse_hot
        // is the guard — the nodes and the workspace both check it, exactly
        // the way they check global.showcode_mouse_over.
    }
}

// INIT is the movable anchor of the main spine, independent of room centre.
function scr_init_anchor() {
    // Every node's Step asks for this, so cache it for the frame: the scan
    // made each frame O(nodes^2). Only a found INIT is cached.
    static _tick   = -1;
    static _cached = noone;
    if (_tick == global.frame_tick && instance_exists(_cached)) return _cached;
    var _anchor = noone;
    with (obj_c64_node) if (node_type == "INIT") { _anchor = id; break; }
    if (_anchor != noone) { _tick = global.frame_tick; _cached = _anchor; }
    return _anchor;
}

function scr_init_move(_anchor, _x, _y) {
    var _dx = _x - _anchor.x;
    var _dy = _y - _anchor.y;
    if (_dx == 0 && _dy == 0) return;
    with (obj_c64_node) {
        var _on_spine = is_connected && org_parent == noone && node_type != "ORG";
        if (instance_exists(macro_owner)) {
            _on_spine = macro_owner.is_connected && macro_owner.org_parent == noone;
        }
        if (id == _anchor || _on_spine) {
            x += _dx; y += _dy;
            if (wedge_y_stored >= 0) wedge_y_stored += _dy;
            overlap_check_dirty = true;
            last_overlap_check = false;
        }
    }
    global.addresses_dirty = true;
    global.undo_dirty = true;
    global.autosave_dirty = true;
    with (obj_workspace_manager) { flow_overlay_dirty = true; }
}

function scr_init_drag_update(_anchor) {
    with (_anchor) {
        var _init_x = mouse_x + drag_offset_x;
        var _init_y = mouse_y + drag_offset_y;
        if (_init_x != x || _init_y != y) was_dragged = true;
        scr_init_move(id, _init_x, _init_y);
        if (scr_workspace_mouse_check_button_released(mb_left)) {
            if (was_dragged) scr_init_move(id, round(x / 20) * 20, round(y / 20) * 20);
            is_dragging = false;
            depth = pre_click_depth;
            global.active_drag_node = noone;
            if (was_dragged) {
                scr_c64_update_addresses();
                with (obj_workspace_manager) { alarm[1] = 1; alarm[3] = 6; }
            }
        }
    }
}

function scr_focus_init(_record_undo = true) {
    var _anchor = scr_init_anchor();
    if (!instance_exists(_anchor)) return;
    with (obj_workspace_manager) {
        cam_zoom_target = 1;
        cam_zoom = 1;
        cam_x = _anchor.x + _anchor.width * 0.5 - 960;
        cam_y = _anchor.y - 160;
        cam_target_x = cam_x;
        cam_target_y = cam_y;
        if (_record_undo) {
            global.undo_dirty = true;
            alarm[3] = 6;
        }
    }
}

/// OPTIONS > MINIMIZE ALL / EXPAND ALL: fold or unfold SYSTEM INIT and every
/// ORG (code and VARIABLES alike) that has a fold tab. Folded blocks draw
/// only their header, which is the point on a large project.
function scr_org_set_all_collapsed(_collapsed) {
    var _anchors = [];
    with (obj_c64_node) {
        if (node_type != "ORG" && node_type != "INIT") continue;
        if (collapsed == _collapsed || !scr_org_has_children(id)) continue;
        array_push(_anchors, id);
    }
    for (var _i = 0; _i < array_length(_anchors); _i++) scr_org_set_collapsed(_anchors[_i], _collapsed);
    return array_length(_anchors);
}

/// Folding changes which cached bodies participate in the visible layout.
function scr_org_set_collapsed(_anchor, _collapsed) {
    _anchor.collapsed = _collapsed;
    if (_anchor.node_type == "INIT") global.init_collapsed = _collapsed;
    with (obj_c64_node) {
        var _belongs = id == _anchor || org_parent == _anchor;
        if (_anchor.node_type == "INIT" && is_connected && org_parent == noone && node_type != "ORG") _belongs = true;
        if (instance_exists(macro_owner)) {
            if (macro_owner.org_parent == _anchor) _belongs = true;
            if (_anchor.node_type == "INIT" && macro_owner.is_connected && macro_owner.org_parent == noone) _belongs = true;
        }
        if (!_belongs) continue;
        height_dirty = true;
        draw_cache_dirty = true;
        overlap_check_dirty = true;
        last_overlap_check = false;
        if (!_collapsed) {
            // Re-measure bodies on their next draw, including mode-dependent rows.
            macro_layout_type = "";
            scr_macro_sync_height(id);
            if (node_type == "COMMENT") scr_comment_sync_layout(id);
            if (node_type == "MACRO_PRINT") scr_print_sync_height(id);
        }
    }
    global.addresses_dirty = true;
    global.autosave_dirty = true;
    obj_workspace_manager.flow_overlay_dirty = true;
    // Heights are re-derived in Draw (macro bodies a frame later still), but
    // the pack that sets y only runs from scr_c64_do_update_addresses. Owe a
    // few passes so the unfolded chain closes up without waiting for a click.
    global.relayout_frames = max(global.relayout_frames, 3);
}

/// ====================================================================
/// NODE IMAGE CACHE
/// A quiet node of a static type (code block, comment, label, plain
/// opcode) is drawn once into its own surface and then blitted, instead of
/// running the whole node Draw every frame. It draws live (and re-renders)
/// whenever anything that can change its look is going on: pointer near
/// it, drag, picker, edit, selection, flash, conflict, dirty caches, or a
/// change in its key (position, size, address, text, LOD, display
/// options). Every node also re-renders about every 45 frames, which picks
/// up anything the key does not list. OPTIONS > NODE CACHE turns it off.
/// ====================================================================
#macro NC_PAD_L 120   // address gutter / badge sit left of the node
#macro NC_PAD_R 80    // params tab and stats sit right of it
#macro NC_PAD_T 24
#macro NC_PAD_B 24

/// Once per frame: may nodes use their cached image at all, and the global
/// display inputs every cached image depends on.
function scr_node_cache_frame() {
    static _tick = -1;
    if (_tick == global.frame_tick) return;
    _tick = global.frame_tick;
    var _wm = obj_workspace_manager;
    var _dbg = variable_global_exists("debug_hud_active") && global.debug_hud_active;
    global.node_cache_live = global.node_cache_enabled
        && !global.any_node_dragging && !global.group_drag_active && !global.box_drag_active
        && !instance_exists(global.wire_drag_node) && !global.any_picker_open
        && global.ref_highlight_source == noone && !global.tour_active && !_dbg
        && array_length(global.selected_nodes) == 0
        && !_wm.label_search_open && _wm.cam_zoom >= 1;
    global.node_cache_gsig = string(global.use_hex_display) + string(global.show_stats) + string(global.idle_fade)
        + string(global.comments_visible) + string(global.lite) + string(global.init_collapsed)
        + "|" + string(global.nodepad) + "|" + string(global.node_display_width)
        + "|" + string(_wm.opcode_headers_on) + string(_wm.opcode_extra_height)
        + "|" + string(_wm.nodeStyle) + "|" + string(global.lang)
        + "|" + string(variable_global_exists("known_labels_gen") ? global.known_labels_gen : 0);
}

/// Called from node Draw once the node is known to be on screen. Returns
/// true when the cached image was drawn (Draw exits). Otherwise Draw runs as
/// normal; if this node may be cached, its output is being captured into
/// nc_surf and scr_node_cache_end() puts it on screen.
function scr_node_cache_begin(_cam_x, _cam_y, _cam_zoom) {
    nc_rendering = false;
    scr_node_cache_frame();
    if (!global.node_cache_live) { scr_node_cache_stat("live: off this frame"); return false; }
    if (node_type != "MACRO_CODE" && node_type != "COMMENT" && node_type != "LABEL" && node_type != "NORMAL") {
        scr_node_cache_stat("live: type not cached");
        return false;
    }
    // draw_cache_dirty / stats_cache_dirty / code_cache_dirty are NOT tested:
    // they guard text data caches that only clear on some draw paths (a code
    // block never clears draw_cache_dirty), and the key covers what they track.
    if (is_dragging || label_picker_open || rmb_flash > 0 || latch_glow_alpha > 0 || is_conflicted
     || height_dirty || global.memory_bar_hover_node == id) {
        scr_node_cache_stat("live: node busy");
        return false;
    }
    var _wm = obj_workspace_manager;
    if (_wm.is_entering_text && _wm.input_target_node == id) { scr_node_cache_stat("live: node busy"); return false; }
    var _dx = x + x_indent;
    if (point_in_rectangle(mouse_x, mouse_y, _dx - 40, y - 40, _dx + width + NC_PAD_R, y + height + 40)) {
        scr_node_cache_stat("live: pointer near");
        return false;
    }
    // The first node runs the '@' debug toggle in its Draw
    if (id == instance_find(obj_c64_node, 0)) { scr_node_cache_stat("live: first node"); return false; }

    // Level of detail as Draw section C works it out (the gutter only shows near the centre)
    var _vw  = 1920 * _cam_zoom;
    var _vh  = 1080 * _cam_zoom;
    var _cdx = _dx - (_cam_x + _vw * 0.5);
    var _cdy = y   - (_cam_y + _vh * 0.5);
    var _lod = string(global.show_stats && _cam_zoom < 2.0) + string(_cam_zoom < 1.6)
             + string(_cam_zoom < 3.5) + string(_cam_zoom < 2.0) + string((_cdx * _cdx + _cdy * _cdy) < 640000)
             + string(_cam_zoom <= 2.55)
             // the box fades out between zoom 2.5 and 3.25 (Draw section H)
             + string(round(clamp(1.0 - (_cam_zoom - 2.5) / 0.75, 0, 1) * 20));
    var _key = global.node_cache_gsig + "|" + _lod
             + "|" + string(_dx) + "," + string(y) + "," + string(width) + "," + string(height)
             + "|" + string(is_connected) + string(collapsed)
             + "|" + string(pc_address) + "," + string(total_node_size) + "," + string(node_cycles)
             + "|" + custom_title + "|" + string(code_descriptor);
    if (node_type == "MACRO_CODE") _key += "|" + string(code_cached_lines);
    else                           _key += "|" + string(instructions);

    var _w = width + NC_PAD_L + NC_PAD_R;
    var _h = height + NC_PAD_T + NC_PAD_B;
    var _refresh = ((global.frame_tick + real(id)) mod 45) == 0;
    if (!_refresh && nc_key == _key && surface_exists(nc_surf)) {
        scr_node_cache_stat("hit");
        draw_surface(nc_surf, _dx - NC_PAD_L, y - NC_PAD_T);
        return true;
    }

    // Capture this frame's normal draw into the surface
    if (surface_exists(nc_surf) && (surface_get_width(nc_surf) != _w || surface_get_height(nc_surf) != _h)) {
        surface_free(nc_surf);
    }
    if (!surface_exists(nc_surf)) nc_surf = surface_create(_w, _h);
    if (_refresh) scr_node_cache_stat("capture: refresh");
    else if (nc_key == "") scr_node_cache_stat("capture: first");
    else {
        scr_node_cache_stat("capture: key changed");
        if (global.perf_on) { global.nc_last_old = nc_key; global.nc_last_new = _key; }
    }
    nc_key = _key;
    nc_ox  = _dx - NC_PAD_L;
    nc_oy  = y - NC_PAD_T;
    surface_set_target(nc_surf);
    draw_clear_alpha(c_black, 0);
    // Accumulate alpha correctly on a transparent target; blitted premultiplied
    gpu_set_blendmode_ext_sepalpha(bm_src_alpha, bm_inv_src_alpha, bm_one, bm_inv_src_alpha);
    matrix_set(matrix_world, matrix_build(-nc_ox, -nc_oy, 0, 0, 0, 0, 1, 1, 1));
    nc_rendering = true;
    return false;
}

/// End of node Draw (every exit after scr_node_cache_begin): finish a
/// capture and put it on screen.
function scr_node_cache_end() {
    if (!nc_rendering) return;
    nc_rendering = false;
    matrix_set(matrix_world, matrix_build_identity());
    gpu_set_blendmode(bm_normal);
    surface_reset_target();
    gpu_set_blendmode_ext(bm_one, bm_inv_src_alpha);
    draw_surface(nc_surf, nc_ox, nc_oy);
    gpu_set_blendmode(bm_normal);
}
