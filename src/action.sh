#!/system/bin/sh
# Astra action.sh —— 管理器里点「执行」
MODDIR=${0%/*}
. "$MODDIR/bin/lib.sh"
cfg_load
st_load
ensure_zone_cache
real_batt_md; b=$RB
real_soc_md; s=$RS
echo "Astra $(sed -n 's/^version=//p' "$MODDIR/module.prop" | head -1)"
echo "温控: $CFG_THERMAL_MODE   调度: $CFG_SAVE_ENABLED   GPU: $CFG_GPU_BOOST"
echo "电池: $((b / 1000)).$((b % 1000 / 100))℃   SoC: $((s / 1000)).$((s % 1000 / 100))℃"
echo "日志: $LOGS/astra.log"
