# Isla

**An interactive MacBook notch companion for notifications, music, battery, calendar and timers.** Isla is a native macOS menu bar app built with Swift and SwiftUI. It is designed for MacBooks with a built-in notch and runs locally on your Mac.

> Isla is an independent project. Its notch concept was inspired by [Coucou](https://github.com/Louis-CFM/coucou), distributed under the MIT License. Isla's implementation, interface and assets are original.

## Features

- **Claude Code:** optional notifications for permission requests, waiting states and completed tasks. You can allow or deny supported permission requests from the notch.
- **Visual Studio Code:** optional notifications when a VS Code task finishes, including whether it failed.
- **n8n:** optional notices for completed or failed executions from an instance you configure.
- **Music:** view and control Spotify or Apple Music playback.
- **Battery:** alerts at 20%, 10% and 5%, and when power is connected or disconnected.
- **Calendar:** see the next event and its countdown, with reminders before it starts.
- **Timers:** a countdown and a 25/5 minute Pomodoro timer.
- **Custom notifications:** send a notice to Isla from a shell script or another local tool.

Move the pointer over the notch to open Isla's panel with music controls, battery status and recent notifications. An icon in the menu bar opens settings and lets you send a test notification or quit the app.

## Requirements

- A MacBook with a built-in display notch.
- macOS 14 Sonoma or later.
- Xcode Command Line Tools, including Swift 5.10 or later.
- Optional: Claude Code, Visual Studio Code, Spotify, Apple Music, or an n8n instance for their respective integrations.

Isla is not distributed as a signed or notarized installer. Building it on your own Mac creates a locally signed app and avoids relying on a prebuilt download.

## Build and launch

Open Terminal and run:

```sh
git clone https://github.com/ELMURGA/Isla-Notch.git
cd Isla-Notch
./scripts/build-app.sh
open build/Isla.app
```

The build script compiles the Swift package in release mode and creates `build/Isla.app`. The app runs in the menu bar and does not add an icon to the Dock. To quit it, use the Isla menu bar icon and choose **Salir de Isla**.

To compile the executable without packaging the app bundle:

```sh
swift build -c release
```

## First launch and integrations

Isla works without connecting any external service. Enable only the integrations you want from the menu bar icon → **Ajustes…**.

### Claude Code

Choose **Instalar avisos** in Isla's Claude Code settings. Isla adds its supported hooks to `~/.claude/settings.json` and saves a backup first. The hooks apply to Claude Code sessions opened after installation. Choose **Quitar** to remove Isla's hooks.

### Visual Studio Code

The included extension notifies Isla when a VS Code task that runs a process ends. It does not detect every code edit or the end of an AI chat. With VS Code closed, run this from the cloned project directory:

```sh
mkdir -p ~/.vscode/extensions
ln -s "$PWD/integrations/vscode-isla" ~/.vscode/extensions/isla-vscode-notifications-0.1.0
```

Reopen VS Code. To turn these notices off, set **Isla: Notify When Task Ends** to `false` in VS Code settings. To uninstall, remove the link:

```sh
rm ~/.vscode/extensions/isla-vscode-notifications-0.1.0
```

### n8n

In Isla's n8n settings, enter your own n8n base URL and API key. Create the key in n8n under **Settings → n8n API**. Isla keeps the key in the macOS Keychain. The first successful poll records the latest execution, so old runs are not announced. Failed runs are reported by default; successful runs are optional.

### Calendar and music

macOS may ask for Calendar access when Isla reads your next event. Music controls need Spotify or Apple Music to be open and playing. macOS may ask to allow Isla to control the selected music app.

### Custom notifications

After Isla has been built and launched, send a notification from Terminal:

```sh
"$HOME/Library/Application Support/Isla/isla-notify" "Build terminado" "La compilación ha acabado correctamente."
```

The app also accepts a source label, for example:

```sh
"$HOME/Library/Application Support/Isla/isla-notify" --source chatgpt "Tarea terminada" "Tu automatización ha terminado."
```

ChatGPT does not provide a public local callback for the end of every response. This command can be called by an automation you configure; Isla does not intercept ChatGPT activity by itself.

## Project structure

```text
Sources/Isla/             Native macOS app and integrations
Resources/                App icons and source logos
integrations/vscode-isla/  VS Code task notification extension
scripts/build-app.sh       Build and package Isla.app
Package.swift             Swift package manifest
```

## Privacy and permissions

- Isla runs locally and stores the optional n8n API key in the macOS Keychain.
- The n8n integration makes requests only to the base URL you enter in settings.
- Claude hooks are installed only after you choose to install them; the installer backs up the existing settings file first.
- Calendar and music integrations use macOS permissions and local applications.
- Do not commit API keys, personal hook configuration, build output or app bundles to this repository.

## License

Isla is released under the MIT License. See [LICENSE](LICENSE). The original idea and technique for a notch companion were inspired by Coucou; its code, sounds and graphics are not included.

## Credits

Made by [Alejandro Hernández Murga](https://github.com/ELMURGA) for Dazenty. Questions or suggestions are welcome through [GitHub Issues](https://github.com/ELMURGA/Isla-Notch/issues).
