# Snake (Godot 4) — notes for Claude

Live: https://sobalaklukasz.github.io/snake/ · Repo: https://github.com/sobalaklukasz/snake
The owner plays and tests mainly on an iPhone in Safari. Keep replies short; explain in plain words.

## Project
- Godot **4.7.2**, GDScript, compatibility renderer (needed for web). Web is the only target for now.
- Everything is in `main.gd` (one Node2D, all drawing in `_draw()`), scene `main.tscn`.
- Viewport 720x1280, stretch `canvas_items` + `expand`; layout is computed from `get_viewport_rect()`.
- Warnings are treated as errors: give variables explicit types when the value is a Variant
  (e.g. `turns.back()`, `min()` → use `minf()`).
- `ProjectSettings application/config/version` is empty locally ("dev" is shown) and stamped by CI.

## Build & test locally (Windows, PowerShell 5.1)
- Godot console exe:
  `C:\Users\sobal\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- Web templates are installed in `%APPDATA%\Godot\export_templates\4.7.2.stable` (web only).
- Export: `& $godot --headless --export-release "Web" build/web/index.html` (run in the project folder).
- Preview server: config `snake` in `C:\Users\sobal\IdeaProjects\one-button-game\.claude\launch.json`
  (python http.server on 127.0.0.1:8001 serving `build/web`).
  It sometimes resets the 40 MB `index.wasm` download → restart the preview server.
  After rebuilding, the browser may cache `index.pck`; refetch with `fetch(f, {cache:'reload'})`.
- Drive the game in the preview: arrow keys via the computer tool; swipes via JS `TouchEvent`s on the
  canvas with several `touchmove`s (a single drag jumps and is ignored).

## Deploy
- Push to `main` → `.github/workflows/deploy.yml` builds with Godot on Linux and publishes to Pages.
  It stamps `vN · date time` into the version and renames `index.pck` to `game-<sha>.pck` (cache busting).
- `gh` is at `C:\Program Files\GitHub CLI` (add to PATH per command).

## World record (Firebase)
- Realtime Database `https://snake-45897-default-rtdb.europe-west1.firebasedatabase.app`, value at `records/snake`.
- Rules in `database.rules.json` (owner pastes them into the Firebase console): public read,
  number only, can only go up, no delete. Verified working.
- **Never send fake/test scores to the live database.** The game skips uploads when running on
  localhost or outside the browser, so local tests are safe.
- Personal best is saved with `ConfigFile` at `user://save.cfg` (browser storage on the web).

## Related
- The first game, Auuuuu (plain HTML/JS), lives in `C:\Users\sobal\IdeaProjects\one-button-game`
  and must stay untouched unless asked. It uses a different Firebase project (auuuuu-83d66).
