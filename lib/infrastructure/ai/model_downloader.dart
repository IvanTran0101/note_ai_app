/// Public model downloader entrypoint.
///
/// Native targets use an HTTPS-only `dart:io` implementation. Web exposes the
/// same factory and contract surface but reports that local model downloads
/// are unsupported; Web can later use a separate remote inference path.
library;

export 'model_provisioning_contract.dart' show IModelDownloader;

export 'model_downloader_stub.dart'
    if (dart.library.io) 'model_downloader_io.dart';
