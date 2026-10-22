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
  edited in a pop-up), Playing, Dots, Colors, with the color blind view beside
  the preview; nothing is written until Save, and leaving unsaved asks first.
- `scripts/popup_card.gd`, `info_button.gd`, `toy_switch.gd`: the pop-up window,
  the round "?" that opens an explanation, and the on/off switch both grown-up
  screens use. Pop-ups sit on their own CanvasLayer (110), above the dots.
- `scripts/dots.gd` + `shaders/dot_circle.gdshader`: the Ishihara dot filter
  (a CanvasLayer that repacks circles around the tray and reads screen colors).
- `scripts/color_groups.gd`: protan/deutan/tritan confusion-color groups.
- `scripts/color_vision.gd`: autoload that simulates color blindness on screen.
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

All of them read and write through `SettingsFile.read_path` / `write_path`. In
the editor that's the `res://` file itself, so tuned settings can be committed.
An exported game can't write `res://`, so it saves to `user://` and reads that
copy once it exists. The export presets have `include_filter="*.json"` so the
files are packed at all.

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
