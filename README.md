# Magento 2 load testing example

Public repository: https://github.com/volt-test/magento-load-testing

A Magento Open Source 2.4.8 project with the VoltTest load test from
[Magento 2 Load Testing Tools: 5 Options Compared](https://volt-test.com/blog/magento-load-testing-tools)
living in the same repository, the same `composer.json` and the same vendor
tree as the store. It is the validation target for that article and the
starting point for the benchmark follow-up.

The repository holds only what a Magento project normally commits:
`composer.json`, the Docker runtime, and `loadtest/`. Magento itself comes
from composer on first install. Never add this host to `DEMO_TARGET_HOSTS`.

```
composer.json          Magento 2.4.8 metapackage + volt-test/php-sdk (require-dev)
loadtest/
  magento-guest-checkout.php   the article's checkout scenario, verbatim
  export-skus.sh               builds data/skus.csv from the catalogue
  sync-from-article.sh         regenerates the script from the blog post
  responses/                   raw REST responses captured during validation
compose.yaml           app, loadtest, MariaDB 11.4, OpenSearch 2.19, Redis 7.2
Dockerfile, docker/    PHP 8.3 FPM + nginx runtime; no application inside
```

## Packages and keys

`composer.json` points at the [Mage-OS mirror](https://mirror.mage-os.org/),
which serves the Magento Open Source packages without marketplace keys. If you
prefer Adobe's repository, change the `repositories` URL to
`https://repo.magento.com/` and provide keys in `auth.json` (or, for Docker,
`COMPOSER_AUTH='{"http-basic":{"repo.magento.com":{"username":"…","password":"…"}}}'`).

## Run it with Docker

```bash
GENERATE_FIXTURES=1 docker compose up -d   # composer install + setup:install + small-profile fixtures
docker compose logs -f app                 # wait for "starting php-fpm and nginx"
```

Storefront http://localhost:8090, Admin http://localhost:8090/admin
(`admin` / `Admin123456`; 2FA is disabled at install). The repository is
mounted into the container, so the code on disk is the code that runs;
`vendor`, `generated`, `var`, `pub/static` and `pub/media` sit in named volumes
for speed on macOS. `docker compose down -v` wipes everything.

Env knobs: `MAGENTO_MODE=production` (di:compile + static deploy, needed for
benchmark numbers, not for REST checkout), `PHP_FPM_MAX_CHILDREN` (default 6),
`FIXTURE_PROFILE` (small|medium|large).

## Run it without Docker

Any Magento-capable environment works (Herd, Valet, Warden, a VM). You need
PHP 8.3 or 8.4 with Magento's extensions plus `pcntl`, MySQL 8.4 or MariaDB
11.4, OpenSearch 2.19 and Redis 7.2.

```bash
composer install
bin/magento setup:install --base-url=http://magento.test/ --backend-frontname=admin \
  --db-host=127.0.0.1 --db-name=magento --db-user=magento --db-password=magento \
  --admin-firstname=Load --admin-lastname=Test --admin-email=admin@example.com \
  --admin-user=admin --admin-password=Admin123456 --use-rewrites=1 \
  --search-engine=opensearch --opensearch-host=127.0.0.1 --opensearch-port=9200
bin/magento config:set system/smtp/disable 1
php -d memory_limit=2G bin/magento setup:perf:generate-fixtures setup/performance-toolkit/profiles/ce/small.xml
```

`docker/entrypoint.sh` is the exact sequence the container runs, if you want
the Redis cache and session flags too.

## Run the load test

The SDK is in `require-dev`, so `composer install` already put it in `vendor/`.
The engine binary downloads on the first run.

```bash
loadtest/export-skus.sh                                   # data/skus.csv from the catalogue
docker compose run --rm loadtest                          # VUS=3 DURATION=30s by default
VUS=10 DURATION=1m docker compose run --rm loadtest
# or, on a host install:
TARGET_URL=http://magento.test VUS=3 DURATION=30s php loadtest/magento-guest-checkout.php
```

The `loadtest` service runs the same image and the same vendor tree in its own
container, so the generator is not the php-fpm it measures. That is enough to
prove the script; for numbers use VoltTest Cloud, as the article says.

Success means zero errors on all five steps and a rising count in
`sales_order` (the small profile seeds 80 orders):

```bash
docker compose exec db mariadb -u magento -pmagento magento \
  -e "SELECT COUNT(*) orders FROM sales_order; SELECT increment_id, customer_email FROM sales_order ORDER BY entity_id DESC LIMIT 3;"
```

## Out of stock, on purpose

Repeated `checkmo` orders consume fixture inventory. To see the failure the
article warns about, leave one unit of a SKU and run two carts through it:

```bash
docker compose exec db mariadb -u magento -pmagento magento \
  -e "UPDATE cataloginventory_stock_item SET qty=1, is_in_stock=1 WHERE product_id=(SELECT entity_id FROM catalog_product_entity WHERE sku='product_dynamic_1')"
docker compose exec app php bin/magento cache:clean full_page block_html collections
```

`loadtest/responses/out-of-stock-race-msi.txt` has the captured responses:
the first `payment-information` succeeds, the second returns
400 `Some of the products are out of stock.`, and a fresh cart then gets
400 `Product that you are trying to add is not available.` from `items`.
The same messages were observed on a source-built store without Inventory
Management (`out-of-stock-race.txt`).

## Validation log

- 2026-09-14, this layout (composer project from the Mage-OS mirror, Inventory
  Management installed): `docker compose run --rm loadtest` at 3 VUs for 30 s,
  29 requests, 100% success, orders 80 to 85, five `inventory_reservation`
  rows. `payment-information` returned the order id as a bare number here and
  as a quoted string on the source-built store; the article's regex accepts both.
- Raw responses from each endpoint are in `loadtest/responses/`.

## Notes

- `opcache.validate_timestamps=0` in the container: after editing
  `app/etc/env.php` or `config.php`, `docker compose restart app`, then
  `bin/magento cache:flush`, because a page generated with stale config stays
  in the Redis full page cache.
- Debian's nginx `fastcgi_params` sends `HTTP_HOST` without the port, which
  makes Magento reject `/admin` on a non-80 port. The image patches it to
  `$http_host`.
- Outbound mail is disabled (`system/smtp/disable=1`); there is no transport.
- Not here yet (benchmark follow-up): Varnish in front, production mode by
  default, a customer-checkout CSV of fixture accounts, a browse scenario.
