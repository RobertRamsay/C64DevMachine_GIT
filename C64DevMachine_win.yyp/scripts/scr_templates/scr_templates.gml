/// Bundled projects use the normal JSON loader and existing C64 features.
function scr_template_catalog(_index) {
    var _titles = ["V.SHMUP", "H.SHMUP", "PFORMER", "PFRMR.SCRL", "TOP DOWN"];
    var _files = ["vshmup", "hshmup", "pformer", "pfrmr_scrl", "top_down"];
    var _genre = clamp(_index div 2, 0, 4);
    var _pro = (_index mod 2) == 1;
    return {title: _titles[_genre] + (_pro ? " (PRO)" : " (LITE)"), pro: _pro,
        path: working_directory + "C64DMResources/TEMPLATES/" + _files[_genre] + (_pro ? "_pro.json" : "_lite.json")};
}

function scr_template_load(_index) {
    if (_index < 0 || _index >= 10) return;
    var _entry = scr_template_catalog(_index);
    if (global.lite && _entry.pro) return;
    // Validate before the native loader destroys the current workspace.
    if (!file_exists(_entry.path)) { scr_show_message("Template file is missing: " + _entry.title); return; }
    var _buf = buffer_load(_entry.path);
    if (_buf == -1) { scr_show_message("Could not read template."); return; }
    var _text = buffer_read(_buf, buffer_text);
    buffer_delete(_buf);
    try {
        var _data = json_parse(_text);
        if (!is_struct(_data) || !variable_struct_exists(_data, "nodes") || !is_array(_data.nodes)
            || !variable_struct_exists(_data, "assets") || !is_array(_data.assets)) throw "Invalid project";
    } catch (_err) { scr_show_message("Template project is invalid."); return; }
    scr_load_workspace_from_path(_entry.path, true);
    // A template is a new document: SAVE must never overwrite the bundled JSON.
    global.workspace_path = "";
    global.current_filename = "";
    global.manual_saved = false;
    global.saved_hash = "";
    global.saved_hash_pending = 0;
    global.autosave_dirty = true;
    window_set_caption(game_project_name + " - " + _entry.title + " (new project)");
}

function scr_template_step() {
    if (global.question_result == "template_save_yes") {
        global.question_result = "";
        var _choice = template_waiting;
        template_waiting = -1;
        // Cancelled Save As leaves changes intact and cancels the template load.
        var _default = global.workspace_path != "" ? filename_name(global.workspace_path) : "my_project.json";
        var _path = get_save_filename("C64 Node Project|*.json", _default);
        io_clear();
        if (_path == "") return;
        scr_save_workspace_as_path(_path);
        // Verify the written document before replacing the workspace.
        var _verified = false;
        if (file_exists(_path)) {
            var _saved = buffer_load(_path);
            if (_saved != -1) {
                _verified = md5_string_utf8(buffer_read(_saved, buffer_text)) == global.saved_hash;
                buffer_delete(_saved);
            }
        }
        if (_verified) scr_template_load(_choice);
        else {
            global.manual_saved = false;
            scr_show_message("The save could not be verified. Your current project has been kept.");
        }
        return;
    }
    if (global.question_result == "template_save_no") {
        global.question_result = "";
        scr_show_question("Discard changes and load the template?\nNO keeps your current project.", "template_discard");
        return;
    }
    if (global.question_result == "template_discard_yes") {
        global.question_result = "";
        var _choice = template_waiting;
        template_waiting = -1;
        scr_template_load(_choice);
        return;
    }
    if (global.question_result == "template_discard_no") {
        global.question_result = "";
        template_waiting = -1;
        return;
    }
    if (template_pending < 0 || instance_exists(obj_question_box)) return;
    var _choice = template_pending;
    template_pending = -1;
    if (global.lite && scr_template_catalog(_choice).pro) return;
    if (scr_workspace_has_changes()) {
        template_waiting = _choice;
        scr_show_question("Save changes before loading the template?", "template_save");
    } else scr_template_load(_choice);
}
