import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/config/app_config.dart';

class InvoiceChatScreen extends StatefulWidget {
  final Map<String, dynamic> extractedData;

  const InvoiceChatScreen({Key? key, required this.extractedData}) : super(key: key);

  @override
  State<InvoiceChatScreen> createState() => _InvoiceChatScreenState();
}

class _InvoiceChatScreenState extends State<InvoiceChatScreen> {
  final TextEditingController _queryController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  // Suggested questions
  final List<String> _suggestedQuestions = [
    "What is the total amount?",
    "Who is the vendor?",
    "What are the line items?",
    "What is the invoice number?",
    "What is the due date?",
    "Are there any missing fields?",
  ];

  @override
  void initState() {
    super.initState();
    // Add welcome message
    _messages.add(ChatMessage(
      text: "Hello! I can help you analyze this invoice. Ask me anything about the extracted data.",
      isUser: false,
    ));
  }

  Future<void> _sendMessage(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: query, isUser: true));
      _isLoading = true;
    });

    _queryController.clear();

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.apiBaseUrl}/chat/query'),
      );

      request.fields['query'] = query;
      request.fields['extracted_data'] = jsonEncode(widget.extractedData);

      final response = await request.send().timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseBody);

        setState(() {
          _messages.add(ChatMessage(
            text: jsonResponse['answer'] ?? "No response received",
            isUser: false,
          ));
        });
      } else {
        setState(() {
          _messages.add(ChatMessage(
            text: "Error: Server returned ${response.statusCode}",
            isUser: false,
          ));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: "Error: ${e.toString()}",
          isUser: false,
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Analysis Chat'),
        backgroundColor: Colors.blue[700],
      ),
      body: Column(
        children: [
          // Suggested questions
          if (_messages.length <= 2)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Suggested Questions:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedQuestions.map((question) {
                      return ElevatedButton(
                        onPressed: () => _sendMessage(question),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[50],
                          foregroundColor: Colors.blue[900],
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: Colors.blue[200]!),
                          ),
                        ),
                        child: Text(question),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          // Chat messages
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(message: message);
              },
            ),
          ),
          // Input field
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      hintText: 'Ask about the invoice...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () => _sendMessage(_queryController.text),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.send,
                          color: Colors.blue[700],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
