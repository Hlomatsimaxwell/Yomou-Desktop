import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomou/core/app_icon/app_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux icon picker lists the bundled variants', () async {
    final options = await AppIconService.options();
    final ids = options.map((option) => option.id).toList();

    expect(
      ids,
      containsAll(<String>['gold', 'blue', 'white', 'bw']),
    );
    expect(ids, isNot(contains('dark')));
    expect(ids, isNot(contains('light')));
    expect(ids.first, 'gold');
    expect(
      options.firstWhere((option) => option.id == 'bw').label,
      'B&W',
    );
    for (final option in options) {
      expect(option.asset, startsWith('assets/app_icons/variant_'));
      expect(option.label, isNotEmpty);
    }
  });

  test('gold is the default before the user picks an icon', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AppIconService.current(), 'gold');
  });
}
