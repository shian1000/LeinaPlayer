import 'package:flutter/material.dart';

void main() {
  runApp(const MusicDatabaseApp());
}

class MusicDatabaseApp extends StatelessWidget {
  const MusicDatabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicDatabase',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const Scaffold(
        body: Center(child: Text('Hello World')),
      ),
    );
  }
}
