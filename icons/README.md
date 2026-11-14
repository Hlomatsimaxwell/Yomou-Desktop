# App icon sources

One folder per launcher-icon variant, exported from
[Icon Kitchen](https://icon.kitchen/) in the default layout:

```
icons/<variant>/
  AppIcon16.png … AppIcon1024.png
  AppIcon.icns
```

The app discovers variants from `assets/app_icons/variant_<id>.png`, which are
generated from these sources:

```bash
./tool/sync_app_icons.sh
```

After that, the new icon shows up in **Settings → Appearance → App Icon** with
no Dart changes. The file name becomes the label, so `moon_gold` reads as
“Moon Gold”.
