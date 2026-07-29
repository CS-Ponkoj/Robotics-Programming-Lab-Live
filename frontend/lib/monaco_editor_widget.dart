import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui_web' as ui;
import 'package:iuse_demo/api_config.dart';

class MonacoEditorWidget extends StatefulWidget {
  const MonacoEditorWidget({super.key, required this.id, this.content = ''});
  final int id;
  final String content;

  @override
  State<MonacoEditorWidget> createState() => _MonacoEditorWidgetState();
}

class _MonacoEditorWidgetState extends State<MonacoEditorWidget> {
  late StreamSubscription<web.MessageEvent> _messageSubscription;

  @override
  void initState() {
    super.initState();

    _messageSubscription = web.window.onMessage.listen((event) {
      print(event.data);
    });
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //iFrame
    const String iframeId = 'monaco-editor-container';

    //create iframe element
    final web.HTMLIFrameElement iframeElement = web.HTMLIFrameElement()
      ..src = Uri(
        path: 'monaco_editor.html',
        queryParameters: {
          'id': widget.id.toString(),
          'apiBase': apiBaseUrl,
        },
      ).toString()
      ..style.border = 'none';

    //register iframe
    //ignore:undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      iframeId,
      (int viewId) => iframeElement,
    );

    return Expanded(child: HtmlElementView(viewType: iframeId));
  }
}
