# Omarchy Notification Center

Native Omarchy v4 Quickshell panel for the first-party `omarchy.notifications`
service. It does not start, replace, or configure a separate notification daemon.

## Features

- Live notifications from the running Omarchy notification service.
- Persistent notification history collected by that service.
- Search by application, title, or body.
- Per-notification dismissal for live notifications and clear-all for live
  notifications plus saved history.
- A theme-aware optional bar icon with a live-popup count.

## Use

```bash
omarchy plugin validate ~/.config/omarchy/plugins/shahriar.notification-center
omarchy-shell shell rescanPlugins
omarchy-shell shell toggle shahriar.notification-center '{}'
```

Enable the plugin through Omarchy if it is not already enabled:

```bash
omarchy plugin enable shahriar.notification-center
```

The bar widget can then be placed using Omarchy's bar/plugin controls.

## Limits of the current Omarchy API

The notification service persists its newest ten historical entries and does
not expose an individual-history-dismiss or read/unread API. This panel shows
the history exactly as maintained by Omarchy; only live notifications have an
individual dismissal action.
