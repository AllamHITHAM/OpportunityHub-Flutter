import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/question_model.dart';
import '../../../providers/organization_quiz_provider.dart';
import '../data/question_input.dart';

/// A modal bottom sheet for adding or editing a single Question on a draft
/// Quiz. Pass [existing] to edit that question in place; omit it to create
/// a new one. Never shown for a published quiz — the editor screen only
/// ever offers Add/Edit actions while `quiz.status == 'draft'`.
class QuestionFormSheet extends StatefulWidget {
  const QuestionFormSheet({super.key, this.existing});

  final QuestionModel? existing;

  @override
  State<QuestionFormSheet> createState() => _QuestionFormSheetState();
}

class _QuestionFormSheetState extends State<QuestionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _promptController = TextEditingController();
  final _pointsController = TextEditingController(text: '1');
  final _positionController = TextEditingController(text: '0');
  final List<TextEditingController> _optionControllers = [];

  String _type = 'multiple_choice';

  /// Index into [_optionControllers] of the selected correct option —
  /// `multiple_choice` only.
  int? _correctOptionIndex;

  /// `true_false` only: `'True'` or `'False'`.
  String? _trueFalseAnswer;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    if (existing != null) {
      _promptController.text = existing.prompt;
      _pointsController.text = existing.points.toString();
      _positionController.text = existing.position.toString();
      _type = existing.type;

      if (existing.type == 'multiple_choice') {
        final options = existing.options ?? const [];
        for (final option in options) {
          _optionControllers.add(TextEditingController(text: option));
        }
        final correctAnswer = existing.correctAnswer;
        final matchedIndex = correctAnswer == null
            ? -1
            : options.indexOf(correctAnswer);
        _correctOptionIndex = matchedIndex == -1 ? null : matchedIndex;
      } else {
        _trueFalseAnswer = existing.correctAnswer == 'False' ? 'False' : 'True';
      }
    } else {
      _trueFalseAnswer = 'True';
    }

    while (_optionControllers.length < 2) {
      _optionControllers.add(TextEditingController());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationQuizProvider>().clearActionErrors();
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _pointsController.dispose();
    _positionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _fieldError(String field) {
    final provider = context.read<OrganizationQuizProvider>();
    final messages = provider.fieldErrors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  void _addOption() {
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
      if (_correctOptionIndex == index) {
        _correctOptionIndex = null;
      } else if (_correctOptionIndex != null && _correctOptionIndex! > index) {
        _correctOptionIndex = _correctOptionIndex! - 1;
      }
    });
  }

  String? _promptValidator(String? value) {
    final backendError = _fieldError('prompt');
    if (backendError != null) return backendError;
    if ((value?.trim() ?? '').isEmpty) return 'Prompt is required';
    if (value!.trim().length > 2000) {
      return 'Prompt must be 2000 characters or fewer';
    }
    return null;
  }

  String? _pointsValidator(String? value) {
    final backendError = _fieldError('points');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Points is required';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  String? _positionValidator(String? value) {
    final backendError = _fieldError('position');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) {
      return 'Enter a whole number of 0 or more';
    }
    return null;
  }

  String? _optionValidator(String? value) {
    if ((value?.trim() ?? '').isEmpty) return 'Option cannot be empty';
    return null;
  }

  /// Options-level and correct-answer-level errors that don't belong to a
  /// single text field — shown once beneath the option list, mirroring how
  /// [AppErrorView] surfaces a form-level (as opposed to field-level)
  /// business error elsewhere in this app.
  String? _optionsGroupError() {
    if (_type != 'multiple_choice') return null;
    final nonEmptyCount = _optionControllers
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    if (nonEmptyCount < 2) {
      return _fieldError('options') ?? 'At least 2 options are required';
    }
    if (_correctOptionIndex == null) {
      return _fieldError('correct_answer') ?? 'Select which option is correct';
    }
    return null;
  }

  bool get _isBusy {
    final provider = context.watch<OrganizationQuizProvider>();
    final existingId = widget.existing?.id;
    return provider.isCreatingQuestion ||
        (existingId != null && provider.isBusyQuestion(existingId));
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    final optionsError = _optionsGroupError();
    if (!isValid || optionsError != null) {
      setState(() {}); // Re-render so the options-group error becomes visible.
      return;
    }

    final provider = context.read<OrganizationQuizProvider>();

    final input = QuestionInput(
      prompt: _promptController.text.trim(),
      type: _type,
      options: _type == 'multiple_choice'
          ? _optionControllers.map((c) => c.text.trim()).toList()
          : null,
      correctAnswer: _type == 'multiple_choice'
          ? _optionControllers[_correctOptionIndex!].text.trim()
          : _trueFalseAnswer!,
      points: int.parse(_pointsController.text.trim()),
      position: int.tryParse(_positionController.text.trim()) ?? 0,
    );

    final existing = widget.existing;
    final success = existing == null
        ? await provider.createQuestion(input)
        : await provider.updateQuestion(questionId: existing.id, input: input);

    if (!mounted) return;

    if (!success) {
      setState(() {}); // Surface any backend field errors inline.
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationQuizProvider>();
    final isBusy = _isBusy;
    final optionsError = _optionsGroupError();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: _isEditing ? 'Edit Question' : 'Add Question',
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _promptController,
                label: 'Prompt',
                maxLines: 3,
                maxLength: 2000,
                enabled: !isBusy,
                validator: _promptValidator,
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                    value: 'multiple_choice',
                    child: Text('Multiple Choice'),
                  ),
                  DropdownMenuItem(
                    value: 'true_false',
                    child: Text('True / False'),
                  ),
                ],
                onChanged: isBusy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _type = value);
                      },
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              if (_type == 'multiple_choice') ...[
                Text('Options', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                RadioGroup<int>(
                  groupValue: _correctOptionIndex,
                  onChanged: (value) {
                    if (isBusy) return;
                    setState(() => _correctOptionIndex = value);
                  },
                  child: Column(
                    children: [
                      for (var i = 0; i < _optionControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              Radio<int>(value: i),
                              Expanded(
                                child: AppTextField(
                                  controller: _optionControllers[i],
                                  label: 'Option ${i + 1}',
                                  enabled: !isBusy,
                                  validator: _optionValidator,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed:
                                    isBusy || _optionControllers.length <= 2
                                    ? null
                                    : () => _removeOption(i),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: isBusy ? null : _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Option'),
                  ),
                ),
                Text(
                  'Select the radio button next to the correct option.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else ...[
                Text(
                  'Correct Answer',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                RadioGroup<String>(
                  groupValue: _trueFalseAnswer,
                  onChanged: (value) {
                    if (isBusy) return;
                    setState(() => _trueFalseAnswer = value);
                  },
                  child: Column(
                    children: const [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'True',
                        title: Text('True'),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'False',
                        title: Text('False'),
                      ),
                    ],
                  ),
                ),
              ],
              if (optionsError != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  optionsError,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.red),
                ),
              ],
              const SizedBox(height: AppSpacing.inputSpacing),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _pointsController,
                      label: 'Points',
                      keyboardType: TextInputType.number,
                      enabled: !isBusy,
                      validator: _pointsValidator,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      controller: _positionController,
                      label: 'Position',
                      keyboardType: TextInputType.number,
                      enabled: !isBusy,
                      validator: _positionValidator,
                    ),
                  ),
                ],
              ),
              if (provider.actionErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: provider.actionErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: _isEditing ? 'Save Question' : 'Add Question',
                isLoading: isBusy,
                onPressed: isBusy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [QuestionFormSheet] for [existing] (edit) or a new question
/// (create). Returns `true` only if the question was successfully
/// created/updated.
Future<bool> showQuestionFormSheet(
  BuildContext context, {
  QuestionModel? existing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => QuestionFormSheet(existing: existing),
  );
  return result ?? false;
}
