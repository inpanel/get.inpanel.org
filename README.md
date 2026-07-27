# InPanel 一键安装

[![InPanel](https://img.shields.io/badge/InPanel-1.2.8-blue)](https://inpanel.org)

通过 `get.inpanel.org` 快速安装 [InPanel](https://github.com/inpanel/inpanel) —— 一个 Web 化的 Linux 服务器管理面板。

## 支持的系统

| 系统 | 版本 | 安装方式 |
|------|------|----------|
| **Ubuntu** | 18.04 / 20.04 / 22.04 / 24.04 | DEB 包（推荐） |
| **Debian** | 10 / 11 / 12 | DEB 包（推荐） |
| **CentOS** | 7 / 8 / 9 | RPM 包（推荐） |
| **RHEL / Rocky / AlmaLinux** | 7 / 8 / 9 | RPM 包（推荐） |
| **Fedora** | 36+ | RPM 包（推荐） |
| **Deepin / UOS** | 20+ | DEB 包 |
| **macOS** | 10.15+ | pip + venv |

> **最低要求：** Python 3.7+，root 权限

## 安装

### 一键安装（推荐）

```bash
curl -fsSL https://get.inpanel.org/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://get.inpanel.org/install.sh | bash
```

脚本会自动检测系统并选择最佳安装方式。

### 指定安装模式

```bash
# 强制使用 DEB 包安装（仅 Debian/Ubuntu）
curl -fsSL https://get.inpanel.org/install.sh | bash -s -- --mode=deb

# 强制使用 RPM 包安装（仅 CentOS/RHEL/Fedora）
curl -fsSL https://get.inpanel.org/install.sh | bash -s -- --mode=rpm

# 使用虚拟环境安装（避免系统 pip 限制）
curl -fsSL https://get.inpanel.org/install.sh | bash -s -- --mode=venv

# 直接 pip 安装（--break-system-packages）
curl -fsSL https://get.inpanel.org/install.sh | bash -s -- --mode=pip-system
```

### 指定端口

```bash
curl -fsSL https://get.inpanel.org/install.sh | bash -s -- --port=14433
```

### 查看帮助

```bash
bash install.sh --help
```

## 安装策略

脚本按以下优先级自动选择安装方式：

| 优先级 | 方式 | 说明 |
|--------|------|------|
| 1 | **DEB / RPM 包** | Debian/Ubuntu 用 DEB，CentOS/RHEL 用 RPM，`purge`/`erase` 可完全卸载 |
| 2 | **pip + venv** | 创建 `/opt/inpanel` 虚拟环境，避免 PEP 668 `externally-managed` 限制 |
| 3 | **pip --break-system-packages** | 最后手段，直接安装到系统 Python 环境 |

## 安装后

安装完成后，访问面板：

```
http://<服务器IP>:14433
```

默认账号：`admin` / `admin`

## 常用命令

```bash
inpanel status              # 查看服务状态
inpanel start               # 启动服务
inpanel stop                # 停止服务
inpanel restart             # 重启服务
inpanel config              # 管理配置
inpanel config set auth password <新密码>   # 修改密码
```

## 卸载

```bash
# DEB 安装方式
sudo apt purge inpanel

# RPM 安装方式
sudo rpm -e inpanel

# pip + venv 安装方式
sudo rm -rf /opt/inpanel /usr/local/bin/inpanel /etc/systemd/system/inpanel.service
sudo systemctl daemon-reload
```

## 相关链接

- [InPanel 主仓库](https://github.com/inpanel/inpanel)
- [问题反馈](https://github.com/inpanel/inpanel/issues)
- [官方网站](https://inpanel.org)
