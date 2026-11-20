// Host test: runs under plain `flutter test`, where Ditto cannot load.
// snippet:start flutter-testing-1
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the cars screen needs. The app's repository implements it with
/// Ditto; widget and unit tests use [FakeCars].
abstract interface class CarsSource {
  ValueListenable<List<Map<String, dynamic>>> get cars;
}

class FakeCars implements CarsSource {
  @override
  final ValueNotifier<List<Map<String, dynamic>>> cars = ValueNotifier(
    const [],
  );
}

class CarCount extends StatelessWidget {
  const CarCount({super.key, required this.source});

  final CarsSource source;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: source.cars,
    builder: (context, cars, _) => Text('${cars.length} cars'),
  );
}

void main() {
  testWidgets('shows the number of cars', (tester) async {
    final source = FakeCars();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CarCount(source: source),
      ),
    );
    expect(find.text('0 cars'), findsOneWidget);

    source.cars.value = [
      {'_id': 'car-1'},
    ];
    await tester.pump();
    expect(find.text('1 cars'), findsOneWidget);
  });
}
// snippet:end flutter-testing-1
