#!/bin/sh
# Mini-MWAN main script

. /lib/functions.sh

CONFIG_FILE="/etc/config/mini-mwan"
ENABLED=0
CHECK_INTERVAL=30

load_config() {
    config_load mini-mwan
    config_get ENABLED global enabled 0
    config_get CHECK_INTERVAL global check_interval 30
}

start_service() {
    rm -f /var/run/mini-mwan.status

    load_config

    if [ "$ENABLED" = "1" ]; then
        logger -t mini-mwan "Starting mini-mwan service with check interval: ${CHECK_INTERVAL}s"
        # Add your service logic here
    else
        logger -t mini-mwan "Service is disabled"
    fi
}

stop_service() {
    logger -t mini-mwan "Stopping mini-mwan service"
    # Add your cleanup logic here
}

case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        start_service
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
