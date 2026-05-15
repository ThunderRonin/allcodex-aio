---
name: dep-audit
description: Audit Dependabot alerts and open PRs across allcodex-aio, allknower, and allcodex-portal. Reports severity breakdown and recommends merge order.
---

# Dependency Security Audit

Check all 3 repos for Dependabot alerts and open dependency PRs.

## Steps

1. Check Dependabot alerts for each repo:
   ```bash
   gh api repos/ThunderRonin/allknower/dependabot/alerts --jq '[.[] | select(.state=="open")] | group_by(.security_advisory.severity) | map({severity: .[0].security_advisory.severity, count: length, packages: [.[].dependency.package.name] | unique})'
   gh api repos/ThunderRonin/allcodex-portal/dependabot/alerts --jq '[.[] | select(.state=="open")] | group_by(.security_advisory.severity) | map({severity: .[0].security_advisory.severity, count: length, packages: [.[].dependency.package.name] | unique})'
   gh api repos/ThunderRonin/allcodex-core/dependabot/alerts --jq '[.[] | select(.state=="open")] | group_by(.security_advisory.severity) | map({severity: .[0].security_advisory.severity, count: length, packages: [.[].dependency.package.name] | unique})'
   ```

2. List open Dependabot PRs:
   ```bash
   gh pr list --repo ThunderRonin/<repo> --author "app/dependabot" --state open --json number,title,mergeable
   ```

3. For each open PR, check CI status and mergeability

4. Recommend merge order:
   - Critical/High severity first
   - Direct dependencies before transitive
   - Security packages (next, dompurify, helmet) before dev deps
   - Flag any that need conflict resolution

## Output

Summary table:
```
| Repo | High | Medium | Low | Open PRs | Action |
```

Then per-repo details with specific merge commands.

## Notes

- Portal Dependabot PRs target `main` by default — retarget to `dev` with `gh pr edit --base dev` before merging
- Core has Dependabot disabled — skip alerts check (403)
- After merging Dependabot PRs that touch lockfiles, remaining PRs often conflict — merge highest-priority first, then update branches
