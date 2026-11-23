FROM php:8.3-apache

# pdo_pgsql pour PostgreSQL, git pour composer, gcc et make pour le moteur C (suite de la SAE)
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev git unzip gcc make \
    && docker-php-ext-install pdo_pgsql \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY docker/php.ini /usr/local/etc/php/conf.d/boggle.ini
COPY docker/apache.conf /etc/apache2/sites-available/boggle.conf
RUN a2dissite 000-default && a2ensite boggle && echo "" > /etc/apache2/ports.conf

WORKDIR /var/www/html
ENV COMPOSER_ALLOW_SUPERUSER=1 PORT=80

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-autoloader

COPY . .
RUN composer dump-autoload --optimize --no-dev
