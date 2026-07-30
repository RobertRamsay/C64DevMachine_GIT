/// @function scr_bitmap_builder_create(_asset)
/// @desc Seeds the meta for a fresh BITMAP_BUILDER asset. Every field the
///       editor touches is initialised here, so the editor never has to test
///       variable_struct_exists at runtime.
///
/// A BITMAP_BUILDER is an AUTHORING asset. It holds a list of copy records
/// (each a char-cell grab: sx,sy,dx,dy,w,h) and emits them as a BYTE_DATA
/// table that MACRO_MOVE_BMP_BLOCK consumes in ASSET mode.
///
///   records[]  — array of structs. Two kinds:
///                  { kind:"REC", sx,sy,dx,dy,w,h }   a copy
///                  { kind:"END" }                    an $FF terminator
///                An END divides the table into runs; MOVE_BMP_BLOCK's ENTRY
///                VAR picks which run gets drawn at runtime.
///   blend      — 0 = SOLID (OPAQUE), 1 = MASKED (MASK00). One per builder,
///                so one builder yields exactly one table.
///   bbd_name   — the BYTE_DATA asset this builder owns. Set on first
///                GENERATE; re-generating updates that same asset in place.
function scr_bitmap_builder_create(_asset) {
    _asset.meta = {
        src_asset    : "",      // BITMAP asset name — the tile sheet
        dst_asset    : "",      // BITMAP asset name — the canvas being built
        blend        : 0,       // 0 = SOLID, 1 = MASKED
        records      : [],      // array of {kind:"REC",sx,sy,dx,dy,w,h} | {kind:"END"}
        bbd_name     : "",      // owned BYTE_DATA asset name ("" = none yet)

        // ── PREVIEW ──
        // Scratch surface. Seeded from the dest bitmap, then the records are
        // replayed onto it. Never written back unless the user hits BAKE.
        prev_surf    : -1,
        prev_entry   : 0,       // record index the replay starts from
        prev_dirty   : true,    // rebuild the scratch surface next draw

        // ── GRAB / PLACE (two-phase, mirrors the vbmp COPYRGN tool) ──
        //   phase 0 = drag a source rect
        //   phase 1 = source locked, click the dest to place
        phase        : 0,
        anchor_c     : -1,      // live source-drag anchor cell (-1 = idle)
        anchor_r     : -1,
        grab_c       : 0,       // locked source cell rect
        grab_r       : 0,
        grab_w       : 1,
        grab_h       : 1,

        // ── LIST ──
        sel_rec      : -1,      // selected record index (-1 = none)
        list_scroll  : 0,
        // Row drag-to-reorder. -1 = no drag in progress. list_drag_row is the
        // record index that was picked up; list_drag_over is whichever row the
        // pointer is currently over. Both live here (not as locals in the
        // editor script) because a drag spans multiple frames.
        list_drag_row  : -1,
        list_drag_over : -1,
        // ── DEST TAG PREVIEW ──
        // Session-only UI toggle (like list_scroll / phase). When 1, the source
        // tag grid is remapped through the records and overlaid on the dest
        // preview, showing where each grabbed cell's collision TYPE lands once
        // MOVE_BMP_BLOCK blits it. Toggled by the SHOW/HIDE TAGS button or T.
        show_dest_tags : 0,
        // ── COLLISION TAGGING ──
        // TAG mode paints collision TYPE IDs onto the SOURCE sheet's cells. The
        // tags live on the BITMAP asset (meta.coll_types), not here — the builder
        // only holds transient paint state, so two builders on one sheet can't
        // fight over an in-progress stroke.
        //
        // GENERATE emits that grid verbatim as BBT_<builder> (1000 bytes, ONCE —
        // not per room). MACRO_MOVE_BMP_BLOCK reads it during the blit and writes
        // each source cell's type into $0400 + dest_cell, so the collision map is
        // built by the same pass that draws the pixels. No per-room plane, and
        // MACRO_COLL_ADV works unchanged because it already reads $0400.
        tag_mode     : 0,       // 0 = grab/place, 1 = paint collision tags
        tag_type     : 1,       // 0 = erase, 1..16 = collision type
        tag_painting : 0,       // 0 = idle, 1 = LMB paint, 2 = RMB erase
        bbt_name     : "",      // owned tag-grid BYTE_DATA ("" = none yet)
        // ── UNDO / REDO ──
        // Snapshot stacks: each entry is a deep copy of records[] plus the
        // cursor state at the time. Session-only — pruned on save/load rather
        // than serialised, since a stale history from another session can't be
        // meaningfully replayed against a project that may have moved on.
        // Seeded here so the editor never has to guard for their existence.
        undo_stack   : [],
        redo_stack   : [],
        // ── WARNING LINE ──
        warn_msg     : "",
        warn_timer   : 0
    };
}