/// @function scr_open_text_editor(_path)
/// @description Opens a text file in the system default text editor.
/// @param {string} _path  Absolute path to a text file

function scr_open_text_editor(_path)
{
    if (_path == "" || !file_exists(_path)) return;

        execute_shell_simple("notepad.exe", _path);

}