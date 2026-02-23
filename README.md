# wp-dev-docker-template

Basic template for Docker and Dockge imports - like Local, but better.

## What works out-of-the-box now

- Auto-detects your import archive when exactly one `.zip` is in the project root.
- Imports both `wp-content` and the first `.sql`/`.sql.gz` found in that archive.
- Runs fully non-interactive (no prompts that block container startup).
- Uses an unused host port by default (`WP_PORT=0`).

## Quick start

1. Put your export zip in the project root (only one zip file).
2. Run:

   ```bash
   docker compose up -d --build
   ```

3. Get the assigned WordPress URL:

   ```bash
   docker compose port wordpress 80
   ```

## Optional env vars

- `IMPORT_ZIP_FILE`: choose a specific zip file if there are multiple.
- `OLD_SITE_URL` + `NEW_SITE_URL`: enable post-import search-replace.
- `WP_PORT`: set a fixed host port instead of auto-assigning one.
