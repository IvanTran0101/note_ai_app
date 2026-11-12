export 'attachment_media_bridge_stub.dart'
    if (dart.library.io) 'attachment_media_bridge_io.dart'
    if (dart.library.js_interop) 'attachment_media_bridge_web.dart';
