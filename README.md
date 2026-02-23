# wp-dev-docker-template

Basic WordPress + MySQL dev setup for Docker/Dockge imports.

## Quick start

1. Start the stack:
   ```bash
   docker compose up -d --build
   ```
2. Open WordPress at `http://localhost:8080`.
3. (Optional) Open phpMyAdmin at `http://localhost:8081`.

This now works out-of-the-box without requiring any import files.

## Optional site import

If you have a migration ZIP (containing a SQL dump and/or `wp-content`), place it in the project root and set:

- `IMPORT_ZIP_FILE` (default: `site-export.zip`)
- `RUN_IMPORT=true` (default)
- `RUN_IMPORT=force` to re-run import on an existing volume

Optional URL replacement is controlled via:

- `OLD_SITE_URL`
- `NEW_SITE_URL` (default: `http://localhost:8080`)

If no ZIP is present, startup continues normally and WordPress runs as a clean install.
