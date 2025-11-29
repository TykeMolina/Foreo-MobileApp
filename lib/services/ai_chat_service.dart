import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_state.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class AIChatService {
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;
  int _conversationCount = 0;
  
  // For Android emulator use 10.0.2.2, for iOS simulator use localhost
  static const String BASE_URL = 'http://localhost:62391'; // Webpage deployed backend
  //static const String BASE_URL = 'http://10.0.2.2:8000'; // Android emulator
  // static const String BASE_URL = 'http://localhost:8000'; // iOS simulator

  // Add this test method
  Future<void> testConnection() async {
    print('🔍 Testing connection to: $BASE_URL');
    try {
      final response = await http.get(Uri.parse('$BASE_URL/health'));
      print('✅ Health check successful: ${response.statusCode}');
      print('Response: ${response.body}');
      
      // Test the ask endpoint too
      final askResponse = await http.post(
        Uri.parse('$BASE_URL/ask'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'question': 'Connection test'}),
      );
      print('✅ Ask endpoint successful: ${askResponse.statusCode}');
    } catch (e) {
      print('❌ Connection failed: $e');
    }
  }


  void addUserMessage(String text) {
    _messages.add(
      ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
    );
    _conversationCount++;
  }

  void addBotMessage(String text) {
    _messages.add(
      ChatMessage(text: text, isUser: false, timestamp: DateTime.now()),
    );
  }

  Future<String> generateResponse(String userMessage, AppState appState) async {
    // First, check if we should use the AI model or fallback
    if (_shouldUseAIModel(userMessage)) {
      try {
        final response = await _callAIModel(userMessage, appState);
        if (response.success) {
          return response.answer;
        } else {
          print('AI Model error: ${response.error}');
          return _getFallbackResponse(userMessage, appState);
        }
      } catch (e) {
        print('Error calling AI model: $e');
        return _getFallbackResponse(userMessage, appState);
      }
    } else {
      // Use rule-based responses for simple queries
      return _getRuleBasedResponse(userMessage, appState);
    }
  }

  bool _shouldUseAIModel(String userMessage) {
    final lowerMessage = userMessage.toLowerCase();
    
    // Use rule-based for simple greetings and basic queries
    final simplePatterns = [
      'hey', 'hi', 'hello', 'merhaba', 'selam',
      'thanks', 'thank you', 'teşekkür', 'sağol',
      'bye', 'goodbye', 'görüşürüz', 'hoşça kal',
      'what are you doing', 'ne yapıyorsun', 'ne var ne yok',
      'how are you', 'nasılsın', 'naber'
    ];
    
    // Use AI model for complex health-related queries
    final complexPatterns = [
      'hrv', 'heart rate', 'steps', 'sleep', 'mood', 'skin',
      'wellbeing', 'health', 'how am i', 'sağlık', 'nasılım',
      'trend', 'pattern', 'kalıp', 'değişim',
      'tip', 'advice', 'help', 'ipucu', 'tavsiye', 'öneri', 'ne yapmalı',
      'why', 'how to', 'what should', 'recommend', 'suggest'
    ];

    // Check if it's a complex query that should go to the AI model
    for (final pattern in complexPatterns) {
      if (lowerMessage.contains(pattern)) {
        return true;
      }
    }

    // Check if it's a simple query that should use rule-based
    for (final pattern in simplePatterns) {
      if (lowerMessage.contains(pattern)) {
        return false;
      }
    }

    // Default to AI model for unknown queries
    return true;
  }

  Future<AIResponse> _callAIModel(String userMessage, AppState appState) async {
    try {
      // Enhance the user message with context from app state
      final enhancedMessage = _enhanceMessageWithContext(userMessage, appState);
      
      final response = await http.post(
        Uri.parse('$BASE_URL/ask'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'question': enhancedMessage,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AIResponse(
          success: data['success'],
          answer: data['answer'],
          error: data['error'],
        );
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to call AI model: $e');
    }
  }

  String _enhanceMessageWithContext(String userMessage, AppState appState) {
    // Add relevant context from the app state to help the AI model
    final context = StringBuffer();
    context.write(userMessage);
    
    // Add HRV context if relevant
    if (userMessage.toLowerCase().contains('hrv')) {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final hrvToday = appState.hrvData
          .where((d) => d.timestamp.isAfter(todayStart))
          .toList();
      
      if (hrvToday.isNotEmpty) {
        final avgHRV = hrvToday.map((d) => d.value!).reduce((a, b) => a + b) / hrvToday.length;
        context.write(' My current HRV is ${avgHRV.toStringAsFixed(1)}ms.');
      }
    }
    
    // Add heart rate context
    if (userMessage.toLowerCase().contains('heart')) {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final hrToday = appState.heartRateData
          .where((d) => d.timestamp.isAfter(todayStart))
          .toList();
      
      if (hrToday.isNotEmpty) {
        final avgHR = hrToday.map((d) => d.value!).reduce((a, b) => a + b) / hrToday.length;
        context.write(' My current heart rate is ${avgHR.toStringAsFixed(0)}bpm.');
      }
    }
    
    // Add steps context
    if (userMessage.toLowerCase().contains('step') || userMessage.toLowerCase().contains('walk')) {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final stepsToday = appState.stepsData
          .where((d) => d.timestamp.isAfter(todayStart))
          .toList();
      
      if (stepsToday.isNotEmpty) {
        final totalSteps = stepsToday.map((d) => d.value!).reduce((a, b) => a + b).toInt();
        context.write(' I have taken $totalSteps steps today.');
      }
    }

    return context.toString();
  }

  String _getRuleBasedResponse(String userMessage, AppState appState) {
    // Your existing rule-based response logic
    final lowerMessage = userMessage.toLowerCase();

    // Greeting detection
    if (lowerMessage.contains('hey') ||
        lowerMessage.contains('hi') ||
        lowerMessage.contains('hello') ||
        lowerMessage.contains('merhaba') ||
        lowerMessage.contains('selam')) {
      if (_conversationCount == 1) {
        return '${_getGreeting()}! ${_getRandomEmoji()} I\'m your wellness assistant. How are you today? How can I help you?';
      }
      return '${_getGreeting()}! ${_getRandomEmoji()} How can I help you?';
    }

    // How are you
    if (lowerMessage.contains('how are you') ||
        lowerMessage.contains('nasılsın') ||
        lowerMessage.contains('naber')) {
      return 'I\'m doing great, thanks! ${_getRandomEmoji()} I\'m here to help you with your wellness journey. How are you feeling today?';
    }

    // Thank you
    if (lowerMessage.contains('thanks') ||
        lowerMessage.contains('thank you') ||
        lowerMessage.contains('teşekkür') ||
        lowerMessage.contains('sağol')) {
      return 'You\'re welcome! ${_getRandomEmoji()} Feel free to ask anything else.';
    }

    // Goodbye
    if (lowerMessage.contains('bye') ||
        lowerMessage.contains('goodbye') ||
        lowerMessage.contains('görüşürüz') ||
        lowerMessage.contains('hoşça kal') ||
        lowerMessage.contains('güle güle')) {
      return 'See you! ${_getRandomEmoji()} Have a healthy day!';
    }

    // Casual conversation
    if (lowerMessage.contains('what are you doing') ||
        lowerMessage.contains('ne yapıyorsun') ||
        lowerMessage.contains('ne var ne yok')) {
      return 'I\'m analyzing your health data and ready to help! ${_getRandomEmoji()} How can I assist you?';
    }

    // Default fallback (shouldn't reach here often)
    return 'I can help you with your wellness questions! ${_getRandomEmoji()} Try asking about your health metrics or general wellbeing advice.';
  }

  String _getFallbackResponse(String userMessage, AppState appState) {
    return '${_getRuleBasedResponse(userMessage, appState)}\n\n*(Note: Using basic mode - AI model is unavailable)*';
  }

  // Helper methods
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _getRandomEmoji() {
    final emojis = ['😊', '✨', '🌟', '💫', '🎯', '🔥', '💪', '🌈'];
    return emojis[DateTime.now().millisecond % emojis.length];
  }
}

class AIResponse {
  final bool success;
  final String answer;
  final String? error;

  AIResponse({
    required this.success,
    required this.answer,
    this.error,
  });
}