Drop audio files into the matching subfolder — the game scans each folder at startup
and picks a random file from it whenever that sound is triggered.
No filename conventions needed; any .wav, .ogg, or .mp3 will be picked up.

FOLDER LAYOUT
──────────────
sounds/
├── Blade_Blade/   Outer disc vs outer disc    (fallback for all clash sounds)
├── Blade_Ring/    Outer disc hits energy ring  (ringing, resonant metallic tone)
├── Blade_Track/   Outer disc hits track body   (duller thud / clunk)
├── Blade_Wall/    Blade or side hits bowl wall (sharp scrape / impact)
├── Tip_Wall/      Tip contacts the bowl floor  (soft tick / scrape)
└── music/         Background music tracks      (not yet wired to gameplay)

FALLBACK RULES
───────────────
If Blade_Ring/ or Blade_Track/ are empty, the game falls back to Blade_Blade/.
If Tip_Wall/ is empty the game falls back to Blade_Wall/, and vice versa.
If a folder has no files at all a synthesised placeholder tone is used instead.

MULTIPLE FILES PER FOLDER
───────────────────────────
Add as many files as you like to each folder — the game picks one at random
every hit, so variety feels natural without any extra code.

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
