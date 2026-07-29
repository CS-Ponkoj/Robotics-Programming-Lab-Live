import 'progress_storage_base.dart';
import 'progress_storage_stub.dart'
    if (dart.library.io) 'progress_storage_native.dart'
    if (dart.library.js_interop) 'progress_storage_web.dart' as platform;

ProgressStorage createProgressStorage() =>
    platform.createPlatformProgressStorage();
