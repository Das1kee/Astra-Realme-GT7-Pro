/* Astra WebUI  Beta0.3.0
 * 桥接层兼容 KernelSU / SukiSU / MMRL 的三种 exec 调用形态（参考实机可用的模块写法）：
 *   1) api.exec(cmd)             → string | Promise<string|{errno,stdout}>
 *   2) api.exec(cmd, cb)         → cb(errno, stdout, stderr)
 *   3) api.exec(cmd, "", cb)     → cb(errno, stdout, stderr)
 * 另外：window.ksu 是页面加载后才注入的，必须重试等待，不能一次性判定。
 */
(function () {
  "use strict";

  var MOD = null;
  var S = null;
  var busy = false;
  var lang = "zh";
  var poll = null;
  var appsAt = 0;
  var bridge = null;

  var T = {
    zh: {
      g0: "凌晨好", g1: "早上好", g2: "下午好", g3: "晚上好",
      connecting: "正在连接控制器…",
      nobridge: "未检测到 root 桥接（SukiSU 的 WebUI 接口尚未注入）",
      nodir: "未找到模块目录，请确认已安装并重启",
      prefix: "系统可见温度", realb: "真实电池", reals: "真实 SoC",
      official: "官方温控", off: "GT去温控", mask: "温度伪装", fused: "已熔断",
      hint_official: "官方温控，模块不介入", hint_off: "厂商温控表已替换，硬件保护仍在",
      hint_mask: "系统当前看到的是伪装温度", hint_fuse: "真实温度过高，已交还官方温控",
      mode: "温控模式", only1: "三种模式互斥，切换即时生效。",
      maskt: "温度伪装", on: "已开启", offs: "未启用", see: "系统看到",
      see_fake: "Scene 显示伪装温度", see_fake_s: "开启后电池节点也伪装，Scene 看到伪装值",
      wall: "拉高真实温控墙", wall_s: "两条熔断线整体上移 3℃",
      fb: "电池熔断", fs: "SoC 熔断",
      offt: "GT去温控", offd: "替换厂商温控策略表，关闭软降级；硬件过温关机保护始终保留。",
      patch: "补丁状态", unmounted: "未挂载", mountedCount: "项策略表已挂载", patchUnavailable: "未找到可用策略表",
      pw: "充电功率", charging: "充电中", notch: "未充电", fulled: "已充满",
      notplug: "未连接充电器", dur: "充电时长", btemp: "电池温度",
      chg_full: "模块可控限流已解除；实际速度由原厂充电策略决定", chg_atmax: "当前已到协商电流上限，Astra 没有额外限流可解除", chg_unavailable: "系统未接受解除限流请求，当前按原厂策略充电", chg_hot: "温度到线，已交还官方充电",
      chg_90: "已到 90%，交还官方阶梯充电", chg_off: "未接管，官方策略",
      chg_idle: "已连接充电器，当前未在充电",
      hint_radio: "检测到信号异常，已自动交还官方温控",
      
      autot: "每次充电请求解除模块限流", autos: "只释放模块可控的限流项；充电速度仍由原厂策略决定",
      nowbtn: "本次充电请求解除模块限流", nowoff: "取消本次充电请求",
      cut: "温度保护线", cuth: "到达保护线或电量 90% 自动交还官方充电策略。",
      deep: "深度睡眠", deep_s: "锁屏 20 秒进入 Android Doze，减少后台唤醒；亮屏、充电、通话或音乐时保持在线",
      deep_on: "深度睡眠中（Doze）", deep_off: "未启用", deep_ready: "已启用：锁屏 20 秒后进入 Doze", deep_last: "最近进入：",
      ltpo: "LTPO 全场景", ltpo_s: "允许全场景启用 LTPO / 全亮度 VRR；systemless 替换显示配置，重启后生效",
      ltpo_live: "已生效", ltpo_pending: "已启用，重启后生效", ltpo_off: "未启用",
      bit_hint: "电池详情（剩余电量 / 健康度 / 循环 / 容量曲线）将在 Astra App 提供。",
      remain: "剩余电量", percent: "电量百分比", health: "电池健康", design: "设计容量",
      fullcap: "满充容量", cycle: "循环次数",
      sched: "调度", capped: "限频中", uncapped: "未限制", ingame: "游戏 · 已暂停限频",
      sceneon: "Scene 接管",
      save: "官调限频", save_s: "官方调度不变，只封顶最高频率",
      gamehint: "游戏中会自动暂停限频，退出游戏后恢复；检测到 Scene 正在调度前台应用时也会自动让出。",
      gpu: "禁用 GPU Boost", gpu_s: "开启则关闭 GPU 的 DCVS 提升；关闭为系统默认",
      gpu_forced: "官调限频开启时强制禁用", gpu_free: "可自由开关", gpu_failed: "DCVS 节点未接受设置",
      cap_failed: "限频节点未接受设置",
      apps: "耗电统计", avgpow: "平均功耗", curw: "当前功耗", appavg: "平均",
      appsh: "按 Astra 自安装后的前台采样统计，mAh 由整机电流折算，仅供参考。",
      appsnone: "暂无记录",
      dev: "设备", model: "机型", rom: "系统", kernel: "内核", root: "Root", ver: "模块版本",
      intro: "功能介绍",
      intro_t: "为 Realme GT7 Pro 定制的模块：温控 · 电池 · 调度。所有开关即时生效，卸载模块自动还原全部设置，不写系统分区。",
      changelog: "更新日志", langrow: "语言 / Language",
      rep: "生成 debug 报告", reph: "保存到 /data/adb/Astra/logs/ 并复制到 /sdcard/Astra/",
      author: "作者",
      note: "无需重启即可生效；去温控模式建议重启一次让厂商服务重读温控表。",
      n1: "温控", n2: "电池", n3: "调度", n4: "设置",
      applied: "已生效", failed: "失败", saved: "报告已生成", plugfirst: "请先连接充电器",
      ago0: "刚刚", agom: "分钟前", agoh: "小时前", agod: "天前"
    },
    en: {
      g0: "Good night", g1: "Good morning", g2: "Good afternoon", g3: "Good evening",
      connecting: "Connecting to controller…",
      nobridge: "Root bridge not detected (SukiSU WebUI API not injected yet)",
      nodir: "Module directory not found — install and reboot first",
      prefix: "System-visible temp", realb: "Real battery", reals: "Real SoC",
      official: "Official", off: "GT thermal off", mask: "Masked temp", fused: "Fused",
      hint_official: "Official policy, module idle", hint_off: "Vendor tables replaced, hardware net kept",
      hint_mask: "The system sees the masked value", hint_fuse: "Too hot — handed back to official",
      mode: "Thermal mode", only1: "One mode at a time, applied instantly.",
      maskt: "Masked temp", on: "On", offs: "Off", see: "System sees",
      see_fake: "Scene shows masked temp", see_fake_s: "Also spoofs the battery node for Scene",
      wall: "Raise thermal wall", wall_s: "Both fuse lines move up by 3°C",
      fb: "Battery fuse", fs: "SoC fuse",
      offt: "GT thermal off", offd: "Replaces vendor thermal tables and soft steps; the hardware shutdown net stays.",
      patch: "Patch state", unmounted: "Not mounted", mountedCount: "thermal tables mounted", patchUnavailable: "No compatible table found",
      pw: "Power", charging: "Charging", notch: "Not charging", fulled: "Full",
      notplug: "No charger", dur: "Duration", btemp: "Battery temp",
      chg_full: "Module controlled limits released; OEM charging policy determines the rate", chg_atmax: "Already at the negotiated current limit; Astra has no extra limit to release", chg_unavailable: "System did not accept the request; OEM charging policy remains active", chg_hot: "Temp guard — official charging",
      chg_90: "90% reached — official step charging", chg_off: "Not active — official policy",
      chg_idle: "Charger connected, not charging right now",
      hint_radio: "Radio issue detected — handed back to official thermal",
      
      autot: "Request limit release on every charge", autos: "Releases only limits controlled by Astra; OEM policy still sets the rate",
      nowbtn: "Request limit release this charge", nowoff: "Cancel this charge request",
      cut: "Temperature guard", cuth: "Reverts at the guard temperature or 90% charge.",
      deep: "Deep sleep", deep_s: "Enters Android Doze 20 s after screen-off to cut background wakeups; stays online while the screen is on, charging, on a call or playing music",
      deep_on: "Deep sleep (Doze) active", deep_off: "Disabled", deep_ready: "Enabled: Doze starts 20 s after screen-off", deep_last: "Last entered: ",
      ltpo: "Full-scene LTPO", ltpo_s: "Enable LTPO / full-brightness VRR in every scene; systemless display-config swap, applies after reboot",
      ltpo_live: "Active", ltpo_pending: "Enabled — applies after reboot", ltpo_off: "Disabled",
      bit_hint: "Battery details (remaining / health / cycles / curve) arrive with the Astra App.",
      remain: "Remaining", percent: "Level", health: "Health", design: "Design",
      fullcap: "Full charge", cycle: "Cycles",
      sched: "Scheduling", capped: "Capped", uncapped: "Unrestricted", ingame: "Game · cap paused",
      sceneon: "Scene in control",
      save: "Official-clock cap", save_s: "Official governor unchanged, only the ceiling drops",
      gamehint: "The cap pauses in games, and yields when Scene is scheduling the foreground app.",
      gpu: "Disable GPU Boost", gpu_s: "Turns off the GPU DCVS boost; off = system default",
      gpu_forced: "Forced while the CPU cap is applied", gpu_free: "Free to toggle", gpu_failed: "DCVS node did not accept the setting",
      cap_failed: "CPU cap node did not accept the setting",
      apps: "Battery usage", avgpow: "Avg power", curw: "Now", appavg: "avg",
      appsh: "Sampled by Astra since install; mAh is derived from device current.",
      appsnone: "No records",
      dev: "Device", model: "Model", rom: "ROM", kernel: "Kernel", root: "Root", ver: "Version",
      intro: "About",
      intro_t: "A Realme GT7 Pro module: thermal, battery, scheduling. Every switch is live and uninstalling restores everything.",
      changelog: "Changelog", langrow: "Language / 语言",
      rep: "Generate debug report", reph: "Saved under /data/adb/Astra/logs/ and copied to /sdcard/Astra/",
      author: "Author",
      note: "No reboot needed for switches; thermal-off benefits from one reboot so vendor services re-read the tables.",
      n1: "Thermal", n2: "Battery", n3: "Sched", n4: "Settings",
      applied: "Applied", failed: "Failed", saved: "Report saved", plugfirst: "Connect a charger first",
      ago0: "just now", agom: "m ago", agoh: "h ago", agod: "d ago"
    }
  };
  var CHANGELOG = {
    zh: [
      { version: "Beta0.3.0", groups: [
        ["修复", [
          "深度睡眠：进入 Doze 后不再每 4 秒跑 media_session / telephony dumpsys（这两个检查本身会把 CPU 反复唤醒，把 Doze 省下的电又吃回去），改为倒计时 15 秒、进入后 60 秒一次。",
          "深度睡眠：熄屏时跳过前台应用检测、掉信号保护降到 30 秒一次、模块状态刷新降到 5 分钟，明显减少守护进程唤醒。",
          "深度睡眠：进入 Doze 后轮询放慢到 10 秒；每 5 分钟确认强制 idle 是否还在，被系统顶掉会自动重新强制；新增进入/退出日志与 debug 报告 doze 段。",
          "界面：深度睡眠提示改为“已启用：锁屏 20 秒后进入 Doze · 最近进入 X 前”，不再显示无意义的“待机中，未进入深度睡眠”。"
        ]],
        ["优化", [
          "状态：SukiSU 模块页描述只保留功能快捷查看（温控 / 充电 / 调度），切换开关后立即刷新。",
          "性能：守护进程每轮只取一次系统时间；官方温控熄屏时跳过热区缓存校验；无待还原状态时不再每轮拿模式锁。"
        ]]
      ]},
      { version: "Beta0.2.9", groups: [
        ["新增", [
          "显示：融合 GT7Pro-LTPO v2.0 —— 全场景 LTPO / 全亮度 VRR。安装时用音量键询问（音量上=启用、音量下=跳过、10 秒无操作默认启用），也可在设置页随时开关，重启后生效。",
          "显示：systemless bind mount 替换 /my_product/etc/oplus_vrr_config.json（去掉低亮度退出 LTPO 的档位、ambient、hw_nit_limit），resetprop -n 临时打开 VRR；不写系统分区、不写持久属性。",
          "设置：新增「LTPO 全场景」开关与状态（已生效 / 已启用待重启 / 未启用）。"
        ]],
        ["修复", [
          "显示：升级/重装时沿用上次的 LTPO 选择，不会被覆盖；独立 GT7PROLTPOEnhance 模块存在时安装器会提示卸载，避免重复挂载。",
          "设置：修复 set 命令内部变量被配置文件覆盖，开关“立即生效”分支匹配到错误键名（以前要等守护进程下一轮）；现在各开关点按即时生效。"
        ]]
      ]},
      { version: "Beta0.2.8", groups: [
        ["修复", [
          "温控：温度伪装不再写 socd 热区。该热区是整摄氏度单位、带 100℃ 硬件 trip，写毫摄氏度会被固件当成 30100℃ 极端过温，触发厂商紧急保护导致掉信号（实测：开启伪装 5 秒内语音/数据全部 OUT_OF_SERVICE、运营商清空，关闭后立即恢复）。",
          "温控：伪装写入前校验“热区序号仍指向原传感器名”，序号变化时自动重建缓存，避免热区重排后写错传感器。",
          "温控：开机和切换模式时全量清除其它热区的仿真值，清理旧版本残留；停用伪装后按记录精确清零。",
          "电池：充电功率只在真正充电时显示；未充电、已充满时显示 0.0 W，不再把放电功率当成充电功率。",
          "电池：USB 输入节点不刷新时退回电池侧（整组电压）估算，避免充电中显示 0.0 W。",
          "信号：SIM 仍为 LOADED 但注册/运营商丢失时，90 秒后自动交还官方温控（旧逻辑只判断 ABSENT，双卡机型不会触发）。"
        ]],
        ["优化", [
          "界面：充电状态按实际状态显示充电中 / 已充满 / 未充电，并区分“已连接但未充电”。",
          "温控：掉信号自动交还官方后，温控页会提示“检测到信号异常，已自动交还官方温控”。"
        ]]
      ]},
      { version: "Beta0.2.7", groups: [
        ["修复", ["调度：平均功耗改用平滑的 30 秒采样，充放电切换或重启后重新建立基线，避免短采样造成读数跳变。"]],
        ["优化", ["调度：恢复当前功耗、平均功耗和最近三款应用的名称、时长、耗电量与平均功耗显示。"]],
        ["移除", ["统计：首次升级时备份并清空旧的单电芯口径应用记录，避免双电芯耗电量显示偏低。"]]
      ]},
      { version: "Beta0.2.6", groups: [
        ["修复", ["调度：充电时以双电芯总电压换算 USB 功率对应的等效电池电流，避免应用平均功耗估高一倍。"]]
      ]},
      { version: "Beta0.2.5", groups: [
        ["修复", ["日志：调试报告对不存在的电池限流节点显示“不可用”，不再复用上一条节点的旧值。"]],
        ["优化", ["电池：电量统计与应用耗电估算统一使用双电芯总电压，充电器 USB 输入功率仍按输入侧实测值计算。"]]
      ]},
      { version: "Beta0.2.4", groups: [
        ["修复", ["电池：避免 Android sh 在 USB 电流与电压乘法中发生 32 位溢出，修正充电功率异常偏低。"]],
        ["优化", ["状态：先换算为 mA 与 mV 再计算 USB 输入功率，保证低功耗与高功耗读数都在整数范围内。"]]
      ]},
      { version: "Beta0.2.3", groups: [
        ["新增", ["温控：启动时清理旧守护进程 PID，避免 PID 被其他系统服务复用后跳过 Astra 启动。"]],
        ["修复", ["安装：修正模块属性编码，避免 SukiSU 将 Astra 识别为重复目录并导致管理器异常。", "温控：把补丁表存到模块内部隐藏目录，只在 GT 去温控模式手动挂载；官方模式不再被元模块自动覆盖。", "电池：充电功率改读 USB 输入电流和电压，停止用电池侧电流推算充电瓦数。", "充电：只报告已被可写电流节点回读确认的限流解除结果；无可用节点或已经达到协商上限时明确显示状态。", "充电：本次充电请求按钮现在可以取消，未生效时不再展示成功提示。"]],
        ["优化", ["安装：缩短刷入分隔线，避免 Astra 标题错位换行。", "日志：补充 USB 输入、电量计与充电节点诊断信息。", "界面：温控状态按真实挂载数量显示，并继续按新增、修复、优化、移除分类展示更新日志。"]],
        ["移除", ["充电：移除对只读快充状态和厂商私有温控节点的写入尝试，避免将无效写操作标记为成功。"]]
      ]},
      { version: "Beta0.2.2", groups: [
        ["新增", ["温控：GT 去温控仅替换保留全部等级的厂商策略表；不修改射频、电池、相机和硬件过温保护配置。", "状态：显示成功挂载的策略表数量；调度页区分配置开关与实际限频结果。"]],
        ["修复", ["安装：构建包清除 module.prop 的 UTF-8 BOM，避免 SukiSU 将模块识别成第二个目录。", "温控：模式先写入配置并与后台串行执行，重启后不再被旧防变砖逻辑覆盖。", "电池：修复页面访问已删除控件造成的 JavaScript 异常。", "调度：每轮重新应用并回读 GPU DCVS 状态；Scene 的 ignored 标记按接管规则处理。"]],
        ["优化", ["温控：保留厂商策略表全部等级并校验挂载文件；无有效策略时不会伪报成功。", "日志：限制日志文件大小并滚动保留；debug 报告包含挂载、GPU、充电和 CPU 上限状态。", "深度睡眠：说明改为 Android Doze 行为，提示应用通知受系统白名单与维护窗口规则影响。"]],
        ["移除", ["电池：删除无效的接口上限和系统智能极速充电展示。"]]
      ]},
      { version: "Beta0.2.1", groups: [
        ["新增", ["温控：引入厂商温控策略表挂载方案。", "调度：加入锁屏深度睡眠选项。"]],
        ["修复", ["修复模块属性 BOM、温控模式重启回退、满血充电控制及更新日志脚本问题。"]],
        ["优化", ["改进刷入提示与版本显示。"]],
        ["移除", ["删除两个无法控制硬件的电池状态项。"]]
      ]},
      { version: "Beta0.2.0", groups: [["新增", ["温控模式切换提示、策略表补丁和掉信号保护。", "电池功率自动刷新与充电控制。", "官调限频、GPU Boost 开关和深度睡眠。", "星空 WebUI 与 GitHub 入口。"]]] }
    ],
    en: [
      { version: "Beta0.3.0", groups: [
        ["Fixed", [
          "Deep sleep: after Doze is forced, stop running media_session / telephony dumpsys every 4 s (those probes themselves keep waking the CPU and eat the savings); now every 15 s while counting down and every 60 s once in Doze.",
          "Deep sleep: skip foreground-app detection while the screen is off, check the radio guard every 30 s instead of 4 s, and refresh module.prop every 5 minutes — far fewer daemon wakeups.",
          "Deep sleep: the daemon polls every 10 s inside Doze, re-verifies the forced idle state every 5 minutes (and re-forces it if the system dropped it), and logs every enter/exit with a reason; the debug report gains a doze section.",
          "UI: the deep-sleep hint now reads “Enabled: Doze starts 20 s after screen-off · last entered X ago” instead of the meaningless “Idle, not in deep sleep”."
        ]],
        ["Optimized", [
          "Status: the SukiSU module description is now a compact status strip (thermal / charging / scheduling) and refreshes right after you toggle a switch.",
          "Performance: the daemon takes the system time once per tick, skips thermal-zone cache validation while official and screen-off, and no longer grabs the mode lock every tick when nothing needs restoring."
        ]]
      ]},
      { version: "Beta0.2.9", groups: [
        ["Added", [
          "Display: merged GT7Pro-LTPO v2.0 — full-scene LTPO / full-brightness VRR. The installer asks with the volume keys (VOL UP = enable, VOL DOWN = skip, no key within 10 s = enabled); the Settings page has a live switch, applied after reboot.",
          "Display: systemless bind mount over /my_product/etc/oplus_vrr_config.json (drops the low-brightness LTPO exit steps, ambient, hw_nit_limit) plus a transient resetprop VRR flag; no system-partition or persistent-property writes.",
          "Settings: new Full-scene LTPO switch and state (active / enabled pending reboot / disabled)."
        ]],
        ["Fixed", [
          "Display: the installer keeps an existing LTPO choice on upgrade/reinstall, and warns when the standalone GT7PROLTPOEnhance module is present to avoid a double mount.",
          "Settings: the set command's own variables were clobbered by the config file, so switch actions matched the wrong key (they used to apply on the daemon's next cycle); switches now take effect immediately."
        ]]
      ]},
      { version: "Beta0.2.8", groups: [
        ["Fixed", [
          "Thermal: masked temperature no longer writes the socd zone. That zone is whole-°C and has a 100 °C hardware trip, so a millidegree value reads as 30100 °C and triggers OEM emergency protection — the radio drops (reproduced: voice and data OUT_OF_SERVICE, operator cleared within 5 s of enabling the mask, recovered immediately after disabling).",
          "Thermal: every masked write re-checks that the cached zone index still resolves to the intended sensor name; the cache is rebuilt when indices move, so a reordered zone can never be spoofed.",
          "Thermal: clears emulation on all zones at boot and on mode changes to remove leftovers, and clears exactly the zones it wrote when masking stops.",
          "Battery: charging power is only shown while actually charging; unplugged or full batteries show 0.0 W instead of discharge power.",
          "Battery: falls back to the battery-side estimate (dual-cell pack voltage) when the USB input node does not refresh, so a charging phone no longer shows 0.0 W.",
          "Radio: if the SIM is still LOADED but registration/operator is lost, Astra hands the thermal policy back to official after 90 s (the old check only matched ABSENT, which never fires on dual-SIM phones)."
        ]],
        ["Optimized", [
          "UI: charging state shows Charging / Full / Not charging from the real battery status and distinguishes a connected-but-idle charger.",
          "Thermal: the thermal page explains when the radio guard handed control back to the official policy."
        ]]
      ]},
      { version: "Beta0.2.7", groups: [
        ["Fixed", ["Scheduling: smooth average power over 30-second samples and reset its baseline after reboot or charge-state changes, preventing short samples from spiking the result."]],
        ["Optimized", ["Scheduling: restore current and average power plus the three most recent apps with duration, estimated energy and average power."]],
        ["Removed", ["Statistics: back up and clear legacy single-cell app samples on upgrade so dual-cell energy totals are not understated."]]
      ]},
      { version: "Beta0.2.6", groups: [
        ["Fixed", ["Scheduling: convert USB input power to equivalent battery current with the dual-cell pack voltage, preventing per-app average power from being doubled while charging."]]
      ]},
      { version: "Beta0.2.5", groups: [
        ["Fixed", ["Logs: show missing battery limit nodes as unavailable instead of reusing a previous node's value."]],
        ["Optimized", ["Battery: use the dual-cell pack voltage for battery and app drain estimates; USB input power remains measured on the input side."]]
      ]},
      { version: "Beta0.2.4", groups: [
        ["Fixed", ["Battery: avoid 32-bit overflow in Android shell arithmetic when multiplying USB current and voltage."]],
        ["Optimized", ["Status: scale to mA and mV before calculating USB input power so low and high readings stay in range."]]
      ]},
      { version: "Beta0.2.3", groups: [
        ["Added", ["Thermal: clear stale daemon PID state at boot so a reused system PID cannot suppress Astra startup."]],
        ["Fixed", ["Install: correct module metadata encoding to prevent SukiSU duplicate-directory recognition.", "Thermal: keep patched tables outside auto-mounted partition directories and mount them only in GT mode.", "Battery: read USB input current and voltage for charging power instead of estimating it from battery-side current.", "Charging: report a limit release only after a writable current node accepts and reads back the value; explain when the negotiated limit is already reached.", "Charging: allow canceling the current-session request and show no success state unless a node confirms it."]],
        ["Optimized", ["Installer: shorten banner separators to keep Astra aligned.", "Logs: include USB input, battery gauge and charging-node diagnostics.", "UI: show mounted thermal tables and categorize changelog entries."]],
        ["Removed", ["Charging: stop writing read-only fast-charge and private vendor thermal nodes, and stop marking those writes as successful."]]
      ]},
      { version: "Beta0.2.2", groups: [
        ["Added", ["Thermal: GT mode patches vendor strategy tables while retaining all levels; radio, battery, camera and hardware over-temperature files stay intact.", "Status: show mounted table count and distinguish scheduler setting from applied CPU caps."]],
        ["Fixed", ["Install: strip UTF-8 BOM from module.prop to prevent SukiSU creating a duplicate module directory.", "Thermal: serialize mode changes and persist them before applying, preventing stale boot logic from reverting the mode.", "Battery: remove stale WebUI selectors that caused a JavaScript exception.", "Scheduling: reapply and read back GPU DCVS state each cycle; recognize Scene's ignored marker."]],
        ["Optimized", ["Thermal: retain and validate every vendor strategy level; report unavailable when no valid table can be mounted.", "Logs: rotate bounded logs; debug report includes mounts, GPU, charging and CPU cap state.", "Deep sleep: explain Android Doze and note that notifications follow Android whitelist and maintenance-window rules."]],
        ["Removed", ["Battery: remove the ineffective adapter-limit and smart-charge status rows."]]
      ]},
      { version: "Beta0.2.1", groups: [["Added", ["Vendor thermal table patching and screen-off deep sleep."]], ["Fixed", ["Module BOM, thermal mode rollback, charging controls and changelog script issues."]], ["Optimized", ["Installer banner and version display."]], ["Removed", ["Two battery status items without hardware control."]]] },
      { version: "Beta0.2.0", groups: [["Added", ["Thermal switch feedback and safety handling.", "Automatic charging status and controls.", "CPU caps, GPU Boost control and deep sleep.", "Starfield WebUI and GitHub link."]]] }
    ]
  };

  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return [].slice.call((r || document).querySelectorAll(s)); }
  function t(k) { return (T[lang] && T[lang][k]) || T.zh[k] || k; }
  function c(v) { return (Number(v || 0) / 1000).toFixed(1); }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (x) { return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[x]; }); }

  /* ---------------- 桥接 ---------------- */
  function getApi() {
    if (window.ksu && typeof window.ksu.exec === "function") return window.ksu;
    if (window.$mmrl && typeof window.$mmrl.exec === "function") return window.$mmrl;
    return null;
  }

  function norm(x) {
    if (x == null) return "";
    if (typeof x === "string") return x;
    if (typeof x === "object") {
      if (typeof x.stdout === "string") return x.stdout;
      if (typeof x.result === "string") return x.result;
    }
    return String(x);
  }

  var cbSeq = 0;

  function exec(cmd) {
    return new Promise(function (resolve, reject) {
      var tries = 0;

      function attempt() {
        var api = getApi();
        if (!api) {
          if (tries++ < 40) { setTimeout(attempt, 150); return; }   // 最多等 6 秒
          reject(new Error("nobridge"));
          return;
        }
        bridge = api;
        run(api, cmd).then(resolve, reject);
      }

      function run(api, cmd) {
        function named(fn) {
          var n = "__astra_cb" + (++cbSeq);
          window[n] = function (code, stdout) { try { delete window[n]; } catch (e) { } fn(stdout || ""); };
          return n;
        }
        var forms = [
          // 1) 同步/直接返回（SukiSU 的 exec(cmd) 是同步返回 stdout 的）
          function (done, skip) {
            var r = api.exec(cmd);
            if (typeof r === "string") return done(r);
            if (r && typeof r.then === "function") return r.then(function (x) { done(norm(x)); }, skip);
            if (r !== undefined && r !== null) return done(norm(r));
          },
          // 2) exec(cmd, cbFunction)
          function (done) {
            var r = api.exec(cmd, function (code, stdout) { done(stdout || ""); });
            if (r && typeof r.then === "function") r.then(function (x) { done(norm(x)); });
          },
          // 3) exec(cmd, "{}", cbName)    ← KernelSU 官方形态
          function (done) {
            api.exec(cmd, "{}", named(done));
          },
          // 4) exec(cmd, null, cbName)    ← SukiSU 源码里 options 可为 null
          function (done) {
            api.exec(cmd, null, named(done));
          },
          // 5) exec(cmd, "{}", cbFunction)
          function (done) {
            api.exec(cmd, "{}", function (code, stdout) { done(stdout || ""); });
          },
          // 6) exec(cmd, null, cbFunction)
          function (done) {
            api.exec(cmd, null, function (code, stdout) { done(stdout || ""); });
          }
        ];

        return new Promise(function (resolve, reject) {
          var i = 0;
          function next() {
            if (i >= forms.length) { reject(new Error("exec-bridge")); return; }
            var settled = false, timer = null;
            function done(v) {
              if (settled) return;
              settled = true; clearTimeout(timer); resolve(v);
            }
            function skip(e) {
              if (settled) return;
              settled = true; clearTimeout(timer); i++; next();
            }
            timer = setTimeout(skip, 1500);
            try { forms[i](done, skip); } catch (e) { skip(e); }
          }
          next();
        });
      }

      attempt();
    });
  }

  function astra(args) { return exec("sh " + MOD + "/bin/astra " + args); }

  function toast(m) {
    var el = $("#toast"); el.textContent = m; el.classList.add("show");
    clearTimeout(el._t); el._t = setTimeout(function () { el.classList.remove("show"); }, 2200);
  }
  function banner(msg) {
    var b = $("#banner");
    if (!msg) { b.hidden = true; return; }
    b.textContent = msg; b.hidden = false;
  }

  /* ---------------- 渲染 ---------------- */
  function render(s) {
    S = s;
    var m = s.thermal.mode, mk = s.thermal.mask, ch = s.charge, sc = s.sched;
    var dp = s.display || {};

    if (m === "mask") {
      $("#tmode").textContent = Number(mk.latch) ? t("fused") : t("mask");
      $("#tmode").className = "pill " + (Number(mk.latch) ? "warn" : "on");
      $("#tbig").textContent = c(mk.applied);
      $("#thint").textContent = Number(mk.latch) ? t("hint_fuse") : t("hint_mask");
    } else if (m === "off") {
      $("#tmode").textContent = t("off"); $("#tmode").className = "pill on";
      $("#tbig").textContent = c(mk.real_batt); $("#thint").textContent = t("hint_off");
    } else {
      var radio = Number(mk.radio) === 1;
      $("#tmode").textContent = t("official");
      $("#tmode").className = "pill" + (radio ? " warn" : "");
      $("#tbig").textContent = c(mk.real_batt);
      $("#thint").textContent = radio ? t("hint_radio") : t("hint_official");
    }
    $("#rbatt").textContent = c(mk.real_batt) + "°";
    $("#rsoc").textContent = c(mk.real_soc) + "°";
    $$("#mode button").forEach(function (b) { b.classList.toggle("on", b.dataset.m === m); });
    // 这两个开关只属于温度伪装模式
    $("#maskCard").hidden = m !== "mask";
    $("#offCard").hidden = m !== "off";

    var on = m === "mask" && !Number(mk.latch);
    $("#maskTag").textContent = on ? t("on") : t("offs");
    $("#maskTag").className = "tag" + (on ? " on" : "");
    $("#maskVal").textContent = c(mk.base) + "°";
    $("#maskBase").value = Math.round(Number(mk.base) / 100);
    var wall = Number(mk.wall) ? 3000 : 0;
    $("#fuseB").textContent = c(Number(mk.fuse_batt) + wall) + "°";
    $("#fuseS").textContent = c(Number(mk.fuse_soc) + wall) + "°";
    var mounts = Number(s.thermal.mounts || 0);
    $("#offState").textContent = mounts > 0 ? mounts + " " + t("mountedCount") : t("patchUnavailable");
    $("#offState").className = mounts > 0 ? "state-ok" : "state-warn";

    var online = Number(ch.online), applied = Number(ch.applied);
    var cst = String(ch.status || "");
    $("#curPower").textContent = signed(ch.cur);
    $("#avgPower").textContent = (Number(ch.avg || 0) / 1000).toFixed(2) + " W";
    $("#cstate").textContent = online
      ? (cst === "Full" ? t("fulled") : cst === "Charging" ? t("charging") : t("notch"))
      : t("notch");
    $("#cstate").className = "pill" + (online && cst === "Charging" ? " on" : "");
    $("#cw").textContent = (Number(ch.watts) / 1000).toFixed(1);
    var guard = Number(ch.guard);
    $("#chint").textContent = !online
      ? t("notplug")
      : (cst !== "Charging" && cst !== "Full") ? t("chg_idle")
        : applied === 1 ? t("chg_full")
          : applied === 2 ? t("chg_atmax")
            : guard === 1 ? t("chg_hot")
              : guard === 2 ? t("chg_90")
                : (Number(ch.auto) || Number(ch.now)) ? t("chg_unavailable")
                : t("chg_off");
    $("#ctime").textContent = fmt(ch.elapsed);
    $("#ctemp").textContent = c(ch.temp) + "°";
    $("#cutVal").textContent = Math.round(Number(ch.cut) / 1000) + "°";
    $("#cut").value = Math.round(Number(ch.cut) / 1000);
    $("#chargeNow").classList.toggle("on", Number(ch.now) === 1);
    $("#chargeNow").textContent = Number(ch.now) === 1 ? t("nowoff") : t("nowbtn");
    var capApplied = Number(sc.save_applied) === 1;
    $("#sstate").textContent = Number(sc.scene) ? t("sceneon")
      : Number(sc.game) ? t("ingame")
        : (Number(sc.save) ? (capApplied ? t("capped") : t("cap_failed")) : t("uncapped"));
    $("#sstate").className = "pill" + (capApplied || Number(sc.scene) ? " on" : Number(sc.save) ? " warn" : "");
    $("#caps").textContent = (Number(sc.little) / 1e6).toFixed(2) + " / " + (Number(sc.prime) / 1e6).toFixed(2);
    $("#shint").textContent = Number(sc.scene) ? t("sceneon")
      : Number(sc.game) ? t("ingame")
      : (Number(sc.save) ? (capApplied ? t("capped") : t("cap_failed")) : t("uncapped"));

    $("#dModel").textContent = s.device.model;
    $("#dRom").textContent = s.device.rom;
    $("#dKernel").textContent = s.device.kernel;
    $("#dRoot").textContent = s.device.root;
    $("#dVer").textContent = "Astra " + s.version;

    var vals = { RAISE_WALL: mk.wall, CHARGE_AUTO: ch.auto, SAVE_ENABLED: sc.save, DISABLE_GPU_BOOST: sc.gpu, DEEP_SLEEP: sc.deep, LTPO_ENABLE: dp.ltpo };
    $$(".switchrow[data-k]").forEach(function (el) {
      var k = el.dataset.k, sw = $(".sw", el);
      sw.classList.toggle("on", Number(vals[k]) === 1);
      if (k === "DISABLE_GPU_BOOST") {
        var forced = Number(sc.gpu_forced) === 1;
        sw.classList.toggle("dim", forced);
        $("#gpuHint").textContent = sc.gpu_state === "failed" ? t("gpu_failed") : forced ? t("gpu_forced") : t("gpu_free");
      }
      if (k === "DEEP_SLEEP") {
        var dh = $("#deepHint");
        if (!dh) return;
        if (Number(vals[k]) !== 1) {
          dh.textContent = t("deep_off");
        } else {
          var dsLast = Number(sc.dslast || 0);
          var dsTxt = t("deep_ready");
          if (dsLast > 0) dsTxt += " · " + t("deep_last") + ago(Math.floor(Date.now() / 1000) - dsLast);
          dh.textContent = Number(sc.dsactive) === 1 ? t("deep_on") : dsTxt;
        }
      }
      if (k === "LTPO_ENABLE") {
        var lh = $("#ltpoHint");
        if (!lh) return;
        lh.textContent = Number(vals[k]) !== 1 ? t("ltpo_off")
          : Number(dp.mounted) === 1 ? t("ltpo_live")
            : t("ltpo_pending");
      }
    });
  }

  function fmt(sec) {
    sec = Number(sec || 0);
    if (!sec) return "—";
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    if (h > 0) return h + "h " + m + "m";
    if (m > 0) return m + "m";
    return Math.floor(sec) + "s";
  }
  function signed(mw) {
    var v = Number(mw || 0) / 1000;
    if (v > 0) return "+" + v.toFixed(2) + " W";
    if (v < 0) return "-" + Math.abs(v).toFixed(2) + " W";
    return "0.00 W";
  }
  function ago(sec) {
    sec = Number(sec || 0);
    if (sec < 60) return t("ago0");
    if (sec < 3600) return Math.floor(sec / 60) + " " + t("agom");
    if (sec < 86400) return Math.floor(sec / 3600) + " " + t("agoh");
    return Math.floor(sec / 86400) + " " + t("agod");
  }

  function loadApps(force) {
    if (!MOD) return Promise.resolve();
    var now = Date.now();
    if (!force && now - appsAt < 30000) return Promise.resolve();
    appsAt = now;
    return astra("apps").then(function (out) {
      var items;
      try { items = JSON.parse(out); } catch (e) { throw new Error("apps-json"); }
      var root = $("#appsList");
      while (root.firstChild) root.removeChild(root.firstChild);
      if (!Array.isArray(items) || !items.length) {
        var empty = document.createElement("div"); empty.className = "apps-empty";
        empty.textContent = t("appsnone"); root.appendChild(empty); return;
      }
      var maxMah = Math.max.apply(null, items.map(function (x) { return Number(String(x.mah || "0").replace(/[^0-9.]/g, "")) || 0; })) || 1;
      items.slice(0, 3).forEach(function (item) {
        var row = document.createElement("div"); row.className = "app";
        var mid = document.createElement("div"); mid.className = "mid";
        var name = document.createElement("div"); name.className = "nm"; name.textContent = item.label || item.pkg || "—";
        var bar = document.createElement("div"); bar.className = "bar";
        var fill = document.createElement("i");
        var mah = Number(String(item.mah || "0").replace(/[^0-9.]/g, "")) || 0;
        fill.style.width = Math.max(4, Math.min(100, mah / maxMah * 100)) + "%";
        bar.appendChild(fill);
        var meta = document.createElement("div"); meta.className = "meta";
        meta.textContent = fmt(item.dur) + " · " + (item.mah || "0.0") + " mAh · " + ago(item.ago);
        mid.appendChild(name); mid.appendChild(bar); mid.appendChild(meta);
        var val = document.createElement("div"); val.className = "val";
        var watts = document.createElement("b"); watts.textContent = (item.w || "0.00") + " W";
        var avg = document.createElement("span"); avg.textContent = t("appavg");
        val.appendChild(watts); val.appendChild(avg);
        row.appendChild(mid); row.appendChild(val); root.appendChild(row);
      });
    }).catch(function () {
      var root = $("#appsList");
      while (root.firstChild) root.removeChild(root.firstChild);
      var empty = document.createElement("div"); empty.className = "apps-empty";
      empty.textContent = t("appsnone"); root.appendChild(empty);
    });
  }

  /* ---------------- 数据 ---------------- */
  function load() {
    if (!MOD) return Promise.resolve();
    return astra("status").then(function (out) {
      var j;
      try { j = JSON.parse(out); } catch (e) { throw new Error("json[" + String(out).replace(/\s+/g, " ").slice(0, 90) + "]"); }
      render(j); banner("");
      return loadApps(false);
    }).catch(function (e) {
      banner(t("failed") + " · " + e.message);
    });
  }

  function act(cmd) {
    if (busy || !MOD) return;
    busy = true;
    astra(cmd).then(function (out) {
      var j;
      try { j = JSON.parse(out); } catch (e) { throw new Error("json[" + String(out).replace(/\s+/g, " ").slice(0, 90) + "]"); }
      render(j); banner("");
    }).catch(function (e) {
      toast(t("failed") + ": " + e.message);
    }).then(function () { busy = false; });
  }

  /* 切换类操作：盖一层 5 秒遮罩，确认命令确实生效后再放开，避免"看起来没反应" */
  function applyOverlay(cmd, label) {
    if (busy || !MOD) return;
    busy = true;
    var ov = $("#overlay"), txt = $("#ovtext");
    txt.textContent = (lang === "zh" ? "正在切换到 " + label + "…" : "Switching to " + label + "…");
    ov.hidden = false;
    ov.classList.remove("ok");
    var t0 = Date.now();
    astra(cmd).then(function (out) {
      var j = JSON.parse(out);
      render(j);
      var wait = Math.max(0, 3200 - (Date.now() - t0));
      return new Promise(function (res) { setTimeout(res, wait); }).then(function () {
        return astra("status");
      }).then(function (out2) {
        render(JSON.parse(out2));
        txt.textContent = (lang === "zh" ? "已生效 ✓ " : "Applied ✓ ") + label;
        ov.classList.add("ok");
        return new Promise(function (res) { setTimeout(res, 1000); });
      });
    }).catch(function (e) {
      txt.textContent = t("failed") + ": " + e.message;
    }).then(function () {
      setTimeout(function () { ov.hidden = true; busy = false; }, 300);
    });
  }

  /* ---------------- 绑定 ---------------- */
  function bind() {
    $$(".dock button").forEach(function (b) {
      b.addEventListener("click", function () {
        $$(".dock button").forEach(function (x) { x.classList.toggle("on", x === b); });
        $$(".page").forEach(function (p) { p.hidden = p.id !== "p-" + b.dataset.p; });
        window.scrollTo(0, 0);
        if (b.dataset.p === "sched") { appsAt = 0; loadApps(true); }
      });
    });

    $("#refresh").addEventListener("click", function () {
      var el = this; el.classList.add("spin");
      if (!MOD) { init(); return; }
      appsAt = 0;
      load().then(function () { setTimeout(function () { el.classList.remove("spin"); }, 400); });
    });

    $$("#mode button").forEach(function (b) {
      b.addEventListener("click", function () {
        var m = b.dataset.m;
        var label = m === "mask" ? t("mask") : m === "off" ? t("off") : t("official");
        applyOverlay("thermal " + m, label);
      });
    });

    $("#maskBase").addEventListener("change", function () { act("set MASK_BASE " + (this.value * 100)); });
    $("#maskBase").addEventListener("input", function () { $("#maskVal").textContent = (this.value / 10).toFixed(1) + "°"; });

    $("#cut").addEventListener("change", function () { act("set CHARGE_TEMP_CUT " + (this.value * 1000)); });
    $("#cut").addEventListener("input", function () { $("#cutVal").textContent = this.value + "°"; });

    $$(".switchrow[data-k]").forEach(function (el) {
      el.addEventListener("click", function () {
        var k = el.dataset.k, sw = $(".sw", el);
        if (k === "GPU_BOOST" || k === "DISABLE_GPU_BOOST") {
          if (sw.classList.contains("dim")) { toast(t("gpu_forced")); return; }
        }
        var next = sw.classList.contains("on") ? 0 : 1;
        sw.classList.toggle("on", next === 1);
        if (k === "SAVE_ENABLED") act("sched save " + (next ? "on" : "off"));
        else if (k === "DISABLE_GPU_BOOST") act("sched gpu " + (next ? "on" : "off"));
        else if (k === "DEEP_SLEEP") act("sched deep " + (next ? "on" : "off"));
        else act("set " + k + " " + next);
      });
    });

    $("#chargeNow").addEventListener("click", function () {
      if (!S || Number(S.charge.online) !== 1) { toast(t("plugfirst")); return; }
      act("charge now " + (Number(S.charge.now) === 1 ? "off" : "on"));
    });

    $$("#langRow .mini button").forEach(function (b) {
      b.addEventListener("click", function (e) {
        e.stopPropagation();
        setLang(b.dataset.lang);
        if (MOD) astra("set LANG " + lang).catch(function () { });
      });
    });

    $("#report").addEventListener("click", function () {
      if (!MOD) return;
      astra("report").then(function (p) { toast(t("saved") + " " + p); }).catch(function () { toast(t("failed")); });
    });
  }

  function setLang(l) {
    lang = l === "en" ? "en" : "zh";
    document.documentElement.lang = lang;
    $$("[data-i18n]").forEach(function (el) { el.textContent = t(el.getAttribute("data-i18n")); });
    $("#langNow").textContent = lang === "zh" ? "中文" : "English";
    $$("#langRow .mini button").forEach(function (b) { b.classList.toggle("on", b.dataset.lang === lang); });
    renderChangelog();
    if (MOD) loadApps(true);
    greet(); if (S) render(S);
  }

  function renderChangelog() {
    var root = $("#changelog");
    while (root.firstChild) root.removeChild(root.firstChild);
    (CHANGELOG[lang] || CHANGELOG.zh).forEach(function (entry) {
      var article = document.createElement("article"); article.className = "change-entry";
      var title = document.createElement("h3"); title.textContent = entry.version; article.appendChild(title);
      entry.groups.forEach(function (group) {
        var section = document.createElement("section"); section.className = "change-group";
        var heading = document.createElement("h4"); heading.textContent = group[0]; section.appendChild(heading);
        var list = document.createElement("ul");
        group[1].forEach(function (item) { var li = document.createElement("li"); li.textContent = item; list.appendChild(li); });
        section.appendChild(list); article.appendChild(section);
      });
      root.appendChild(article);
    });
  }

  function greet() {
    var h = new Date().getHours();
    $("#greet").textContent = t(h < 5 ? "g0" : h < 12 ? "g1" : h < 18 ? "g2" : "g3");
  }

  function init() {
    if (!getApi()) {
      banner(t("connecting"));
      setTimeout(function () {
        if (!getApi()) {
          var g = [];
          try {
            for (var k in window) { if (/ksu|mmrl|webui|android/i.test(k)) g.push(k); }
          } catch (e) { }
          banner(t("nobridge") + " [" + g.slice(0, 8).join(", ") + "]");
          return;
        }
        init();
      }, 400);
      return;
    }
    exec("for d in /data/adb/modules/astra /data/adb/modules_update/astra; do [ -f $d/bin/astra ] && { echo $d; break; }; done")
      .then(function (dir) {
        dir = (dir || "").trim().split("\n")[0];
        if (!dir) { banner(t("nodir")); return; }
        MOD = dir;
        banner("");
        return load().then(function () {
          if (poll) clearInterval(poll);
          poll = setInterval(function () { if (!busy && !document.hidden) load(); }, 6000);
          document.addEventListener("visibilitychange", function () { if (!document.hidden) load(); });
        });
      })
      .catch(function (e) {
        banner((e.message === "nobridge" ? t("nobridge") : t("failed") + " · " + e.message));
      });
  }

  /* ---------------- 星空（Astra） ---------------- */
  function stars() {
    var cv = document.getElementById("stars");
    if (!cv || !cv.getContext) return;
    var ctx = cv.getContext("2d"), w, h, list = [];
    function resize() {
      w = cv.width = window.innerWidth;
      h = cv.height = window.innerHeight;
      list = [];
      var n = Math.round(w * h / 14000);
      if (n > 130) n = 130;
      for (var i = 0; i < n; i++) {
        list.push({
          x: Math.random() * w, y: Math.random() * h,
          r: Math.random() * 1.25 + 0.35,
          p: Math.random() * Math.PI * 2,
          s: 0.35 + Math.random() * 0.9,
          v: 0.02 + Math.random() * 0.05
        });
      }
    }
    resize();
    window.addEventListener("resize", resize);
    var t = 0;
    function frame() {
      t += 0.016;
      ctx.clearRect(0, 0, w, h);
      for (var i = 0; i < list.length; i++) {
        var st = list[i];
        st.y -= st.v;
        if (st.y < -2) { st.y = h + 2; st.x = Math.random() * w; }
        var a = 0.28 + 0.62 * Math.abs(Math.sin(t * st.s + st.p));
        ctx.beginPath();
        ctx.fillStyle = i % 7 === 0 ? "rgba(169,240,230," + a * 0.9 + ")" : "rgba(255,255,255," + a + ")";
        ctx.arc(st.x, st.y, st.r, 0, 6.2832);
        ctx.fill();
      }
      requestAnimationFrame(frame);
    }
    frame();
  }

  function boot() {
    setLang("zh");
    stars();
    bind();
    init();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
