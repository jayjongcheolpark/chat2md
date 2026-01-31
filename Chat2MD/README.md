# Chat2MD

A macOS menu bar app that syncs [Claude Code](https://claude.ai/claude-code) conversations to Markdown files for use with [Obsidian](https://obsidian.md) or any markdown-based note system.

## Features

- **Automatic Sync**: Periodically syncs new conversations (configurable interval: 5s - 5min)
- **Incremental Updates**: Only syncs new messages, not entire conversations
- **Smart Optimization**: Uses file modification time to skip unchanged files
- **Auto Cleanup**: Removes orphan entries when project folders are deleted
- **Launch at Login**: Optionally start automatically when you log in
- **Status Graph**: Visual history of recent sync operations
- **Debug View**: Inspect sync state and troubleshoot issues

## Screenshots

<img src="Screenshots/Menu Bar.png" width="300" alt="Menu Bar">

<img src="Screenshots/Setings - General.png" width="500" alt="Settings - General">

<img src="Screenshots/Settings - Paths.png" width="500" alt="Settings - Paths">

<img src="Screenshots/Settings - Debug.png" width="500" alt="Settings - Debug">

## Installation

### Requirements
- macOS 14.0 (Sonoma) or later
- [Claude Code](https://claude.ai/claude-code) CLI installed

### Build from Source
1. Clone this repository
2. Open `Chat2MD.xcodeproj` in Xcode
3. Build and run (⌘R)

## Configuration

### Paths
| Setting | Default | Description |
|---------|---------|-------------|
| Claude Projects | `~/.claude/projects` | Where Claude Code stores session files |
| Output Directory | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vault/claude` | Where to save markdown files |

### Sync Options
| Setting | Default | Description |
|---------|---------|-------------|
| Sync Interval | 5 seconds | How often to check for new messages |
| Session Max Age | 1 hour | Only sync sessions modified within this time |

## Status Graph Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | Sync successful (new messages synced) |
| 🔴 Red | Sync failed (error occurred) |
| ⚫ Gray | Skipped (no new messages) |
| ⬜ Light Gray | No data |

## How It Works

1. Reads Claude Code session files from `~/.claude/projects`
2. Uses `sessions-index.json` to get the actual project path
3. Extracts new messages since last sync
4. Appends to daily markdown files named `YYYY-MM-DD-projectname.md`

## Output Format

Conversations are saved as daily markdown files:
```
2026-01-31-app.md
2026-01-31-chat2md.md
```

Each message is formatted as:
```markdown
**User**:
Your question here

**Claude**:
Claude's response here

| Tables | Work | Too |
|--------|------|-----|
| data   | data | data|
```

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| Sync State | `~/.chat2md/sync_state.json` | Tracks last synced line per session |
| App Settings | macOS UserDefaults | Stores user preferences |

## Troubleshooting

### Messages are missing or duplicated
1. Go to Settings → Debug
2. Click "Reset Sync State"
3. Delete existing markdown files if needed
4. Sync will restart from scratch

### Tables not rendering correctly
Ensure there's a blank line before tables in your markdown viewer. Chat2MD automatically adds this.

### Project name is wrong
The app uses the `projectPath` from Claude's `sessions-index.json`. The last folder name is used as the project name.

## Development

### Project Structure
```
Chat2MD/
├── App/
│   ├── Chat2MDApp.swift      # App entry point
│   └── AppDelegate.swift     # Menu bar setup
├── Models/
│   ├── ClaudeMessage.swift   # JSONL message parsing
│   ├── Settings.swift        # User preferences
│   ├── SyncState.swift       # Sync progress tracking
│   └── SyncHistory.swift     # Sync history entries
├── Services/
│   ├── SyncService.swift     # Main sync logic
│   ├── JSONLParser.swift     # Parse Claude session files
│   ├── MarkdownConverter.swift # Convert to markdown
│   ├── ProjectNameResolver.swift # Resolve project names
│   └── LaunchAgentManager.swift # Login item management
└── Views/
    ├── MenuBarView.swift     # Menu bar UI
    ├── SettingsView.swift    # Settings window
    └── StatusGraphView.swift # Sync status graph
```

## License

MIT License

## Acknowledgments

- Built for use with [Claude Code](https://claude.ai/claude-code) by Anthropic
- Designed for [Obsidian](https://obsidian.md) markdown workflows
