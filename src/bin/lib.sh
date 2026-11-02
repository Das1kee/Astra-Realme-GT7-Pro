#!/system/bin/sh
# Astra — Realme GT7 Pro (RMX5010) 温控 / 电池 / 调度  核心库
# Beta0.1.06 · Dasikee
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

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >>"$LOGS/astra.log" 2>/dev/null; }

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
		SCENE_TAKEOVER) ST_SCENE_TAKEOVER=$v ;;
		CC_LAST) CC_LAST=$v ;;
		CC_AT) CC_AT=$v ;;
		AVG_MA) AVG_MA=$v ;;
		CURR_MA) CURR_MA=$v ;;
		DIS_UAH) DIS_UAH=$v ;;
		DIS_SEC) DIS_SEC=$v ;;
		DS_ACTIVE) ST_DS_ACTIVE=$v ;;
		MODEM_BAD) ST_MODEM_BAD=$v ;;
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
		echo "SCENE_TAKEOVER=${ST_SCENE_TAKEOVER:-0}"
		echo "CC_LAST=$CC_LAST"
		echo "CC_AT=$CC_AT"
		echo "AVG_MA=$AVG_MA"
		echo "CURR_MA=$CURR_MA"
		echo "DIS_UAH=$DIS_UAH"
		echo "DIS_SEC=$DIS_SEC"
		echo "DS_ACTIVE=${ST_DS_ACTIVE:-0}"
		echo "MODEM_BAD=${ST_MODEM_BAD:-0}"
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
zone_idx() {
	for d in "$THERMAL"/thermal_zone*; do
		R=
		IFS= read -r R <"$d/type" 2>/dev/null
		[ "$R" = "$1" ] && { echo "${d##*thermal_zone}"; return 0; }
	done
	return 1
}
build_zone_cache() {
	: >"$ZONE_SPOOF"
	for t in shell_front shell_frame shell_back socd sys-therm-0 sys-therm-2 sys-therm-4 sys-therm-5 sys-therm-6; do
		i=$(zone_idx "$t" 2>/dev/null)
		[ -n "$i" ] && echo "$t $i" >>"$ZONE_SPOOF"
	done
	for t in cpuss-0-0 cpuss-0-1 cpuss-1-0 cpuss-1-1 gpuss-0 gpuss-2 gpuss-4 gpuss-6 gpuss-7 cpu-0-2-0 cpu-1-1-1; do
		i=$(zone_idx "$t" 2>/dev/null)
		[ -n "$i" ] && echo "$t $i" >>"$ZONE_WITNESS"
	done
	i=$(zone_idx battery 2>/dev/null)
	[ -n "$i" ] && echo "battery $i" >"$ZONE_BATTERY" || : >"$ZONE_BATTERY"
	log "zones: spoof=$(wc -l <"$ZONE_SPOOF") witness=$(wc -l <"$ZONE_WITNESS")"
}
ensure_zone_cache() { [ -s "$ZONE_SPOOF" ] || build_zone_cache; }
ztmp() { # ztmp INDEX -> ZT
	ZT=0
	IFS= read -r ZT <"$THERMAL/thermal_zone$1/temp" 2>/dev/null
	case "$ZT" in ''|*[!0-9-]*) ZT=0 ;; esac
}
emu_set() {
	z="$THERMAL/thermal_zone$1"
	[ -e "$z/emul_temp" ] || return 1
	t=""
	IFS= read -r t <"$z/type" 2>/dev/null
	# 安全线：射频/PA/mmWave/ddr/camera 热区一律不碰，否则可能掉信号
	case "$t" in
	*sdr*|*mmw*|*modem*|*_pa|*pa_*|ddr*|camera*) return 1 ;;
	esac
	echo "$2" >"$z/emul_temp" 2>/dev/null
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
	# 退路：热区（注意电池热区可能正在被伪装，只在万不得已时用）
	IFS= read -r RB <"$THERMAL/thermal_zone$(cat "$ZONE_BATTERY" 2>/dev/null | cut -d' ' -f2)/temp" 2>/dev/null
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
	while read -r _t i; do [ -n "$i" ] && emu_set "$i" 0; done <"$ZONE_SPOOF"
	while read -r _t i; do [ -n "$i" ] && emu_set "$i" 0; done <"$ZONE_BATTERY"
	scene_spoof_off
	ST_MASK_ACTIVE=0
}
mask_on() { # mask_on FAKE_MD
	f="$1"
	while read -r _t i; do [ -n "$i" ] && emu_set "$i" "$f"; done <"$ZONE_SPOOF"
	# 默认：Scene 看到真实电池温度；打开 SCENE_SEES_FAKE 才伪装（热区 + power_supply 节点）
	if [ "$CFG_SCENE_SEES_FAKE" = "1" ]; then
		while read -r _t i; do [ -n "$i" ] && emu_set "$i" "$f"; done <"$ZONE_BATTERY"
	else
		while read -r _t i; do [ -n "$i" ] && emu_set "$i" 0; done <"$ZONE_BATTERY"
	fi
	ST_MASK_ACTIVE=1
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
	pos=$(( $(date +%s) % period ))
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
thermal_off_on() {
	[ -d "$MODDIR/patch" ] || return 0
	: >"$MNT.new"
	while IFS= read -r src; do
		case "$src" in
		*ThermalServiceConfig*|*high_temp_protect*) continue ;;
		esac
		dst=${src#"$MODDIR/patch"}
		[ -f "$dst" ] || continue
		if is_mounted "$dst" || mount --bind "$src" "$dst" 2>/dev/null; then
			echo "$dst" >>"$MNT.new"
		else
			log "bind FAILED $dst"
		fi
	done <<EOF
$(find "$MODDIR/patch" -type f 2>/dev/null)
EOF
	mv -f "$MNT.new" "$MNT" 2>/dev/null
	setprop persist.sys.environment.temp 25 2>/dev/null
	setprop persist.sys.oplus.wifi.sla.game_high_temperature 50 2>/dev/null
	ST_THERMAL_OFF=1
}
thermal_off_off() {
	if [ -s "$MNT" ]; then
		while IFS= read -r dst; do
			[ -n "$dst" ] && is_mounted "$dst" && umount "$dst" 2>/dev/null
		done <"$MNT"
		: >"$MNT"
	fi
	ST_THERMAL_OFF=0
}
thermal_all_clear() { # 官方模式：确保没有任何伪装/挂载残留
	thermal_off_off
	mask_off
	ST_MASK_LATCH=0
}

# ---------------------------------------------------------------- 充电
OPLUS=/sys/class/oplus_chg/battery
charge_snapshot() {
	: >"$STATE/charge.orig"
	chmod 0600 "$STATE/charge.orig" 2>/dev/null
	for f in "$BATT/constant_charge_current_max" "$BATT/input_current_limit" \
		"$USB/input_current_limit" "$USB/current_max" "$OPLUS/fast_charge"; do
		[ -r "$f" ] || continue
		IFS= read -r v <"$f" 2>/dev/null
		[ -n "$v" ] && echo "$f=$v" >>"$STATE/charge.orig"
	done
}
# 满血：输入电流拉到适配器能给的最高值 + 打开快充开关（不改 vendor 的恒流/阶梯算法）
charge_on() {
	[ -s "$STATE/charge.orig" ] || charge_snapshot
	mx=0
	IFS= read -r mx <"$USB/current_max" 2>/dev/null
	case "$mx" in ''|*[!0-9]*) mx=0 ;; esac
	[ -w "$OPLUS/fast_charge" ] && echo 1 >"$OPLUS/fast_charge" 2>/dev/null
	if [ "$mx" -gt 0 ]; then
		[ -w "$USB/input_current_limit" ] && echo "$mx" >"$USB/input_current_limit" 2>/dev/null
		[ -w "$BATT/input_current_limit" ] && echo "$mx" >"$BATT/input_current_limit" 2>/dev/null
	fi
	ST_CHARGE_APPLIED=1
}
charge_off() {
	if [ -s "$STATE/charge.orig" ]; then
		while IFS='=' read -r f old; do
			[ -w "$f" ] && [ -n "$old" ] && echo "$old" >"$f" 2>/dev/null
		done <"$STATE/charge.orig"
	fi
	ST_CHARGE_APPLIED=0
}
charge_online() {
	IFS= read -r s <"$BATT/status" 2>/dev/null
	[ "$s" = "Charging" ] || [ "$s" = "Full" ]
}
# 系统「智能极速充电」是否开启（模块开启时模块优先）
smart_charge_sys() {
	for ns in global system secure; do
		for k in smart_fast_charge smart_charge oplus_smart_charge smart_charging; do
			v=$(settings get "$ns" "$k" 2>/dev/null)
			[ "$v" = "1" ] && return 0
		done
	done
	return 1
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
	case "$m" in ''|igoned) return 1 ;; esac
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
	now=$(date +%s)
	cc=0
	IFS= read -r cc <"$BATT/charge_counter" 2>/dev/null
	case "$cc" in ''|*[!0-9]*) cc=0 ;; esac
	[ "$cc" -le 0 ] && return 0
	if [ "$CC_LAST" -gt 0 ] && [ $((now - CC_AT)) -ge 20 ]; then
		dt=$((now - CC_AT))
		dc=$((CC_LAST - cc))            # µAh，正=放电
		CURR_MA=$(( dc * 3600 / dt / 1000 ))
		# 电量计校准/满电修正会产生离谱差值，直接丢弃
		[ "$CURR_MA" -gt 12000 ] && CURR_MA=0
		[ "$CURR_MA" -lt -12000 ] && CURR_MA=0
		CC_LAST=$cc
		CC_AT=$now
		if [ "$CURR_MA" -gt 0 ]; then
			# 放电会话累计：用于 Scene 同款「平均功耗」
			DIS_UAH=$(( DIS_UAH + dc ))
			DIS_SEC=$(( DIS_SEC + dt ))
			CURR_W=$(( CURR_MA * VB_MV / 1000 ))
		else
			# 插电即重置本次放电会话
			DIS_UAH=0
			DIS_SEC=0
			CURR_W=0
		fi
		AVG_MA=0
		if [ "$DIS_SEC" -gt 0 ]; then
			AVG_MA=$(( DIS_UAH * 3600 / DIS_SEC / 1000 ))
		fi
	else
		CC_LAST=$cc
		CC_AT=$now
	fi
}
batt_mv() {
	VB_MV=3800
	IFS= read -r v <"$BATT/voltage_now" 2>/dev/null
	case "$v" in ''|*[!0-9]*) ;; *) VB_MV=$(( v / 1000 )) ;; esac
}
avg_from_bstats() {
	now=$(date +%s)
	at=${ST_AVG_AT:-0}
	case "$at" in ''|*[!0-9]*) at=0 ;; esac
	[ $((now - at)) -lt 600 ] && return 0
	line=$(dumpsys batterystats --charged 2>/dev/null | grep -m1 "Time on battery:")
	sec=$(printf '%s' "$line" | awk '{s=0; for(i=1;i<=NF;i++){v=$i; n=v+0; if(v~/h$/)s+=n*3600; else if(v~/m$/)s+=n*60; else if(v~/s$/)s+=n}; print s}')
	mah=$(dumpsys batterystats --charged 2>/dev/null | grep -m1 "actual drain:" | sed 's/.*actual drain: *\([0-9][0-9]*\).*/\1/')
	case "$sec" in ''|*[!0-9]*|0) return 0 ;; esac
	case "$mah" in ''|*[!0-9]*|0) return 0 ;; esac
	mv=3850
	IFS= read -r vnow <"$BATT/voltage_now" 2>/dev/null
	case "$vnow" in ''|*[!0-9]*) ;; *) mv=$((vnow / 1000)) ;; esac
	ma=$(( mah * 3600 / sec ))
	ST_AVG_MW=$(( ma * mv / 1000 ))
	ST_AVG_AT=$now
}

# 功率（毫瓦）：双电芯机型电池节点报单芯电压，整组 ×2（与若晴/Scene 同口径）
pack_mv() {
	batt_mv
	PACK_MV=$VB_MV
	[ "$CFG_DUAL_COMP" = "1" ] && PACK_MV=$(( VB_MV * 2 ))
}
power_mw() {
	PMW=0
	st=""
	IFS= read -r st <"$BATT/status" 2>/dev/null
	cm=${CURR_MA:-0}
	case "$cm" in ''|*[!0-9-]*) cm=0 ;; esac
	[ "$cm" -lt 0 ] && cm=$(( -cm ))
	pack_mv
	[ "$cm" -gt 0 ] && [ "$PACK_MV" -gt 0 ] && PMW=$(( cm * PACK_MV / 1000 ))
	if [ "$PMW" -le 0 ] || [ "$st" = "Full" ]; then
		IFS= read -r iu <"$USB/current_now" 2>/dev/null
		IFS= read -r vu <"$USB/voltage_now" 2>/dev/null
		case "$iu" in ''|*[!0-9-]*) iu=0 ;; esac; iu=${iu#-}
		case "$vu" in ''|*[!0-9-]*) vu=0 ;; esac
		PMW=$(( (iu / 1000) * (vu / 1000) / 1000 ))
	fi
}
avg_power_tick() { # 放电平均功耗（毫瓦，含双电芯整组电压）
	if charge_online; then return 0; fi
	power_mw
	[ "$PMW" -le 0 ] && return 0
	case "${ST_AVG_MW:-}" in ''|*[!0-9]*) ST_AVG_MW=$PMW ;; *) ST_AVG_MW=$(( (ST_AVG_MW * 9 + PMW) / 10 )) ;; esac
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
		[ "$ST_CHARGE_APPLIED" = "1" ] && charge_off
		ST_CHARGE_START=0
		ST_CHARGE_GUARD=0
		return 0
	fi
	[ "$ST_CHARGE_START" = "0" ] && ST_CHARGE_START=$(date +%s)
	want=0
	[ "$CFG_CHARGE_AUTO" = "1" ] && want=1
	[ "$CFG_CHARGE_NOW" = "1" ] && want=1
	[ "$want" = "1" ] || { [ "$ST_CHARGE_APPLIED" = "1" ] && charge_off; ST_CHARGE_GUARD=0; return 0; }
	if bypass_on; then
		[ "$ST_CHARGE_APPLIED" = "1" ] && charge_off
		ST_CHARGE_GUARD=0
		return 0
	fi
	real_batt_md
	if [ "$RB" -gt 0 ] && [ "$RB" -ge "$CFG_CHARGE_TEMP_CUT" ]; then
		[ "$ST_CHARGE_APPLIED" = "1" ] && charge_off
		ST_CHARGE_GUARD=1
		return 0
	fi
	# 90% 之后交还官方阶梯充电（保护电池）
	cap=0
	IFS= read -r cap <"$BATT/capacity" 2>/dev/null
	case "$cap" in ''|*[!0-9]*) cap=0 ;; esac
	if [ "$cap" -ge 90 ]; then
		[ "$ST_CHARGE_APPLIED" = "1" ] && charge_off
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
	[ -w "$CAP_NODE" ] && echo "$w" >"$CAP_NODE" 2>/dev/null
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
	caps_write "$SAVE_CAPS"
	for p in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -d "$p" ] || continue
		rc=""
		IFS= read -r rc <"$p/related_cpus" 2>/dev/null
		case " $rc " in
		*" 6 "*|*" 7 "*) tgt=$PRIME_CAP ;;
		*) tgt=$LITTLE_CAP ;;
		esac
		clamp_freq "$p" "$tgt"
		echo "$CLAMPED" >"$p/scaling_max_freq" 2>/dev/null
	done
	ST_SAVE_APPLIED=1
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
	[ "$CFG_SAVE_ENABLED" = "1" ] && dis=1
	bn=$(kgsl_boost_node)
	if [ -n "$bn" ]; then
		if [ "$dis" = "1" ] && [ "$ST_GPU_STATE" != disabled ]; then
			[ -z "$GPU_BOOST_ORIG" ] && IFS= read -r GPU_BOOST_ORIG <"$bn" 2>/dev/null
			echo 0 >"$bn" 2>/dev/null
			ST_GPU_STATE=disabled
		elif [ "$dis" != "1" ] && [ "$ST_GPU_STATE" != default ]; then
			echo "${GPU_BOOST_ORIG:-1}" >"$bn" 2>/dev/null
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
		now=$(date +%s)
		[ $((now - ${FG_AT:-0})) -ge 10 ] && {
			FG_AT=$now
			p=$(foreground_pkg)
			ST_FG_PKG=$p
			if is_game "$p"; then ST_FG_GAME=1; else ST_FG_GAME=0; fi
			if scene_takes_over "$p"; then ST_SCENE_TAKEOVER=1; else ST_SCENE_TAKEOVER=0; fi
			# 横屏非视频应用（游戏/全屏应用）→ 交还官方调度
			if [ "$ST_FG_GAME" = "0" ] && ! is_video_pkg "$p" && screen_landscape; then
				ST_FG_GAME=1
			fi
		}
		# 游戏 / Scene 调度接管 → 立即让出，不和官方/Scene 抢
		if [ "$ST_FG_GAME" = "1" ] || [ "$ST_SCENE_TAKEOVER" = "1" ]; then
			[ "$ST_SAVE_APPLIED" = "1" ] && save_off
		else
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
modem_guard_tick() {
	[ "$CFG_THERMAL_MODE" = "official" ] && { ST_MODEM_BAD=0; return 0; }
	air=$(settings get global airplane_mode_on 2>/dev/null)
	[ "$air" = "1" ] && { ST_MODEM_BAD=0; return 0; }
	s=$(getprop gsm.sim.state 2>/dev/null)
	s=${s%%,*}   # 只看 SIM1，副卡槽 ABSENT 属正常
	case "$s" in
	*ABSENT*|"")
		ST_MODEM_BAD=$(( ${ST_MODEM_BAD:-0} + 4 ))
		if [ "$ST_MODEM_BAD" -ge 180 ]; then
			log "modem guard: SIM ABSENT ${ST_MODEM_BAD}s -> revert thermal to official"
			thermal_all_clear
			cfg_set THERMAL_MODE official
			CFG_THERMAL_MODE=official
			ST_MODEM_BAD=0
		fi
		;;
	*) ST_MODEM_BAD=0 ;;
	esac
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
	dumpsys telephony.registry 2>/dev/null | grep -q "mCallState=1"
}
DS_AT=0
deep_sleep_tick() {
	if [ "$CFG_DEEP_SLEEP" != "1" ]; then deep_sleep_off; return 0; fi
	if screen_on; then deep_sleep_off; return 0; fi
	if charge_online; then deep_sleep_off; return 0; fi
	if music_playing || in_call; then deep_sleep_off; return 0; fi
	now=$(date +%s)
	[ "$DS_AT" = "0" ] && { DS_AT=$now; return 0; }
	[ $((now - DS_AT)) -lt 20 ] && return 0
	[ "$ST_DS_ACTIVE" = "1" ] && return 0
	dumpsys deviceidle force-idle >/dev/null 2>&1
	ST_DS_ACTIVE=1
}
deep_sleep_off() {
	DS_AT=0
	[ "$ST_DS_ACTIVE" = "1" ] || return 0
	dumpsys deviceidle unforce >/dev/null 2>&1
	ST_DS_ACTIVE=0
}

# ---------------------------------------------------------------- 使用统计（Scene 式自采样）
USAGE_DB="$STATE/usage.db"
screen_on() {
	for f in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness; do
		[ -r "$f" ] || continue
		IFS= read -r b <"$f" 2>/dev/null
		case "$b" in ''|*[!0-9]*) continue ;; esac
		[ "$b" -gt 0 ] && return 0
		return 1
	done
	return 0
}
usage_sample() {
	now=$(date +%s)
	last_at=${ST_USAGE_AT:-0}
	case "$last_at" in ''|*[!0-9]*) last_at=0 ;; esac
	[ $((now - last_at)) -lt 30 ] && return 0
	ST_USAGE_AT=$now
	screen_on || return 0
	p=$(foreground_pkg)
	[ -z "$p" ] && return 0
	# 本次 30 秒里的电量消耗（µAh）：放电时用库仑计电流，充电时用 USB 输入折算成等效电流
	add=0
	eff=${CURR_MA:-0}
	case "$eff" in ''|*[!0-9-]*) eff=0 ;; esac
	if [ "$eff" -le 0 ]; then
		iu=0; vu=0
		IFS= read -r iu <"$USB/current_now" 2>/dev/null
		IFS= read -r vu <"$USB/voltage_now" 2>/dev/null
		case "$iu" in ''|*[!0-9-]*) iu=0 ;; esac; iu=${iu#-}
		case "$vu" in ''|*[!0-9-]*) vu=0 ;; esac
		umw=$(( (iu / 1000) * (vu / 1000) / 1000 ))
		[ "$umw" -gt 0 ] && [ "${VB_MV:-0}" -gt 0 ] && eff=$(( umw * 1000 / VB_MV ))
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
	cfg_load
	st_load
	ensure_zone_cache
	case "$CFG_THERMAL_MODE" in
	mask)
		[ "$ST_THERMAL_OFF" = "1" ] && thermal_off_off
		mask_tick
		;;
	off)
		[ "$ST_MASK_ACTIVE" = "1" ] && mask_off
		[ "$ST_THERMAL_OFF" = "1" ] || thermal_off_on
		;;
	*)
		[ "$ST_THERMAL_OFF" = "1" ] && thermal_off_off
		[ "$ST_MASK_ACTIVE" = "1" ] && mask_off
		;;
	esac
	# 保底：清理旧版本可能残留的 Scene 假温度挂载
	[ "$CFG_SCENE_SEES_FAKE" = "1" ] || scene_spoof_off
	modem_guard_tick
	batt_mv
	cc_sample
	charge_tick
	sched_tick
	deep_sleep_tick
	# 电量计还没攒够样本时，用 batterystats 兜底
	[ "$AVG_MA" -le 0 ] && avg_from_bstats
	[ -f "$DEV_CACHE" ] || cache_device
	usage_sample
	update_prop
	st_save
}
update_prop() {
	now=$(date +%s)
	[ $((now - ST_PROP_AT)) -lt 30 ] && return 0
	ST_PROP_AT=$now
	case "$CFG_THERMAL_MODE" in
	mask) tw="伪装温控" ;;
	off) tw="去温控" ;;
	*) tw="官方温控" ;;
	esac
	[ "$ST_CHARGE_APPLIED" = "1" ] && cw="满血中" || cw="官方"
	[ "$CFG_SAVE_ENABLED" = "1" ] && sw="限频中" || sw="关"
	sed -i "s@^description=.*@description=为Realme GT7 Pro定制的模块，功能为温控·电池·调度相关。私人定制切勿分享。当前状态：运行中 / 温控 $tw / 充电 $cw / 调度 $sw@" \
		"$MODDIR/module.prop" 2>/dev/null
}
