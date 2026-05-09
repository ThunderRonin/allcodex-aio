---
name: submodule-bump
description: Use when bumping one or all submodule SHAs in the allcodex-aio parent repo after work is merged to a submodule's dev branch. Invoke with a submodule name or "all".
---

# Submodule Bump

Bumps submodule refs in the parent repo to the latest `dev` HEAD. Always: submodule first, parent second.

## Rule

Confirm the submodule's `dev` is pushed to remote before bumping parent. A bump pointing at an unpushed SHA will break anyone who clones.

## Single Submodule

```bash
# 1. Ensure submodule dev is current and pushed
git -C <name> checkout dev
git -C <name> push

# 2. Pull latest dev SHA into parent
git submodule update --remote <name>

# 3. Commit
git add <name>
git commit -m "chore: bump <name> to latest dev"
git push
```

## All Submodules

```bash
git submodule update --remote
git add allcodex-core allknower allcodex-portal docs/shared
git commit -m "chore: bump all submodules to latest dev"
git push
```

## Submodule Reference

| Name | Path | Remote |
|------|------|--------|
| `allcodex-core` | `allcodex-core/` | ThunderRonin/allcodex-core |
| `allknower` | `allknower/` | ThunderRonin/allknower |
| `allcodex-portal` | `allcodex-portal/` | ThunderRonin/allcodex-portal |
| `docs/shared` | `docs/shared/` | ThunderRonin/allcodex-docs |

## Verification

`git submodule status` — no `+` prefix means all SHAs match what's checked out.
