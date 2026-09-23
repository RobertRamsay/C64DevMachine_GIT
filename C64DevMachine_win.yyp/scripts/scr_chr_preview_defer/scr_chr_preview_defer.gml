/// Deferred charset preview rebuild.
///
/// scr_asset_chr_build_preview recreates three full-charset surfaces (a rect
/// per pixel for all 256 chars). Painting in the char editor used to call it
/// every frame the mouse was held. Drag-paint now only flags the asset; the
/// rebuild waits until the mouse buttons are released. State lives on obj_asset_manager (initialised in its Create event).

/// Flag a charset preview for rebuild.
/// @param {struct} _asset  CHAR_SET asset
function scr_chr_preview_request(_asset) {
    with (obj_asset_manager) {
        // A different charset was already waiting - don't drop its rebuild
        if (chr_preview_pending != noone && chr_preview_pending != _asset) {
            scr_asset_chr_build_preview(chr_preview_pending);
        }
        chr_preview_pending = _asset;
    }
}

/// Run a pending rebuild when due. Called every frame from obj_asset_manager Draw GUI.
function scr_chr_preview_service() {
    with (obj_asset_manager) {
        if (chr_preview_pending == noone) { exit; }
        if (mouse_check_button(mb_left) || mouse_check_button(mb_right)) { exit; }
        var _a = chr_preview_pending;
        chr_preview_pending = noone;
        scr_asset_chr_build_preview(_a);
    }
}
