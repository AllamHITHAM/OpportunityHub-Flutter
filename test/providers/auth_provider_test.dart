// Direct unit tests for AuthProvider, using a fake repository (no real
// network). Mirrors the fake-repository-extends-real conventions used
// throughout this app's other provider tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';

UserModel _user({bool emailVerified = false}) {
  return UserModel(
    id: 1,
    name: 'Jane Doe',
    email: 'jane@example.com',
    role: 'student',
    status: 'active',
    emailVerified: emailVerified,
  );
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  String? savedToken;

  UserModel? loginResult;
  ApiException? loginError;

  UserModel? currentUserResult;
  ApiException? currentUserError;

  ApiException? forgotPasswordError;
  Duration forgotPasswordDelay = Duration.zero;
  int forgotPasswordCallCount = 0;

  ApiException? resetPasswordError;
  Duration resetPasswordDelay = Duration.zero;
  int resetPasswordCallCount = 0;

  ApiException? resendVerificationError;
  Duration resendVerificationDelay = Duration.zero;
  int resendVerificationCallCount = 0;

  int logoutCallCount = 0;

  @override
  Future<String?> getSavedToken() async => savedToken;

  @override
  Future<UserModel> login(String email, String password) async {
    if (loginError != null) throw loginError!;
    return loginResult ?? _user();
  }

  @override
  Future<UserModel> getCurrentUser() async {
    if (currentUserError != null) throw currentUserError!;
    return currentUserResult ?? _user();
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }

  @override
  Future<void> forgotPassword(String email) async {
    forgotPasswordCallCount++;
    if (forgotPasswordDelay > Duration.zero) {
      await Future<void>.delayed(forgotPasswordDelay);
    }
    if (forgotPasswordError != null) throw forgotPasswordError!;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    resetPasswordCallCount++;
    if (resetPasswordDelay > Duration.zero) {
      await Future<void>.delayed(resetPasswordDelay);
    }
    if (resetPasswordError != null) throw resetPasswordError!;
  }

  @override
  Future<void> resendVerificationEmail() async {
    resendVerificationCallCount++;
    if (resendVerificationDelay > Duration.zero) {
      await Future<void>.delayed(resendVerificationDelay);
    }
    if (resendVerificationError != null) throw resendVerificationError!;
  }
}

void main() {
  group('login', () {
    test('sets user on success', () async {
      final repository = _FakeAuthRepository()..loginResult = _user();
      final provider = AuthProvider(authRepository: repository);

      await provider.login('jane@example.com', 'password123');

      expect(provider.isAuthenticated, isTrue);
      expect(provider.user?.email, 'jane@example.com');
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage and clears user on failure', () async {
      final repository = _FakeAuthRepository()
        ..loginError = ApiException('Invalid credentials', statusCode: 401);
      final provider = AuthProvider(authRepository: repository);

      await provider.login('jane@example.com', 'wrong-password');

      expect(provider.isAuthenticated, isFalse);
      expect(provider.errorMessage, 'Invalid credentials');
    });
  });

  test('logout clears the user', () async {
    final repository = _FakeAuthRepository()..loginResult = _user();
    final provider = AuthProvider(authRepository: repository);
    await provider.login('jane@example.com', 'password123');
    expect(provider.isAuthenticated, isTrue);

    await provider.logout();

    expect(provider.isAuthenticated, isFalse);
    expect(repository.logoutCallCount, 1);
  });

  group('forgotPassword (Phase 8B-2)', () {
    test('sets forgotPasswordSucceeded on success', () async {
      final repository = _FakeAuthRepository();
      final provider = AuthProvider(authRepository: repository);

      await provider.forgotPassword('jane@example.com');

      expect(provider.forgotPasswordSucceeded, isTrue);
      expect(provider.forgotPasswordErrorMessage, isNull);
      expect(provider.isSendingResetLink, isFalse);
    });

    test('sets forgotPasswordErrorMessage on failure, not succeeded', () async {
      final repository = _FakeAuthRepository()
        ..forgotPasswordError = ApiException(
          'Server error, please try again later.',
        );
      final provider = AuthProvider(authRepository: repository);

      await provider.forgotPassword('jane@example.com');

      expect(provider.forgotPasswordSucceeded, isFalse);
      expect(
        provider.forgotPasswordErrorMessage,
        'Server error, please try again later.',
      );
    });

    test('a duplicate submission while one is in flight is ignored', () async {
      final repository = _FakeAuthRepository()
        ..forgotPasswordDelay = const Duration(milliseconds: 50);
      final provider = AuthProvider(authRepository: repository);

      await Future.wait([
        provider.forgotPassword('jane@example.com'),
        provider.forgotPassword('jane@example.com'),
      ]);

      expect(repository.forgotPasswordCallCount, 1);
    });

    test('a new attempt resets the previous succeeded/error flags', () async {
      final repository = _FakeAuthRepository()
        ..forgotPasswordError = ApiException('Server error.');
      final provider = AuthProvider(authRepository: repository);
      await provider.forgotPassword('jane@example.com');
      expect(provider.forgotPasswordErrorMessage, isNotNull);

      repository.forgotPasswordError = null;
      await provider.forgotPassword('jane@example.com');

      expect(provider.forgotPasswordErrorMessage, isNull);
      expect(provider.forgotPasswordSucceeded, isTrue);
    });
  });

  group('resetPassword (Phase 8B-2)', () {
    test('sets resetPasswordSucceeded on success', () async {
      final repository = _FakeAuthRepository();
      final provider = AuthProvider(authRepository: repository);

      await provider.resetPassword(
        email: 'jane@example.com',
        token: 'real-token',
        password: 'new-password-456',
      );

      expect(provider.resetPasswordSucceeded, isTrue);
      expect(provider.resetPasswordErrorMessage, isNull);
    });

    test('never signs the user in on success', () async {
      final repository = _FakeAuthRepository();
      final provider = AuthProvider(authRepository: repository);

      await provider.resetPassword(
        email: 'jane@example.com',
        token: 'real-token',
        password: 'new-password-456',
      );

      expect(provider.isAuthenticated, isFalse);
      expect(provider.user, isNull);
    });

    test('sets resetPasswordErrorMessage on an invalid token', () async {
      final repository = _FakeAuthRepository()
        ..resetPasswordError = ApiException(
          'This password reset token is invalid.',
          statusCode: 422,
        );
      final provider = AuthProvider(authRepository: repository);

      await provider.resetPassword(
        email: 'jane@example.com',
        token: 'wrong-token',
        password: 'new-password-456',
      );

      expect(provider.resetPasswordSucceeded, isFalse);
      expect(
        provider.resetPasswordErrorMessage,
        'This password reset token is invalid.',
      );
    });

    test('a duplicate submission while one is in flight is ignored', () async {
      final repository = _FakeAuthRepository()
        ..resetPasswordDelay = const Duration(milliseconds: 50);
      final provider = AuthProvider(authRepository: repository);

      await Future.wait([
        provider.resetPassword(
          email: 'jane@example.com',
          token: 'token',
          password: 'new-password-456',
        ),
        provider.resetPassword(
          email: 'jane@example.com',
          token: 'token',
          password: 'new-password-456',
        ),
      ]);

      expect(repository.resetPasswordCallCount, 1);
    });
  });

  group('resendVerificationEmail (Phase 8B-2)', () {
    test('sets resendVerificationSucceeded on success', () async {
      final repository = _FakeAuthRepository();
      final provider = AuthProvider(authRepository: repository);

      await provider.resendVerificationEmail();

      expect(provider.resendVerificationSucceeded, isTrue);
      expect(provider.resendVerificationErrorMessage, isNull);
    });

    test('sets resendVerificationErrorMessage on failure', () async {
      final repository = _FakeAuthRepository()
        ..resendVerificationError = ApiException(
          'Server error, please try again later.',
        );
      final provider = AuthProvider(authRepository: repository);

      await provider.resendVerificationEmail();

      expect(provider.resendVerificationSucceeded, isFalse);
      expect(
        provider.resendVerificationErrorMessage,
        'Server error, please try again later.',
      );
    });

    test('a duplicate tap while one is in flight is ignored', () async {
      final repository = _FakeAuthRepository()
        ..resendVerificationDelay = const Duration(milliseconds: 50);
      final provider = AuthProvider(authRepository: repository);

      await Future.wait([
        provider.resendVerificationEmail(),
        provider.resendVerificationEmail(),
      ]);

      expect(repository.resendVerificationCallCount, 1);
    });
  });

  group('refreshUser (Phase 8B-2)', () {
    test('updates user from /me on success', () async {
      final repository = _FakeAuthRepository()
        ..loginResult = _user()
        ..currentUserResult = _user(emailVerified: true);
      final provider = AuthProvider(authRepository: repository);
      await provider.login('jane@example.com', 'password123');
      expect(provider.user?.emailVerified, isFalse);

      await provider.refreshUser();

      expect(provider.user?.emailVerified, isTrue);
    });

    test('leaves the current user untouched on failure', () async {
      final repository = _FakeAuthRepository()..loginResult = _user();
      final provider = AuthProvider(authRepository: repository);
      await provider.login('jane@example.com', 'password123');

      repository.currentUserError = ApiException('Server error.');
      await provider.refreshUser();

      expect(provider.user?.email, 'jane@example.com');
    });
  });
}
