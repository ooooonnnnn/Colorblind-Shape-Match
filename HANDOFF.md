# Shape Match: handoff notes

Where the work stands, why it was built this way, and what to pick up next.
Last updated 2026-10-21.

## The game in one paragraph

A Godot 4.7 (GL Compatibility, 1920×1080, Android export) colour-vision
screening game for young children, styled as a shape sorter. Holes sit in a
tray, hollow outlined pieces are scattered on the board, and the child drags
or taps each piece into its hole. Levels can hide the pieces under an
Ishihara-style dot filter (`scripts/dots.gd`, `shaders/dot_circle.gdshader`):
each dot reads the screen under its centre and takes the background colour or
the piece colour, with Perlin hue/saturation/brightness noise. Colour groups
(Protan, Deutan, Tritan) decide which colours are used. Every piece's search
time, wrong drops and outcome are saved as stats (`scripts/stats.gd`), read on
the stats screen and exported to Excel.

## The research articles

Both are in `C:\Users\talor\Downloads\`. They are the source for the colour
groups, the simulation and the stats reading.

1. **"Advanced Colorimetry Protocols and Design in Color Vision Deficiency
   Diagnosis for Children Using Pseudoisochromatic Plates"**
   (`Ishihara Test Colors For Children.pdf`)
   - **Confusion lines:** for each type, colours on one straight line through
     its *copunctal point* on the CIE 1931 xy diagram look the same to it, at
     equal brightness. The copunctal points (the numbers everything is built on):

     | Type | Missing cone | CIE 1931 x | CIE 1931 y | Confused colours |
     |---|---|---|---|---|
     | Protan | L (red) | 0.747 | 0.253 | red, yellow-green, grey |
     | Deutan | M (green) | 1.080 | −0.800 | green, purple-magenta, grey |
     | Tritan | S (blue) | 0.171 | 0.000 | blue, yellow, purple |

   - **Colour pairings:** red-green plates use yellow-green to blue-green
     backgrounds with red, orange and purple figures (Ishihara/CVTME). HRR uses
     a neutral grey background with red/cyan (protan), green/magenta (deutan)
     and blue-purple/yellow-green (tritan) figures.
   - **Luminance noise:** dots must vary in brightness so a figure can't be
     found by brightness alone.
   - **Shapes for children:** CVTME uses circle, star and square instead of
     numbers.
   - **Plate types:** demonstration plates (visible to all, prove the child
     can do the task), vanishing plates, transformation plates and hidden plates.
   - **Hesitation:** answers that take over 30 s, or self-corrections, point to
     a deficiency even when the answer ends up right.
   - **Screen limits:** sRGB screens, blue-light filters and "True Tone" break
     calibration, so the game screens; it doesn't diagnose.
   - **Watch out:** the prose in this article says purple-magenta is on the
     *protan* line, but its own copunctal numbers put green ↔ purple-magenta on
     the *deutan* line. We follow the numbers.

2. **"Comprehensive Research Report on Color Vision Deficiencies: Etiology,
   Prevalence Across Demographic Groups, and Clinical Paradigms"**
   (`Color Blindness Types and Prevalence.pdf`)
   - **Prevalence:** deuteranomaly ~5–6% of males (most common), protanomaly
     ~1%, protanopia ~1%, deuteranopia ~1%, tritan under 0.01% (males and
     females alike). Overall about 8% of males and 0.5% of females in European
     populations.
   - **Anomalous vs dichromat:** most colour-blind people are anomalous
     trichromats (a shifted cone), not dichromats (a missing cone). That's why
     colour blind mode has a Strength slider.
   - **Protan detail:** red looks dark to protans (a red-black confusion).
   - **Used for:** the "kind" and "prevalence" text on the groups and the notes
     on the stats screen.

## What was built

### 1. Colour blind mode (Settings → "Color blind" tab)

Shows every screen of the game as one type sees it.

- **Files:** `scripts/color_vision.gd` (autoload `ColorVision`, CanvasLayer
  128, above the dots at 100 and effects at 101), `shaders/color_vision.gdshader`
  and `color_vision.json` (`mode`: none/protan/deutan/tritan,
  `severity_percent`).
- **Model:** the cone space is built so each missing-cone axis has *exactly*
  the article's copunctal chromaticity, normalised so sRGB white is (1, 1, 1).
  A colour is then projected along the missing cone onto two half-planes
  (Brettel, Viénot & Mollon 1997) anchored at 475/575 nm for protan and deutan
  and 485/660 nm for tritan (CIE 1931 2° colour matching values are in
  `SPECTRUM`). Strength blends between normal (0) and the full dichromacy (1).
- **Why not the Machado (2009) matrices:** the first version used them, but
  they don't match the article's copunctal points (deutan especially). That
  made protan colours vanish for deutans, which you noticed.
- **Saving:** live while editing; saved with Save; Back drops unsaved changes.
- **Don't ship a mode switched on:** `color_vision.json` is committed, so keep
  `mode` at `"none"` in commits.

### 2. Colour groups rebuilt from the article (`scripts/color_groups.gd`)

- **Rule:** a colour is invisible to a type exactly when it differs from the
  background *only in the cone that type is missing*. Each figure colour is the
  background with only that cone scaled, from pale to vivid.

  | Group | Background | Figure colours | Looks like |
  |---|---|---|---|
  | Protan | `#559c68` | `#b59267 #c98e67 #db8b67 #eb8767 #fa8366` | salmon reds/oranges on green |
  | Deutan | `#489b6d` | `#8c807b #9f7180 #b06085 #be498a #cc248f` | mauve → magenta on green |
  | Tritan | `#8b8b8b` | `#977fc7 #9d76e3 #a46dfb #839245 #819420` | violets and yellow-greens on grey |

- **Verified result:** each group's own type sees ΔE 0 (CIELAB) between pieces
  and background, while the other two types see 20–78. The protan group has no
  purples, because purple isn't on the protan line through a green background.
- **Swatch bars:** the bars under the swatches on the Colors tab now check "does
  this colour vanish for the group's type" (`ColorGroups.seen_difference`,
  tolerance `MATCH_TOLERANCE` = 5), not brightness.
- **Dot noise:** hue and saturation noise shifts dots slightly off the exact
  line. Brightness noise doesn't (it's the article's luminance noise).

### 3. Extra shapes (control pieces)

Pieces in colours the level's type sees as well as anyone. If a player finds
them but misses the group's pieces, that points to colour rather than attention.

- **Per sequence (Levels tab):** two controls on each card.
  - **"Extra shapes":** 0–20, *added* to the board on top of the level's pieces.
  - **"Extras count toward score":**
    - **On:** extras are part of the total; every piece must be placed (2 own
      + 2 extra = 4 dots).
    - **Off:** only the level's own pieces count (2 dots), extras are optional,
      and leftover extras float away when the level clears.
  - **Saved in `config.json`** as `extra` and `extra_scored` per sequence.
- **Colours (Shapes tab → "How easy to see"):** a target ΔE as seen by the
  group's type (default 30, in `extra_shapes.json`). `ColorGroups.extra_colors`
  searches the cones the type still has, up and down, for up to 2 in-gamut
  colours near that difference. Swatches per group are shown.
- **Dot filter:** shader slots raised from 7 to 9
  (`BASE_COUNT = 1 + MAX_COLORS 6 + MAX_EXTRA_COLORS 2`).
- **Stats:**
  - **Group:** in filtered levels extras are recorded under group `"extra"`
    (`Stats.EXTRA`); in unfiltered levels under the baseline.
  - **Flag:** each record has `"extra": true/false`.
  - **Stats screen:** shows an "Extra shapes" control card.
  - **Excel export:** has an "Extra shape" column.
  - **Leftovers:** extras left when a level clears aren't recorded; own pieces
    left (possible when extras count) are recorded as seen or missed.

### Also on `main` (from the other branches, not covered here)

- **Time bonus:** +2 s per match and −1 s per stray tap, per sequence.
- **Optional dragging:** `play.json` and the "Other" tab on the settings page.
- **Tutorial level:** a hand demo, switched on with `tutorial: true` in
  `play.json`.

## Branches: status on 2026-10-21

- **`main` (`e51dbd1`):** has everything above **except** the latest extra-shape
  fix. Its `main.gd` still clears after the level's own count
  (`_left_to_clear = own`, `pips.total = own`).
- **`visual-fixes` (`3b9d26b "idk"`):** has that fix (extras counted when the
  switch is on), but not the tutorial and dragging work.
- **First thing next time:** merge `visual-fixes` into `main` and check that
  `main.gd` ends up with:

  ```gdscript
  _left_to_clear = total if extra_scored else own
  pips.total = _left_to_clear
  ```

  Expect conflicts in `scripts/main.gd` and `scripts/config.gd`, because both
  branches changed them.
- **GitHub Desktop:** it stashes uncommitted changes when you switch branches
  (`!!GitHub_Desktop<branch>` in `git stash list`). Restore them with
  `git stash pop` on the same branch.

## Settings files (all `res://` in the editor, copied to `user://` when exported; see `scripts/settings_file.gd`)

| File | Holds | Edited on |
|---|---|---|
| `config.json` | level sequences, including `extra` and `extra_scored` | Levels tab |
| `dots.json`, `noise.json` | dot size and colour noise | Dots tab |
| `color_groups.json` | research groups or your own copy | Colors tab |
| `shape_size.json` | piece size and outline | Shapes tab |
| `extra_shapes.json` | extra-shape visibility (`difference`) | Shapes tab |
| `color_vision.json` | colour blind mode and strength | Color blind tab |
| `play.json` | dragging, tutorial | Other tab |

## How things were tested

- **Godot executable:** `C:\Users\talor\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Compile check:**
  `Godot --path <project> --headless --editor --quit`. Afterwards run
  `git checkout -- '*.import'`, because the re-import rewrites `.import` files.
- **Behaviour tests:** a throwaway `extends SceneTree` script run with
  `Godot --path <project> --script <file.gd>`. It opens `main.tscn` or
  `config.tscn`, sets up a level (`game.levels = one; game.level_num = 0;
  game.new_level()`), calls `game.place(p)`, prints counts and saves
  screenshots with `root.get_texture().get_image().save_png(...)`. Wait about
  1.5 s between levels, or the clear animation's timers throw errors.
- **Colour maths:** checked in plain Python (no numpy available) against the
  same copunctal-point model. GDScript gives the same numbers.
- **Harmless warning:** "Dots covered 47% of the area, short of 50%" was there
  before all of this.

## Open ideas and loose ends

- **Merge first:** merge `visual-fixes` → `main` (see above).
- **Extra shapes in the preview:** the Settings preview doesn't show extra
  shapes yet.
- **Stats bias:** with extras not counting, leftover extras aren't recorded, so
  the "Extra shapes" control card can look better than it should. Recording
  them as "missed" is a one-line change in `end_level` (`scripts/main.gd`).
- **Colour blind mode in stats:** session details don't say whether colour
  blind mode was on during play. Worth adding if testers might leave it on.
- **Protan palette:** it's one hue family (salmon/orange), since one background
  allows only one confusion line. More variety would need several backgrounds
  per group, which the dot shader doesn't support yet.
- **Strength slider:** a linear blend toward the dichromat, an approximation
  of anomalous trichromacy, not a separate model per severity.
