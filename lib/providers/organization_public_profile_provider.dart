import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/opportunities/data/opportunity_repository.dart';
import '../features/organization/data/organization_profile_repository.dart';
import '../features/organization_profile/data/picked_image_file.dart';
import '../models/opportunity_model.dart';
import '../models/organization_post_model.dart';
import '../models/organization_profile_model.dart';

/// Holds one Organization's public-facing profile + posts (Organization
/// Public Profile phase) — used by both the Student-facing public Company
/// Profile screen and the Organization's own "view as public" screen,
/// since both render the exact same real, safe-field data from the same
/// `GET /organizations/{id}` / `GET /organizations/{id}/posts` endpoints.
/// Deliberately a separate provider from [OrganizationProfileProvider]
/// (which owns the authenticated organization's *own* profile-completion
/// state used by the router's redirect logic) — this one can load any
/// organization's data by ID without ever risking overwriting that
/// router-critical state.
class OrganizationPublicProfileProvider extends ChangeNotifier {
  OrganizationPublicProfileProvider({
    required this.repository,
    required this.opportunityRepository,
  });

  final OrganizationProfileRepository repository;
  final OpportunityRepository opportunityRepository;

  OrganizationProfileModel? profile;
  bool isLoadingProfile = false;
  String? profileErrorMessage;

  List<OrganizationPostModel> posts = [];
  bool isLoadingPosts = false;
  String? postsErrorMessage;

  /// The organization's real open opportunities (spec section 4/17) --
  /// reuses `GET /opportunities?organization_id=X`, the exact same
  /// open+approved-only query every other public opportunity listing in
  /// this app already runs, never a duplicate fetch/business-logic path.
  List<OpportunityModel> openOpportunities = [];
  bool isLoadingOpportunities = false;
  String? opportunitiesErrorMessage;

  bool isSubmittingPost = false;
  String? postActionErrorMessage;

  /// Post IDs with an edit/delete request currently in flight — guards
  /// against a duplicate submission for the same post.
  final Set<int> busyPostIds = {};

  /// The signed-in organization's own closed opportunities (Company
  /// Profile Polish phase; Closed Opportunities Scalability Polish for
  /// the real backend-paginated/filtered/sorted fetch below) — owner-
  /// only, never fetched for a non-owner-viewed profile (there is no way
  /// to scope `GET /organization/opportunities/closed` to an arbitrary
  /// organization ID; it always returns the *authenticated*
  /// organization's own rows). The screen only ever calls
  /// [loadClosedOpportunitiesForOwner] when it has already confirmed
  /// `isOwner` itself.
  List<OpportunityModel> closedOpportunities = [];
  bool isLoadingClosedOpportunities = false;
  String? closedOpportunitiesErrorMessage;

  bool isLoadingMoreClosedOpportunities = false;
  String? loadMoreClosedOpportunitiesErrorMessage;

  int _closedCurrentPage = 1;
  int _closedLastPage = 1;
  bool get hasMoreClosedOpportunities => _closedCurrentPage < _closedLastPage;

  /// The organization's real, TOTAL closed count — unaffected by
  /// whichever date filter is currently applied. The Company Profile
  /// accordion header ("Closed Opportunities (N)") always reads this,
  /// never [closedOpportunitiesFilteredTotal].
  int totalClosedOpportunities = 0;

  /// The CURRENT filter/sort selection's own total (the paginated
  /// response's real `total`, before pagination) — used for the
  /// "Showing X of Y" caption whenever a filter narrows the list below
  /// [totalClosedOpportunities].
  int closedOpportunitiesFilteredTotal = 0;

  /// `all`/`last_30_days`/`last_3_months`/`last_6_months`/`this_year`/
  /// `older` — mutually exclusive with [closedFromDate]/[closedToDate]
  /// on the backend (a custom range always wins when either is set); the
  /// UI itself only ever offers one or the other, never both at once.
  String closedDatePreset = 'all';
  DateTime? closedFromDate;
  DateTime? closedToDate;

  /// `newest` (default, per spec) or `oldest`.
  String closedSort = 'newest';

  /// The in-flight closed-opportunities page-1 fetch, if any — guards
  /// against a duplicate request (e.g. a rapid repeated filter tap)
  /// without preventing an explicit refresh once the previous fetch has
  /// finished, mirroring [load]'s own `_pendingLoad` convention.
  Future<void>? _pendingClosedFetch;

  /// Closed-opportunity IDs with a permanent-delete request currently in
  /// flight.
  final Set<int> busyClosedOpportunityIds = {};
  String? deleteClosedOpportunityErrorMessage;

  /// Which organization [profile]/[posts] (or the in-flight load) is
  /// for — a request for a different organization ID always starts a
  /// fresh load rather than reusing a stale in-flight one.
  int? _loadedOrganizationId;
  Future<void>? _pendingLoad;

  bool isBusyWithPost(int postId) => busyPostIds.contains(postId);
  bool isBusyWithClosedOpportunity(int id) => busyClosedOpportunityIds.contains(id);

  /// Loads both the profile and posts for [organizationId]. Safe to call
  /// repeatedly — a fetch already in flight *for the same organization*
  /// is reused; a request for a different organization always starts
  /// fresh. Pass [forceRefresh] to start a fresh one regardless.
  Future<void> load(int organizationId, {bool forceRefresh = false}) {
    if (forceRefresh || _loadedOrganizationId != organizationId) {
      _pendingLoad = null;
    }
    _loadedOrganizationId = organizationId;
    return _pendingLoad ??= _performLoad(organizationId);
  }

  Future<void> _performLoad(int organizationId) async {
    isLoadingProfile = true;
    profileErrorMessage = null;
    isLoadingPosts = true;
    postsErrorMessage = null;
    isLoadingOpportunities = true;
    opportunitiesErrorMessage = null;
    notifyListeners();

    bool stillCurrent() => organizationId == _loadedOrganizationId;

    await Future.wait([
      _loadProfile(organizationId, stillCurrent),
      _loadPosts(organizationId, stillCurrent),
      _loadOpenOpportunities(organizationId, stillCurrent),
    ]);

    if (stillCurrent()) {
      _pendingLoad = null;
    }
  }

  Future<void> _loadOpenOpportunities(
    int organizationId,
    bool Function() stillCurrent,
  ) async {
    try {
      final result = await opportunityRepository.getPublicOpportunities(
        organizationId: organizationId,
        perPage: 50,
      );
      if (stillCurrent()) {
        openOpportunities = result.items;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        opportunitiesErrorMessage = error.message;
      }
    } catch (_) {
      if (stillCurrent()) {
        opportunitiesErrorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoadingOpportunities = false;
      }
      notifyListeners();
    }
  }

  Future<void> _loadProfile(int organizationId, bool Function() stillCurrent) async {
    try {
      final result = await repository.getPublicProfile(organizationId);
      if (stillCurrent()) {
        profile = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        profileErrorMessage = error.message;
      }
    } catch (_) {
      if (stillCurrent()) {
        profileErrorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoadingProfile = false;
      }
      notifyListeners();
    }
  }

  Future<void> _loadPosts(int organizationId, bool Function() stillCurrent) async {
    try {
      final result = await repository.getPosts(organizationId);
      if (stillCurrent()) {
        posts = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        postsErrorMessage = error.message;
      }
    } catch (_) {
      if (stillCurrent()) {
        postsErrorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoadingPosts = false;
      }
      notifyListeners();
    }
  }

  /// Publishes a new post, Organization-owner only. On success, the real
  /// created row is prepended to [posts] locally (newest-first, matching
  /// the backend's own ordering) rather than triggering a full reload.
  /// Returns `true` only on success. A duplicate submission while one is
  /// already in flight is ignored.
  Future<bool> createPost({
    String? title,
    required String body,
    PickedImageFile? image,
  }) async {
    if (isSubmittingPost) return false;

    isSubmittingPost = true;
    postActionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final created = await repository.createPost(
        title: title,
        body: body,
        image: image,
      );
      posts = [created, ...posts];
      success = true;
    } on ApiException catch (error) {
      postActionErrorMessage = error.message;
    } catch (_) {
      postActionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isSubmittingPost = false;
      notifyListeners();
    }
    return success;
  }

  /// Edits one of the current organization's own posts. On success,
  /// [posts] is patched in place with the real, freshly-saved row.
  /// Returns `true` only on success.
  Future<bool> updatePost(
    int postId, {
    String? title,
    required String body,
    PickedImageFile? image,
    bool removeImage = false,
  }) async {
    if (busyPostIds.contains(postId)) return false;

    busyPostIds.add(postId);
    postActionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.updatePost(
        postId,
        title: title,
        body: body,
        image: image,
        removeImage: removeImage,
      );
      final index = posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final updatedList = [...posts];
        updatedList[index] = updated;
        posts = updatedList;
      }
      success = true;
    } on ApiException catch (error) {
      postActionErrorMessage = error.message;
    } catch (_) {
      postActionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyPostIds.remove(postId);
      notifyListeners();
    }
    return success;
  }

  /// Deletes one of the current organization's own posts. On success,
  /// [posts] no longer contains it. Returns `true` only on success — a
  /// failed delete leaves the post visible with a real error rather than
  /// silently disappearing.
  Future<bool> deletePost(int postId) async {
    if (busyPostIds.contains(postId)) return false;

    busyPostIds.add(postId);
    postActionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.deletePost(postId);
      posts = posts.where((p) => p.id != postId).toList();
      success = true;
    } on ApiException catch (error) {
      postActionErrorMessage = error.message;
    } catch (_) {
      postActionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyPostIds.remove(postId);
      notifyListeners();
    }
    return success;
  }

  void clearPostActionError() {
    postActionErrorMessage = null;
    notifyListeners();
  }

  /// Loads page 1 of the signed-in organization's own closed
  /// opportunities (Closed Opportunities Scalability Polish) via the
  /// real, backend-paginated/filtered/sorted
  /// `GET /organization/opportunities/closed`, using the current
  /// [closedDatePreset]/[closedFromDate]/[closedToDate]/[closedSort]
  /// selection. Safe to call repeatedly -- a fetch already in flight is
  /// reused rather than duplicated (guarding against e.g. a rapid
  /// repeated filter tap); pass [forceRefresh] to start a fresh one
  /// regardless (e.g. after changing a filter, or a successful delete).
  /// The caller (the Company Profile screen) is responsible for only
  /// ever calling this when it has already confirmed the viewer is the
  /// owner.
  Future<void> loadClosedOpportunitiesForOwner({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingClosedFetch = null;
    }
    return _pendingClosedFetch ??= _performLoadClosedOpportunities();
  }

  Future<void> _performLoadClosedOpportunities() async {
    isLoadingClosedOpportunities = true;
    closedOpportunitiesErrorMessage = null;
    notifyListeners();

    try {
      final response = await opportunityRepository.getClosedOpportunities(
        datePreset: _hasCustomClosedRange ? null : closedDatePreset,
        closedFrom: closedFromDate,
        closedTo: closedToDate,
        sort: closedSort,
      );
      closedOpportunities = response.result.items;
      _closedCurrentPage = response.result.currentPage;
      _closedLastPage = response.result.lastPage;
      closedOpportunitiesFilteredTotal = response.result.total;
      totalClosedOpportunities = response.totalClosed;
    } on ApiException catch (error) {
      closedOpportunitiesErrorMessage = error.message;
    } catch (_) {
      closedOpportunitiesErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoadingClosedOpportunities = false;
      _pendingClosedFetch = null;
      notifyListeners();
    }
  }

  bool get _hasCustomClosedRange => closedFromDate != null || closedToDate != null;

  /// Fetches the next page of closed opportunities and appends it to
  /// [closedOpportunities], using the same filter/sort currently applied.
  /// A no-op while a page is already loading or none remains. A failed
  /// page fetch leaves every already-loaded row exactly as it was --
  /// never clears [closedOpportunities] on failure.
  Future<void> loadMoreClosedOpportunities() async {
    if (isLoadingMoreClosedOpportunities || !hasMoreClosedOpportunities) return;

    isLoadingMoreClosedOpportunities = true;
    loadMoreClosedOpportunitiesErrorMessage = null;
    notifyListeners();

    try {
      final response = await opportunityRepository.getClosedOpportunities(
        datePreset: _hasCustomClosedRange ? null : closedDatePreset,
        closedFrom: closedFromDate,
        closedTo: closedToDate,
        sort: closedSort,
        page: _closedCurrentPage + 1,
      );
      closedOpportunities = [...closedOpportunities, ...response.result.items];
      _closedCurrentPage = response.result.currentPage;
      _closedLastPage = response.result.lastPage;
      closedOpportunitiesFilteredTotal = response.result.total;
      totalClosedOpportunities = response.totalClosed;
    } on ApiException catch (error) {
      loadMoreClosedOpportunitiesErrorMessage = error.message;
    } catch (_) {
      loadMoreClosedOpportunitiesErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoadingMoreClosedOpportunities = false;
      notifyListeners();
    }
  }

  /// Applies a new date-preset selection (clearing any custom range) and
  /// immediately refetches page 1 -- changing a filter always resets
  /// pagination and clears whatever "load more" state/error the previous
  /// filter had.
  Future<void> applyClosedOpportunitiesDatePreset(String preset) {
    closedDatePreset = preset;
    closedFromDate = null;
    closedToDate = null;
    loadMoreClosedOpportunitiesErrorMessage = null;
    return loadClosedOpportunitiesForOwner(forceRefresh: true);
  }

  /// Applies a custom `from`/`to` range (clearing any preset selection)
  /// and immediately refetches page 1. Either bound may be omitted for
  /// an open-ended range.
  Future<void> applyClosedOpportunitiesDateRange({
    DateTime? from,
    DateTime? to,
  }) {
    closedDatePreset = 'all';
    closedFromDate = from;
    closedToDate = to;
    loadMoreClosedOpportunitiesErrorMessage = null;
    return loadClosedOpportunitiesForOwner(forceRefresh: true);
  }

  /// Applies a new sort order and immediately refetches page 1.
  Future<void> applyClosedOpportunitiesSort(String sort) {
    closedSort = sort;
    loadMoreClosedOpportunitiesErrorMessage = null;
    return loadClosedOpportunitiesForOwner(forceRefresh: true);
  }

  /// Permanently deletes a closed opportunity with zero recruitment
  /// history. Returns `true` only on success, in which case
  /// [closedOpportunities] no longer contains it and both
  /// [totalClosedOpportunities]/[closedOpportunitiesFilteredTotal] are
  /// decremented locally (a full refetch is never required just to keep
  /// the counts accurate). A duplicate submission while one is already
  /// in flight for the same ID is ignored. A rejected deletion (wrong
  /// status, or real recruitment history) never removes the item locally
  /// -- the backend is the sole authority.
  Future<bool> deleteClosedOpportunity(int opportunityId) async {
    if (busyClosedOpportunityIds.contains(opportunityId)) return false;

    busyClosedOpportunityIds.add(opportunityId);
    deleteClosedOpportunityErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await opportunityRepository.deleteClosedOpportunity(opportunityId);
      closedOpportunities = closedOpportunities
          .where((o) => o.id != opportunityId)
          .toList();
      if (totalClosedOpportunities > 0) totalClosedOpportunities--;
      if (closedOpportunitiesFilteredTotal > 0) closedOpportunitiesFilteredTotal--;
      success = true;
    } on ApiException catch (error) {
      deleteClosedOpportunityErrorMessage = error.message;
    } catch (_) {
      deleteClosedOpportunityErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyClosedOpportunityIds.remove(opportunityId);
      notifyListeners();
    }
    return success;
  }

  void clearDeleteClosedOpportunityError() {
    deleteClosedOpportunityErrorMessage = null;
    notifyListeners();
  }

  /// Clears all state — called when navigating away from a Company
  /// Profile screen, so the next one opened never briefly shows stale
  /// data from a previously-viewed organization.
  void reset() {
    profile = null;
    isLoadingProfile = false;
    profileErrorMessage = null;
    posts = [];
    isLoadingPosts = false;
    postsErrorMessage = null;
    openOpportunities = [];
    isLoadingOpportunities = false;
    opportunitiesErrorMessage = null;
    isSubmittingPost = false;
    postActionErrorMessage = null;
    busyPostIds.clear();
    closedOpportunities = [];
    isLoadingClosedOpportunities = false;
    closedOpportunitiesErrorMessage = null;
    isLoadingMoreClosedOpportunities = false;
    loadMoreClosedOpportunitiesErrorMessage = null;
    _closedCurrentPage = 1;
    _closedLastPage = 1;
    totalClosedOpportunities = 0;
    closedOpportunitiesFilteredTotal = 0;
    closedDatePreset = 'all';
    closedFromDate = null;
    closedToDate = null;
    closedSort = 'newest';
    _pendingClosedFetch = null;
    busyClosedOpportunityIds.clear();
    deleteClosedOpportunityErrorMessage = null;
    _loadedOrganizationId = null;
    _pendingLoad = null;
    notifyListeners();
  }
}
