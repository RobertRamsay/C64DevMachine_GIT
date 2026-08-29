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

    // Headers never hide themselves.
    if (_n.node_type == "INIT")     { return false; }
    if (_n.node_type == "ORG")      { return false; }

    if (_n.org_parent != noone) {
        if (!instance_exists(_n.org_parent)) { return false; }
        return _n.org_parent.collapsed;
    }

    // Main spine — folded by the INIT header. Read from a global rather than
    // hunting for the INIT node: this runs for every node in both Draw and
    // Step, and a search per call would make it O(nodes squared) per frame.
    // scr_org_collapse_hit refreshes it once each Begin Step.
    return global.init_collapsed;
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
        if (org_parent == _org) {
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
            if (org_parent != _org)  { continue; }
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
    return mouse_check_button_pressed(mb_left);
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
    with (obj_c64_node) {
        if (node_type == "INIT") {
            global.init_collapsed = collapsed;
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
        _hot.collapsed = !_hot.collapsed;

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
