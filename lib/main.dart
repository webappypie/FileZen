import 'package:flutter/material.dart';
import 'app/bootstrap/app_bootstrap.dart';

void main() async {
  final app = await AppBootstrap.createRootWidget();
  runApp(app);
}
