FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libzip-dev \
    zip \
    unzip \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libcurl4-openssl-dev \
    pkg-config \
    libssl-dev \
    libmagickwand-dev \
    libicu-dev \
    git \
    supervisor \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/log/supervisor

RUN docker-php-ext-install -j"$(nproc)" iconv \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd \
    && docker-php-ext-install pdo_mysql pdo mysqli zip sockets \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && pecl install redis imagick mailparse \
    && docker-php-ext-enable redis imagick mailparse

ENV COMPOSER_HOME=/composer
ENV PATH=./vendor/bin:/composer/vendor/bin:$PATH
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin/ --filename=composer

RUN cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && chown -R www-data:www-data /var/www

WORKDIR /var/www/html
