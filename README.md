# TerpCommons

A student-built UMD community: ask AI privately, then choose whether to share a question with other Terps. Students can post discussions, updates and events, answer threads, create communities, and post anonymously behind a private account.

## Run locally

1. Install Node.js 22.13+ and run `npm install`.
2. Fill `.env.local` using `.env.example`.
3. Follow [SUPABASE_SETUP.md](SUPABASE_SETUP.md) to create the shared tables and configure email accounts.
4. Run `npm run dev` and open http://localhost:3000.

The active app uses **Next.js, React, Supabase Auth/PostgreSQL and Gemini**. Vercel deployment can be added after shared account testing. The earlier Cloudflare/D1 preview and starter configuration remain in the repository for reference but are not used by the active npm dev/build/start commands. Local D1 student activity is not transferred.

## Features

- Separate email/password accounts, editable public username and self-reported student stage.
- Private AI answer previews, optional community escalation, linked source citations, Google Search grounding when quota permits, and live campus weather.
- Public posts, one-level nested replies, communities, memberships, upvotes, bookmarks and in-app notifications.
- Anonymous posts/replies hide username, stage and author ID from other users. The service still associates content with its owner.
- Server-verified identity, server-only database API, RLS, ownership checks, private draft filtering, transactional writes and per-account rate limits.
- Clearly marked synthetic examples and curated UMD source summaries.

## Checks

- `npm run test:database`: actual PostgreSQL schema/functions in PGlite; two identities, privacy, ownership and browser permissions.
- `npm run test:ai`: retrieval, provider contracts, safe citations and fallback regressions; provider responses mocked.
- `npm run test:hosted`: requires configured Supabase and a running local app. Creates two disposable confirmed accounts, checks real sign-in and shared API behavior, then removes test data. Sends no emails and does not call Gemini.
- `npm run build`: production Next.js build using Webpack, selected for this Windows environment.

Never commit `.env.local`, provider keys, local databases or account tokens. The Gemini key and Supabase secret key run only on the server.

## Prototype limits

Public posts are readable without signing in. UMD enrollment verification, private messaging, email broadcasts, a password-reset screen, and staffed moderation are not enabled. Reports are stored privately for the project owner. Supabase email delivery must be configured before general tester signup. Google Search grounding can hit a separate quota even when normal Gemini generation works. Saved sources and general guidance are labeled accordingly.

Independent hackathon project, not an official University of Maryland service.
