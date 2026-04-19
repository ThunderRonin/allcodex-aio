# Gitflow Design — AllCodex-AIO Monorepo

**Date:** 2026-04-19
**Status:** Implemented

## Context

The workspace had an ad-hoc gitflow: `main` served as an informal baseline, sprint branches like `quality-hardening` existed across multiple submodules, and `.gitmodules` declared `branch = main` while two submodules were actually checked out on divergent branches. This caused `+` drift in `git submodule status` and unclear promotion paths.

**Goal:** Establish a clean, minimal flow for a solo developer with no active deployment pipeline.

---

## Design: Trunk-Lite

### Permanent Branches

Every repo — parent + all 4 submodules — has exactly two permanent branches:

| Branch | Purpose |
|--------|---------|
| `main` | Stable checkpoint. No direct commits. Only receives merges from `dev`. |
| `dev` | Daily integration. All active work lands here. |

### Short-Lived Branches

Cut from `dev`, merged back into `dev`, then deleted:

| Prefix | Use case |
|--------|---------|
| `feat/<name>` | New features |
| `fix/<name>` | Bug fixes |
| `chore/<name>` | Maintenance, tooling, config |

### `.gitmodules`

All submodules declare `branch = dev`. The parent always tracks the `dev` HEAD of each submodule.

---

## Submodule Coordination Rule

**Submodule first, parent second. Always.**

```bash
# 1. Finish work inside a submodule, merge branch → dev
git -C allknower checkout dev
git -C allknower merge feat/my-feature
git -C allknower branch -d feat/my-feature

# 2. Bump parent ref
git submodule update --remote allknower
git add allknower
git commit -m "chore: bump allknower to latest dev"
```

**Checkpointing to `main`:**

```bash
# In each touched submodule
git -C allknower checkout main && git -C allknower merge dev && git -C allknower push

# In parent
git submodule update --remote
git add .
git commit -m "chore: bump submodule refs to main"
git checkout main && git merge dev && git push
```

---

## Day-to-Day Workflow

```bash
# Start new work (inside relevant submodule)
git checkout dev && git pull
git checkout -b feat/my-thing

# ... commit work ...

# Merge back
git checkout dev
git merge feat/my-thing
git branch -d feat/my-thing
git push

# Bump parent
cd ../..
git submodule update --remote allknower
git add allknower
git commit -m "chore: bump allknower to latest dev"
git push

# Checkpoint to main (when dev is stable)
# See submodule coordination rule above
```

---

## What Was Migrated

- `dev` branch created from `main` in: parent, allcodex-portal, allknower, allcodex-core, docs/shared
- `quality-hardening` merged into `dev` in: allcodex-portal, allknower, parent
- `.gitmodules` updated: all `branch = main` → `branch = dev`
- Parent submodule refs bumped to new `dev` SHAs
- `quality-hardening` to be deleted after confirming remote push of `dev`
