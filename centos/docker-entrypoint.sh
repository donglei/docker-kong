#!/bin/sh
set -e

# Disabling nginx daemon mode
export KONG_NGINX_DAEMON="off"

# Setting default prefix (override any existing variable)
export KONG_PREFIX="/usr/local/kong"

export KONG_LUA_PACKAGE_PATH="$KONG_CUSTOM_PLUGINS_PATH/?.lua;;"
export KONG_CUSTOM_PLUGINS="prometheus"

# Prepare Kong prefix
if [ "$1" = "/usr/local/openresty/nginx/sbin/nginx" ]; then
	kong prepare -p "/usr/local/kong"
fi

exec "$@"
