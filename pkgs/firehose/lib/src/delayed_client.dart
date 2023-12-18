import 'dart:convert';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DelayedClient implements http.Client {
  final http.Client _client;

  factory DelayedClient() => DelayedClient._(client: http.Client());

  DelayedClient._({required http.Client client}) : _client = client;

  @override
  void close() => _client.close();

  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          const Duration(seconds: 1),
          () => _client.delete(url,
              body: body, encoding: encoding, headers: headers));

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(
          const Duration(seconds: 1), () => _client.get(url, headers: headers));

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(const Duration(seconds: 1),
          () => _client.head(url, headers: headers));

  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          const Duration(seconds: 1),
          () => _client.patch(url,
              headers: headers, body: body, encoding: encoding));

  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          const Duration(seconds: 1),
          () => _client.post(url,
              headers: headers, body: body, encoding: encoding));
  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          const Duration(seconds: 1),
          () => _client.put(url,
              headers: headers, body: body, encoding: encoding));
  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(const Duration(seconds: 1),
          () => _client.read(url, headers: headers));

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(const Duration(seconds: 1),
          () => _client.readBytes(url, headers: headers));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.delayed(const Duration(seconds: 1), () => _client.send(request));
}
