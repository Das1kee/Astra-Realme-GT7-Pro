#!/system/bin/sh
# Astra service.sh —— 常驻守护
MODDIR=${0%/*}
. "$MODDIR/bin/lib.sh"
cfg_load
st_load

# 单实例
pid=$(cat "$STATE/daemon.pid" 2>/dev/null)
if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
	log "daemon already running: $pid"
	exit 0
fi

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
	sleep 2
	i=$((i + 1))
	[ "$i" -gt 90 ] && break
done
sleep 6
echo $$ >"$STATE/daemon.pid"
rm -f "$STATE/device.env" 2>/dev/null
cache_device
# 首次用系统使用记录播种一次耗电统计（后台，不阻塞）
[ -s "$STATE/usage.db" ] || (sh "$MODDIR/bin/astra" seed-usage >/dev/null 2>&1 &) 

# 官方模式下先清一遍仿真温度，避免任何残留
if [ "$CFG_THERMAL_MODE" = "official" ]; then
	for z in /sys/class/thermal/thermal_zone*/emul_temp; do
		[ -w "$z" ] && echo 0 >"$z" 2>/dev/null
	done
fi
STM=0
log "daemon start mode=$CFG_THERMAL_MODE"
while :; do
	[ -d "$MODDIR" ] || break
	tick
	sleep 4
done
log "daemon exit"
rm -f "$STATE/daemon.pid"
