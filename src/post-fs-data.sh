#!/system/bin/sh
# Astra post-fs-data
MODDIR=${0%/*}
STATE=/data/adb/Astra
mkdir -p "$STATE/logs" "$STATE/settings" "$STATE/tmp" 2>/dev/null
chmod 0700 "$STATE" 2>/dev/null
[ -f "$STATE/config.conf" ] || {
	cp -f "$MODDIR/config/defaults.conf" "$STATE/config.conf" 2>/dev/null
	chmod 0600 "$STATE/config.conf" 2>/dev/null
}
[ -f "$STATE/settings/games.list" ] || cp -f "$MODDIR/config/games.list" "$STATE/settings/games.list" 2>/dev/null

# 仅在"去温控"模式下才需要尽早挂载补丁
. "$MODDIR/bin/lib.sh" 2>/dev/null
cfg_load
[ -d "$MODDIR/patch" ] && [ "$CFG_THERMAL_MODE" = "off" ] && thermal_off_on
exit 0
