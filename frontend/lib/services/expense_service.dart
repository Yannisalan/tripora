import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../models/expense_model.dart';

/// Talks to the `expenses` blueprint on the backend.
class ExpenseService {
  static const String baseUrl = AppConfig.apiBaseUrl;

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
    final response = await ApiClient.instance.get(
      Uri.parse('$baseUrl/api/trips/$tripId/expenses'),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
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
    final response = await ApiClient.instance.post(
      Uri.parse('$baseUrl/api/trips/$tripId/expenses'),
      body: jsonEncode(expense.toJson()),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
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
    final response = await ApiClient.instance.patch(
      Uri.parse('$baseUrl/api/expenses/$expenseId'),
      body: jsonEncode(expense.toJson()),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
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
    final response = await ApiClient.instance.delete(
      Uri.parse('$baseUrl/api/expenses/$expenseId'),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 401) {
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded?['message']?.toString() ?? 'Could not delete expense.',
      );
    }
  }
}