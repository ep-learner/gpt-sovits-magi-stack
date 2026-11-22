# gpt-sovits-magi-stack

用 **GPT-SoVITS** 克隆音色 + **MAGI** 阅读器听小说的本地方案。
日常操作集中在中文图形启动器：选音频、训练、切换、试听、打开 MAGI，都不需要手动敲命令。

```
GPT-SoVITS（造音色 + 出音频，端口 9880）  →  MAGI（阅读器，显示 + 逐句播放）
```

## 新电脑首次使用

把仓库交给 Agent，让它读 [initProject.md](initProject.md) 即可自动完成模型与工具下载、路径修复、配置生成和启动验证。用户不需要手动敲命令。

初始化完成后，依赖会在仓库同级生成一个不参与 Git 的 `aiVoiceDep` 目录；它只用于本地语音合成，不会上传，也不需要时可以整个删除。

## 日常使用

1. 双击 `launcher\启动器.bat`，打开「音色工坊」。
2. 点击 **启动或重启朗读服务**，等状态显示“朗读服务：运行中”。
3. 点击 **打开 MAGI 阅读器**，导入书籍并点朗读。
4. 需要检查当前声音时，点击 **试听**。

听书时只开朗读服务，不要再开 WebUI 推理页，避免两个模型争抢显存。

## 训练与换音色

- **训练新音色**：点击“训练新音色”并选择干净人声音频，填写英文或拼音名称；程序会自动切片和识别文字。校对弹出的 `.list` 文件，保存并关闭记事本，再确认开始训练。训练完成后可直接设为当前音色。
- **切换音色**：点击“切换音色”，选择已有音色并确认。程序会同步模型权重、参考音频和提示文本；服务正在运行时会热切换，并重新打开 MAGI。
- **编辑配置**：仅高级维护使用。保存并关闭记事本后会自动应用配置，已打开的服务和 MAGI 会重启。

建议训练素材为 1～10 分钟单人、无背景音乐的干净人声。训练前关闭游戏、安卓模拟器和视频软件，给显卡留出足够显存。

## 仓库内容

```
gpt-sovits-magi-stack/
├── launcher/
│   ├── 启动器.bat           日常双击入口
│   └── 启动器.ps1           中文图形界面与后台任务
├── config/
│   ├── stack.yaml           路径、端口、当前音色的唯一事实源
│   └── stack.local.yaml.example  机器私有覆盖配置示例
├── scripts/
│   ├── apply-config.ps1     应用配置并同步 API 与 MAGI
│   ├── switch-voice.ps1     列出或切换已训练音色
│   ├── train_v2pro.py       v2Pro 无头训练驱动
│   ├── start-api.bat        启动朗读服务
│   └── test-tts.ps1         合成冒烟测试
├── initProject.md           新电脑自动初始化 SOP（交给 Agent 执行）
├── docs/                    方案、架构与使用文档
└── QA.md                    换音色、重训与数据量问答
```

大型依赖统一放在仓库外、由 `config\stack.yaml` 的 `dep_root` 指定，默认是仓库同级的 `aiVoiceDep`：

```
<仓库父目录>\aiVoiceDep\
├── GPT-SoVITS-v2pro-20250604\  整合包、权重与训练产物
├── magi\                       MAGI 便携版
├── input\                      训练素材
├── huggingface\                Hugging Face 缓存
├── modelscope\                 ModelScope 缓存
└── numba\                      numba JIT 缓存
```

## 配置说明

`config\stack.yaml` 保存可公开的公共默认（依赖根目录、路径、端口、模型版本），路径全部使用相对写法：`dep_root` 相对仓库，其余路径相对 `dep_root`，所以换电脑不会失效。

真实音色信息（实验名、参考音频、提示文本）只写在**不入库**的 `config\stack.local.yaml`，由启动器自动维护。不要把这些内容提交到 Git。

高级用户可在启动器中点击“编辑配置”，或运行 `scripts\apply-config.ps1`。配置会同步到：

- API 端：`GPT_SoVITS\configs\tts_infer.yaml` 的 `custom` 段。
- MAGI 端：`%APPDATA%\magi\library.json` 的 `settings.tts`。

`config\_env.bat`、`config\_env.ps1`、`config\_env.py` 均为自动生成文件，不要手动编辑。机器私有覆盖（例如依赖放在别的盘）写入不入库的 `config\stack.local.yaml`，只需覆盖 `dep_root` 或个别路径。

## 关键认知

- 阅读器连的是 **API（端口 9880）**，不是 WebUI（9871～9874）。
- 8 GB 显存使用 **v2Pro** 全量微调，参数保持默认、**DPO 关闭**。
- 参考音频决定本次合成的音色；提示文本必须与参考音频逐字一致。
- 所有入口都会把缓存指向 `aiVoiceDep`，包括 `NUMBA_CACHE_DIR`，无需再手动设置到系统缓存目录。

更详细的操作与排查见 [使用文档](docs/03-使用文档.md)；要不要重训、数据量怎么选见 [QA.md](QA.md)。

## 合规

克隆可识别真人声音需本人授权；公开发布基于 GPT-SoVITS 的作品需署名 GPT-SoVITS。详见 [使用文档 §六](docs/03-使用文档.md)。
