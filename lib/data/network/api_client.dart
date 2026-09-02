import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

/// Client HTTP unique. Gère :
/// * le User-Agent mobile ;
/// * le cookie de session PHP (nécessaire pour /api/* après connexion),
///   persisté sur disque pour rester connecté entre deux lancements ;
/// * le domaine configurable (miroirs).
class ApiClient {
  ApiClient._(this._dio, this._jar);

  final Dio _dio;
  final PersistCookieJar _jar;

  Dio get dio => _dio;

  String get baseUrl => _dio.options.baseUrl;
  set baseUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.startsWith('http')) u = 'https://$u';
    _dio.options.baseUrl = u;
  }

  static Future<ApiClient> create({String? baseUrl}) async {
    final dir = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage('${dir.path}/cookies'),
    );
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.defaultBaseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.plain,
        headers: {
          HttpHeaders.userAgentHeader: AppConstants.userAgent,
          HttpHeaders.acceptLanguageHeader: 'fr-FR,fr;q=0.9,en;q=0.8',
          HttpHeaders.acceptHeader:
              'text/html,application/xhtml+xml,application/json,*/*;q=0.8',
        },
        // On gère nous-mêmes les 404 (pages de langue inexistantes).
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    dio.interceptors.add(CookieManager(jar));
    return ApiClient._(dio, jar);
  }

  /// GET texte (HTML / JS / JSON brut).
  Future<Response<String>> getText(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
  }) {
    return _dio.get<String>(path, queryParameters: query, options: options);
  }

  /// GET avec query multi-valeurs (`type[]=Anime&type[]=Scans`).
  /// Dio n'encode pas les clés `[]` comme PHP les attend, on construit donc
  /// la query string à la main.
  Future<Response<String>> getWithMultiQuery(
    String path,
    Map<String, List<String>> query,
  ) {
    final parts = <String>[];
    query.forEach((k, values) {
      for (final v in values) {
        parts.add(
          '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}',
        );
      }
    });
    final url = parts.isEmpty ? path : '$path?${parts.join('&')}';
    return _dio.get<String>(url);
  }

  /// POST formulaire (x-www-form-urlencoded) – utilisé par la recherche.
  Future<Response<String>> postForm(String path, Map<String, dynamic> data) {
    return _dio.post<String>(
      path,
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// POST JSON – utilisé par /api/*.
  Future<Response<String>> postJson(String path, Object body) {
    return _dio.post<String>(
      path,
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  /// HEAD/GET rapide pour tester l'existence d'une page.
  Future<int> statusOf(String path) async {
    try {
      final r = await _dio.get<String>(
        path,
        options: Options(receiveTimeout: const Duration(seconds: 12)),
      );
      return r.statusCode ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCookies() => _jar.deleteAll();

  /// Résout un chemin relatif ou absolu vers une URL complète.
  String absolute(String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    if (!pathOrUrl.startsWith('/')) return '$baseUrl/$pathOrUrl';
    return '$baseUrl$pathOrUrl';
  }
}
