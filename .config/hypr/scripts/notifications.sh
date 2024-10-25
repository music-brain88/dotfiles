#!/bin/bash

# 通知のオン/オフを切り替える
toggle_notifications() {
    if pidof mako >/dev/null; then
        makoctl mode -r do-not-disturb && \
        notify-send "Notifications Enabled" "You will receive notifications"
    else
        makoctl mode -a do-not-disturb && \
        notify-send "Notifications Disabled" "You will not receive notifications"
    fi
}

# 通知をクリア
clear_notifications() {
    makoctl dismiss -a
}

case "$1" in
    "toggle")
        toggle_notifications
        ;;
    "clear")
        clear_notifications
        ;;
esac
