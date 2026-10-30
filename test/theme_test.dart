import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/common.dart';

void main() {
  test('a chamfered palette cuts corners on chips, cards and buttons', () {
    final p = cyberpunkTheme.palette;
    expect(p.pillShape, isA<ChamferedBorder>());
    expect(p.buttonShape, isA<ChamferedBorder>());
    final card = p.boxShape(12) as ChamferedBorder;
    expect(card.notch, p.accent);
    expect(p.radius(12), BorderRadius.zero);
    expect(dummifyTheme.palette.pillShape, isA<StadiumBorder>());
  });

  test('ChamferedBorder leaves out the cut corners', () {
    const border = ChamferedBorder(cut: 10);
    final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 100, 50));
    expect(path.contains(const Offset(1, 1)), isFalse);
    expect(path.contains(const Offset(99, 49)), isFalse);
    expect(path.contains(const Offset(99, 1)), isTrue);
    expect(path.contains(const Offset(50, 25)), isTrue);
  });

  testWidgets('Cyberpunk headings are capitals and fit a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(cyberpunkTheme),
        home: Scaffold(
          body: Column(
            children: [
              const TabHeader(title: 'Biblioteka'),
              const SectionTitle(
                'Ostatnio słuchane i bardzo długi nagłówek sekcji',
              ),
              SectionTitle(
                'Przypięte',
                icon: Icons.push_pin,
                trailing: const Icon(Icons.more_horiz),
              ),
              Card(
                shape: cyberpunkTheme.palette.boxShape(12),
                child: const SizedBox(height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('BIBLIOTEKA'), findsOneWidget);
    expect(find.text('PRZYPIĘTE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
