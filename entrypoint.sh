#!/bin/sh
set -e

if [ "$1" = 'renew' ]; then
    initialise.sh
    certbot renew
elif [[ -z "$1" ]]; then
    echo >&2 "Usage: image <renew|cmd>"
    exit 1
else
    exec "$@"
fi
