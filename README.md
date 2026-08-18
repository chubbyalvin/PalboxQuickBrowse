# Palbox Quick Browse

Ever been frustrated with Palworld's vanilla Pal Details menu?

When checking several Pals, you normally have to open a Pal's details, go back to the list, select another Pal, open their details, and repeat the process over and over.

**Palbox Quick Browse** makes this much faster by letting you browse directly through your Pals while keeping the Pal Details page open.

## Features

- Browse the previous or next Pal without leaving the Details page
- Use **A / D** or the **Left / Right Arrow Keys** with keyboard
- Use **LT / L2** or **RT / R2** with controller
- On-screen navigation controls for mouse users
- Automatically skips empty Palbox slots
- Navigation buttons automatically disappear when you reach the first or last available Pal
- Works when viewing:
  - Palbox Pals
  - Base Pals
  - Party Pals from within the Palbox
  - Party Pals from the separate Party menu
- Supports expanded Party sizes dynamically
- Lightweight UE4SS mod
- No configuration required

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Previous Pal | **A** or **←** | **LT / L2** |
| Next Pal | **D** or **→** | **RT / R2** |

You can also click the navigation controls displayed on the left and right sides of the Pal Details screen.

## Installation

### Requirements

- Palworld
- UE4SS

### Option 1 — Standard UE4SS Installation

If your UE4SS installation is inside the Palworld game directory, extract the `PalboxQuickBrowse` folder into:

    ...\Palworld\Pal\Binaries\Win64\ue4ss\Mods\

The final structure should look like:

    ...\Palworld\Pal\Binaries\Win64\ue4ss\Mods\
    └── PalboxQuickBrowse
        ├── enabled.txt
        └── Scripts
            └── main.lua

### Option 2 — Steam NativeMods UE4SS Installation

If you are using the Steam-style UE4SS installation under Palworld's `Mods\NativeMods` directory, extract the `PalboxQuickBrowse` folder into:

    ...\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\

The final structure should look like:

    ...\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\
    └── PalboxQuickBrowse
        ├── enabled.txt
        └── Scripts
            └── main.lua

Your Steam library drive or folder may differ.

## Usage

1. Start Palworld.
2. Open your Palbox.
3. Open a Pal's Details page.
4. Use **A / D**, **← / →**, **LT / L2**, **RT / R2**, or the on-screen controls to browse directly between Pals.

The mod automatically skips empty slots.

When you reach the first available Pal, the previous button disappears. When you reach the last available Pal, the next button disappears.

## Compatibility

Palbox Quick Browse currently supports browsing:

- Palbox Pals
- Base Pals
- Party Pals accessed from within the Palbox
- Party Pals from Palworld's separate **Party menu**
- Expanded Party layouts

## Troubleshooting

If the mod does not appear to load:

1. Confirm UE4SS is installed and working.
2. Confirm the folder structure is correct.
3. Make sure `enabled.txt` is inside the `PalboxQuickBrowse` folder.
4. Confirm that `main.lua` is located at:

       PalboxQuickBrowse\Scripts\main.lua

If you encounter a bug, please open an issue on GitHub and include your **UE4SS.log** file when possible.

## Credits

Created by **ChubbyAlvin**.

If you modify, redistribute, or use this mod's source code in another project, please give appropriate credit to **ChubbyAlvin** as the original author.

## License

This project is licensed under the **MIT License**.

See the `LICENSE` file for details.
