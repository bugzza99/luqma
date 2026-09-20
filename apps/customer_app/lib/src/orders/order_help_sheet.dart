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

/// «زعتر» — the complaints assistant.
///
/// Every sentence in here comes from [OrderHelper], read off the order the customer is
/// looking at. What the server adds is *which* of the five topics a typed question is
/// about — the model may choose a topic and may do nothing else, so it cannot promise a
/// time, name a price or offer a button. When the server cannot be reached the topic is
/// read from the words on the phone instead and the customer is told so; the answer is
/// the same answer either way, because there is only one place it is written.
class OrderHelpSheet extends ConsumerStatefulWidget {
  const OrderHelpSheet({super.key, required this.order, this.shopPhone});

  final Order order;

  /// The shop's number when it is known; «كلّم المطعم» is offered only with one.
  final String? shopPhone;

  static Key topicKey(HelpTopic topic) => Key('help.topic.${topic.name}');
  static Key actionKey(HelpAction action) => Key('help.action.${action.name}');
  static const inputKey = Key('zaatar.input');
  static const sendKey = Key('zaatar.send');
  static const replyKey = Key('zaatar.reply');
  static const privacyNoticeKey = Key('zaatar.privacyNotice');

  @override
  ConsumerState<OrderHelpSheet> createState() => _OrderHelpSheetState();
}

class _Bubble {
  const _Bubble(
    this.text, {
    required this.mine,
    this.isReply = false,
    this.isNotice = false,
  });

  final String text;
  final bool mine;
  final bool isReply;
  final bool isNotice;
}

class _OrderHelpSheetState extends ConsumerState<OrderHelpSheet> {
  final _typed = TextEditingController();
  final _chatController = TextEditingController();
  final _scroll = ScrollController();
  final _bubbles = <_Bubble>[];

  HelpTopic? _topic;
  List<HelpAction> _actions = const [];
  bool _writing = false;
  bool _pending = false;
  bool _fallbackNoticeShown = false;
  String? _error;
  String _lastCustomerMessage = '';

  @override
  void initState() {
    super.initState();
    _bubbles.add(_Bubble(
      'أهلاً، أنا زعتر من لقمة. اسألني عن طلب #${widget.order.orderNumber} أو اختار من تحت',
      mine: false,
    ));
  }

  @override
  void dispose() {
    _typed.dispose();
    _chatController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _hasPhone => (widget.shopPhone ?? '').trim().isNotEmpty;

  /// The order as it is *now*, not as it was when the sheet opened.
  ///
  /// A conversation outlives a status: the customer asks «فين الأوردر» while the shop
  /// has not answered, the shop accepts while زعتر is thinking, and an answer built from
  /// the snapshot this sheet was handed says «لسه مردش» and offers a cancel the database
  /// will refuse. The order screen behind it is already a live listener; this reads the
  /// same provider rather than a copy taken at `showModalBottomSheet`.
  Order get _order =>
      ref.read(orderProvider(widget.order.id)).value ?? widget.order;

  void _pick(HelpTopic topic) {
    final strings = LuqmaStrings.of(context);
    final reply = OrderHelper.answer(
      topic,
      _order,
      ref.read(clockProvider)(),
      money: strings.amount,
    );

    setState(() {
      _topic = topic;
      _error = null;
      _bubbles
        ..add(_Bubble(OrderHelper.label(topic), mine: true))
        ..add(_Bubble(reply.text, mine: false, isReply: true));
      _actions = [
        for (final action in reply.actions)
          if (action != HelpAction.callShop || _hasPhone) action,
      ];
      // «حاجة تانية» has nothing to answer: it goes straight to the words.
      _writing = topic == HelpTopic.other;
      if (_writing) {
        _typed.text = '';
      }
    });
    _toBottom();
  }

  Future<void> _sendChat() async {
    final message = _chatController.text.trim();
    if (message.isEmpty || _pending) return;

    _chatController.clear();
    _lastCustomerMessage = message;

    setState(() {
      _error = null;
      _bubbles.add(_Bubble(message, mine: true));
      _pending = true;
      _actions = const [];
    });
    _toBottom();

    final result = await ref.read(zaatarRepositoryProvider).ask(
          orderId: widget.order.id,
          message: message,
        );

    if (!mounted) return;

    if (result case Ok(:final value)) {
      _render(value.topic);
    } else {
      // The server could not be reached, so the topic is read here instead. Saying so
      // matters: the rules answer from the order and cannot read a sentence the way the
      // model can, and a customer who is told nothing assumes they were understood.
      _render(
        ZaatarClassifier.read(message).topic,
        notice: 'زعتر بيرد من الردود الجاهزة دلوقتي',
      );
    }
    _toBottom();
  }

  /// The one place an answer is drawn, whoever chose the topic.
  void _render(HelpTopic topic, {String? notice}) {
    final strings = LuqmaStrings.of(context);
    final reply = OrderHelper.answer(
      topic,
      // The order as it is when the answer is written, which is not the order as it was
      // when the question was asked: the shop may have accepted in between.
      _order,
      ref.read(clockProvider)(),
      money: strings.amount,
    );

    setState(() {
      _topic = topic;
      _pending = false;
      if (notice != null && !_fallbackNoticeShown) {
        _fallbackNoticeShown = true;
        _bubbles.add(_Bubble(notice, mine: false, isNotice: true));
      }
      _bubbles.add(_Bubble(reply.text, mine: false, isReply: true));
      _actions = [
        for (final action in reply.actions)
          if (action != HelpAction.callShop || _hasPhone) action,
      ];
    });
  }

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
          _typed.text = _lastCustomerMessage;
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

  void _sendComplaint() {
    final topic = _topic ?? HelpTopic.other;
    final typed = _typed.text.trim();
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

  bool get _showChips => _topic == null && _actions.isEmpty && !_pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    // Followed live, so a shop accepting while this sheet is open reaches it. An answer
    // already on screen is a thing that was said and stays said; a *button* is an offer
    // made now, so «ألغِ الطلب» is withdrawn the moment the database would refuse it.
    final live = ref.watch(orderProvider(widget.order.id)).value ?? widget.order;
    final canCancel =
        live.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer);
    final actions = [
      for (final action in _actions)
        if (action != HelpAction.cancelOrder || canCancel) action,
    ];

    final lastReplyIndex = _bubbles.lastIndexWhere((b) => b.isReply);

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
                      child: Text('زعتر', style: theme.textTheme.titleLarge),
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
                    for (final (index, bubble) in _bubbles.indexed)
                      _BubbleView(
                        bubble: bubble,
                        isLatestReply: index == lastReplyIndex,
                      ),
                    if (_pending) const _TypingIndicatorBubble(),
                    if (_showChips) ...[
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
                    ] else if (!_writing && actions.isNotEmpty) ...[
                      const SizedBox(height: Space.sm),
                      for (final action in actions)
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
                        onPressed: _sendComplaint,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(Sizes.minTarget),
                        ),
                        child: const Text('ابعت'),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.xs,
                    Space.gutter,
                    Space.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'ماتكتبش بياناتك الشخصية هنا (رقمك أو عنوانك)',
                        key: OrderHelpSheet.privacyNoticeKey,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: Space.xs),
                      Row(children: [
                      Expanded(
                        child: TextField(
                          key: OrderHelpSheet.inputKey,
                          controller: _chatController,
                          maxLength: 500,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _pending ? null : (_) => _sendChat(),
                          decoration: const InputDecoration(
                            hintText: 'اسأل زعتر عن طلبك...',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      IconButton(
                        key: OrderHelpSheet.sendKey,
                        tooltip: 'ابعت لزعتر',
                        icon: const Icon(Icons.send_rounded),
                        color: colors.brand,
                        onPressed: _pending ? null : _sendChat,
                      ),
                      ]),
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

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Text(
          'زعتر بيكتب...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BubbleView extends StatelessWidget {
  const _BubbleView({required this.bubble, this.isLatestReply = false});

  final _Bubble bubble;
  final bool isLatestReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    if (bubble.isNotice) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Center(
          child: Text(
            bubble.text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      );
    }

    // RTL: the customer's own words sit at the start (right), the assistant's at the end.
    return Align(
      alignment: bubble.mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Container(
        key: isLatestReply ? OrderHelpSheet.replyKey : null,
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

