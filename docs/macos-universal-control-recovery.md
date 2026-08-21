# Universal Control between the M1 and M4 MacBooks

## Current recommendation

Use macOS Screen Sharing instead of Universal Control for this setup. Universal Control resumed working after the recovery procedure below, but stopped working again shortly afterward. The reset is therefore a temporary workaround, not a reliable fix.

Screen Sharing has been more dependable, keeps control inside the remote M4 display, and correctly forwards keyboard shortcuts when the Screen Sharing window is active. Avoid High Performance mode when the M4 must continue displaying its desktop on the attached TV.

## Temporary recovery procedure

Use this procedure when the M4 MacBook does not appear as a keyboard and mouse link target on the M1 MacBook, even though the Universal Control settings appear to be enabled.

1. On both MacBooks, open **System Settings > Displays > Advanced**.
2. Turn off all three keyboard-and-mouse linking settings on both machines.
3. Reboot both MacBooks while those settings are off.
4. Return to **System Settings > Displays > Advanced** on both machines.
5. Turn all three linking settings back on on both machines.
6. On the M1, open **System Settings > Displays** and select the **+** menu.

After this reset, the M4 may appear in the **+** menu as a link target. Select it to let the M1 keyboard and mouse control the M4.

Merely toggling the settings was not enough. The sequence that temporarily worked was to disable all three settings on both Macs, reboot both Macs, and then re-enable all three settings. Universal Control later stopped working again without an intentional configuration change, which points to unreliable macOS behavior rather than a durable settings problem.
