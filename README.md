# Omarchy Shell Plugin for Obsidian Search

A beautiful [Obsidian](https://obsidian.md/) vault search menu. Type to filter notes with fuzzy ranking, open one with Enter, or create a new note when nothing matches.

## Features

- Fuzzy search across your vault, ranked by relevance
- Support for bases and canvas files as well
- Create a missing note directly from the menu

## Requirements

- Omarchy quattro
- Obsidian
- `fd` and `jq` (preinstalled on Omarchy)

## Install

```bash
omarchy plugin add https://github.com/BibekBhusal0/omarchy-obsidian-search.git --enable
```

## Usage

Bind the menu to a key (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER", "O", "exec, omarchy-shell shell summon bibek.obsidian-search")
```

Type to filter, Enter opens the selected note, Escape closes. A query that matches nothing creates `query.md` in the vault root.

## Configuration

The vault is auto-detected from `~/.config/obsidian/obsidian.json` by default. Override it under the plugin entry in `~/.config/omarchy/shell.json`:

```json
"plugins": [
  { "id": "bibek.obsidian-search", "vaultPath": "/path/to/your/vault" }
]
```

## Uninstall

```bash
omarchy plugin remove bibek.obsidian-search
```

## Credits

Fuzzy matching uses [`FuzzySearch.js`](FuzzySearch.js), adapted from [omarchy-raindrop-bookmarks](https://github.com/treramey/omarchy-raindrop-bookmarks) by Trevor Ramey, licensed under the MIT License.

This plugin is licensed under the [MIT License](LICENSE).
