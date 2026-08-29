import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/organization_post_model.dart';
import '../../../providers/organization_public_profile_provider.dart';
import '../data/picked_image_file.dart';

/// A modal bottom sheet to create a new "Update & Achievement" post, or
/// edit an existing one when [post] is passed (Organization Public
/// Profile phase) — one shared sheet for both, matching
/// [InviteToApplySheet]'s own "one sheet, optional context" shape.
/// Extended (Company Profile Polish phase) with an optional single image
/// — Choose Image / Preview / Remove, and (when editing an existing post
/// that already has one) Keep existing / Replace / Remove.
class EditPostSheet extends StatefulWidget {
  const EditPostSheet({
    super.key,
    this.post,
    this.pickImage = pickImageFileFromDevice,
  });

  /// `null` for Create, the real existing post for Edit.
  final OrganizationPostModel? post;

  /// Defaults to the real platform file picker
  /// ([pickImageFileFromDevice]) — overridable in tests so this sheet's
  /// image flow can be exercised without a real platform file-picker
  /// channel.
  final Future<PickedImageFile?> Function() pickImage;

  @override
  State<EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<EditPostSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _hasSubmitted = false;

  /// A freshly-picked image not yet uploaded -- `null` until the user
  /// chooses one.
  PickedImageFile? _newImage;

  /// True once the user has explicitly asked to remove the existing
  /// image (Edit only) -- distinct from simply never having picked a new
  /// one, so "keep existing unchanged" and "remove it" are never
  /// conflated.
  bool _removeExistingImage = false;

  bool get _isEditing => widget.post != null;

  /// Whether *some* image will be attached after a successful submit --
  /// either a freshly-picked one, or the existing one being kept.
  bool get _hasAnyImage =>
      _newImage != null ||
      (!_removeExistingImage && (widget.post?.imageUrl != null));

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.post?.title);
    _bodyController = TextEditingController(text: widget.post?.body);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    final picked = await widget.pickImage();
    if (!mounted || picked == null) return;
    setState(() {
      _newImage = picked;
      _removeExistingImage = false;
    });
  }

  void _removeImage() {
    setState(() {
      _newImage = null;
      _removeExistingImage = true;
    });
  }

  Future<void> _submit(OrganizationPublicProfileProvider provider) async {
    setState(() => _hasSubmitted = true);
    FocusScope.of(context).unfocus();

    final body = _bodyController.text.trim();
    if (body.isEmpty) return;

    final title = _titleController.text.trim();
    final success = _isEditing
        ? await provider.updatePost(
            widget.post!.id,
            title: title.isEmpty ? null : title,
            body: body,
            image: _newImage,
            removeImage: _removeExistingImage,
          )
        : await provider.createPost(
            title: title.isEmpty ? null : title,
            body: body,
            image: _newImage,
          );
    if (!mounted || !success) return;

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationPublicProfileProvider>();
    final isLoading = _isEditing
        ? provider.isBusyWithPost(widget.post!.id)
        : provider.isSubmittingPost;
    final bodyEmpty = _bodyController.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(title: _isEditing ? 'Edit Update' : 'Create Update'),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _titleController,
              label: 'Title (optional)',
              hint: 'e.g. Summer Internship Program',
              maxLength: 255,
              enabled: !isLoading,
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _bodyController,
              label: 'Update',
              hint: 'Share a company update or achievement',
              maxLines: 6,
              minLines: 3,
              maxLength: 5000,
              enabled: !isLoading,
              onChanged: (_) => setState(() {}),
              validator: (_) =>
                  _hasSubmitted && bodyEmpty ? 'Update text is required' : null,
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _ImagePicker(
              newImageBytes: _newImage?.bytes,
              existingImageUrl: _removeExistingImage ? null : widget.post?.imageUrl,
              hasAnyImage: _hasAnyImage,
              enabled: !isLoading,
              onChoose: _chooseImage,
              onRemove: _removeImage,
            ),
            if (_hasSubmitted && provider.postActionErrorMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              AppErrorView(
                title: 'Something Went Wrong',
                message: provider.postActionErrorMessage!,
                compact: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _isEditing ? 'Save Changes' : 'Publish',
              isLoading: isLoading,
              onPressed: (isLoading || bodyEmpty)
                  ? null
                  : () => _submit(provider),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Add Image" / preview / "Remove Image" control (Company Profile
/// Polish phase) -- shows "Choose Image" when nothing is attached yet, or
/// a preview (from freshly-picked local [newImageBytes] if present,
/// otherwise the already-published [existingImageUrl]) plus "Replace"/
/// "Remove" once one is.
class _ImagePicker extends StatelessWidget {
  const _ImagePicker({
    required this.newImageBytes,
    required this.existingImageUrl,
    required this.hasAnyImage,
    required this.enabled,
    required this.onChoose,
    required this.onRemove,
  });

  final Uint8List? newImageBytes;
  final String? existingImageUrl;
  final bool hasAnyImage;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (!hasAnyImage) {
      return SecondaryButton(
        label: 'Add Image (optional)',
        icon: Icons.image_outlined,
        onPressed: enabled ? onChoose : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.mediumRadius,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: newImageBytes != null
                ? Image.memory(newImageBytes!, fit: BoxFit.cover)
                : Image.network(
                    existingImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.surfaceVariant,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Replace',
                icon: Icons.image_outlined,
                onPressed: enabled ? onChoose : null,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: SecondaryButton(
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                onPressed: enabled ? onRemove : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shows [EditPostSheet] with the ancestor provider it needs, and returns
/// `true` only when the post was successfully created/saved.
Future<bool> showEditPostSheet(
  BuildContext context, {
  OrganizationPostModel? post,
}) async {
  final provider = context.read<OrganizationPublicProfileProvider>();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        ChangeNotifierProvider<OrganizationPublicProfileProvider>.value(
          value: provider,
          child: EditPostSheet(post: post),
        ),
  );
  return result ?? false;
}
