import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import '../storage/token_storage_service.dart';

/// A friendly error thrown by [ApiClient] whenever a request fails.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.errors});

  /// A human-readable message safe to show to the user.
  final String message;

  /// The HTTP status code, if the server responded at all.
  final int? statusCode;

  /// Laravel validation errors, keyed by field name, if this was a
  /// 422 validation failure.
  final Map<String, List<String>>? errors;

  @override
  String toString() => message;
}

/// Wraps [Dio] and centralizes how the app talks to the Laravel backend.
class ApiClient {
  ApiClient({required this.tokenStorageService}) : dio = Dio(_baseOptions) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorageService.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorageService tokenStorageService;

  static final BaseOptions _baseOptions = BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    headers: const {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  );

  /// Pulls the `data` field out of a Laravel `{success, message, data}`
  /// response. Falls back to the raw body if it isn't in that shape.
  dynamic parseData(Response response) {
    final body = response.data;
    if (body is Map && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }

  /// Converts a low-level [DioException] into a friendly [ApiException],
  /// understanding both known Laravel error shapes:
  /// - `{success, message, data}` for most errors.
  /// - `{message, errors}` for validation failures (HTTP 422).
  ApiException handleError(DioException error) {
    final response = error.response;
    final rawBody = response?.data;
    final body = rawBody is Map ? Map<String, dynamic>.from(rawBody) : null;

    if (body != null) {
      final rawErrors = body['errors'];
      if (rawErrors is Map) {
        final errors = <String, List<String>>{};
        rawErrors.forEach((field, messages) {
          if (messages is List) {
            errors[field.toString()] = messages
                .map((message) => message.toString())
                .toList();
          }
        });
        return ApiException(
          (body['message'] as String?) ?? 'The given data was invalid.',
          statusCode: response?.statusCode,
          errors: errors,
        );
      }

      final message = body['message'];
      if (message is String) {
        return ApiException(message, statusCode: response?.statusCode);
      }
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('The connection timed out. Please try again.');
      case DioExceptionType.connectionError:
        return ApiException('No internet connection.');
      case DioExceptionType.badResponse:
        return ApiException(
          'Server error (${response?.statusCode}). Please try again.',
          statusCode: response?.statusCode,
        );
      default:
        return ApiException('Something went wrong. Please try again.');
    }
  }
}
