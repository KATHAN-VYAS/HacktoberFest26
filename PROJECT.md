# TerpCommons

A UMD-specific community web app: grounded campus answers first, lived student experience when sources aren't enough. Built for a two-person, six-hour hackathon scope.

## What works

- Live weather near UMD via Open-Meteo, with observation timestamps, stale-data rejection, and a private retry on service failure. Weather does not require a Gemini key.
- CS AI faculty and Clark Hall / campus map sources are included. Curated source additions sync into existing databases without resetting student posts.
- Questions from either composer use the answer-first path. Authors can retry an AI lookup on the same thread without creating duplicate posts. Provider failures distinguish busy, quota, access, model, and timeout problems.

- A responsive community feed with discussions, questions, campus updates, and events.
- Accounts with editable usernames and self-reported student stages. The hosted prototype uses Sign in with ChatGPT; local development uses the starter's loopback-only test identity.
- Anonymous posts and replies linked to an authenticated account. Public API responses omit underlying account IDs, usernames, and stages for anonymous content.
- A server-side, curated UMD knowledge base with source URLs and check dates. Keyword-ranked retrieval works without an API key. Gemini uses retrieved summaries, can search the web when needed, and can provide clearly labeled general guidance when no local source matches.
- All AI previews, including uncertain answers and provider failures, remain private. Authors can mark an answer helpful or publish the same question to the community.
- Public community questions generate in-app alerts for signed-in members; replies generate author alerts. Feeds refresh every 30 seconds. There is no campus-wide email or push broadcast.
- Replies with one visible nesting level, idempotent upvotes, saved posts, group creation and membership, search, and feed filters.
- Persistent Cloudflare D1 data. Report records are saved; owners can delete their own posts. Reports require manual review through the project database; no staffed moderation service is implied.

## Start locally

Requires Node.js 22.13+ and npm. Dependencies are pinned by `package-lock.json`.

```powershell
npm ci
npm run build
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/0000_red_toad_men.sql
npm run dev -- --port 5173
```

Visit the printed localhost address. Select **Sign in to join** to enter the loopback-only test account. That sign-in simulation is excluded from production builds. Local D1 data and hosted D1 data are separate. Run the migration only against a fresh local database; don't replay it after it has been applied.

## Connect Gemini

The app works in clearly labeled source-retrieval mode without a key. Gemini 3.5 Flash-Lite is configured and was tested successfully with the local key. Provider model availability depends on the project. To enable generated answers locally, create an untracked `.dev.vars` file at the project root:

```dotenv
GEMINI_API_KEY=your_key_here
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_WEB_SEARCH=true
```

Restart the development server. For hosting, configure the same names as server runtime environment variables through Sites and redeploy. Never place a secret in a browser bundle, commit, hosting manifest, or public form. The model name is configurable because provider availability can change.

Google Search grounding is enabled by default. If the key has exhausted its Search quota, the app labels that failure and falls back to saved-source answers or general AI guidance. Normal Gemini generation and Google Search grounding can have different quota availability. Grounded responses display source citations and the provider's Search Suggestions in a sandboxed frame. Set GEMINI_WEB_SEARCH=false to disable search calls.

Provider API reference: https://ai.google.dev/api/generate-content

## Validation

```powershell
npx tsc --noEmit
node --experimental-strip-types scripts/retrieval-test.mjs
node --experimental-strip-types scripts/web-grounding-test.mjs
# With the local development server running:
node scripts/smoke-test.mjs
```

The integration script creates and removes test-only posts in the local development database. Run it before adding your own local posts because it expects an initially seeded feed. The provider-contract tests mock Gemini responses; they do not prove a live key or model is working.

## Architecture

- UI: React 19, TypeScript, Lucide icons, custom responsive CSS.
- Server: Vinext/Vite on Cloudflare Workers; `/api/community` handles authenticated operations.
- Data: Cloudflare D1 (SQLite), schema tracked with Drizzle migrations.
- Identity: Sites-authenticated identity headers on hosting. Public usernames are randomly generated until edited, and are not derived from email addresses.
- Retrieval: a small curated SQL corpus, keyword ranking, optional Google Search grounding, and labeled general Gemini guidance. This MVP does not implement embeddings or a vector database.
- Community content never enters the trusted corpus automatically.

`app/community.tsx` contains the main interface, `lib/community.ts` the server operations, `lib/retrieval.ts` the retrieval/provider adapter, `lib/seed.ts` the curated sources and clearly marked sample content, and `db/schema.ts` the database schema.

## Knowledge sources

All source summaries were checked against official UMD pages on October 25, 2026. Summaries are snapshots; the app links to originals for updated hours, eligibility, policies, and deadlines.

- Off-campus housing: https://ochdatabase.umd.edu/housing
- Graduate housing resources: https://networth.rhsmith.umd.edu/admits/housing-resources-college-park-students
- Campus acreage (2023 snapshot): https://facilities.umd.edu/info-resources/facility-quick-facts-2023
- CS faculty: https://www.cs.umd.edu/people/faculty
- Clark Hall directions: https://ceee.umd.edu/about/directions
- Campus map: https://maps.umd.edu/
- Live weather API documentation: https://open-meteo.com/en/docs
- Campus Pantry: https://dining.umd.edu/md-community/campus-pantry
- Physical access: https://accessibility.umd.edu/campus-areas/physical-access
- UMD app: https://umd.edu/app
- Residence halls: https://reslife.umd.edu/explore-halls
- Traditions: https://umd.edu/about/history
- Events and involvement: https://studentaffairs.umd.edu/student-life/events-traditions
- Do Good: https://www.dogood.umd.edu/research-impact/projects/do-good-campus-fund
- Mission and values: https://umd.edu/about/mission

## Hackathon demo (about 90 seconds)

1. Show the feed and its distinct communities. Explain that sample conversations are labeled.
2. Ask “How can I use the UMD Campus Pantry?” anonymously. Show the linked source and private-answer status. Without Gemini, call this source retrieval.
3. Select “Ask the community.” The same question becomes public, preserving anonymity.
4. Add a reply and show the thread, upvote, and bookmark. With a second permitted hosted visitor, demonstrate an independent reply and in-app alert.
5. Ask a subjective question such as “Anyone know a good way to find roommates?” to demonstrate an AI preview that can then be shared with the community.
6. Create a research community and start its first discussion.

UMD connection: belonging, mutual support, accountability, and growth through shared knowledge. Independent student prototype; not an official UMD service.

## Before a wider student launch

Enrollment verification, non-ChatGPT email authentication, private groups/DMs, staffed moderation, reliable notification delivery, pagination beyond the MVP feed window, stronger abuse controls, accessibility auditing, and a continuously maintained source corpus need additional work. Incoming students must retain a route to join even before receiving UMD credentials. Anonymous publishing hides the public profile; account operators still hold the author link.

Hosted access starts owner-private. A link alone does not let teammates or judges enter; the owner must explicitly choose sharing permissions. No audience expansion is performed automatically.
