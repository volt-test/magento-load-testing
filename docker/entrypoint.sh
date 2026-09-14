#!/usr/bin/env bash
# First boot: composer install into the mounted project, install Magento
# against the compose services, optionally generate Performance Toolkit
# fixtures. Every boot: start php-fpm and nginx. Nothing here is Docker
# specific; the same bin/magento commands work on a host install.
set -euo pipefail

cd /var/www/html
MAGENTO="php -d memory_limit=2G bin/magento"

: "${PHP_FPM_MAX_CHILDREN:=6}"
: "${MAGENTO_BASE_URL:=http://localhost:8090/}"
: "${MAGENTO_MODE:=default}"
: "${GENERATE_FIXTURES:=0}"
: "${FIXTURE_PROFILE:=small}"
: "${DB_HOST:=db}" "${DB_NAME:=magento}" "${DB_USER:=magento}" "${DB_PASSWORD:=magento}"
: "${OPENSEARCH_HOST:=opensearch}" "${REDIS_HOST:=redis}"
: "${ADMIN_USER:=admin}" "${ADMIN_PASSWORD:=Admin123456}" "${ADMIN_EMAIL:=admin@example.com}"
export PHP_FPM_MAX_CHILDREN

log() { printf '[magento-target] %s\n' "$*"; }

if [ ! -f vendor/autoload.php ] || [ ! -f bin/magento ]; then
    log "composer install (first boot, several minutes)"
    composer install --no-interaction --prefer-dist --no-progress
fi

log "waiting for MariaDB at ${DB_HOST}"
until mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -e 'SELECT 1' >/dev/null 2>&1; do sleep 2; done
log "waiting for OpenSearch at ${OPENSEARCH_HOST}"
until curl -sf "http://${OPENSEARCH_HOST}:9200/_cluster/health?wait_for_status=yellow&timeout=5s" >/dev/null; do sleep 2; done

if [ ! -f app/etc/env.php ]; then
    log "installing Magento (first boot)"
    $MAGENTO setup:install \
        --base-url="$MAGENTO_BASE_URL" --backend-frontname=admin \
        --db-host="$DB_HOST" --db-name="$DB_NAME" --db-user="$DB_USER" --db-password="$DB_PASSWORD" \
        --admin-firstname=Load --admin-lastname=Test \
        --admin-email="$ADMIN_EMAIL" --admin-user="$ADMIN_USER" --admin-password="$ADMIN_PASSWORD" \
        --language=en_US --currency=USD --timezone=UTC --use-rewrites=1 \
        --search-engine=opensearch --opensearch-host="$OPENSEARCH_HOST" --opensearch-port=9200 \
        --opensearch-index-prefix=magento2 --opensearch-timeout=15 \
        --cache-backend=redis --cache-backend-redis-server="$REDIS_HOST" --cache-backend-redis-db=0 \
        --page-cache=redis --page-cache-redis-server="$REDIS_HOST" --page-cache-redis-db=1 \
        --session-save=redis --session-save-redis-host="$REDIS_HOST" --session-save-redis-db=2 \
        --session-save-redis-log-level=3 \
        --disable-modules=Magento_TwoFactorAuth,Magento_AdminAdobeImsTwoFactorAuth
    # Offline shipping and payment used by the load test; both default to on,
    # this only pins them for a store where someone switched them off.
    $MAGENTO config:set carriers/flatrate/active 1
    $MAGENTO config:set payment/checkmo/active 1
    $MAGENTO config:set admin/security/admin_account_sharing 1
    # No mail transport in the stack; stop every placed order from logging a send failure.
    $MAGENTO config:set system/smtp/disable 1
    $MAGENTO indexer:set-mode schedule
    $MAGENTO cache:flush
    log "install done"
fi

if [ "$GENERATE_FIXTURES" = "1" ] && [ ! -f var/.fixtures-${FIXTURE_PROFILE}-done ]; then
    log "generating Performance Toolkit '${FIXTURE_PROFILE}' fixtures (several minutes)"
    $MAGENTO setup:performance:generate-fixtures --skip-reindex \
        "setup/performance-toolkit/profiles/ce/${FIXTURE_PROFILE}.xml"
    $MAGENTO indexer:reindex
    $MAGENTO cache:flush
    touch "var/.fixtures-${FIXTURE_PROFILE}-done"
    log "fixtures done"
fi

if [ "$MAGENTO_MODE" = "production" ] && [ "$($MAGENTO deploy:mode:show | grep -o 'production' || true)" != "production" ]; then
    log "switching to production mode (di:compile + static deploy)"
    $MAGENTO deploy:mode:set production
fi

chown -R www-data:www-data var generated pub/static pub/media 2>/dev/null || true
sed -i "s/set \$MAGE_MODE .*/set \$MAGE_MODE ${MAGENTO_MODE};/" /etc/nginx/conf.d/default.conf

log "starting php-fpm and nginx on :8080"
php-fpm -D
exec nginx -g 'daemon off;'
