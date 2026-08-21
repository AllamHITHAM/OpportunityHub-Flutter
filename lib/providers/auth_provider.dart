import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/auth/data/auth_repository.dart';
import '../models/user_model.dart';

/// Holds the app's authentication state and exposes auth actions to the UI.
class AuthProvider extends ChangeNotifier {
  AuthProvider({required this.authRepository});

  final AuthRepository authRepository;

  UserModel? user;
  bool isLoading = true;
  String? errorMessage;

  /// True once [initialize] has finished running once at app startup.
  /// The router uses this to know when it's safe to leave the splash screen.
  bool isInitialized = false;

  bool get isAuthenticated => user != null;

  /// Restores the session at app startup: reads the saved token, and if
  /// one exists, confirms it's still valid by calling `/me`.
  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();

    final token = await authRepository.getSavedToken();
    if (token == null) {
      user = null;
      isLoading = false;
      isInitialized = true;
      notifyListeners();
      return;
    }

    try {
      user = await authRepository.getCurrentUser();
    } on ApiException {
      // The saved token is invalid or expired — clear it and sign out.
      await authRepository.clearToken();
      user = null;
    }

    isLoading = false;
    isInitialized = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      user = await authRepository.login(email, password);
    } on ApiException catch (error) {
      errorMessage = error.message;
      user = null;
    }

    isLoading = false;
    notifyListeners();
  }

  /// Registers a new student account (Step 1: account information only).
  ///
  /// On success, [user] is set and the caller becomes authenticated — same
  /// as [login]. Returns `true` on success and `false` on failure, so the
  /// registration screen knows whether to navigate on to Step 2; [login]
  /// doesn't need this because the router navigates for it declaratively,
  /// but Step 2 requires an explicit `extra` payload that only an
  /// imperative navigation can provide.
  Future<bool> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    var success = false;
    try {
      user = await authRepository.registerStudent(
        name: name,
        email: email,
        password: password,
      );
      success = true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      user = null;
    }

    isLoading = false;
    notifyListeners();
    return success;
  }

  /// Registers a new organization (company) account, including its profile
  /// — the backend creates both atomically in one call, so unlike
  /// [registerStudent] there's no later separate profile step to navigate
  /// to imperatively; the router handles that declaratively once
  /// authenticated. Returns `true` on success and `false` on failure, same
  /// convention as [registerStudent].
  Future<bool> registerOrganization({
    required String name,
    required String email,
    required String password,
    required String organizationName,
    required String organizationType,
    String? industry,
    String? description,
    String? website,
    String? phone,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    var success = false;
    try {
      user = await authRepository.registerOrganization(
        name: name,
        email: email,
        password: password,
        organizationName: organizationName,
        organizationType: organizationType,
        industry: industry,
        description: description,
        website: website,
        phone: phone,
      );
      success = true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      user = null;
    }

    isLoading = false;
    notifyListeners();
    return success;
  }

  Future<void> logout() async {
    isLoading = true;
    notifyListeners();

    await authRepository.logout();
    user = null;

    isLoading = false;
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  // -----------------------------------------------------------------
  // Password recovery (Phase 8B-2)
  // -----------------------------------------------------------------

  bool isSendingResetLink = false;
  String? forgotPasswordErrorMessage;

  /// `true` once the current forgot-password request has succeeded — the
  /// screen shows the same safe message regardless of whether the email
  /// actually belonged to an account, so this flag is all it needs.
  /// Reset to `false` at the start of every new attempt.
  bool forgotPasswordSucceeded = false;

  /// Requests a password-reset email for [email]. A duplicate submission
  /// while one is already in flight is ignored (returns immediately, no
  /// second request). Never reveals whether [email] belongs to a real
  /// account — success is success either way.
  Future<void> forgotPassword(String email) async {
    if (isSendingResetLink) return;

    isSendingResetLink = true;
    forgotPasswordErrorMessage = null;
    forgotPasswordSucceeded = false;
    notifyListeners();

    try {
      await authRepository.forgotPassword(email);
      forgotPasswordSucceeded = true;
    } on ApiException catch (error) {
      forgotPasswordErrorMessage = error.message;
    }

    isSendingResetLink = false;
    notifyListeners();
  }

  bool isResettingPassword = false;
  String? resetPasswordErrorMessage;
  bool resetPasswordSucceeded = false;

  /// Completes a password reset using the `token`/`email` pair from the
  /// reset link. Deliberately does **not** sign the user in on success —
  /// [user] is left untouched either way; the caller navigates to Login.
  /// A duplicate submission while one is already in flight is ignored.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    if (isResettingPassword) return;

    isResettingPassword = true;
    resetPasswordErrorMessage = null;
    resetPasswordSucceeded = false;
    notifyListeners();

    try {
      await authRepository.resetPassword(
        email: email,
        token: token,
        password: password,
      );
      resetPasswordSucceeded = true;
    } on ApiException catch (error) {
      resetPasswordErrorMessage = error.message;
    }

    isResettingPassword = false;
    notifyListeners();
  }

  // -----------------------------------------------------------------
  // Email verification (Phase 8B-2)
  // -----------------------------------------------------------------

  bool isResendingVerification = false;
  String? resendVerificationErrorMessage;
  bool resendVerificationSucceeded = false;

  /// Resends the verification email to the current user. A duplicate tap
  /// while one is already in flight is ignored.
  Future<void> resendVerificationEmail() async {
    if (isResendingVerification) return;

    isResendingVerification = true;
    resendVerificationErrorMessage = null;
    resendVerificationSucceeded = false;
    notifyListeners();

    try {
      await authRepository.resendVerificationEmail();
      resendVerificationSucceeded = true;
    } on ApiException catch (error) {
      resendVerificationErrorMessage = error.message;
    }

    isResendingVerification = false;
    notifyListeners();
  }

  /// Refreshes [user] from `/me` — used after the user returns from
  /// verifying their email in another tab/browser, so the in-app
  /// "unverified" banner can clear without requiring a full re-login.
  Future<void> refreshUser() async {
    try {
      user = await authRepository.getCurrentUser();
      notifyListeners();
    } on ApiException {
      // Leave the current `user` untouched on failure -- a transient
      // refresh failure must never sign the user out or blank their state.
    }
  }
}
