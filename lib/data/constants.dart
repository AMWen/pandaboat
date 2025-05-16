import 'package:flutter/material.dart';

Color primaryColor = Color.fromARGB(255, 3, 78, 140);
Color secondaryColor = Colors.grey[200]!;
Color dullColor = Colors.grey[500]!;

class TextStyles {
  static TextStyle mediumText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static TextStyle normalText = TextStyle(fontSize: 16);
  static TextStyle largeMediumText = TextStyle(fontSize: 40, fontWeight: FontWeight.w600);
  static TextStyle titleText = TextStyle(fontSize: 20, fontWeight: FontWeight.w500);
  static TextStyle labelText = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
  static TextStyle buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: secondaryColor);
  static const TextStyle dialogTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
}
