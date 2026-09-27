import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/core/theme/typography.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('ReaderSettings Model', () {
    test('default values are literary serif Literata and continuous mode', () {
      const settings = ReaderSettings();
      expect(settings.fontFamily, AppTypography.readerSerif);
      expect(settings.fontSize, 18.0);
      expect(settings.lineHeight, 1.6);
      expect(settings.contentMaxWidth, 680.0);
      expect(settings.horizontalPadding, 24.0);
      expect(settings.mode, ReadingMode.continuous);
      expect(settings.isPaginated, isFalse);
    });

    test('toSettingsMap and fromSettingsMap roundtrip correctly', () {
      const original = ReaderSettings(
        fontFamily: AppTypography.readerSans,
        fontSize: 22.0,
        lineHeight: 1.8,
        contentMaxWidth: 720.0,
        horizontalPadding: 32.0,
        mode: ReadingMode.paginated,
      );

      final map = original.toSettingsMap();
      final restored = ReaderSettings.fromSettingsMap(map);

      expect(restored.fontFamily, AppTypography.readerSans);
      expect(restored.fontSize, 22.0);
      expect(restored.lineHeight, 1.8);
      expect(restored.contentMaxWidth, 720.0);
      expect(restored.horizontalPadding, 32.0);
      expect(restored.mode, ReadingMode.paginated);
      expect(restored.isPaginated, isTrue);
    });
  });

  group('ReaderSettingsNotifier Provider', () {
    test('updates state and persists to database', () async {
      final notifier = container.read(readerSettingsProvider.notifier);

      await notifier.setFontFamily(AppTypography.readerHighDistinction);
      await notifier.setFontSize(24.0);
      await notifier.setLineHeight(2.0);
      await notifier.setContentMaxWidth(800.0);
      await notifier.setReadingMode(ReadingMode.paginated);

      final current = container.read(readerSettingsProvider);
      expect(current.fontFamily, AppTypography.readerHighDistinction);
      expect(current.fontSize, 24.0);
      expect(current.lineHeight, 2.0);
      expect(current.contentMaxWidth, 800.0);
      expect(current.mode, ReadingMode.paginated);

      // Verify persistence in SQLite database
      final savedFamily = await db.getSetting('reader_font_family');
      final savedSize = await db.getSetting('reader_font_size');
      final savedMode = await db.getSetting('reader_mode');

      expect(savedFamily, AppTypography.readerHighDistinction);
      expect(savedSize, '24.0');
      expect(savedMode, 'paginated');
    });
  });
}
