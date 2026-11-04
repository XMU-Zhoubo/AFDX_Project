# AFDX 代码与仿真环境（C45 冻结版）

本目录用于“代码及仿真环境”提交。设计源码采用 C45 冻结版本，83 项 DUT 编译顺序及文件内容保持不变，顶层为 `AFDX_top`。不包含历史运行日志、波形、检查点。

## 目录与入口

|目录/文件|用途|
|---|---|
|`rtl/`、`ip/`、`compile.f`|完整 DUT、双 MAC 依赖及唯一有效的 83 项编译清单|
|`tb/fragment/`|分片单元、完整应用系统、与网表相同的代表场景|
|`tb/system/`、`tb/load/`、`tb/common/`|同 C45 源码配套的管理服务、外部存储及 watchdog 测试平台|
|`vectors/`|输入向量、文件加载样本及独立参考模型使用的输入规格；不是历史运行结果|
|`models/`、`tools/legacy/`|独立协议模型与逐字节、校验、唯一交付、BAG 和资源回收检查器|
|`tools/run_simulation.py`|统一命令行入口，按所选用例创建新库、新输出|
|`tools/c45_runtime.py`|原 C45 编译、仿真及 RTL/网表比较函数|
|`tools/run_services.py`|与 C45 同源码的管理服务短 RTL 入口|
|`project/`|eLinx 工程、综合前端配置和 100/125 MHz 时钟约束|
|`netlist/functional/`|C45 完整官方功能网表，作为后仿输入保留|
|`environment.example.json`、`requirements.txt`|外部工具路径示例与 Python 依赖|
|`simulation-inputs.json`、`external-models.json`|运行前检查源码、输入及官方模型是否匹配的配置|

请使用 `compile.f`，不要把各目录的同名文件扁平化。当前顶层文件是 `rtl/fragment/c42s_stats/AFDX_top.v`。`tb/fragment/c42s_system_body.vh`为生成源备份，不作为额外编译单元；`c42s_system.v`已经包含对应内容。

## 环境配置

- Windows、Python 3.12，管理服务独立 BER 检查需要 `pyasn1==0.6.4`。
- ModelSim SE-64 2020.4。
- 完整官方功能网表需要与 C45 匹配的 eLinx 3.0.7 官方 `elinx_lib`。`external-models.json`记录匹配所需的模型文件。
- 重新综合时使用已有 eLinx 安装打开 `project/c42s_application_stats.epr`；仅 RTL 用例不调用 eLinx，也不运行综合或布线。
- 为新编译库和输出预留至少 10 GiB 空间。工具耗时取决于机器和负载。

请先把本目录复制到全英文运行路径，例如 `D:/AFDX_C45_Run`，保留“代码提交”原件。本机 ModelSim 2020.4 实际测试无法可靠读取中文路径，运行器会在启动前拒绝非 ASCII 路径；不要直接在“代码提交”目录中运行。全英文路径可含空格。把 `environment.example.json`复制为 `environment.local.json`，修改 Python、ModelSim、eLinx 和官方库路径。示例中的 `D:/...`只是配置示例，不要求存在原工程目录。

以下 PowerShell 命令均在自己的包副本根目录执行，不调用 `.ps1`脚本，也不修改执行策略：

```powershell
$codeRoot = (Get-Location).Path
Copy-Item -LiteralPath (Join-Path $codeRoot 'environment.example.json') -Destination (Join-Path $codeRoot 'environment.local.json')
```

编辑 `environment.local.json`后再运行；若配置文件已存在，跳过上面的复制命令。

```powershell
$simEnv = Join-Path $codeRoot 'environment.local.json'
$simPython = (Get-Content -LiteralPath $simEnv -Raw -Encoding utf8 | ConvertFrom-Json).python
& $simPython -m pip install -r (Join-Path $codeRoot 'requirements.txt')
```

依赖已安装时不必再次执行 pip。程序不会自动安装工具或包。

## 仿真操作

每次使用新的输出名；禁止覆盖旧输出或拷入旧 work/checkpoint。不要使用 Python `-O`，独立检查器保留断言。

**快速 RTL：单元、完整分片系统、网表对应代表场景。**

```powershell
$quickOut = Join-Path $codeRoot ('runs/quick_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
& $simPython -I -B -X utf8 (Join-Path $codeRoot 'tools/run_simulation.py') --environment $simEnv --output $quickOut --cases quick
```

该入口使用新编译库，执行正常收发、1–4096 B消息、分片与重组、错误拒收、A/B冗余及资源回收检查；完整系统结果还会由独立模型重新核对字节、IPv4/UDP/FCS、BAG、唯一交付与资源账目。历史运行量级为分钟。

**管理服务：SNMP、RTC、双向文件加载。**

```powershell
$serviceOut = Join-Path $codeRoot ('runs/services_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
& $simPython -I -B -X utf8 (Join-Path $codeRoot 'tools/run_simulation.py') --environment $simEnv --output $serviceOut --cases services
```

该测试平台来自同 C45 83 项源码配套的 C46 短 RTL 环境。验证真实 GET/Trap、实际 RTC 校正、不同内容的上传和下载、存储请求/完成及最终解锁。服务测试平台中的协议期限配置与正式默认参数存在原有的有限场景设置，DUT、BAG 和时钟频率未改变。生成的 `management/services/key-interfaces.vcd`可用于波形查看；它由本次运行生成，包内不预置历史波形。

**完整官方功能网表：先完成 quick，再使用相同输出目录。**

```powershell
& $simPython -I -B -X utf8 (Join-Path $codeRoot 'tools/run_simulation.py') --environment $simEnv --output $quickOut --cases eq
```

`eq`冷启动新库，编译完整官方网表和原代表测试平台，检查独立输出并与本次 `rtl-representative`比较。它需要匹配的官方库和较长运行时间；C45 原运行耗时约 2 小时 41 分，仅作成本参考。本入口不自动重试，不导入历史检查点，不执行综合/布线。

如需只核对路径、输入和官方库，不推进 HDL：

```powershell
$checkOut = Join-Path $codeRoot ('runs/preflight_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
& $simPython -I -B -X utf8 (Join-Path $codeRoot 'tools/run_simulation.py') --environment $simEnv --output $checkOut --cases preflight
```

`--cases all`会顺序执行 quick、services、eq，包含耗时较长的网表仿真，按需选择。

## 结果读取与工程范围

终端 `SUBMISSION_SIMULATION_PASS`只针对所选用例；退出码非零、未完成、许可错误或控制器中断均不算通过。新结果写入指定 `runs/...`，quick 每项保留实际原生退出、done/failures/checks及独立检查；services 查看 `management/batch-result.json`；eq 查看 `RTL-EQ-comparison.json`和 `eq-suite-result.json`。`preflight`通过仅表示依赖检查通过。

提交副本的包装入口去掉了原候选强制执行的历史指标复算、保护清单及历史证据依赖；DUT、测试刺激和独立业务检查保持。C45 原生仿真函数保留，主机启动参数补充了显式 `do {path}`引用；管理服务包装也补充了路径含空格时的 Tcl 参数引用。

官方网表为布局后、布线前功能网表。重新综合所需源码、工程和时钟约束已保留。QSF 中 `EP1S80F1508C6`为原厂前端沿用别名，实际 eLinx 工程器件为 `EQ6HL130 / CSG484_H`，不自行替换。
