# JF Catalogue – Jellyfin plugin

Serves an offline, installable catalogue of your library from your own Jellyfin server. Open the link on your phone once, add it to your home screen, and it keeps working in a shop with no signal, or with the server switched off.

No GitHub account, scripts or scheduled tasks needed: everything is set up in the Jellyfin dashboard.

> JF Catalogue is an independent project, not affiliated with or endorsed by the Jellyfin project.

**Works with:** Jellyfin 10.11 and 12.x.

## Install

1. In Jellyfin, go to **Dashboard > Plugins > Repositories** (on 10.11: *Catalog > Settings*) and add:
   - Name: `JF Catalogue`
   - URL: `https://raw.githubusercontent.com/stephenbeale/jellyfin-catalogue/master/plugin/manifest.json`
2. In the **Catalog**, find **JF Catalogue** and install it. Jellyfin picks the right build for your server version.
3. Restart Jellyfin.

## Set up

Open **Dashboard > Plugins > JF Catalogue**:

| Setting | What it does |
|---|---|
| **Catalogue link** | Your private link, `https://<your-server>/JFCatalogue/<secret>/`. Copy it, or open it on your phone. |
| **Link is on** | Turn the link off entirely. |
| **New link** | Makes a new secret. The old link (and home-screen apps made from it) stop working. Use it if the link got shared too widely. |
| **Title** | Name shown in the header and under the home-screen icon, e.g. "Steve's DVDs". |
| **Movies / TV series / Music albums** | Which content types to include. |
| **Libraries** | Only include some libraries (e.g. leave out "Kids" or a private library). None ticked = all. |
| **Plot summaries / Actors and directors** | Leave them out for a smaller, more private catalogue. |

**Save and rebuild** applies the settings straight away. After that the catalogue rebuilds daily at 04:00. You can change the time in **Dashboard > Scheduled Tasks > Rebuild JF Catalogue**, which is also where a failed rebuild shows up.

## On your phone

1. Open the catalogue link while your phone can reach the server (e.g. on home Wi-Fi).
2. Add it to your home screen: **Install app** on Android, or Share > **Add to Home Screen** on iPhone.
3. From then on it opens from the copy saved on the phone whenever the server can't be reached, with a banner saying when it was last updated. It refreshes whenever it can reach the server again.

## Privacy

The catalogue page is not behind a Jellyfin login, because a phone opening a home-screen app has no Jellyfin session. Access is controlled by the 128-bit secret in the link instead. Anyone with the link can see titles and details (not your media files, and not your Jellyfin account). Turn the link off or make a new one at any time.

## Build it yourself

Needs the .NET 10 SDK.

```bash
cd plugin/Jellyfin.Plugin.JFCatalogue
dotnet build -c Release                                                  # Jellyfin 12.x
dotnet build -c Release -p:JellyfinVersion=10.11.11 -p:JellyfinTfm=net9.0   # Jellyfin 10.11
```

Copy `bin/Release/<tfm>/Jellyfin.Plugin.JFCatalogue.dll` into a folder such as `plugins/JF Catalogue_0.1.0.0/` in your Jellyfin data directory, then restart Jellyfin.

The web app is not duplicated: the build embeds the repo's own `index.html`, `sw.js`, `manifest.webmanifest` and `icons/`.

## Releasing (maintainer)

Push a tag such as `plugin-v0.1.0`. `.github/workflows/plugin.yml` then builds both server lines, attaches the zips to a GitHub release, and adds them to `plugin/manifest.json` on master. The fourth version number is the server line (`0.1.0.12` for 12.x, `0.1.0.11` for 10.11), so each server picks its own build.
