# mairy-crawl local dev (external stack) — PHP CLI + mount source, không COPY lib (prod image dùng images/base-image/Dockerfile)
FROM php:8.2-cli

ENV TZ=Asia/Tokyo

RUN apt-get update && apt-get install -y \
    git \
    p7zip \
    p7zip-full \
    zip \
    unzip \
    zlib1g-dev \
    libzip-dev \
    vim \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install -j"$(nproc)" zip pdo_mysql

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

RUN touch /usr/local/etc/php/conf.d/memory.ini \
    && echo "memory_limit = 2048M;" >> /usr/local/etc/php/conf.d/memory.ini \
    && echo "phar.readonly = Off;" >> /usr/local/etc/php/conf.d/phar.ini \
    && echo "date.timezone = Asia/Tokyo" >> /usr/local/etc/php/conf.d/timezone.ini \
    && echo "auto_detect_line_endings = On" >> /usr/local/etc/php/conf.d/php.ini

WORKDIR /var/www/html

RUN mkdir -p Chrome /tmp/Downloads && chmod 777 /tmp/Downloads

CMD ["php", "main.php"]
