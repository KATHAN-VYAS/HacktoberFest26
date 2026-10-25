# Validation record

Checked October 25, 2026 on Windows, Node.js 22.18.0.

- TypeScript checking passed (`npx tsc --noEmit`).
- Production Worker build passed through the Sites build helper.
- 26 local integration checks passed, including unauthenticated-write rejection, cross-origin rejection, public/private question separation, anonymous identifier redaction, community escalation, unknown-question fallback, parent-thread validation, idempotent votes, saved-state privacy, ownership checks, and membership persistence.
- Retrieval/provider-contract checks passed. Gemini responses were mocked, including a provider outage, abstention, and a supported answer. No live Gemini request was made and no real API key was configured.
- Browser verification in the Codex in-app browser covered sign-in simulation, an anonymous Pantry question, source links, private-answer status, community escalation, an anonymous reply, mobile navigation, and creating a community with automatic membership. The narrow layout was visually inspected. Desktop breakpoints are implemented but were not visually audited in a full-width browser.
- Local and hosted databases are distinct. Hosted deployment has not occurred: automatic approval review rejected source upload to the external private Sites project, pending the user's explicit authorization.

Not validated: real multi-account hosted interaction, live Gemini availability, UMD enrollment verification, production concurrency/load, notification delivery guarantees, a complete accessibility audit, or a staffed moderation workflow. No campus-wide student directory or email broadcast is connected.


## Live Gemini configuration check

The local app successfully loaded the user-supplied key from the ignored `.dev.vars` file. The key was neither printed nor committed. Gemini 2.5 Flash returned HTTP 404 for this new-user key, recommending Gemini 3.8 Flash. The model setting and default were updated accordingly. Subsequent Gemini requests returned HTTP 503 (high demand) or timed out; no successful live generated answer was observed. The local app returned its labeled source-summary fallback correctly. Generation now requests low thinking for Gemini 3 models and permits up to 30 seconds. Provider-contract tests and TypeScript checks passed after the change. The connection-test questions were removed from the local database.


## Latest AI-answer repair (October 25, 2026)

Resolved the earlier Gemini limitation by configuring gemini-3.5-flash-lite, which returned a successful real generated answer to the user's exact CS / AI professor question. The earlier 3.8 failure record describes the previous configuration.

Removed the topic keyword bypass (including professor and roommate), improved abbreviation/plural matching, added the official CS faculty directory, Clark Hall directions, and campus map summaries, and synchronized these records into the existing database without resetting community data. Both question composers now use the answer-first server path. Provider failures are labeled by category and authors can retry the same question.

The user's exact current-weather question returned fresh Open-Meteo campus-area conditions and an observation time. Weather service outages and stale observations keep the question private and never fabricate conditions. The existing public test threads retained their visibility when retried; new supported questions remain private.

29 integration checks, provider/retrieval/weather regressions, and TypeScript checks passed. Browser verification confirmed a real Gemini faculty answer with its official source, and the Retry AI answer control refreshed the same thread successfully. No hosting upload was attempted.


## Search and general-answer repair

Removed the empty-index early return. Questions can now attempt Google Search grounding, then use saved-source generation or clearly labeled general AI guidance. Uncertain answers and provider outages remain private until the author chooses to share. Structured Google grounding citations, safe source URLs, and required Search Suggestions are preserved; suggestions run in a sandboxed frame with scripts disabled. The stored source envelope remains compatible with older array-format records.

Live tests of the screenshot housing question and main-campus-area question returned useful Gemini answers. The area answer cited the 2023 Facilities source and reported 1,347 acres (about 5.45 square kilometers), retaining its reporting date. Google Search grounding returned HTTP 429 for this key while normal Gemini requests returned HTTP 200, so a successful live Search-grounded answer was not observed. The app shows that limitation. Positive search metadata/citation behavior was tested with mocked provider responses.

The retrieval/provider/weather tests, new grounding/general-answer regressions, TypeScript checks, and all 29 integration checks passed. GitHub publication was explicitly requested by the user after these repairs. No API key, runtime database, or local identity data is intended for the GitHub commit.
