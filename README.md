# Parayaya-NS
##### Server emulator for the game Honkai: Nexus Anima
# ![title](assets/img/screenshot.png)

# Getting started
### Requirements
- [Zig 0.15.1](https://ziglang.org/download)
- [SDK server](https://git.xeondev.com/reversedrooms/hoyo-sdk)
##### NOTE: this server doesn't include the sdk server as it's not specific per game. You can use `hoyo-sdk` with this server.

#### For additional help, you can join our [discord server](https://discord.xeondev.com)

### Setup
#### a) building from sources
```sh
git clone https://git.xeondev.com/parayaya-ns/parayaya-ns.git
cd parayaya-ns
zig build run-parayaya-dispatch
zig build run-parayaya-gameserver
```

#### b) using pre-built binaries
Navigate to the [Releases](https://git.xeondev.com/parayaya-ns/parayaya-ns/releases) page and download the latest release for your platform.
Start each server in order from option `a)`.

### Configuration
Configuration is loaded from current working directory. If no configuration file exists, default one will be created.
- To change server settings (such as server bind address), edit `dispatch_config.zon` (for dispatch).

### Logging in
Currently supported client version is `OSCBWindows0.3.0` aka `First Closed Beta`, you can get it from 3rd party sources. Next, you have to apply the necessary [client patch](https://git.xeondev.com/parayaya-ns/parayaya-patch). It allows you to connect to the local server and replaces encryption keys with custom ones.

## Support
Your support for this project is greatly appreciated! If you'd like to contribute, feel free to send a tip [via Boosty](https://boosty.to/xeondev/donate)!
