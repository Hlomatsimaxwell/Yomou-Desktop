import 'package:flutter_test/flutter_test.dart';
import 'package:yomou/core/app_icon/app_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux icon picker lists the bundled variants', () async {
    final options = await AppIconService.options();
    final ids = options.map((option) => option.id).toList();

    expect(ids, containsAll(<String>['dark', 'light', 'gold', 'blue']));
    for (final option in options) {
      expect(option.asset, startsWith('assets/app_icons/variant_'));
      expect(option.label, isNotEmpty);
    }
  });
}
