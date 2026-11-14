# Yomou Desktop

Yomou Desktop is the Linux desktop build of **Yomou**, a free and open-source
manga reader built with Flutter.

> The Android and iOS app lives in a separate repository:
> [Hlomatsimaxwell/Yomou](https://github.com/Hlomatsimaxwell/Yomou).
> Desktop builds are versioned independently and start at `1.0.0`.

## Features

- **200+ built-in online sources** across many languages, with a searchable
  source catalog, language filters and pinned sources
- **Search everything at once** — one query across all sources, by title or
  genre; when a source is missing a title, **Alternatives** finds it elsewhere
  and carries your progress over
- **Desktop layout** — History, Favorites, Suggestions, Explore and an Updates
  feed, with a wide-window layout that makes room for covers and details
- **Continue Reading** — resume your latest chapter exactly where you left off
- **Full-featured reader** — paged, right-to-left, vertical and Webtoon modes,
  e-ink mode, zoom/crop/gap controls, plus mouse-wheel, arrow-key and on-screen
  paging
- **Offline downloads** — download chapters and read them with no connection,
  or open your own CBZ/ZIP archives
- **Library and history tools** — favorites, filters, sorting, date-grouped
  lists and progress rings
- **Backups** — export and restore your library and history, including
  Tachiyomi/Kotatsu backup import
- **Reading statistics** — chapters read, time spent and per-manga progress
- **Built-in Cloudflare handling** — solves the challenge inside the app, so
  protected sources keep working
- **Remembers your window** — size, position and maximised state are restored
  on the next launch

## Download

[![Latest release](https://img.shields.io/github/v/release/Hlomatsimaxwell/Yomou-Desktop?label=release&color=blue)](https://github.com/Hlomatsimaxwell/Yomou-Desktop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Hlomatsimaxwell/Yomou-Desktop/total?label=downloads&color=brightgreen)](https://github.com/Hlomatsimaxwell/Yomou-Desktop/releases)

Linux packages are attached to the
[latest release](https://github.com/Hlomatsimaxwell/Yomou-Desktop/releases/latest).

| Format | File | Install |
| --- | --- | --- |
| AppImage | `Yomou-<version>-linux-x86_64.AppImage` | `chmod +x` the file, then run it |
| Debian/Ubuntu | `yomou_<version>_amd64.deb` | `sudo apt install ./yomou_<version>_amd64.deb` |
| Fedora/RHEL/openSUSE | `yomou-<version>-1.x86_64.rpm` | `sudo dnf install ./yomou-<version>-1.x86_64.rpm` |
| Portable tarball | `yomou-<version>-linux-x64.tar.gz` | extract, then run `Yomou-<version>/manga_reader` |

All builds target `x86_64` Linux and require GTK 3.

## Build from source

Install the Flutter SDK (stable channel) and the Linux desktop toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

Then build and run:

```bash
flutter pub get
flutter build linux --release
./build/linux/x64/release/bundle/manga_reader
```

### Package it

```bash
./linux/package.sh all
```

This writes the four formats above into `dist/`. The individual targets are
`tarball`, `deb`, `rpm`, `appimage` and `all`. `VERSION` can be overridden, for
example `VERSION=1.0.1 ./linux/package.sh all`.

To install the built bundle for the current user instead:

```bash
./linux/install.sh
```

That copies the app to `~/.local/share/com.stunna.manga_reader`, links the
binary into `~/.local/bin` and registers a launcher entry, so Yomou shows up in
the application menu.

## Contributing

Issues and pull requests are welcome. If you are adding or fixing a source,
include the URL you tested it against — sources drift, and a reproducible page
is what makes a fix checkable.

Before sending a pull request, run the checks the project uses:

```bash
flutter analyze
flutter test
```

## Disclaimer

Yomou is a reader, not a content provider. The developers have no affiliation
with any of the content available through the app and do not store or
distribute any of it; everything the app can reach is already publicly available
on the internet. Any takedown request should go to the site that hosts the
material.

The app is meant for personal use. Please support the official releases of the
works you read.

## Acknowledgments

- [Kotatsu](https://github.com/KotatsuApp/Kotatsu) and
  [Kotatsu-Redo](https://github.com/Kotatsu-Redo/Kotatsu-Redo) — the design this
  app follows and the origin of parts of its parser and backup code, which are
  licensed under GPLv3 and remain so
- [Flutter](https://flutter.dev) and the packages in `pubspec.yaml`
- Icons: [Material Design Icons](https://materialdesignicons.com/)
  (Pictogrammers), plus glyphs ported from Kotatsu-Redo

## License

Apache License 2.0 — see [LICENSE](LICENSE).
