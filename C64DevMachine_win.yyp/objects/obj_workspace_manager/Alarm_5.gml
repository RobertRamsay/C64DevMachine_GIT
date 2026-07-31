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
	    if (show_question("Autosave detected:\n" + filename_name(_last_autosave) + "\n\nLoad it?")) {
	        scr_load_workspace_from_path(_last_autosave);
	    }
	}
}