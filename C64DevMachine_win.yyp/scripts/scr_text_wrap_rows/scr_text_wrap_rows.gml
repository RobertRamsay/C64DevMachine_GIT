/// @function scr_text_wrap_rows(_txt, _max_w)
/// @desc Splits a string into VISUAL rows that each fit inside _max_w pixels
///       in the CURRENTLY SET FONT. Call draw_set_font() before this.
///
/// Rows break on hard newlines first, then soft-wrap on the last space that
/// still fits, falling back to a hard character break for a single word that
/// is wider than the box. Nothing is ever scaled and nothing ever overruns
/// _max_w, which is the whole point: the asset viewers used to either squash
/// text horizontally with draw_text_transformed (unreadable at any length) or
/// draw it raw and let it run out past the panel edge.
///
/// Rows are CONTIGUOUS in offset terms — row N+1 starts exactly where row N
/// ends — so a caret offset into the original string maps onto a row and a
/// column with no bookkeeping. A soft break keeps the breaking space at the
/// end of the row it broke on (invisible), which is what preserves that.
///
/// @param {string} _txt    the text to lay out
/// @param {real}   _max_w  usable width in pixels
/// @return {array} array of structs:
///                   text - the row's characters
///                   off  - 0-based offset of the row's first char in _txt
///                   lnum - 0-based LOGICAL line index (for a gutter number)
///                   iscont - true when this row is a soft-wrap continuation
function scr_text_wrap_rows(_txt, _max_w) {

    var _rows = [];

    // A box this narrow cannot show anything sensible; clamp rather than
    // loop forever on a zero-width row.
    var _w = _max_w;
    if (_w < 8) {
        _w = 8;
    }

    var _lines = [""];
    if (_txt != "") {
        _lines = string_split(_txt, "\n");
    }
    if (array_length(_lines) == 0) {
        _lines = [""];
    }

    var _base = 0;   // absolute offset of the current logical line's first char

    for (var _li = 0; _li < array_length(_lines); _li++) {

        var _line  = _lines[_li];
        var _llen  = string_length(_line);
        var _pos   = 0;      // characters of this logical line already placed
        var _first = true;

        while (true) {

            var _rest_len = _llen - _pos;

            // Empty logical line still needs one row, so the gutter numbering
            // and the caret both have somewhere to sit.
            if (_rest_len <= 0) {
                if (_first) {
                    array_push(_rows, {
                        text: "",
                        off:  _base + _pos,
                        lnum: _li,
                        iscont: false
                    });
                }
                break;
            }

            var _rest = string_copy(_line, _pos + 1, _rest_len);

            if (string_width(_rest) <= _w) {
                array_push(_rows, {
                    text: _rest,
                    off:  _base + _pos,
                    lnum: _li,
                    iscont: !_first
                });
                break;
            }

            // Largest prefix that fits, by binary search. string_width() is
            // the expensive call here, so this is log(n) of them per row
            // rather than one per character.
            var _lo  = 1;
            var _hi  = _rest_len;
            var _fit = 1;
            while (_lo <= _hi) {
                var _mid = floor((_lo + _hi) / 2);
                if (string_width(string_copy(_rest, 1, _mid)) <= _w) {
                    _fit = _mid;
                    _lo  = _mid + 1;
                } else {
                    _hi = _mid - 1;
                }
            }

            // Prefer the last space inside that prefix so words stay whole.
            // Position 1 is excluded: breaking there would emit a row holding
            // nothing but a space and make no progress on a long word.
            var _take = _fit;
            for (var _ci = _fit; _ci >= 2; _ci--) {
                if (string_char_at(_rest, _ci) == " ") {
                    _take = _ci;
                    break;
                }
            }

            array_push(_rows, {
                text: string_copy(_rest, 1, _take),
                off:  _base + _pos,
                lnum: _li,
                iscont: !_first
            });

            _pos  += _take;
            _first = false;
        }

        _base += _llen + 1;   // +1 for the newline that split() consumed
    }

    return _rows;
}
