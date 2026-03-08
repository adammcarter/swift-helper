# 🛠️ swift-helper

Automates the setup, build, and installation of local Swift toolchains.

## 🚀 Installation

```bash
source <(curl -sL https://raw.githubusercontent.com/adammcarter/swifthelper/main/install.sh)
```

## 💻 Usage

**Clone Swift source**

> [!WARNING]
> Skip this step if you've already cloned the [Swift repo](https://github.com/swiftlang/swift).

```bash
swift run swift-helper clone
```

**1. Check environment**

> [!WARNING]
> This tool assumes your cloned `swift-project` repo containing swift etc. is under `~/repos`

```bash
swift run swift-helper doctor
```

**2. Build toolchain**
```bash
swift run swift-helper build
```

**3. Activate in Xcode**
Select **Swift Local** from the **Xcode > Toolchains** menu.

<img width="500" alt="Xcode, Toolchains menu" src="https://github.com/user-attachments/assets/b7aa8ce6-a578-4fd3-a207-9a450ed68cb3" />
