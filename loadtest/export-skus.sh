#!/usr/bin/env bash
# Writes data/skus.csv (sku,email) from the target's catalogue. Run after the
# fixtures are generated. Emails use example.com because Magento validates the
# TLD of a guest email and rejects reserved ones like .test.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data
docker compose -f ../compose.yaml exec -T db mariadb -N -u magento -pmagento magento \
  -e "SELECT p.sku FROM catalog_product_entity p JOIN cataloginventory_stock_item s ON s.product_id=p.entity_id WHERE p.type_id='simple' AND s.is_in_stock=1 AND s.qty>0 ORDER BY p.entity_id" \
  | awk -F'\t' 'BEGIN{print "sku,email"} {printf "%s,shopper-%d@example.com\n", $1, NR}' > data/skus.csv
echo "$(($(wc -l < data/skus.csv) - 1)) SKUs written to data/skus.csv"
