# Scenario OmniChannel — Legal Website

A standalone, static legal site for Scenario OmniChannel: Privacy Policy, Data Deletion Instructions, and Terms
of Service, covering both the web/Meta-integration side of the product and the Scenario mobile app.

Plain HTML + one CSS file. No build step, no framework, no external fonts/CDNs, no JavaScript.

## Structure

```
legal/
├── index.html                   Homepage — links to all three documents
├── privacy-policy/index.html    Privacy Policy
├── data-deletion/index.html     Data Deletion Instructions
├── terms/index.html             Terms of Service
├── assets/
│   ├── css/style.css            Shared stylesheet (responsive, light/dark aware)
│   └── images/favicon.svg       Site icon (small inline SVG, no raster assets)
├── README.md                    This file
└── LEGAL_SITE_AUDIT.md          Source-of-truth audit: what was imported, what was added, what's still unknown
```

## Deploying this folder — hand this to your backend/infra dev

**Give them the `legal/` folder as-is.** It is a complete, self-contained static site — every link inside it is
relative, so it works from any path or domain without edits.

### Option A — replace the current live routes (recommended)

The live site already serves `/privacy-policy/`, `/data-deletion/`, and `/terms/` on `scenariomnchnl.tech`. To
make this version the new source of truth at those same URLs (so nothing that already links to them — App
Store/Play Store listings, Meta app review, etc. — breaks):

1. Copy the contents of `legal/` to wherever the current site's static files are served from, preserving the
   folder names (`privacy-policy/`, `data-deletion/`, `terms/`) so the URLs stay identical.
2. If the current pages are rendered by a CMS/template rather than static files, either point that route at
   these static files instead, or port this HTML/CSS into the existing template — the content and structure are
   final either way.
3. Confirm all four pages load: `/`, `/privacy-policy/`, `/data-deletion/`, `/terms/`.

### Option B — host it as a separate static site

Any static host works (nginx, S3+CloudFront, Netlify, Vercel, GitHub Pages, etc.) — there is nothing
server-side to configure. Point the web server's document root at the `legal/` folder. Most static hosts
resolve `/privacy-policy/` to `privacy-policy/index.html` automatically; if yours doesn't, configure that
rewrite (or rename the files to `privacy-policy.html` etc. and update the internal links to match).

If you deploy to a different domain than `scenariomnchnl.tech`, update:
- The Google Play Console **App content → Privacy policy** URL, and the Data Safety account-deletion URL.
- Any link to these pages from within the mobile app itself (none currently exist — see the audit file).

## Editing later

Each page is self-contained plain HTML — open it in any editor and edit the text directly. There's no
templating: shared header/nav/footer markup is duplicated per page, so if you change the nav links, apply the
same change in all four HTML files. `assets/css/style.css` is the single stylesheet all four pages share.

## What NOT to do

Don't reintroduce a second, differently-worded privacy policy elsewhere — this site is meant to be the single
source of truth referenced from Google Play, the mobile app, and anywhere else Scenario's legal pages are
linked.
