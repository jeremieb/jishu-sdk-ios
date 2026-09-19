# Averagium Plan Structure — Agent Guide

This document tells an LLM agent how to turn a plan (a PRD, a roadmap, a stream-of-consciousness list of things to build) into the file layout that **Averagium** reads. Averagium treats a repository's Markdown files as the single source of truth — there is no database. Follow this spec exactly so the app can parse what you write.

## 1. Folder layout

```
<repo root>/
├── README.md                 ← project header + feature index
└── averagium/
    ├── feature-slug-01.md     ← one file per feature, at the top level of averagium/
    ├── feature-slug-02.md
    ├── archive/               ← archived (done/shelved) feature files land here
    │   └── feature-slug-03.md
    ├── doc/                   ← freeform documentation attached to features/tasks
    │   └── SOME-DOC.md
    └── logs/                  ← optional dated logs, one file per day
        └── 2026-09-05.md
```

Rules:
- `averagium/` is created at the repo root, sibling to `README.md`.
- Every feature is its own `.md` file directly under `averagium/` (not nested further).
- Archiving a feature **moves its file** to `averagium/archive/` and removes it from the active list in `README.md`. It does not change the file's content.
- Documentation files referenced from a feature or task frontmatter live under `averagium/doc/`.
- Feature/task file names should be short kebab-case slugs (e.g. `calendar-sync.md`, `autoupdate.md`). The slug does not need to match the feature's display `name`.

## 2. `README.md` — project header + feature index

Structure, top to bottom:

1. YAML-style frontmatter (each key on its own line, blank line between key groups is optional):
   ```
   ---
   name: Project title
   category: Category        (optional)
   tags: Tag, Tag             (optional, comma-separated)
   color: #RRGGBB             (optional hex)
   ---
   ```
2. The **feature index**, immediately after the frontmatter — one line per feature:
   ```
   [Int] Feature name | averagium/feature-slug.md
   ```
   - `[Int]` is the feature's completion percentage (0–100). This is a cache of the value stored in the feature file's own `progress` field — keep them in sync whenever you edit either.
   - The path is relative to the repo root and must point at a real file under `averagium/`.
   - One feature per line, in whatever order matters to the project (priority, chronology, etc.).
3. Everything below the index is free-form Markdown body content (project description, longer notes, roadmap, etc.). Averagium preserves this content verbatim when it rewrites the index — do not rely on line position beyond "index comes right after frontmatter."

Minimal example:

```markdown
---
name: My Project
tags: swift, ios
color: #4373FA
---

[33] Autoupdate | averagium/autoupdate.md
[0] Calendar Sync | averagium/calendar-sync.md

# My Project

Free-text description, links, notes...
```

## 3. Feature files (`averagium/<slug>.md`)

Structure:

1. Frontmatter:
   ```
   ---
   name: Feature name
   start_date: YYYY-MM-DD    (optional, blank allowed)
   due_date: YYYY-MM-DD      (optional, blank allowed)
   progress: Int              (0-100, overall feature completion)
   priority: none|low|medium|high|urgent
   documentation: averagium/doc/SOME-DOC.md   (optional)
   ---
   ```
2. The **task index** — one line per task, immediately after frontmatter, same bracket format as the README:
   ```
   [Int] Task title
   ```
   (No path here — tasks live in the same file as `##` sections below, not separate files.)
3. One `##` section per task, in the same order as the task index, each with its own mini-frontmatter-like block (plain `key: value` lines, no `---` fences) followed by free-text task details:
   ```
   ## Task title
   due_date: YYYY-MM-DD
   priority: none|low|medium|high|urgent
   Free-text description of the task. Can include sub-bullets, decisions,
   links to documentation, acceptance criteria, etc.
   ```

Full example (trimmed):

```markdown
---
name: Calendar Sync
due_date:
progress: 0
priority: medium
start_date:
---
[0] .ics file

## .ics file
due_date: 2026-09-08
priority: high
Generating a calendar file from the features/tasks with start or due date.
If we only have a due date, display it for that day. All elements are
full-day only, no time included.
```

Notes:
- `progress` on the feature is normally the average of its tasks' completion (Averagium recalculates and writes this back), but you can set an initial value when authoring by hand.
- A task's own `[Int]` in the task index is its individual completion percentage, independent of the feature's overall `progress`.
- Priority is one of exactly five values: `none`, `low`, `medium`, `high`, `urgent`. Unknown/malformed values are treated as `none` — don't invent new levels.
- Dates are `YYYY-MM-DD` or blank. No times.
- `documentation:` (feature-level) points at one attached doc file under `averagium/doc/`.

## 4. Documentation files (`averagium/doc/*.md`)

Plain Markdown, no required frontmatter. Used for anything too long to live inline in a task description — design decisions, research, external links, technical recommendations. Reference them from a feature's `documentation:` frontmatter field. Keep filenames descriptive/short (e.g. `OTA-02.md`).

## 5. Turning a plan into this structure — the actual workflow

Given a plan (PRD, roadmap, bullet list, meeting notes, etc.), an agent should:

1. **Identify the project.** If `README.md` doesn't exist yet at the repo root, create it with frontmatter (`name`, optionally `category`/`tags`/`color`) and an empty feature index.
2. **Group the plan into features.** A feature is a cohesive chunk of work worth tracking as one unit (roughly: something you'd put on a roadmap, not a single commit). Give each one a short display `name` and a kebab-case file slug.
3. **For each feature:**
   - Create `averagium/<slug>.md` with frontmatter (`name`, `start_date`, `due_date`, `progress: 0`, `priority`).
   - Break the feature's scope into tasks — concrete, independently completable units of work (roughly: a PR-sized or session-sized chunk).
   - Write the task index (`[0] Task title` per task, in execution order where order matters).
   - Write one `##` section per task with `due_date`, `priority`, and a description detailed enough that an agent picking up the task later doesn't need the original plan — include acceptance criteria, decisions already made, file/command specifics, and anything a future session would otherwise have to rediscover.
4. **Add the feature to `README.md`**: append `[0] Feature name | averagium/<slug>.md` to the index.
5. **Cross-link documentation** where a task needs longer-form background: write it to `averagium/doc/<NAME>.md` and set `documentation:` on the feature.
6. **Keep progress numbers honest.** As tasks complete, update the task's `[Int]` in its feature file's task index; recompute and update the feature's `progress:` and the README's `[Int]` for that feature to match (average of task progress, or an explicit judgment call if tasks are unequal in size).
7. **Archive, don't delete, finished features.** Move the feature file to `averagium/archive/` and remove its line from the README index once a feature is fully done and no longer active.

## 6. Things to preserve when editing existing files

- Never reorder or drop frontmatter keys you don't understand — Averagium supports optional/unknown metadata fields; leave them as-is.
- Never let a `documentation:` or index path escape the project directory (no `../`, no absolute paths) — treat this as a hard validation rule, not a style preference.
- Preserve existing free-text body content in README and feature files; only edit the index/frontmatter/task sections you're actually changing.
- Task order in the task index must match the order of the `##` sections below it — Averagium correlates them positionally as well as by title.
