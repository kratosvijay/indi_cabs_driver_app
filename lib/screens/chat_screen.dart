import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class ChatScreen extends StatefulWidget {
  final String rideId;
  final String currentUserId; // Driver's ID
  final String otherUserName; // Customer's Name

  const ChatScreen({
    super.key,
    required this.rideId,
    required this.currentUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isQuickChatExpanded = true; // Open by default

  // Predefined quick messages
  final List<String> _quickMessages = [
    "I have arrived",
    "Please come to the pickup location",
    "Are you at the pickup location?",
    "I am waiting at the location",
    "You are not reachable by call",
  ];

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    _firestore
        .collection('ride_requests')
        .doc(widget.rideId)
        .collection('messages')
        .add({
          'text': _messageController.text.trim(),
          'senderId': widget.currentUserId,
          'timestamp': FieldValue.serverTimestamp(),
        });

    _messageController.clear();
  }

  void _sendQuickMessage(String message) {
    _firestore
        .collection('ride_requests')
        .doc(widget.rideId)
        .collection('messages')
        .add({
          'text': message,
          'senderId': widget.currentUserId,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: Text('Chat with ${widget.otherUserName}')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('ride_requests')
                  .doc(widget.rideId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nUse quick chat below to start.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['senderId'] == widget.currentUserId;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? primaryColor
                              : (isDark ? Colors.grey[800] : Colors.grey[200]),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          msg['text'] ?? '',
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Quick Chat Section
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _isQuickChatExpanded = !_isQuickChatExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Quick Chat',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        Icon(
                          _isQuickChatExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isQuickChatExpanded)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _quickMessages.map((msg) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OutlinedButton(
                            onPressed: () => _sendQuickMessage(msg),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              alignment: Alignment.centerLeft,
                              backgroundColor: isDark
                                  ? primaryColor.withAlpha(51)
                                  : primaryColor.withAlpha(26),
                              side: BorderSide(
                                color: isDark
                                    ? primaryColor.withAlpha(128)
                                    : primaryColor.withAlpha(77),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              msg,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white : primaryColor,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                if (_isQuickChatExpanded) const SizedBox(height: 4),
              ],
            ),
          ),
          // Text Input
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ProTextField(
                    controller: _messageController,
                    hintText: 'Type a message...',
                    icon: Icons.message,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
