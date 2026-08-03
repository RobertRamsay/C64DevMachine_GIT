if (welcome_open) {
    alarm[5] = 40; // wait for the welcome screen to close first
    exit;
}

ini_open("c64devmachine.ini");
var _last_autosave = ini_read_string("autosave", "last_path", "");
ini_close();

if global.autosave_mode!=3
	{
	if (_last_autosave != "" && file_exists(_last_autosave)) {
	    if (scr_show_question_bool("Autosave detected:\n" + filename_name(_last_autosave) + "\n\nLoad it?")) {
	        scr_load_workspace_from_path(_last_autosave);
	    } else {
	        // Declined the load — offer to clear it so this prompt
	        // doesn't keep coming back for the same stale autosave.
	        if (scr_show_question_bool("Remove this autosave so you're not asked again?")) {
	            if (file_exists(_last_autosave)) {
	                file_delete(_last_autosave);
	            }
	            ini_open("c64devmachine.ini");
	            ini_write_string("autosave", "last_path", "");
	            ini_close();
	            global.autosave_last_path = "";
	            autosave_last_path        = "";
	        }
	    }
	}
}