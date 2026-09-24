# Meal Shuffler — review and improvements, 24 September 2026

## Verdict

The app is further along than "a basic app". It has a real constraint planner (required and preferred rules, softmax taste learning, a bounded search for interacting rules), dated weeks with rollover and history, leftovers and a freezer, undo, four import paths plus a share extension, unit-normalised grocery aggregation, iCloud household sharing, a widget, Siri, reminders, complete Norwegian localisation, and 180+ XCTests behind five static CI checks. It did not need a rewrite. Rewriting 17,000 lines of Swift without a compiler would also have been the most likely way to make it worse, so I didn't.

The gaps were in the four places where the product idea actually happens:

| The idea | Where it stood | The gap |
| --- | --- | --- |
| Setting up rules ("fish on Tuesday, taco Friday, only healthy") | A rich rule vocabulary behind a template form | Five taps and a translation into the app's vocabulary for every rule. There was also no way to say "healthy". |
| Adding meals (text, pictures, links) | Link, scan, photo, paste, manual entry and the share sheet all work | Nothing important missing. I left it alone. |
| Clicking SHUFFLE, plus something viral | A spinner, then a list that had changed silently | The app's signature moment had no feel to it, and nothing a household would want to show anyone. |
| Community libraries and shopping export | Community switched off (correctly); Bring! could take only one web-imported dinner | Meal ideas had no way to travel between households, and the whole list couldn't reach Bring!. |

## What changed

### 1. Rules in your own words
Type the rule the way you'd say it, in English or Norwegian. The parser is [RuleSentenceParser.swift](../MealShuffler/Services/RuleSentenceParser.swift) and the UI is [RuleComposer.swift](../MealShuffler/Views/Rules/RuleComposer.swift).

- It covers the whole existing rule vocabulary. Some examples of what it reads:
  - Days: "Taco Friday", "fredagstaco", "tacofredag", "fish on Tuesday and Thursday", "mon–fri"
  - Groups of days: "weekdays" / "hverdager", "the weekend"
  - Limits: "max 2 chicken a week", "at least twice", "fewer than 3"
  - Time: "under 30 minutes", "half an hour"
  - Bans and allergies: "no pasta on weekdays", "no nuts", "allergic to peanuts"
  - Day plans: "leftovers on Wednesday", "we eat out on Fridays", "takeaway"
  - Variety: "not pasta two days in a row", "no repeats within 3 weeks", "fish every 2 weeks"
  - Schedules: "pizza every other Saturday" becomes a day rule on a two-week schedule
  - Softeners: "preferably" / "gjerne" makes the rule preferred rather than required
- Named dishes win over their categories, so "fish tacos on Friday" means that dish and not just fish. The household's own labels ("kid-friendly") work too.
- Several rules can go on one line, separated by commas. A comma inside a number isn't a separator, so Norwegian "1,5 time" stays one rule.
- Nothing is saved on a guess. The rule is shown back as its own sentence, together with how many meals fit it, before it's added. The existing duplicate and contradiction checks still apply.
- Tappable suggestion chips show the range. A chip is hidden once you already have that rule.
- The composer also appears in onboarding under the generated first week. Typing "fredagstaco" there re-plans Friday on the spot, which shows what rules are for better than any explanation would.
- It is a deterministic grammar, not a model call. It works offline, runs on every keystroke, and costs nothing.

### 2. A "healthy" category
`MealTag.healthy` is now a category, and 13 of the 40 built-in dinners carry it. That includes four fish dishes, so "healthy on weekdays" and "fish Tuesday and Thursday" can both hold. The recipe service's schema has the tag too. Meal tags now decode leniently: a category added by a newer version drops out instead of failing the whole meal. See [Meal.swift](../MealShuffler/Models/Meal.swift).

### 3. The shuffle moment
- **Slot reel.** Tapping shuffle spins each changeable day in the week strip. The days settle left to right, each with a light haptic tap: it feels like a slot machine, not a spinner. Reduce Motion turns it into a plain change. See [SlotReel.swift](../MealShuffler/Views/Components/SlotReel.swift).
- **The size of the draw.** The planner header shows "1 of 2.3M possible weeks". This is an estimate of how many weeks the household's required rules allow, and it moves when a rule tightens or a meal is added. It makes the rules feel like a shape rather than a cage. See `ShuffleOdds` in [WeekPosterContent.swift](../MealShuffler/Services/WeekPosterContent.swift).
- **No blocking spinner flash.** "Planning dinners…" now appears only if a draw takes longer than 0.6 s.

### 4. The viral piece: the week as a picture
- After a whole-week shuffle, a banner offers "A fresh week — send it to the family chat?" for eight seconds.
- The share sheet ([WeekShareView.swift](../MealShuffler/Views/Planner/WeekShareView.swift)) renders a 1080 × 1920 story-sized poster. It shows:
  - the household's name and the week
  - each dinner with its illustration
  - the household's own rule next to the day it decided ("✓ Taco Friday")
  - "N rules kept", the protein mix, and the "1 of 2.3M possible weeks" hook
- The poster uses fixed colours, so it looks the same whatever appearance the sending phone is in.
- From the same sheet you can also send the week as text, send this week's recipes, or send the house rules.

This is the loop that can spread: the picture is interesting even without the app, and the rules on it are something another family can adopt in one tap.

### 5. Community, friend-to-friend
The public community needs identity and moderation first ([ROADMAP §4](ROADMAP.md)), and it stays off. What families actually do is text each other, and that needs no backend. See [HouseholdShare.swift](../MealShuffler/Services/HouseholdShare.swift) and [IncomingShareView.swift](../MealShuffler/Views/Community/IncomingShareView.swift).

- **What can be sent:** house rules (from the Rules tab), a single recipe (library context menu or recipe detail), a whole collection (a "cookbook pack"), or this week's recipes.
- **How it travels:** the content is packed into the link itself, after the `#`: raw DEFLATE, then base64url, with a version prefix. Nothing is uploaded or stored, and a fragment is never sent to any server.
- **What gets left out:** rules about a family member's dislikes, or about the sender's own private recipes, don't travel, because they mean nothing in someone else's kitchen.
- **Receiving:** the receiver sees a preview, picks what to add, and gets a clear result, for example "Added 3 rules. 1 you already had. 1 would contradict your own rules and was left out." Received rules go through the same duplicate and contradiction checks, so a friend's list never overrides your own. Received recipes become new copies with new ids, and dishes you already have are skipped.
- **After adding rules:** "Shuffle a week with them" closes the loop.
- **Safety:** links are untrusted input. Decoding is capped at 1 MB (tested against a decompression bomb), numbers are range-checked, references to unknown dishes are dropped, only https images and http(s) source links survive, and one unreadable item drops alone rather than the whole message.

### 6. The whole shopping list to Bring!
This implements [ROADMAP §2](ROADMAP.md) as designed:

- A stateless `GET /v1/bring/list` on the Worker echoes the remaining list back as schema.org `Recipe` markup, with `no-store` and `noindex`.
- The access log records a fixed route label, never the URL.
- The app's menu item appears only when the service is configured, and a plain one-time confirmation says the list passes through the service.

### 7. Server: share landing pages
`/s/rules` and `/s/recipes` serve one static page. The page decodes the fragment in the browser, renders it with `textContent` only, and hands off to the app. The CSP allows only the Worker's own script. The page's script is built from the same functions the tests run, and I confirmed the script still parses after Wrangler's real bundling. See [server/src/share.ts](../server/src/share.ts).

## Verification, and its limits

- **Swift was not compiled or run.** This Windows machine has no Swift toolchain (installing one needs several GB of Visual Studio build tools). Every new Swift file was reviewed line by line for type-checking pitfalls, but **the first CI run may surface small compile errors**. Run Codemagic's simulator workflow before anything else.
- All five repository checks pass: localisation (1056 keys, 1181 Norwegian entries), format arguments, Swift structure, store API and call labels. The theme-colour check passes too.
- `npm run check` in `server/` passes: typecheck plus 31 tests (21 existing, 10 new).
- The parser grammar was mirrored in a Python harness that reads the lexicon straight from the Swift file. All 70 English and Norwegian phrases I tried parsed as intended, including every suggestion chip in both languages.
- New XCTests: 22 for the parser and 16 for sharing, the Bring! link, the poster and the odds, in [RuleSentenceParserTests.swift](../MealShufflerTests/RuleSentenceParserTests.swift) and [HouseholdShareTests.swift](../MealShufflerTests/HouseholdShareTests.swift). They have not been run yet.
- The device test round is in [IPHONE_TESTING.md](IPHONE_TESTING.md), under "Regler med egne ord, stokking og deling".

## Risks to check

1. **Mixed app versions in one iCloud household.** An older build cannot decode a meal tagged `healthy`: before this change, one unknown tag failed the whole meal. Update every device in a household together. From this build on, unknown tags are dropped instead.
2. **`mealshuffler://` links in chat apps.** Whether Messages and WhatsApp make custom-scheme links tappable is unverified. The message text reads fine either way, but deploying the service gives real `https` links with a landing page.
3. **Bring!'s parser.** Nobody has yet checked that Bring actually imports the list page. It uses the same markup Bring reads on recipe sites.
4. **Poster images.** Recipe photos are remote, so the poster uses the bundled illustrations, which render reliably offline.

## What I'd do next, in order

1. Run CI, fix whatever doesn't compile, then run the new device test round.
2. Deploy the Worker. That one step switches on better import, https share links with landing pages, and the Bring! list. Set `APP_STORE_URL` once there is a listing.
3. Universal links. Serve `apple-app-site-association` from the Worker and add the Associated Domains entitlement, so https share links open the app directly instead of going through the landing page.
4. **"Vote on the week"** as the next viral feature. The share codec already carries a week: send it to the family, and each person can mark dinners they'd swap before the shuffle is locked in. It is social, useful and private.
5. Parser fallback. When the grammar can't read a sentence, offer "Ask the service" as a fallback to the same recipe-service model, with the result still shown as a sentence before it's saved. This covers the long tail without making the common case slower.
6. Split `AppStore`, which is 1,600 lines. Persistence, planning orchestration, groceries, reminders and undo all live in one class. The new work is written as pure services with thin store hooks, which is the pattern to follow. Do the split with a compiler and the test suite running, not blind.
7. Public community ([ROADMAP §4](ROADMAP.md)), only after identity and moderation exist.

I considered and left out streaks, leaderboards and a public feed. They don't fit a calm family planner, and a feed without moderation is the fastest way to make the rest of the app look unfinished.
