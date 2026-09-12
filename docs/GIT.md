# Git conventions

## One trunk

`main` is the only long-lived branch (since 2026-09-05, W0 of
`PHASE_2_POLISH_PLAN.md`). Work happens on a short-lived wave branch —
`onyx/w<N>-<slug>`, optionally in a worktree under `.claude/worktrees/` — and
is merged back `--no-ff`, then deleted. There is no `develop`, no long-running
feature branch, and no per-track branch: those cost us a three-day-old security
fix that sat unmerged on `feature/native-migration-wave-1`.

## `[skip ci]` is retired, and so is the build

Netlify publishes `site/` as-is on every push to `main` — no build command, no
build minute. `[skip ci]` once spared build minutes on native-only work and
once withheld a security fix for three days; the static site makes both the
tag and the `[build] ignore` rule that replaced it unnecessary. The local push
guard in `.claude/settings.json` still asks for `[skip ci]` or `HELIX_DEPLOY=1`
on a bare `git push`; either satisfies it.

## The `merge=ours` driver is machine-local — run this once per clone

```sh
git config merge.ours.driver true
```

`.gitattributes` marks `graphify-out/**` and `native/__screenshots__/**` as
`merge=ours`, so a conflict in a generated file resolves to the target branch
instead of stopping the merge. **Git ships no built-in driver by that name** —
without the config line above the attribute is inert and the conflicts come
back. The setting lives in `.git/config`, which is not tracked, so every fresh
clone has to run it.

After a merge that touched either path, regenerate rather than trust the
result: `graphify update .` for the graph, `scripts/native-shot.sh` for the
screenshots.
