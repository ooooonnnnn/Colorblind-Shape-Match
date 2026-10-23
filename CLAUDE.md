# Shape Match (Colorblind-Shape-Match)

A Godot 4.7 (GDScript) shape-sorting game for children that doubles as a color
vision deficiency screener, built on Ishihara-style pseudoisochromatic plates.
Players drag or tap pieces into matching holes; with the dot filter on, pieces
show only through hue, so a player with the matching deficiency can't see them.

## Working rules

- Work on the `fixes-also-also` branch unless told to switch. Check
  `git branch --show-current` before editing, committing, pushing or exporting;
  if it's another branch, say so instead of carrying on. Never switch on your own.
- After committing, push right away; don't ask.
- The user often switches branches and commits from their own editor or Git
  client mid-session, and a collaborator pushes to `main` too: fetch and look
  before merging, and expect real merges, not fast-forwards.
- Scripts use CRLF line endings; keep them when editing.
- Match the code's style: `##` doc comments on classes and functions, short
  `#` comments that say why, constants with a trailing comment for units.

## Layout

- Scenes: `splash.tscn` → `menu.tscn` → `main.tscn` (game), `config.tscn`
  (grown-up settings), `stats.tscn`, `references.tscn`.
- `scripts/main.gd`: the game: levels, input (drag and tap-tap), timer, stats.
- `scripts/config.gd`: the settings page, in tabs Levels (sequence cards, each
  edited in a pop-up), Playing, Dots, Colors, Calibration, with the color blind
  view beside the preview; nothing is written until Save, and leaving unsaved
  asks first.
- `scripts/popup_card.gd`, `info_button.gd`, `toy_switch.gd`: the pop-up window,
  the round "?" that opens an explanation, and the on/off switch both grown-up
  screens use. Pop-ups sit on their own CanvasLayer (110), above the dots.
- `scripts/dots.gd` + `shaders/dot_circle.gdshader`: the Ishihara dot filter
  (a CanvasLayer that repacks circles around the tray and reads screen colors).
- `scripts/color_groups.gd`: protan/deutan/tritan confusion-color groups.
- `scripts/color_vision.gd`: autoload that simulates color blindness on screen.
- Screen calibration (from "Color calibration using a phone camera.pdf" in
  Downloads): `scripts/display_calibration.gd`, autoload `DisplayCalibration`
  (layer 128, after ColorVision so it draws last), runs every pixel through a
  32³ LUT packed in a 1024x32 texture (`shaders/display_calibration.gdshader`),
  baked from per-channel curves (codes for 25/50/75% light), a gamut matrix and
  an eye tint. `scripts/calibration_screen.gd` is the full-screen wizard
  (layer 120), with pictures from `scripts/calibration_art.gd`: by eye, only taps
  (the user found sliders and squinting too hard): the square hardest to see in
  1px gray stripes (`shaders/calibration_pattern.gdshader`, real pixels via
  FRAGCOORD) sets gamma, then "tap the grayest of 9 tinted grays" at 50/75/25%
  sets the channel balance, 3 narrowing rounds each; or
  with a phone, where `scripts/calibration_link.gd` serves
  `calibration/phone.html` over HTTPS (self-signed cert in `user://`) behind a
  QR code (`scripts/qr_code.gd`), and `scripts/camera_calibration.gd` plans the
  patches. Curves come from split patches, a solid circle in 1px stripes, the
  phone comparing the middle and a ring of one frame (so auto exposure can't
  skew it; a plain patch per search first measures lens shading), read from
  WebCodecs frames where it can. With manual exposure and white balance it
  also probes white/R/G/B and turns exposure down until none clips, then
  camera linearization from the gray matches, primaries with white point
  preservation, white to D65 if the phone locks 6500 K, and ΔE00 before/after.
  Impossible results (matches off their range, gammas outside 1.6-3.0) are
  marked untrusted and not applied. Each run's readings go to
  `user://calibration_log.json`, and a copy per run in `user://calibration_logs/`
  (in `%APPDATA%/Godot/app_userdata/Shape Match`).
  While lining up, the circle can be dragged (so the phone can rest on the desk)
  and the phone posts `/aim` with where it sees the circle's edge, so the PC
  resizes it; both are kept in `user://calibration.cfg`. The phone refuses to
  start while it sees the stripes sharply (resolved stripes clip and read low).
- Shape Match Meter (`calibration/meter`, Java with only framework classes):
  an Android app reading Camera2 RAW_SENSOR data under manual exposure, focus at
  infinity. The page offers it on Android through an `intent://` link (scheme
  `shapematch-meter`) whose fallback downloads `calibration/meter.apk` from the
  game's server. With it the game uses `scripts/raw_calibration.gd`: levels
  as a disc on a white screen (no stripes), each scaled by the white around it
  in the same picture (the user's screen read far too flat with full-screen
  patches: it dims and brightens with its content), raw straightened by a
  bracket of exposure times on white, and curves balanced on a gray ramp so
  each gray is, in raw camera colors, a dimmer copy of the white (no color
  matrix needed). The camera's matrix proved unfit for a screen's colors (it
  put the white far off, and R+G+B came to 116% of white), so gamut and white
  point are left alone; the matrix only scores ΔE00 against the screen's own
  white, grays reported apart. Eye runs are logged too. The app shows the raw picture to
  line up the disc (dragged on the PC, sized from the app's `/aim`); the game
  answers `/hello` with `METER_VERSION` (`calibration_link.gd`, keep it equal
  to `android:versionCode`) and an older app offers its update. Rebuild the APK with
  `sh calibration/meter/build.sh` (javac, d8, aapt2, zipalign, apksigner; no
  Gradle) after changing it; the built APK is committed.
- `scripts/extra_shapes.gd`: control pieces in colors the group's type sees.
- `scripts/stats.gd`, `scripts/stats_screen.gd`, `scripts/xlsx_writer.gd`: per-piece
  records in `user://stats.json`, the reading of them, and the Excel export.
- `scripts/settings_file.gd`, `scripts/play_settings.gd`, `scripts/tutorial_hand.gd`:
  see below.

## Settings files

JSON at the project root, each with a loader and saver in its script:
`config.json` (level sequences, `LevelConfig`), `dots.json` and `noise.json`
(`Dots`), `color_groups.json` (`ColorGroups`), `shape_size.json` (`ShapeView`),
`color_vision.json` (`ColorVision`), `extra_shapes.json` (`ExtraShapes`),
`play.json` (`PlaySettings`: `drag`, `tutorial`).

The exception is `user://display_calibration.json` (`DisplayCalibration`): a
calibration belongs to one screen, so it is never written to `res://`.

All of them read and write through `SettingsFile.read_path` / `write_path`. In
the editor that's the `res://` file itself, so tuned settings can be committed.
An exported game can't write `res://`, so it saves to `user://` and reads that
copy once it exists. The export presets have `include_filter="*.json, phone.html"` so the
files (and the calibration phone page) are packed at all. Android needs the
`internet` permission for the calibration server.

## Features added so far (Oct 2026)

- Settings save on Android/Web (the `SettingsFile` change above).
- Per level sequence `time_bonus` switch: in timed levels a right match adds
  `LevelConfig.TIME_BONUS` (2 s, capped at the level's full time) and a tap on
  neither a piece, a hole nor Home takes `TIME_PENALTY` (1 s). Wrong drops cost
  nothing. Stray taps are caught in `main.gd` `_input`, then claimed by the
  piece/hole/Home handlers before a deferred `_penalize_stray`.
- `new_level` calls `dots.refresh()` in the same frame, as it runs from a timer
  after `_process`; otherwise the last level's circles showed for a frame.
- Other tab, "Drag pieces" (`PlaySettings.drag`): off means tap a piece, then its hole.
- Friendlier selecting: `ShapeView._has_point` takes taps in the bounding circle
  plus outline plus `TOUCH_SLOP` (12% of the side); pieces select on press;
  `DRAG_THRESHOLD` is 14 px.
- Other tab, "Tutorial level" (`PlaySettings.tutorial`): every game starts with
  `TUTORIAL_LEVEL` in `main.gd`: one piece in `Icons.INK`, no dots, no time,
  no score or stats, while a `TutorialHand` loops (drags a lighter copy of the
  piece in drag mode, taps piece then hole otherwise). The Levels tab shows it
  as a "T" card above the sequences.
- All of this was merged into `main` at `2dc8745`.

## Possible next steps

- Sliders on the Other tab for `TOUCH_SLOP`, `DRAG_THRESHOLD`, `TIME_BONUS`,
  `TIME_PENALTY` (all fixed in code now).
- A "+2 s" / "−1 s" popup on the timer when time moves.
- Overlapping tap areas go to the piece drawn on top, not the nearest one.
- The first level of a game may still show one stale dot frame before the
  board is laid out (only level changes were fixed).
- The tutorial plays every game, not only the first.

## Screen sizes

The design size is 1080x1080 with `stretch/aspect="expand"`, so the shorter
side is always 1080 units and the longer one grows: 2400x1080 on a wide phone,
1440x1080 on a tablet, 1080x1542 upright. Settings and stats switch to a
stacked or compact layout below 1300 units wide, pop-ups keep at least 720,
and the game shrinks a level's shapes (`ShapeView.fit_scale`) when its row of
holes would not fit across the board.

## Building and checking

- Godot: `C:/Users/talor/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
- Android export is set up (templates in `AppData/Roaming/Godot/export_templates/4.7.2.stable`,
  JDK 17 in `AppData/Local/Programs/Java`, SDK in `AppData/Local/Android/Sdk`,
  debug keystore in `AppData/Roaming/Godot/keystores`). There is no release
  keystore, so export debug:
  `<godot> --headless --path . --export-debug "Android" "builds/android/<name>.apk"`.
  Web, Windows, macOS and Linux export with `--export-release` and their preset
  names into `builds/web`, `builds/windows`, `builds/mac`, `builds/linux`
  (git-ignored); zip `builds/web` for itch.
  iOS (`--export-release "iOS" "builds/ios/Shape Match.ipa"`) can only write the
  Xcode project on Windows (`export_project_only`); build and sign it in Xcode on a
  Mac. Its Team ID is the placeholder `XXXXXXXXXX`, as Godot won't export without one.
  The Java SDK path must be set in Godot's editor settings for Android.
- Quick checks, with `<godot>` the console exe:
  - `<godot> --headless --path . --import` after adding a `class_name` script.
  - `<godot> --headless --path . --quit-after 90 res://main.tscn` (and
    `config.tscn`) to catch runtime errors. `--check-only --script` misses
    autoloads, so it wrongly reports `ColorVision` as unknown in `config.gd`.
  - `<godot> --path . --resolution 960x540 --write-movie <dir>/f.png --fixed-fps 10 --quit-after 40 res://main.tscn`
    records frames to look at. Change `play.json` temporarily to test modes,
    and put the user's version back after.
