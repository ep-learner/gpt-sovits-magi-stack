# gpt-sovits-magi-stack

用 **GPT-SoVITS** 克隆音色 + **MAGI** 阅读器听小说的本地落地全套方案。
8 GB 显存（RTX 4060 Ti）即可跑通，造一个音色模型约 1 小时（训练本身几分钟），之后每次听书就是「双击起服务 → 打开阅读器 → 点朗读」。

```
GPT-SoVITS（造音色 + 出音频，端口 9880）  →  MAGI（阅读器，显示 + 逐句播放）
```

## 仓库内容

```
gpt-sovits-magi-stack/
├── docs/
│   ├── 00-原始PRD.md      原始教程（需求来源，原样存档）
│   ├── 01-技术方案.md      完整技术方案与选型
│   ├── 02-架构说明.md      软件职责、数据流、ASCII 架构图
│   └── 03-使用文档.md      从零到跑通的操作手册 + 踩坑排查
├── scripts/
│   ├── train_v2pro.py     无头一键训练驱动（复用 WebUI 逻辑，v2Pro 默认参数，关 DPO）
│   ├── start-api.bat       一键起 API 服务（端口 9880，含占用检查）
│   └── test-tts.ps1        /tts 接口冒烟测试
├── config/
│   └── magi-config.example.txt   MAGI 阅读器四项配置示例
├── QA.md                 换音色 / 要不要重训 / 数据量 等高频问答
└── README.md
```

> 大文件不放仓库：GPT-SoVITS 整合包（~13 GB）、MAGI 阅读器、训练素材、模型权重均放在仓库外（见 [使用文档](docs/03-使用文档.md) 的目录约定）。

## 三步跑通

1. **训练** — 素材切片 → ASR → 校对 → 运行 `scripts/train_v2pro.py`（详见 [使用文档 §二](docs/03-使用文档.md)）。
2. **起服务** — 双击 `scripts/start-api.bat`，等 `Uvicorn running on http://127.0.0.1:9880`。
3. **打开阅读器** — MAGI 配置已预写入 `library.json`，直接导入书点朗读即可（详见 [使用文档 §二.6](docs/03-使用文档.md)）。

> 想换新音色 / 纠结要不要重新训练 / 数据量多少合适？看 [QA.md](QA.md)。

## 关键认知

- 阅读器连的是 **API（端口 9880）**，不是 WebUI（9871~9874）。
- 8 GB 卡选 **v2Pro** 全量微调（v3/v4 只能 LoRA，v5 跑不动），参数全默认、**DPO 关闭**。
- 参考音频决定音色；提示文本必须与参考音频**逐字一致**。
- 所有 Python 进程设置 `NUMBA_CACHE_DIR` 到 C 盘，规避嵌入 Python 的 numba 缓存问题。

## 合规

克隆可识别真人声音需本人授权；公开发布基于 GPT-SoVITS 的作品需署名 GPT-SoVITS。详见 [使用文档 §五](docs/03-使用文档.md)。
