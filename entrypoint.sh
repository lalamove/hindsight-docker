#! /bin/sh
if [ "$1" = 'hindsight'  -a "$(id -u)" = '0' ]; then
    chown -R hindsight /hindsight/output

    exec gosu hindsight "$@"
fi

exec "$@"
