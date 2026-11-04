#!/system/bin/sh
# Astra installer for KernelSU / SukiSU / Magisk.
SKIPUNZIP=0
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
MODPATH=${MODPATH:-$(pwd)}

A_MODEL=$(getprop ro.product.model 2>/dev/null)
A_SOC=$(getprop ro.soc.model 2>/dev/null)
A_ROM=$(getprop ro.build.display.id 2>/dev/null)
A_VER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -1)

ui_print " "
ui_print "  =================================="
ui_print "  Astra $A_VER · Dasikee"
ui_print "  GT7 Pro / Thermal / Charge / CPU"
ui_print "  =================================="
ui_print " "
ui_print "  Device : ${A_MODEL:-unknown} / ${A_SOC:-unknown}"
ui_print "  System : ${A_ROM:-unknown}"
if [ "$A_MODEL" != "RMX5010" ]; then
	ui_print "  ! Astra is tuned for RMX5010; unsupported nodes will be skipped."
fi

# Patch only the OPlus game thermal strategy tables. Keep each XML level and
# remove its software CPU/GPU frequency ceilings without touching battery,
# camera, radio, or hardware over-temperature protection files.
_sources="$MODPATH/.astra-thermal-sources"
_patched="$MODPATH/.astra-thermal-patched"
: >"$_sources"
: >"$_patched"
find /odm /my_product /vendor /system/vendor /product /system \
	-type f -name 'sys_thermal_control_config*.xml' -print 2>/dev/null | sort -u >"$_sources"

PATCH_COUNT=0
for src in $(cat "$_sources" 2>/dev/null); do
	if ! head -c 128 "$src" 2>/dev/null | grep -qE '<\?xml|<sys_thermal'; then
		ui_print "  ! Skipped non-XML thermal file: ${src##*/}"
		continue
	fi
	# Keep patched XML outside KSU/Magisk's recognized partition directories.
	# Otherwise a manager may auto-mount them even when Thermal Mode is Official.
	dst="$MODPATH/.astra-thermal-patches/${src#/}"
	mkdir -p "$(dirname "$dst")"
	orig_levels=$(grep -c '<level[[:space:]]' "$src" 2>/dev/null)
	case "$orig_levels" in ''|*[!0-9]*) orig_levels=0 ;; esac
	sed \
		-e 's#<feature_enable_item booleanVal="true"#<feature_enable_item booleanVal="false"#g' \
		-e 's#<feature_safety_test_enable_item booleanVal="true"#<feature_safety_test_enable_item booleanVal="false"#g' \
		-e 's#<aging_thermal_control_enable_item booleanVal="true"#<aging_thermal_control_enable_item booleanVal="false"#g' \
		-e 's#<aging_cpu_level_item intVal="[0-9-]*"#<aging_cpu_level_item intVal="-1"#g' \
		-e 's#maxCpuCore="[^"]*"#maxCpuCore="-1,-1"#g' \
		-e 's#maxCpuFreq="[^"]*"#maxCpuFreq="-1,-1"#g' \
		-e 's#boostCeiling="[^"]*"#boostCeiling="-1,-1"#g' \
		-e 's#boostCpuCoreCeiling="[^"]*"#boostCpuCoreCeiling="-1,-1"#g' \
		"$src" >"$dst" 2>/dev/null
	patched_levels=$(grep -c '<level[[:space:]]' "$dst" 2>/dev/null)
	case "$patched_levels" in ''|*[!0-9]*) patched_levels=0 ;; esac
	if [ "$orig_levels" -gt 0 ] && [ "$patched_levels" -eq "$orig_levels" ] \
		&& grep -q 'maxCpuFreq="-1,-1"' "$dst" 2>/dev/null; then
		PATCH_COUNT=$((PATCH_COUNT + 1))
		printf '%s|%s\n' "$dst" "$patched_levels" >>"$_patched"
		ui_print "  ✓ ${src##*/}: $patched_levels levels retained, software caps cleared"
	else
		rm -f "$dst"
		ui_print "  ! Thermal table validation failed; file left unmounted: ${src##*/}"
	fi
done
rm -f "$_sources"

if [ "$PATCH_COUNT" -eq 0 ]; then
	ui_print "  ! No compatible OPlus game thermal table was patched."
	ui_print "  ! GT去温控 will report unavailable instead of claiming success."
else
	ui_print "  Thermal strategy files ready: $PATCH_COUNT"
fi

# Install-time work is limited to module files and diagnostic defaults.
# Runtime properties and service state are changed only when GT mode is enabled.
mkdir -p /data/adb/Astra/logs /data/adb/Astra/settings /data/adb/Astra/tmp /sdcard/Astra 2>/dev/null
[ -f /data/adb/Astra/settings/games.list ] || \
	cp -f "$MODPATH/config/games.list" /data/adb/Astra/settings/games.list 2>/dev/null
printf '[%s] install version=%s model=%s thermal_tables=%s\n' \
	"$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$A_VER" "${A_MODEL:-unknown}" "$PATCH_COUNT" \
	>>/data/adb/Astra/logs/install.log 2>/dev/null

chown -R 0:0 "$MODPATH" 2>/dev/null
find "$MODPATH" -type d -exec chmod 0755 {} + 2>/dev/null
find "$MODPATH" -type f -exec chmod 0644 {} + 2>/dev/null
chmod 0755 "$MODPATH/bin/astra" "$MODPATH/service.sh" "$MODPATH/post-fs-data.sh" \
	"$MODPATH/uninstall.sh" "$MODPATH/action.sh" "$MODPATH/customize.sh" 2>/dev/null
chcon -R u:object_r:vendor_configs_file:s0 "$MODPATH/.astra-thermal-patches" 2>/dev/null

ui_print " "
ui_print "  Install complete. Reboot, then enable Astra in SukiSU."
ui_print "  GT去温控 changes only validated game thermal strategy tables."
ui_print "  Battery, camera, radio and hardware over-temperature protections remain active."
ui_print "  Uninstall from the manager and reboot to restore runtime changes."
ui_print " "
