#! /bin/sh
if [ "$1" = 'hindsight'  -a "$(id -u)" = '0' ]; then
    chown -R hindsight /hindsight/var/output

    exec gosu hindsight "$@"
fi

exec "$@"
