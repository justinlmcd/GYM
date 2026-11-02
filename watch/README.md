# YOU for Apple Watch

All six apps on your wrist. The home screen shows each one's number for today (weight, money left this month, workouts this week, calories, your day's rating, pages read), its 🔥 streak, a check once you've logged it today, and **4 of 6 logged today** at the top, read from the same tables as the YOU page. Tap any app to log to it from your wrist:

- **BODY**: today's weight on the crown, starting from your last reading.
- **MONEY**: an amount on the crown, a category and where, with what's left of that category's budget this month.
- **GYM**: your workouts, cardio and sets, below.
- **MEAL**: calories and protein on the crown, an optional name, and which meal, with today's total against your goal.
- **WRITE**: rate today 1–10 and add a note by voice; saving again updates today's entry.
- **READ**: pages read for a book you're reading, with where they take you (needs READ's pages.sql).

Everything you log is saved on the watch first and uploads to that app's own table, so it shows on the web apps and the YOU page; with no signal it waits and uploads later. In GYM: Pick an exercise, turn the Digital Crown to set weight and reps, tap **Log set**. Each set goes straight into the same `sets` table the GYM web app uses, and cardio into the same `cardio` table, on the same login. So everything shows up in GYM's history, progress lines and coach, and in YOU's workout count, with no syncing step.

- **Workouts** you build in GYM, like **Chest day 1**, are listed at the top. Tap one to start it: its exercises appear in order, with a check on each one you've finished today and the next one marked **up next**. Once you've logged an exercise's target sets, **Next** takes you straight to the following exercise. Workouts need GYM's workouts table; if you set GYM up before workouts existed, run [workouts.sql](../workouts.sql) once.
- **Your exercises** come from GYM. Add or edit them on the web; the watch lists the ones that aren't archived.
- **Weight starts at GYM's suggestion**: the progressive-overload rule from the web app, based on your last session before today. After your first set it starts from your last set.
- **The crown moves weight by the exercise's increment** (falling back to 5 lbs or 2.5 kg if the increment is 0). Tap reps to move the crown to reps.
- **A rest timer** counts up from your last logged set.
- **No signal at the gym?** Sets are saved on the watch and upload the next time the app opens with a connection. Each set has its own ID, so a retry never logs it twice.
- **Swipe a set left** to delete it.
- **Cardio** sits at the top of the list. Pick treadmill, stairmaster, bike, rowing, elliptical or other. Press **Start timer** when you begin and **Stop** when you finish to fill in the minutes, or dial the minutes in. Calories and speed from the machine are optional; tap the unit to switch between mph, km/h, level, spm and rpm. The timer keeps running if you leave the app. Cardio needs GYM's cardio table; if you set GYM up before cardio existed, run [cardio.sql](../cardio.sql) once.

Sets you log on the watch are dated with your local day, like the web app. If you edit that day's workout in the web app afterwards, the web app's save replaces the sets for that exercise and day, as it always does.

## Install it (about 15 minutes, needs a Mac)

You need a Mac with **Xcode 26 or later**, your iPhone, and your Apple Watch on **watchOS 10 or later**. A free Apple ID works for signing; with a free account the app stops opening after 7 days and you reinstall it from Xcode. A paid Apple Developer account removes that limit.

1. **Make the project.** In Xcode: **File → New → Project → watchOS → App**. Name it `GYM`, interface **SwiftUI**, and choose **Watch-only App**. Save it inside this `watch/` folder.
2. **Name it YOU.** Select the project → the watch app target → **General**, and set **Display Name** to `YOU`.
3. **Swap in the code.** In the project navigator, delete the generated `ContentView.swift` and `GYMApp.swift` (Move to Trash). Then drag every `.swift` file from `watch/GYMWatch/` onto the watch app's folder in Xcode. Leave **Copy items if needed** unticked, and tick the watch app target.
4. **Add the icon.** Delete the generated `Assets.xcassets` (Move to Trash), then drag `watch/GYMWatch/Assets.xcassets` in the same way. It holds the app icon (YOU's six dots) and the accent color.
5. **Add your Supabase settings.** Open `Config.swift` and paste your project URL and publishable key (`sb_publishable_…`), the same two values as the GYM web app's Vercel settings. The publishable key is the public one; never use a secret or service-role key.
6. **Sign the app.** Select the project → the watch app target → **Signing & Capabilities** → choose your Apple ID under **Team**. Check that **Minimum Deployments** is watchOS 10.0 or later.
7. **Turn on Developer Mode.** Plug your iPhone into the Mac and trust it. On the iPhone: **Settings → Privacy & Security → Developer Mode** → on. On the watch: **Settings → Privacy & Security → Developer Mode** → on. Both restart.
8. **Run it.** In Xcode's run destination menu, pick your Apple Watch, then press **Run** (⌘R). The first install can take a few minutes. With a free account, on the watch go to **Settings → General → VPN & Device Management** and trust your developer profile if asked.
9. **Sign in** on the watch with the same email and password as YOU and the web apps. You stay signed in.

To try it without a watch first, pick an Apple Watch simulator as the run destination.

**Updating an existing project:** after pulling new code, drag any new files from `watch/GYMWatch/` into Xcode the same way (they aren't picked up automatically), then press **Run** again.

## What's in it

- `GYMWatchApp.swift`: app entry; shows sign-in or the home screen, and retries unsent logs and refreshes today's numbers when the app opens
- `HomeView.swift`: the YOU home screen, one row per app
- `QuickLogViews.swift`: the BODY, MONEY, MEAL, WRITE and READ log screens each row opens
- `HubModels.swift` and `Store+Hub.swift`: what each app's row reads and how its number, note and streak are worked out
- `ExerciseListView.swift`: GYM's screen: workouts, cardio and your exercises, today's ones first
- `LogSetView.swift`: weight and reps on the crown, **Log set**, today's sets and the rest timer
- `WorkoutView.swift`: a workout's exercises in order, with today's progress and what's up next
- `CardioView.swift`: cardio type, the timer, minutes, calories and speed, and today's sessions
- `SignInView.swift`: one-time sign-in
- `Store.swift`: loads exercises, recent sets and today's cardio, the overload rule, the offline queue
- `Supabase.swift`: sign-in, token refresh and the REST calls (no packages to install)
- `Keychain.swift`: keeps your session on the watch
- `Models.swift`: the `exercises`, `sets` and `cardio` rows, the cardio types, plus date helpers
- `Config.swift`: your Supabase URL and publishable key
- `Assets.xcassets`: the app icon and accent color
