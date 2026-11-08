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
- Nick pushed `10a3f61` to `KrauseysDevelopment/bites`; installed Claude GitHub App on the org (Claude can push from cloud sessions now).

### 2026-11-07
- Simulator build OK on iPhone 18 Pro Max sim. Device install still failing on Nick's phone (error not yet captured).
- Distribution decision: **free Personal Team for now** (Nick + wife, rebuild every 7 days, max 3 devices). Revisit $99 program/TestFlight when Mom joins. Never delete an expired install: data lives in the app container.
- Built on branch `feature/points-achievements` (unverified until Nick builds):
  - **Tracking modes**: Bites Points (WW-style) vs Bites Macros, toggle in Settings → Your Plan. Points = kcal×0.0305 + satfat×0.275 + sugar×0.12 − protein×0.098 (public SmartPoints formula; WW's current one is unpublished). Missing satfat/sugar estimated (35% of fat / 25% of carbs).
  - ZeroPoint foods (WW list) on USDA whole foods only, name-matched with exclusions; toggleable. Per-meal ZeroPoint toggle + points override in Edit Meal.
  - Daily budget + 28 weekly points, overruns draw from weekly, up to 4 unused/day roll over.
  - **Calorie deficit calculator** (Mifflin-St Jeor × activity, goal pace 2 lb loss → 1 lb gain, 1200/1500 kcal floor) → calories, macros (0.8 g/lb protein, 30% fat), points budget. Full-screen on first launch; Settings → Your Plan any time.
  - Nutrition now carries saturated fat (USDA 1258, OFF `saturated-fat_100g`); Meal stores sugar/satFat/fiber/ZeroPoint/override (tolerant decode).
  - **Scanned** list: every successful barcode lookup saved; search idle view is now Recent | Favorites | Scanned. Star toggle in the serving picker.
  - **One-tap weigh-in** card on Today; weigh-in reminder now Daily or Weekly.
  - **Achievements**: 36 badges (logging/on-budget/workout/weigh-in/water streaks, meal/workout/scan counts, lb lost), streak strip on Today, summary card on Fitness, in-app banner + notification. First run unlocks history silently.
  - **Reminders**: evening log nudge and streak-at-risk (next 7 days scheduled one-off, rebuilt on every diary change so logged days skip), achievement alerts.
  - BitesApp split into BitesApp + RootView + DerivedStateRefresher to keep type-checking fast.
- Verified here: brace balance on all files; ZeroPoint matcher run against 40+ real USDA names. **Not compiled** — needs Nick's Xcode build.
- Next: Nick builds sim + device, reports errors; capture device-install error; merge branch to main once green.
