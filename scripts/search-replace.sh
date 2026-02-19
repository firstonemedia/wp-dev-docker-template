#!/bin/bash
# scripts/search-replace.sh
# Run this manually if you need to change URLs later

WP_ROOT="/var/www/html"

echo "WordPress URL Search & Replace"
echo "=============================="

read -p "Old URL: " OLD_URL
read -p "New URL: " NEW_URL

if [ -z "$OLD_URL" ] || [ -z "$NEW_URL" ]; then
    echo "Error: Both URLs are required"
    exit 1
fi

cd "$WP_ROOT"
wp search-replace "$OLD_URL" "$NEW_URL" --all-tables --allow-root
wp search-replace "${OLD_URL%/}" "${NEW_URL%/}" --all-tables --allow-root

echo "✅ Replacement complete!"