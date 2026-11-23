# Snake

Classic snake made with [Godot 4](https://godotengine.org), playable in the browser.

**▶ Play: https://sobalaklukasz.github.io/snake/**

## How to play

- **Phone:** swipe to turn. Keep your finger down and swipe again for quick turns.
- **Computer:** arrow keys or WASD.
- Eat the gold coins (+10 each). The snake gets faster as it grows.
- Hitting a wall or yourself ends the game. Tap or press any key to play again.

**Your best** (top left) is saved on your device. **World record** (top right) is shared by all players through Firebase.

## Development

1. Open `project.godot` in Godot 4.7.
2. Press F5 to run.

Runs from the editor or `localhost` never upload scores.

Every push to `main` builds the web version and publishes it to GitHub Pages (`.github/workflows/deploy.yml`).

`database.rules.json` holds the Firebase rules: anyone can read the record, it can only go up, and it can't be deleted. They are pasted into the Firebase console by hand.
