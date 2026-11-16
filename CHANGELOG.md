# Changelog

Each entry is one version of this template. Railway shows deployers an "update available" notice when a change lands on `main`; read the entry before you apply it.

## 18.9.0-2 (2026-11-16)

- README: add the Deploy on Railway button for the published template `xwiki-1`. No change to the image or the start script.

## 18.9.0-1 (2026-11-16)

- First release: XWiki 18.9.0 (`xwiki:18.9.0-postgres-tomcat`, pinned by digest) with Railway PostgreSQL and a volume at `/usr/local/xwiki`.
- First boot creates the administrator from `XWIKI_ADMIN_USER` / `XWIKI_ADMIN_PASSWORD` and installs the standard XWiki flavor, with XWiki reachable on localhost only until both are done.
