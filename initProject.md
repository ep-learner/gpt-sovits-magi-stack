# initProject.md — 新电脑一键初始化 SOP（给 Agent 执行）

> 目标：用户 `git clone` 本仓库后，Agent 读完本文件即可自动下载依赖、修好路径、初始化配置，让新电脑能双击启动器听书。
> 读者是 Agent；用户是完全不懂技术的小白。**默认自主执行，不逐项征求同意**，只在遇到硬阻塞时停下说明。

---

## 一、执行原则（Agent 必读）

1. **先做后说，不反复确认。** 开头用 3～5 句话一次讲清「要下载什么、多大、为什么、放哪里」，然后直接开始。
2. **只报告结果和阻塞。** 不要每一步都问“是否继续”。用户反对时会主动叫停。
3. **不碰用户数据。** 只写入依赖目录和本仓库的配置；不删除用户文件，不提交 Git，不修改系统 PATH。
4. **不改训练成果。** 已存在的权重、切片、`.list` 一律保留；同名文件不覆盖。
5. **失败可恢复。** 下载支持断点续传；解压失败先检查磁盘空间和压缩包大小，再重试。
6. **不把机器路径和音色信息写进代码。** 真实音色名、参考音频、提示文本只写进 `config/stack.local.yaml`（不入库）；公共默认在 `config/stack.yaml`，其中 `current_voice` 必须保持为空。
7. **体积与网络提前说明。** 下载约 8～16 GB，解压后约 16～20 GB；只下载一次，后续可离线使用。
8. **绝不提交音色产物。** 权重、切片、`.list`、参考音频、`library.json` 和 `config/stack.local.yaml` 都不能进入 Git；提交前检查 `git status`。

### 只有这些情况才暂停询问

- 没有 NVIDIA 显卡或驱动异常（`nvidia-smi` 不可用）。
- 目标磁盘空闲不足 35 GB，且没有其他可用磁盘。
- 下载连续失败 3 次，或官方下载源 404 且找不到替代源。
- 必须管理员权限且当前无法提权。
- 用户明确表示不想下载。

---

## 二、目标布局

```
<仓库父目录>\
├── gpt-sovits-magi-stack\         ← 本仓库（git 跟踪）
└── aiVoiceDep\                    ← 依赖目录（不跟踪，可随时删除重下）
    ├── GPT-SoVITS-v2pro-20250604\
    ├── magi\MAGI-portable-2.3.0.exe
    ├── input\
    ├── huggingface\
    ├── modelscope\
    └── numba\
```

`config/stack.yaml` 默认 `dep_root: ..\aiVoiceDep`，与仓库同级。若用户希望放到别的盘，只需写 `config/stack.local.yaml` 覆盖 `dep_root`，不要改公共配置。

依赖目录不入 git，也不会上传任何地方；用户不需要时可整个删除，重新运行本流程即可恢复。

---

## 三、步骤

以下命令均在 PowerShell 5.1 中执行。先设置变量：

```powershell
$repo = (Resolve-Path "<本仓库路径>").Path      # 例如 D:\apps\gpt-sovits-magi-stack
$dep  = Join-Path (Split-Path $repo -Parent) 'aiVoiceDep'   # 与 stack.yaml 默认一致（仓库同级）
New-Item -ItemType Directory -Force -Path $dep | Out-Null
```

### 步骤 0：预检

```powershell
# 显卡
nvidia-smi
# 磁盘（依赖盘至少留 35 GB）
Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
# 网络（任一通即可）
curl.exe -I -L --max-time 20 https://hf-mirror.com
curl.exe -I -L --max-time 20 https://github.com
```

判定：

- `nvidia-smi` 失败 → 停止，告知用户需要 NVIDIA 显卡与最新驱动。
- 目标盘不足 35 GB → 选空闲最大的盘作为 `$dep`，并写入 `config/stack.local.yaml` 的 `dep_root`。
- 两个下载源都不通 → 停止，说明网络限制。

### 步骤 1：下载 GPT-SoVITS v2Pro 整合包

先检查是否已经装好，已存在就跳过下载和解压：

```powershell
if (Test-Path -LiteralPath "$dep\GPT-SoVITS-v2pro-20250604\runtime\python.exe") {
    Write-Host 'GPT-SoVITS 已存在，跳过下载。'
}
```

来源（任选其一，优先镜像）：

```text
https://hf-mirror.com/lj1995/GPT-SoVITS-windows-package/resolve/main/GPT-SoVITS-v2pro-20250604.7z
https://huggingface.co/lj1995/GPT-SoVITS-windows-package/resolve/main/GPT-SoVITS-v2pro-20250604.7z
```

若上述固定文件名 404，用模型文件列表找含 `v2pro` 的最新 `.7z`：

```powershell
curl.exe -L --max-time 30 https://hf-mirror.com/api/models/lj1995/GPT-SoVITS-windows-package
```

下载命令（断点续传、失败重试）：

```powershell
$archive = Join-Path $dep 'GPT-SoVITS-v2pro-20250604.7z'
$url = 'https://hf-mirror.com/lj1995/GPT-SoVITS-windows-package/resolve/main/GPT-SoVITS-v2pro-20250604.7z'
for ($i = 1; $i -le 3; $i++) {
    curl.exe -L -C - --retry 3 --retry-delay 5 -o "$archive" "$url"
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 5
}
```

下载后检查：扩展名为 `.7z`，大小应在 8 GB 左右；若只有几 MB，说明拿到的是错误页面，删除重下。

```powershell
if (-not (Test-Path -LiteralPath $archive)) { throw '整合包下载失败，请检查网络后重试' }
$sizeGB = (Get-Item -LiteralPath $archive).Length / 1GB
if ($sizeGB -lt 1) { throw "下载文件异常（$([math]::Round($sizeGB,3)) GB），请删除后重下" }
Write-Host ("整合包大小 {0:N2} GB" -f $sizeGB)
```

### 步骤 2：解压

先找 7-Zip：

```powershell
$seven = (Get-Command 7z.exe, 7za.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $seven) {
    $seven = @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $seven) {
    winget install --id 7zip.7zip -e --accept-source-agreements --accept-package-agreements
    $seven = 'C:\Program Files\7-Zip\7z.exe'
}
if (-not (Test-Path -LiteralPath $seven)) { throw '未找到 7-Zip，请安装后重试' }
```

解压到依赖目录：

```powershell
& $seven x "$archive" "-o$dep" -y
```

解压后应存在 `$dep\GPT-SoVITS-v2pro-20250604\runtime\python.exe` 和 `api_v2.py`。若目录名不同（例如带 `-nvidia50`），把它改为 `GPT-SoVITS-v2pro-20250604`，或在 `stack.local.yaml` 覆盖 `paths.gpt_sovits_root`。

解压成功后可以删除 `.7z` 释放空间（先确认解压完整）。

### 步骤 3：修复 users.pth 的写死路径

整合包内置 Python 的 `users.pth` 记录了打包者的旧路径，不修会报 `ModuleNotFoundError: No module named 'tools'`。

```powershell
$root = Join-Path $dep 'GPT-SoVITS-v2pro-20250604'
$pth = Join-Path $root 'runtime\Lib\site-packages\users.pth'
$lines = @(
    $root,
    "$root\GPT_SoVITS\BigVGAN",
    "$root\tools",
    "$root\tools\asr",
    "$root\GPT_SoVITS",
    "$root\tools\uvr5"
)
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($pth, ($lines -join "`r`n") + "`r`n", $enc)
```

验证：

```powershell
Push-Location $root
& "$root\runtime\python.exe" -c "import tools, GPT_SoVITS; print('paths ok')"
Pop-Location
```

### 步骤 4：下载 MAGI 阅读器

```powershell
$magiDir = Join-Path $dep 'magi'
New-Item -ItemType Directory -Force -Path $magiDir | Out-Null
$existingMagi = Get-ChildItem -LiteralPath $magiDir -Filter 'MAGI-portable-*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingMagi) {
    Write-Host "MAGI 已存在，跳过下载：$($existingMagi.Name)"
} else {
    $release = Invoke-RestMethod 'https://api.github.com/repos/noemoe5/MAGI/releases/latest' -Headers @{ 'User-Agent' = 'initProject' }
    $asset = $release.assets | Where-Object { $_.name -like 'MAGI-portable-*.exe' } | Select-Object -First 1
    if (-not $asset) { throw 'MAGI release 中找不到 portable exe，请检查 https://github.com/noemoe5/MAGI/releases' }
    curl.exe -L -C - --retry 3 -o (Join-Path $magiDir $asset.name) $asset.browser_download_url
}
```

若 GitHub API 不通，提示用户开启代理后重试；不要随意从第三方站下载 exe。

如果下载到的版本号不是 `2.3.0`，把实际文件名写进 `stack.local.yaml`：

```yaml
paths:
  magi_exe: magi\MAGI-portable-<实际版本>.exe
```

### 步骤 5：迁移已有音色（可选，但推荐）

训练权重属于个人数据，**不在 git 里**。用户如果从旧电脑迁移，把以下内容复制进新整合包：

```text
SoVITS_weights_v2Pro\*
GPT_weights_v2Pro\*
output\slicer_opt\<音色名>\*
output\asr_opt\*.list
```

复制后无需改路径：`.list` 里的旧绝对路径用仓库自带工具批量修正：

```powershell
& "$repo\scripts\relocate.ps1" -OldRoot "<旧整合包根目录>"
& "$repo\scripts\apply-config.ps1"
```

如果没有旧音色，跳过本步骤。程序仍可初始化成功；用户之后在启动器点「训练新音色」即可。

### 步骤 6：应用配置

```powershell
& "$repo\scripts\apply-config.ps1"
```

预期：

- 生成 `config\_env.bat`、`config\_env.ps1`、`config\_env.py`。
- 若已有音色权重与参考音频，会同步 `tts_infer.yaml` 和 MAGI 的 `library.json`。
- 若还没有任何音色，会提示“跳过 tts_infer.yaml 同步”，这是新电脑的正常状态，不算失败。

### 步骤 7：启动并冒烟

```powershell
Start-Process -FilePath (Join-Path $repo 'scripts\start-api.bat')
Start-Sleep -Seconds 8
try { Invoke-WebRequest -Uri 'http://127.0.0.1:9880' -UseBasicParsing -TimeoutSec 3 | Out-Null } catch { }
```

只要能拿到 HTTP 响应（含 404/405）就说明服务已监听。再跑合成：

```powershell
& "$repo\scripts\test-tts.ps1"
```

- 已有音色：应生成 `scripts\test-output.wav` 且大于 0 字节。
- 尚无音色：这一步会失败，属预期；改为让用户先在启动器训练首个音色。

### 步骤 8：交给用户

打开启动器：

```powershell
Start-Process (Join-Path $repo 'launcher\启动器.bat')
```

告诉用户：

> 初始化已完成。以后只需双击 `launcher\启动器.bat`：
> 1. 点「启动或重启朗读服务」；
> 2. 点「打开 MAGI 阅读器」，导入书即可听；
> 3. 想换声音，点「切换音色」；想造新声音，点「训练新音色」。
>
> 模型和工具都放在项目旁边的 `aiVoiceDep` 目录，只下载这一次，不会上传，也不会影响系统其它软件；不需要时可整个删除。

---

## 四、给用户的一次性说明模板（下载前说，不要逐项问）

> 这个项目需要本地跑语音模型，所以第一次要下载约 8～16 GB 的模型和阅读器，解压后约 16～20 GB，全部放在你项目旁边的 `aiVoiceDep` 文件夹里。
> 这些文件只用于本地合成语音，不会上传，也不会改动系统设置；下载完成后可以离线使用，不需要时整个文件夹删掉即可恢复。
> 我现在开始自动下载和配置，中途不需要你操作；如果网络或磁盘不够，我会停下来告诉你。

---

## 五、验收清单（Agent 自检）

- [ ] `$dep\GPT-SoVITS-v2pro-20250604\runtime\python.exe` 存在。
- [ ] `users.pth` 六行均指向新根目录，`import tools` 成功。
- [ ] `$dep\magi\MAGI-portable-*.exe` 存在且大于 100 MB。
- [ ] `apply-config.ps1` 退出码为 0，`config\_env.*` 三个文件已生成。
- [ ] `http://127.0.0.1:9880` 有 HTTP 响应。
- [ ] 有音色时 `test-output.wav` > 0 字节；无音色时已明确告知用户先训练。
- [ ] `git status` 中没有依赖目录、权重、音频、`.list`、`library.json` 或 `stack.local.yaml`。
- [ ] `config/stack.yaml` 的 `current_voice` 仍为空，真实音色只存在于未跟踪的 `config/stack.local.yaml`。
- [ ] 启动器能打开，状态区显示服务和当前音色。

---

## 六、常见问题

| 现象 | 处理 |
|---|---|
| 解压报“文件损坏” | 删除压缩包重下；确认大小接近 8 GB，不要用浏览器下载到一半的副本 |
| `ModuleNotFoundError: tools` | 重做步骤 3，确认 `users.pth` 六行都是当前根目录 |
| `Cannot find empty port` | 在 `stack.local.yaml` 把 `server.port` 改为 9881 等，再运行 `apply-config` |
| `CUDA out of memory` | 关闭游戏、模拟器、视频软件后重试；不要改训练参数 |
| 启动器提示“当前音色读取失败” | 检查 `config\stack.yaml` 的 `current_voice` 与 `dep_root`；重新运行 `apply-config` |
| 没有声音 / 试听失败 | 尚未训练音色，或参考音频路径不存在；先训练或迁移权重 |
| 下载很慢 | 使用 `hf-mirror.com`；确认已开启断点续传，不要中途删除临时文件 |
| GitHub 打不开 | 开启代理后重试 MAGI 下载；不要从不明来源下载 exe |
