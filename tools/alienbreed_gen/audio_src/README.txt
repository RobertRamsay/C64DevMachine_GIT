REU audio sources for ALIEN BREED 64 (C64 Ultimate / REU build).

Drop mono or stereo WAV files here (PCM 8/16/24/32-bit or float) and run
node build.mjs again; each one replaces the generator's own version:

  title.wav      title theme (loops)            -> 7884 Hz, 4-bit
  gun.wav  alien_die.wav  hurt.wav  pickup.wav  door.wav
  key.wav  terminal.wav  alarm.wav  core_hit.wav  explode.wav
                                                -> 5512 Hz, 4-bit

This is where the original Amiga audio goes once Team17 supplies it: the
tracks in the GamesNostalgia package are in Team17's packed module format
and could not be extracted cleanly.
