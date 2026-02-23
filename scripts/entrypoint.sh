#!/bin/bash
# scripts/entrypoint.sh

set -euo pipefail

EXTRACT_DIR="/tmp/extracted"
WP_ROOT="/var/www/html"
IMPORT_DIR="/imports"

log() {
    echo "$1"
}

find_import_zip() {
    # Prefer explicit path when provided and mounted.
    if [ -n "${IMPORT_ZIP_FILE:-}" ] && [ -f "$IMPORT_DIR/$IMPORT_ZIP_FILE" ]; then
        echo "$IMPORT_DIR/$IMPORT_ZIP_FILE"
        return
    fi

    # Fallback: exactly one zip in project root mount.
    mapfile -t zip_files < <(find "$IMPORT_DIR" -maxdepth 1 -type f -name "*.zip" | sort)

    if [ "${#zip_files[@]}" -eq 1 ]; then
        echo "${zip_files[0]}"
        return
    fi

    if [ "${#zip_files[@]}" -eq 0 ]; then
        log "⚠️  No ZIP files found in project root mount ($IMPORT_DIR)."
    else
        log "⚠️  Multiple ZIP files found in project root mount ($IMPORT_DIR). Set IMPORT_ZIP_FILE to choose one."
        printf '   - %s\n' "${zip_files[@]}"
    fi

    echo ""
}

log "=========================================="
log "🚀 WordPress Development Setup"
log "=========================================="

DB_HOST="${WORDPRESS_DB_HOST%%:*}"
DB_PORT="${WORDPRESS_DB_HOST##*:}"
if [ "$DB_HOST" = "$DB_PORT" ]; then
    DB_PORT="3306"
fi

log "⏳ Waiting for database connection at ${DB_HOST}:${DB_PORT}..."
until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" --silent; do
    sleep 1
done
log "✅ Database is ready!"

# Check if WordPress is already installed
if [ -f "$WP_ROOT/wp-config.php" ] && [ "${RUN_IMPORT:-true}" != "force" ]; then
    log "⚠️  WordPress appears to be already configured."
    log "   Set RUN_IMPORT=force to re-run import"
else
    # Standard WordPress setup first
    log "🔧 Running standard WordPress entrypoint bootstrap..."
    docker-entrypoint.sh apache2-foreground &
    WP_PID=$!

    # Wait for WordPress files to be copied
    sleep 5

    # Kill the background process (we'll restart properly later)
    kill "$WP_PID" 2>/dev/null || true

    # Handle ZIP import if specified
    if [ "${RUN_IMPORT:-true}" = "true" ] || [ "${RUN_IMPORT:-true}" = "force" ]; then
        ZIP_FILE="$(find_import_zip)"

        if [ -n "$ZIP_FILE" ] && [ -f "$ZIP_FILE" ]; then
            log "📦 Found import ZIP file: $ZIP_FILE"

            # Clean up previous extraction
            rm -rf "$EXTRACT_DIR"
            mkdir -p "$EXTRACT_DIR"

            # Extract ZIP
            log "📂 Extracting ZIP contents..."
            unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"

            # Find wp-content folder (might be nested)
            WP_CONTENT_SOURCE=$(find "$EXTRACT_DIR" -type d -name "wp-content" | head -n 1)

            if [ -n "$WP_CONTENT_SOURCE" ]; then
                log "✅ Found wp-content at: $WP_CONTENT_SOURCE"

                # Backup current wp-content if exists
                if [ -d "$WP_ROOT/wp-content" ]; then
                    log "💾 Backing up current wp-content..."
                    mv "$WP_ROOT/wp-content" "$WP_ROOT/wp-content.backup.$(date +%s)"
                fi

                # Copy new wp-content
                log "📋 Copying wp-content to WordPress..."
                cp -a "$WP_CONTENT_SOURCE" "$WP_ROOT/wp-content"
                chown -R www-data:www-data "$WP_ROOT/wp-content"

                log "✅ wp-content deployed successfully"
            else
                log "⚠️  No wp-content folder found in ZIP"
            fi

            # Find and import SQL file
            SQL_FILE=$(find "$EXTRACT_DIR" -type f \( -name "*.sql" -o -name "*.sql.gz" \) | head -n 1)

            if [ -n "$SQL_FILE" ]; then
                log "🗄️  Found SQL file: $SQL_FILE"

                # Ensure wp-config exists
                if [ ! -f "$WP_ROOT/wp-config.php" ]; then
                    log "📝 Creating wp-config.php..."
                    cp "$WP_ROOT/wp-config-sample.php" "$WP_ROOT/wp-config.php"
                    sed -i "s/database_name_here/$WORDPRESS_DB_NAME/" "$WP_ROOT/wp-config.php"
                    sed -i "s/username_here/$WORDPRESS_DB_USER/" "$WP_ROOT/wp-config.php"
                    sed -i "s/password_here/$WORDPRESS_DB_PASSWORD/" "$WP_ROOT/wp-config.php"
                    sed -i "s/localhost/$WORDPRESS_DB_HOST/" "$WP_ROOT/wp-config.php"
                fi

                # Import database
                log "💾 Importing database..."
                if [[ "$SQL_FILE" == *.gz ]]; then
                    gunzip < "$SQL_FILE" | mysql -h"$DB_HOST" -P"$DB_PORT" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" "$WORDPRESS_DB_NAME"
                else
                    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" "$WORDPRESS_DB_NAME" < "$SQL_FILE"
                fi
                log "✅ Database imported successfully"

                # URL Replacement using WP-CLI (non-interactive only)
                if [ -n "${OLD_SITE_URL:-}" ] && [ -n "${NEW_SITE_URL:-}" ]; then
                    log "🔄 Replacing URLs: $OLD_SITE_URL → $NEW_SITE_URL"
                    cd "$WP_ROOT"
                    wp search-replace "$OLD_SITE_URL" "$NEW_SITE_URL" --all-tables --allow-root
                    wp search-replace "${OLD_SITE_URL%/}" "${NEW_SITE_URL%/}" --all-tables --allow-root
                    log "✅ URL replacement complete"
                else
                    log "ℹ️  Skipping URL replacement (set OLD_SITE_URL and NEW_SITE_URL to enable)"
                fi
            else
                log "⚠️  No SQL file found in ZIP"
            fi

            # Cleanup
            rm -rf "$EXTRACT_DIR"
            log "🧹 Cleanup complete"
        else
            log "⚠️  Import ZIP not found. Place exactly one .zip in project root or set IMPORT_ZIP_FILE."
        fi
    fi
fi

# Fix permissions
log "🔒 Setting correct permissions..."
chown -R www-data:www-data "$WP_ROOT"
find "$WP_ROOT" -type d -exec chmod 755 {} \;
find "$WP_ROOT" -type f -exec chmod 644 {} \;

log ""
log "=========================================="
log "🎉 WordPress is ready!"
log "=========================================="
log "Site URL will be available on host port mapped to container :80"
log "=========================================="

# Start Apache in foreground
exec apache2-foreground
