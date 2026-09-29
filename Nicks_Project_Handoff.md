# Bites: Project Handoff and Change Log

**Project:** Bites, an iOS food and fitness tracker
**Owner:** Nicholas Krause
**Repository:** https://github.com/KrauseysDevelopment/Bites (private)
**Local path:** `~/Documents/Nicks Development Folder/Bites`
**Document last updated:** 29 September 2026

---

## 1. What Bites Is

A SwiftUI iOS application for tracking food intake, water, workouts and body
weight, with Apple Health integration. Originally built about a year ago as a
food diary, then substantially expanded. The immediate audience is family use;
it is not on the App Store.

**Current version:** 1.0 (`MARKETING_VERSION`)
**Bundle identifier:** `NickKrause.Bites`
**Deployment target:** iOS 18.5
**Swift language mode:** 5
**Device family:** iPhone and iPad (1,2)
**Dependencies:** none. No SPM packages, no CocoaPods, no Carthage.

### Feature summary

| Area | What it does |
|---|---|
| Today | Calorie ring against a daily goal, protein/carb/fat progress, water tracking, seven-day calorie sparkline |
| Diary | Meals grouped by day; tap to edit name, category, macros or date; swipe to delete |
| Food search | USDA FoodData Central, split into Whole Foods and Branded sections; recents and favourites |
| Barcode scanning | VisionKit scanner; Open Food Facts first, USDA branded as fallback |
| Saved Meals | Reusable multi-item meal templates |
| Fitness | Workout streaks, manual logging across 16 activity types, Apple Health workout import, Health metric tiles |
| Weight | Trend chart with 7D/1M/1Y/All ranges, seven-day moving average, optional weekly weigh-in reminder |
| Settings | Goals for calories, macros, water, exercise minutes and active calories; dark mode; distance units; USDA key entry; weigh-in reminder configuration |

---

## 2. Access and Credentials

### GitHub

- **Account:** KrauseysDevelopment (https://github.com/KrauseysDevelopment)
- **Repository:** `Bites`, private
- **Remote already configured** in the local clone as `origin`:
  `https://github.com/KrauseysDevelopment/Bites.git`
- **Commit identity** configured locally for this repo:
  - `user.name` = `Nicholas Krause`
  - `user.email` = `KrauseysDevelopment@users.noreply.github.com`
  - The noreply address links commits to the GitHub account without exposing a
    personal email address.

**Status: the first push has not been completed yet.** Two commits exist
locally. See section 9 for the exact commands.

### USDA FoodData Central API key

Food search will not function without this. It is free and issued instantly.

- **Sign-up:** https://fdc.nal.usda.gov/api-key-signup/
- **Rate limit:** 1,000 requests per hour per IP for a registered key
- **Where the app reads it from**, in order:
  1. `Bites/Secrets.plist`, key `USDA_API_KEY`. This file is **gitignored** and
     is not in the repository.
  2. Failing that, a key pasted into the app at Settings → Food Database,
     stored in `UserDefaults`.
- **Template:** `Bites/Secrets.example.plist` is committed. Copy it to
  `Bites/Secrets.plist` and paste a key in.

**The live key value is deliberately not recorded in this document.** This file
sits inside a git repository, and a key committed to source control is a key
that leaks. The working key is in `Bites/Secrets.plist` on the development
machine. If that machine is unavailable, issue a new key from the link above;
it takes under a minute and costs nothing. Note that USDA deactivates keys it
finds published, and GitHub secret-scans public repositories.

### Open Food Facts

No account, no key, no registration. The app identifies itself with a
User-Agent header, which Open Food Facts requires. Used only for barcode
lookups.

### Apple Health

Read-only. The app requests `stepCount`, `activeEnergyBurned`,
`basalEnergyBurned`, `appleExerciseTime`, `distanceWalkingRunning`, `bodyMass`
and `HKWorkout`. It never writes back to Health. Usage strings are set in build
settings as `INFOPLIST_KEY_NSHealthShareUsageDescription` and
`INFOPLIST_KEY_NSCameraUsageDescription`. HealthKit entitlements are in
`Bites/Bites.entitlements`.

---

## 3. Getting Set Up

1. Clone the repository, or open the existing local copy.
2. Open `Bites.xcodeproj` in Xcode 16 or later.
3. Create the secrets file:
   ```sh
   cp Bites/Secrets.example.plist Bites/Secrets.plist
   ```
   Replace `PASTE_YOUR_USDA_API_KEY_HERE` with a real key.
4. Set a development team in Signing and Capabilities if building to a device.
5. Build and run.

**Build to a physical device where possible.** Two features do not work in the
Simulator: barcode scanning needs a real camera, and Apple Health returns no
data unless the Simulator has been seeded manually.

The project uses **Xcode 16 file-system synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`, `objectVersion = 77`). Any `.swift` file
dropped into the `Bites/` folder is compiled automatically. There is no need to
add files to the target manually, and no need to edit `project.pbxproj` when
adding source files.

---

## 4. Architecture

Plain SwiftUI with `ObservableObject` singletons. No architectural framework,
no third-party dependencies. Persistence is JSON encoded into `UserDefaults`.

### Source map

| File | Lines | Role |
|---|---|---|
| `BitesApp.swift` | 65 | App entry, TabView, environment objects, toast overlay |
| **Models** | | |
| `DayEntry.swift` | 137 | `Meal`, `MealCategory`, `DayEntry` |
| `Workout.swift` | 200 | `WorkoutType` (16 cases), `WorkoutSource`, `Workout`, `DayActivity` |
| `FoodItem.swift` | 207 | Normalized food model, `Nutrition`, `FoodSource`, barcode helpers, lenient decoders |
| `Date+Extensions.swift` | 12 | Calendar helpers |
| `Item.swift` | 2 | Empty. Vestigial SwiftData template file, safe to delete |
| **Stores** | | |
| `DiaryStore.swift` | 365 | Meals, days, water, weight, goals, saved meals, persistence |
| `WorkoutStore.swift` | 198 | Workouts, fitness goals, streak calculation, Health merge |
| `RecentFoodsStore.swift` | 131 | Recently logged and favourited foods |
| **Services** | | |
| `HealthManager.swift` | 265 | HealthKit authorization, today's metrics, 180-day history, `HKWorkout` import, weight sync |
| `USDAFoodService.swift` | 358 | FoodData Central search and barcode lookup |
| `OpenFoodFactsService.swift` | 190 | Barcode product lookup |
| `FoodSearchService.swift` | 169 | Coordinates the two food sources, debounce, ranking |
| `WeighInReminder.swift` | 173 | Weekly local notification, in-app due state |
| `Secrets.swift` | 58 | API key resolution |
| **Views** | | |
| `ContentView.swift` | 395 | Today tab, calorie ring, macro cards, water, weekly sparkline |
| `FoodDiaryView.swift` | 219 | Diary tab |
| `EditMealView.swift` | 168 | Edit a logged meal |
| `AddMealView.swift` | 232 | Log Meal sheet, Search and Scan entry points |
| `FoodSearchView.swift` | 340 | Food search, recents, favourites |
| `ServingPickerView.swift` | 287 | Portion sizing and macro scaling |
| `BarcodeScannerView.swift` | 220 | VisionKit scanner and permission states |
| `SavedMealsView.swift` | 282 | Saved meal templates |
| `CreateSavedMealView.swift` | 97 | Build a saved meal |
| `FitnessView.swift` | 920 | Fitness tab, streak card, goal rings, metrics, weight card, condensed log, sparkline |
| `WorkoutHistoryView.swift` | 121 | Full workout history with filters |
| `LogWorkoutView.swift` | 266 | Log or edit a workout |
| `WeightView.swift` | 432 | Weight chart, ranges, stats, history |
| `SettingsView.swift` | 299 | All settings |

Roughly 6,800 lines of Swift across 29 files.

### Data flow notes

- All nutrition is normalized to **per 100 g** at the service boundary. Scaling
  to a portion happens in exactly one place, `Nutrition.scaled(toGrams:)`.
- `DiaryStore.today` is **derived** from `days`, not stored. An earlier stored
  copy drifted out of sync.
- Streak rule: a day counts when workout minutes meet the minutes goal **or**
  active calories meet the calorie goal. Today not yet meeting the goal does
  not break the streak; counting starts from yesterday in that case.
- Imported Health workouts are deduplicated by `healthKitID`, and a manual
  entry of the same type within 20 minutes suppresses the import.

---

## 5. Change Log

All entries below were completed in the September 2026 development block.

### 5.1 Data-layer corrections

These were pre-existing defects found while reading the project, fixed before
any new feature work.

- **Codable identity loss.** `Meal`, `DayEntry`, `SavedMeal`, `SavedMealItem`
  and `WeightEntry` declared `let id = UUID()`. Swift encodes such a property
  but never decodes it, so every app launch minted fresh identifiers. Deleting
  a meal logged before the last relaunch removed the wrong record. All models
  now have explicit tolerant `init(from:)` implementations that also survive
  data written by older builds.
- **Goals did not propagate.** Goal values used `@AppStorage` inside
  `DiaryStore`. `@AppStorage` is a `DynamicProperty` intended for `View` types;
  inside an `ObservableObject` it reads and writes `UserDefaults` but never
  fires `objectWillChange`. Editing a goal in Settings left the Today tab
  stale. Now `@Published` with a `UserDefaults` write in `didSet`.
- **Serving sizes were fiction.** `servingGrams` was never populated from the
  food database, so every "1 serving" silently resolved to 100 g.
- **Duplicate day rows.** Same-day `DayEntry` records could accumulate and
  render as repeated diary sections. They are now folded on load.
- **`today` drift.** Changed from a stored copy to a derived property.
- **Search hammering.** Food search fired one network request per keystroke
  with no User-Agent, which Open Food Facts rate-limits. Added a 350 ms
  debounce, a User-Agent, and real error states.

### 5.2 Workout tracking (new)

- `Workout` and `WorkoutType` models covering 16 activity types with SF Symbol
  icons, colors and MET values for calorie estimation.
- `WorkoutStore` with persistence, goal evaluation and streak calculation
  (current and longest).
- `HealthManager` extended to import `HKWorkout` sessions over a 180-day
  window, map Apple's activity types onto the app's, and merge without
  duplication.
- Fitness tab rebuilt: streak card with week dots and personal best, twin goal
  rings for minutes and calories, seven-day summary tiles, Health metric grid,
  weight card, and workout log.
- `LogWorkoutView` for manual entry, with calories auto-estimated from MET and
  logged body weight, and the estimate stopping once the user types a value.
- Exercise minutes and active calorie goals added to Settings, plus a toggle
  for the Health import.

### 5.3 Food database replacement

- **Replaced Open Food Facts text search with USDA FoodData Central.** Open
  Food Facts is a barcode database of packaged goods and returned nothing
  usable for generic ingredients. The reported symptom was that "boneless
  skinless chicken breast" could not be found.
- Whole foods and branded products are queried **separately and concurrently**,
  then shown as distinct sections. A single blended query lets branded volume
  bury the ingredient: USDA holds 4,848 branded matches for "banana" against 3
  Foundation entries.
- Calorie extraction falls through nutrient IDs 1008, then 2048, then 2047,
  then kilojoules. Foundation foods stopped reporting plain Energy in late 2020
  in favour of the two Atwater variants.
- Separate wire types for `/foods/search` and `/food/{fdcId}`. The published
  USDA OpenAPI specification documents only the nested detail shape and is
  wrong about search, which returns a flat shape. This is a known upstream bug
  (USDA/USDA-APIs issue 102).
- `servingSizeUnit` is decoded as a UN/CEFACT code. USDA returns `GRM` and
  `MLT`, never `g` or `ml`. This was found by testing against the live API and
  would otherwise have discarded every branded serving size.
- `gtinUpc` and `servingSize` decode leniently, because one mistyped field in
  one product would otherwise throw and void the entire search response.
- `Survey (FNDDS)` has a documented fallback: its parentheses cause a 400 over
  GET, so whole-food search retries with Foundation and SR Legacy only.

### 5.4 Barcode scanning (new)

- `BarcodeScannerView` built on VisionKit `DataScannerViewController`, with
  camera permission states and a clear unsupported state for the Simulator.
- Lookup tries Open Food Facts first, then USDA branded. USDA has no barcode
  endpoint, so that fallback puts the number through full-text search and
  verifies `gtinUpc` client-side.
- UPC-A and EAN-13 are normalized against each other, since the same product is
  12 digits in one source and 13 in the other.
- Reachable from the Log Meal screen as a primary action, and from the search
  screen toolbar.

### 5.5 Usability work

- **Recents and favourites** on the food search empty state, remembering the
  gram weight used last time.
- **Serving picker rewritten** around the real declared serving, with per-unit
  quick amounts (servings 0.5–3, grams 25–250, oz 1–8, cups 0.25–2, tbsp
  0.5–6) and amount conversion on unit change so the quantity stays fixed.
- **Diary editing added.** Logged meals were previously delete-only. Now name,
  category, macros and date are editable, including moving a meal to another
  day, with a quiet warning when macros do not reconcile with stated calories.
- **Workout log condensed.** It rendered every workout from the last 60 inline
  and made the Fitness page several screens tall. Now three recent entries with
  an expand toggle, plus a dedicated `WorkoutHistoryView` for the full history.
- **Metric card alignment fixed.** `.overlay` centres content that is narrower
  than its container. Three of the four Fitness metric cards contained a
  `GeometryReader` for their progress bar, which stretched them to full width
  by accident; Distance had no bar and so appeared centred. Alignment is now
  explicit, and the bar row is always laid out so the four cards share a
  vertical rhythm.
- **Sheet presentation race fixed.** The scanner dismissed itself and handed
  back the barcode in the same state transaction, so the serving-picker sheet
  was requested mid-dismissal and could be silently dropped by UIKit. The
  lookup now runs from the sheet's `onDismiss`.

### 5.6 Weight tracking (new)

- `WeightView` with a Swift Charts line chart, 7D/1M/1Y/All range filter,
  seven-day moving average, scrub-to-read selection, Start/Current/Change
  stats, and a history list.
- The chart is single-hue by design. A second categorical colour would have to
  pass colourblind separation and lightness-band checks in both light and dark
  mode, and system orange sits outside the usable band against a dark surface.
- Y-axis is deliberately not zero-based; a zero baseline flattens real weight
  movement.
- Compact sparkline added to the Fitness weight card, which now navigates to
  the full screen.

### 5.7 Weigh-in reminder (new)

- `WeighInReminder` schedules a repeating weekly local notification on a chosen
  weekday and time via `UNCalendarNotificationTrigger`.
- An in-app card appears at the top of the Fitness tab when a weigh-in is due,
  dismissible for the day.
- Settings section for enable, day, time, and a permission-denied state with a
  shortcut to iOS Settings.
- Registers at launch, because property observers do not fire during `init` and
  a reminder enabled in a previous session would otherwise never re-register.

### 5.8 App icon

- Source artwork was a 1024 px JPEG with the icon inset inside white padding.
  iOS requires full-bleed square artwork and applies its own corner mask, so
  the supplied file would have rendered as a small squircle inside a white one.
- Cropped to the artwork and extended the gradient into the corners by sampling
  the nearest real pixels, then exported 1024×1024 PNG with no alpha.
- Generated the dark and tinted variants iOS 18 expects. The asset catalog
  already declared the slots.
- Original artwork preserved at `Design/Bites_app_logo_iOS.jpg`.

### 5.9 Repository setup

- Proper Xcode `.gitignore` covering build output, per-user state, SPM,
  CocoaPods and macOS noise, with `Bites/Secrets.plist` at the top.
- `Bites.xcodeproj/xcuserdata/...xcschememanagement.plist` untracked; it was in
  the initial commit and is per-user window state.
- `README.md` written covering features, setup and architecture.
- All work committed as `cef42f0`. The remote is configured.

---

## 6. Known Issues and Limitations

| Item | Notes |
|---|---|
| **Not yet pushed** | Two commits exist locally. Section 9 has the commands. |
| **Persistence is UserDefaults JSON** | Fine at family scale. It loads everything into memory and has no migration story. SwiftData is the natural next step. |
| **No tests** | `BitesTests` and `BitesUITests` are the untouched Xcode templates. |
| **No sync** | Data is local to one device. Nothing shared between family members. |
| **Health is read-only** | Workouts logged in Bites do not appear in Apple Health. |
| **Volume conversions are approximate** | Cups and tablespoons assume water-like density. |
| **Simulator gaps** | Barcode scanning and Health data do not work there. |
| **`Item.swift` is vestigial** | Empty file left from the SwiftData template. |
| **USDA rate limit** | 1,000 requests per hour per IP. Each search costs two requests. Ample for personal use, worth remembering during heavy testing. |

---

## 7. Future Goals

Ordered roughly by value against effort. None of these are started.

**Near term**
1. Complete the first push and confirm the repository contents.
2. Test barcode scanning on physical hardware across a range of real packages.
3. Delete `Item.swift`.
4. Add unit tests for the parts where correctness is not visually obvious:
   streak calculation, nutrient extraction and scaling, barcode normalization,
   and the Codable migration paths.

**Medium term**
5. Migrate persistence from `UserDefaults` JSON to SwiftData, with a one-time
   import from the existing format.
6. TestFlight distribution so family members can install without Xcode.
7. iCloud sync, or at minimum an export and import of the diary.
8. Write workouts back to Apple Health so Bites is a first-class source.

**Longer term**
9. Home Screen and Lock Screen widgets for calories remaining and streak.
10. Apple Watch companion for logging water and workouts.
11. Accessibility pass: Dynamic Type at larger sizes, VoiceOver labels on the
    charts and rings.
12. Meal photos.
13. Recipe builder that computes per-serving macros from ingredients.

---

## 8. How This Project Is Worked On

The project is developed conversationally with Claude in Cowork, with the
project folder connected to the session.

### The division of labour

- **Claude** reads and edits source files directly in the project folder,
  researches API contracts, and runs verification passes.
- **Nicholas** builds and runs in Xcode, tests on a physical iPhone, and
  reports back with specific feedback.
- Claude cannot build the project. The shell it runs in is an isolated Linux
  VM with the project folder mounted; it has no Xcode, no Swift compiler and no
  Simulator. Every compile error costs a round trip, so correctness is verified
  by review rather than by compilation.

### Verification practice

Because there is no compiler in the loop, each batch of changes is reviewed by
a separate agent instructed to hunt for compile errors specifically: undefined
symbols, argument-label mismatches, Codable synthesis problems, SwiftUI
type-checker traps, and API signatures checked against real documentation
rather than assumed. This has repeatedly caught real defects before a build,
including a file that was never written to disk because a failed `rm`
short-circuited a shell chain, and a view property deleted by a scripted edit
that left its call site intact.

Brace and parenthesis balance across all source files is also checked
programmatically after scripted edits.

### Practical constraints worth knowing

- **New source files need no project changes.** Xcode 16 synchronized groups
  pick up anything dropped into `Bites/`.
- **Claude cannot delete files by default.** Deletion inside the connected
  folder requires an explicit permission grant, which lapses. Without it,
  `rm` fails with "Operation not permitted".
- **Claude cannot push to GitHub.** The Linux VM has no access to the macOS
  keychain, SSH keys or GitHub CLI. Pushes are run by Nicholas from Terminal,
  where credentials already work. Claude prepares the commit and the remote.
- **A stale `.git/index.lock`** can block all git writes after an interrupted
  command. Deleting it is the fix.

### Feedback style that works well

Specific, line-level observations produce the best results. Examples from this
block that led directly to fixes: "the miles indicator is not pushed to the
left of the square the same way the steps/kcal/mins is", and "grams oz cup and
tbsp all have the same static numeric options". Both identified real defects
that were more interesting underneath than they appeared on the surface.

---

## 9. Command Reference

### Complete the first push

The repository must exist and be empty on GitHub first. Create it at
https://github.com/new with owner `KrauseysDevelopment`, name `Bites`,
visibility Private, and no README, `.gitignore` or license.

```sh
cd "/Users/nickkrause/Documents/Nicks Development Folder/Bites"
git push -u origin main
```

### Everyday git

```sh
cd "/Users/nickkrause/Documents/Nicks Development Folder/Bites"

git status                       # what has changed
git add -A                       # stage everything
git commit -m "Message"          # commit
git push                         # push to origin/main
git log --oneline                # history
```

### Verify no secret is about to be committed

Worth running before any commit that touches configuration.

```sh
git diff --cached --name-only | grep -x "Bites/Secrets.plist" \
  && echo "STOP: secret staged" || echo "safe"

git check-ignore -v Bites/Secrets.plist    # should print the gitignore rule
```

### Recover from a stale git lock

```sh
rm -f .git/index.lock
```

### Build from the command line

```sh
cd "/Users/nickkrause/Documents/Nicks Development Folder/Bites"

xcodebuild -scheme Bites -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

xcrun simctl list devices available
xcrun simctl install booted <path-to-Bites.app>
xcrun simctl launch booted NickKrause.Bites
```

### Set up secrets on a fresh machine

```sh
cp Bites/Secrets.example.plist Bites/Secrets.plist
# then edit Bites/Secrets.plist and replace the placeholder
```

### Confirm the USDA key works

Replace `YOUR_KEY` with the real key. A working key returns `totalHits` in the
high hundreds for this query.

```sh
curl -s "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=YOUR_KEY\
&query=boneless%20skinless%20chicken%20breast&dataType=SR%20Legacy&pageSize=2" \
  | python3 -m json.tool | head -30
```

### Reset local app data during testing

Delete the app from the device or Simulator. All state lives in `UserDefaults`
under the app's container, so a delete and reinstall clears everything.

---

## 10. Reference Links

| Resource | URL |
|---|---|
| Repository | https://github.com/KrauseysDevelopment/Bites |
| USDA API key sign-up | https://fdc.nal.usda.gov/api-key-signup/ |
| USDA API guide | https://fdc.nal.usda.gov/api-guide |
| USDA Foundation Foods docs | https://fdc.nal.usda.gov/Foundation_Foods_Documentation/ |
| USDA search-response spec bug | https://github.com/USDA/USDA-APIs/issues/102 |
| Open Food Facts API | https://openfoodfacts.github.io/openfoodfacts-server/api/ |
| Apple HealthKit | https://developer.apple.com/documentation/healthkit |
| VisionKit DataScannerViewController | https://developer.apple.com/documentation/visionkit/datascannerviewcontroller |
| Swift Charts | https://developer.apple.com/documentation/charts |
