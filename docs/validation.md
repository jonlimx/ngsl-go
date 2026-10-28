# 验证记录 · 2026-10-27

## 独立视觉设计与新图标

- 从绿色侧栏布局改为暖白、橙色、墨蓝体系。横屏顶部导航，首页拆分今日练习、今日单词、故事入口和进度；竖屏保留底部导航。词库改为可勾选的词卡网格，原有筛选、快速筛词、词卡、发音及故事入口保留。
- 最终图标采用叠放词卡、NGSL 字样及回忆勾选；没有喇叭。替换 App 内标识、Android 五种密度桌面图标和自适应图标；自适应图标保留裁切安全边距，启动背景同步到暖白。
- `flutter analyze --no-pub` 无问题；无端口适配器执行 26 项真实 Flutter / test_api 测试全部通过，增加横竖屏导航、网格词卡打开、故事入口检查，原有筛词及学习记录测试全部保留。
- 真实词库离屏渲染：首页、词库、故事、学习者弹窗及竖屏首页和词库，共六个画面，无布局错误。修复竖屏品牌副标题 1 像素溢出。
- `flutter build bundle --debug --no-pub` 成功，包含新图标素材的 Flutter 应用 bundle 已编译；Android `aapt2 compile` 资源编译成功。这两项不代替完整 APK 构建。
- 标准 `flutter test --no-pub` 仍因测试传输无法绑定 `127.0.0.1` 而未加载；ARM64 release APK 仍在 Gradle `FileLockContentionHandler` 创建本机 socket 时被当前会话拒绝。未生成或安装新 APK，未触碰设备数据；构建后恢复 `android/local.properties` 的原 Flutter SDK 路径。

## 快速筛词

- 首页及词库新增快速筛词入口，每批最多 100 词，只选择不熟或不确定的词。提交前须浏览到本批末尾；没有按词频范围跳过的操作。
- 可切换中文释义、整批保留生词、撤销上一批。已提交批次的熟词与生词筛选记录按学习者保存，重新打开不重复筛选；未提交的选择不会改变学习数据。
- 批次原子保存；已熟练和学习中的词不覆盖。尚未开始的每日计划立即补词；已开始的计划及复习进度保持稳定。撤销不会覆盖此后产生的复习或手动编辑。
- `flutter analyze --no-pub`：无问题。新增 4 项数据测试、2 项横竖屏界面测试；使用现有无端口适配器执行全部 Flutter / test_api 测试，25 项通过、0 失败，包含保存、撤销、重启续接、学习者隔离及最后不足 100 词的批次。
- 真实 NGSL 词库 1280×800 离屏渲染，检查单词模式与中文释义模式，无布局错误或溢出。
- 本次标准 `flutter test --no-pub` 在加载测试时仍因 `127.0.0.1` socket 绑定被拒而未执行，不能将无端口结果当作标准 CLI 测试通过。
- ARM64 release APK 构建仍在 Gradle `FileLockContentionHandler` 初始化时被本机 socket 权限拒绝，未进入应用编译。本次没有生成或安装新 APK，也未操作设备学习数据；构建用临时 SDK 路径已从 `android/local.properties` 恢复。

## Android 工具链升级（用户手动构建之后）

- Gradle 8.14 → 9.3.1，AGP 8.11.1 → 9.1.1，Kotlin 2.2.20 → 2.4.0。Gradle Wrapper JAR 同步更新到 9.3.1，SHA-256 与 Gradle 官方发布校验表一致，并配置发行包 SHA-256 校验。
- 按 Flutter 官方指南启用 AGP 内置 Kotlin，移除应用模块的 `kotlin-android` 插件，将 `kotlinOptions` 迁移至 `kotlin.compilerOptions`，保留 Java/Kotlin JVM 17 目标。声明最低 Flutter 3.47，保留 Flutter 3.47 所需的 `android.newDsl=false`。
- `flutter pub get --offline` 成功；依赖版本保持不变，锁文件的 Flutter 最低版本更新至 3.47。
- `flutter analyze --no-pub`：无问题；标准 `flutter test --no-pub`：19 项通过。本次标准 CLI 测试已能正常执行。
- `./gradlew --version`：确认 Gradle 9.3.1，构建运行 JDK 为 Android Studio JBR 21。
- 升级后的 ARM64 release APK 构建尚未验证：Gradle 守护进程在 `ServerSocketChannel.bind` / `Net.listen` 被当前执行环境拒绝（`SocketException: Operation not permitted`）。尝试 `--no-daemon` 仍需单次守护进程，结果相同，未进入项目配置及编译阶段。
- 用户已手动完成旧工具链 APK 构建；现有 `app-arm64-v8a-release.apk` 不是上述工具链升级后的验证产物。

参考：
- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
- https://developer.android.com/build/releases/agp-9-1-0-release-notes
- https://kotlinlang.org/docs/gradle-configure-project.html
- https://gradle.org/release-checksums/

## 接续检查（升级前）

- 重新运行 `flutter analyze --no-pub`：无问题；独立核心检查 15 项全部通过。
- 重新编译无端口测试入口，在系统字体和 Flutter 标准测试字体下分别执行：均为 19 项通过、0 失败。
- 修复标准测试字体下侧栏应用名称横向溢出的问题；标题现在受侧栏可用宽度约束。
- 再次执行标准 `flutter test --no-pub`：测试传输仍无法绑定 `127.0.0.1`，测试未加载；无端口测试结果不能记作标准 CLI 测试已通过。
- 再次执行 ARM64 release APK 构建：Gradle `FileLockContentionHandler` 仍因 `java.net.SocketException: Operation not permitted` 无法启动。尚无 APK。
- ADB 服务也无法监听本机端口 5037，因此本次未连接或安装到设备，未改动设备学习数据。

## 已通过

- Flutter 静态分析：无问题。
- 真实 Flutter / test_api 测试：19 项通过，0 失败。由于标准 Flutter CLI 测试传输需要本机端口，本次使用 `app/tooling/run_socket_free_tests.dart` 在 Flutter engine 中执行同一批测试。
- 独立核心检查：15 项通过，涵盖账号隔离、并发写入、重启恢复、损坏文件恢复、稳定每日任务、复习优先级、重复评分保护、故事校验、SSE 完整性及 UTF-8 分段解码。
- 平板 1280×800 离屏渲染：首页、词库、故事空状态、学习者切换弹窗，无布局错误或溢出。
- Android 三份 Kotlin 源码的独立编译检查通过。该检查使用缓存中的 Android/Flutter/AndroidX 依赖和临时资源 ID 声明；不能替代完整 Gradle APK 构建。
- 完整词库：2,809 个唯一词条，词频排名 1～2,809，全部有中英文基础释义及英美发音元数据。
- 音频：Kokoro 1.0 / Misaki，英音 bf_emma、美音 af_heart，共 5,618 段 MP3；完成全量解码检查。read 使用动词原形读音，close 对应官方主释义中的副词读音。音标与多义词发音仍需要人工持续抽查。

## 未完成验证

- APK 构建尝试被当前执行环境阻止：Gradle 的 FileLockContentionHandler 创建本机通信 socket 时返回 `Operation not permitted`。不是一次成功的 APK 构建，也未安装到设备。
- 新应用的 ChatGPT 登录、模型可用性、实际生成质量及断网行为，需要在安装后验证。接入代码来自 FCE-Go 的已验证方案，但新应用使用独立身份和安全存储。
- 系统语音包、动态故事音频缓存、Android 生命周期和 KPad 实际播放效果尚未经过实机检查。
- 当前 33 张词卡随附原创搭配与例句，其余通过 GPT 按需补充并缓存在当前学习者名下；不宣称全词库已离线预置全部例句。
- 学习者档案没有密码，定位是家庭学习进度隔离；没有云同步。

## 在普通终端继续构建

在项目根目录运行 `bash tooling/verify_and_build.sh`。保留同一签名和应用标识，后续安装只使用 `adb install -r`，不要卸载或清除应用数据。
