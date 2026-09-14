# syntax=docker/dockerfile:1
# Runtime for the Magento project in this repository: PHP 8.3 FPM with every
# extension Magento 2.4.8 requires, nginx, and composer. The application itself
# is NOT in the image; compose mounts the repository at /var/www/html and the
# entrypoint runs `composer install` and `setup:install` on first boot.
FROM php:8.3-fpm-bookworm

ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=-1
WORKDIR /var/www/html

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx git curl unzip default-mysql-client \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default

# Magento's required extensions plus pcntl, which the VoltTest SDK needs.
RUN set -eux; \
    install-php-extensions \
        @composer \
        bcmath ftp gd intl opcache pcntl pdo_mysql soap sockets xsl zip \
    ;

COPY docker/php/magento.ini $PHP_INI_DIR/conf.d/zz-magento.ini
COPY docker/php/www.conf /usr/local/etc/php-fpm.d/zz-magento.conf
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint

# Debian's fastcgi_params passes HTTP_HOST as $host, which drops the port;
# Magento's admin host check then compares localhost:8090 with localhost:80
# and routes /admin to the storefront 404. $http_host keeps the port.
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && sed -i 's/^fastcgi_param  HTTP_HOST        $host;/fastcgi_param  HTTP_HOST        $http_host;/' /etc/nginx/fastcgi_params \
    && chmod +x /usr/local/bin/docker-entrypoint

EXPOSE 8080
ENTRYPOINT ["docker-entrypoint"]
