import 'package:flutter_test/flutter_test.dart';
import 'package:yomou/core/image_referer.dart';
import 'package:yomou/data/providers/sources_provider.dart';
import 'package:yomou/data/sources/catalog/manga_themesia_catalog.g.dart';
import 'package:yomou/data/sources/manga_themesia_source.dart';

void main() {
  test('bundled MangaThemesia catalog is present and unique', () {
    expect(catalogMangaThemesiaConfigs.length, 114);

    final ids = catalogMangaThemesiaConfigs.map((c) => c.id).toSet();
    expect(ids.length, catalogMangaThemesiaConfigs.length);

    final names = catalogMangaThemesiaConfigs.map((c) => c.name).toSet();
    expect(names.length, catalogMangaThemesiaConfigs.length);

    expect(catalogMangaThemesiaSourceRows.length, 114);
  });

  test('registry resolves a MangaThemesia site by name and by id', () {
    final first = catalogMangaThemesiaConfigs.first;

    final byName = getSourceByName(first.name);
    expect(byName, isA<MangaThemesiaSource>());
    expect(byName.id, first.id);

    final byId = getSourceBySourceId(first.id);
    expect(byId, isA<MangaThemesiaSource>());
    expect(byId!.id, first.id);
    expect(byId.baseUrl, first.baseUrl);
  });

  test('every catalog site is exposed in the default source rows', () {
    final rowNames = SourcesNotifier.defaultSources
        .map((row) => row['name'])
        .toSet();
    for (final config in catalogMangaThemesiaConfigs) {
      expect(rowNames, contains(config.name));
    }
  });

  test('Sushi-Scan image hosts send the site referer', () {
    expect(
      ImageReferer.refererFor(
        Uri.parse('https://c5.sushiscan.net/uploads/1/2/3.jpg'),
      ),
      'https://sushiscan.net/',
    );
  });
}
