# NGSL Go

面向安卓平板的 NGSL 词汇学习应用。家庭自用，多学习者进度独立。

视觉设计采用暖白、橙色与墨蓝；横屏使用顶部导航、分区学习首页和词卡网格，竖屏使用底部导航。应用图标为叠放词卡、NGSL 字样和回忆勾选，Android 自适应图标与各密度桌面图标同步提供。

## 第一版功能

- 创建成人或儿童档案，随时切换。熟词筛选、每日任务、复习安排、生成内容和学习偏好按学习者分别保存。
- 完整 NGSL 1.2：2,809 个词条，官方词频、词形、中英文基础释义。
- 批量标记熟词并恢复；尚未开始的每日任务会立即补入未排除的词。
- 快速筛词：每批最多 100 词，只点不熟或不确定的词，浏览到本批末尾后再提交，其余词标为熟词。可显示中文释义、本批都不熟、撤销上一批；已提交的筛选进度按学习者保存，随时可返回学习。没有按词频范围直接跳过的功能。
- 每日新词与到期复习，任务固定保存。没想起来的词在本轮再次出现；成功回忆后安排下一次复习。
- 复用 FCE-Go 的 ChatGPT 授权与 Responses API 调用方式。连接由平板共用，使用独立授权和安全存储，不读取 FCE-Go 凭据。
- 每篇故事最多串联六个目标词，包含中英对照、常见搭配、例句、遮词回忆与表达任务；生成内容经程序检查后保存。
- 单词英美音标、英美 Kokoro 离线音频，共 5,618 段。动态例句和故事使用系统已安装的离线英语语音包，合成后缓存。
- 33 张随附原创例句与搭配词卡。其他词可在词卡中通过 ChatGPT 补充；每日故事也会补充相应词卡。补充内容属于当前学习者，首次补充需要联网。
- 学习数据在本机保存，原子写入并保留上一份有效快照。没有云同步，也不将学习者档案作为密码或隐私隔离系统。

## 构建

Flutter 3.47 或更高版本，Dart 版本应满足 `app/pubspec.yaml`，Android SDK 36，Java 17 或兼容的 Android 构建 JDK。Android 工具链为 Gradle 9.3.1、AGP 9.1.1、Kotlin 2.4.0；依赖锁定在 `app/pubspec.lock`。

Android 使用 AGP 内置 Kotlin 和 `compilerOptions`，不再应用旧的 `kotlin-android` 插件。Flutter 3.47 仍需要 `android.newDsl=false` 兼容其 DSL/Variant API；升级工具链时不要将此标记与内置 Kotlin 开关一并移除。

```bash
bash tooling/verify_and_build.sh
```

APK 输出：`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。

应用标识：`com.jonlimx.ngsl_go`，与 FCE-Go 分开安装、分开存储。目前是家庭自用调试签名，后续更新应保留同一签名。不要通过卸载、清除数据解决安装问题。

## 数据与音频的可复现构建

原始词表在 `data/source`，字段来源与校验摘要在 `data/provenance.json`。原创教学内容在 `data/curated.json`，音频清单在 `data/audio_manifest.json`。

```bash
python3 tooling/import_ngsl.py
python tooling/build_audio.py --model /path/to/kokoro-multi-lang-v1_0
```

音频工具使用与 FCE-Go 相同的 Kokoro / Misaki / ONNX 构建环境、ffmpeg，以及本地 Kokoro 配置和音色。App 仅分发 MP3，不分发模型权重。

## 检查与当前限制

详见 `docs/validation.md`。受限环境可运行 `cd app && dart run tooling/check_core.dart`；它不依赖 Flutter 测试传输使用的本机端口。

完整 Flutter 测试位于 `app/test`。`app/tooling/run_socket_free_tests.dart` 是当前锁定测试依赖的无端口适配器，执行真实的 test_api / Flutter 测试；`render_preview.dart` 用于平板布局的离屏检查。

旧工具链 APK 已由用户手动构建。工具链升级后，静态分析和标准 Flutter 测试 19 项通过；自动执行环境仍阻止 Gradle 守护进程监听端口，因此升级后的 APK 构建尚未验证。现有 APK 不代表本次工具链升级构建成功。新应用的 ChatGPT 授权、音频与实际 KPad 兼容性仍需安装后验证，不能以复用旧项目代码代替新应用的实机验证。

## 许可

NGSL 数据及其改编：CC BY-SA 4.0，作者 Charles Browne、Brent Culligan、Joseph Phillips。

Kokoro / Misaki：Apache 2.0。美音参考音标采用 open-dict-data/ipa-dict 的 en_US 数据（MIT，基于 cmudict-ipa / syllabify）；英音标注由 Misaki 生成。多读音词选择与本次目标词性相符的读音。音标和自动生成内容仍可能有误，不应视为权威词典。

完整来源和许可保留在 `app/assets/content`。原作者不为本应用背书。
