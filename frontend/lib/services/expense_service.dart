import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_guard.dart';
import '../core/config/app_config.dart';
import '../models/expense_model.dart';

/// Talks to the `expenses` blueprint on the backend.
class ExpenseService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('access_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();

    if (token == null || token.isEmpty) {
      await AuthGuard.handleUnauthorized(
        message: 'Please log in to continue.',
      );

      throw Exception('You are not logged in.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // LIST EXPENSES FOR A TRIP
  // GET /api/trips/<trip_id>/expenses
  // ============================================================

  Future<Map<String, dynamic>> listExpenses(
    int tripId,
  ) async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips/$tripId/expenses'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded?['message']?.toString() ??
            'Could not load expenses.',
      );
    }

    return decoded is Map<String, dynamic> ? decoded : {};
  }

  // ============================================================
  // CREATE EXPENSE
  // POST /api/trips/<trip_id>/expenses
  // ============================================================

  Future<ExpenseModel> createExpense({
    required int tripId,
    required ExpenseModel expense,
  }) async {
    final headers = await _headers();

    final response = await http.post(
      Uri.parse('$baseUrl/api/trips/$tripId/expenses'),
      headers: headers,
      body: jsonEncode(expense.toJson()),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded?['message']?.toString() ?? 'Could not add expense.',
      );
    }

    final rawExpense = decoded?['expense'];
    if (rawExpense is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the server.');
    }

    return ExpenseModel.fromJson(rawExpense);
  }

  // ============================================================
  // UPDATE EXPENSE
  // PATCH /api/expenses/<expense_id>
  // ============================================================

  Future<ExpenseModel> updateExpense({
    required int expenseId,
    required ExpenseModel expense,
  }) async {
    final headers = await _headers();

    final response = await http.patch(
      Uri.parse('$baseUrl/api/expenses/$expenseId'),
      headers: headers,
      body: jsonEncode(expense.toJson()),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded?['message']?.toString() ?? 'Could not update expense.',
      );
    }

    final rawExpense = decoded?['expense'];
    if (rawExpense is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the server.');
    }

    return ExpenseModel.fromJson(rawExpense);
  }

  // ============================================================
  // DELETE EXPENSE
  // DELETE /api/expenses/<expense_id>
  // ============================================================

  Future<void> deleteExpense(int expenseId) async {
    final headers = await _headers();

    final response = await http.delete(
      Uri.parse('$baseUrl/api/expenses/$expenseId'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded?['message']?.toString() ?? 'Could not delete expense.',
      );
    }
  }
}