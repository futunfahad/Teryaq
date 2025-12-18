import 'dart:convert';
import 'dart:ui' as ui; // ✅ fix for TextDirection.ltr
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';

const String kChatApiUrl = "http://192.168.8.113:7860/chat";
const Color kUserColor = Color(0xFFD5F7FF);
const Color kAiColor = Color(0xFFE0E0E0);

class ChatBotPage extends StatefulWidget {
  const ChatBotPage({super.key});

  @override
  State<ChatBotPage> createState() => _ChatBotPageState();
}

class _ChatBotPageState extends State<ChatBotPage> {
  final _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isThinking = false;

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isThinking) return;

    setState(() {
      _messages.add({'text': text, 'isUser': true});
      _controller.clear();
      _isThinking = true;
    });

    try {
      final res = await http.post(
        Uri.parse(kChatApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"message": text}),
      );

      final reply =
          jsonDecode(res.body)["response"] ?? "fallback_no_understand".tr();
      setState(() {
        _messages.add({'text': reply, 'isUser': false});
        _isThinking = false;
      });
    } catch (_) {
      setState(() {
        _messages.add({'text': "error_connection".tr(), 'isUser': false});
        _isThinking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "chatbot_title".tr(),
          showBackButton: true,
          onBackTap: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isThinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (_isThinking && i == _messages.length) {
                  return _thinkingBubble();
                }
                final msg = _messages[i];
                return msg["isUser"]
                    ? _userBubble(msg["text"], maxWidth)
                    : _aiBubble(msg["text"], maxWidth);
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: "chat_input_hint".tr(),
                filled: true,
                fillColor: const Color(0xFFF2F2F2),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.buttonBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _userBubble(String text, double maxWidth) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: const BoxDecoration(
          color: kUserColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _aiBubble(String text, double maxWidth) {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.buttonBlue,
            child: Icon(Icons.smart_toy, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: kAiColor,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thinkingBubble() {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.buttonBlue,
            child: Icon(Icons.smart_toy, size: 18, color: Colors.white),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }
}
