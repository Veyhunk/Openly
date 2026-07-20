# Openly

<div align="center">

<img src="Assets/icon.png" width="128" alt="Openly icon">

**打开方式，一目了然**

macOS 文件打开方式管理工具 — 按后缀选 App，按 App 管后缀

</div>

---

## 功能

- **扩展名视图** — 表格展示所有已知扩展名及默认打开 App，支持搜索、分类、系统/第三方筛选
- **App 视图** — 查看每个已安装 App 管理的所有文件格式，显示版本和路径
- **更换默认 App** — 为任意扩展名选择新的默认打开程序
- **批量操作** — 多选扩展名，一键统一分配给同一个 App
- **清除关联** — 解除扩展名与 App 的绑定，恢复未关联状态
- **内置描述库** — 655 个扩展名的中文描述，分 13 大分类
- **导出/导入** — 配置文件关联到 JSON，支持备份和恢复
- **xattr 清理** — 检测并清除单文件级别的 OpenWith 覆盖

## 安装

### 从源码构建

```bash
# 要求：macOS 14+，Swift 6+
git clone https://github.com/user/openly.git
cd openly
swift build
```

构建产物在 `.build/debug/Openly`，可直接运行或复制到 `/Applications`。

### Homebrew（即将支持）

```bash
brew install --cask openly
```

## 使用

1. 启动 Openly
2. **扩展名** 标签页查看所有已知文件格式
3. 搜索或按分类筛选，点击右侧箭头更换默认 App
4. **应用** 标签页查看已安装 App 管理的格式
5. Cmd+R 刷新，Cmd+S 导出配置

## 系统要求

- macOS 14 Sonoma 及以上
- Apple Silicon 或 Intel Mac

## 技术

原生 SwiftUI + AppKit 构建，纯 SPM 管理（无需 Xcode 项目文件）。使用 macOS Launch Services API 读取和修改文件关联。

## 许可

MIT License

---

<div align="center">
<sub>Built for macOS · Inspired by Finder's "Open With"</sub>
</div>
