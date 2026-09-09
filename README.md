# Omarchy Shell Plugin for Obsidian Search

A beautiful [Obsidian](https://obsidian.md/) vault search menu. Type to filter notes with fuzzy ranking, open one with Enter, or create a new note when nothing matches.

![Obsidian Search preview](preview.png)

## Features

- Fuzzy search across your vault, ranked by relevance
- Daily notes included, resolved from your daily-notes settings
- Today's daily note pinned on top, opened or created with one Enter
- Support for bases and canvas files as well
- Create a missing note directly from the menu
- Open notes in Obsidian, omawrite, Neovim, or any command you configure

## Requirements

- Omarchy quattro
- Obsidian
- `fd` and `jq` (preinstalled on Omarchy)

## Install

```bash
omarchy plugin add https://github.com/BibekBhusal0/omarchy-obsidian-search.git --enable
```

## Demo

![Obsidian search Demo](demo.gif)

## Usage

Bind the menu to a key (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER", "O", "exec, omarchy-shell shell summon bibek.obsidian-search")
```

Type to filter, Enter opens the selected note, Escape closes. A query that matches nothing creates `query.md` in the vault root. With an empty query the first row is always today's daily note, opened via Obsidian's `obsidian://daily` URI (it creates the note when missing). Typing `daily` or `today` keeps that row pinned on top.

Shortcuts: Up/Down or Ctrl+K/Ctrl+J to move, PageUp/PageDown to jump, Enter to open with the configured opener, Alt+O to open the selected note in omawrite, Alt+N to open it in Neovim.

## Where notes open

Regular notes open in your configured opener (Obsidian by default). Everything else always opens in Obsidian:

- Today's daily note and daily-note files
- Canvas files
- Bases
- Templates

So Alt+O and Alt+N only ever apply to regular notes. Creating a missing note also follows the opener: Obsidian creates it for you by default, while an external opener gets an empty file created first and then opened in that app.

## Configuration

The vault is auto-detected from `~/.config/obsidian/obsidian.json` by default. Daily notes are shown by default: the plugin reads the daily folder from `.obsidian/daily-notes.json` (or the periodic-notes plugin when it manages daily notes), and only hides that exact folder when you opt out. The today's-note pin needs the daily-notes (or periodic-notes daily) plugin enabled in the vault; it opens via `obsidian://daily`, so no filename or folder setup is needed for it.

Override settings in `~/.config/omarchy/obsidian-search.json` (watched live, so edits apply instantly):

```json
{
  "vaultPath": "/path/to/your/vault",
  "showDailyNotes": true,
  "showTemplates": false,
  "opener": "obsidian"
}
```

- `vaultPath`: vault directory. Defaults to the first vault in the Obsidian config.
- `showDailyNotes`: show daily notes in results. Default `true`. Today's-note pin is always shown regardless.
- `showTemplates`: also list files under the templates folder. Default `false`.
- `opener`: how notes open with Enter. Default `"obsidian"`. Use `"omawrite"` to edit in omawrite, `"neovim"` (or `"nvim"`) to edit in Neovim inside a terminal, or any other command that takes a file path (for example `"code"` or `"xdg-open"`).

```json
{ "vaultPath": "/path/to/your/vault", "opener": "omawrite" }
```

```json
{ "id": "bibek.obsidian-search", "opener": "neovim" }
```

## Uninstall

```bash
omarchy plugin remove bibek.obsidian-search
```

## Credits

Fuzzy matching uses [`FuzzySearch.js`](FuzzySearch.js), adapted from [omarchy-raindrop-bookmarks](https://github.com/treramey/omarchy-raindrop-bookmarks) by Trevor Ramey, licensed under the MIT License.

This plugin is licensed under the [MIT License](LICENSE).

## Others

Here are my other Omarchy plugins:

- [Focusd](https://github.com/BibekBhusal0/omarchy-focusd) - pomodoro timer with streak, history and daily goal
- [Readest](https://github.com/BibekBhusal0/omarchy-readest) - fuzzy-search your Readest library
- [Youtube Video Downloader](https://github.com/BibekBhusal0/omarchy-ytdl) - video downloads with progress and history
- [Better Lock](https://github.com/BibekBhusal0/omarchy-better-lock) - lock screen with date/time, media and power controls
- [Better Media](https://github.com/BibekBhusal0/omarchy-better-media) - MPRIS now-playing with playback controls
- [Better Menu](https://github.com/BibekBhusal0/omarchy-better-menu) - fuzzy menu with app grid, calculator and web search

Please give a star if you find them useful!
