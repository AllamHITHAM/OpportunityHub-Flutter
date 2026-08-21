import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_education_verifications_repository.dart';
import '../models/admin_education_verification_model.dart';
import 'auth_provider.dart';

/// Holds the Admin education-verification review list and exposes the
/// verify/reject actions (Phase 8B-1). Mirrors
/// `AdminSkillSuggestionsProvider`'s shape.
class AdminEducationVerificationsProvider extends ChangeNotifier {
  AdminEducationVerificationsProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AdminEducationVerificationsRepository repository;
  final AuthProvider _authProvider;

  List<AdminEducationVerificationModel> verifications = [];
  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Verification ids with a verify/reject/document request currently in
  /// flight — guards against a duplicate action for the same row.
  final Set<int> busyIds = {};

  Future<void>? _pendingLoad;

  bool isBusy(int verificationId) => busyIds.contains(verificationId);

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingLoad = null;
    }
    return _pendingLoad ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      verifications = await repository.getVerifications();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoading = false;
      _pendingLoad = null;
      notifyListeners();
    }
  }

  String? downloadErrorMessage;

  /// Downloads the document for [verificationId] for Admin review.
  /// Returns `null` on failure (see [downloadErrorMessage]) — shares
  /// [busyIds] with verify/reject, so a download in flight for a row also
  /// blocks a duplicate action on that same row.
  Future<Uint8List?> downloadDocument(int verificationId) async {
    if (busyIds.contains(verificationId)) return null;

    busyIds.add(verificationId);
    downloadErrorMessage = null;
    notifyListeners();

    Uint8List? bytes;
    try {
      bytes = await repository.downloadDocument(verificationId);
    } on ApiException catch (error) {
      downloadErrorMessage = error.message;
    } catch (_) {
      downloadErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyIds.remove(verificationId);
      notifyListeners();
    }
    return bytes;
  }

  /// Approves [verificationId] and removes it from the local list on
  /// success. Returns `true` only on success.
  Future<bool> verify(int verificationId) =>
      _review(verificationId, (id) => repository.verify(id));

  /// Rejects [verificationId] with [reason] and removes it from the local
  /// list on success. Returns `true` only on success.
  Future<bool> reject(int verificationId, {required String reason}) =>
      _review(verificationId, (id) => repository.reject(id, reason: reason));

  Future<bool> _review(
    int verificationId,
    Future<void> Function(int) call,
  ) async {
    if (busyIds.contains(verificationId)) return false;

    busyIds.add(verificationId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await call(verificationId);
      verifications = verifications
          .where((verification) => verification.id != verificationId)
          .toList();
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyIds.remove(verificationId);
      notifyListeners();
    }
    return success;
  }

  void reset() {
    verifications = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    downloadErrorMessage = null;
    busyIds.clear();
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
