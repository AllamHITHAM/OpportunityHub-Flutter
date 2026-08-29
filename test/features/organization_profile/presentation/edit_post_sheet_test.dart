// Widget tests for EditPostSheet (Organization Public Profile phase, and
// Company Profile Polish's optional single-image extension), in isolation
// with a fake repository (no real network).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/organization_profile/data/picked_image_file.dart';
import 'package:opportunityhub_flutter/features/organization_profile/presentation/edit_post_sheet.dart';
import 'package:opportunityhub_flutter/models/organization_post_model.dart';
import 'package:opportunityhub_flutter/providers/organization_public_profile_provider.dart';

// A real, minimal valid 1x1 PNG -- `Image.memory` decodes actual image
// bytes even in the widget-test environment, so arbitrary placeholder
// bytes (e.g. `[1, 2, 3]`) throw "Invalid image data" mid-test.
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
    '42YAAAAASUVORK5CYII=';

PickedImageFile _fakeImage([String filename = 'photo.png']) => PickedImageFile(
  filename: filename,
  bytes: base64Decode(_tinyPngBase64),
);

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  int createCallCount = 0;
  int updateCallCount = 0;
  ApiException? createError;
  String? lastBody;
  PickedImageFile? lastCreateImage;
  PickedImageFile? lastUpdateImage;
  bool? lastUpdateRemoveImage;

  @override
  Future<OrganizationPostModel> createPost({
    String? title,
    required String body,
    PickedImageFile? image,
  }) async {
    createCallCount++;
    lastBody = body;
    lastCreateImage = image;
    if (createError != null) throw createError!;
    // A small delay so a rapid double-tap genuinely races against the
    // in-flight guard rather than always finishing before the second tap.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return OrganizationPostModel(
      id: 1,
      organizationId: 1,
      title: title,
      body: body,
      imageUrl: image != null ? 'https://cdn.example.com/posts/1.png' : null,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<OrganizationPostModel> updatePost(
    int postId, {
    String? title,
    required String body,
    PickedImageFile? image,
    bool removeImage = false,
  }) async {
    updateCallCount++;
    lastUpdateImage = image;
    lastUpdateRemoveImage = removeImage;
    return OrganizationPostModel(
      id: postId,
      organizationId: 1,
      title: title,
      body: body,
      imageUrl: image != null
          ? 'https://cdn.example.com/posts/$postId-new.png'
          : null,
      createdAt: DateTime.now(),
    );
  }
}

Future<_FakeOrganizationProfileRepository> _pumpSheet(
  WidgetTester tester, {
  OrganizationPostModel? post,
  Future<PickedImageFile?> Function() pickImage = _defaultPickImage,
}) async {
  // Tall enough that the image preview plus Replace/Remove/Publish rows
  // are all on-screen without needing to scroll to tap them -- the
  // default 800x600 test surface is too short once an image is attached.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _FakeOrganizationProfileRepository();
  final provider = OrganizationPublicProfileProvider(
    repository: repository,
    opportunityRepository: OpportunityRepository(
      apiClient: ApiClient(tokenStorageService: TokenStorageService()),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: ChangeNotifierProvider<OrganizationPublicProfileProvider>.value(
        value: provider,
        child: Scaffold(
          body: EditPostSheet(post: post, pickImage: pickImage),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return repository;
}

Future<PickedImageFile?> _defaultPickImage() async => null;

void main() {
  testWidgets('Create shows a Publish button and an empty body field', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.text('Create Update'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
  });

  testWidgets('Edit prepopulates the existing post and shows Save Changes', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      post: OrganizationPostModel(
        id: 5,
        organizationId: 1,
        title: 'Existing Title',
        body: 'Existing body text.',
        createdAt: DateTime.now(),
      ),
    );

    expect(find.text('Edit Update'), findsOneWidget);
    expect(find.text('Existing Title'), findsOneWidget);
    expect(find.text('Existing body text.'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
  });

  testWidgets('Publish is disabled while the body is empty', (tester) async {
    await _pumpSheet(tester);

    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Publish'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('publishing calls createPost exactly once and never twice on '
      'a rapid double tap', (tester) async {
    final repository = await _pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).last, 'A real update.');
    await tester.pump();

    // Two rapid taps before the first request resolves.
    await tester.tap(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repository.createCallCount, 1);
    expect(repository.lastBody, 'A real update.');
  });

  testWidgets('a failed create shows a real error and keeps the entered text', (
    tester,
  ) async {
    final repository = await _pumpSheet(tester);
    repository.createError = ApiException('Something went wrong');

    await tester.enterText(find.byType(TextFormField).last, 'A real update.');
    await tester.pump();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('A real update.'), findsOneWidget);
  });

  testWidgets('editing calls updatePost, never createPost', (tester) async {
    final repository = await _pumpSheet(
      tester,
      post: OrganizationPostModel(
        id: 5,
        organizationId: 1,
        title: null,
        body: 'Old body.',
        createdAt: DateTime.now(),
      ),
    );

    await tester.enterText(find.byType(TextFormField).last, 'New body.');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repository.updateCallCount, 1);
    expect(repository.createCallCount, 0);
  });

  testWidgets('shows Add Image when no image is attached yet', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.text('Add Image (optional)'), findsOneWidget);
    expect(find.text('Replace'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('choosing an image shows a preview with Replace/Remove', (
    tester,
  ) async {
    await _pumpSheet(tester, pickImage: () async => _fakeImage());

    await tester.tap(find.text('Add Image (optional)'));
    await tester.pumpAndSettle();

    expect(find.text('Add Image (optional)'), findsNothing);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('removing a freshly-picked image restores Add Image', (
    tester,
  ) async {
    await _pumpSheet(tester, pickImage: () async => _fakeImage());

    await tester.tap(find.text('Add Image (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Add Image (optional)'), findsOneWidget);
  });

  testWidgets('publishing with an image sends it to createPost', (
    tester,
  ) async {
    final repository = await _pumpSheet(
      tester,
      pickImage: () async => _fakeImage('new-post.png'),
    );

    await tester.enterText(find.byType(TextFormField).last, 'A real update.');
    await tester.tap(find.text('Add Image (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repository.createCallCount, 1);
    expect(repository.lastCreateImage?.filename, 'new-post.png');
  });

  testWidgets('Edit with an existing image shows Keep-state preview and '
      'Remove clears it', (tester) async {
    final repository = await _pumpSheet(
      tester,
      post: OrganizationPostModel(
        id: 7,
        organizationId: 1,
        body: 'Body with an image.',
        imageUrl: 'https://cdn.example.com/posts/7.png',
        createdAt: DateTime.now(),
      ),
    );

    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Add Image (optional)'), findsOneWidget);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repository.updateCallCount, 1);
    expect(repository.lastUpdateImage, isNull);
    expect(repository.lastUpdateRemoveImage, isTrue);
  });

  testWidgets('Edit replacing an existing image sends the new file, not a '
      'remove flag', (tester) async {
    final repository = await _pumpSheet(
      tester,
      post: OrganizationPostModel(
        id: 8,
        organizationId: 1,
        body: 'Body with an image.',
        imageUrl: 'https://cdn.example.com/posts/8.png',
        createdAt: DateTime.now(),
      ),
      pickImage: () async => _fakeImage('replacement.png'),
    );

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repository.updateCallCount, 1);
    expect(repository.lastUpdateImage?.filename, 'replacement.png');
    expect(repository.lastUpdateRemoveImage, isFalse);
  });
}
