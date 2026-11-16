# XWiki on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/xwiki-1?utm_medium=integration&utm_source=button&utm_campaign=xwiki)

Railway template for [XWiki](https://www.xwiki.org), the open-source enterprise wiki and application platform.

It deploys:

- **XWiki 18.9.0** from the official image `xwiki:18.9.0-postgres-tomcat`, pinned by digest in the [`Dockerfile`](Dockerfile), with a small start script ([`railway-start.sh`](railway-start.sh)).
- **PostgreSQL** (Railway's database service).
- A volume at `/usr/local/xwiki` for attachments, installed extensions, the Solr search index and logs.

## First start

The first start takes a few minutes. While a placeholder page answers on the public URL, the start script runs XWiki on localhost only and:

1. creates the administrator from `XWIKI_ADMIN_USER` (default `Admin`) and `XWIKI_ADMIN_PASSWORD` (a generated secret) through XWiki's own Distribution Wizard step, so nobody else can claim the wiki;
2. installs the standard XWiki flavor (`org.xwiki.platform:xwiki-platform-distribution-flavor-mainwiki`, the default pages and applications) from the XWiki extension repository.

Then XWiki starts on the public port. Log in with the user and password from the XWiki service's **Variables** tab, and change the password from your profile if you like (the template doesn't reset it).

Markers on the volume (`data/.railway-admin-created`, `data/.railway-flavor-installed`) stop this from running again.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `XWIKI_ADMIN_USER` | `Admin` | Login of the first administrator, created on the first start |
| `XWIKI_ADMIN_PASSWORD` | generated secret | Password of the first administrator (used on the first start only) |
| `PORT` | `8080` | Port Tomcat listens on, used by Railway's domain and health check |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_DATABASE` | references to the Postgres service | Database connection |

Optional: `JAVA_OPTS` (the image defaults to `-Xmx1024m`; set for example `-Xmx2g` on a bigger plan), `XWIKI_ADMIN_EMAIL` (profile email of the first administrator).

Mail (SMTP) for registrations and notifications is set in XWiki under *Administer Wiki → Mail*.

## Updates

Railway notifies deployers when this repo's `main` branch changes. Each change bumps the pinned image and adds an entry to [`CHANGELOG.md`](CHANGELOG.md). After you apply an update that changes the XWiki version, log in as an administrator: XWiki's Distribution Wizard then offers to upgrade the installed flavor.

XWiki's own docs: [Docker image](https://hub.docker.com/_/xwiki), [installation guide](https://www.xwiki.org/xwiki/bin/view/Documentation/AdminGuide/Installation/), [release notes](https://www.xwiki.org/xwiki/bin/view/ReleaseNotes/).
