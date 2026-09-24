# KDEtoContext

Send files to your phone (or any KDE Connect device) straight from the Windows Explorer right-click menu.

## Why use it?

KDE Connect for Windows can already share files, but getting there takes several steps: open the KDE Connect app or tray icon, pick the device, choose "Send file", then browse to the file you were already looking at.

KDEtoContext puts a **"Send to &lt;your device&gt;"** entry directly in the right-click menu, so sending a file is:

1. Right-click the file(s)
2. Click **Send to &lt;device&gt;**

That's it. No app windows, no file picker, no console flashing. It saves a few clicks every time, which adds up fast if you move files to your phone often.

- One menu entry per device, named after the device
- Works with multiple selected files
- Runs silently in the background
- No admin rights needed (writes only to your user registry, `HKCU`)
- Easy to add or remove devices at any time

## Requirements

- Windows 10 / 11
- [KDE Connect for Windows](https://kdeconnect.kde.org/download.html) installed at the default location (`C:\Program Files\KDE Connect`)
- Your device paired with KDE Connect

## How to use

1. Download or clone this repository:
   ```
   git clone https://github.com/arshit09/KDEtoContext.git
   ```
2. Double-click **`KDEConnect-ContextMenu.bat`**.
3. In the menu that opens:
   - Press **A** to add a device. Pick it from the list of paired devices.
   - Press **R** to remove a device you added before.
   - Press **Q** to quit.
4. Right-click any file in Explorer and choose **Send to &lt;device&gt;**.

On Windows 11 the entry is under **Show more options** (or Shift + right-click).

## How it works

- Adds a registry entry under `HKCU\Software\Classes\*\shell\KDEConnect.<device-id>` for each device you choose.
- The entry calls a small hidden VBScript launcher (saved in `%LOCALAPPDATA%\KDEConnectContextMenu\send.vbs`) that runs `kdeconnect-cli --share` on the file.
- Everything is logged to `KDEConnect-ContextMenu.log` next to the script, which helps if a send fails.

## Uninstall

Run the `.bat` again and remove each device with **R**. Then delete the `%LOCALAPPDATA%\KDEConnectContextMenu` folder.

## Troubleshooting

- **No devices listed:** make sure the KDE Connect app is running and the device is paired.
- **File didn't arrive:** the device must be reachable (same network, KDE Connect open). Check `KDEConnect-ContextMenu.log` for the exact error.
- **Different install path:** edit `$KdeBin` and `$Icon` at the top of `KDEConnect-ContextMenu.ps1`.
- **Moved or renamed this folder, or updated the script:** run the `.bat` once and press **Q**. That refreshes the installed launcher so sends are logged next to the script again.
