#!/system/bin/sh
# Astra — Realme GT7 Pro (RMX5010) 温控 / 电池 / 调度  核心库
# Beta0.3.0 · Dasikee
# 性能约定：status 路径里不许出现 awk/sed/grep/dumpsys，全部用内建命令

ASTRA_ID=astra
STATE=/data/adb/Astra
LOGS=$STATE/logs
CONF=$STATE/config.conf
STATE_FILE=$STATE/state.conf
MODDIR=${ASTRA_MODDIR:-/data/adb/modules/$ASTRA_ID}
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/$ASTRA_ID
SDCARD=/storage/emulated/0
THERMAL=/sys/class/thermal
BATT=/sys/class/power_supply/battery
USB=/sys/class/power_supply/usb

umask 022
mkdir -p "$LOGS" "$STATE/tmp" 2>/dev/null

log() {
	_log_file=$LOGS/astra.log
	_log_size=$(wc -c <"$_log_file" 2>/dev/null)
	case "$_log_size" in ''|*[!0-9]*) _log_size=0 ;; esac
	if [ "$_log_size" -ge 524288 ]; then
		rm -f "$LOGS/astra.log.2" 2>/dev/null
		[ -f "$LOGS/astra.log.1" ] && mv -f "$LOGS/astra.log.1" "$LOGS/astra.log.2" 2>/dev/null
		mv -f "$_log_file" "$LOGS/astra.log.1" 2>/dev/null
	fi
	printf '[%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >>"$_log_file" 2>/dev/null
}

MODE_LOCK=$STATE/.thermal-mode.lock
mode_lock_acquire() {
	_mode_wait=0
	while ! mkdir "$MODE_LOCK" 2>/dev/null; do
		_mode_owner=$(cat "$MODE_LOCK/owner" 2>/dev/null)
		if [ -n "$_mode_owner" ] && [ ! -d "/proc/$_mode_owner" ]; then
			rm -rf "$MODE_LOCK" 2>/dev/null
		elif [ -z "$_mode_owner" ] && [ "$_mode_wait" -ge 3 ]; then
			rmdir "$MODE_LOCK" 2>/dev/null
		fi
		_mode_wait=$((_mode_wait + 1))
		[ "$_mode_wait" -ge 20 ] && return 1
		sleep 1
	done
	echo $$ >"$MODE_LOCK/owner" 2>/dev/null
	return 0
}
mode_lock_release() {
	_mode_owner=$(cat "$MODE_LOCK/owner" 2>/dev/null)
	if [ "$_mode_owner" = "$$" ]; then
		rm -f "$MODE_LOCK/owner" 2>/dev/null
		rmdir "$MODE_LOCK" 2>/dev/null
	fi
}

# ---------------------------------------------------------------- 配置（一次性读入）
CFG_THERMAL_MODE=official
CFG_MASK_BASE=26600
CFG_MASK_AMP=350
CFG_MASK_PERIOD=240
CFG_SCENE_SEES_FAKE=0
CFG_RAISE_WALL=0
CFG_MASK_FUSE_BATT=45000
CFG_MASK_FUSE_SOC=95000
CFG_CHARGE_AUTO=0
CFG_CHARGE_NOW=0
CFG_CHARGE_TEMP_CUT=45000
CFG_SAVE_ENABLED=0
CFG_DISABLE_GPU_BOOST=0
CFG_DEEP_SLEEP=0
CFG_DUAL_COMP=1
CFG_LTPO=1
CFG_LANG=zh

cfg_load() {
	[ -f "$CONF" ] || {
		cp -f "$MODDIR/config/defaults.conf" "$CONF" 2>/dev/null
		chmod 0600 "$CONF" 2>/dev/null
	}
	[ -f "$CONF" ] || return 0
	while IFS='=' read -r k v; do
		case "$k" in
		THERMAL_MODE) CFG_THERMAL_MODE=${v:-official} ;;
		MASK_BASE) CFG_MASK_BASE=${v:-26600} ;;
		MASK_AMP) CFG_MASK_AMP=${v:-350} ;;
		MASK_PERIOD) CFG_MASK_PERIOD=${v:-240} ;;
		SCENE_SEES_FAKE) CFG_SCENE_SEES_FAKE=${v:-0} ;;
		RAISE_WALL) CFG_RAISE_WALL=${v:-0} ;;
		MASK_FUSE_BATT) CFG_MASK_FUSE_BATT=${v:-45000} ;;
		MASK_FUSE_SOC) CFG_MASK_FUSE_SOC=${v:-95000} ;;
		CHARGE_AUTO) CFG_CHARGE_AUTO=${v:-0} ;;
		CHARGE_NOW) CFG_CHARGE_NOW=${v:-0} ;;
		CHARGE_TEMP_CUT) CFG_CHARGE_TEMP_CUT=${v:-45000} ;;
		SAVE_ENABLED) CFG_SAVE_ENABLED=${v:-0} ;;
		DISABLE_GPU_BOOST) CFG_DISABLE_GPU_BOOST=${v:-0} ;;
		DEEP_SLEEP) CFG_DEEP_SLEEP=${v:-0} ;;
		DUAL_COMP) CFG_DUAL_COMP=${v:-1} ;;
		LTPO_ENABLE) CFG_LTPO=${v:-1} ;;
		LANG) CFG_LANG=${v:-zh} ;;
		esac
	done <"$CONF"
}
cfg_set() { # 只改一行，不读全文件
	k="$1"; v="$2"
	if [ -f "$CONF" ] && grep -q "^$k=" "$CONF" 2>/dev/null; then
		sed -i "s@^$k=.*@$k=$v@" "$CONF" 2>/dev/null
	else
		echo "$k=$v" >>"$CONF" 2>/dev/null
	fi
}

# ---------------------------------------------------------------- 运行时状态
ST_MASK_LATCH=0
ST_MASK_ACTIVE=0
ST_THERMAL_OFF=0
ST_CHARGE_APPLIED=0
ST_CHARGE_GUARD=0
ST_CHARGE_START=0
ST_SAVE_APPLIED=0
ST_GPU_STATE=
ST_FG_GAME=0
ST_FG_PKG=
ST_SCENE_TAKEOVER=0
ST_DS_ACTIVE=0
ST_DS_LAST=0
ST_RADIO_LATCH=0
ST_PROP_AT=0
CAP_BASE=
st_load() {
	[ -f "$STATE_FILE" ] || return 0
	while IFS='=' read -r k v; do
		case "$k" in
		MASK_LATCH) ST_MASK_LATCH=${v:-0} ;;
		MASK_ACTIVE) ST_MASK_ACTIVE=${v:-0} ;;
		THERMAL_OFF) ST_THERMAL_OFF=${v:-0} ;;
		CHARGE_APPLIED) ST_CHARGE_APPLIED=${v:-0} ;;
		CHARGE_GUARD) ST_CHARGE_GUARD=${v:-0} ;;
		CHARGE_START) ST_CHARGE_START=${v:-0} ;;
		SAVE_APPLIED) ST_SAVE_APPLIED=${v:-0} ;;
		GPU_STATE) ST_GPU_STATE=${v:-} ;;
		GPU_ORIG_MIN) GPU_ORIG_MIN=$v ;;
		GPU_ORIG_MAX) GPU_ORIG_MAX=$v ;;
		GPU_BOOST_ORIG) GPU_BOOST_ORIG=$v ;;
		FG_GAME) ST_FG_GAME=${v:-0} ;;
		FG_PKG) ST_FG_PKG=${v:-} ;;
		PROP_AT) ST_PROP_AT=${v:-0} ;;
		CAP_BASE) CAP_BASE=$v; while [ "${CAP_BASE% }" != "$CAP_BASE" ]; do CAP_BASE=${CAP_BASE% }; done ;;
		USAGE_AT) ST_USAGE_AT=$v ;;
		AVG_MW) ST_AVG_MW=$v ;;
		AVG_AT) ST_AVG_AT=$v ;;
		AVG_MODE) ST_AVG_MODE=$v ;;
		SCENE_TAKEOVER) ST_SCENE_TAKEOVER=$v ;;
		CC_LAST) CC_LAST=$v ;;
		CC_AT) CC_AT=$v ;;
		AVG_MA) AVG_MA=$v ;;
		CURR_MA) CURR_MA=$v ;;
		DIS_UAH) DIS_UAH=$v ;;
		DIS_SEC) DIS_SEC=$v ;;
		DS_ACTIVE) ST_DS_ACTIVE=$v ;;
		DS_LAST) ST_DS_LAST=${v:-0} ;;
		MODEM_BAD) ST_MODEM_BAD=$v ;;
		RADIO_LATCH) ST_RADIO_LATCH=${v:-0} ;;
		FG_AT) FG_AT=${v:-0} ;;
		esac
	done <"$STATE_FILE"
}
st_save() { # 一次写盘
	{
		echo "MASK_LATCH=$ST_MASK_LATCH"
		echo "MASK_ACTIVE=$ST_MASK_ACTIVE"
		echo "THERMAL_OFF=$ST_THERMAL_OFF"
		echo "CHARGE_APPLIED=$ST_CHARGE_APPLIED"
		echo "CHARGE_GUARD=$ST_CHARGE_GUARD"
		echo "CHARGE_START=$ST_CHARGE_START"
		echo "SAVE_APPLIED=$ST_SAVE_APPLIED"
		echo "GPU_STATE=$ST_GPU_STATE"
		echo "GPU_ORIG_MIN=$GPU_ORIG_MIN"
		echo "GPU_ORIG_MAX=$GPU_ORIG_MAX"
		echo "GPU_BOOST_ORIG=$GPU_BOOST_ORIG"
		echo "FG_GAME=$ST_FG_GAME"
		echo "FG_PKG=$ST_FG_PKG"
		echo "PROP_AT=$ST_PROP_AT"
		echo "CAP_BASE=$CAP_BASE"
		echo "USAGE_AT=${ST_USAGE_AT:-0}"
		echo "AVG_MW=${ST_AVG_MW:-0}"
		echo "AVG_AT=${ST_AVG_AT:-0}"
		echo "AVG_MODE=${ST_AVG_MODE:-}"
		echo "SCENE_TAKEOVER=${ST_SCENE_TAKEOVER:-0}"
		echo "CC_LAST=$CC_LAST"
		echo "CC_AT=$CC_AT"
		echo "AVG_MA=$AVG_MA"
		echo "CURR_MA=$CURR_MA"
		echo "DIS_UAH=$DIS_UAH"
		echo "DIS_SEC=$DIS_SEC"
		echo "DS_ACTIVE=${ST_DS_ACTIVE:-0}"
		echo "DS_LAST=${ST_DS_LAST:-0}"
		echo "MODEM_BAD=${ST_MODEM_BAD:-0}"
		echo "RADIO_LATCH=${ST_RADIO_LATCH:-0}"
		echo "FG_AT=${FG_AT:-0}"
	} >"$STATE_FILE.tmp" 2>/dev/null && mv -f "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null
}

# 设备信息缓存（status 不再每 6 秒 fork 一次 getprop/ksud）
DEV_CACHE="$STATE/device.env"
cache_device() {
	{
		echo "MODEL=$(getprop ro.product.model)"
		echo "ROM=$(getprop ro.build.display.id)"
		echo "KERNEL=$(uname -r)"
		echo "ROOT=$(/data/adb/ksud -V 2>/dev/null | head -1)"
	} >"$DEV_CACHE" 2>/dev/null
}
dev_get() { # dev_get KEY
	DV=
	[ -f "$DEV_CACHE" ] || cache_device
	while IFS='=' read -r k v; do
		[ "$k" = "$1" ] && { DV=$v; break; }
	done <"$DEV_CACHE"
	printf '%s' "$DV"
}

# ---------------------------------------------------------------- 文件小工具
rd() { # rd FILE -> 变量 R（不 fork）
	R=
	[ -r "$1" ] && IFS= read -r R <"$1" 2>/dev/null
	printf '%s' "${R%$'\n'}"
}
fnum() { case "$1" in ''|*[!0-9-]*) echo 0 ;; *) echo "$1" ;; esac; }

# ---------------------------------------------------------------- 温度
ZONE_SPOOF="$STATE/zones.spoof"
ZONE_WITNESS="$STATE/zones.witness"
ZONE_BATTERY="$STATE/zones.battery"
ZONE_ACTIVE="$STATE/zones.active"
# 伪装目标只保留皮肤/主板这类“供显示和温控策略使用”的传感器。
# socd 绝对不能写：它是整摄氏度单位的 SoC 传感器，固件 trip 为 100℃；
# 写入 30100（毫摄氏度）在固件眼里就是 30100℃，直接触发厂商紧急过温保护，
# 实测会让手机掉信号（VOICE/DATA OUT_OF_SERVICE、运营商清空），因此从名单移除。
ZONE_SPOOF_NAMES="shell_front shell_frame shell_back sys-therm-0 sys-therm-2 sys-therm-4 sys-therm-5 sys-therm-6"
ZONE_WITNESS_NAMES="cpuss-0-0 cpuss-0-1 cpuss-1-0 cpuss-1-1 gpuss-0 gpuss-2 gpuss-4 gpuss-6 gpuss-7 cpu-0-2-0 cpu-1-1-1"
zone_idx() {
	for d in "$THERMAL"/thermal_zone*; do
		R=
		IFS= read -r R <"$d/type" 2>/dev/null
		[ "$R" = "$1" ] && { echo "${d##*thermal_zone}"; return 0; }
	done
	return 1
}
zone_get_type() { # zone_get_type INDEX -> ZT_TYPE（空 = 热区不存在）
	ZT_TYPE=
	[ -n "$1" ] && [ -d "$THERMAL/thermal_zone$1" ] || return 1
	IFS= read -r ZT_TYPE <"$THERMAL/thermal_zone$1/type" 2>/dev/null
	[ -n "$ZT_TYPE" ]
}
# 射频 / 调制解调器 / NSP / 电源管理 / 充电相关热区一律不碰
zone_is_rf() {
	case "$1" in
	*sdr*|*mmw*|*modem*|*mdmss*|*nsp*|*_pa|*pa_*|ddr*|camera*|socd*|pm8*|pmih*|*_tz|usb*|svooc*|*mos*|vbat*|*ibat*|*bcl*) return 0 ;;
	esac
	return 1
}
# 热区温度单位校验：trip_point_0_temp 形如 100/90 说明该热区用“摄氏度”，
# 写毫摄氏度会被固件当成极端过温；正常热区是 125000/135000（毫摄氏度）。
zone_scale_ok() {
	_zt=0
	IFS= read -r _zt <"$THERMAL/thermal_zone$1/trip_point_0_temp" 2>/dev/null
	case "$_zt" in ''|*[!0-9]*) return 0 ;; esac
	[ "$_zt" -eq 0 ] && return 0
	[ "$_zt" -gt 1000 ] && return 0
	return 1
}
zone_spoof_ok() { # zone_spoof_ok INDEX NAME -> 0 = 序号仍指向该热区且可安全写入
	zone_get_type "$1" || return 1
	[ "$ZT_TYPE" = "$2" ] || return 1
	zone_is_rf "$ZT_TYPE" && return 1
	zone_scale_ok "$1" || return 1
	[ -e "$THERMAL/thermal_zone$1/emul_temp" ] || return 1
	return 0
}
emu_write() { # emu_write INDEX VALUE —— 0 表示关闭仿真，对任何热区都安全
	[ -e "$THERMAL/thermal_zone$1/emul_temp" ] || return 1
	echo "$2" >"$THERMAL/thermal_zone$1/emul_temp" 2>/dev/null
}
emu_clear_all() { # 清掉所有热区的仿真值（开机/切换模式时清理旧版残留）
	for d in "$THERMAL"/thermal_zone*; do
		[ -e "$d/emul_temp" ] && echo 0 >"$d/emul_temp" 2>/dev/null
	done
	: >"$ZONE_ACTIVE" 2>/dev/null
}
build_zone_cache() {
	: >"$ZONE_SPOOF"
	: >"$ZONE_WITNESS"
	: >"$ZONE_BATTERY"
	for t in $ZONE_SPOOF_NAMES; do
		i=$(zone_idx "$t" 2>/dev/null)
		[ -n "$i" ] && echo "$t $i" >>"$ZONE_SPOOF"
	done
	for t in $ZONE_WITNESS_NAMES; do
		i=$(zone_idx "$t" 2>/dev/null)
		[ -n "$i" ] && echo "$t $i" >>"$ZONE_WITNESS"
	done
	i=$(zone_idx battery 2>/dev/null)
	[ -n "$i" ] && echo "battery $i" >>"$ZONE_BATTERY"
	log "zones: spoof=$(wc -l <"$ZONE_SPOOF") witness=$(wc -l <"$ZONE_WITNESS")"
}
zone_cache_valid() { # 每个“名字↔序号”是否仍然对得上（热区序号会随开机变化）
	while read -r _n _i; do
		[ -n "$_i" ] || continue
		zone_get_type "$_i" || return 1
		[ "$ZT_TYPE" = "$_n" ] || return 1
	done <"$ZONE_SPOOF"
	while read -r _n _i; do
		[ -n "$_i" ] || continue
		zone_get_type "$_i" || return 1
		[ "$ZT_TYPE" = "$_n" ] || return 1
	done <"$ZONE_WITNESS"
	while read -r _n _i; do
		[ -n "$_i" ] || continue
		zone_get_type "$_i" || return 1
		[ "$ZT_TYPE" = "$_n" ] || return 1
	done <"$ZONE_BATTERY"
	return 0
}
ensure_zone_cache() {
	[ -s "$ZONE_SPOOF" ] && zone_cache_valid && return 0
	[ -s "$ZONE_SPOOF" ] && log "thermal zone index changed; rebuilding zone cache"
	build_zone_cache
}
ztmp() { # ztmp INDEX -> ZT
	ZT=0
	IFS= read -r ZT <"$THERMAL/thermal_zone$1/temp" 2>/dev/null
	case "$ZT" in ''|*[!0-9-]*) ZT=0 ;; esac
}
emu_set() { # 旧接口：只做安全过滤的底层写入（selftest 用）
	[ -e "$THERMAL/thermal_zone$1/emul_temp" ] || return 1
	zone_get_type "$1" || return 1
	zone_is_rf "$ZT_TYPE" && return 1
	zone_scale_ok "$1" || return 1
	emu_write "$1" "$2"
}
real_batt_md() {
	RB=0
	IFS= read -r RB <"$BATT/temp" 2>/dev/null
	case "$RB" in ''|*[!0-9-]*) RB=0 ;; esac
	# 本机 power_supply 的 temp 单位是 0.1℃（278 = 27.8℃），少数机型是毫摄氏度
	if [ "$RB" -gt 0 ] && [ "$RB" -lt 1000 ]; then
		RB=$((RB * 100))
	elif [ "$RB" -lt 0 ]; then
		RB=0
	fi
	[ "$RB" -gt 1000 ] && return 0
	# 退路：热区（注意电池热区可能正在被伪装，只在万不得已时用；序号以名字校验）
	_fb=0
	while read -r _n _i; do [ "$_n" = "battery" ] && _fb=$_i; done <"$ZONE_BATTERY"
	[ -n "$_fb" ] && IFS= read -r RB <"$THERMAL/thermal_zone$_fb/temp" 2>/dev/null
	case "$RB" in ''|*[!0-9-]*) RB=0 ;; esac
	[ "$RB" -gt 1000 ] || RB=0
}

# ---- 兼容清理：旧版曾把假温度挂到 power_supply/battery/temp，这里统一卸掉 ----
SCENE_NODE="$BATT/temp"
SCENE_FAKE_FILE="$STATE/fake_batt_temp"
scene_spoof_off() {
	if is_mounted "$SCENE_NODE"; then
		src=$(awk -v p="$SCENE_NODE" 'index($0,p){print $1}' /proc/mounts 2>/dev/null | head -1)
		case "$src" in
		*"$STATE"*|*fake_batt_temp*) umount "$SCENE_NODE" 2>/dev/null && log "cleaned legacy scene mount" ;;
		esac
	fi
	rm -f "$SCENE_FAKE_FILE" 2>/dev/null
}
is_scene_spoofed() { is_mounted "$SCENE_NODE"; }
real_soc_md() {
	RS=0
	[ -s "$ZONE_WITNESS" ] || return 0
	while read -r _t i; do
		[ -n "$i" ] || continue
		IFS= read -r v <"$THERMAL/thermal_zone$i/temp" 2>/dev/null
		case "$v" in ''|*[!0-9-]*) continue ;; esac
		[ "$v" -gt 1000 ] && [ "$v" -gt "$RS" ] && RS=$v
	done <"$ZONE_WITNESS"
}

# ---------------------------------------------------------------- 伪装温度
mask_off() {
	# emul_temp 在本机不可回读，所以只能靠 zones.active 记账，精确清掉写过的地方
	if [ -s "$ZONE_ACTIVE" ]; then
		while read -r i _n; do
			[ -n "$i" ] && emu_write "$i" 0
		done <"$ZONE_ACTIVE"
	fi
	# 兜底：缓存指向的热区也写 0（0 = 关闭仿真，对任何热区都安全）
	while read -r _n i; do [ -n "$i" ] && emu_write "$i" 0; done <"$ZONE_SPOOF"
	while read -r _n i; do [ -n "$i" ] && emu_write "$i" 0; done <"$ZONE_BATTERY"
	: >"$ZONE_ACTIVE" 2>/dev/null
	rm -f "$ZONE_ACTIVE.tmp" 2>/dev/null
	scene_spoof_off
	ST_MASK_ACTIVE=0
}
mask_on() { # mask_on FAKE_MD
	f="$1"
	ok=0
	drift=0
	: >"$ZONE_ACTIVE.tmp" 2>/dev/null
	while read -r _n i; do
		[ -n "$i" ] || continue
		# 序号必须仍然指向缓存里的传感器名字，否则绝不写（防止热区重排后写错传感器）
		if zone_spoof_ok "$i" "$_n"; then
			emu_write "$i" "$f" && { echo "$i $_n" >>"$ZONE_ACTIVE.tmp"; ok=$((ok + 1)); }
		else
			drift=1
		fi
	done <"$ZONE_SPOOF"
	# 默认：Scene 看到真实电池温度；打开 SCENE_SEES_FAKE 才伪装电池热区
	scene_f="$f"
	[ "$CFG_SCENE_SEES_FAKE" = "1" ] || scene_f=0
	while read -r _n i; do
		[ -n "$i" ] || continue
		zone_get_type "$i" && [ "$ZT_TYPE" = "$_n" ] && emu_write "$i" "$scene_f"
	done <"$ZONE_BATTERY"
	mv -f "$ZONE_ACTIVE.tmp" "$ZONE_ACTIVE" 2>/dev/null
	MASK_SPOOFED=$ok
	ST_MASK_ACTIVE=1
	if [ "$drift" = "1" ]; then
		log "thermal zone cache drifted; rebuilt (spoofed=$ok)"
		build_zone_cache
	fi
}
mask_tick() {
	ensure_zone_cache
	real_batt_md; rb=$RB
	real_soc_md; rs=$RS
	wall=0
	[ "$CFG_RAISE_WALL" = "1" ] && wall=3000
	fo=$((CFG_MASK_FUSE_BATT + wall))
	so=$((CFG_MASK_FUSE_SOC + wall))

	if [ "$ST_MASK_LATCH" = "1" ]; then
		if [ "$rb" -gt 0 ] && [ "$rb" -lt $((fo - 5000)) ] && [ "$rs" -lt $((so - 5000)) ]; then
			ST_MASK_LATCH=0
			log "mask resume batt=$rb soc=$rs"
		else
			mask_off
			st_save
			return 0
		fi
	fi
	if { [ "$rb" -gt 0 ] && [ "$rb" -ge "$fo" ]; } || { [ "$rs" -gt 0 ] && [ "$rs" -ge "$so" ]; }; then
		ST_MASK_LATCH=1
		mask_off
		st_save
		log "mask FUSE batt=$rb soc=$rs limits=$fo/$so"
		return 0
	fi
	period=$CFG_MASK_PERIOD; [ "$period" -lt 60 ] 2>/dev/null && period=60
	amp=$CFG_MASK_AMP
	half=$((period / 2))
	pos=$(( ${TICK_NOW:-$(date +%s)} % period ))
	[ "$pos" -gt "$half" ] && pos=$((period - pos))
	fake=$((CFG_MASK_BASE - amp + amp * 2 * pos / half))
	mask_on "$fake"
	MASK_APPLIED=$fake
	st_save
}

# ---------------------------------------------------------------- 去温控
MNT="$STATE/mounts.list"
is_mounted() { # 不用 mountpoint（部分机型 toybox 没编进去）；sysfs 常是软链，需解析后再比
	p=$(readlink -f "$1" 2>/dev/null)
	[ -z "$p" ] && p="$1"
	awk -v a="$1" -v b="$p" '$2==a || $2==b {f=1} END{exit !f}' /proc/mounts 2>/dev/null
}
# ---------------------------------------------------------------- GT 去温控
# 方案来自 Extreme_GT：安装时把原厂温控 XML 改好放在模块里，开机后 bind 挂载覆盖；
# 再停 OPlus 温控服务、解锁 GPU 上限。官调模式卸载全部挂载并还原。
ORMS_SVC=vendor.oplus.ormsHalService-aidl-default
GPU_UNLOCK_ORIG="$STATE/gpu.unlock.orig"
PROPS_ORIG="$STATE/props.orig"
ORMS_ORIG="$STATE/orms.orig"
EXTREME_PATCH="$MODDIR/.astra-thermal-patches"
EXTREME_TOPS="odm my_product system vendor product"

extreme_walk_mount() { # $1 模块内目录  $2 对应系统目录
	for f in "$1"/*; do
		[ -e "$f" ] || continue
		b=${f##*/}
		t="$2/$b"
		if [ -f "$f" ]; then
			[ -f "$t" ] || continue
			is_mounted "$t" && continue
			if mount --bind "$f" "$t" 2>/dev/null; then
				grep -qxF "$t" "$MNT" 2>/dev/null || echo "$t" >>"$MNT"
			fi
		elif [ -d "$f" ] && [ -d "$t" ]; then
			extreme_walk_mount "$f" "$t"
		fi
	done
}
extreme_apply_mounts() {
	for top in $EXTREME_TOPS; do
		[ -d "$EXTREME_PATCH/$top" ] || continue
		extreme_walk_mount "$EXTREME_PATCH/$top" "/$top"
	done
}
extreme_clear_mounts() {
	if [ -s "$MNT" ]; then
		while IFS= read -r dst; do
			[ -n "$dst" ] && umount "$dst" 2>/dev/null
		done <"$MNT"
	fi
	: >"$MNT"
}
extreme_props_on() {
	if [ ! -s "$PROPS_ORIG" ]; then
		: >"$PROPS_ORIG"
		for k in persist.sys.environment.temp persist.sys.orms.name; do
			printf '%s=%s\n' "$k" "$(getprop "$k" 2>/dev/null)" >>"$PROPS_ORIG"
		done
		chmod 0600 "$PROPS_ORIG" 2>/dev/null
	fi
	setprop persist.sys.environment.temp 25 2>/dev/null
	setprop persist.sys.orms.name "" 2>/dev/null
}
extreme_props_off() {
	if [ -s "$PROPS_ORIG" ]; then
		while IFS='=' read -r k v; do
			[ -n "$k" ] && setprop "$k" "$v" 2>/dev/null
		done <"$PROPS_ORIG"
	fi
	rm -f "$PROPS_ORIG" 2>/dev/null
}
off_orms_stop() {
	svc=$(getprop "init.svc.$ORMS_SVC" 2>/dev/null)
	if [ "$svc" = "running" ]; then
		[ -f "$ORMS_ORIG" ] || { echo running >"$ORMS_ORIG"; chmod 0600 "$ORMS_ORIG" 2>/dev/null; }
		stop "$ORMS_SVC" >/dev/null 2>&1
	fi
	setprop persist.sys.orms.name "" 2>/dev/null
}
orms_restore() {
	if [ -f "$ORMS_ORIG" ]; then
		[ "$(cat "$ORMS_ORIG" 2>/dev/null)" = running ] && start "$ORMS_SVC" >/dev/null 2>&1
		 rm -f "$ORMS_ORIG" 2>/dev/null
	elif [ "$ST_THERMAL_OFF" = "1" ]; then
		# Upgrade from 0.2.1 did not save the original service state.
		start "$ORMS_SVC" >/dev/null 2>&1
	fi
}
gpu_unlock() {
	if [ ! -s "$GPU_UNLOCK_ORIG" ]; then
		: >"$GPU_UNLOCK_ORIG"
		for f in /sys/class/kgsl/kgsl-3d0/max_gpu_clk \
		         /sys/class/kgsl/kgsl-3d0/max_clock_mhz \
		         /sys/class/kgsl/kgsl-3d0/max_pwrlevel; do
			[ -e "$f" ] || continue
			v=""
			IFS= read -r v <"$f" 2>/dev/null
			[ -n "$v" ] && echo "$f=$v" >>"$GPU_UNLOCK_ORIG"
		done
		chmod 0600 "$GPU_UNLOCK_ORIG" 2>/dev/null
	fi
	[ -w /sys/class/kgsl/kgsl-3d0/max_gpu_clk ] && echo 2147483647 >/sys/class/kgsl/kgsl-3d0/max_gpu_clk 2>/dev/null
	[ -w /sys/class/kgsl/kgsl-3d0/max_clock_mhz ] && echo 2147483647 >/sys/class/kgsl/kgsl-3d0/max_clock_mhz 2>/dev/null
	[ -w /sys/class/kgsl/kgsl-3d0/max_pwrlevel ] && echo 0 >/sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null
}
gpu_restore() {
	if [ -s "$GPU_UNLOCK_ORIG" ]; then
		while IFS='=' read -r f v; do
			[ -w "$f" ] && [ -n "$v" ] && echo "$v" >"$f" 2>/dev/null
		done <"$GPU_UNLOCK_ORIG"
	fi
	rm -f "$GPU_UNLOCK_ORIG" 2>/dev/null
}
thermal_off_on() {
	thermal_off_keep
}
thermal_mount_count() {
	MOUNT_COUNT=0
	[ -s "$MNT" ] || return 0
	while IFS= read -r _mount_dst; do
		[ -n "$_mount_dst" ] || continue
		is_mounted "$_mount_dst" && MOUNT_COUNT=$((MOUNT_COUNT + 1))
	done <"$MNT"
}
thermal_off_keep() {
	extreme_apply_mounts
	thermal_mount_count
	if [ "$MOUNT_COUNT" -gt 0 ]; then
		extreme_props_on
		off_orms_stop
		gpu_unlock
		[ "$ST_THERMAL_OFF" = "1" ] || log "GT thermal patch active: $MOUNT_COUNT config file(s) mounted"
		ST_THERMAL_OFF=1
		rm -f "$STATE/thermal.mount.warn" 2>/dev/null
	else
		if [ "$ST_THERMAL_OFF" = "1" ]; then
			extreme_props_off
			gpu_restore
			orms_restore
		fi
		ST_THERMAL_OFF=0
		if [ ! -f "$STATE/thermal.mount.warn" ]; then
			log "GT thermal patch requested but no matching system config could be mounted"
			: >"$STATE/thermal.mount.warn"
		fi
	fi
}
thermal_off_off() {
	extreme_clear_mounts
	extreme_props_off
	gpu_restore
	orms_restore
	ST_THERMAL_OFF=0
	rm -f "$STATE/thermal.mount.warn" 2>/dev/null
	log "thermal OFF disabled: unmounted, restored"
}
thermal_all_clear() { # 官方模式：确保没有任何伪装/挂载残留
	thermal_off_off
	mask_off
	emu_clear_all
	ST_MASK_LATCH=0
}

# ---------------------------------------------------------------- LTPO 显示扩展
# 由独立模块 GT7Pro-LTPO v2.0 融合而来：systemless bind mount 替换
# /my_product/etc/oplus_vrr_config.json（去掉低亮度退出 LTPO 的档位、ambient、
# hw_nit_limit），并用 resetprop -n 临时打开 persist.oplus.display.vrr。
# 不写系统分区、不写持久属性；卸载或关闭后重启即恢复。
LTPO_SRC="$MODDIR/.astra-ltpo/oplus_vrr_config.json"
LTPO_TGT=/my_product/etc/oplus_vrr_config.json
LTPO_PROP=persist.oplus.display.vrr
LTPO_PROP_FILE=/data/property/persist.oplus.display.vrr
ltpo_resetprop() {
	if command -v resetprop >/dev/null 2>&1; then
		command -v resetprop
		return 0
	fi
	for _rp in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
		[ -x "$_rp" ] && { echo "$_rp"; return 0; }
	done
	return 1
}
ltpo_mounted() { # 不 fork：扫 /proc/mounts 的目标路径
	while read -r _dev _mnt _rest; do
		[ "$_mnt" = "$LTPO_TGT" ] && return 0
	done </proc/mounts
	return 1
}
ltpo_prop_set() {
	RP=$(ltpo_resetprop)
	[ -n "$RP" ] || { log "ltpo: resetprop not found"; return 1; }
	[ "$(getprop "$LTPO_PROP" 2>/dev/null)" = "1" ] && return 0
	HAD=0
	OLD=
	if [ -f "$LTPO_PROP_FILE" ]; then
		HAD=1
		OLD=$(cat "$LTPO_PROP_FILE" 2>/dev/null)
	fi
	"$RP" -n "$LTPO_PROP" 1 2>/dev/null || { log "ltpo: set VRR prop failed"; return 1; }
	# 防御：确认这次只改了内存属性，没有改写持久存储
	if [ "$HAD" -eq 0 ]; then
		[ -f "$LTPO_PROP_FILE" ] && rm -f "$LTPO_PROP_FILE" 2>/dev/null
	else
		NEW=$(cat "$LTPO_PROP_FILE" 2>/dev/null)
		[ "$NEW" = "$OLD" ] || printf '%s' "$OLD" >"$LTPO_PROP_FILE" 2>/dev/null
	fi
	return 0
}
ltpo_prop_restore() {
	RP=$(ltpo_resetprop)
	[ -n "$RP" ] || return 0
	if [ -f "$LTPO_PROP_FILE" ]; then
		OLD=$(cat "$LTPO_PROP_FILE" 2>/dev/null)
		if [ -n "$OLD" ]; then
			"$RP" -n "$LTPO_PROP" "$OLD" 2>/dev/null
		else
			"$RP" -n --delete "$LTPO_PROP" 2>/dev/null
		fi
	else
		"$RP" -n --delete "$LTPO_PROP" 2>/dev/null
	fi
}
ltpo_sync_attrs() { # 让源文件拥有目标文件的权限/属主/SELinux context
	[ -f "$LTPO_TGT" ] && [ -f "$LTPO_SRC" ] || return 1
	PERM=$(stat -c '%a' "$LTPO_TGT" 2>/dev/null)
	[ -n "$PERM" ] && chmod "$PERM" "$LTPO_SRC" 2>/dev/null
	OWNER=$(stat -c '%u:%g' "$LTPO_TGT" 2>/dev/null)
	[ -n "$OWNER" ] && chown "$OWNER" "$LTPO_SRC" 2>/dev/null
	if command -v chcon >/dev/null 2>&1; then
		CTX=$(ls -Z "$LTPO_TGT" 2>/dev/null | awk '{print $1}')
		[ -n "$CTX" ] && [ "$CTX" != "?" ] && chcon "$CTX" "$LTPO_SRC" 2>/dev/null
	fi
	return 0
}
ltpo_apply() { # 属性 + bind mount（CFG_LTPO=1 时才做，幂等）
	[ "$CFG_LTPO" = "1" ] || return 0
	[ -s "$LTPO_SRC" ] || { log "ltpo: payload missing ($LTPO_SRC)"; return 1; }
	[ -f "$LTPO_TGT" ] || { log "ltpo: target missing ($LTPO_TGT)"; return 1; }
	ltpo_prop_set
	ltpo_mounted && return 0
	ltpo_sync_attrs
	if mount --bind "$LTPO_SRC" "$LTPO_TGT" 2>/dev/null; then
		log "ltpo: display config mounted"
		return 0
	fi
	log "ltpo: bind mount failed"
	return 1
}
ltpo_remove() {
	if ltpo_mounted; then
		umount "$LTPO_TGT" 2>/dev/null || umount -l "$LTPO_TGT" 2>/dev/null
		log "ltpo: display config unmounted"
	fi
	ltpo_prop_restore
}
LTPO_CHECK_AT=0
ltpo_tick() { # 每 60 秒补齐一次（挂载丢失 / 属性被系统覆盖）
	[ "$CFG_LTPO" = "1" ] || return 0
	now=${TICK_NOW:-$(date +%s)}
	[ $((now - ${LTPO_CHECK_AT:-0})) -lt 60 ] && return 0
	LTPO_CHECK_AT=$now
	ltpo_apply
}



# ---------------------------------------------------------------- 充电
OPLUS=/sys/class/oplus_chg/battery
charge_snapshot() {
	: >"$STATE/charge.orig"
	chmod 0600 "$STATE/charge.orig" 2>/dev/null
	# Save only writable limits we actually control. current_max and OPlus fast/cool
	# nodes are read-only or write-only on this device and cannot be restored safely.
	for f in "$USB/input_current_limit" "$BATT/input_current_limit"; do
		[ -r "$f" ] && [ -w "$f" ] || continue
		IFS= read -r v <"$f" 2>/dev/null
		[ -n "$v" ] && echo "$f=$v" >>"$STATE/charge.orig"
	done
}
# Release only Astra's writable input-current limits. Charger negotiation and the
# vendor's temperature/step-charge policy remain authoritative.
charge_on() {
	[ -s "$STATE/charge.orig" ] || charge_snapshot
	mx=0
	IFS= read -r mx <"$USB/current_max" 2>/dev/null
	case "$mx" in ''|*[!0-9]*) mx=0 ;; esac
	applied=0
	controls=0
	all_at_max=1
	if [ "$mx" -gt 0 ]; then
		for f in "$USB/input_current_limit" "$BATT/input_current_limit"; do
			[ -r "$f" ] && [ -w "$f" ] || continue
			IFS= read -r old <"$f" 2>/dev/null
			case "$old" in ''|*[!0-9]*) continue ;; esac
			controls=$((controls + 1))
			if [ "$old" -ge "$mx" ]; then continue; fi
			all_at_max=0
			echo "$mx" >"$f" 2>/dev/null || continue
			IFS= read -r actual <"$f" 2>/dev/null
			[ "$actual" = "$mx" ] && [ "$actual" -gt "$old" ] && applied=1
		done
	fi
	ST_CHARGE_APPLIED=$applied
	[ "$applied" = "0" ] && [ "$controls" -gt 0 ] && [ "$all_at_max" = "1" ] && ST_CHARGE_APPLIED=2
	if [ "$applied" = "1" ]; then
		ST_CHARGE_WARNED=0
	elif [ "$ST_CHARGE_APPLIED" = "2" ]; then
		[ "${ST_CHARGE_WARNED:-0}" = "2" ] || log "charging limit already at negotiated maximum; no Astra input cap to release"
		ST_CHARGE_WARNED=2
	else
		[ "${ST_CHARGE_WARNED:-0}" = "1" ] || log "charging limit request failed: no writable current-limit node accepted negotiated maximum=${mx:-unknown}"
		ST_CHARGE_WARNED=1
	fi
}
charge_off() {
	if [ -s "$STATE/charge.orig" ]; then
		while IFS='=' read -r f old; do
			[ -w "$f" ] && [ -n "$old" ] && echo "$old" >"$f" 2>/dev/null
		done <"$STATE/charge.orig"
	fi
	# A later plug-in must snapshot the then-current defaults again.
	rm -f "$STATE/charge.orig" 2>/dev/null
	ST_CHARGE_APPLIED=0
}
charge_keep() {
	[ "$ST_CHARGE_APPLIED" = "1" ] || return 0
	charge_online || return 0
	mx=0
	IFS= read -r mx <"$USB/current_max" 2>/dev/null
	case "$mx" in ''|*[!0-9]*) mx=0 ;; esac
	[ "$mx" -gt 0 ] || { ST_CHARGE_APPLIED=0; return 0; }
	controls=0
	failed=0
	for f in "$USB/input_current_limit" "$BATT/input_current_limit"; do
		[ -r "$f" ] && [ -w "$f" ] || continue
		IFS= read -r old <"$f" 2>/dev/null
		case "$old" in ''|*[!0-9]*) continue ;; esac
		controls=$((controls + 1))
		[ "$old" -ge "$mx" ] && continue
		echo "$mx" >"$f" 2>/dev/null || { failed=1; continue; }
		IFS= read -r actual <"$f" 2>/dev/null
		[ "$actual" = "$mx" ] && [ "$actual" -gt "$old" ] || failed=1
	done
	[ "$controls" -gt 0 ] && [ "$failed" = "0" ] || ST_CHARGE_APPLIED=0
}
charge_online() {
	IFS= read -r s <"$BATT/status" 2>/dev/null
	[ "$s" = "Charging" ] || [ "$s" = "Full" ]
}
# ---- Scene 调度接管检测：Scene 在跑，且给当前前台应用下发了功耗模式 ----
SCENE_POWERCFG=/data/data/com.omarea.vtools/shared_prefs/powercfg.xml
SCENE_GAMES=/data/data/com.omarea.vtools/shared_prefs/games.xml
scene_running() {
	ps -A 2>/dev/null | grep -q "com.omarea.vtools"
}
scene_mode_for() { # scene_mode_for PKG -> 模式（空 = 未接管）
	[ -z "$1" ] && return 0
	[ -r "$SCENE_POWERCFG" ] || return 0
	sed -n "s#.*<string name=\"$1\">\([a-z]*\)</string>.*#\1#p" "$SCENE_POWERCFG" 2>/dev/null | head -1
}
scene_takes_over() {
	[ -z "$1" ] && return 1
	scene_running || return 1
	m=$(scene_mode_for "$1")
	case "$m" in ''|ignore|ignored|igoned) return 1 ;; esac
	return 0
}

# ---- 电流/功耗：本机 current_now 是单电芯 mA（双电芯需 ×2），
#      所以直接用电量计 charge_counter 的差值算真实电流，单位无关 ----
CC_LAST=0
CC_AT=0
CURR_MA=0        # 正=放电，负=充电
AVG_MA=0
DIS_UAH=0        # 本次放电累计（µAh）
DIS_SEC=0        # 本次放电累计时长（s）
cc_sample() {
	now=${TICK_NOW:-$(date +%s)}
	cc=0
	IFS= read -r cc <"$BATT/charge_counter" 2>/dev/null
	case "$cc" in ''|*[!0-9]*) cc=0 ;; esac
	[ "$cc" -le 0 ] && return 0
	case "$CC_LAST" in ''|*[!0-9]*) CC_LAST=0 ;; esac
	case "$CC_AT" in ''|*[!0-9]*) CC_AT=0 ;; esac
	if [ "$CC_LAST" -le 0 ] || [ "$CC_AT" -le 0 ]; then
		CC_LAST=$cc
		CC_AT=$now
		CURR_MA=0
		AVG_MA=0
		return 0
	fi
	dt=$((now - CC_AT))
	# The gauge updates coarsely; keep one baseline for a full minute. A long gap
	# is a suspend/restart boundary, not a valid average-power interval.
	[ "$dt" -lt 60 ] && return 0
	if [ "$dt" -gt 180 ]; then
		CC_LAST=$cc
		CC_AT=$now
		CURR_MA=0
		AVG_MA=0
		DIS_UAH=0
		DIS_SEC=0
		return 0
	fi
	dc=$((CC_LAST - cc))            # µAh，正=放电
	CURR_MA=$(( dc * 3600 / dt / 1000 ))
	# 电量计校准/满电修正会产生离谱差值，直接丢弃
	[ "$CURR_MA" -gt 12000 ] && CURR_MA=0
	[ "$CURR_MA" -lt -12000 ] && CURR_MA=0
	CC_LAST=$cc
	CC_AT=$now
	if [ "$CURR_MA" -gt 0 ]; then
		DIS_UAH=$(( DIS_UAH + dc ))
		DIS_SEC=$(( DIS_SEC + dt ))
	else
		# 插电或电量计转为充电方向时重置本次放电会话
		DIS_UAH=0
		DIS_SEC=0
	fi
	AVG_MA=0
	# 用至少五分钟的样本估算整机平均电流，避免启动瞬态主导结果。
	if [ "$DIS_SEC" -ge 300 ]; then
		AVG_MA=$(( DIS_UAH * 3600 / DIS_SEC / 1000 ))
	fi
}
batt_mv() {
	VB_MV=3800
	IFS= read -r v <"$BATT/voltage_now" 2>/dev/null
	case "$v" in ''|*[!0-9]*) ;; *) VB_MV=$(( v / 1000 )) ;; esac
}
# 功率（毫瓦）：放电用电量计差分 × 双芯电池电压；充电用 USB 输入侧的实测值。
pack_mv() {
	batt_mv
	PACK_MV=$VB_MV
	[ "$CFG_DUAL_COMP" = "1" ] && PACK_MV=$(( VB_MV * 2 ))
}
power_mw() {
	PMW=0
	st=""
	IFS= read -r st <"$BATT/status" 2>/dev/null
	if [ "$st" = "Charging" ] || [ "$st" = "Full" ]; then
		# power_supply exposes current_now in µA and voltage_now in µV.
		# Compute at the USB input; battery current is not charger input current.
		IFS= read -r iu <"$USB/current_now" 2>/dev/null
		IFS= read -r vu <"$USB/voltage_now" 2>/dev/null
		case "$iu" in ''|*[!0-9-]*) iu=0 ;; esac
		case "$vu" in ''|*[!0-9]*) vu=0 ;; esac
		[ "$iu" -lt 0 ] && iu=$(( -iu ))
		# Scale before multiplying: Android sh uses 32-bit arithmetic on this ROM.
		[ "$iu" -gt 0 ] && [ "$vu" -gt 0 ] && PMW=$(( (iu / 1000) * (vu / 1000) / 1000 ))
		return 0
	fi
	cm=${CURR_MA:-0}
	case "$cm" in ''|*[!0-9-]*) cm=0 ;; esac
	[ "$cm" -lt 0 ] && cm=$(( -cm ))
	pack_mv
	[ "$cm" -gt 0 ] && [ "$PACK_MV" -gt 0 ] && PMW=$(( cm * PACK_MV / 1000 ))
}
avg_power_tick() { # 平滑的当前/平均功耗（毫瓦）
	st=""
	IFS= read -r st <"$BATT/status" 2>/dev/null
	case "$st" in Charging|Full) mode=charging ;; *) mode=discharging ;; esac
	if [ "$mode" != "${ST_AVG_MODE:-}" ]; then
		ST_AVG_MODE=$mode
		ST_AVG_MW=0
		ST_AVG_AT=0
	fi
	now=${TICK_NOW:-$(date +%s)}
	at=${ST_AVG_AT:-0}
	case "$at" in ''|*[!0-9]*) at=0 ;; esac
	[ $((now - at)) -lt 30 ] && return 0
	power_mw
	ST_AVG_AT=$now
	[ "$PMW" -le 0 ] && return 0
	case "${ST_AVG_MW:-}" in ''|*[!0-9]*|0) ST_AVG_MW=$PMW ;; *) ST_AVG_MW=$(( (ST_AVG_MW * 9 + PMW) / 10 )) ;; esac
}
# 充电功率（毫瓦）：只有“确实在充电”时才非 0。
# 之前直接把 power_mw 当充电功率：没插电时它算的是放电功率，于是电池页在
# 未充电状态下也会显示一个“充电功率”。另外部分充电器/PD 场景下 usb/current_now
# 不刷新，这里退回电池侧（整组电压）估算，避免充电中一直显示 0.0 W。
charge_power_mw() {
	CPMW=0
	_cst=""
	IFS= read -r _cst <"$BATT/status" 2>/dev/null
	_chg=0
	[ "$_cst" = "Charging" ] && _chg=1
	if [ "$_chg" = "0" ] && [ "$_cst" != "Full" ]; then
		_bi=0
		IFS= read -r _bi <"$BATT/current_now" 2>/dev/null
		case "$_bi" in ''|*[!0-9-]*) _bi=0 ;; esac
		[ "$_bi" -lt 0 ] && _chg=1   # 负电流 = 流入电池
	fi
	[ "$_chg" = "1" ] || return 0
	_mw=0
	iu=0
	vu=0
	IFS= read -r iu <"$USB/current_now" 2>/dev/null
	IFS= read -r vu <"$USB/voltage_now" 2>/dev/null
	case "$iu" in ''|*[!0-9-]*) iu=0 ;; esac
	case "$vu" in ''|*[!0-9]*) vu=0 ;; esac
	[ "$iu" -lt 0 ] && iu=$(( -iu ))
	[ "$iu" -gt 0 ] && [ "$vu" -gt 0 ] && _mw=$(( (iu / 1000) * (vu / 1000) / 1000 ))
	if [ "$_mw" -le 0 ]; then
		_bi=0
		IFS= read -r _bi <"$BATT/current_now" 2>/dev/null
		case "$_bi" in ''|*[!0-9-]*) _bi=0 ;; esac
		# 只认负电流（流入电池）；正电流表示整机在净放电，不能算充电功率
		if [ "$_bi" -lt 0 ]; then _bi=$(( -_bi )); else _bi=0; fi
		pack_mv
		[ "$_bi" -gt 0 ] && [ "$PACK_MV" -gt 0 ] && _mw=$(( _bi * PACK_MV / 1000 ))
	fi
	[ "$_mw" -gt 300000 ] && _mw=0   # >300W 视为节点异常
	CPMW=$_mw
}
bypass_on() {
	[ -s "$STATE/bypass.list" ] || find /sys/class/power_supply /sys/class/oplus_chg -maxdepth 3 -type f -name '*bypass*' 2>/dev/null >"$STATE/bypass.list"
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		IFS= read -r v <"$f" 2>/dev/null
		[ "$v" = "1" ] && return 0
	done <"$STATE/bypass.list"
	return 1
}
charge_tick() {
	if ! charge_online; then
		[ "$CFG_CHARGE_NOW" = "1" ] && { cfg_set CHARGE_NOW 0; CFG_CHARGE_NOW=0; }
		charge_off
		ST_CHARGE_START=0
		ST_CHARGE_GUARD=0
		return 0
	fi
	[ "$ST_CHARGE_START" = "0" ] && ST_CHARGE_START=${TICK_NOW:-$(date +%s)}
	want=0
	[ "$CFG_CHARGE_AUTO" = "1" ] && want=1
	[ "$CFG_CHARGE_NOW" = "1" ] && want=1
	[ "$want" = "1" ] || { charge_off; ST_CHARGE_GUARD=0; return 0; }
	if bypass_on; then
		charge_off
		ST_CHARGE_GUARD=0
		return 0
	fi
	real_batt_md
	if [ "$RB" -gt 0 ] && [ "$RB" -ge "$CFG_CHARGE_TEMP_CUT" ]; then
		charge_off
		ST_CHARGE_GUARD=1
		return 0
	fi
	# 90% 之后交还官方阶梯充电（保护电池）
	cap=0
	IFS= read -r cap <"$BATT/capacity" 2>/dev/null
	case "$cap" in ''|*[!0-9]*) cap=0 ;; esac
	if [ "$cap" -ge 90 ]; then
		charge_off
		ST_CHARGE_GUARD=2
		return 0
	fi
	ST_CHARGE_GUARD=0
	[ "$ST_CHARGE_APPLIED" = "1" ] || charge_on
}

# ---------------------------------------------------------------- 调度
# 本机（ColorOS 17）scaling_max_freq 会被性能 HAL 立刻覆盖，
# 真正生效的入口是 Qualcomm msm_performance 的 cpu_max_freq。
CAP_NODE=/sys/kernel/msm_performance/parameters/cpu_max_freq
SAVE_CAPS="0:1785600 1:1785600 2:1785600 3:1785600 4:1785600 5:1785600 6:2246400 7:2246400"
sched_policy() {
	for p in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -d "$p" ] || continue
		IFS= read -r rc <"$p/related_cpus" 2>/dev/null
		case " $rc " in
		*" 6 "*|*" 7 "*) echo "$p prime" ;;
		*) echo "$p little" ;;
		esac
	done
}
caps_read() {
	CAPS=CAPPAD=""
	[ -r "$CAP_NODE" ] && IFS= read -r CAPS <"$CAP_NODE" 2>/dev/null
	while [ "${CAPS% }" != "$CAPS" ]; do CAPS=${CAPS% }; done
}
caps_write() {
	w=$1
	while [ "${w% }" != "$w" ]; do w=${w% }; done
	[ -w "$CAP_NODE" ] || return 1
	echo "$w" >"$CAP_NODE" 2>/dev/null || return 1
	_cap_want=$(printf '%s' "$w" | tr -d ' ,')
	_cap_got=$(cat "$CAP_NODE" 2>/dev/null | tr -d ' ,')
	[ -n "$_cap_want" ] && [ "$_cap_got" = "$_cap_want" ]
}
LITTLE_CAP=1785600
PRIME_CAP=2246400
clamp_freq() { # clamp_freq POLICY TARGET -> CLAMPED（贴到该 policy 可用频点）
	CLAMPED=$2
	av=""
	IFS= read -r av <"$1/scaling_available_frequencies" 2>/dev/null
	[ -z "$av" ] && return 0
	best=""
	for f in $av; do
		if [ "$f" -le "$2" ]; then
			if [ -z "$best" ]; then best=$f; elif [ "$f" -gt "$best" ]; then best=$f; fi
		fi
	done
	[ -n "$best" ] && CLAMPED=$best
}
cap_snapshot() {
	: >"$STATE/caps.orig"
	for p in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -d "$p" ] || continue
		v=""
		IFS= read -r v <"$p/scaling_max_freq" 2>/dev/null
		[ -n "$v" ] && echo "$p/scaling_max_freq=$v" >>"$STATE/caps.orig"
	done
}
save_on() {
	[ -s "$STATE/caps.orig" ] || cap_snapshot
	[ -n "$CAP_BASE" ] || { caps_read; CAP_BASE=$CAPS; }
	CAP_APPLIED=0
	caps_write "$SAVE_CAPS" && CAP_APPLIED=1
	for p in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -d "$p" ] || continue
		rc=""
		IFS= read -r rc <"$p/related_cpus" 2>/dev/null
		case " $rc " in
		*" 6 "*|*" 7 "*) tgt=$PRIME_CAP ;;
		*) tgt=$LITTLE_CAP ;;
		esac
		clamp_freq "$p" "$tgt"
		if [ -w "$p/scaling_max_freq" ]; then
			echo "$CLAMPED" >"$p/scaling_max_freq" 2>/dev/null
			IFS= read -r _cap_readback <"$p/scaling_max_freq" 2>/dev/null
			[ "$_cap_readback" = "$CLAMPED" ] && CAP_APPLIED=1
		fi
	done
	if [ "$CAP_APPLIED" = "1" ]; then
		ST_SAVE_APPLIED=1
		ST_CAP_WARNED=0
	else
		ST_SAVE_APPLIED=0
		[ "${ST_CAP_WARNED:-0}" = "1" ] || log "CPU cap request failed: msm_performance and cpufreq nodes did not retain requested values"
		ST_CAP_WARNED=1
	fi
}
save_off() {
	[ -n "$CAP_BASE" ] && caps_write "$CAP_BASE"
	if [ -s "$STATE/caps.orig" ]; then
		while IFS='=' read -r f v; do
			[ -w "$f" ] || continue
			# 快照录到的如果是被压过的值，就用硬件上限兜底
			p=${f%/scaling_max_freq}
			hw=""
			IFS= read -r hw <"$p/cpuinfo_max_freq" 2>/dev/null
			case "$hw" in ''|*[!0-9]*) hw="" ;; esac
			if [ -n "$hw" ] && [ -n "$v" ] && [ "$v" -lt "$hw" ]; then
				echo "$hw" >"$f" 2>/dev/null
			else
				[ -n "$v" ] && echo "$v" >"$f" 2>/dev/null
			fi
		done <"$STATE/caps.orig"
	fi
	ST_SAVE_APPLIED=0
}
gpu_dir() {
	for d in /sys/class/devfreq/*; do
		case "$d" in *kgsl*|*gpu*|*gpufreq*) echo "$d"; return 0 ;; esac
	done
	return 1
}
# 真正的 GPU Boost 开关：kgsl 的 dcvs_boost（1=系统默认提升，0=禁用）
kgsl_boost_node() {
	for d in /sys/class/kgsl/kgsl-3d0 /sys/class/kgsl/*; do
		[ -e "$d/dcvs_boost" ] && { echo "$d/dcvs_boost"; return 0; }
	done
	return 1
}
GPU_IDLE_MIN=160000000
GPU_DISABLED_MAX=832000000
gpu_tick() {
	dis=$CFG_DISABLE_GPU_BOOST
	# 官调限频开启时强制禁用 GPU Boost
	[ "$ST_SAVE_APPLIED" = "1" ] && dis=1
	bn=$(kgsl_boost_node)
	if [ -n "$bn" ]; then
		current=""
		IFS= read -r current <"$bn" 2>/dev/null
		if [ "$dis" = "1" ]; then
			[ -n "$GPU_BOOST_ORIG" ] || GPU_BOOST_ORIG=$current
			[ "$current" = "0" ] || echo 0 >"$bn" 2>/dev/null
			IFS= read -r current <"$bn" 2>/dev/null
			if [ "$current" = "0" ]; then
				ST_GPU_STATE=disabled
				ST_GPU_WARNED=0
			else
				ST_GPU_STATE=failed
				[ "${ST_GPU_WARNED:-0}" = "1" ] || log "GPU DCVS boost node did not accept disable request: $bn value=${current:-unknown}"
				ST_GPU_WARNED=1
			fi
		elif [ -n "$GPU_BOOST_ORIG" ]; then
			[ "$current" = "$GPU_BOOST_ORIG" ] || echo "$GPU_BOOST_ORIG" >"$bn" 2>/dev/null
			IFS= read -r current <"$bn" 2>/dev/null
			[ "$current" = "$GPU_BOOST_ORIG" ] && ST_GPU_STATE=default || ST_GPU_STATE=failed
		else
			ST_GPU_STATE=default
		fi
		return 0
	fi
	# 兜底（没有 dcvs_boost 的机器）：压上限
	gd=$(gpu_dir) || { ST_GPU_STATE=none; return 0; }
	if [ "$dis" = "1" ] && [ "$ST_GPU_STATE" != disabled ]; then
		[ -z "$GPU_ORIG_MIN" ] && IFS= read -r GPU_ORIG_MIN <"$gd/min_freq" 2>/dev/null
		[ -z "$GPU_ORIG_MAX" ] && IFS= read -r GPU_ORIG_MAX <"$gd/max_freq" 2>/dev/null
		echo "$GPU_IDLE_MIN" >"$gd/min_freq" 2>/dev/null
		echo "$GPU_DISABLED_MAX" >"$gd/max_freq" 2>/dev/null
		ST_GPU_STATE=disabled
	elif [ "$dis" != "1" ] && [ "$ST_GPU_STATE" = disabled ]; then
		[ -n "$GPU_ORIG_MIN" ] && echo "$GPU_ORIG_MIN" >"$gd/min_freq" 2>/dev/null
		[ -n "$GPU_ORIG_MAX" ] && echo "$GPU_ORIG_MAX" >"$gd/max_freq" 2>/dev/null
		ST_GPU_STATE=default
	fi
}
foreground_pkg() {
	FP=
	line=$(dumpsys activity activities 2>/dev/null | grep -m1 -E 'ResumedActivity|mResumedActivity|topResumedActivity')
	[ -z "$line" ] && line=$(dumpsys window 2>/dev/null | grep -m1 mCurrentFocus)
	for tok in $line; do
		case "$tok" in
		*/*) FP=${tok%%/*}; break ;;
		esac
	done
	case "$FP" in u0*|*[!A-Za-z0-9_.]*) FP= ;; esac
	echo "$FP"
}
is_game() {
	[ -z "$1" ] && return 1
	grep -qx "$1" "$MODDIR/config/games.list" 2>/dev/null && return 0
	grep -qx "$1" "$STATE/settings/games.list" 2>/dev/null && return 0
	# 也认 Scene 自己的游戏标记
	[ -r "$SCENE_GAMES" ] && grep -q "name=\"$1\" value=\"true\"" "$SCENE_GAMES" 2>/dev/null && return 0
	return 1
}
sched_tick() {
	if [ "$CFG_SAVE_ENABLED" = "1" ]; then
		now=${TICK_NOW:-$(date +%s)}
		scr_on=1
		screen_on || scr_on=0
		# 熄屏时不跑前台 dumpsys（省唤醒），保留熄屏前的游戏/Scene 判断
		if [ "$scr_on" = "1" ] && [ $((now - ${FG_AT:-0})) -ge 10 ]; then
			FG_AT=$now
			p=$(foreground_pkg)
			ST_FG_PKG=$p
			if is_game "$p"; then ST_FG_GAME=1; else ST_FG_GAME=0; fi
			if scene_takes_over "$p"; then ST_SCENE_TAKEOVER=1; else ST_SCENE_TAKEOVER=0; fi
			# 横屏非视频应用（游戏/全屏应用）→ 交还官方调度
			if [ "$ST_FG_GAME" = "0" ] && ! is_video_pkg "$p" && screen_landscape; then
				ST_FG_GAME=1
			fi
		fi
		# 游戏 / Scene 调度接管 → 立即让出，不和官方/Scene 抢
		if [ "$ST_FG_GAME" = "1" ] || [ "$ST_SCENE_TAKEOVER" = "1" ]; then
			[ "$ST_SAVE_APPLIED" = "1" ] && save_off
		elif [ "$scr_on" = "1" ] || [ "$ST_SAVE_APPLIED" != "1" ]; then
			# 熄屏且限频已生效时不再每 tick 重写节点（每次 save_on 有几十次 fork）
			save_on
		fi
	else
		[ "$ST_SAVE_APPLIED" = "1" ] && save_off
		ST_FG_GAME=0
		ST_SCENE_TAKEOVER=0
	fi
	gpu_tick
}

# ---------------------------------------------------------------- 掉信号保护
ST_MODEM_BAD=0
ST_OP_OK=0      # 本次开机是否见过正常运营商信息（避免开机/无覆盖误判）
ST_RADIO_LATCH=0
modem_guard_tick() {
	if [ "$CFG_THERMAL_MODE" = "official" ]; then
		ST_MODEM_BAD=0
		return 0
	fi
	# 这个检查要 fork settings/getprop，30 秒一次足够，避免熄屏时被它反复唤醒
	now=${TICK_NOW:-$(date +%s)}
	elapsed=$((now - ${MG_AT:-0}))
	[ "$elapsed" -lt 30 ] && return 0
	MG_AT=$now
	air=$(settings get global airplane_mode_on 2>/dev/null)
	[ "$air" = "1" ] && { ST_MODEM_BAD=0; return 0; }
	s=$(getprop gsm.sim.state 2>/dev/null)
	op=""
	case "$s" in
	*READY*|*LOADED*)
		# SIM 已加载：再用运营商名判断是否真的注册上了网络。
		# 掉信号时 SIM 仍是 LOADED，只是注册丢失、运营商变空，旧逻辑只看 ABSENT 抓不到。
		op=$(getprop gsm.operator.alpha 2>/dev/null)
		case "$op" in
		*[!,\ ]*) ST_OP_OK=1; ST_MODEM_BAD=0 ;;
		*)
			if [ "$ST_OP_OK" = "1" ]; then
				ST_MODEM_BAD=$(( ${ST_MODEM_BAD:-0} + elapsed ))
			else
				ST_MODEM_BAD=0
			fi
			;;
		esac
		;;
	*ABSENT*)
		[ "$ST_OP_OK" = "1" ] && ST_MODEM_BAD=$(( ${ST_MODEM_BAD:-0} + elapsed )) || ST_MODEM_BAD=0
		;;
	*) ST_MODEM_BAD=0 ;; # Unknown during boot is not evidence that the SIM disappeared.
	esac
	[ "${ST_MODEM_BAD:-0}" -ge 90 ] || return 0
	log "modem guard: radio lost ${ST_MODEM_BAD}s (sim=[$s] op=[$op]) -> revert thermal to official"
	ST_RADIO_LATCH=1
	thermal_all_clear
	cfg_set THERMAL_MODE official
	CFG_THERMAL_MODE=official
	ST_MODEM_BAD=0
}

VIDEO_PKGS="com.bilibili.app.in tv.danmaku.bili com.google.android.youtube com.tencent.qqlive com.qiyi.video com.youku.phone com.netflix.mediaclient com.mxtech.videoplayer.ad org.videolan.vlc com.ss.android.ugc.aweme com.coloros.video"
is_video_pkg() {
	case " $VIDEO_PKGS " in *" $1 "*) return 0 ;; esac
	return 1
}
screen_landscape() {
	dumpsys window 2>/dev/null | grep -m1 -o "mRotation=[0-9]" | grep -q "mRotation=[13]"
}
music_playing() {
	dumpsys media_session 2>/dev/null | grep -q "state=PlaybackState {state=3"
}
in_call() {
	dumpsys telephony.registry 2>/dev/null | grep -qE 'mCallState=[12]'
}
DS_AT=0
DS_CHECK_AT=0
DS_VERIFY_AT=0
DEEP_IDLE_WAIT=20
DEEP_IDLE_FILE="$STATE/.doze.active"
deep_sleep_enter() {
	[ "$ST_DS_ACTIVE" = "1" ] && return 0
	if dumpsys deviceidle force-idle >/dev/null 2>&1; then
		ST_DS_ACTIVE=1
		ST_DS_LAST=${TICK_NOW:-$(date +%s)}
		DS_VERIFY_AT=$ST_DS_LAST
		: >"$DEEP_IDLE_FILE" 2>/dev/null
		log "deep sleep: doze forced after $((ST_DS_LAST - DS_AT))s screen off"
		st_save
		return 0
	fi
	log "deep sleep: force-idle failed"
	return 1
}
deep_sleep_off() { # deep_sleep_off [原因]
	DS_AT=0
	DS_CHECK_AT=0
	rm -f "$DEEP_IDLE_FILE" 2>/dev/null
	[ "$ST_DS_ACTIVE" = "1" ] || return 0
	dumpsys deviceidle unforce >/dev/null 2>&1
	ST_DS_ACTIVE=0
	log "deep sleep: released${1:+ ($1)}"
}
deep_sleep_tick() {
	if [ "$CFG_DEEP_SLEEP" != "1" ]; then
		deep_sleep_off "disabled"
		return 0
	fi
	# 熄屏/充电用 sysfs 判断，代价极低，每 tick 都做
	if screen_on; then
		deep_sleep_off "screen on"
		return 0
	fi
	if charge_online; then
		deep_sleep_off "charging"
		return 0
	fi
	now=${TICK_NOW:-$(date +%s)}
	# 音乐/通话检查节流：倒计时阶段 15 秒一次，进入 Doze 后 60 秒一次。
	# 这两个 dumpsys 很贵，之前每 4 秒跑一次，会把 Doze 省下的电又吃回去。
	_chk=15
	[ "$ST_DS_ACTIVE" = "1" ] && _chk=60
	if [ $((now - ${DS_CHECK_AT:-0})) -ge "$_chk" ]; then
		DS_CHECK_AT=$now
		if music_playing || in_call; then
			deep_sleep_off "music/call"
			return 0
		fi
	fi
	if [ "$ST_DS_ACTIVE" = "1" ]; then
		# 每 5 分钟确认强制 idle 还在（部分系统服务会把它顶掉）
		if [ $((now - ${DS_VERIFY_AT:-0})) -ge 300 ]; then
			DS_VERIFY_AT=$now
			case "$(dumpsys deviceidle 2>/dev/null | grep -m1 -o 'mState=[A-Z_]*')" in
			mState=IDLE*|mState=IDLE_MAINTENANCE*) : ;;
			*)
				log "deep sleep: doze state lost, re-forcing"
				ST_DS_ACTIVE=0
				deep_sleep_enter
				;;
			esac
		fi
		return 0
	fi
	[ "$DS_AT" = "0" ] && { DS_AT=$now; return 0; }
	[ $((now - DS_AT)) -lt "$DEEP_IDLE_WAIT" ] && return 0
	deep_sleep_enter
}

# ---------------------------------------------------------------- 使用统计（Scene 式自采样）
USAGE_DB="$STATE/usage.db"
screen_on() {
	found=0
	for f in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness; do
		[ -r "$f" ] || continue
		IFS= read -r b <"$f" 2>/dev/null
		case "$b" in ''|*[!0-9]*) continue ;; esac
		found=1
		[ "$b" -gt 0 ] && return 0
	done
	[ "$found" = "1" ] && return 1
	return 0
}
usage_sample() {
	now=${TICK_NOW:-$(date +%s)}
	last_at=${ST_USAGE_AT:-0}
	case "$last_at" in ''|*[!0-9]*) last_at=0 ;; esac
	[ $((now - last_at)) -lt 30 ] && return 0
	ST_USAGE_AT=$now
	screen_on || return 0
	p=$(foreground_pkg)
	[ -z "$p" ] && return 0
	# 本次 30 秒里的电量消耗（µAh）：放电时用库仑计电流，充电时用 USB 输入折算成等效电流
	add=0
	eff=0
	bs=""
	IFS= read -r bs <"$BATT/status" 2>/dev/null
	if [ "$bs" = "Charging" ] || [ "$bs" = "Full" ]; then
		iu=0; vu=0
		IFS= read -r iu <"$USB/current_now" 2>/dev/null
		IFS= read -r vu <"$USB/voltage_now" 2>/dev/null
		case "$iu" in ''|*[!0-9-]*) iu=0 ;; esac; iu=${iu#-}
		case "$vu" in ''|*[!0-9-]*) vu=0 ;; esac
		umw=$(( (iu / 1000) * (vu / 1000) / 1000 ))
		# Convert USB power to equivalent pack current; do_apps multiplies by PACK_MV later.
		pack_mv
		[ "$umw" -gt 0 ] && [ "${PACK_MV:-0}" -gt 0 ] && eff=$(( umw * 1000 / PACK_MV ))
	else
		eff=${CURR_MA:-0}
		case "$eff" in ''|*[!0-9-]*) eff=0 ;; esac
	fi
	[ "$eff" -gt 0 ] && add=$(( eff * 30 * 1000 / 3600 ))
	new="$STATE/usage.db.new"
	: >"$new"
	found=0
	[ -s "$USAGE_DB" ] && while IFS='|' read -r pk sec at uah; do
		[ -z "$pk" ] && continue
		case "$uah" in ''|*[!0-9]*) uah=0 ;; esac
		if [ "$pk" = "$p" ]; then
			echo "$pk|$((sec + 30))|$now|$((uah + add))" >>"$new"
			found=1
		else
			echo "$pk|$sec|$at|$uah" >>"$new"
		fi
	done <"$USAGE_DB"
	[ "$found" = "0" ] && echo "$p|30|$now|$add" >>"$new"
	# 只保留最近 40 条
	tail -n 40 "$new" >"$USAGE_DB" 2>/dev/null
	rm -f "$new"
}

# ---------------------------------------------------------------- 统一 tick
tick() {
	# 每轮只取一次时间，内部函数共用（少 5-6 次 date fork）
	TICK_NOW=$(date +%s)
	cfg_load
	st_load
	# 官方温控 + 熄屏：热区缓存只用于显示/伪装，没必要每轮校验（省 ~20 次读）
	if [ "$CFG_THERMAL_MODE" != "official" ] || screen_on; then
		ensure_zone_cache
	fi
	# 官方温控且没有任何待还原状态时，不需要拿锁做串行（省掉每 tick 的 mkdir/rmdir）
	if [ "$CFG_THERMAL_MODE" != "official" ] || [ "$ST_MASK_ACTIVE" = "1" ] || [ "$ST_THERMAL_OFF" = "1" ]; then
		if mode_lock_acquire; then
			# The WebUI and daemon share one mode transaction. Reload after locking so a
			# stale daemon read cannot immediately undo a just-committed user selection.
			cfg_load
			st_load
			case "$CFG_THERMAL_MODE" in
			mask)
				[ "$ST_THERMAL_OFF" = "1" ] && thermal_off_off
				mask_tick
				;;
			off)
				[ "$ST_MASK_ACTIVE" = "1" ] && mask_off
				thermal_off_keep
				;;
			*)
				[ "$ST_THERMAL_OFF" = "1" ] && thermal_off_off
				[ "$ST_MASK_ACTIVE" = "1" ] && mask_off
				;;
			esac
			modem_guard_tick
			st_save
			mode_lock_release
		fi
	fi
	cfg_load
	st_load
	batt_mv
	cc_sample
	charge_tick
	charge_keep
	avg_power_tick
	sched_tick
	deep_sleep_tick
	ltpo_tick
	[ -f "$DEV_CACHE" ] || cache_device
	usage_sample
	update_prop
	# Doze 期间状态基本不变，5 分钟落一次盘即可；状态切换时 deep_sleep_* 会主动写
	if [ "$ST_DS_ACTIVE" = "1" ]; then
		ST_SAVE_N=$(( ${ST_SAVE_N:-0} + 1 ))
		if [ "$ST_SAVE_N" -ge 30 ]; then
			ST_SAVE_N=0
			st_save
		fi
	else
		ST_SAVE_N=0
		st_save
	fi
}
update_prop() { # module.prop 描述只放“功能状态快捷查看”，不再写模块介绍
	now=${TICK_NOW:-$(date +%s)}
	[ $((now - ${ST_PROP_AT:-0})) -lt 300 ] && return 0
	ST_PROP_AT=$now
	case "$CFG_THERMAL_MODE" in
	mask) tw="伪装" ;;
	off) tw="去温控" ;;
	*) tw="官方" ;;
	esac
	[ "$ST_CHARGE_APPLIED" = "1" ] && cw="已解除限流" || cw="官方"
	if [ "$CFG_SAVE_ENABLED" = "1" ]; then
		if [ "$ST_SAVE_APPLIED" = "1" ]; then sw="限频中"; else sw="限频(未生效)"; fi
	else
		sw="关"
	fi
	# 模块页描述只保留三项功能状态（用户要求）
	sed -i "s@^description=.*@description=温控 $tw · 充电 $cw · 调度 $sw@" \
		"$MODDIR/module.prop" 2>/dev/null
}
