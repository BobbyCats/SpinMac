<div align="center">

<img src="docs/assets/hero.svg" alt="SpinMac — 原生 macOS 屏幕与触控板旋转工具" width="100%"/>

<br/><br/>

# SpinMac

**把 MacBook 像书一样侧立在床上：屏幕、触控板与多指手势，一键同步翻转（或彻底解耦）。**

纯原生 SwiftUI & AppKit · 联动或独立旋转 · 多指手势全量一致 · **静止 0% CPU**

<p>
  <a href="#快速开始"><img src="https://img.shields.io/badge/macOS-14%2B%20(Sonoma%20%E2%80%93%2026)-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+"/></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6"/>
  <img src="https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-14B8A6?style=for-the-badge" alt="全架构支持"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-22C55E?style=for-the-badge" alt="MIT 开源协议"/></a>
</p>

<p>
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

</div>

---

## 这玩意是怎么诞生的（说出来你可能不信）

一切的起点其实特别朴素：**我只是想舒舒服服躺在床上玩会儿 MacBook。**

但在床上用笔记本有个千古难题——坐直了玩太累，平躺着架在肚子上又根本不好打字和操作。直到某天**侧躺**的时候，我突然悟到了一个反重力姿势：**把 MacBook 沿着侧面立起来，像一本打开的硬壳书一样卡在床垫上。** 它居然稳得离谱！

唯一的问题来了：MacBook 在没有外接显示器的时候，macOS 系统设置里把**屏幕旋转**选项直接藏起来了；就算费劲找办法把画面转成竖屏，触控板还死死留在横屏维度里——手指往上划，鼠标往右飙，双指翻页和切桌面全在跟你唱反调。尝试过一些零散方案，要么只能单独转屏，要么还得折腾一堆步骤去配触控板。

于是干脆自己撸了这个小工具 **SpinMac**：
以后不管是**朝右侧躺（`270°`）**还是**朝左侧躺（`90°`）**，按一下快捷键 `⌃⌥⌘R`，**屏幕和触控板（连带三指拖移、双指滚动、切换桌面等所有多指手势）一起转过来**；想把屏幕和触控板拆成不同角度单独玩也完全没问题。

> **认真插播一条护眼提醒**
> 工具虽顺手，但**千万别长时间侧躺看电脑**！双眼焦距不对称很容易加重散光和视疲劳，颈椎也会抗议。SpinMac 适合临时偷个懒、或者搭配桌面特殊摆放姿势使用，该坐起来的时候还是得坐起来，保护眼睛要紧。

---

## SpinMac 能做什么

### 1. 左翻身、右翻身，或者屏与板彻底解耦
- **联动模式（默认）**：按 `⌃⌥⌘R` 或点选 `90° / 180° / 270°`，MacBook 内建屏与触控板同步旋转。如果连接并旋转外接显示器，笔记本自带触控板会自动保持 `0°` 不误伤。
- **独立模式**：彻底解耦屏幕和触控板的方向——比如屏幕保持 `0°` 横屏不动，桌面上侧放的外接妙控板单独旋转 `270°`；或者屏幕 `90°` 配触控板 `180°`，四个角度任意自由组合。
- **关闭模式**：只转屏幕，触控板事件拦截彻底休眠，零开销。

### 2. 正着能做的手势，转过来照样顺手

| 输入 / 手势 | 旋转后的原生体验 |
| :--- | :--- |
| **指针移动、点击与三指拖移** | HID 层增量旋转 + 多屏边界钳制虚拟光标 + 左/右/中键位置精准同步 |
| **双指滚动与惯性** | 连续滚动与惯性向量同步旋转，完整保留你的系统「自然滚动」习惯 |
| **双指左右翻页** | Safari / Chrome / Finder 前进后退手势自动对齐视觉左右方向 |
| **三/四指切换桌面与调度中心** | 同时重写 `CGEvent` 与底层 `IOHIDEvent` 的 Dock-swipe 向量，Spaces、Mission Control、App Exposé 照常丝滑 |
| **外接鼠标与物理滚轮** | 基于 `MultitouchSupport` 实时硬件接触态门控，外接 USB/蓝牙鼠标永远原样透传不干扰 |

### 3. 原生菜单栏交互 & 120fps 实时校准
- **左键控制中心 + 右键快捷菜单**：
  - **左键点托盘图标**：弹出原生毛玻璃控制中心，带实时双体 MacBook 硬件姿态动画（屏幕与触控板箭头各自独立指向）和底栏 `中 / EN` 一键双语切换；
  - **右键点托盘图标**：直接展开原生 `NSMenu` 快捷菜单，无需打开面板就能切换角度、触控板模式、界面语言、打开设置或退出。
- **120fps 实时轨迹校准 & 「向上划一笔自动校准」**：
  - 打开 **偏好设置 → 方向校准**，GPU 加速的 SwiftUI `Canvas` 左右同屏显示物理坐标与映射输出，自带渐隐手指运动轨迹与方向矢量箭头；
  - 分不清当前姿势该选 `90°` 还是 `270°`？点 **「向上划一笔自动校准」**，顺着你眼前的“正上方”划一下，自动识别并应用。
- **为了“偷懒”顺手做满的工程细节**：
  - **静止 0.0% CPU**：切回 `0°` 或关闭触控板旋转时，自动停用双 `CGEventTap` 并通过引用计数彻底停止硬件触控回调。
  - **独立高优先级事件线程**：事件拦截运行在专属 `.userInteractive` 线程，绝不因 UI 动画卡顿影响光标跟手度。
  - **10 秒防翻车悬浮 HUD**：切入竖屏或倒置时，在目标屏幕正中央弹出毛玻璃确认条——按 `Return` 保留、按 `Esc` 立刻还原、10 秒未确认自动复原。
  - **光标安全底线**：停用、超时、退出或异常终止（`applicationWillTerminate` + `atexit`）无条件恢复硬件光标绑定，绝不锁死光标。

---

## 架构总览

<div align="center">
  <img src="docs/assets/architecture.svg" alt="SpinMac 架构管线图" width="100%"/>
</div>

### 关于私有系统框架的透明说明
由于 macOS 公开 API 未开放内建屏旋转和底层 Dock 手势重写，SpinMac 在运行时动态加载三个系统框架：
- `MonitorPanel.framework`（`MPDisplay.setOrientation:`）：驱动内建与外接显示器原生旋转；
- `MultitouchSupport.framework`（`MTDeviceCreateList` 与触控帧回调）：精准区分触控板与外接鼠标，并驱动实时校准画板；
- `SkyLight.framework` / `IOKit`（`SLEventCopyIOHIDEvent`、`SLEventSetIOHIDEvent`、`IOHIDEvent*`）：重写多指切桌面与翻页手势向量。

正因如此，**SpinMac 通过 GitHub 开源分发而非上架 Mac App Store**；所有符号均动态探测加载并保留安全降级路径。

---

## 快速开始

### 环境要求
- **macOS 14.0+**（Sonoma / Sequoia / macOS 26 Tahoe）
- **Swift 6.0+** / Xcode 16+（从源码编译时需要）

### 一键编译安装

```bash
git clone https://github.com/BobbyCats/SpinMac.git
cd SpinMac

# 自动跑完单元测试、Release 编译、双语 96 项文案校验、打包签名并安装到 /Applications/SpinMac.app
./Scripts/build_app.sh
```

> **开发者签名与公证（可选）：**
> 传入 Apple Developer ID 签名标识可让 macOS 在每次重编后继续保留权限授权：
> ```bash
> SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build_app.sh
> ```
> 如需签名并走 Apple `notarytool` 公证打包发布 ZIP：
> ```bash
> SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
> NOTARY_PROFILE="your-notary-profile" \
> ./Scripts/notarize.sh
> ```

### 权限说明
1. **屏幕旋转**无需任何额外权限，装好就能用。
2. **触控板与多指手势旋转**需要授予 **辅助功能（Accessibility）** 和 **输入监控（Input Monitoring）**（系统设置 → 隐私与安全性），点主界面里的「去授权」胶囊即可自动跳转并即时生效。

---

## 常见问题

<details>
<summary><strong>会影响我的外接鼠标吗？</strong></summary>

完全不会。SpinMac 仅在检测到目标触控板有真实硬件触摸接触时才转换指针与连续滚轮，外接有线/蓝牙鼠标与刻度滚轮永远原样透传。
</details>

<details>
<summary><strong>旋转外接竖屏时，会把笔记本自带触控板也转歪吗？</strong></summary>

不会。在默认的 **「联动 + 仅内建触控板」** 模式下，旋转外接显示器时内建触控板保持 `0°`。如果搭配侧放的外接妙控板，切到 **「独立」** 模式即可给触控板自由设定任意角度。
</details>

<details>
<summary><strong>万一 App 意外退出，光标会卡死吗？</strong></summary>

不会。SpinMac 同时注册了 `applicationWillTerminate` 与 C 层 `atexit` 兜底钩子，任何情况下退出或停用都会无条件恢复 `CGAssociateMouseAndMouseCursorPosition(1)`。
</details>

---

## 参与贡献与协议

欢迎提交 Issue、不同 macOS 版本的实测反馈或 PR，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

本项目基于 [MIT License](LICENSE) 开源，全部源码从零洁净室编写。希望这个为了侧躺刷电脑顺手写出来的小工具，也能给你带来一点有意思的参考！
