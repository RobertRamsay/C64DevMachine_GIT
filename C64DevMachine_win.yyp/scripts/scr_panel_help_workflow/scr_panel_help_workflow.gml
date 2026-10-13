/// scr_panel_help_workflow - WORKFLOW tour content for the HELP GUIDE.
/// Each scr_panel_help_wf_<group>() returns a struct of asset type -> array of
/// steps: { title, text, targets }. targets name controls by their on-screen
/// label (see scr_panel_help_resolve). Returns undefined when a type has none.
global.ph_wf_cache = undefined;

function scr_panel_help_workflow(_type) {
    // Built once: the title bar asks every frame whether a panel has one.
    if (is_undefined(global.ph_wf_cache)) {
        global.ph_wf_cache = {};
        var _sets = [scr_panel_help_wf_bitmaps(), scr_panel_help_wf_sprites(), scr_panel_help_wf_maps(), scr_panel_help_wf_sound()];
        for (var _i = 0; _i < array_length(_sets); _i++) {
            var _keys = variable_struct_get_names(_sets[_i]);
            for (var _k = 0; _k < array_length(_keys); _k++) global.ph_wf_cache[$ _keys[_k]] = _sets[_i][$ _keys[_k]];
        }
    }
    return variable_struct_exists(global.ph_wf_cache, _type) ? global.ph_wf_cache[$ _type] : undefined;
}
