# Third-Party Attribution

The agent/skill/rule framework under `.claude/` (agents, skills, rules, and the
shared docs in `.claude/docs/`) is adapted from:

**Claude Code Game Studios** — https://github.com/donchitos/claude-code-game-studios
Copyright (c) 2026 Donchitos — MIT License.

## What was imported and adapted

- **Agents**: the Godot specialists plus general game-dev disciplines. Excluded:
  all Unity/Unreal specialists, the GDScript-vs-C# C# specialist,
  network/narrative/world-building/community roles (not applicable to a
  single-player GDScript math puzzle).
- **Rules**: kept the gameplay/engine/ui/data/test/design/shader/prototype rules,
  with their `paths:` scopes adapted to this repo's layout (`core/`, `scenes/`,
  `autoloads/`, `data/`, `tests/`, `docs/`, `tools/`). Dropped ai/narrative/network.
- **Skills**: a focused subset covering design, architecture, planning, QA, UX,
  and release. Engine setup, hooks-management, and Unity/Unreal-specific skills
  were omitted.
- **Docs**: shared reference files and the document templates the skills emit;
  `technical-preferences.md` and `directory-structure.md` were rewritten for this
  project.
- **NOT imported**: the upstream executable hooks (`.claude/hooks/`) and their
  `settings.json` hook wiring, the statusline script, and `agent-memory/`. This
  repo's `.claude/settings.json` contains only permission defaults — no hooks.

## MIT License (upstream)

```
MIT License

Copyright (c) 2026 Donchitos

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
