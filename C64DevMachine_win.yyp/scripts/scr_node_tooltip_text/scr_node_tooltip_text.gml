/// @desc scr_node_tooltip_text()
/// Returns a struct { title, lines[] } describing a node type, for the
/// header-hover tooltip system (hover the right 20% of a node's header
/// bar for ~1s with no mouse button held). Returns undefined for any
/// node_type with no entry yet, so unlisted nodes simply show nothing.
function scr_node_tooltip_text(_node_type) {
    static _map = {
        "MACRO_REU": {
            title: "REU - RAM EXPANSION UNIT",
            lines: [
                "DMA transfer between C64 RAM and REU RAM,",
                "via registers $DF00-$DF0A.",
                "",
                "OP  STASH  copies C64 -> REU",
                "    FETCH  copies REU -> C64",
                "    SWAP   exchanges both directions",
                "    COMPARE verifies only, no write",
                "",
                "C64   16-bit start address in C64 RAM",
                "REU   16-bit start address in REU RAM",
                "BANK  REU bank, 0-255 (most units: bank 0 only)",
                "LEN   bytes to move, $0000 = 65536",
                "",
                "AUTOLOAD reloads the start addresses once the",
                "transfer finishes, so the node can fire again",
                "without re-setting anything.",
                "",
                "FIX C64 / FIX REU hold that side's address",
                "still during the transfer - use for fills or",
                "repeated single-byte reads/writes.",
                "",
                "FF00-disable is always set on the command byte:",
                "without it, a stray write to $FF00 can",
                "re-trigger the last queued transfer."
            ]
        }
    };

    if (variable_struct_exists(_map, _node_type)) {
        return _map[$ _node_type];
    }
    return undefined;
}
