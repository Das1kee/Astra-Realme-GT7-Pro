#!/system/bin/sh
# Astra post-fs-data —— 只做准备工作，绝不在这里挂载/改热区（避免开机早期把射频/温控服务打崩）
MODDIR=${0%/*}
STATE=/data/adb/Astra
mkdir -p "$STATE/logs" "$STATE/settings" "$STATE/tmp" 2>/dev/null
chmod 0700 "$STATE" 2>/dev/null
# PIDs and mkdir locks from the previous boot are never live after boot. Remove
# them before service.sh starts so PID reuse cannot suppress the Astra daemon.
rm -f "$STATE/daemon.pid" 2>/dev/null
rm -rf "$STATE/.thermal-mode.lock" 2>/dev/null
[ -f "$STATE/config.conf" ] || {
	cp -f "$MODDIR/config/defaults.conf" "$STATE/config.conf" 2>/dev/null
	chmod 0600 "$STATE/config.conf" 2>/dev/null
}
[ -f "$STATE/settings/games.list" ] || cp -f "$MODDIR/config/games.list" "$STATE/settings/games.list" 2>/dev/null

# ---- 启动计数：只做提示，绝不擅自改用户设置 ----
# 上一轮如果活过了 3 分钟（daemon 会写 boot_ok），说明不是坏启动，清空计数
if [ -f "$STATE/boot_ok" ]; then
	rm -f "$STATE/boot_ok" 2>/dev/null
	: >"$STATE/boots.log"
fi
NOW=$(date +%s)
echo "$NOW" >>"$STATE/boots.log" 2>/dev/null
tail -n 6 "$STATE/boots.log" >"$STATE/boots.tmp" 2>/dev/null && mv -f "$STATE/boots.tmp" "$STATE/boots.log"
FIRST=$(head -n 1 "$STATE/boots.log" 2>/dev/null)
case "$FIRST" in ''|*[!0-9]*) FIRST=$NOW ;; esac
COUNT=$(wc -l <"$STATE/boots.log" 2>/dev/null)
case "$COUNT" in ''|*[!0-9]*) COUNT=1 ;; esac
# 10 分钟内连续 4 次短启动：只打标记警告，不再强制改温控模式
if [ "$COUNT" -ge 4 ] && [ $((NOW - FIRST)) -lt 600 ]; then
	grep -q "^SAFE_MODE=" "$STATE/config.conf" 2>/dev/null || echo "SAFE_MODE=1" >>"$STATE/config.conf"
	echo "$NOW bootloop warning: $COUNT short boots within 10 min" >>"$STATE/logs/astra.log" 2>/dev/null
fi
exit 0
