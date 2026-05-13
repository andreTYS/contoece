import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message_model.dart';
import '../theme/app_theme.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: isUser ? _buildUserMessage() : _buildAiMessage(context),
    );
  }

  // ─── Mensaje del usuario ──────────────────────────────────────────────────
  Widget _buildUserMessage() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryRed,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              message.content,
              style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Mensaje de la IA ────────────────────────────────────────────────────
  Widget _buildAiMessage(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar IA
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(
            color: AppTheme.black,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.silver, width: 1.5),
          ),
          child: const Center(
            child: Text('IA',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Burbuja
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: message.isLoading
                    ? _buildTyping()
                    : MarkdownBody(
                        data: message.content,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(color: AppTheme.textDark, fontSize: 14.5, height: 1.6),
                          strong: const TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold),
                          code: const TextStyle(
                            backgroundColor: Color(0xFFF3F4F6),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: AppTheme.lightBlue,
                            borderRadius: BorderRadius.circular(4),
                            border: const Border(left: BorderSide(color: AppTheme.primaryRed, width: 3)),
                          ),
                          listBullet: const TextStyle(color: AppTheme.primaryRed),
                          h2: const TextStyle(
                              color: AppTheme.textDark, fontWeight: FontWeight.w700, fontSize: 16),
                          h3: const TextStyle(
                              color: AppTheme.textDark, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
              ),
              // Fuentes citadas
              if (message.sources.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildSources(),
              ],
              const SizedBox(height: 2),
              Text(
                _formatTime(message.timestamp),
                style: const TextStyle(fontSize: 10, color: AppTheme.textGray),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSources() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book, size: 12, color: AppTheme.textGray),
          SizedBox(width: 3),
          Text('Fuentes:', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
        ]),
        ...message.sources.take(4).map((s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryRed.withOpacity(0.25)),
          ),
          child: Text(s,
              style: const TextStyle(fontSize: 11, color: AppTheme.primaryRed),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        )),
      ],
    );
  }

  Widget _buildTyping() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _Dot(delay: 0), const SizedBox(width: 4),
      _Dot(delay: 180), const SizedBox(width: 4),
      _Dot(delay: 360),
    ]);
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

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
    _ctrl = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.primaryRed.withOpacity(0.3 + 0.7 * _anim.value),
        ),
      ),
    );
  }
}
