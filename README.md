# rhythmgame

Godot-based rhythm game prototype with osu!mania `.osu` / `.osz` import support (4K filtered).

## Downloads

- GitHub Pages build portal: `https://<your-user>.github.io/<repo>/`
- Compatible 4K map search:
  - https://osu.ppy.sh/beatmapsets?m=3&q=keys%3D4%20stars%3D1&s=any
- Bundled easiest 4K map release asset:
  - `speicher-galerie-easiest-4k.osz`

## Build/Release Pipeline

This repo includes GitHub Actions workflows that:

- Export Windows and macOS builds on pushes to `main`
- Publish the newest assets to a `latest` prerelease tag
- Deploy `docs/` to GitHub Pages

## Leaderboard Infrastructure

The project includes a leaderboard scaffold for future backend integration:

- `scripts/LeaderboardService.gd`
- Menu panel wiring in `scripts/Main.gd`

Current behavior is intentionally placeholder-only until a backend API is added.
