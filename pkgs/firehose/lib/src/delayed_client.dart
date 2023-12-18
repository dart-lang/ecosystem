// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DelayedClient implements http.Client {
  final http.Client _client;
  final Duration duration;

  factory DelayedClient(Duration duration) => DelayedClient._(
        client: http.Client(),
        duration: duration,
      );

  DelayedClient._({required this.duration, required http.Client client})
      : _client = client;

  @override
  void close() => _client.close();

  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          duration,
          () => _client.delete(url,
              body: body, encoding: encoding, headers: headers));

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(duration, () => _client.get(url, headers: headers));

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(duration, () => _client.head(url, headers: headers));

  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          duration,
          () => _client.patch(url,
              headers: headers, body: body, encoding: encoding));

  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          duration,
          () => _client.post(url,
              headers: headers, body: body, encoding: encoding));
  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.delayed(
          duration,
          () => _client.put(url,
              headers: headers, body: body, encoding: encoding));
  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(duration, () => _client.read(url, headers: headers));

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      Future.delayed(duration, () => _client.readBytes(url, headers: headers));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.delayed(duration, () => _client.send(request));
}
