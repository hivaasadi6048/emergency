import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal in-process HTTP stub for repository/client tests — a REAL local
/// server (dart:io), so the client code under test exercises genuine sockets.
class FakeBackend {
  final Map<String, Route> routes = {};
  final List<String> seenAuthorization = [];
  final List<String?> seenIdempotencyKeys = [];
  HttpServer? _server;
  late String baseUrl;

  Future<void> start() async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    baseUrl = 'http://127.0.0.1:${_server!.port}';
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  void on(String method, String path, RouteHandler handler) {
    routes['$method $path'] = Route(handler);
  }

  Future<void> _handle(HttpRequest req) async {
    seenAuthorization.add(req.headers.value(HttpHeaders.authorizationHeader) ?? '');
    seenIdempotencyKeys.add(req.headers.value('Idempotency-Key'));
    final route = routes['${req.method} ${req.uri.path}'];
    if (route == null) {
      req.response.statusCode = 404;
      req.response.write(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'no route'}}));
      await req.response.close();
      return;
    }
    final body = await utf8.decoder.bind(req).join();
    final payload = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
    final result = await route.handler(FakeRequest(req, payload));
    req.response.statusCode = result.$1;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(result.$2));
    await req.response.close();
  }
}

class Route {
  final RouteHandler handler;
  Route(this.handler);
}

class FakeRequest {
  final HttpRequest raw;
  final Map<String, dynamic> body;
  FakeRequest(this.raw, this.body);
}

typedef RouteHandler = Future<(int, Object)> Function(FakeRequest req);
