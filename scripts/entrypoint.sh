#!/bin/bash
# scripts/entrypoint.sh

set -e

ZIP_FILE="/tmp/import.zip"
EXTRACT_DIR="/tmp/extracted"
WP_ROOT="/var/www/html"

echo "=========================================="
echo "🚀 WordPress Development Setup"
echo "=========================================="

# Wait for database to be ready
echo "⏳ Waiting for database connection..."
until mysqladmin ping -h"$WORDPRESS_DB_HOST" --silent; do
    sleep 1
done
echo "✅ Database is ready!"

# Check if WordPress is already installed
if [ -f "$WP_ROOT/wp-config.php" ] && [ "$RUN_IMPORT" != "force" ]; then
    echo "⚠️  WordPress appears to be already configured."
    echo "   Set RUN_IMPORT=force to re-run import"
else
    # Standard WordPress setup first
    echo "🔧 Running standard WordPress entrypoint..."
    docker-entrypoint.sh apache2-foreground &
    WP_PID=$!
    
    # Wait for WordPress files to be copied
    sleep 5
    
    # Kill the background process (we'll restart properly later)
    kill $WP_PID 2>/dev/null || true
    
    # Handle ZIP import if specified
    if [ "$RUN_IMPORT" = "true" ] || [ "$RUN_IMPORT" = "force" ]; then
        if [ -f "$ZIP_FILE" ]; then
            echo "📦 Found import ZIP file"
            
            # Clean up previous extraction
            rm -rf "$EXTRACT_DIR"
            mkdir -p "$EXTRACT_DIR"
            
            # Extract ZIP
            echo "📂 Extracting ZIP contents..."
            unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
            
            # Find wp-content folder (might be nested)
            WP_CONTENT_SOURCE=$(find "$EXTRACT_DIR" -type d -name "wp-content" | head -n 1)
            
            if [ -n "$WP_CONTENT_SOURCE" ]; then
                echo "✅ Found wp-content at: $WP_CONTENT_SOURCE"
                
                # Backup current wp-content if exists
                if [ -d "$WP_ROOT/wp-content" ]; then
                    echo "💾 Backing up current wp-content..."
                    mv "$WP_ROOT/wp-content" "$WP_ROOT/wp-content.backup.$(date +%s)"
                fi
                
                # Copy new wp-content
                echo "📋 Copying wp-content to WordPress..."
                cp -r "$WP_CONTENT_SOURCE" "$WP_ROOT/wp-content"
                chown -R www-data:www-data "$WP_ROOT/wp-content"
                
                echo "✅ wp-content deployed successfully"
            else
                echo "⚠️  No wp-content folder found in ZIP"
            fi
            
            # Find and import SQL file
            SQL_FILE=$(find "$EXTRACT_DIR" -type f \( -name "*.sql" -o -name "*.sql.gz" \) | head -n 1)
            
            if [ -n "$SQL_FILE" ]; then
                echo "🗄️  Found SQL file: $SQL_FILE"
                
                # Wait for WordPress to create wp-config.php or create it
                if [ ! -f "$WP_ROOT/wp-config.php" ]; then
                    echo "📝 Creating wp-config.php..."
                    cp "$WP_ROOT/wp-config-sample.php" "$WP_ROOT/wp-config.php"
                    sed -i "s/database_name_here/$WORDPRESS_DB_NAME/" "$WP_ROOT/wp-config.php"
                    sed -i "s/username_here/$WORDPRESS_DB_USER/" "$WP_ROOT/wp-config.php"
                    sed -i "s/password_here/$WORDPRESS_DB_PASSWORD/" "$WP_ROOT/wp-config.php"
                    sed -i "s/localhost/$WORDPRESS_DB_HOST/" "$WP_ROOT/wp-config.php"
                    
                    # Generate unique keys
                    UNIQUE_KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
                    echo "$UNIQUE_KEYS" >> "$WP_ROOT/wp-config.php"
                fi
                
                # Import database
                echo "💾 Importing database..."
                if [[ "$SQL_FILE" == *.gz ]]; then
                    gunzip < "$SQL_FILE" | mysql -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" "$WORDPRESS_DB_NAME"
                else
                    mysql -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" "$WORDPRESS_DB_NAME" < "$SQL_FILE"
                fi
                echo "✅ Database imported successfully"
                
                # URL Replacement using WP-CLI
                echo ""
                echo "=========================================="
                echo "🔄 URL Search & Replace"
                echo "=========================================="
                
                # Interactive or ENV-based replacement
                if [ -z "$OLD_SITE_URL" ] || [ -z "$NEW_SITE_URL" ]; then
                    echo "Enter the OLD site URL (from the export):"
                    read -r OLD_URL_INPUT
                    echo "Enter the NEW site URL (this dev site):"
                    read -r NEW_URL_INPUT
                    
                    OLD_SITE_URL="${OLD_URL_INPUT:-$OLD_SITE_URL}"
                    NEW_SITE_URL="${NEW_URL_INPUT:-$NEW_SITE_URL}"
                fi
                
                if [ -n "$OLD_SITE_URL" ] && [ -n "$NEW_SITE_URL" ]; then
                    echo "Replacing: $OLD_SITE_URL → $NEW_SITE_URL"
                    
                    cd "$WP_ROOT"
                    wp search-replace "$OLD_SITE_URL" "$NEW_SITE_URL" --all-tables --allow-root
                    
                    # Also handle serialized data variations
                    wp search-replace "${OLD_SITE_URL%/}" "${NEW_SITE_URL%/}" --all-tables --allow-root
                    
                    echo "✅ URL replacement complete"
                else
                    echo "⚠️  Skipping URL replacement (URLs not provided)"
                fi
                
            else
                echo "⚠️  No SQL file found in ZIP"
            fi
            
            # Cleanup
            rm -rf "$EXTRACT_DIR"
            echo "🧹 Cleanup complete"
            
        else
            echo "⚠️  Import ZIP not found at $ZIP_FILE"
            echo "   Place your export ZIP as '$IMPORT_ZIP_FILE' in the project root"
        fi
    fi
fi

# Fix permissions
echo "🔒 Setting correct permissions..."
chown -R www-data:www-data "$WP_ROOT"
find "$WP_ROOT" -type d -exec chmod 755 {} \;
find "$WP_ROOT" -type f -exec chmod 644 {} \;

echo ""
echo "=========================================="
echo "🎉 WordPress is ready!"
echo "=========================================="
echo "Site URL: ${NEW_SITE_URL:-http://localhost:${WP_PORT:-8080}}"
echo "Admin:    ${NEW_SITE_URL:-http://localhost:${WP_PORT:-8080}}/wp-admin"
if [ -n "$PHP_MY_ADMIN_PORT" ]; then
    echo "phpMyAdmin: http://localhost:${PMA_PORT:-8081}"
fi
echo "=========================================="

# Start Apache in foreground
exec apache2-foreground