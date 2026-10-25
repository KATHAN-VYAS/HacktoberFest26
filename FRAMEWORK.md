# Active runtime

TerpCommons runs as a standard Next.js App Router app with Node.js API routes. Use npm dev/build/start, not the retained Vinext/Sites starter scripts. The API verifies Supabase Auth cookies using auth.getUser(), and refreshes cookies within API route responses. Pages are public shells; all account-dependent data passes through these routes.

Supabase holds shared PostgreSQL data. Browser roles cannot access community tables or functions directly. A server-only Supabase client invokes narrowly scoped tc_ functions with a verified user ID; the functions validate ownership, filter private content and redact anonymous identities. The secret key must stay in server environment settings.

See SUPABASE_SETUP.md for installation, account configuration, local testing and later Vercel deployment. Old D1 migrations, worker files and Vite tooling are historical and unused by the active runtime.
