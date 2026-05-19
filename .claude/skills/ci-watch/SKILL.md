---
name: ci-watch
description: Poll GitHub Actions CI status for allcodex-aio, allknower, and allcodex-portal until all jobs complete or fail. Shows failed job logs.
---

# CI Watch

Monitor CI runs across all 3 repos on the current branch.

## Steps

1. Detect current branch:
   ```bash
   git branch --show-current
   ```

2. List latest run for each repo:
   ```bash
   gh run list --repo ThunderRonin/allcodex-aio --branch <branch> --limit 1 --json databaseId,status,conclusion,name,createdAt
   gh run list --repo ThunderRonin/allknower --branch <branch> --limit 1 --json databaseId,status,conclusion,name,createdAt
   gh run list --repo ThunderRonin/allcodex-portal --branch <branch> --limit 1 --json databaseId,status,conclusion,name,createdAt
   ```

3. If any run has `status: "in_progress"`, wait 30s and re-check (max 10 iterations)

4. For each completed run, report status:
   - ✅ passed
   - ❌ failed — fetch logs: `gh run view <id> --repo <repo> --log-failed | tail -40`
   - ⏭️ skipped

5. Summary table at end:
   ```
   | Repo | Job | Status | Duration |
   ```

## Notes

- AllKnower CI needs Postgres — failures in `migrate deploy` step usually mean schema drift
- Portal CI runs `tsc --noEmit && vitest run` — no Playwright in CI (separate workflow)
- Core CI only typechecks (no test runner in CI yet)
