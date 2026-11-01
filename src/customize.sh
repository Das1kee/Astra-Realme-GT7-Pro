#!/system/bin/sh
# Astra 安装脚本（KernelSU / SukiSU / Magisk 通用）
SKIPUNZIP=0
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
MODPATH=${MODPATH:-$(pwd)}

A_MODEL=$(getprop ro.product.model)
A_SOC=$(getprop ro.soc.model)
A_ROM=$(getprop ro.build.display.id)

ui_print " "
ui_print "  ╔══════════════════════════════════════════════╗"
ui_print "  ║   █████╗ ███████╗████████╗██████╗  █████╗    ║"
ui_print "  ║  ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗   ║"
ui_print "  ║  ███████║███████╗   ██║   ██████╔╝███████║   ║"
ui_print "  ║  ██╔══██║╚════██║   ██║   ██╔══██╗██╔══██║   ║"
ui_print "  ║  ██║  ██║███████║   ██║   ██║  ██║██║  ██║   ║"
ui_print "  ║  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ║"
ui_print "  ║        Beta 0.1.06   ·   by Dasikee          ║"
ui_print "  ╚══════════════════════════════════════════════╝"
ui_print " "
ui_print "- 机型：$A_MODEL    SoC：$A_SOC"
ui_print "- 版本：$A_ROM"
[ "$A_MODEL" != "RMX5010" ] && ui_print "! 警告：本模块为 RMX5010 定制，当前为 $A_MODEL"
ui_print " "

ui_print "- 生成温控补丁…"
PATCHDIR="$MODPATH/patch"
mkdir -p "$PATCHDIR"

for src in /odm/etc/temperature_profile/sys_thermal_control_config.xml \
           /odm/etc/temperature_profile/sys_thermal_control_config_gt.xml; do
	[ -f "$src" ] || continue
	dst="$PATCHDIR$src"
	mkdir -p "$(dirname "$dst")"
	sed \
		-e 's#<feature_enable_item booleanVal="true"#<feature_enable_item booleanVal="false"#' \
		-e 's#<feature_safety_test_enable_item booleanVal="true"#<feature_safety_test_enable_item booleanVal="false"#' \
		-e 's#<aging_thermal_control_enable_item booleanVal="true"#<aging_thermal_control_enable_item booleanVal="false"#' \
		-e 's#<aging_cpu_level_item intVal="[0-9-]*"#<aging_cpu_level_item intVal="-1"#' \
		-e 's#maxCpuFreq="[^"]*"#maxCpuFreq="-1,-1"#g' \
		-e 's#boostCeiling="[^"]*"#boostCeiling="-1,-1"#g' \
		-e 's#boostCpuCoreCeiling="[^"]*"#boostCpuCoreCeiling="-1,-1"#g' \
		"$src" >"$dst" 2>/dev/null && ui_print "  · $(basename "$src")"
done

for src in /odm/etc/ThermalServiceConfig/sys_thermal_config.xml; do
	[ -f "$src" ] || continue
	dst="$PATCHDIR$src"
	mkdir -p "$(dirname "$dst")"
	sed -e 's#<isOpen>1</isOpen>#<isOpen>0</isOpen>#' \
		-e 's#<is_feature_on>1</is_feature_on>#<is_feature_on>0</is_feature_on>#' \
		"$src" >"$dst" 2>/dev/null && ui_print "  · $(basename "$src")"
done

for src in /odm/etc/temperature_profile/sys_high_temp_protect_realme_*.xml; do
	[ -f "$src" ] || continue
	dst="$PATCHDIR$src"
	mkdir -p "$(dirname "$dst")"
	sed \
		-e 's#<HighTemperatureProtectSwitch>true#<HighTemperatureProtectSwitch>false#' \
		-e 's#<HighTemperatureFirstStepSwitch>true#<HighTemperatureFirstStepSwitch>false#' \
		-e 's#<HighTemperatureDisableFlashSwitch>true#<HighTemperatureDisableFlashSwitch>false#' \
		-e 's#<HighTemperatureDisableFlashChargeSwitch>true#<HighTemperatureDisableFlashChargeSwitch>false#' \
		-e 's#<HighTemperatureControlVideoRecordSwitch>true#<HighTemperatureControlVideoRecordSwitch>false#' \
		-e 's#<HighTemperatureProtectThresholdIn>[0-9]*#<HighTemperatureProtectThresholdIn>520#' \
		-e 's#<HighTemperatureProtectThresholdOut>[0-9]*#<HighTemperatureProtectThresholdOut>500#' \
		-e 's#<HighTemperatureProtectFirstStepIn>[0-9]*#<HighTemperatureProtectFirstStepIn>500#' \
		-e 's#<HighTemperatureProtectFirstStepOut>[0-9]*#<HighTemperatureProtectFirstStepOut>480#' \
		"$src" >"$dst" 2>/dev/null && ui_print "  · $(basename "$src")"
done

ui_print "- 设置权限…"
chown -R 0:0 "$MODPATH" 2>/dev/null
find "$MODPATH" -type d -exec chmod 0755 {} + 2>/dev/null
find "$MODPATH" -type f -exec chmod 0644 {} + 2>/dev/null
chmod 0755 "$MODPATH/bin/astra" "$MODPATH/service.sh" "$MODPATH/post-fs-data.sh" \
	"$MODPATH/uninstall.sh" "$MODPATH/action.sh" 2>/dev/null

mkdir -p /data/adb/Astra/logs /data/adb/Astra/settings /storage/emulated/0/Astra 2>/dev/null
[ -f /data/adb/Astra/settings/games.list ] || cp -f "$MODPATH/config/games.list" /data/adb/Astra/settings/games.list 2>/dev/null

ui_print " "
ui_print "- 安装完成。请【重启手机】，重启后模块才会真正落到"
ui_print "  /data/adb/modules/astra（SukiSU 会先暂存在 modules_update）。"
ui_print "- 打开：SukiSU → 模块 → Astra → 打开"
ui_print "- 卸载：管理器里删除模块，重启即可，自动还原全部设置。"
ui_print " "
