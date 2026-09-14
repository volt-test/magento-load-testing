#!/usr/bin/env bash
# Regenerates magento-guest-checkout.php from the code block in the VoltTest
# blog post so the validated script and the published one cannot drift.
# Maintainer tool: it needs the post's MDX source, which lives in the VoltTest
# website repository, not here. Point ARTICLE_PATH at it.
set -euo pipefail
cd "$(dirname "$0")"
POST="${ARTICLE_PATH:-../../frontend-portal/content/blog/magento-load-testing-tools.mdx}"
if [ ! -f "$POST" ]; then
  echo "article source not found at $POST; set ARTICLE_PATH (maintainers only)" >&2
  exit 1
fi
{
  printf '<?php\n// Verbatim copy of the checkout scenario in the blog post, produced by\n// sync-from-article.sh. Edit the post, not this file.\nrequire __DIR__."/../vendor/autoload.php";\n\n'
  awk '/```php title="loadtest\/magento-guest-checkout.php"/{f=1;next} /```/{f=0} f' "$POST"
} > magento-guest-checkout.php
php -l magento-guest-checkout.php
