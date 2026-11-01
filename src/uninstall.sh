#!/system/bin/sh
# Astra uninstall.sh —— 还原一切
MODDIR=${0%/*}
. "$MODDIR/bin/lib.sh" 2>/dev/null

p=$(cat "$STATE/daemon.pid" 2>/dev/null)
[ -n "$p" ] && kill -9 "$p" 2>/dev/null

# 温控补丁挂载
if [ -s "$STATE/mounts.list" ]; then
	while IFS= read -r dst; do
		[ -n "$dst" ] && is_mounted "$dst" && umount "$dst" 2>/dev/null
	done <"$STATE/mounts.list"
fi

# 所有温度仿真归零
for z in /sys/class/thermal/thermal_zone*/emul_temp; do
	[ -w "$z" ] && echo 0 >"$z" 2>/dev/null
done

# 充电节点
[ -s "$STATE/charge.orig" ] && while IFS='=' read -r f old; do
	[ -w "$f" ] && [ -n "$old" ] && echo "$old" >"$f" 2>/dev/null
done <"$STATE/charge.orig"

# CPU 频率上限（走 perf HAL 也能识别的节点）
if [ -s "$STATE/state.conf" ]; then
	while IFS='=' read -r k v; do
		[ "$k" = "CAP_BASE" ] && [ -n "$v" ] && echo "$v" >/sys/kernel/msm_performance/parameters/cpu_max_freq 2>/dev/null
	done <"$STATE/state.conf"
fi
for p in /sys/devices/system/cpu/cpufreq/policy*; do
	chmod 0644 "$p/scaling_max_freq" 2>/dev/null
done

# GPU 最低频
for d in /sys/class/devfreq/*; do
	case "$d" in *kgsl*|*gpu*|*gpufreq*) ;; *) continue ;; esac
	echo 160000000 >"$d/min_freq" 2>/dev/null
	break
done

# 厂商属性
setprop persist.sys.environment.temp 25 2>/dev/null
setprop persist.sys.oplus.wifi.sla.game_high_temperature 43 2>/dev/null

rm -rf /data/adb/Astra 2>/dev/null
