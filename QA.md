# QA — 常见问题与换音色指南

> 配套 [docs/03-使用文档.md](docs/03-使用文档.md)。这里回答「跑通之后怎么换音色、要不要重新训练、数据量多少合适」等高频问题。

---

## Q1：下次想用新的音色，怎么做？在 `input\` 里加音频然后跑脚本就行？需要 Agent 帮忙训练吗？自己跑会不会报错？之前跑了很久，是不是直接触发脚本有坑？

### 一句话流程
`input\` 放新音频 → 切片+ASR → 跑 `train_v2pro.py` → 产出新权重 → 改 `tts_infer.yaml` 指向新权重 → 重启 API → 换 MAGI 的参考音频/提示文本 → 完成。

### 需要 Agent 帮忙吗？
- **首次搭环境**需要（整合包解压、`users.pth` 路径修复、`NUMBA_CACHE_DIR` 配置、首次训练验证）—— 这些已经做完了。
- **之后换新音色**：你自己跑脚本就行，不需要 Agent。照着 [docs/03](docs/03-使用文档.md) 第二节的命令复制执行即可。
- 如果自己跑报错了，把错误信息贴给 Agent，帮忙排查比从头跑快。

### 自己跑会不会报错？—— 分清「Agent 沙箱的坑」和「真坑」

| 坑 | 是不是你自己跑也会遇到 | 说明 |
|---|---|---|
| 后台进程写 D 盘被拒（`PermissionError`） | ❌ 不会 | 这是 **Agent 工具沙箱**的限制。你在自己的 PowerShell / 终端里前台跑，完全没这个问题。 |
| 单条命令 10 分钟超时，必须分 `--stage` 跑 | ❌ 不会 | 这是 **Agent 工具的执行超时**，不是脚本限制。你自己跑可以直接 `--stage all` 一次跑完，不用分段。 |
| PowerShell 的 `Copy-Item`/`Set-Content` 写 D 盘偶发拒绝 | ❌ 不会 | Agent 工具的限制。你自己操作文件管理器或终端没问题。 |
| **`NUMBA_CACHE_DIR` 没设 → numba/librosa `cannot cache ... no locator`** | ✅ 会 | **真坑。** 每次跑训练/API 前都要设：`$env:NUMBA_CACHE_DIR = "C:\Users\admin\.cache\numba"`。`start-api.bat` 已内置，训练命令记得带。 |
| 训练 OOM / `CUDA out of memory` | ✅ 可能 | 关安卓模拟器、游戏、视频播放器、多余浏览器标签，确认 `nvidia-smi` 空闲 ≥6 GB。 |
| `ModuleNotFoundError: No module named 'tools'` | ❌ 已修复 | 整合包 `users.pth` 路径问题已修好，不用管。 |

### 「之前跑了很久」是不是脚本有坑？
**不是坑，是训练本身就需要时间。** 当时分了三阶段跑，是为了绕开 Agent 单条命令 10 分钟超时，不是脚本慢或卡住。

在 RTX 4060 Ti 8G 上的正常耗时（参考，随素材量浮动）：
- 1abc 预处理：1~2 分钟
- 1Ba SoVITS 8 epoch：3~6 分钟
- 1Bb GPT 15 epoch：3~6 分钟
- **合计约 8~15 分钟**，属正常。终端里会持续打印 loss，不是卡死。

你自己跑直接一条命令 `--stage all` 就行，它会顺序跑完三个阶段，不用分段。

### 换新音色的完整命令（替换 `newvoice` 为你的实验名）
```powershell
$v = "D:\GPT-SoVITS-stack\GPT-SoVITS-v2pro-20250604"
$env:NUMBA_CACHE_DIR = "C:\Users\admin\.cache\numba"
New-Item -ItemType Directory -Force -Path $env:NUMBA_CACHE_DIR | Out-Null
cd $v

# 1) 切片
& "$v\runtime\python.exe" -s tools/slice_audio.py "D:\GPT-SoVITS-stack\input\你的新音频.wav" "$v\output\slicer_opt\newvoice" "-34" "4000" "300" "10" "500" "0.9" "0.25" "0" "1"
# 2) ASR
& "$v\runtime\python.exe" -s tools/asr/funasr_asr.py -i "$v\output\slicer_opt\newvoice" -o "$v\output\asr_opt" -l zh
# 3) 校对 output\asr_opt\newvoice.list，删掉 >15 秒的片段
# 4) 训练（一次跑完）
& "$v\runtime\python.exe" "C:\Users\admin\Documents\Trae-CN\default\gpt-sovits-magi-stack\scripts\train_v2pro.py" --exp newvoice --list "$v\output\asr_opt\newvoice.list" --wav "$v\output\slicer_opt\newvoice"
```
训练完会产出 `SoVITS_weights_v2Pro\newvoice_*.pth` 和 `GPT_weights_v2Pro\newvoice*.ckpt`，然后按 Q2 切换。

---

## Q2：训练出来的结果，直接给 MAGI 用就好？

**是的，但要分清「两端」，换音色时两端都要同步改：**

```
┌─────────────────────┐    HTTP /tts     ┌──────────────────────┐
│  MAGI（阅读器）      │ ───────────────► │  API（api_v2.py:9880）│
│  决定"用哪段参考音频"│                  │  决定"加载哪个模型权重"│
│  refAudioPath       │                  │  tts_infer.yaml       │
│  promptText         │                  │  custom 段            │
└─────────────────────┘                  └──────────────────────┘
```

| 端 | 改什么 | 在哪改 |
|---|---|---|
| **API 端** | 训练好的模型权重 | `GPT_SoVITS\configs\tts_infer.yaml` 的 `custom:` 段 → `t2s_weights_path` / `vits_weights_path` |
| **MAGI 端** | 推理参考音频 + 提示文本 | MAGI 设置，或 `library.json` 的 `settings.tts`（`refAudioPath` / `promptText`） |

**换音色的完整动作：**
1. 训练完拿到新权重（`newvoice_e8_s*.pth` + `newvoice-e15.ckpt`）。
2. 改 `tts_infer.yaml` 的 `custom:` 段指向新权重，**重启 API**（关窗口重开 `start-api.bat`）。也可以用 `/set_gpt_weights`、`/set_sovits_weights` 端点热切换，不用重启。
3. 改 MAGI 的参考音频和提示文本为**新音色的切片**（从 `output\slicer_opt\newvoice\` 里挑一条 3~6 秒干净的，提示文本用它的 ASR 结果逐字填写）。改 `library.json` 前先关 MAGI。
4. 冒烟测试确认音色对，再开始听书。

> 只换同一模型下的不同说话风格/语气 → 只改 MAGI 端的参考音频就行，API 端不用动。

---

## Q3：训练时只能用 3~6 秒的音频吗？同一个人的音色不需要重新训练？输入越少模型越难表征音色，是不是数据越多越好？

这是个**概念混淆**，先把两个「长度」分清楚：

### 1. 「3~6 秒」是**推理参考音频**的限制，不是训练集的限制
- 文档里说的「3~6 秒、超 10 秒报错」，指的是 **MAGI 请求 `/tts` 时传的 `ref_audio_path`**（推理时给模型听的那一小段，用来锁定本次合成的音色）。这段太长会报错。
- **训练集**没有这个限制。训练用的原始音频可以是 **1 分钟到几十分钟**，程序会自动切成 3~10 秒的片段（`slice_audio.py`），每条片段单独作为一条训练样本。切片超过 15 秒的建议删掉（容易出怪声），但 3~10 秒的正常用。

### 2. 同一个人的音色，需要重新训练吗？—— 看情况
GPT-SoVITS 是**零样本声音克隆**模型。它训练时学的不是「记住某个人的声音」，而是「学会从任意一段参考音频里提取音色特征，再把这个音色用到新文本上」。

所以：
- **目标音色已经在训练集里（或非常接近）** → **不用重新训练**。直接在 MAGI 里换一段该人的参考音频（3~6 秒）+ 对应提示文本，就能用这个音色朗读。模型见过这个人，零样本就能出好效果。
- **目标音色是全新的人 / 与训练集差异大**（不同性别、年龄、语言、声线）→ 零样本也能出声，但**质量会明显下降**（音色不像、韵律飘、吞字）。想要好效果，需要把这个人的音频加入训练集**重新微调**。

> 类比：模型像一个「会模仿的演员」。训练集是它「学过模仿的人」。学过的人，给句台词就能演；没学过的人，也能模仿个大概但不像，要让它先跟这个人学一段时间（重新训练）。

### 3. 数据量和效果的关系
| 训练集总时长 | 效果 | 说明 |
|---|---|---|
| < 30 秒 | 勉强出声，质量差 | 不推荐，音素覆盖不全 |
| 1~3 分钟 | 可克隆，基本能用 | 最小可行集（本次约 1~2 分钟，23 条切片，属于这档） |
| 5~10 分钟 | 较稳，韵律自然 | 官方推荐区间，性价比最高 |
| 10~30 分钟 | 更好，细节更丰富 | 边际收益开始递减 |
| > 30 分钟 | 提升有限，训练变慢 | 除非追求极致，否则没必要 |

**结论：**
- 数据**不是越多越好到线性增长**，10 分钟以内基本是「越多越稳」，超过后边际收益递减，而训练时间线性增长。
- 关键不是单条多长，而是**总时长 + 覆盖的音素/韵律多样性**：有轻声、有不同声调、有不同语气的句子，比单纯堆时长更有用。
- 本次用的是「最小可行集」，能跑通、能听，但如果你觉得某些字音不准或语气单调，**把训练素材加到 5~10 分钟重新训一次**，效果会有可感知的提升。

---

## 快速对照：你现在能做什么

| 想做的事 | 要不要重新训练 | 动作 |
|---|---|---|
| 用现在的「仙工」音色听书 | ❌ 不用 | 直接打开 MAGI 听（已预配置好） |
| 换「仙工」的另一段语气/风格朗读 | ❌ 不用 | 只在 MAGI 换参考音频 + 提示文本 |
| 用一个**没训练过的新音色** | ✅ 要 | 按 Q1 流程训练 + Q2 切换 |
| 觉得现在音色质量不够好 | ✅ 建议 | 把素材加到 5~10 分钟，用 `--exp xiangong` 重新训（覆盖产出） |
