import 'package:flutter/material.dart';

const accent = Color(0xFFDA5835);
const canvas = Color(0xFFFAF8F4);
const ink = Color(0xFF25364B);
const muted = Color(0xFF667080);
const line = Color(0xFFE7E5DF);
const peach = Color(0xFFFFE9DE);
const blue = Color(0xFF355C9A);
const mist = Color(0xFFEEF2F8);

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .27),
    child: Image.asset(
      'assets/branding/ngsl_mark.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}
