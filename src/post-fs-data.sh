#!/system/bin/sh
# Astra post-fs-data —— 只做准备工作，绝不在这里挂载/改热区（避免开机早期把射频/温控服务打崩）
MODDIR=${0%/*}
STATE=/data/adb/Astra
mkdir -p "$STATE/logs" "$STATE/settings" "$STATE/tmp" 2>/dev/null
chmod 0700 "$STATE" 2>/dev/null
[ -f "$STATE/config.conf" ] || {
	cp -f "$MODDIR/config/defaults.conf" "$STATE/config.conf" 2>/dev/null
	chmod 0600 "$STATE/config.conf" 2>/dev/null
}
[ -f "$STATE/settings/games.list" ] || cp -f "$MODDIR/config/games.list" "$STATE/settings/games.list" 2>/dev/null

# ---- 启动计数 / 防变砖 ----
NOW=$(date +%s)
echo "$NOW" >>"$STATE/boots.log" 2>/dev/null
tail -n 6 "$STATE/boots.log" >"$STATE/boots.tmp" 2>/dev/null && mv -f "$STATE/boots.tmp" "$STATE/boots.log"
FIRST=$(head -n 1 "$STATE/boots.log" 2>/dev/null)
case "$FIRST" in ''|*[!0-9]*) FIRST=$NOW ;; esac
COUNT=$(wc -l <"$STATE/boots.log" 2>/dev/null)
case "$COUNT" in ''|*[!0-9]*) COUNT=1 ;; esac
# 15 分钟内重启 3 次以上：判定异常，强制回官方温控
if [ "$COUNT" -ge 3 ] && [ $((NOW - FIRST)) -lt 900 ]; then
	grep -q "^SAFE_MODE=" "$STATE/config.conf" 2>/dev/null || echo "SAFE_MODE=1" >>"$STATE/config.conf"
	sed -i 's@^THERMAL_MODE=.*@THERMAL_MODE=official@' "$STATE/config.conf" 2>/dev/null
	echo "$NOW bootloop guard: forced official" >>"$STATE/logs/astra.log" 2>/dev/null
	: >"$STATE/boots.log"
fi
exit 0
