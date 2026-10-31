# Total War: Warhammer 3 — how to remove a mod that won't uninstall the usual way

A mod usually "won't uninstall" because its file stayed on disk or in the launcher's list after you unsubscribed in Steam. Close the game and the launcher, then follow these steps.

## 1. Unsubscribe in Steam

In the Workshop, open "Your Files" → "Subscribed Items" and unsubscribe from the mod: if you only delete the file, Steam will download it again.

## 2. Delete the mod's Workshop folder

It is located in:

```
...\Steam\steamapps\workshop\content\1142710\<mod ID>\
```

The ID is the number in the link to the mod's page.

## 3. Check the game's `data` folder

```
...\Steam\steamapps\common\Total War WARHAMMER III\data\
```

Delete the mod's `.pack` file if it is there. Mods installed manually or through a third-party manager end up here. "Movie" type mods in this folder are always loaded, even if they are not ticked in the launcher.

Do not touch the vanilla files (`data.pack`, `local_*.pack`, etc.). If you are not sure, sort by date modified: the mod will be among the most recent files.

## 4. Reset the launcher's mod list

In the folder:

```
%APPDATA%\The Creative Assembly\Launcher\
```

delete the file named like `*-moddata.dat`. The launcher will recreate it, but your mod order and ticks will be reset.

## 5. Delete `used_mods.txt`

If it exists, it is in the root of the game folder: it records which mods to load.

## 6. Verify file integrity

In Steam: right-click the game → "Properties" → "Installed Files" → "Verify integrity of game files". This restores the vanilla files if the mod replaced anything.

## If the mod still comes back

- The subscription is still active, possibly through a collection.
- A third-party mod manager is restoring it from its profile.

## About saves

Saves made with the mod may fail to load or crash after it is removed.
