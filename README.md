# GYM.

Log workouts, build exercises with a progressive-overload target, and watch each lift climb on its own line. One page, no build step, your data in your own Supabase database.

## How progressive overload works here

Each exercise has a target, like **3 sets × 8 reps**, and an increment, like **+5 lbs**. After every session GYM checks your top weight: if you hit every target set for the target reps, the next session suggests that weight plus the increment. If not, it suggests the same weight again and shows how close you got. **Log this ↗** opens the workout form pre-filled with the suggestion.

The progress line plots your estimated one-rep max per session (Epley: weight × (1 + reps/30)), so a heavier set and a higher-rep set both count. Bodyweight exercises plot best reps instead. Sessions that beat every earlier one are marked **PR**.

## Set up (about 10 minutes)

1. **Supabase.** Create a project at supabase.com (or reuse one you already have). In **SQL Editor**, paste the contents of [setup.sql](setup.sql) and click **Run**. Do this once.
2. **A login.** In **Authentication → Users**, click **Add user**, enter your email and a password, and tick **Auto confirm**. If you already have a user from another app on the same project, skip this.
3. **Vercel.** Import this repository at vercel.com → Add New → Project. Framework preset **Other**, no build command, root directory blank.
4. **Two environment variables** on that Vercel screen, both from your Supabase project's **Connect** dialog:
   - `SUPABASE_URL` → your project URL
   - `SUPABASE_PUBLISHABLE_KEY` → the key starting `sb_publishable_`
5. **Deploy.** Open the URL Vercel gives you, click **Sign in**, create your first exercise, then log a workout.

Vercel redeploys on every push to `main`.

## Your coach

A card near the top reads your own recent data and tells you how you are doing: a score out of ten, what is going well, what to change, and one next step. Nothing is sent until you press **Ask the coach**, and the last answer is kept on your device. It runs on Claude through a small Vercel function, so you need one extra environment variable in Vercel: `ANTHROPIC_API_KEY`, created at console.anthropic.com under API keys. Each ask costs about a cent. Without the key, the card simply says the coach is off.

## Run locally

```
SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... node dev.js
```

Then open http://localhost:8799.

## What's in it

- `index.html` — the page and its styles
- `gym.js` — sign-in, loading, the overload rule, the progress line, logging and editing
- `quote-of-day.js` — a quote that changes at local midnight
- `api/config.js` — hands the two public Supabase settings to the page
- `setup.sql` — the `exercises` and `sets` tables, locked to each user by row-level security

## Add to your iPhone home screen

Open the site in Safari, tap Share, then **Add to Home Screen**. It runs full screen below a black status bar.
