# Navigation

Where everything lives, and why. Written for 0.7 after the 0.6.0 test round showed features
that existed but could not be found (the lock, Bring!, history) and others that were in two or
three places at once (reminders, sharing the week, sharing house rules).

## The rule

Each tab answers one question a household asks, in the order of the weekly loop. A feature
lives in the tab whose question it answers, **once**. A second way in is allowed only when it
is *contextual* -- it appears next to the thing it acts on (a rule chip above the week opens the
rules; "History" beside the "longest since cooked" shelf) -- never as a second menu entry.

| Tab | Question | Owns |
| --- | --- | --- |
| **Uke** | What are we eating this week and next? | the two plans, locks, per-day plans (who eats, guests, who cooks), shuffling, sharing and printing a week |
| **Retter** | What can we make? | the recipe library, its views, adding and importing recipes, collections, the freezer, history of what was cooked, recipe files |
| **Handle** | What do we need to buy? | the list, the shopping period, staples, shop order, sending/sharing/printing the list (Bring!, Reminders, PDF) |
| **Familie** | Who are we, and what do we like? | members, who is home when (attendance patterns), tastes, house rules, wishes, the kids view, the kitchen board, the dinner year |
| Settings (gear in Familie) | How should this phone behave? | reminders, planning aids (calendar, shake, sound, shared ingredients), recipe reading, full backup, privacy, about |

## What moves in 0.7

| Item | Was | Now | Why |
| --- | --- | --- | --- |
| Reminders | Familie row **and** Settings | Settings only | Set once; the Familie row was a duplicate. |
| Share this week | Uke toolbar **and** Familie | Uke toolbar only, for this *and* next week | Sharing a week belongs with the week. Next week used to get text only. |
| Print / PDF of the week | -- | Uke → share sheet | Fridge sheet on A4, optionally with the shopping list. |
| Print / PDF of the list | -- | Handle → send/share button | Next to Bring! and Reminders. |
| Share house rules | Familie, Rules toolbar, week share sheet | Rules toolbar (and as part of sharing a week) | The rules screen is where rules are; the week share keeps it because the rules shaped that week. |
| History | Only from the Retter shelf, which shows only while browsing and once something is cooked | Retter → ⋯ menu (always), plus the shelf link | One reliable way in where the recipes are; the shelf link stays as the contextual one. |
| Collections, Freezer | Inside the *filter* menu in Retter | Retter → ⋯ menu; the freezer shelf stays | They are places, not filters. The filter menu now only filters. |
| Recipe file import/export | Settings → "Export recipes" (which also imports) | Retter → ⋯ → "Recipe files" | It is about recipes, and it imports as well as exports. Settings keeps the full backup. |
| People at dinner | A bare stepper in Familie, unrelated to the member list | "Usually N at dinner" inside the People section, with each member's home pattern | One place that explains the number: the usual table, minus who is away by pattern, plus guests on the day. |
| Tastes | Section "Tastes" listing members | Section "People"; a member opens one page with when they eat at home and their tastes | One page per person instead of facts about them spread out. |
| Kids view | Menu of every member, adults included | Children only (all members if none is marked a child) | It is a child's view. |
| Kitchen board | Familie, on every device | Familie, on iPad only | It is a landscape iPad screen; on a phone it was clutter. |
| Guests on a day | Day → "Plan this day" → stepper (three levels) | Day sheet, directly: "N at dinner · +2 guests" | The most common day edit, one level down. |
| Shake to shuffle | Always on | Settings → Planning toggle (on by default) | iOS users expect shake to mean undo; it should be possible to turn off. |

Nothing is removed from the app; every feature still has exactly one place, plus at most one
contextual shortcut.

## Uke

- Header: week label, This week / Next week, rule chips (contextual way into the rules).
- Tonight card (this week only): picture, dinner, who cooks, lock, Start cooking, Change.
- Seven day rows: date, picture, dinner, one-tap lock; swipe to lock, replace or choose.
- Day sheet: recipe, cook, change the dinner, swap days, **people at dinner (+/− guests)**,
  who cooks, Plan this day (attendance, portions, time limit, takeaway/leftovers/away), lock,
  favourite, cooked / not today / not for a while.
- Toolbar: Undo, Share (picture, **print / PDF**, emoji, text, recipes, rules).
- Floating: Shuffle N days / All dinners are locked.

## Retter

- Search, segmented filter (all/favourites/mine…), category chips, filter menu (collection,
  label, needs review -- filters only).
- Shelves while browsing: Longest since cooked (→ History), In the freezer.
- All meals: pictures / list / names only, sort.
- Toolbar: + (add recipe: link, paste, scan, photos, write) and ⋯ (**History, Collections,
  Freezer, Recipe files**).

## Handle

- Progress, quick add, "Send the list to Bring!" (when the service is configured), aisles,
  bought, at home.
- Toolbar: Send/share (Bring!, Reminders, **Print / PDF**, share text) and ⋯ (shopping period,
  staples, shop order).

## Familie

- Household card (name, avatars, rename).
- **People**: "Usually N at dinner", each member → their page (home pattern, tastes), add member.
- House rules: first four, all rules (share lives in the rules screen).
- Wishes (only when there are any).
- Together: Kids view, Kitchen board (iPad), Dinner year.
- iCloud sharing / Explore when their feature flags are on.
- Toolbar: gear → Settings.

## Settings

- Reminders.
- Planning: busy evenings from the calendar, fewer things to buy, shake to shuffle, sound.
- Recipe imports (online reading).
- Your data: Full backup (recipe files are in Retter).
- About: privacy, introduction again, version.
