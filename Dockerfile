# Heimdall on the official Docker Hub PHP image (no LinuxServer runtime).
# App source: https://github.com/linuxserver/Heimdall (upstream project)
FROM docker.io/library/composer:2 AS composer

FROM docker.io/library/php:8.4-apache-bookworm

ARG HEIMDALL_VERSION=v2.8.1

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    curl \
    git \
    libicu-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libsqlite3-dev \
    libzip-dev \
    unzip \
    zlib1g-dev \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j"$(nproc)" gd intl pdo_sqlite zip \
  && a2enmod rewrite headers \
  && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY patch-database.php /tmp/patch-database.php

RUN curl -fsSL "https://github.com/linuxserver/Heimdall/archive/refs/tags/${HEIMDALL_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 \
  && composer install --no-dev --optimize-autoloader --no-interaction \
  && php /tmp/patch-database.php \
  && rm /tmp/patch-database.php \
  && sed -i 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/public#' /etc/apache2/sites-available/000-default.conf \
  && printf '%s\n' \
    '<Directory /var/www/html/public/>' \
    '  Options FollowSymLinks' \
    '  AllowOverride All' \
    '  Require all granted' \
    '</Directory>' \
    > /etc/apache2/conf-available/heimdall.conf \
  && a2enconf heimdall \
  && chown -R www-data:www-data /var/www/html

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV ALLOW_INTERNAL_REQUESTS=true \
    TZ=UTC

VOLUME ["/config"]
EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
