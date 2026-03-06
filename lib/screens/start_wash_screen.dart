import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/box.dart';
import '../models/qr_box_payload.dart';
import 'qr_scan_screen.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/backend_error_message_service.dart';
import '../services/box_service.dart';
import '../services/loyalty_service.dart';
import '../services/wash_backend_gateway.dart';

class StartWashScreen extends StatefulWidget {
  const StartWashScreen({super.key});

  @override
  State<StartWashScreen> createState() => _StartWashScreenState();
}

class _StartWashScreenState extends State<StartWashScreen> {
  final TextEditingController _qrBoxController = TextEditingController();
  int? _selectedBoxNumber;
  String? _selectedQrSignature;
  int? _selectedAmount;
  BoxIdentificationMethod _identificationMethod =
      BoxIdentificationMethod.manual;
  PaymentStatus _paymentStatus = PaymentStatus.idle;
  bool _isSubmitting = false;
  bool _isToppingUp = false;
  String? _persistentErrorMessage;
  BackendGatewayException? _persistentBackendError;
  bool _isResolvingErrorAction = false;
  bool _manualBoxConfirmed = false;
  bool _useRewardSlot = false;
  String? _lastSelectionSyncFingerprint;
  bool _selectionSyncScheduled = false;

  final List<int> _amountOptions = const [5, 10, 15];

  Color _chipColorForBoxState(BoxState state) {
    switch (state) {
      case BoxState.available:
        return Colors.green.shade700;
      case BoxState.reserved:
        return Colors.blueGrey.shade700;
      case BoxState.active:
        return Colors.red.shade700;
      case BoxState.cleaning:
        return Colors.orange.shade700;
      case BoxState.outOfService:
        return Colors.grey.shade700;
    }
  }

  bool _isBoxStartable(WashBox box) => box.state == BoxState.available;

  WashBox? _findBoxByNumber(List<WashBox> boxes, int boxNumber) {
    for (final box in boxes) {
      if (box.number == boxNumber) {
        return box;
      }
    }
    return null;
  }

  int? _remainingSecondsOrNull(WashBox box) {
    final remainingSeconds = box.remainingSeconds;
    if (remainingSeconds != null) {
      return remainingSeconds < 0 ? 0 : remainingSeconds;
    }
    final remainingMinutes = box.remainingMinutes;
    if (remainingMinutes != null) {
      final minutes = remainingMinutes < 0 ? 0 : remainingMinutes;
      return minutes * 60;
    }
    return null;
  }

  int _secondsUntilAvailable(WashBox box) {
    if (box.state == BoxState.available) {
      return 0;
    }
    final remainingSeconds = _remainingSecondsOrNull(box);
    if (remainingSeconds != null) {
      return remainingSeconds;
    }
    switch (box.state) {
      case BoxState.active:
      case BoxState.cleaning:
        return 60 * 60;
      case BoxState.reserved:
        return 5 * 60;
      case BoxState.outOfService:
        return 24 * 60 * 60;
      case BoxState.available:
        return 0;
    }
  }

  int _availabilityPriority(BoxState state) {
    switch (state) {
      case BoxState.available:
        return 0;
      case BoxState.active:
      case BoxState.cleaning:
        return 1;
      case BoxState.reserved:
        return 2;
      case BoxState.outOfService:
        return 3;
    }
  }

  List<WashBox> _sortedBoxesForSelection(List<WashBox> boxes) {
    final sorted = List<WashBox>.from(boxes);
    sorted.sort((a, b) {
      final priorityCompare = _availabilityPriority(
        a.state,
      ).compareTo(_availabilityPriority(b.state));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      final etaCompare = _secondsUntilAvailable(
        a,
      ).compareTo(_secondsUntilAvailable(b));
      if (etaCompare != 0) {
        return etaCompare;
      }
      return a.number.compareTo(b.number);
    });
    return sorted;
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutesPart = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  String _availabilityLabelForBox(WashBox box) {
    switch (box.state) {
      case BoxState.available:
        return 'Sofort';
      case BoxState.active:
      case BoxState.cleaning:
        final remainingSeconds = _remainingSecondsOrNull(box);
        if (remainingSeconds != null) {
          return 'in ${_formatDuration(remainingSeconds)}';
        }
        return 'belegt';
      case BoxState.reserved:
        return 'reserviert';
      case BoxState.outOfService:
        return 'ausser Betrieb';
    }
  }

  String? _selectionBlockReasonForBox(WashBox? box) {
    if (box == null) {
      return 'Box nicht gefunden.';
    }
    switch (box.state) {
      case BoxState.available:
        return null;
      case BoxState.reserved:
        return 'aktuell reserviert';
      case BoxState.active:
        final remainingSeconds = _remainingSecondsOrNull(box);
        if (remainingSeconds != null) {
          return 'in Benutzung, frei in ${_formatDuration(remainingSeconds)}';
        }
        return 'in Benutzung';
      case BoxState.cleaning:
        final remainingSeconds = _remainingSecondsOrNull(box);
        if (remainingSeconds != null) {
          return 'Reinigung, frei in ${_formatDuration(remainingSeconds)}';
        }
        return 'Reinigung laeuft';
      case BoxState.outOfService:
        return 'ausser Betrieb';
    }
  }

  String _selectionSyncFingerprint(List<WashBox> boxes) {
    final buffer = StringBuffer()
      ..write('sel=')
      ..write(_selectedBoxNumber ?? -1)
      ..write('|id=')
      ..write(_identificationMethod.name);
    for (final box in boxes) {
      buffer
        ..write('|')
        ..write(box.number)
        ..write(':')
        ..write(box.state.name)
        ..write(':')
        ..write(box.remainingSeconds ?? -1)
        ..write(':')
        ..write(box.remainingMinutes ?? -1);
    }
    return buffer.toString();
  }

  void _selectManualBox(int boxNumber) {
    setState(() {
      _selectedBoxNumber = boxNumber;
      _selectedQrSignature = null;
      _identificationMethod = BoxIdentificationMethod.manual;
      _manualBoxConfirmed = false;
    });
    unawaited(
      context.read<BoxService>().rememberStartSelection(
        boxNumber: boxNumber,
        identificationMethod: BoxIdentificationMethod.manual,
      ),
    );
  }

  void _revalidateSelectionWithBoxes({
    required List<WashBox> boxes,
    bool persistSelection = true,
  }) {
    if (boxes.isEmpty) {
      return;
    }

    final sortedBoxes = _sortedBoxesForSelection(boxes);
    final recommendedBox = sortedBoxes.first;
    final selectedBox = _selectedBoxNumber == null
        ? null
        : _findBoxByNumber(boxes, _selectedBoxNumber!);

    if (_identificationMethod == BoxIdentificationMethod.qr) {
      // Keep QR-driven selection stable to avoid switching to a different box
      // than the one physically scanned by the user.
      if (selectedBox != null) {
        return;
      }
      setState(() {
        _selectedBoxNumber = recommendedBox.number;
        _selectedQrSignature = null;
        _identificationMethod = BoxIdentificationMethod.manual;
        _manualBoxConfirmed = false;
      });
      if (persistSelection) {
        unawaited(
          context.read<BoxService>().rememberStartSelection(
            boxNumber: recommendedBox.number,
            identificationMethod: BoxIdentificationMethod.manual,
          ),
        );
      }
      return;
    }

    if (selectedBox != null && _isBoxStartable(selectedBox)) {
      return;
    }

    if (selectedBox != null &&
        !_isBoxStartable(selectedBox) &&
        _manualBoxConfirmed) {
      setState(() {
        _manualBoxConfirmed = false;
      });
    }

    if (_selectedBoxNumber == recommendedBox.number) {
      return;
    }

    setState(() {
      _selectedBoxNumber = recommendedBox.number;
      _selectedQrSignature = null;
      _identificationMethod = BoxIdentificationMethod.manual;
      _manualBoxConfirmed = false;
    });
    if (persistSelection) {
      unawaited(
        context.read<BoxService>().rememberStartSelection(
          boxNumber: recommendedBox.number,
          identificationMethod: BoxIdentificationMethod.manual,
        ),
      );
    }
  }

  void _scheduleSelectionRevalidation(List<WashBox> boxes) {
    final fingerprint = _selectionSyncFingerprint(boxes);
    if (_lastSelectionSyncFingerprint == fingerprint ||
        _selectionSyncScheduled) {
      return;
    }
    _lastSelectionSyncFingerprint = fingerprint;
    _selectionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final latestBoxes = context.read<BoxService>().boxes;
      _revalidateSelectionWithBoxes(boxes: latestBoxes);
    });
  }

  Future<void> _syncLoyaltyFromBackendSessions() async {
    try {
      final boxService = context.read<BoxService>();
      final loyalty = context.read<LoyaltyService>();
      await boxService.syncRecentSessions(limit: 100);
      await loyalty.syncWithBackendIfAvailable();
    } catch (_) {
      // Keep screen responsive when session sync is temporarily unavailable.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final boxService = context.read<BoxService>();
      setState(() {
        _selectedBoxNumber = boxService.lastSelectedBoxNumber;
        _selectedAmount = boxService.lastSelectedAmountEuro;
        _identificationMethod = boxService.lastIdentificationMethod;
        _manualBoxConfirmed =
            boxService.lastIdentificationMethod == BoxIdentificationMethod.qr;
      });
      _revalidateSelectionWithBoxes(
        boxes: boxService.boxes,
        persistSelection: false,
      );
      final auth = context.read<AuthService>();
      final loyalty = context.read<LoyaltyService>();
      unawaited(auth.refreshProfileAndBalance().catchError((_) {}));
      unawaited(loyalty.syncWithBackendIfAvailable());
      unawaited(_syncLoyaltyFromBackendSessions());
    });
  }

  @override
  void dispose() {
    _qrBoxController.dispose();
    super.dispose();
  }

  void _simulateQrScan() {
    _parseAndSetQrPayload(_qrBoxController.text);
  }

  void _parseAndSetQrPayload(String rawPayload) {
    try {
      final payload = QrBoxPayload.parse(rawPayload);
      final selectedBox = context.read<BoxService>().getBoxByNumber(
        payload.boxNumber,
      );
      final blockReason = _selectionBlockReasonForBox(selectedBox);
      setState(() {
        _selectedBoxNumber = payload.boxNumber;
        _selectedQrSignature = payload.signature;
        _identificationMethod = BoxIdentificationMethod.qr;
        _manualBoxConfirmed = true;
      });
      context.read<BoxService>().rememberStartSelection(
        boxNumber: payload.boxNumber,
        identificationMethod: BoxIdentificationMethod.qr,
      );
      if (blockReason != null) {
        _showMessage('Box ${payload.boxNumber}: $blockReason');
      }
    } on FormatException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('QR konnte nicht gelesen werden.');
    }
  }

  Future<void> _scanWithCamera() async {
    final scannedRaw = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (!mounted || scannedRaw == null) {
      return;
    }
    _qrBoxController.text = scannedRaw;
    _parseAndSetQrPayload(scannedRaw);
  }

  Future<bool> _confirmRewardRedeem() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belohnung einloesen?'),
        content: const Text(
          'Du loest jetzt deinen 10-Minuten-Slot fuer die gewaehlte Box ein.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Einloesen'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _startWash() async {
    if (_selectedBoxNumber == null) {
      _showMessage('Bitte zuerst eine Box waehlen.');
      return;
    }
    if (!_useRewardSlot && _selectedAmount == null) {
      _showMessage('Bitte Betrag waehlen.');
      return;
    }
    if (_identificationMethod == BoxIdentificationMethod.manual &&
        !_manualBoxConfirmed) {
      _showMessage('Bitte bestaetige, dass du an der richtigen Box stehst.');
      return;
    }

    final boxService = context.read<BoxService>();
    final authService = context.read<AuthService>();
    final analytics = context.read<AnalyticsService>();
    final loyaltyService = context.read<LoyaltyService>();
    final selectedBox = boxService.getBoxByNumber(_selectedBoxNumber!);
    final selectedBoxBlockReason = _selectionBlockReasonForBox(selectedBox);
    if (selectedBoxBlockReason != null) {
      _showMessage('Box $_selectedBoxNumber: $selectedBoxBlockReason');
      return;
    }
    if (_useRewardSlot) {
      final confirmed = await _confirmRewardRedeem();
      if (!mounted || !confirmed) {
        return;
      }
    } else if (authService.hasAccount && _selectedAmount != null) {
      try {
        await authService.refreshProfileAndBalance();
      } catch (_) {
        // Continue with cached balance if refresh is temporarily unavailable.
      }
      if (_selectedAmount! > authService.profileBalanceEuro) {
        _showMessage('Nicht genug Guthaben. Bitte zuerst aufladen.');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _paymentStatus = PaymentStatus.pending;
    });

    try {
      if (_useRewardSlot) {
        await boxService.startRewardWashFlow(
          boxNumber: _selectedBoxNumber!,
          identificationMethod: _identificationMethod,
        );
      } else {
        await boxService.startWashFlow(
          boxNumber: _selectedBoxNumber!,
          euroAmount: _selectedAmount!,
          identificationMethod: _identificationMethod,
          qrSignature: _selectedQrSignature,
          onPaymentStatusChanged: (status) {
            if (!mounted) {
              return;
            }
            setState(() {
              _paymentStatus = status;
            });
          },
        );
      }
      if (!mounted) return;
      if (_useRewardSlot) {
        await loyaltyService.consumeRewardAuthoritative(
          boxNumber: _selectedBoxNumber!,
        );
        analytics.track(
          'reward_redeemed',
          properties: {'box': '$_selectedBoxNumber'},
        );
        if (!mounted) {
          return;
        }
      } else if (authService.hasAccount) {
        await loyaltyService.syncWithBackendIfAvailable();
        await authService.refreshProfileAndBalance();
        if (!mounted) {
          return;
        }
      }
      setState(() {
        _persistentBackendError = null;
        _persistentErrorMessage = null;
      });
      _showMessage(
        _useRewardSlot
            ? 'Belohnung eingeloest. Box $_selectedBoxNumber wurde fuer 10 min gestartet.'
            : 'Bezahlung bestaetigt. Box $_selectedBoxNumber wurde gestartet.',
      );
      Navigator.pop(context);
    } on StateError catch (e) {
      setState(() {
        _paymentStatus = PaymentStatus.failed;
      });
      _setPersistentError(e.message);
      analytics.track(
        'wash_start_failed_state',
        properties: {'box': '${_selectedBoxNumber ?? -1}', 'error': e.message},
      );
      _showMessage(e.message);
    } on BackendGatewayException catch (e) {
      final uiMessage = _mapBackendErrorToUiMessage(e);
      setState(() {
        _paymentStatus = PaymentStatus.failed;
      });
      _setPersistentError(uiMessage, backendError: e);
      analytics.track(
        'wash_start_failed_backend',
        properties: {
          'box': '${_selectedBoxNumber ?? -1}',
          'code': e.code.name,
          'error': e.message,
        },
      );
      _showMessage(uiMessage);
    } catch (e) {
      final uiMessage = 'Start fehlgeschlagen: $e';
      setState(() {
        _paymentStatus = PaymentStatus.failed;
      });
      _setPersistentError(uiMessage);
      analytics.track(
        'wash_start_failed_unknown',
        properties: {'box': '${_selectedBoxNumber ?? -1}', 'error': '$e'},
      );
      _showMessage(uiMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _mapBackendErrorToUiMessage(BackendGatewayException e) {
    return BackendErrorMessageService.mapForStartFlow(e);
  }

  String _formatEuro(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  Future<void> _topUpBalance(int amountEuro) async {
    if (_isToppingUp || _isSubmitting) {
      return;
    }
    setState(() {
      _isToppingUp = true;
    });
    try {
      final auth = context.read<AuthService>();
      final nextBalance = await auth.topUpBalance(amountEuro: amountEuro);
      if (!mounted) {
        return;
      }
      _showMessage(
        '$amountEuro EUR aufgeladen. Neues Guthaben: ${_formatEuro(nextBalance)} EUR',
      );
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage(
        'Aufladen aktuell nicht moeglich. Bitte in wenigen Sekunden erneut versuchen.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isToppingUp = false;
        });
      }
    }
  }

  Color _paymentColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.idle:
        return Colors.grey;
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.success:
        return Colors.green;
      case PaymentStatus.failed:
        return Colors.red;
    }
  }

  String _paymentLabel(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.idle:
        return 'Bereit';
      case PaymentStatus.pending:
        return 'In Pruefung';
      case PaymentStatus.success:
        return 'Bestaetigt';
      case PaymentStatus.failed:
        return 'Fehlgeschlagen';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setPersistentError(
    String message, {
    BackendGatewayException? backendError,
  }) {
    setState(() {
      _persistentErrorMessage = message;
      _persistentBackendError = backendError;
    });
  }

  void _clearPersistentError() {
    setState(() {
      _persistentErrorMessage = null;
      _persistentBackendError = null;
    });
  }

  Future<void> _runInlineErrorAction(Future<void> Function() action) async {
    if (_isResolvingErrorAction) {
      return;
    }
    setState(() {
      _isResolvingErrorAction = true;
    });
    try {
      await action();
    } catch (e) {
      _showMessage('Aktion fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingErrorAction = false;
        });
      }
    }
  }

  _InlineErrorAction? _buildInlineErrorAction({
    required AuthService authService,
    required BoxService boxService,
  }) {
    final error = _persistentBackendError;
    if (error == null) {
      return null;
    }

    switch (error.code) {
      case BackendErrorCode.insufficientBalance:
        if (authService.canTopUpBalance) {
          final topUpAmount = _selectedAmount ?? 5;
          return _InlineErrorAction(
            label: '+ $topUpAmount EUR aufladen',
            icon: Icons.account_balance_wallet_outlined,
            run: () async {
              await _topUpBalance(topUpAmount);
              _clearPersistentError();
            },
          );
        }
        return _InlineErrorAction(
          label: 'Betrag anpassen',
          icon: Icons.tune,
          run: () async {
            setState(() {
              _useRewardSlot = false;
              _selectedAmount = null;
            });
            _clearPersistentError();
            _showMessage('Bitte waehle einen niedrigeren Betrag.');
          },
        );
      case BackendErrorCode.unauthorized:
        return _InlineErrorAction(
          label: 'Neu einloggen',
          icon: Icons.login,
          run: () async {
            await authService.logout();
            if (!mounted) {
              return;
            }
            Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          },
        );
      case BackendErrorCode.boxUnavailable:
      case BackendErrorCode.reservationExpired:
        return _InlineErrorAction(
          label: 'Beste Box waehlen',
          icon: Icons.recommend_outlined,
          run: () async {
            _revalidateSelectionWithBoxes(boxes: boxService.boxes);
            _clearPersistentError();
          },
        );
      case BackendErrorCode.boxNotFound:
        return _InlineErrorAction(
          label: 'Boxen neu laden',
          icon: Icons.sync,
          run: () async {
            await boxService.refreshBoxesReadOnly();
            _revalidateSelectionWithBoxes(boxes: boxService.boxes);
            _clearPersistentError();
          },
        );
      case BackendErrorCode.backendUnavailable:
        return _InlineErrorAction(
          label: 'Jetzt synchronisieren',
          icon: Icons.sync_problem,
          run: () async {
            await boxService.forceSyncAllBoxes();
            _clearPersistentError();
          },
        );
      case BackendErrorCode.invalidSignature:
        return _InlineErrorAction(
          label: 'QR zuruecksetzen',
          icon: Icons.qr_code_2,
          run: () async {
            setState(() {
              _qrBoxController.clear();
              _selectedQrSignature = null;
              _identificationMethod = BoxIdentificationMethod.manual;
              _manualBoxConfirmed = false;
            });
            _revalidateSelectionWithBoxes(boxes: boxService.boxes);
            _clearPersistentError();
          },
        );
      case BackendErrorCode.invalidAmount:
        return _InlineErrorAction(
          label: 'Betrag neu waehlen',
          icon: Icons.payments_outlined,
          run: () async {
            setState(() {
              _useRewardSlot = false;
              _selectedAmount = null;
            });
            _clearPersistentError();
          },
        );
      case BackendErrorCode.noRewardAvailable:
        return _InlineErrorAction(
          label: 'Belohnung deaktivieren',
          icon: Icons.workspace_premium_outlined,
          run: () async {
            setState(() {
              _useRewardSlot = false;
              _paymentStatus = PaymentStatus.idle;
            });
            _clearPersistentError();
          },
        );
      case BackendErrorCode.forbidden:
        return _InlineErrorAction(
          label: 'Zur Startseite',
          icon: Icons.home_outlined,
          run: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
          },
        );
      case BackendErrorCode.sessionNotActive:
      case BackendErrorCode.invalidSessionId:
      case BackendErrorCode.unknown:
        return null;
    }
  }

  String _startActionLabel({
    required bool canSubmit,
    required String? selectedBoxBlockReason,
    required bool isSelectionMissing,
    required bool needsManualConfirmation,
    required bool hasInsufficientBalanceSelection,
  }) {
    if (_isSubmitting) {
      return 'Start wird vorbereitet...';
    }
    if (hasInsufficientBalanceSelection) {
      return 'Guthaben aufladen';
    }
    if (selectedBoxBlockReason != null) {
      return 'Box aktuell blockiert';
    }
    if (isSelectionMissing) {
      return 'Box und Betrag waehlen';
    }
    if (needsManualConfirmation) {
      return 'Box vor Ort bestaetigen';
    }
    if (canSubmit) {
      return '3) Zahlung bestaetigen und starten';
    }
    return 'Start aktuell nicht moeglich';
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final boxService = context.watch<BoxService>();
    final loyaltyService = context.watch<LoyaltyService>();
    final boxes = boxService.boxes;
    final sortedBoxes = _sortedBoxesForSelection(boxes);
    final recommendedBox = sortedBoxes.isEmpty ? null : sortedBoxes.first;
    _scheduleSelectionRevalidation(boxes);
    final selectedBox = _selectedBoxNumber == null
        ? null
        : boxService.getBoxByNumber(_selectedBoxNumber!);
    final selectedBoxBlockReason = _selectedBoxNumber == null
        ? null
        : _selectionBlockReasonForBox(selectedBox);
    final recommendationText = recommendedBox == null
        ? null
        : _isBoxStartable(recommendedBox)
        ? 'Vorauswahl: Box ${recommendedBox.number} ist sofort verfuegbar.'
        : recommendedBox.state == BoxState.outOfService
        ? 'Aktuell ist keine nutzbare Box verfuegbar.'
        : 'Aktuell keine sofort freie Box. Naechste: Box ${recommendedBox.number} (${_availabilityLabelForBox(recommendedBox)}).';
    final accountBalance = authService.profileBalanceEuro;
    final hasInsufficientBalanceSelection =
        authService.hasAccount &&
        !_useRewardSlot &&
        _selectedAmount != null &&
        _selectedAmount! > accountBalance;
    final canManualTopUp = authService.canTopUpBalance;
    final isSelectionMissing =
        _selectedBoxNumber == null ||
        (!_useRewardSlot && _selectedAmount == null);
    final needsManualConfirmation =
        _identificationMethod == BoxIdentificationMethod.manual &&
        _selectedBoxNumber != null &&
        !_manualBoxConfirmed;
    final canSubmit =
        !_isSubmitting &&
        !isSelectionMissing &&
        selectedBoxBlockReason == null &&
        !needsManualConfirmation &&
        !hasInsufficientBalanceSelection;
    final canUseReward =
        authService.hasAccount &&
        loyaltyService.hasRewardAvailable &&
        _selectedBoxNumber != null &&
        selectedBoxBlockReason == null;
    final rewardHintText = !loyaltyService.hasRewardAvailable
        ? 'Noch keine Belohnung verfuegbar.'
        : _selectedBoxNumber == null
        ? 'Waehle zuerst eine Box zum Einloesen.'
        : selectedBoxBlockReason != null
        ? 'Einloesen nicht moeglich: $selectedBoxBlockReason'
        : loyaltyService.rewardSlots > 0
        ? 'Verfuegbar: ${loyaltyService.rewardSlots} Reward-Slot(s), fuer die gewaehlte Box einloesbar.'
        : 'Belohnung verfuegbar: fuer die gewaehlte Box einloesbar.';
    final inlineErrorAction = _buildInlineErrorAction(
      authService: authService,
      boxService: boxService,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Waschvorgang starten')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (authService.isGuest)
            Card(
              color: Colors.teal.shade900,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Gastmodus aktiv. Mit Konto kannst du spaeter Historie und Bonusfunktionen nutzen.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/register');
                      },
                      child: const Text('Registrieren'),
                    ),
                  ],
                ),
              ),
            ),
          if (authService.hasAccount)
            Card(
              color: const Color(0xFF0F2D52),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guthaben: ${_formatEuro(accountBalance)} EUR',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      canManualTopUp
                          ? 'Schnell aufladen (Testmodus)'
                          : authService.hasAccount &&
                                authService.isCustomerAccount
                          ? 'Kunden-Aufladung ist aktuell deaktiviert.'
                          : 'Nur mit Konto verfuegbar.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (canManualTopUp) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [5, 10, 20].map((amount) {
                          return OutlinedButton(
                            onPressed: _isSubmitting || _isToppingUp
                                ? null
                                : () => _topUpBalance(amount),
                            child: Text('+ $amount EUR'),
                          );
                        }).toList(),
                      ),
                    ],
                    if (_isToppingUp)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              ),
            ),
          if (_persistentErrorMessage != null)
            Card(
              color: Colors.red.shade900,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _persistentErrorMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          onPressed: _clearPersistentError,
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                    if (inlineErrorAction != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('start_error_inline_action'),
                          onPressed: _isResolvingErrorAction
                              ? null
                              : () => _runInlineErrorAction(
                                  inlineErrorAction.run,
                                ),
                          icon: _isResolvingErrorAction
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(inlineErrorAction.icon),
                          label: Text(inlineErrorAction.label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const Text(
            '1) Box identifizieren',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _scanWithCamera,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Mit Kamera scannen'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qrBoxController,
            decoration: InputDecoration(
              labelText: 'QR-Payload manuell eingeben',
              hintText: 'z.B. glanzpunkt://box?box=3&sig=abc',
              suffixIcon: IconButton(
                onPressed: _simulateQrScan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Manueller Fallback'),
          const SizedBox(height: 8),
          if (recommendationText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                recommendationText,
                key: const ValueKey('start_box_recommendation'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: boxes.map((box) {
              final isBoxStartable = _isBoxStartable(box);
              final isSelected = _selectedBoxNumber == box.number;
              return ChoiceChip(
                key: ValueKey('start_box_chip_${box.number}'),
                label: Text(
                  'Box ${box.number} · ${_availabilityLabelForBox(box)}',
                ),
                selected: isSelected,
                selectedColor: _chipColorForBoxState(box.state),
                backgroundColor: Colors.white12,
                disabledColor: Colors.white10,
                labelStyle: TextStyle(
                  color: isBoxStartable || isSelected
                      ? Colors.white
                      : Colors.white60,
                ),
                onSelected: isBoxStartable
                    ? (_) => _selectManualBox(box.number)
                    : null,
              );
            }).toList(),
          ),
          if (!boxes.any(_isBoxStartable) && recommendedBox != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Hinweis: Aktuell ist keine sofort verfuegbare Box vorhanden. '
                'Schnellste Option: Box ${recommendedBox.number} (${_availabilityLabelForBox(recommendedBox)}).',
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          if (selectedBox != null) ...[
            const SizedBox(height: 10),
            Card(
              color: selectedBoxBlockReason == null
                  ? Colors.green.shade900
                  : Colors.orange.shade900,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(
                      selectedBoxBlockReason == null
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedBoxBlockReason == null
                            ? 'Box ${selectedBox.number} ist sofort startbar.'
                            : 'Box ${selectedBox.number}: $selectedBoxBlockReason',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (authService.hasAccount) ...[
            const SizedBox(height: 10),
            Card(
              color: _useRewardSlot ? Colors.amber.shade900 : Colors.white10,
              child: ListTile(
                leading: const Icon(Icons.workspace_premium),
                title: const Text('Belohnung einloesen (10 min Slot)'),
                subtitle: Text(rewardHintText),
                trailing: Switch(
                  key: const ValueKey('reward_slot_switch'),
                  value: _useRewardSlot,
                  onChanged: canUseReward
                      ? (value) {
                          setState(() {
                            _useRewardSlot = value;
                            if (value) {
                              _selectedAmount = null;
                              _paymentStatus = PaymentStatus.success;
                            } else {
                              _paymentStatus = PaymentStatus.idle;
                            }
                          });
                        }
                      : null,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_identificationMethod == BoxIdentificationMethod.manual &&
              _selectedBoxNumber != null) ...[
            CheckboxListTile(
              value: _manualBoxConfirmed,
              onChanged: (value) {
                setState(() {
                  _manualBoxConfirmed = value ?? false;
                });
              },
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Ich stehe an Box $_selectedBoxNumber',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Pflicht bei manueller Auswahl, um Fehlstarts zu vermeiden.',
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Erkannt via: ${_identificationMethod == BoxIdentificationMethod.qr ? 'QR' : 'Manuell'}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Payment: '),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _paymentColor(_paymentStatus),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _paymentLabel(_paymentStatus),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            boxService.lastSyncErrorMessage != null
                ? 'Backend-Sync: Fehler'
                : boxService.lastSuccessfulSyncAt == null
                ? 'Backend-Sync: noch nicht erfolgt'
                : 'Backend-Sync: ok',
            style: TextStyle(
              color: boxService.lastSyncErrorMessage != null
                  ? Colors.redAccent
                  : Colors.white70,
            ),
          ),
          if (_persistentErrorMessage != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isSubmitting ? null : _startWash,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            '2) Betrag waehlen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (authService.hasAccount)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Verfuegbar: ${_formatEuro(accountBalance)} EUR',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          const SizedBox(height: 8),
          if (!_useRewardSlot)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _amountOptions.map((amount) {
                final blockedByBalance =
                    authService.hasAccount && amount > accountBalance;
                return ChoiceChip(
                  label: Text('$amount EUR'),
                  selected: _selectedAmount == amount,
                  onSelected: blockedByBalance
                      ? null
                      : (_) {
                          setState(() {
                            _selectedAmount = amount;
                          });
                          context.read<BoxService>().rememberStartSelection(
                            amountEuro: amount,
                          );
                        },
                );
              }).toList(),
            )
          else
            const Text(
              'Belohnung aktiv: Der 10-Minuten-Slot ersetzt die Bezahlung.',
              style: TextStyle(color: Colors.amber),
            ),
          if (hasInsufficientBalanceSelection)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Ausgewaehlter Betrag ist hoeher als dein Guthaben.',
                style: TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: canSubmit ? _startWash : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
              _startActionLabel(
                canSubmit: canSubmit,
                selectedBoxBlockReason: selectedBoxBlockReason,
                isSelectionMissing: isSelectionMissing,
                needsManualConfirmation: needsManualConfirmation,
                hasInsufficientBalanceSelection:
                    hasInsufficientBalanceSelection,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedAmount != null)
            Text(
              'Voraussichtliche Laufzeit: ${boxService.amountToMinutes(_selectedAmount!)} min',
              style: const TextStyle(color: Colors.white70),
            ),
          if (_useRewardSlot)
            const Text(
              'Voraussichtliche Laufzeit: 10 min (Belohnung)',
              style: TextStyle(color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

class _InlineErrorAction {
  final String label;
  final IconData icon;
  final Future<void> Function() run;

  const _InlineErrorAction({
    required this.label,
    required this.icon,
    required this.run,
  });
}
