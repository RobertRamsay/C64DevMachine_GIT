/// @desc Every entry-point label the connected macro nodes publish.
///
/// Macro nodes emit labels of their own - MSC_L, Scroller_U, sng3_init and so
/// on - that only come into existence when the chain is compiled. Anything
/// that wants to know whether a symbol is real before a compile has run had
/// no way to find them, which is why a converted CODE block drew every
/// JSR MSC_L in error red until the first build.
///
/// This is the single source of truth for that list. The label pickers in
/// obj_c64_node's Step and Draw events and in scr_node_step_macro_coll_adv
/// still build their own copies; when one of them gains a macro and the
/// others do not, symbols go red in the editor for no reason. Point them at
/// this function and that class of bug goes away.
///
/// Existence only - the addresses are not known until the assembler has run,
/// so the struct holds `true`, never a number. Do not use it for arithmetic.
///
/// @return {Struct} label name -> true
function scr_macro_entry_labels() {

    var _out = {};

    with (obj_c64_node) {

        if (!is_connected) { continue; }
        if (array_length(instructions) == 0) { continue; }
        if (array_length(instructions[0]) == 0) { continue; }

        switch (node_type) {

            case "MACRO_METASCROLL":
                _out[$ "MSC_L"]      = true;
                _out[$ "MSC_R"]      = true;
                _out[$ "MSC_U"]      = true;
                _out[$ "MSC_D"]      = true;
                _out[$ "MSC_Update"] = true;
            break;

            case "MACRO_SCROLL":
                _out[$ "Scroller_L"] = true;
                _out[$ "Scroller_R"] = true;
                var _sc_src = (array_length(instructions[0]) > 6  && is_real(instructions[0][6]))  ? real(instructions[0][6])  : 0;
                var _sc_vm  = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
                if (_sc_src == 1 && _sc_vm == 1)
                {
                    _out[$ "Scroller_MapSet"] = true;
                }
            break;

            case "MACRO_VSCROLL":
                _out[$ "Scroller_U"] = true;
                _out[$ "Scroller_D"] = true;
            break;

            case "MACRO_SID_SONG":
                _out[$ "sng" + string(stable_uid) + "_play"] = true;
                _out[$ "sng" + string(stable_uid) + "_init"] = true;
                _out[$ "sng" + string(stable_uid) + "_seek"] = true;
            break;

            case "MACRO_HUD":
                var _hud_key = "hud" + string(stable_uid) + "_";
                _out[$ _hud_key + "draw"] = true;
                // One per DIGITS/BAR field. TEXT fields emit no routine, so
                // publishing a label for them would send a JSR to a symbol the
                // compile chain never creates.
                var _hud_name = "";
                if (array_length(instructions[0]) > 1) {
                    _hud_name = string(instructions[0][1]);
                }
                if (_hud_name != "" && instance_exists(obj_asset_manager)) {
                    var _hud_am = obj_asset_manager;
                    for (var _hai = 0; _hai < ds_list_size(_hud_am.asset_list); _hai++) {
                        var _hua = ds_list_find_value(_hud_am.asset_list, _hai);
                        if (_hua.type != "HUD" || _hua.name != _hud_name) {
                            continue;
                        }
                        if (!variable_struct_exists(_hua.meta, "fields")) {
                            break;
                        }
                        var _hud_fields = _hua.meta.fields;
                        for (var _hfi = 0; _hfi < array_length(_hud_fields); _hfi++) {
                            var _huf = _hud_fields[_hfi];
                            if (real(_huf.kind) == 0) {
                                continue;
                            }
                            _out[$ _hud_key + string(_huf.name)] = true;
                        }
                        break;
                    }
                }
            break;

            case "MACRO_ANIM":
                var _an_alias = anim_alias;
                if (_an_alias == "")
                {
                    _an_alias = "anim" + string(real(id));
                }
                _out[$ _an_alias + "_sub"]   = true;
                _out[$ _an_alias + "_reset"] = true;
            break;

            case "MACRO_TEXT_SCROLL":
                var _jsr_m = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
                if (_jsr_m == 1)
                {
                    var _ts_alias = "ts" + string(real(id));
                    if (array_length(instructions[0]) > 12
                     && is_string(instructions[0][12])
                     && string(instructions[0][12]) != "")
                    {
                        _ts_alias = string(instructions[0][12]);
                    }
                    _out[$ _ts_alias + "_scrl"] = true;
                }
            break;
        }
    }

    return _out;
}
