#!/bin/sh
set -eu

: "${API_STAGING_HOST:?Set API_STAGING_HOST to the hostname of the staging API}"
case "$API_STAGING_HOST" in
  *[!A-Za-z0-9.-]*|.*|*.) echo "API_STAGING_HOST must be a hostname without scheme, port, or path" >&2; exit 1 ;;
esac

envsubst '${API_STAGING_HOST}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
exec nginx -g 'daemon off;'
