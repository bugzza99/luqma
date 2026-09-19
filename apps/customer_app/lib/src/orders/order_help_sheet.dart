import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// What the customer decided in the assistant, for the order screen to carry out.
sealed class HelpOutcome {
  const HelpOutcome();
}

/// Cancel the order — the order screen asks once more, as it always has.
final class CancelRequested extends HelpOutcome {
  const CancelRequested();
}

/// Send a ticket to the Luqma team.
final class ComplaintWritten extends HelpOutcome {
  const ComplaintWritten(this.text);

  final String text;
}

/// «مساعد لقمة» — the complaints assistant, as a conversation.
///
/// Rules, not a model: the customer picks what went wrong, and the answer is read off the
/// order they are looking at by [OrderHelper]. Anything it cannot settle becomes an
/// ordinary ticket for a person — the assistant never closes a complaint by itself.
class OrderHelpSheet extends ConsumerStatefulWidget {
  const OrderHelpSheet({super.key, required this.order, this.shopPhone});

  final Order order;

  /// The shop's number when it is known; «كلّم المطعم» is offered only with one.
  final String? shopPhone;

  static Key topicKey(HelpTopic topic) => Key('help.topic.${topic.name}');
  static Key actionKey(HelpAction action) => Key('help.action.${action.name}');

  @override
  ConsumerState<OrderHelpSheet> createState() => _OrderHelpSheetState();
}

class _Bubble {
  const _Bubble(this.text, {required this.mine});

  final String text;
  final bool mine;
}

class _OrderHelpSheetState extends ConsumerState<OrderHelpSheet> {
  final _typed = TextEditingController();
  final _scroll = ScrollController();
  final _bubbles = <_Bubble>[];
  HelpTopic? _topic;
  List<HelpAction> _actions = const [];
  bool _writing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bubbles.add(_Bubble(
      'أهلاً، أنا مساعد لقمة. إيه اللي حصل في طلب #${widget.order.orderNumber}؟',
      mine: false,
    ));
  }

  @override
  void dispose() {
    _typed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pick(HelpTopic topic) {
    final strings = LuqmaStrings.of(context);
    final reply = OrderHelper.answer(
      topic,
      widget.order,
      ref.read(clockProvider)(),
      money: strings.amount,
    );
    setState(() {
      _topic = topic;
      _error = null;
      _bubbles
        ..add(_Bubble(OrderHelper.label(topic), mine: true))
        ..add(_Bubble(reply.text, mine: false));
      _actions = [
        for (final action in reply.actions)
          if (action != HelpAction.callShop || _hasPhone) action,
      ];
      // «حاجة تانية» has nothing to answer: it goes straight to the words.
      _writing = topic == HelpTopic.other;
    });
    _toBottom();
  }

  bool get _hasPhone => (widget.shopPhone ?? '').trim().isNotEmpty;

  Future<void> _act(HelpAction action) async {
    switch (action) {
      case HelpAction.cancelOrder:
        Navigator.of(context).pop(const CancelRequested());
      case HelpAction.callShop:
        final opened = await ref
            .read(externalLinksProvider)
            .open(Uri(scheme: 'tel', path: widget.shopPhone!.trim()));
        if (!opened && mounted) {
          setState(() => _error = 'مش قادرين نفتح الاتصال. الرقم: ${widget.shopPhone}');
        }
      case HelpAction.complain:
        setState(() {
          _writing = true;
          _bubbles.add(const _Bubble(
            'اكتب اللي حصل بالتفصيل وفريق لقمة هيراجعه ويرد عليك.',
            mine: false,
          ));
        });
        _toBottom();
      case HelpAction.done:
        Navigator.of(context).pop();
    }
  }

  void _send() {
    final topic = _topic ?? HelpTopic.other;
    final typed = _typed.text.trim();
    // «حاجة تانية» with nothing typed tells an admin nothing; every other topic at least
    // says what it is about.
    if (topic == HelpTopic.other && typed.isEmpty) {
      setState(() => _error = 'اكتب اللي حصل الأول');
      return;
    }
    Navigator.of(context).pop(ComplaintWritten(OrderHelper.complaintText(topic, typed)));
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _actionLabel(HelpAction action) => switch (action) {
        HelpAction.cancelOrder => 'ألغِ الطلب',
        HelpAction.callShop => 'كلّم المطعم',
        HelpAction.complain => 'ابعت لفريق لقمة',
        HelpAction.done => 'تمام، شكراً',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.md,
                  Space.gutter,
                  Space.sm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.support_agent_rounded, color: colors.brand),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text('مساعد لقمة', style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'اقفل',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.hairline),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(Space.gutter),
                  children: [
                    for (final bubble in _bubbles) _BubbleView(bubble: bubble),
                    if (_topic == null) ...[
                      const SizedBox(height: Space.sm),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final topic in HelpTopic.values)
                            ActionChip(
                              key: OrderHelpSheet.topicKey(topic),
                              label: Text(OrderHelper.label(topic)),
                              onPressed: () => _pick(topic),
                            ),
                        ],
                      ),
                    ] else if (!_writing) ...[
                      const SizedBox(height: Space.sm),
                      for (final action in _actions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: action == HelpAction.complain ||
                                  action == HelpAction.cancelOrder
                              ? FilledButton(
                                  key: OrderHelpSheet.actionKey(action),
                                  onPressed: () => _act(action),
                                  style: FilledButton.styleFrom(
                                    minimumSize:
                                        const Size.fromHeight(Sizes.minTarget),
                                  ),
                                  child: Text(_actionLabel(action)),
                                )
                              : OutlinedButton(
                                  key: OrderHelpSheet.actionKey(action),
                                  onPressed: () => _act(action),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize:
                                        const Size.fromHeight(Sizes.minTarget),
                                  ),
                                  child: Text(_actionLabel(action)),
                                ),
                        ),
                      TextButton(
                        key: const Key('help.again'),
                        onPressed: () => setState(() {
                          _topic = null;
                          _actions = const [];
                          _error = null;
                          _bubbles.add(const _Bubble('في حاجة تانية؟', mine: false));
                        }),
                        child: const Text('سؤال تاني'),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.danger),
                        ),
                      ),
                  ],
                ),
              ),
              if (_writing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    0,
                    Space.gutter,
                    Space.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('order.issueText'),
                        controller: _typed,
                        maxLines: 3,
                        maxLength: 300,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'الأكل وصل بارد، ناقص صنف، اتأخر…',
                        ),
                      ),
                      FilledButton(
                        key: const Key('order.sendIssue'),
                        onPressed: _send,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(Sizes.minTarget),
                        ),
                        child: const Text('ابعت'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleView extends StatelessWidget {
  const _BubbleView({required this.bubble});

  final _Bubble bubble;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    // RTL: the customer's own words sit at the start (right), the assistant's at the end.
    return Align(
      alignment: bubble.mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        decoration: BoxDecoration(
          color: bubble.mine ? colors.brand : colors.card,
          borderRadius: Radii.cardAll,
          border: bubble.mine ? null : Border.all(color: colors.hairline),
        ),
        child: Text(
          bubble.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: bubble.mine ? colors.onBrand : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
