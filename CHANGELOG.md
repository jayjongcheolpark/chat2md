# Changelog

## [1.1.3] - 2026-02-10

### Fixed
- Codex provider no longer skips active sessions due to stale leaf-folder (`YYYY/MM/DD`) modification timestamps
- Message date filtering now uses sync `Session Max Age` cutoff instead of always using today's midnight
- Claude project name resolution now falls back to `cwd` from session JSONL when `sessions-index.json` is missing
- Claude folder-name fallback preserves common `*-YYYYMMDD` project suffixes (e.g. `projects-20260209`)

## [1.1.2] - 2026-02-05

### Fixed
- Remove lossy folder name parsing in Claude provider; rely on `sessions-index.json` as sole source of truth for project names
- Strip `<proposed_plan>` tags from Claude and Codex conversation output

### Removed
- Unused `ProjectNameResolver.swift`

## [1.1.1] - 2026-02-04

### Fixed
- Claude provider folder name parsing for hyphenated project names (e.g., `office-20260202`)

## [1.1.0] - 2026-02-01

### Added
- **Multi-provider support**: Gemini CLI and Codex CLI alongside Claude Code
- **YAML frontmatter**: Metadata in markdown files (date, provider, project, session, cwd)
- **Session-based files**: Each session gets its own file with session ID in filename
- **Menu bar provider toggles**: Enable/disable each provider without opening Settings
- **Smart sync optimization**:
  - Cold start: fetches all of today's conversations
  - Warm sync: uses cutoff date for efficiency
  - Leaf folder optimization for deep directory structures (Codex)

### Changed
- Filename format now includes session ID: `YYYY-MM-DD-provider-project-sessionid.md`
- Settings: Provider toggles moved to menu bar, Paths section shows only path configuration
- Folder scanning skips unchanged folders based on modification date

### Fixed
- Codex system messages (permissions, AGENTS.md, environment) now filtered out
- Gemini new session format (`chats/*.json`) now supported
- Parent folder modification date issue for nested structures (Codex YYYY/MM/DD)

## [1.0.0] - 2026-01-31

### Added
- Initial release
- Claude Code conversation sync to Markdown
- Incremental sync (only new messages)
- Configurable sync interval and session max age
- Launch at login option
- Status graph showing sync history
- Debug view with state inspection and reset
