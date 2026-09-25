# Bites

A food and fitness tracker for iOS, built in SwiftUI. Food logging, water,
workouts with streaks, weight trends, and Apple Health integration.

## Features

**Today** — calorie ring against a daily goal, protein/carb/fat progress,
water tracking, and a seven-day calorie sparkline.

**Diary** — every meal grouped by day. Tap to edit name, category, macros or
the date; swipe to delete.

**Food search** — USDA FoodData Central for whole ingredients and branded
products, split into separate sections so packaged goods can't bury the raw
ingredient. Recents and favourites make repeat logging one tap.

**Barcode scanning** — VisionKit scanner on the Log Meal screen. Looks up
Open Food Facts first, then falls back to USDA branded, verifying the UPC
client-side because USDA has no barcode endpoint.

**Fitness** — workout streaks against a minutes-or-calories goal, manual
workout logging across 16 activity types with MET-based calorie estimates,
and automatic import of `HKWorkout` sessions from Apple Health, deduplicated
so nothing double counts.

**Weight** — trend chart with 7D / 1M / 1Y / All ranges, a seven-day moving
average to cut daily noise, and an optional weekly weigh-in reminder.

## Requirements

- iOS 18.5+
- Xcode 16+
- A free [USDA FoodData Central API key](https://fdc.nal.usda.gov/api-key-signup/)

## Setup

1. Clone and open `Bites.xcodeproj`.
2. Copy the secrets template and add your key:

   ```sh
   cp Bites/Secrets.example.plist Bites/Secrets.plist
   ```

   Replace `PASTE_YOUR_USDA_API_KEY_HERE` with your key.

   `Bites/Secrets.plist` is gitignored. USDA deactivates keys it finds
   published, so keep it out of version control. You can also paste the key
   into Settings → Food Database at runtime instead.

3. Build to a physical device. Barcode scanning needs a real camera and will
   show an unavailable state in the Simulator.

## Architecture

Plain SwiftUI with `ObservableObject` stores, no external dependencies.

| File | Role |
|---|---|
| `DiaryStore` | Meals, days, water, weight, goals |
| `WorkoutStore` | Workouts, goals, streak calculation |
| `HealthManager` | HealthKit reads and `HKWorkout` import |
| `USDAFoodService` | FoodData Central search and barcode lookup |
| `OpenFoodFactsService` | Barcode product lookup |
| `FoodSearchService` | Coordinates the two food sources |
| `RecentFoodsStore` | Recents and favourites |
| `WeighInReminder` | Weekly local notification |

Persistence is JSON in `UserDefaults`. Fine at family scale; a real
migration to SwiftData would be the move if this grows.

## Notes

Nutrition data from USDA FoodData Central and Open Food Facts is provided
per 100g and scaled locally. Health data is read-only; Bites never writes
back to Apple Health.
