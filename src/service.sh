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
		cmdline=$(tr '\000' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
		case "$cmdline" in
		*"$MODDIR/service.sh"*)
			log "Astra daemon already running: pid=$pid"
			exit 0
			;;
		esac
	fi
	log "discard stale daemon pid: ${pid:-empty}"
	rm -f "$STATE/daemon.pid" 2>/dev/null
fi

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
	sleep 2
	i=$((i + 1))
	[ "$i" -gt 90 ] && break
done
sleep 8
cfg_load
st_load

# Earlier builds accumulated per-app energy with a single-cell voltage assumption.
# Keep a local backup and start clean so the corrected dual-cell estimates are comparable.
USAGE_SCHEMA="$STATE/usage.schema"
if [ "$(cat "$USAGE_SCHEMA" 2>/dev/null)" != "2" ]; then
	if [ -s "$STATE/usage.db" ]; then
		mv "$STATE/usage.db" "$STATE/usage.db.legacy-$(date +%Y%m%d-%H%M%S)" 2>/dev/null
	fi
	: >"$STATE/usage.db"
	chmod 0600 "$STATE/usage.db" 2>/dev/null
	echo 2 >"$USAGE_SCHEMA" 2>/dev/null
	log "reset legacy app usage samples for dual-cell power conversion"
fi

# A reboot breaks the charge-counter interval. Start a fresh baseline instead of
# treating the time between boots as one discharge sample.
CC_LAST=0
CC_AT=0
CURR_MA=0
AVG_MA=0
DIS_UAH=0
DIS_SEC=0
ST_AVG_MW=0
ST_AVG_AT=0
ST_AVG_MODE=
st_save
echo $$ >"$STATE/daemon.pid"
rm -f "$STATE/device.env" 2>/dev/null
cache_device

# 3 分钟后写 boot_ok：证明这次启动是健康的，供 post-fs-data 清理计数
( sleep 180; echo ok > "$STATE/boot_ok" 2>/dev/null ) &

SAFE=0
grep -q "^SAFE_MODE=1" "$STATE/config.conf" 2>/dev/null && SAFE=1
if [ "$SAFE" = "1" ]; then
	log "SAFE_MODE marked: window will show a warning, settings are kept"
fi

log "daemon start mode=$CFG_THERMAL_MODE safe=$SAFE"
# 旧版本可能把假温度留在新代码再也不碰的热区上（典型是 socd：整摄氏度、
# 100℃ trip，被写成 30100 后固件一直按过温处理，直接掉信号）。开机全量清一次。
emu_clear_all
log "cleared thermal emulation leftovers on all zones"
# 清掉旧版本可能残留的 Scene 假温度挂载（原来每 tick 都查，现在只在启动时查一次）
[ "$CFG_SCENE_SEES_FAKE" = "1" ] || scene_spoof_off
# 上一轮如果停在 Doze，标记文件不应影响本次轮询节奏
rm -f "$STATE/.doze.active" 2>/dev/null
# LTPO 显示扩展：post-fs-data 已挂载/设属性，这里幂等补齐一次
ltpo_apply
while :; do
	[ -d "$MODDIR" ] || break
	tick
	# 进入 Doze 后放慢轮询（10s），减少唤醒；熄屏但未进入 Doze 仍保持 4s
	if [ -f "$STATE/.doze.active" ]; then
		sleep 10
	else
		sleep 4
	fi
done
log "daemon exit"
rm -f "$STATE/daemon.pid"
