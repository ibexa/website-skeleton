#!/bin/bash

#
# This script reads settings from `ddev ibexa-configurator` and sets up ddev
#

[ -z "$SETTINGS_FILE" ] && SETTINGS_FILE="./.ddev/.ibexa-instance-settings"
[ -z "$PROVISION_FILE_GENERAL" ] && PROVISION_FILE_GENERAL="./.ddev/.ibexa-setup-general-provisioned"
[ -z "$PROVISION_FILE_SERVICES" ] && PROVISION_FILE_SERVICES="./.ddev/.ibexa-setup-services-provisioned"
[ -z "$VERBOSE_INSTALL" ] && VERBOSE_INSTALL=false

function verbose_output() {
    if [ "$VERBOSE_INSTALL" = true ]; then
        "$@"
    else
        "$@" > /dev/null
    fi
}

if [ "$VERBOSE_INSTALL" != false ] && [ ! -f "$PROVISION_FILE_GENERAL" ] && [ ! -f "$PROVISION_FILE_SERVICES" ]; then
    clear
fi

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Settings file does not exist, run ddev ibexa-configurator first."
    exit 1
fi

source $SETTINGS_FILE

if [ ! -f "$PROVISION_FILE_GENERAL" ]; then
    # PHP
    echo "php_version: $PHP_VERSION" > .ddev/config.php.yaml
    echo "👷 Configured PHP version: $PHP_VERSION"

    # NodeJS
    echo "nodejs_version: $NODE_VERSION" > .ddev/config.node.yaml
    echo "👷 Configured Node version: $NODE_VERSION"

    # Web Server
    if [ "$HTTP_SERVER" = "apache-fpm" ]
    then
        echo "webserver_type: $HTTP_SERVER" > .ddev/config.http.yaml
    fi
    echo "👷 Configured HTTP server: $HTTP_SERVER"

    # Database
    echo "database:
    type: $DATABASE
    version: $DATABASE_VERSION" > .ddev/config.db.yaml
    echo "👷 Configured Database: $DATABASE:$DATABASE_VERSION"

    # App env
    echo "APP_ENV=$APP_ENV" >> .env.local
    if [ "$APP_ENV" = "prod" ]; then
        echo "APP_DEBUG=0" >> .env.local
    else
        echo "APP_DEBUG=1" >> .env.local
    fi
    echo "👷 Configured app environment: $APP_ENV"

    echo "👷 Restarting ddev project to reflect webserver and database changes"

    touch "$PROVISION_FILE_GENERAL"

    verbose_output ddev restart
fi

if [ -f "$PROVISION_FILE_SERVICES" ]; then
    exit 0
fi

DB_SCHEME=mysql
DB_USER=db
DB_PASS=db
DB_NAME=db
DB_HOST=db
DB_PORT=3306
DB_VERSION=$DATABASE_VERSION
DB_CHARSET=utf8mb4
DB_COLLATION=utf8mb4_unicode_520_ci

if [ "$DATABASE" = "mariadb" ]; then
    DB_VERSION=mariadb-`ddev exec -s db mysql -V | awk '{print $5}' | sed 's/-.*//'`
fi

if [ "$DATABASE" = "postgres" ]; then
    DB_PORT=5432
    DB_SCHEME=postgresql
    DB_CHARSET=utf8
    DB_COLLATION=utf8_unicode_ci
fi

echo "# " >> .env.local
echo "# dxp-installer generated" >> .env.local
echo "DATABASE_URL=${DB_SCHEME}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?serverVersion=${DB_VERSION}&charset=${DB_CHARSET}" >> .env.local
echo "DATABASE_VERSION=${DB_VERSION}" >> .env.local
echo "DATABASE_CHARSET=${DB_CHARSET}" >> .env.local
echo "DATABASE_COLLATION=${DB_COLLATION}" >> .env.local

echo "👷 Saved database details in .env.local"

if [ "$HTTP_CACHE" = "varnish" ]; then
   echo "# " >> .env.local
   echo "# dxp-installer generated" >> .env.local
   echo "TRUSTED_PROXIES=REMOTE_ADDR" >> .env.local
   echo "HTTPCACHE_PURGE_TYPE=varnish" >> .env.local
   echo "HTTPCACHE_PURGE_SERVER=$DDEV_PRIMARY_URL" >> .env.local

   verbose_output ddev get reithor/ddev-varnish

   # Config file is incorrectly generated, workaround is to hard replace domain name with sed
   # Can't use -i option because it's not supported in MacOS
   sed 's/VIRTUAL_HOST=novarnish.<nil>/VIRTUAL_HOST=novarnish.${DDEV_SITENAME}/g' .ddev/docker-compose.varnish-extras.yaml > .ddev/varnish.temp
   rm .ddev/docker-compose.varnish-extras.yaml
   mv .ddev/varnish.temp .ddev/docker-compose.varnish-extras.yaml
fi

echo "👷 Configured HTTP cache: $HTTP_CACHE"

# Memcached
if [ "$APP_CACHE" = "memcached" ]; then
    echo "# " >> .env.local
    echo "# dxp-installer generated" >> .env.local
    echo "CACHE_POOL=\"cache.memcached\"" >> .env.local
    echo "CACHE_DSN=\"memcached:11211?weight=33\"" >> .env.local

    verbose_output ddev get ddev/ddev-memcached
fi

# Redis
if [ "$APP_CACHE" = "redis" ]; then
    echo "# " >> .env.local
    echo "# dxp-installer generated" >> .env.local
    echo "CACHE_POOL=cache.redis" >> .env.local
    echo "CACHE_DSN=redis:6379" >> .env.local

    verbose_output ddev get ddev/ddev-redis-7
fi

echo "👷 Configured app cache: $APP_CACHE"

# Solr
if [ "$SEARCH_ENGINE" = "solr" ]; then
    echo "# " >> .env.local
    echo "# dxp-installer generated" >> .env.local
    echo "SEARCH_ENGINE=solr" >> .env.local
    echo "SOLR_CORE=collection1" >> .env.local
    echo "SOLR_DSN=http://solr:8983/solr" >> .env.local

    verbose_output ddev get reithor/ddev-ibexa-solr
fi

# Elasticsearch
if [ "$SEARCH_ENGINE" = "elasticsearch" ]; then
    echo "# " >> .env.local
    echo "# dxp-installer generated" >> .env.local
    echo "SEARCH_ENGINE=elasticsearch" >> .env.local
    echo "ELASTICSEARCH_DSN=http://elasticsearch:9200" >> .env.local

    verbose_output ddev get ddev/ddev-elasticsearch
fi

echo "👷 Configured search engine: $SEARCH_ENGINE"

echo "✅ Finished setting up ddev services. Restarting the environment..."
touch "$PROVISION_FILE_SERVICES"
ddev restart
