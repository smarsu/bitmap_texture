import 'package:bitmap_texture/bitmap_texture.dart';
import 'package:bitmap_texture_example/album.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Album(),
        // body: BitMap(
        //   path: "1",
        //   width: 200,
        //   height: 200,
        // ),
      ),
    );
  }
}
