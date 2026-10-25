# Validation record

Checked October 25, 2026 on Windows, Node.js 22.18.0. This record covers the current Next.js/Supabase migration. Earlier D1 preview checks do not establish real multi-account behavior.

- Production Next.js build passed with Webpack, including TypeScript and all pages/API routes. Turbopack failed to start its CSS helper on this Windows installation, so the supported Webpack compiler is selected in dev/build scripts.
- 28 checks passed against the actual PostgreSQL schema/functions in PGlite with service_role, anon and authenticated roles. Covered two-user posting/replies, anonymous redaction, private draft isolation, explicit community sharing, owner-only changes, source metadata, case-insensitive usernames, vote deduplication, bookmarks, memberships, cascade deletion, AI call limits, and denial of browser SQL/RPC access. Setup was applied twice to check repeatability.
- AI retrieval/provider contract and web-grounding regression suites passed. Provider responses were mocked, with no live Gemini call in this validation. Existing local Gemini credentials were carried into ignored .env.local without printing them.
- 4 local HTTP checks passed: login page, missing-configuration message, and cross-origin rejection for both write endpoints. The sign-in/create-account toggle and desktop layout were also checked in the browser. No account was submitted from that browser check.
- No configured private key was found in 175 tracked/new source files or generated browser assets. The private .env.local file is ignored by Git.
- Live Supabase validation is pending the owner's project URL/keys and execution of supabase/setup.sql. The hosted smoke suite is ready to create two temporary confirmed users, sign in through the actual app, exercise shared posts/replies/privacy/ownership, and remove its records. It sends no emails and makes no Gemini requests.
- Vercel deployment is deferred at the owner's request.

Not yet verified: real project credentials/schema, hosted multi-account interaction, email delivery, production load, account recovery, UMD enrollment, or a full accessibility audit.
