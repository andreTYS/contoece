import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message_model.dart';
import '../theme/app_theme.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: widget.message.role == MessageRole.user
          ? const Offset(0.06, 0)
          : const Offset(-0.06, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 14),
          child: isUser
              ? _buildUserMessage()
              : _buildAiMessage(context),
        ),
      ),
    );
  }

  // ─── User message ─────────────────────────────────────────────────────────

  Widget _buildUserMessage() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: GestureDetector(
            onLongPress: _copyToClipboard,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryRed, AppTheme.darkRed],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.primaryRed.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Text(
                widget.message.content,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14.5, height: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Padding(
          padding: EdgeInsets.only(bottom: 2),
          child: _UserAvatar(),
        ),
      ],
    );
  }

  // ─── AI message ───────────────────────────────────────────────────────────

  Widget _buildAiMessage(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 10),
          child: _AiAvatar(),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label
              if (!widget.message.isLoading)
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 4),
                  child: Text('OECE-IA',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textGray,
                          letterSpacing: 0.8)),
                ),
              // Bubble
              GestureDetector(
                onLongPress: widget.message.isLoading ? null : _copyToClipboard,
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.74),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: AppTheme.lightSilver),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: widget.message.isLoading
                      ? _buildTyping()
                      : MarkdownBody(
                          data: widget.message.content,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                                color: AppTheme.textDark,
                                fontSize: 14.5,
                                height: 1.65),
                            strong: const TextStyle(
                                color: AppTheme.primaryRed,
                                fontWeight: FontWeight.bold),
                            em: const TextStyle(
                                color: AppTheme.textDark,
                                fontStyle: FontStyle.italic),
                            code: const TextStyle(
                              backgroundColor: Color(0xFFF3F4F6),
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Color(0xFF1F2937),
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppTheme.lightSilver),
                            ),
                            blockquoteDecoration: BoxDecoration(
                              color: const Color(0xFFFFF3EA),
                              borderRadius: BorderRadius.circular(4),
                              border: const Border(
                                  left: BorderSide(
                                      color: AppTheme.primaryRed,
                                      width: 3)),
                            ),
                            blockquote: const TextStyle(
                                color: AppTheme.textDark, fontSize: 14),
                            listBullet: const TextStyle(
                                color: AppTheme.primaryRed),
                            h1: const TextStyle(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 18),
                            h2: const TextStyle(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 16),
                            h3: const TextStyle(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                            tableHead: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark),
                            tableBody: const TextStyle(
                                color: AppTheme.textDark, fontSize: 13.5),
                          ),
                        ),
                ),
              ),
              // Sources
              if (widget.message.sources.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildSources(),
              ],
              const SizedBox(height: 3),
              // Timestamp + copy hint
              Row(children: [
                Text(
                  _formatTime(widget.message.timestamp),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textGray),
                ),
                if (!widget.message.isLoading) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _copyToClipboard,
                    child: const Icon(Icons.copy_rounded,
                        size: 12, color: AppTheme.lightSilver),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Sources ──────────────────────────────────────────────────────────────

  Widget _buildSources() {
    final uniqueSources = widget.message.sources.toSet().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.menu_book_rounded, size: 11, color: AppTheme.textGray),
          const SizedBox(width: 4),
          Text('${uniqueSources.length} fuente${uniqueSources.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textGray,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: uniqueSources.take(5).mapIndexed((i, s) => _buildSourceChip(i + 1, s)).toList(),
        ),
      ],
    );
  }

  Widget _buildSourceChip(int index, String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3EA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryRed.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppTheme.primaryRed,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$index',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            source.replaceAll(RegExp(r'\.\w+$'), ''),
            style: const TextStyle(
                fontSize: 11,
                color: AppTheme.primaryRed,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  // ─── Typing indicator ─────────────────────────────────────────────────────

  Widget _buildTyping() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _Dot(delay: 0), const SizedBox(width: 4),
      _Dot(delay: 200), const SizedBox(width: 4),
      _Dot(delay: 400),
    ]);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copiado al portapapeles'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ─── Avatars ───────────────────────────────────────────────────────────────────

class _AiAvatar extends StatelessWidget {
  const _AiAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 33,
      height: 33,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.black, Color(0xFF1A4B8C)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.silver, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: const Center(
        child: Text('IA',
            style: TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: AppTheme.silver,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person_rounded, color: Colors.white, size: 15),
    );
  }
}

// ─── Typing dot animation ──────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 550), vsync: this);
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              AppTheme.primaryRed.withOpacity(0.25 + 0.75 * _anim.value),
        ),
      ),
    );
  }
}

// ─── Extension helper ──────────────────────────────────────────────────────────

extension _IndexedMap<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T element) f) sync* {
    var i = 0;
    for (final e in this) yield f(i++, e);
  }
}
