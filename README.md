

# Omarchy Notification Center

A native notification center for **Omarchy**. This plugin is also available on the Omarchy Plugin Marketplace: https://omarchyplugins.com/plugin.html?id=shavanced.notification-center

It adds a searchable panel for live notifications and persistent notification history while continuing to use Omarchy's built-in `omarchy.notifications` service.

> **No Mako. No replacement notification daemon. No extra background service.**

## Preview

![preview.png](https://github.com/Shavanced/omarchy-notification-center-plugin/blob/main/preview.png?raw=true)


In the preview I am using my custom "Ame-quattro" theme, feel free to check: https://github.com/Shavanced/ame-quattro.git

## Features

- **Live notifications** from Omarchy's first-party notification service.
- **Persistent notification history** maintained by Omarchy.
- History is shown without replaying old notifications as new popups.
- Search notifications by application, title, or body.
- Individual dismissal for live notifications.
- Clear all live notifications and saved history.
- Theme-aware Omarchy UI.
- Optional notification bar widget.
- Live notification count on the bar widget.
- `Esc` and the panel controls can be used to close the center.
- Does not replace Omarchy's normal notification popups.

## Requirements

- Omarchy with the first-party `omarchy.notifications` notification service.
- Quickshell/Omarchy plugin support.

This plugin is designed specifically for Omarchy and relies on the notification
history provided by Omarchy's notification service.

## Installation

### Omarchy plugin system

Run this to install:

```bash
omarchy plugin add https://github.com/Shavanced/omarchy-notification-center-plugin.git --enable
```

If the plugin is already installed:

```bash
omarchy plugin enable shavanced.notification-center
```

### Manual installation

Clone the repository into Omarchy's third-party plugin directory:

```bash
git clone https://github.com/Shavanced/omarchy-notification-center-plugin.git   ~/.config/omarchy/plugins/shavanced.notification-center
```

Validate it:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/shavanced.notification-center
```

Enable it:

```bash
omarchy plugin enable shavanced.notification-center
```

Then reload the shell/plugin registry:

```bash
omarchy-shell shell rescanPlugins
```

## Usage

Open the notification center through Omarchy's shell IPC:

```bash
omarchy-shell shell toggle shavanced.notification-center '{}'
```

The notification bar widget can be added/positioned through Omarchy's plugin/bar controls.

Test it with:

```bash
notify-send -a "Test" "Notification Center" "Hello from Omarchy!"
```

## How it works

The plugin does **not** create its own notification daemon.

It integrates with Omarchy's existing notification service:

```text
Applications
     │
     ▼
omarchy.notifications
     │
     ├── Live notifications ──► normal Omarchy popups
     │
     └── Persistent history ──► Notification Center
```

Opening the Notification Center does not replay historical notifications as
new popups.

When a live notification expires or is dismissed, its historical entry can
remain visible in the notification center according to Omarchy's stored
history.

## Current limitations

The notification history is maintained by Omarchy's notification service.
This plugin does not replace that storage layer.

The current Omarchy notification API does not expose an individual-history
dismissal API or a read/unread API, so:

- Individual dismissal is available for live notifications.
- Historical notifications follow Omarchy's stored history.
- Clear All can clear the available live notifications and saved history.
- The number of retained historical entries is determined by Omarchy.

These limitations may change as Omarchy's notification API evolves.

## Development

Clone the repository:

```bash
git clone https://github.com/Shavanced/omarchy-notification-center-plugin.git
cd omarchy-notification-center-plugin
```

Validate:

```bash
omarchy plugin validate .
```

Lint:

```bash
qmllint NotificationCenter.qml BarWidget.qml
```

After editing a local plugin:

```bash
omarchy-shell shell rescanPlugins
```
## Security

Omarchy plugins run as unsandboxed code inside the long-lived Omarchy shell
process. Only install this plugin from a source you trust and review changes
before enabling it.

## License

MIT
