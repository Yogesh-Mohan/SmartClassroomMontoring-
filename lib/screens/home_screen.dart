import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Smart Classroom'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Please log in to continue'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Classroom'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('focus_summary')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Error state
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          // No data found
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Data Found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          // Extract data from document
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          
          if (data == null) {
            return const Center(
              child: Text('No Data Found'),
            );
          }

          final alertsToday = data['alertsToday'] as int? ?? 0;
          final focusScore = data['focusScore'] as int? ?? 0;
          final status = data['status'] as String? ?? 'Unknown';
          final todayDate = data['todayDate'] as Timestamp?;

          // Format date if available
          String formattedDate = 'N/A';
          if (todayDate != null) {
            final date = todayDate.toDate();
            formattedDate = DateFormat('MMM dd, yyyy').format(date);
          }

          // Determine status color
          Color statusColor;
          switch (status.toLowerCase()) {
            case 'good':
              statusColor = Colors.green;
              break;
            case 'moderate':
              statusColor = Colors.orange;
              break;
            case 'poor':
              statusColor = Colors.red;
              break;
            default:
              statusColor = Colors.grey;
          }

          // Determine violation message
          final violationMessage = alertsToday == 0
              ? 'No violations today'
              : 'Violation recorded today';
          final violationColor = alertsToday == 0 ? Colors.green : Colors.red;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bar_chart,
                            size: 32,
                            color: Colors.blue[700],
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Today Summary',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const Divider(height: 32),

                      // Data display
                      _buildDataRow(
                        'Alerts Today',
                        alertsToday.toString(),
                        Icons.warning_amber_rounded,
                        alertsToday > 0 ? Colors.red : Colors.green,
                      ),
                      const SizedBox(height: 16),
                      _buildDataRow(
                        'Focus Score',
                        focusScore.toString(),
                        Icons.emoji_events,
                        _getScoreColor(focusScore),
                      ),
                      const SizedBox(height: 16),
                      _buildDataRow(
                        'Status',
                        status,
                        Icons.info_outline,
                        statusColor,
                      ),

                      const SizedBox(height: 24),
                      const Divider(height: 32),

                      // Violation message
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: violationColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: violationColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              alertsToday == 0
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: violationColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              violationMessage,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: violationColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDataRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 80) {
      return Colors.green;
    } else if (score >= 50) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}
