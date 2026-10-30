# NGSL Go

面向安卓平板的 NGSL 词汇学习应用。家庭自用，多学习者进度独立。

视觉设计采用暖白、橙色与墨蓝；横屏使用顶部导航、分区学习首页和词卡网格，竖屏使用底部导航。应用图标为叠放词卡、NGSL 字样和回忆勾选，Android 自适应图标与各密度桌面图标同步提供。

## 第一版功能

- 创建成人或儿童档案，随时切换。熟词筛选、每日任务、复习安排、生成内容和学习偏好按学习者分别保存。
- 完整 NGSL 1.2：2,809 个词条，官方词频、词形、中英文基础释义。
- 批量标记熟词并恢复；尚未开始的每日任务会立即补入未排除的词。设置中可将筛词结果复制给另一个学习者，仅填入对方尚未筛选、尚未学习的词，原账号和接收者已有记录保留。
- 快速筛词：每批最多 100 词，只点不熟或不确定的词，浏览到本批末尾后再提交，其余词标为熟词。可显示中文释义、本批都不熟、撤销上一批；已提交的筛选进度按学习者保存，随时可返回学习。没有按词频范围直接跳过的功能。
- 成人和儿童共用记忆机制：新词先理解，再主动回忆；认读、听懂、表达、拼写分别记录，按实际表现调整间隔。提示后想起、忘记与独立想起分别记录，拼写自动核对，其他方向由学习者对照答案自评。
- 每组最多五词、每词每组最多三次回忆。新学或需要重学的词至少间隔一分钟，再配合其他词练习；多次失败后延长休息，重启或跨午夜仍保留等待时间。初次或当天重复成功不会直接获得长间隔。
- 每日任务保留已学记录；每日新词可设置为 0～60 个，调大时立即按所选额度向今日计划追加未学新词（即使原计划已排满），调小从后续计划生效。设置显示剩余新词和预计学完首轮的日期；自动新计划优先安排到期复习，总量最多八十词，复习较多时减少新词，其余到期词仍保留待复习状态。完成后可再练今日单词，单独记录同日练习，成功不会拉长既有间隔，忘记或依赖提示会恢复短间隔。首页显示近七天有记录的跨日独立回忆次数。已有学习进度和计划保持兼容，详见 `docs/memory.md`。
- 复用 FCE-Go 的 ChatGPT 授权与 Responses API 调用方式。连接由平板共用，使用独立授权和安全存储，不读取 FCE-Go 凭据。
- 每篇故事最多串联六个目标词，包含中英对照、常见搭配、例句、遮词回忆与表达任务；生成内容经程序检查后保存。遮词练习记录实际自评结果，阅读故事与词卡复习分别记录。
- 单词、搭配、例句和故事统一使用应用内 Kokoro 1.0（sherpa-onnx 1.13.8），英音 Emma、美音 Heart。模型随安装包提供，无需系统英语语音包；首次解包校验后可离线合成并缓存。后台线程生成，离开页面、停止或切换朗读会丢弃过期请求。模型压缩包约 324 MiB，解包需要约 366 MiB 额外空间；缓存最多 150 MiB。固定词音频继续直接播放，多读音词另带与词性、义项匹配的音频。
- 全部 2,809 词预置中英文基础释义、一条 B1–B2 语境例句及完整中文译文、至少两条双语常用搭配。例句和搭配由大模型一次性原创生成，以条件、原因、让步、关系从句等提供适度复杂的语境，源码在 `data/offline_batches/cards_*.json`；不采用 Tatoeba 例句。另有 857 张词形卡、337 张同根词卡、反义对照、用法结构及 32 道词形练习，统称“词形与用法”。词形、词族和反义词按实际语言关系提供，不假造每个词都具有的变化。学习时无需逐词请求 GPT，故事生成继续提供并缓存其语境内容。
- 全部词条另有按词性整理的 5,849 个常见义项，以及共 458 条独立解释的常用短语，每个义项附中英文释义、双语例句和搭配。词卡逐项展开，搜索支持新增中文释义与短语。`present` 区分名词、形容词、动词及 `at present`；`lie` 的 lied 与 lay/lain 按义项说明。词库是学习型常用义整理，不是穷尽全部历史和专业含义的词典。源码在 `data/common_senses/senses_*.json`，导入前验证全量覆盖、词性、目标词、译文及格式。
- 词卡可标记“已熟悉”，保留历史并转为至少十四天后的低频抽查；答错或依赖提示后回到常规复习，也可手动恢复。原有快速筛词排除标记不因升级而改变。
- 学习数据在本机保存，原子写入并保留上一份有效快照。没有云同步，也不将学习者档案作为密码或隐私隔离系统。

## 墨水屏与完全离线模式

同一个 APK 支持普通平板和墨水屏。首次启动读取 Android 型号与设备声明的墨水屏能力，Ocean 5 Pro 型号名会自动启用墨水屏模式。设置中的“设备显示模式”可选择自动、普通、墨水屏；手动选择保存在独立的 `device_settings.json`，只影响当前设备，不随学习者切换或筛词结果复制而改变。型号采用厂商编码且无法匹配时，可手动选择；Ocean 5 Pro 实际固件返回值仍需实机核对。

墨水屏模式隐藏故事导航、生成入口、故事主题、ChatGPT 连接及模型设置，不读取 GPT 授权、不启动登录。单词、释义、例句、搭配、筛词、间隔复习和随包 Kokoro 发音均可离线使用。HTTP 请求统一经过离线策略检查，包括刷新令牌和查询模型；切换到墨水屏模式会关闭正在进行的请求、取消登录与故事生成，并拒绝过期响应。已保存的学习数据、故事与授权不删除，切回普通模式后可继续使用。

墨水屏界面使用灰度、高对比按钮与边框；页面、对话框和义项展开关闭过渡动画，遵循系统辅助功能设置。七英寸词库将筛选和批量工具收起，并支持整页滚动，避免工具展开后挤压词卡。

## 构建

Flutter 3.47 或更高版本，Dart 版本应满足 `app/pubspec.yaml`，Android SDK 36，Java 17 或兼容的 Android 构建 JDK。Android 工具链为 Gradle 9.3.1、AGP 9.1.1、Kotlin 2.4.0；依赖锁定在 `app/pubspec.lock`。

Android 使用 AGP 内置 Kotlin 和 `compilerOptions`，不再应用旧的 `kotlin-android` 插件。Flutter 3.47 仍需要 `android.newDsl=false` 兼容其 DSL/Variant API；升级工具链时不要将此标记与内置 Kotlin 开关一并移除。

```bash
bash tooling/verify_and_build.sh
```

APK 输出：`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。

应用标识：`com.jonlimx.ngsl_go`，与 FCE-Go 分开安装、分开存储。目前是家庭自用调试签名，后续更新应保留同一签名。不要通过卸载、清除数据解决安装问题。

## 连接 KPad 后构建并安装

接上 USB 线，开启平板的“开发者选项 → USB 调试”，并在平板弹窗中允许此电脑调试。在本机终端运行：

```bash
bash tooling/install_kpad.sh
```

脚本可从任意目录通过完整路径调用。默认选择唯一连接的实体设备，检查 Android 版本和 ARM64 架构，然后运行上述检查及构建流程。构建成功后核对 APK 包名，使用 `adb -s 目标序列号 install -r` 保留数据覆盖安装，最后打开 NGSL Go。

如果连接了多台实体设备，脚本会停止并列出设备。只连接 KPad，或显式指定：

```bash
bash tooling/install_kpad.sh --serial 设备序列号
```

检查或构建失败不会安装之前遗留的 APK；安装失败不会尝试卸载、清除数据或强制降级。签名不兼容时需要使用原签名重新构建。脚本依赖本机 Python 3、Flutter/Dart 与 Android SDK；`adb` 可从 PATH、SDK 环境变量、项目的 `android/local.properties` 或 macOS 默认 SDK 目录定位，APK 包名通过 SDK Build-Tools 的 `aapt` 核对。

## 数据与音频的可复现构建

原始词表在 `data/source`，字段来源与校验摘要在 `data/provenance.json`。原创教学内容在 `data/curated.json`、`data/fce_enrichment.json` 、`data/offline_batches/cards_*.json` 和 `data/common_senses/senses_*.json`，音频清单在 `data/audio_manifest.json`。

```bash
python3 tooling/import_ngsl.py
python tooling/build_audio.py --model /path/to/kokoro-multi-lang-v1_0
python tooling/build_sense_audio.py --model /path/to/kokoro-multi-lang-v1_0
python3 tooling/import_ngsl.py
python3 tooling/prepare_kokoro.py
```

音频工具使用与 FCE-Go 相同的 Kokoro / Misaki / ONNX 构建环境、ffmpeg，以及本地 Kokoro 配置和音色。固定音频预先生成 MP3；动态语音使用随包提供的模型。`prepare_kokoro.py` 验证每个模型文件的 SHA-256，优先使用已验证的缓存，否则下载固定官方版本；安装脚本自动完成准备。模型 ZIP 作为可重建大文件不进入 Git，文件清单及校验值保存在 `data/kokoro_model.json`。多读音词例句通过已核对的目标词音素覆盖，避免自动标注把 lead（金属）或 minute（细小的）读成其他义项。

## 检查与当前限制

详见 `docs/validation.md`。受限环境可运行 `cd app && dart run tooling/check_core.dart`；它不依赖 Flutter 测试传输使用的本机端口。

完整 Flutter 测试位于 `app/test`。`app/tooling/run_socket_free_tests.dart` 是当前锁定测试依赖的无端口适配器，执行真实的 test_api / Flutter 测试；`render_preview.dart` 用于平板布局的离屏检查。

全量常用义项与应用内 Kokoro 更新后，静态分析无问题，无端口适配器执行 86 项真实 Flutter / test_api 测试全部通过，独立核心检查 15 项通过，Flutter debug bundle 构建成功。当前自动执行环境阻止标准测试传输和 Gradle 创建本机通信端口，因此标准 `flutter test` 未能加载，ARM64 APK 构建尚未完成。现有 APK 不包含此次更新；没有安装或操作设备数据。ChatGPT 授权、音频与实际 KPad 兼容性仍需构建安装后验证。

## 许可

NGSL 数据及其改编：CC BY-SA 4.0，作者 Charles Browne、Brent Culligan、Joseph Phillips。

Kokoro / Misaki：Apache 2.0。美音参考音标采用 open-dict-data/ipa-dict 的 en_US 数据（MIT，基于 cmudict-ipa / syllabify）；英音标注由 Misaki 生成。多读音词选择与本次目标词性相符的读音。音标和自动生成内容仍可能有误，不应视为权威词典。

FCE 扩展是依据 B2 First 词形与搭配技能设计的原创材料，不是官方考题，也不宣称覆盖所有 NGSL 词条的全部词族。

完整来源和许可保留在 `app/assets/content`。原作者不为本应用背书。
