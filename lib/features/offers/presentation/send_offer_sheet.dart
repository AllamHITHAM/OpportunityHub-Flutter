import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/organization_offer_provider.dart';
import '../data/send_offer_input.dart';
import 'offer_display.dart';

/// A modal bottom sheet for sending the one Offer an eligible application
/// may receive. Only ever shown for an `in_assessment` application with a
/// completed Assessment and no existing Offer — see
/// `_StatusActionsSection` in `organization_application_details_screen.dart`
/// for the eligibility gate. There is no edit/resend counterpart — once
/// sent, an Offer is immutable in v1.
class SendOfferSheet extends StatefulWidget {
  const SendOfferSheet({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<SendOfferSheet> createState() => _SendOfferSheetState();
}

class _SendOfferSheetState extends State<SendOfferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _salaryAmountController = TextEditingController();
  final _salaryCurrencyController = TextEditingController();
  final _startDateDisplayController = TextEditingController();
  final _messageController = TextEditingController();

  String? _salaryPeriod;
  DateTime? _startDate;

  @override
  void initState() {
    super.initState();
    // A previous, unrelated failed attempt on this same provider instance
    // must never bleed into a freshly-opened sheet — matches
    // ScheduleInterviewScreen's identical reasoning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationOfferProvider>().clearActionErrors();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _salaryAmountController.dispose();
    _salaryCurrencyController.dispose();
    _startDateDisplayController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _hasSalaryAmount => _salaryAmountController.text.trim().isNotEmpty;

  String? _fieldError(String field) {
    final provider = context.read<OrganizationOfferProvider>();
    final messages = provider.fieldErrors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  String? _titleValidator(String? value) {
    final backendError = _fieldError('title');
    if (backendError != null) return backendError;
    if ((value?.trim().length ?? 0) > 255) {
      return 'Title must be 255 characters or fewer';
    }
    return null;
  }

  String? _salaryAmountValidator(String? value) {
    final backendError = _fieldError('salary_amount');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      return 'Enter a valid amount of 0 or more';
    }
    return null;
  }

  String? _salaryCurrencyValidator(String? value) {
    final backendError = _fieldError('salary_currency');
    if (backendError != null) return backendError;
    if (!_hasSalaryAmount) return null;
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Currency is required when a salary amount is set';
    }
    if (text.length > 10) return 'Currency must be 10 characters or fewer';
    return null;
  }

  String? _salaryPeriodValidator(String? _) {
    final backendError = _fieldError('salary_period');
    if (backendError != null) return backendError;
    if (_hasSalaryAmount && _salaryPeriod == null) {
      return 'Select a salary period when a salary amount is set';
    }
    return null;
  }

  String? _messageValidator(String? value) {
    final backendError = _fieldError('message');
    if (backendError != null) return backendError;
    if ((value?.trim().length ?? 0) > 2000) {
      return 'Message must be 2000 characters or fewer';
    }
    return null;
  }

  Future<void> _pickStartDate(bool isBusy) async {
    if (isBusy) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _startDate != null && !_startDate!.isBefore(today)
        ? _startDate!
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      _startDateDisplayController.text = formatDate(picked);
    });
  }

  void _clearStartDate() {
    setState(() {
      _startDate = null;
      _startDateDisplayController.clear();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Send Offer',
      message:
          'Are you sure you want to send this offer? The candidate will be '
          'able to accept or decline it.',
      confirmLabel: 'Send Offer',
      type: AppConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;

    final provider = context.read<OrganizationOfferProvider>();

    final input = SendOfferInput(
      title: _titleController.text,
      salaryAmount: _hasSalaryAmount
          ? double.tryParse(_salaryAmountController.text.trim())
          : null,
      salaryCurrency: _hasSalaryAmount ? _salaryCurrencyController.text : null,
      salaryPeriod: _hasSalaryAmount ? _salaryPeriod : null,
      startDate: _startDate,
      message: _messageController.text,
    );

    final success = await provider.sendOffer(
      applicationId: widget.applicationId,
      input: input,
    );
    if (!mounted) return;

    if (!success) {
      // Re-run validation so any backend field errors surface inline
      // immediately, without waiting for the next field interaction —
      // matches ScheduleInterviewScreen's identical pattern.
      _formKey.currentState?.validate();
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOfferProvider>();
    final isBusy = provider.isSending;
    final hasFieldErrors = provider.fieldErrors.isNotEmpty;

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
              const SectionHeader(title: 'Send Offer'),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _titleController,
                label: 'Title (optional)',
                maxLength: 255,
                enabled: !isBusy,
                textInputAction: TextInputAction.next,
                validator: _titleValidator,
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _salaryAmountController,
                label: 'Salary Amount (optional)',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !isBusy,
                textInputAction: TextInputAction.next,
                validator: _salaryAmountValidator,
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _salaryCurrencyController,
                label: 'Salary Currency',
                hint: 'e.g. USD',
                maxLength: 10,
                enabled: !isBusy,
                textInputAction: TextInputAction.next,
                validator: _salaryCurrencyValidator,
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              DropdownButtonFormField<String>(
                initialValue: _salaryPeriod,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Salary Period'),
                items: [
                  for (final entry in salaryPeriodLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: isBusy
                    ? null
                    : (value) => setState(() => _salaryPeriod = value),
                validator: _salaryPeriodValidator,
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              GestureDetector(
                key: const Key('startDateField'),
                onTap: () => _pickStartDate(isBusy),
                child: AbsorbPointer(
                  child: AppTextField(
                    controller: _startDateDisplayController,
                    label: 'Start Date (optional)',
                    hint: 'Select a date',
                    readOnly: true,
                    enabled: !isBusy,
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
              ),
              if (_startDate != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: isBusy ? null : _clearStartDate,
                    child: const Text('Clear start date'),
                  ),
                ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _messageController,
                label: 'Message (optional)',
                maxLines: 4,
                maxLength: 2000,
                enabled: !isBusy,
                textInputAction: TextInputAction.newline,
                validator: _messageValidator,
              ),
              if (!hasFieldErrors && provider.actionErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: provider.actionErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Once sent, this offer cannot be edited, cancelled, or '
                'resent.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Send Offer',
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

/// Shows [SendOfferSheet] for [applicationId]. Returns `true` only if the
/// Offer was successfully sent.
Future<bool> showSendOfferSheet(
  BuildContext context, {
  required int applicationId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SendOfferSheet(applicationId: applicationId),
  );
  return result ?? false;
}
