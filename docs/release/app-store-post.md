# VerbNest: App Store listing copy

**Name:** VerbNest
**Subtitle:** Local-first API client

Subtitle, name and promotional text must not mention price in any form (guideline 2.3.7 / 2.3.10: free, discounted, no cost, no subscription, "open source" as a price claim). The Mac App Store review of 0.64.3 rejected a subtitle for this; the text above has none, so the subtitle entered in App Store Connect must be set to exactly this line. Price belongs in Pricing and Availability only.

## Promotional text (139/170)
Send requests, write tests and keep every collection on your own device. No account, no cloud, no tracking. Built for iPhone, iPad and Mac.

## Description (2406/4000)
Plain text: the App Store does not render Markdown. Capitalised lines are section headings.

VerbNest is an API client that keeps your work on your own device. Your collections, environments and history live in a local workspace. There is no account to create, nothing is uploaded, and there is no analytics or advertising.

BUILD AND SEND REQUESTS
Every HTTP method, query params, headers, and JSON, form, multipart and binary bodies, plus GraphQL. Variables such as {{baseUrl}} resolve from globals, environments, collections and folders. Secret values stay on your device.

STAY ORGANISED
Collections, folders and tabs. Favourites, workspace search and a command palette take you to any request fast. Save responses as examples and browse them later. Undo a delete or a move from the toast that appears.

SET AUTH ONCE
Choose Basic, Bearer, API key, JWT or OAuth 2.0 on a collection or folder, and every request inside inherits it.

SCRIPT AND TEST
Write pre-request and post-response scripts in JavaScript with a pm-style API, syntax highlighting and completion. Add no-code assertions on status, headers, body and response time, and see pass or fail in the Tests tab. Scripts are off until you turn them on for a workspace you trust.

RUN WHOLE COLLECTIONS
The runner executes a folder or a full collection against the environment you pick and shows the result of every request.

SEE EXACTLY WHAT HAPPENED
Pretty and raw response views, folding JSON with JSONPath filtering, a table view that turns a list of results into a grid you can sort, search, copy and save as CSV, headers, cookies, the exact request that was sent, timings, a history of past calls and a network console.

GENERATE CODE
Turn any request into cURL and other snippets. Secrets are masked unless you choose to include them.

BRING YOUR WORK IN AND OUT
Import Postman collections and environments, cURL commands, OpenAPI and HAR files. Export a readable workspace snapshot of plain files you can keep in Git.

BUILT FOR REAL NETWORKS
Proxy support, custom CA certificates, client certificates and a cookie jar. Certificate checks are on by default.

MADE FOR EVERYONE
Light and dark themes, an accent colour, keyboard shortcuts on iPad and Mac, and support for larger text sizes.

PRIVATE BY DESIGN
VerbNest sends only the requests you write, to the addresses you enter. Secrets are masked in history and reports, and are only sent to hosts you approve.

Download VerbNest and keep your API work where it belongs: with you.

## Keywords (93/100)
rest,http,graphql,json,oauth,openapi,curl,jwt,request,test,debug,endpoint,offline,private,har

Comma-separated, no spaces. Words already in the name, subtitle and category (VerbNest, local-first, API, client, developer, tools) are left out because Apple indexes them anyway. Third-party product names are left out on purpose: App Review rejects trademarked terms in keywords (guideline 2.3.7).

## Screenshots (2880 x 1800)
Regenerate with `scripts/screenshots_macos.sh`. These are headless renders of the real UI with sample data, not captures of a running app.

| File | Shows |
| --- | --- |
| 01-request-and-response | Collections, request editor and response |
| 02-create-pet-body | JSON request body |
| 03-auth-inherited-bearer | Inherited bearer auth |
| 04-scripts | Post-response script with `pm` API |
| 05-assertions-and-test-results | Assertions and test results |
| 06-response-headers | Response headers |
| 07-command-palette | Command palette |
| 08-generate-code | Code generation |
| 09-save-and-browse-examples | Saved examples |
| 10-search-workspace | Workspace search |
| 11-import | Import |
| 12-workspaces | Workspaces |
| 13-collection-runner | Collection runner |
| 14-history | History |
| 15-console | Network console |
| 16-environments | Environments |
| 17-settings | Settings |
| 18-dark-theme | Dark theme |
| 19-results-table | A list response as a sortable table |

Apple accepts 1280x800, 1440x900, 2560x1600 and 2880x1800 for Mac. Upload 3 to 10.
