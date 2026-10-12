# Trim the Fat (Transport Fever 3 mod)

Shows which lines lose money, run more vehicles than they need, or need more. A **Line efficiency** card in every
line window compares the line's balance with its average load over the same 12 months and gives a verdict with a
suggestion of how many vehicles to remove; a button at the top left opens a sortable overview of every line, with
verdict and transport filters and a search. It also marks lines whose income has been falling
(Declining ↘), warns when another vehicle on a busy line would likely lose money, and can hide lines whose vehicles
changed in the last 12 months. On the Mod Hub as "Trim the Fat" (mod.io id in
`mod/pgrace_trim_the_fat/_metadata/mod.io_fileid.txt`).

- Mod ID: `pgrace_trim_the_fat`
- Cosmetic: yes. It doesn't affect the simulation, so achievements stay enabled.

Agent and modding notes for all mods live in `../AGENTS.md`.

## Layout

```
mod/pgrace_trim_the_fat/                        # the mod folder TF3 loads
├── mod.json, _metadata/              # modinfo.json, description.html, screenshots
├── tealdef/                          # Teal type definitions (canonical; build.py mirrors them into content/)
└── content/gui/pgrace_trim_the_fat/
    ├── metrics.tl                    # pure: load, verdict, trim, summaries, plurals (unit-tested)
    ├── line_data.tl                  # reads a line from the engine
    ├── ui.tl                         # shared text helpers
    ├── line_card.script.tl, .res.lua # the Line efficiency card in the line window
    └── overview.script.tl, .css.lua, overview_button.res.lua  # the all-lines window and its button
tools/                                # type check, tests, install, release checks
tests/                                # unit tests for pure modules
```

## Dev loop

```bash
just check      # type-check against the game's API definitions
just test       # unit tests
just verify     # check + test + release-check
just install    # symlink into TF3's staging area (just install-copy to copy)
```

Restart TF3 after code changes. The log is
`~/.local/share/Steam/userdata/*/3493540/local/crash_dump/stdout.txt`; our lines start with `[trim_the_fat]`.

## Releasing

1. Screenshots in `mod/pgrace_trim_the_fat/_metadata/`: `0.png` is the cover, `1.png`… the gallery (1920x1080, ≤8 MB).
2. For an update: `just bump` and commit.
3. `just release` (revision check + verify).
4. Upload from **Mod Hub > My Mods** in TF3.
5. Commit what the upload changed (the first one creates `_metadata/mod.io_fileid.txt`), then `just mark-uploaded`
   and push `main`.

Design notes and in-game findings: `docs/superpowers/specs/`.
