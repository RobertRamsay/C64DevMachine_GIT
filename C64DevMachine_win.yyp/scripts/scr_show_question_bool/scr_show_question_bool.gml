/// @desc OS-safe wrapper for show_question(). On Windows, show_question()
///       returns a real boolean. On Mac, it returns the string "Yes" / "No"
///       instead — see project convention: Mac show_question always needs
///       string comparison, never boolean truthiness. This wrapper hides that
///       difference so call sites can treat the result as a plain bool on
///       either platform.
/// @param {String} _msg  the question text to display
/// @return {Bool} true if the user chose Yes, false otherwise
function scr_show_question_bool(_msg) {
    var _result = show_question(_msg);
    if (os_type == os_macosx) {
        return (string(_result) == "Yes");
    }
    return _result;
}
