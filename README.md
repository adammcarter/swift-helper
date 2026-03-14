# 🛠️ swift-helper

This package automates the setup, build, and installation of local Swift toolchains.


Setting up the toolchain and knowing what to build when wanting to contribute to the [Swift repo](https://github.com/swiftlang/swift) can be daunting when starting out.

This tool aims to remove this initial complexity and lower the barrier to entry for anyone wanting to contribute to Swift and its related repos through a simple and easy to use command line interface tool.


## 🚀 Installation

> [!IMPORTANT]
> This tool assumes you are running on a Mac with an Apple Silicon chip (M1, M2 etc.)
> 
> Run this command to check your Mac is running on Apple Silicon, if it prints `arm`, you're good to go.

> ```
> uname -p
> ```

Install the `swift-helper` tool:

```bash
source <(curl -sL https://raw.githubusercontent.com/adammcarter/swifthelper/main/install.sh)
```


## 💻 Usage

**Preflight: Clone the Swift repo**

> [!WARNING]
> Skip this step if you've already cloned the [Swift repo](https://github.com/swiftlang/swift).


> [!IMPORTANT]
> Clones in to your current working directory.

```bash
swift-helper clone
```

**1. Setup your environment**

```bash
swift-helper doctor
```

**2. Build your toolchain**
```bash
swift-helper build
```

**3. Activate in Xcode**
Select **Swift Local** from the **Xcode > Toolchains** menu.

<img width="500" alt="Xcode, Toolchains menu" src="https://github.com/user-attachments/assets/b7aa8ce6-a578-4fd3-a207-9a450ed68cb3" />
