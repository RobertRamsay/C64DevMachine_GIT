function scr_c64_update_addresses() {
    // Just marks dirty - actual work runs once per frame in workspace manager Step
    global.addresses_dirty = true;
}