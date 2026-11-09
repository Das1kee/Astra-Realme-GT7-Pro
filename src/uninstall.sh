#!/system/bin/sh
# Astra uninstall.sh —— 还原一切
MODDIR=${0%/*}
. "$MODDIR/bin/lib.sh" 2>/dev/null
cfg_load
st_load

p=$(cat "$STATE/daemon.pid" 2>/dev/null)
[ -n "$p" ] && kill -9 "$p" 2>/dev/null

# 还原 GT 模式的配置挂载、厂商属性、GPU 上限与 ORMS 服务状态。
extreme_clear_mounts
extreme_props_off
gpu_restore
orms_restore

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

# CPU 频率上限（msm_performance + 各 policy）
if [ -s "$STATE/state.conf" ]; then
	while IFS='=' read -r k v; do
		[ "$k" = "CAP_BASE" ] && [ -n "$v" ] && echo "$v" >/sys/kernel/msm_performance/parameters/cpu_max_freq 2>/dev/null
	done <"$STATE/state.conf"
fi
if [ -s "$STATE/caps.orig" ]; then
	while IFS='=' read -r f v; do
		[ -w "$f" ] && [ -n "$v" ] && echo "$v" >"$f" 2>/dev/null
	done <"$STATE/caps.orig"
fi

# 深度睡眠退出
dumpsys deviceidle unforce >/dev/null 2>&1

# GPU Boost（dcvs_boost）还原
ori=""
if [ -s "$STATE/state.conf" ]; then
	while IFS='=' read -r k v; do
		case "$k" in
		GPU_BOOST_ORIG) ori=$v ;;
		esac
	done <"$STATE/state.conf"
fi
for b in /sys/class/kgsl/kgsl-3d0/dcvs_boost /sys/class/kgsl/*/dcvs_boost; do
	[ -e "$b" ] && echo "${ori:-1}" >"$b" 2>/dev/null
done

# GPU 上下限
gmin=""; gmax=""
if [ -s "$STATE/state.conf" ]; then
	while IFS='=' read -r k v; do
		case "$k" in
		GPU_ORIG_MIN) gmin=$v ;;
		GPU_ORIG_MAX) gmax=$v ;;
		esac
	done <"$STATE/state.conf"
fi
for d in /sys/class/devfreq/*; do
	case "$d" in *kgsl*|*gpu*|*gpufreq*) ;; *) continue ;; esac
	[ -n "$gmin" ] && echo "$gmin" >"$d/min_freq" 2>/dev/null
	[ -n "$gmax" ] && echo "$gmax" >"$d/max_freq" 2>/dev/null
	[ -z "$gmin" ] && echo 160000000 >"$d/min_freq" 2>/dev/null
	[ -z "$gmax" ] && echo 1100000000 >"$d/max_freq" 2>/dev/null
	break
done

# LTPO 显示扩展：解除配置挂载并恢复 VRR 属性
ltpo_remove

rm -rf /data/adb/Astra 2>/dev/null
