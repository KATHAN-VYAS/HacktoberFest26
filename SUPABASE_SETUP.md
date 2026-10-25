# Connect TerpCommons before deploying

The active app is Next.js + Supabase. Vercel is not required for these steps. The previous Cloudflare/D1 preview in the parent folder is separate and its local posts are not uploaded.

## 1. Local settings

Open `.env.local` in this folder (copy `.env.example` if missing).

In your Supabase project, use **Connect** or **Project Settings → API Keys** to copy:

| Local setting | Supabase value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Project URL, such as `https://YOUR_PROJECT.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Publishable key (`sb_publishable_...`) |
| `SUPABASE_SECRET_KEY` | Secret key (`sb_secret_...`), server only |

Legacy `anon` and `service_role` keys also work in those respective slots. Never put a secret key in a `NEXT_PUBLIC_` variable. Preserve the Gemini settings already in the file. Do not send keys in chat or commit `.env.local`.

## 2. Create the tables and source library

Open **SQL Editor → New query** in the same Supabase project. Copy the complete contents of `supabase/setup.sql`, paste, and click **Run**. This file is safe to run again: it preserves existing posts and refreshes the curated knowledge library. It creates tables, database functions, indexes and permissions, plus clearly marked synthetic sample conversations. It does not include local student activity.

The API uses server-only functions. The `anon` and `authenticated` roles have no direct access to community tables or these functions. RLS is enabled. The server verifies the user's Supabase session before calling functions with its secret key; private drafts and anonymous author details are filtered before any response reaches a browser.

## 3. Email accounts

In **Authentication → Sign In / Providers**, enable email/password signup. Keep email confirmation enabled.

In **Authentication → URL Configuration**, use:

- Site URL: `http://localhost:3000`
- Redirect URL: `http://localhost:3000/auth/confirm`

In **Authentication → Email Templates → Confirm signup**, use this confirmation link in the email body:

```html
<h2>Welcome to TerpCommons</h2>
<p><a href="{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=email">Confirm your email</a></p>
```

Supabase's default email sender restricts recipients and request rates. For testers outside the project's team, configure your own SMTP sender under Authentication before inviting them. For a local technical check, you can create two confirmed test accounts through the dashboard's Authentication → Users → Add user flow and sign in with their passwords. Use accounts you control; don't publish passwords or bypass verification for public signup.

## 4. Run and test locally

```powershell
npm install
npm run dev
```

Open `http://localhost:3000`. Restart the dev server after editing `.env.local`. The original `localhost:5173` tab belongs to the earlier preview and does not use this connection.

Use two independent browser sessions (normal and private windows) with two accounts:

1. Create a profile, post a discussion as account A. B should see it after refresh.
2. Reply as B. A should see the reply and its notification.
3. Ask AI as A. B must not see that private question or open its thread link.
4. Choose **Ask the community** as A. B can now see and answer it.
5. Repeat with anonymous posts/replies. Other users must see **Anonymous Terp**, with no username or student stage.
6. Verify B cannot delete or retry A's question. Bookmark and membership choices must stay separate.
7. Sign out and sign back in. Posts should remain in the shared database.

Automated local checks: `npm run test:database`, `npm run test:ai`, and `npm run build`. The database suite runs the actual PostgreSQL schema/functions in PGlite with two identities and browser/service roles. It does not prove your hosted Supabase project, email delivery, or live account setup works; complete the browser check above after configuring the project.

## 5. Vercel later

Import the GitHub repository as a Next.js project. Add the same environment settings privately in Vercel. Set Supabase's Site URL to your published HTTPS address and add its `/auth/confirm` URL. Do not use localhost links for remote testers. Supabase remains the shared database and account provider; Vercel runs the website and API. No deployment has been performed by this preparation step.

## Limits

This is a hackathon prototype. No UMD enrollment verification, private messaging, email broadcasts, password-reset screen, staffed moderation queue, or automated account deletion is provided. Reports are stored privately for the project owner to inspect. Public posts are readable without signing in. Student stages are self-reported. Google Search grounding depends on the Gemini project's quota; ordinary AI guidance and saved sources have explicit fallback labels.

References: [Supabase keys](https://supabase.com/docs/guides/getting-started/api-keys), [server-side auth](https://supabase.com/docs/guides/auth/server-side/creating-a-client), [email templates](https://supabase.com/docs/guides/auth/auth-email-templates), [SMTP](https://supabase.com/docs/guides/auth/auth-smtp).
