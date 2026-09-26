import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const String readerSerif = 'Literata';
  static const String readerSans = 'Inter';
  static const String readerHighDistinction = 'AtkinsonHyperlegible';

  static const largeTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const headline = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const sectionHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );

  static const micro = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
}
