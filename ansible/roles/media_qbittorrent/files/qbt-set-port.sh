#!/bin/sh
# Gluetun runs this every time ProtonVPN hands out a forwarded port. The port
# changes on each reconnection, so qBittorrent's listen port has to follow it,
# otherwise the tunnel forwards a port nothing is listening on.
#
# The WebUI answers unauthenticated on the loopback (WebUI\LocalHostAuth=false)
# and shares this network namespace, so no credential is needed here. On a cold
# start gluetun may get the port before qBittorrent is up, hence the retry.
set -u

port="$1"
attempt=0

while [ "$attempt" -lt 30 ]; do
	if wget -qO- --post-data="json={\"listen_port\":${port}}" \
		http://127.0.0.1:8080/api/v2/app/setPreferences >/dev/null 2>&1; then
		echo "[qbt-set-port] qBittorrent listen port set to ${port}"
		exit 0
	fi
	attempt=$((attempt + 1))
	sleep 2
done

echo "[qbt-set-port] gave up setting qBittorrent listen port to ${port}" >&2
exit 1
