Drop audio files here and the game will pick them up automatically at startup.
Files are sorted into pools by their filename prefix — use any of the names below.

TOP-VS-TOP CLASH SOUNDS
────────────────────────
clash_blade_*.wav / .ogg    Outer disc / default clash (fallback for all clash sounds)
clash_ring_*.wav  / .ogg    Energy ring is struck  (ringing, resonant metallic tone)
clash_body_*.wav  / .ogg    Inner track body is struck  (duller thud / clunk)

If clash_ring or clash_body pools are empty, the game falls back to clash_blade.

BOWL / WALL SOUNDS
───────────────────
wall_blade_*.wav  / .ogg    Blade or side hits the bowl wall  (sharp scrape / impact)
wall_tip_*.wav    / .ogg    Tip contacts the bowl floor        (soft tick / scrape)

If wall_tip is empty the game falls back to wall_blade, and vice versa.

VOLUME & PITCH
───────────────
All sounds are automatically scaled by impact speed (faster = louder).
A ±8–10 % random pitch shift is applied each play so repeated hits feel natural.
Tip sounds are mixed 6–8 dB quieter than blade hits at the same speed.

RECOMMENDED FREE SOURCES
──────────────────────────
freesound.org   — search "metal impact", "metal clang", "metal scrape"
zapsplat.com    — "metal clash", "impact hard", "scrape metal"
kenney.nl/assets/impact-sounds

TIPS
─────
• Short punchy files (< 0.5 s) work best for clashes.
• Tip scrape sounds can be slightly longer (0.3–1 s) since they fade naturally.
• Export at 44 100 Hz / 16-bit WAV or OGG Vorbis q6+.
• Normalise each file to around -3 dBFS before dropping in.
• You can have multiple files per pool (e.g. clash_blade_1.wav, clash_blade_2.wav)
  and the game will pick one at random each hit.
