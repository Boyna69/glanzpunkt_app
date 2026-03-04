import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/loyalty_service.dart';

class LoyaltyScreen extends StatelessWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final loyalty = context.watch<LoyaltyService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Stempelkarte')),
      body: auth.isGuest
          ? _GuestLoyaltyGate()
          : _LoyaltyContent(
              completed: loyalty.completed,
              rewardSlots: loyalty.rewardSlots,
              goal: loyalty.goal,
              progress: loyalty.progress,
              remainingUntilReward: loyalty.remainingUntilReward,
              redemptions: loyalty.recentRewardRedemptions(limit: 6),
            ),
    );
  }
}

class _GuestLoyaltyGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Die Stempelkarte ist nur fuer Kontonutzer verfuegbar.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/register'),
              child: const Text('Konto erstellen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoyaltyContent extends StatelessWidget {
  final int completed;
  final int rewardSlots;
  final int goal;
  final double progress;
  final int remainingUntilReward;
  final List<RewardRedemptionRecord> redemptions;

  const _LoyaltyContent({
    required this.completed,
    required this.rewardSlots,
    required this.goal,
    required this.progress,
    required this.remainingUntilReward,
    required this.redemptions,
  });

  String _formatTimestamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF112640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deine Stempelkarte',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text('Fortschritt: $completed/$goal'),
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0, end: progress),
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      key: const ValueKey('loyalty_progress'),
                      minHeight: 12,
                      value: value,
                      borderRadius: BorderRadius.circular(999),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  remainingUntilReward == 0
                      ? rewardSlots > 0
                            ? 'Belohnung verfuegbar: $rewardSlots Slot(s)'
                            : 'Belohnung verfuegbar: Gratiswaesche'
                      : 'Noch $remainingUntilReward Waeschen bis zur Belohnung',
                  style: TextStyle(
                    color: remainingUntilReward == 0
                        ? Colors.amber.shade300
                        : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _StampGrid(completed: completed, goal: goal),
        if (remainingUntilReward == 0) ...[
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 500),
            tween: Tween<double>(begin: 0.92, end: 1),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              key: const ValueKey('reward_highlight_card'),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9D6F00), Color(0xFFE5B84D)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.3),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.workspace_premium, color: Colors.white),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Belohnung freigeschaltet: 1 Gratiswaesche',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Card(
          color: const Color(0xFF0E223B),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verbrauchte Belohnungen',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (redemptions.isEmpty)
                  const Text(
                    'Noch keine Belohnung eingeloest.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ...redemptions.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Box ${entry.boxNumber} • ${_formatTimestamp(entry.redeemedAt)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Card(
          color: Color(0xFF0E223B),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Stempel werden automatisch nach erfolgreichem Wasch-Start gesammelt.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }
}

class _StampGrid extends StatelessWidget {
  final int completed;
  final int goal;

  const _StampGrid({required this.completed, required this.goal});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 850),
      tween: Tween<double>(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, revealProgress, _) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List<Widget>.generate(goal, (index) {
            final slot = index + 1;
            final isFilled = slot <= completed;
            final slotStart = (index / goal) * 0.45;
            final slotProgress =
                ((revealProgress - slotStart) / (1 - slotStart))
                    .clamp(0, 1)
                    .toDouble();
            return Transform.scale(
              scale: 0.9 + (0.1 * slotProgress),
              child: Opacity(
                opacity: slotProgress,
                child: AnimatedContainer(
                  key: ValueKey('stamp_slot_$slot'),
                  duration: const Duration(milliseconds: 350),
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? Colors.teal : Colors.white10,
                    border: Border.all(
                      color: isFilled ? Colors.tealAccent : Colors.white24,
                      width: 2,
                    ),
                    boxShadow: isFilled
                        ? [
                            BoxShadow(
                              color: Colors.tealAccent.withValues(alpha: 0.22),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isFilled
                        ? const Icon(Icons.check, color: Colors.white)
                        : Text(
                            '$slot',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
