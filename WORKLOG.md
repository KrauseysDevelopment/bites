# Bites — Worklog

## How we work
- Claude edits source in this folder (connected via Cowork) and reviews; Nick builds/runs in Xcode and tests on his iPhone.
- Claude cannot build (no Xcode/Swift in its VM) and cannot reach GitHub from the folder shell; Nick runs `git push` from Terminal.
- Secrets: USDA key lives only in `Bites/Secrets.plist` (gitignored). Never in docs, logs or commits.
- "Done" = verified in Nick's Xcode build on device.
- Full context: `Nicks_Project_Handoff.md`.

## Session log

### 2026-11-01
- Reviewed folder + handoff. Tree clean on `main` at `c9f8d91`; 3 commits, **never pushed** (no upstream, no remote refs).
- `Secrets.plist` present locally with a 40-char key, correctly gitignored, not tracked.
- Signing: Automatic, team `H3UCT56XPH`, bundle `NickKrause.Bites`, iOS 18.5 target, HealthKit + background-delivery entitlements.
- `github.com/KrauseysDevelopment/Bites` not visible to Claude's GitHub access (missing, or private and not granted).
- Symptom: app stopped launching on iPhone. Leading suspect: expired provisioning profile (Personal Team profiles last 7 days; last build ~29 Sep). Secondary: iPhone on newer iOS than installed Xcode supports.
- Repo created: `github.com/KrauseysDevelopment/bites` (lowercase, **Public**). Checked full history: USDA key appears in 0 commits. Claude's push access refused (Claude GitHub App not installed on org), so Nick pushes from Terminal.
- Next: Nick confirms repo exists / creates it, pushes; rebuilds to device from Xcode; reports Xcode version, iOS version, team type, symptom.
