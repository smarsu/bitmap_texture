import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:storages/storages.dart';

class BitMapNaive {
  static const MethodChannel _channel = const MethodChannel('bitmap');

  /// Dispose all free textures.
  ///
  /// You should call this function every time you quit the album. And if not,
  /// the textures will always stored in the memory. And don't be worry, the
  /// memory usage will not be too much.
  ///
  /// Note that some texture will be kept as the are under build. This function
  /// will only dispose the textures which are free and in the [textureIdPool].
  static Future dispose() async {
    stop = true;

    for (var key in textureIdPool.keys) {
      var textureIds = textureIdPool[key].sublist(0); // deepcopy.
      textureIdPool[key] = [];
      _ntextures -= textureIds.length;
      for (int idx = 0; idx < textureIds.length; ++idx) {
        if (!stop) {
          for (var id in textureIds.sublist(idx)) {
            putTextureId(id, key.width, key.height);
          }
          break;
        }

        await _channel.invokeMethod('dl', {
          'textureIds': [textureIds[idx]],
        });
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }

  /// More texture needed.
  ///
  /// Every time call the [initState] of [BitMap], count it up.
  static void up() {
    ++_nexist;
    _ntop = max(_ntop, _nexist);
  }

  /// Less texture needed.
  ///
  /// Every time call the [dispose] of [BitMap], count it down.
  static void down() {
    --_nexist;
    _ntop = max(_ntop, _nexist);
  }

  /// Add [textureId] to the [textureIdPool].
  ///
  /// Every [textureId] have a specially [width] and [height].
  ///
  /// [textureId] should always >= 0.
  static void putTextureId(int textureId, double width, double height) {
    if (textureId == null) {
      return;
    }

    Size key = Size(width, height); // [Size] can be key but [List] can not.
    var textureIds = textureIdPool[key];
    if (textureIds == null) {
      textureIdPool[key] = [textureId];
    } else {
      textureIdPool[key].add(textureId);
    }
  }

  static Future<void> create(int n, double width, double height) async {
    for (int i = 0; i < n; ++i) {
      ++_ntextures;
      int id = await _channel.invokeMethod('i', {
        'width': width,
        'height': height,
      });
      print('Init: textureId: $id, width: $width, height ... $height');
      putTextureId(id, width, height);
    }
  }

  /// Render the image on the interface.
  ///
  /// This function will make cache of textureId and make cache of bitmap.
  static Future<int> render(
      String path, double width, double height, BoxFit fit) async {
    stop = false;  // interp dispose
    await initialize;

    int textureId = _tryToGetTextureId(width, height);
    print('textureId: $textureId, width: $width, height ... $height');

    if (textureId == -1) {
      if (_ntextures >= _ntop) {
        return null;
      }
    }

    if (textureId == -1) {
      // It means the invoke of 'r' will create new texture.
      ++_ntextures;
    }

    // bool findId = textureId != -1;

    List cache = await _tryToFindBitMapCache(path, width, height, fit);
    bool findCache = cache[0];
    String value = cache[1];
    int srcWidth = cache[3];
    int srcHeight = cache[4];

    // For some case, there is no need to transfer so many params.
    int invokedTextureId = await _channel.invokeMethod('r', {
      'textureId': textureId,
      'path': path, // Not used in the method channel.
      'width': width,
      'height': height,
      'srcWidth': srcWidth,
      'srcHeight': srcHeight,
      'fit': _fitToIndex(fit),
      'bitmap': value, // value is the path of bitmap.
      'findCache': findCache,
    });

    // if (!findId) {
    //   // It means the invoke of 'r' will create new texture.
    //   ++_ntextures;
    // }

    await _storeCache(cache);

    return invokedTextureId;
  }

  /// Internal initialization interface.
  static Future<void> _init() async {}

  /// Returns the free [textureId] or null if there are no free [textureId].
  ///
  /// If the [textureId] is in [textureIdPool], then it is free [textureId]. And this
  /// function will remove the correspond [textureId] from [textureIdPool].
  ///
  /// Note to call [putTextureId] after finish use this [textureId].
  ///
  /// The true [textureId] is always >= 0.
  static int _tryToGetTextureId(double width, double height) {
    Size key = Size(width, height);
    var textureIds = textureIdPool[key];
    if (textureIds == null) {
      return -1;
    } else if (textureIds.isEmpty) {
      return -1;
    } else {
      return textureIds.removeLast();
    }
  }

  /// An extention of [ui.instantiateImageCodec].
  ///
  /// This function decode and resize the image to a suitable size.
  ///
  /// This function will keep the aspect ratio of image.
  static Future<ui.Codec> _instantiateImageCodecEx(
    Uint8List list, {
    int targetWidth,
    int targetHeight,
    bool allowUpscaling = true,
  }) async {
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(list);
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(buffer);
    if (!allowUpscaling) {
      if (targetWidth != null && targetWidth > descriptor.width) {
        targetWidth = descriptor.width;
      }
      if (targetHeight != null && targetHeight > descriptor.height) {
        targetHeight = descriptor.height;
      }
    }
    if (targetWidth / descriptor.width > targetHeight / descriptor.height) {
      targetHeight = null;
    } else {
      targetWidth = null;
    }
    return descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  }

  /// Try to find the cache path of bitmap.
  ///
  /// This use [FixSizedStorage] for safe cache.
  static Future<List> _tryToFindBitMapCache(
      String path, double width, double height, BoxFit fit) async {
    await _fixSizedStorage.init();

    String key = _toKey(path, width, height, fit);
    String value = await _fixSizedStorage.get(key);

    bool findCache = value == null ? false : true;
    int srcWidth = 0;
    int srcHeight = 0;
    if (!findCache) {
      value = await _fixSizedStorage.touch(key);

      ui.Codec codec = await _instantiateImageCodecEx(
          await File(path).readAsBytes(),
          targetWidth: width.toInt(),
          targetHeight: height.toInt(),
          allowUpscaling: true);
      ui.FrameInfo frameInfo = await codec.getNextFrame();
      ui.Image image = frameInfo.image;
      Uint8List colors = (await image.toByteData()).buffer.asUint8List();
      File(value).writeAsBytesSync(colors);

      srcWidth = image.width;
      srcHeight = image.height;
    }

    return [findCache, value, key, srcWidth, srcHeight];
  }

  /// Store the bitmap cache.
  ///
  /// After call [render], you need to store the bitmap cache.
  static Future<void> _storeCache(List cache) async {
    await _fixSizedStorage.init();

    bool findCache = cache[0];
    String value = cache[1];
    String key = cache[2];

    if (!findCache) {
      await _fixSizedStorage.set(key, value);
    }
  }

  /// Line [path], [width], [height] and [fit] to [key].
  ///
  /// This key is for [FixSizedStorage].
  ///
  /// Note that the root of [path] will be mutable of every version of app.
  static String _toKey(String path, double width, double height, BoxFit fit) {
    path = path.split('/').last;
    return '${path}_${width}_${height}_$fit';
  }

  /// Convert [BoxFit] to [int].
  ///
  /// Convert [BoxFit] to [int] so it can be transfer to naive code.
  static int _fitToIndex(BoxFit fit) {
    switch (fit) {
      case BoxFit.fill:
        return 0;

      case BoxFit.contain:
        return 1;

      case BoxFit.cover:
        return 2;

      case BoxFit.fitWidth:
        return 3;

      case BoxFit.fitHeight:
        return 4;

      case BoxFit.none:
        return 5;

      case BoxFit.scaleDown:
        return 6;

      default:
        return -1;
    }
  }

  /// An instance of [FixSizedStorage].
  ///
  /// This make it safe to save bitmap.
  static FixSizedStorage _fixSizedStorage =
      FixSizedStorage.fromId('__BitMap__', capacity: 5 * 1024 * 1024 * 1024);

  /// A pool of textureIds.
  ///
  /// [Size] is hashable, [List] is un-hashable.
  ///
  /// Todo: Consider use linked list for faster to pop and put.
  static Map<Size, List<int>> textureIdPool = {};

  /// Exposed initialization variable.
  ///
  /// You can call it frequently, but in fact it will only be executed once.
  static Future<void> initialize = _init();

  /// The current exist number of [BitMap] widget.
  ///
  /// It means the number of textures are under used.
  static int _nexist = 0;

  /// The top number of [BitMap] widget exist at one time.
  ///
  /// It means the number of textures may been showed at one time.
  static int _ntop = 0;

  /// The total number of textures have been created now.
  ///
  /// It should be less equal to [_ntop] and used to keep the suitable number
  /// of textures.
  static int _ntextures = 0;

  static bool stop = false;
}

/// Create a [BitMap] widget.
///
/// Note if you hot reload without [BitMapNaive.dispose], the textures will not
/// be recycled and some bad images will show out.
class BitMap extends StatefulWidget {
  BitMap({
    this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  /// The path of image.
  final String path;

  /// The width to show the image.
  final double width;

  /// The height to show the image.
  final double height;

  /// How to inscribe the image into the space allocated during layout.
  ///
  /// The default varies based on the other fields. See the discussion at
  /// [paintImage].
  ///
  /// Note only support [BoxFit.conver] now.
  final BoxFit fit;

  @override
  BitMapNaiveState createState() => BitMapNaiveState();
}

class BitMapNaiveState extends State<BitMap> {
  int _textureId;

  /// [nowait] means if this widget need to wait for texture from [BitMapNaive].
  ///
  /// If [true], no need to wait texture, and just use [Texture] widget to show
  /// image; or if [false], use [Image.file] to show the image until there are f
  /// ree textures.
  bool nowait = true;

  @override
  void initState() {
    super.initState();
    BitMapNaive.up();
    run();
  }

  @override
  void dispose() {
    BitMapNaive.down();
    put();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BitMap oldWidget) {
    // No need to update widget in some case.
    if (widget.path != oldWidget.path ||
        widget.width != oldWidget.width ||
        widget.height != oldWidget.height ||
        widget.fit != oldWidget.fit) {
      put();
      run();
    }
    super.didUpdateWidget(oldWidget);
  }

  void run() {
    BitMapNaive.render(widget.path, widget.width, widget.height, widget.fit)
        .then((value) {
      // value is invoked textureId.
      put(); // put the old textureId if have.
      _textureId = value;
      if (_textureId == null) {
        nowait = false;
        print('BitMap [nowait] ... $nowait');
      }

      if (mounted) {
        setState(() {});
      } else {
        // dispose have been called. you should put back textureId now.
        put();
      }
    });
  }

  void put() {
    BitMapNaive.putTextureId(_textureId, widget.width, widget.height);
    _textureId = null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      child: nowait
          ? _textureId == null
              ? null
              : Texture(
                  textureId: _textureId,
                )
          : Image.file(
              File(widget.path),
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
            ),
    );
  }
}
