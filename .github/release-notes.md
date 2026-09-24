## 安装

1. 下载下面的 `cloudtune-x.y.z-macos.dmg`，双击打开，把 **CloudTune** 拖进「应用程序」窗口。
   （也有 `.zip` 版本，解压后同样拖进「应用程序」。）

2. **首次打开一定会被系统拦住** —— 安装包是 ad-hoc 签名、**未做 Apple 公证**
   （公证需要每年 99 美元的付费开发者账号）。提示「无法验证开发者」或
   「Apple 无法验证…是否包含可能危害 Mac 安全或泄漏隐私的恶意软件」都是这个原因，
   **不是中毒，也不是安装包损坏，请不要删除应用。**

3. 按你的 macOS 版本放行一次：

   **macOS 26 (Tahoe) 及以上** —— 系统已移除「右键 → 打开」旁路，隐私与安全性里也可能
   不出现「仍要打开」按钮。打开「终端」执行：

   ```bash
   xattr -rd com.apple.quarantine /Applications/cloudtune.app
   ```

   **macOS 15 (Sequoia)** —— 在「应用程序」里右键点 CloudTune → 打开 → 弹窗里再点一次「打开」。

   **macOS 14 及更早** —— 右键点 CloudTune → 打开 → 再点「打开」。

4. 之后就可以正常双击启动了。

**系统要求**：macOS 11 (Big Sur) 或更高；Apple Silicon 与 Intel 均可（通用二进制）。

完整说明（系统要求、源码构建、常见问题、签名校验）见
[README 的「安装」章节](https://github.com/tanchang03/cloudtune#安装)。

> ⚠️ **使用前请先读 [法律声明](https://github.com/tanchang03/cloudtune/blob/main/DISCLAIMER.md)。**
> 本项目是第三方独立开源客户端，与夸克、阿里云盘、百度网盘官方均无关联、未获其授权或认可。
> 仅供播放**你自己账号下、你有合法访问权**的文件，请勿用于账号共享、对外提供服务或商业化用途。

---

## 本次更新
