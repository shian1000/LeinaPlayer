import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Java exceptions (by class name, as the NewPipe bridge reports them) that mean no connection.
const _javaNetworkErrors = {
  'UnknownHostException',
  'SocketTimeoutException',
  'ConnectException',
  'NoRouteToHostException',
  'SocketException',
  'InterruptedIOException',
};

/// Whether [error] means the phone couldn't reach the network (no internet, or Android cutting
/// the app off in the background) rather than YouTube refusing a video.
bool isNetworkError(Object error) => switch (error) {
  SocketException() || TimeoutException() || HandshakeException() => true,
  HttpException() => true,
  PlatformException(:final code) => _javaNetworkErrors.contains(code),
  // youtube_explode wraps network errors in package:http's ClientException.
  _ =>
    '$error'.contains('SocketException') ||
        '$error'.contains('Failed host lookup'),
};
