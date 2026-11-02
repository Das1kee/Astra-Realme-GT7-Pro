#!/system/bin/sh
# Astra service.sh —— 常驻守护
MODDIR=${0%/*}
. "$MODDIR/bin/lib.sh"
cfg_load
st_load

# 单实例
if [ -f "$STATE/daemon.pid" ]; then
	pid=$(cat "$STATE/daemon.pid" 2>/dev/null)
	if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
		log "daemon already running: $pid"
		exit 0
	fi
fi

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
	sleep 2
	i=$((i + 1))
	[ "$i" -gt 90 ] && break
done
sleep 8
echo $$ >"$STATE/daemon.pid"
rm -f "$STATE/device.env" 2>/dev/null
cache_device
# 首次用系统使用记录播种一次耗电统计（后台，不阻塞）
[ -s "$STATE/usage.db" ] || (sh "$MODDIR/bin/astra" seed-usage >/dev/null 2>&1 &)

SAFE=0
grep -q "^SAFE_MODE=1" "$STATE/config.conf" 2>/dev/null && SAFE=1
if [ "$SAFE" = "1" ]; then
	log "SAFE_MODE: thermal patches skipped"
	CFG_THERMAL_MODE=official
fi

if [ "$CFG_THERMAL_MODE" = "official" ]; then
	for z in /sys/class/thermal/thermal_zone*/emul_temp; do
		[ -w "$z" ] && echo 0 >"$z" 2>/dev/null
	done
elif [ "$CFG_THERMAL_MODE" = "off" ]; then
	# 等系统温控服务起来后再挂载，避免开机早期抢文件
	sleep 20
	thermal_off_on
fi
log "daemon start mode=$CFG_THERMAL_MODE safe=$SAFE"
while :; do
	[ -d "$MODDIR" ] || break
	tick
	sleep 4
done
log "daemon exit"
rm -f "$STATE/daemon.pid"
