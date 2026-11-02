/* Astra WebUI  Beta0.1.07
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
      patch: "补丁状态", unmounted: "未挂载",
      pw: "充电功率", charging: "充电中", notch: "未充电", fulled: "已充满",
      notplug: "未连接充电器", dur: "充电时长", btemp: "电池温度",
      chg_full: "已接管：满血充电（90% 前最快）", chg_hot: "温度到线，已交还官方充电",
      chg_90: "已到 90%，交还官方阶梯充电", chg_off: "未接管，官方策略",
      admax: "本次接口上限", simax: "系统智能极速充电",
      autot: "每次充电自动满血", autos: "插电接管，拔线还原",
      nowbtn: "本次充电满血", notice: "当前充电已开启满血充电",
      cut: "温度保护线", cuth: "到达保护线或电量 90% 自动交还官方充电策略。",
      deep: "深度睡眠", deep_s: "熄屏 20 秒且未充电进入 doze；音乐/通话/亮屏/充电立即退出",
      deep_on: "已进入深度睡眠", deep_off: "待机中，未进入深度睡眠",
      bit_hint: "电池详情（剩余电量 / 健康度 / 循环 / 容量曲线）将在 Astra App 提供。",
      remain: "剩余电量", percent: "电量百分比", health: "电池健康", design: "设计容量",
      fullcap: "满充容量", cycle: "循环次数",
      sched: "调度", capped: "限频中", uncapped: "未限制", ingame: "游戏 · 已暂停限频",
      sceneon: "Scene 接管",
      save: "官调限频", save_s: "官方调度不变，只封顶最高频率",
      gamehint: "游戏中会自动暂停限频，退出游戏后恢复；检测到 Scene 正在调度前台应用时也会自动让出。",
      gpu: "禁用 GPU Boost", gpu_s: "开启则关闭 GPU 的 DCVS 提升；关闭为系统默认",
      gpu_forced: "官调限频开启时强制禁用", gpu_free: "可自由开关",
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
      patch: "Patch state", unmounted: "Not mounted",
      pw: "Power", charging: "Charging", notch: "Not charging", fulled: "Full",
      notplug: "No charger", dur: "Duration", btemp: "Battery temp",
      chg_full: "Active: full speed (until 90%)", chg_hot: "Temp guard — official charging",
      chg_90: "90% reached — official step charging", chg_off: "Not active — official policy",
      admax: "Port limit", simax: "System smart charge",
      autot: "Full speed every charge", autos: "Applies on plug-in, reverts on unplug",
      nowbtn: "Full speed this charge", notice: "Full-speed charging enabled for this session",
      cut: "Temperature guard", cuth: "Reverts at the guard temperature or 90% charge.",
      deep: "Deep sleep", deep_s: "Doze 20s after screen off; music/calls/screen/charging exit it",
      deep_on: "In deep sleep", deep_off: "Idle, not in deep sleep",
      bit_hint: "Battery details (remaining / health / cycles / curve) arrive with the Astra App.",
      remain: "Remaining", percent: "Level", health: "Health", design: "Design",
      fullcap: "Full charge", cycle: "Cycles",
      sched: "Scheduling", capped: "Capped", uncapped: "Unrestricted", ingame: "Game · cap paused",
      sceneon: "Scene in control",
      save: "Official-clock cap", save_s: "Official governor unchanged, only the ceiling drops",
      gamehint: "The cap pauses in games, and yields when Scene is scheduling the foreground app.",
      gpu: "Disable GPU Boost", gpu_s: "Turns off the GPU DCVS boost; off = system default",
      gpu_forced: "Forced while the clock cap is on", gpu_free: "Free to toggle",
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
    zh: "Beta0.2.0\n· 温控：切换模式显示 5 秒“正在切换/已生效”，GT去温控明确提示需重启\n· 温控：只保留降温策略表补丁（不再动 ThermalService 全局配置与高温保护阈值），并新增掉信号保护（射频热区不碰、SIM 异常自动回官方、15 分钟 3 次重启强制安全模式）\n· 电池：修复功率显示需要手动刷新；满血充电改为拉满输入电流+快充开关，90% 交还官方阶梯充电，保留温度保护\n· 电池：电池信息栏改为 Coming Soon\n· 调度：官调限频强化（同时写 msm_performance 与各 policy），内置双电芯补偿，游戏/横屏非视频自动交还，新增深度睡眠\n· 界面：星空效果、GitHub 入口、排版微调\n\nBeta0.1.13\n· 禁用 GPU Boost 语义纠正\n\nBeta0.1.12\n· 耗电统计 Coming Soon\n\nBeta0.1.11\n· 当前功耗带符号；平均功耗改为放电会话平均",
    en: "Beta0.2.0\n· Thermal: 5s switching overlay; GT mode shows a reboot note\n· Thermal: only strategy tables are patched (ThermalService and high-temp thresholds untouched); new signal guard (RF zones skipped, SIM-absent auto revert, safe mode after 3 fast boots)\n· Battery: power refreshes on its own; full-speed charging raises input current + fast-charge flag, hands back at 90%, keeps the temperature guard\n· Battery: info grid is Coming Soon\n· Sched: stronger official-clock cap, built-in dual-cell compensation, landscape non-video hands back, new deep sleep\n· UI: starfield, GitHub link, layout polish\n\nBeta0.1.13\n· GPU Boost switch semantics fixed\n\nBeta0.1.12\n· Usage card is a placeholder\n\nBeta0.1.11\n· Signed current power; session-average power"
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

    if (m === "mask") {
      $("#tmode").textContent = Number(mk.latch) ? t("fused") : t("mask");
      $("#tmode").className = "pill " + (Number(mk.latch) ? "warn" : "on");
      $("#tbig").textContent = c(mk.applied);
      $("#thint").textContent = Number(mk.latch) ? t("hint_fuse") : t("hint_mask");
    } else if (m === "off") {
      $("#tmode").textContent = t("off"); $("#tmode").className = "pill on";
      $("#tbig").textContent = c(mk.real_batt); $("#thint").textContent = t("hint_off");
    } else {
      $("#tmode").textContent = t("official"); $("#tmode").className = "pill";
      $("#tbig").textContent = c(mk.real_batt); $("#thint").textContent = t("hint_official");
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
    $("#offState").textContent = Number(s.thermal.off) ? t("on") : t("offs");

    var online = Number(ch.online), applied = Number(ch.applied);
    $("#cstate").textContent = online ? (ch.status === "Full" ? t("fulled") : t("charging")) : t("notch");
    $("#cstate").className = "pill" + (online ? " on" : "");
    $("#cw").textContent = (Number(ch.watts) / 1000).toFixed(1);
    var guard = Number(ch.guard);
    $("#chint").textContent = online
      ? (applied ? t("chg_full")
        : guard === 1 ? t("chg_hot")
          : guard === 2 ? t("chg_90")
            : t("chg_off"))
      : t("notplug");
    $("#ctime").textContent = fmt(ch.elapsed);
    $("#ctemp").textContent = c(ch.temp) + "°";
    $("#cutVal").textContent = Math.round(Number(ch.cut) / 1000) + "°";
    $("#cut").value = Math.round(Number(ch.cut) / 1000);
    $("#cnotice").hidden = Number(ch.now) !== 1;
    $("#chargeNow").classList.toggle("on", Number(ch.now) === 1);
    var am = Number(ch.admax || 0);
    $("#admax").textContent = am > 0 ? (am / 1000).toFixed(1) + " W" : "—";
    $("#simax").textContent = Number(ch.smart) ? t("on") : t("offs");

    $("#sstate").textContent = Number(sc.scene) ? t("sceneon")
      : Number(sc.game) ? t("ingame")
        : (Number(sc.save) ? t("capped") : t("uncapped"));
    $("#sstate").className = "pill" + (Number(sc.save) || Number(sc.scene) ? " on" : "");
    $("#caps").textContent = (Number(sc.little) / 1e6).toFixed(2) + " / " + (Number(sc.prime) / 1e6).toFixed(2);
    $("#shint").textContent = Number(sc.scene) ? t("sceneon")
      : Number(sc.game) ? t("ingame")
        : (Number(sc.save) ? t("capped") : t("uncapped"));

    $("#dModel").textContent = s.device.model;
    $("#dRom").textContent = s.device.rom;
    $("#dKernel").textContent = s.device.kernel;
    $("#dRoot").textContent = s.device.root;
    $("#dVer").textContent = "Astra " + s.version;

    var vals = { RAISE_WALL: mk.wall, CHARGE_AUTO: ch.auto, SAVE_ENABLED: sc.save, DISABLE_GPU_BOOST: sc.gpu, DEEP_SLEEP: sc.deep };
    $$(".switchrow[data-k]").forEach(function (el) {
      var k = el.dataset.k, sw = $(".sw", el);
      sw.classList.toggle("on", Number(vals[k]) === 1);
      if (k === "DISABLE_GPU_BOOST") {
        var forced = Number(sc.gpu_forced) === 1;
        sw.classList.toggle("dim", forced);
        $("#gpuHint").textContent = forced ? t("gpu_forced") : t("gpu_free");
      }
      if (k === "DEEP_SLEEP") {
        $("#deepHint").textContent = Number(sc.dsactive) ? t("deep_on") : t("deep_off");
      }
    });
  }

  function fmt(sec) {
    sec = Number(sec || 0);
    if (!sec) return "—";
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    return h > 0 ? h + "h " + m + "m" : m + "m";
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

  /* ---------------- 数据 ---------------- */
  function load() {
    if (!MOD) return Promise.resolve();
    return astra("status").then(function (out) {
      var j;
      try { j = JSON.parse(out); } catch (e) { throw new Error("json[" + String(out).replace(/\s+/g, " ").slice(0, 90) + "]"); }
      render(j); banner("");
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
      act("charge now on");
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
    $("#changelog").textContent = CHANGELOG[lang];
    greet(); if (S) render(S);
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
