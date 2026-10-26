# 星星人网页版：后续 Claude 补丁的继承流程

当前原生游戏由 Claude 继续开发；网页适配单独保存在本仓库。不要把原生 `game/` 直接覆盖到网页后立即上传。

## 本次音频修复

- 背景音乐与环境循环使用 Godot 的 Web Audio Sample 播放，提前解码，避免单线程画面繁忙时流式混音断续。
- `game/default_bus_layout.tres` 在启动前声明 Master、Music、Ambience、SFX。实测中动态插入通道会让 Sample 路由错误，播放器位置在走但输出全零。只改播放模式会重现无声。
- `site/assets/web-audio-v172.js` 为引擎输出统一增加音量门。加载时为零；游戏场景准备结束才启动循环并用 0.35 秒淡入。不要用暂停整套 AudioContext 的方式掩盖问题。
- 保留 M 静音、音量设置、天气交叉渐变和重复点击声音恢复按钮；恢复按钮不会重播音乐片头。网页声音以浏览器实际输出为准，Sample 不经过 Godot 流式总线峰值表，不能再用该峰值表判定“没声音”。
- Sample 不支持部分 AudioEffects。未来若新增混响、程序化合成或新音频通道，需要单独验证；不要把全部音乐切回 Stream。

## 合并新补丁

从此仓库目录执行：

```powershell
python scripts/refresh_from_native.py --source D:/claude/starworld/game
python scripts/check_web_contract.py
```

脚本会备份网页脚本、保留浏览器存档命名空间，再同步原生内容、压缩网页 NPC 图像、重新生成完整基本汉字字库、恢复网页专用文件并应用适配。原生目录及正式存档不被改写。若 Claude 改了需要适配的函数结构，脚本会指出需要审查的功能，不能绕过检查直接发布。

快速验证新的原生脚本是否兼容，先不复制大图片、不压缩模型：

```powershell
python scripts/refresh_from_native.py --source D:/claude/starworld/game --out D:/claude/starworld/outputs/web_adapter_trial --code-only
```

`--code-only` 的输出仅用于检查，不能拿来发布。正式导出还必须重新导入资源、按新地图烘焙寻路缓存，并通过实际浏览器检查。GitHub Actions 已包含导入、寻路、导出、音频与操作检查；不要上传旧 PCK。

## 必须继承的已有优化

`scripts/apply_web_adapters.py` 和 `scripts/adapters/` 保存了天空颜色处理、日暮夜雾效响应、完整中文字库与星形符号、预生成寻路、首用效果与字幕准备、花朵与道具缓存、镜头返回、观景椅前景隐藏、网页退出和独立送别入口。`check_web_contract.py` 检查 24 项约束，持续集成也会执行。

不要删除网页专用 `web_shell.html`、`web_platform.gd`、`web_visual_profile.gd`、`ending_checkpoint.gd`、预定义音频通道或网页字体。新地图要重新生成 `walk_grid_web.bin`；新文字要重新生成字体子集；新资源包使用内容指纹，避免浏览器缓存混用。

## 音频验证

安装 Playwright 后，启动本地站点，再执行：

```powershell
node scripts/browser_audio_continuity.cjs audio-evidence http://127.0.0.1:8788/play/
```

测试由独立 AudioWorklet 在音频线程记录输出，不靠页面定时器猜声音是否连续。它检查加载静音、夜晚与白天跑步、傍晚静止/走路/跑步，每段约 22 秒，并记录实际位移。

额外验证傍晚循环开头，并人为给游戏主线程施加 300 毫秒阻塞：

```powershell
$env:AUDIO_DUSK_HEAD_ONLY='1'
$env:AUDIO_STRESS_MAIN='1'
node scripts/browser_audio_continuity.cjs dusk-opening http://127.0.0.1:8788/play/
```

记录静音段的阈值为 20 毫秒，不能据此宣称所有电脑、所有声音都绝无瑕疵。还要验证切换天气、静音与恢复、新游戏后音乐存在，最后等待云端构建和部署成功。

参考：[Godot 官方 Web 音频说明](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html#export-options)、[Sample 注册与播放说明](https://docs.godotengine.org/en/4.4/classes/class_audioserver.html)。
