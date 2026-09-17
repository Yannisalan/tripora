import 'package:flutter/material.dart';

import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../models/expense_model.dart';
import '../../models/trip_model.dart';
import '../../services/expense_service.dart';
import '../../services/trip_service.dart';
import '../../widgets/gradient_button.dart';

/// Full expense tracker for a single trip.
///
/// Shows budget vs. spent, animated budget progress,
/// category breakdown and the list of expenses,
/// with add / edit / delete and an editable trip budget.
class ExpenseTrackerScreen extends StatefulWidget {
  final TripModel trip;

  const ExpenseTrackerScreen({
    super.key,
    required this.trip,
  });

  @override
  State<ExpenseTrackerScreen> createState() =>
      _ExpenseTrackerScreenState();
}

class _ExpenseTrackerScreenState extends State<ExpenseTrackerScreen> {
  final ExpenseService _expenseService = ExpenseService();
  final TripService _tripService = TripService();

  List<ExpenseModel> _expenses = [];

  double? _budgetAmount;
  String _budgetCurrency = 'USD';

  bool _isLoading = true;
  String? _error;

  double _format(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _expenseService.listExpenses(
        widget.trip.id!,
      );

      if (!mounted) return;

      final rawList = data['expenses'] is List
          ? data['expenses'] as List
          : const <dynamic>[];

      final rawBudget = data['budgetAmount'];

      setState(() {
        _expenses = rawList
            .whereType<Map<String, dynamic>>()
            .map(ExpenseModel.fromJson)
            .toList();

        _budgetAmount = rawBudget is num
            ? _format(rawBudget.toDouble())
            : null;

        _budgetCurrency =
            data['budgetCurrency']?.toString() ?? 'USD';
      });
    } catch (error) {
      appLog('LOAD EXPENSES ERROR: $error');

      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double get _totalSpent {
    return _expenses.fold(
      0.0,
          (sum, expense) => sum + expense.amount,
    );
  }

  double? get _remaining {
    final budget = _budgetAmount;

    if (budget == null) {
      return null;
    }

    return budget - _totalSpent;
  }

  double _spentRatio() {
    final budget = _budgetAmount;

    if (budget == null || budget <= 0) {
      return 0;
    }

    return _totalSpent / budget;
  }

  String _formatAmount(double amount, [String? from]) {
    return AppPreferences.instance.formatMoney(
      amount,
      from: from ?? _budgetCurrency,
    );
  }

  Map<String, double> _categoryTotals() {
    final totals = <String, double>{};

    for (final expense in _expenses) {
      totals.update(
        expense.category,
            (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }

    return totals;
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'transport':
        return Icons.directions_car_outlined;

      case 'accommodation':
        return Icons.hotel_outlined;

      case 'food':
        return Icons.restaurant_outlined;

      case 'activities':
        return Icons.attractions_outlined;

      case 'shopping':
        return Icons.shopping_bag_outlined;

      case 'health':
        return Icons.favorite_outline;

      default:
        return Icons.receipt_long_outlined;
    }
  }

  // ============================================================
  // ADD / EDIT / DELETE
  // ============================================================

  Future<void> _openExpenseSheet([
    ExpenseModel? existing,
  ]) async {
    // A budget is required before expenses can be tracked
    // meaningfully against the trip budget.
    if (_budgetAmount == null) {
      await _editBudget();

      if (!mounted || _budgetAmount == null) {
        return;
      }
    }

    final saved = await showModalBottomSheet<ExpenseModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseFormSheet(
        existing: existing,
        currency: _budgetCurrency,
        availableCurrencies: validCurrencies,
      ),
    );

    if (saved == null || !mounted) {
      return;
    }

    try {
      if (existing == null) {
        await _expenseService.createExpense(
          tripId: widget.trip.id!,
          expense: saved,
        );
      } else {
        await _expenseService.updateExpense(
          expenseId: existing.id!,
          expense: saved,
        );
      }

      await _loadExpenses();
    } catch (error) {
      appLog('SAVE EXPENSE ERROR: $error');

      if (!mounted) return;

      _showMessage(
        error.toString(),
        isError: true,
      );
    }
  }

  Future<void> _deleteExpense(
      ExpenseModel expense,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text(
          'This will permanently remove the expense from your trip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              false,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              true,
            ),
            style: TextButton.styleFrom(
              foregroundColor:
              Theme.of(context)
                  .extension<AppStatusColors>()
                  ?.error ??
                  AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _expenseService.deleteExpense(
        expense.id!,
      );

      await _loadExpenses();
    } catch (error) {
      appLog('DELETE EXPENSE ERROR: $error');

      if (!mounted) return;

      _showMessage(
        error.toString(),
        isError: true,
      );
    }
  }

  Future<void> _editBudget() async {
    final saved = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetSheet(
        current: _budgetAmount,
        currency: _budgetCurrency,
      ),
    );

    if (saved == null || !mounted) {
      return;
    }

    try {
      final trip = widget.trip;

      final updated = TripModel(
        id: trip.id,
        destination: trip.destination,
        startDate: trip.startDate,
        endDate: trip.endDate,
        travelers: trip.travelers,
        budget: trip.budget,
        travelStyle: trip.travelStyle,
        interests: trip.interests,
        budgetAmount: saved,
        itinerary: trip.itinerary,
        estimatedCost: trip.estimatedCost,
        createdAt: trip.createdAt,
      );

      await _tripService.updateTrip(
        tripId: trip.id!,
        trip: updated,
      );

      await _loadExpenses();
    } catch (error) {
      appLog('UPDATE BUDGET ERROR: $error');

      if (!mounted) return;

      _showMessage(
        error.toString(),
        isError: true,
      );
    }
  }

  void _showMessage(
      String message, {
        bool isError = false,
      }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? Theme.of(context)
              .extension<AppStatusColors>()
              ?.error ??
              AppColors.error
              : null,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final colors = context.triporaColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        backgroundColor: colors.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Set trip budget',
            onPressed: _isLoading
                ? null
                : _editBudget,
            icon: const Icon(
              Icons.savings_outlined,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading
            ? null
            : () => _openExpenseSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(TriporaColors colors) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colors.appStatus.error,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                onPressed: _loadExpenses,
                height: 44,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final categories = _categoryTotals().entries.toList()
      ..sort(
            (a, b) => b.value.compareTo(a.value),
      );

    return RefreshIndicator(
      onRefresh: _loadExpenses,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          96,
        ),
        children: [
          _buildSummaryCard(colors),
          const SizedBox(height: 16),
          if (categories.isNotEmpty) ...[
            _buildCategoryBreakdown(
              colors,
              categories,
            ),
            const SizedBox(height: 16),
          ],
          _buildExpenseList(colors),
        ],
      ),
    );
  }

  // ============================================================
  // BUDGET SUMMARY
  // ============================================================

  Widget _buildSummaryCard(
      TriporaColors colors,
      ) {
    final budget = _budgetAmount;

    // ----------------------------------------------------------
    // No budget yet
    // ----------------------------------------------------------

    if (budget == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.savings_outlined,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 12),
            const Text(
              'Set your trip budget',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Set a budget to compare your spending and see how much you have left.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _editBudget,
                icon: const Icon(Icons.add),
                label: const Text('Set Budget'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor:
                  colors.textPrimary,
                  elevation: 0,
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final spent = _totalSpent;
    final ratio = budget > 0
        ? spent / budget
        : 0.0;

    final overBudget = ratio > 1.0;

    final progress =
    ratio.clamp(0.0, 1.0);

    final progressColor = overBudget
        ? colors.appStatus.error
        : ratio >= 0.90
        ? colors.appStatus.warning
        : colors.appStatus.success;

    final remaining = budget - spent;

    // ----------------------------------------------------------
    // Animated summary
    // ----------------------------------------------------------

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0,
        end: spent,
      ),
      duration:
      const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (
          context,
          animatedSpent,
          child,
          ) {
        final animatedRatio = budget > 0
            ? animatedSpent / budget
            : 0.0;

        final animatedProgress =
        animatedRatio.clamp(0.0, 1.0);

        final animatedRemaining =
            budget - animatedSpent;

        return Container(
          padding:
          const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient:
            AppColors.brandGradient,
            borderRadius:
            BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
                children: [
                  const Text(
                    'Trip Budget',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w600,
                      color:
                      Colors.white70,
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                    _editBudget,
                    style:
                    TextButton.styleFrom(
                      foregroundColor:
                      Colors.white,
                      padding:
                      EdgeInsets.zero,
                      minimumSize:
                      const Size(0, 32),
                    ),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                    ),
                    label:
                    const Text('Edit'),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // Budget amount
              Text(
                _formatAmount(budget),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight:
                  FontWeight.w800,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 18),

              // Spent
              Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
                children: [
                  const Text(
                    'Spent',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                      Colors.white70,
                    ),
                  ),
                  Text(
                    _formatAmount(
                      animatedSpent,
                    ),
                    style:
                    const TextStyle(
                      fontSize: 15,
                      fontWeight:
                      FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Animated progress
              ClipRRect(
                borderRadius:
                BorderRadius.circular(
                  10,
                ),
                child:
                TweenAnimationBuilder<
                    double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: animatedProgress,
                  ),
                  duration:
                  const Duration(
                    milliseconds: 700,
                  ),
                  curve:
                  Curves.easeOutCubic,
                  builder: (
                      context,
                      progressValue,
                      _,
                      ) {
                    return LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 9,
                      backgroundColor:
                      Colors.white24,
                      valueColor:
                      AlwaysStoppedAnimation<
                          Color>(
                        progressColor,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Percentage + remaining
              Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(animatedRatio * 100).toStringAsFixed(0)}% used',
                    style:
                    const TextStyle(
                      fontSize: 12,
                      color:
                      Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      animatedRatio > 1
                          ? 'Over budget by ${_formatAmount(-animatedRemaining)}'
                          : '${_formatAmount(animatedRemaining)} remaining',
                      textAlign:
                      TextAlign.end,
                      style:
                      const TextStyle(
                        fontSize: 12,
                        fontWeight:
                        FontWeight.w700,
                        color:
                        Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              // Over budget warning
              if (overBudget) ...[
                const SizedBox(height: 14),
                TweenAnimationBuilder<
                    double>(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ),
                  duration:
                  const Duration(
                    milliseconds: 500,
                  ),
                  curve:
                  Curves.easeOutBack,
                  builder: (
                      context,
                      value,
                      child,
                      ) {
                    return Opacity(
                      opacity: value.clamp(
                        0.0,
                        1.0,
                      ),
                      child:
                      Transform.scale(
                        scale: 0.96 +
                            (0.04 * value),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration:
                    BoxDecoration(
                      color: Colors.white
                          .withValues(
                        alpha: 0.12,
                      ),
                      borderRadius:
                      BorderRadius
                          .circular(
                        12,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons
                              .warning_amber_rounded,
                          color:
                          Colors.white,
                          size: 20,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            'You have exceeded your trip budget.',
                            style:
                            TextStyle(
                              fontSize: 12,
                              fontWeight:
                              FontWeight
                                  .w600,
                              color:
                              Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // CATEGORY BREAKDOWN
  // ============================================================

  Widget _buildCategoryBreakdown(
      TriporaColors colors,
      List<MapEntry<String, double>>
      categories,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'By Category',
            style: TextStyle(
              fontSize: 15,
              fontWeight:
              FontWeight.w700,
              color:
              colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories
                .map(
                  (entry) => Chip(
                avatar: Icon(
                  _categoryIcon(
                    entry.key,
                  ),
                  size: 16,
                  color:
                  colors.textSecondary,
                ),
                label: Text(
                  '${expenseCategoryLabel(entry.key)}  '
                      '${_formatAmount(entry.value)}',
                ),
                side: BorderSide(
                  color:
                  colors.border,
                ),
                backgroundColor:
                colors
                    .surfaceSecondary,
                labelStyle:
                TextStyle(
                  color: colors
                      .textSecondary,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w600,
                ),
                visualDensity:
                VisualDensity
                    .compact,
              ),
            )
                .toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EXPENSE LIST
  // ============================================================

  Widget _buildExpenseList(
      TriporaColors colors,
      ) {
    if (_expenses.isEmpty) {
      return Container(
        padding:
        const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius:
          BorderRadius.circular(16),
          border: Border.all(
            color: colors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: colors.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              'No expenses yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                FontWeight.w700,
                color:
                colors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Add your first expense to start tracking your trip spending.',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color:
                colors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(
              onPressed:
                  () => _openExpenseSheet(),
              height: 44,
              child:
              const Text('Add Expense'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'All Expenses',
          style: TextStyle(
            fontSize: 15,
            fontWeight:
            FontWeight.w700,
            color:
            colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._expenses.map(
              (expense) => _buildExpenseTile(
            expense: expense,
            icon: _categoryIcon(
              expense.category,
            ),
            formattedAmount:
            _formatAmount(
              expense.amount,
              expense.currency,
            ),
            onTap: () =>
                _openExpenseSheet(
                  expense,
                ),
            onDelete: () =>
                _deleteExpense(
                  expense,
                ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EXPENSE TILE
  // ============================================================

  Widget _buildExpenseTile({
    required ExpenseModel expense,
    required IconData icon,
    required String formattedAmount,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin:
      const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color:
        context.triporaColors.surface,
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color:
          context.triporaColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                  BoxDecoration(
                    color: context
                        .triporaColors
                        .surfaceSecondary,
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: context
                        .triporaColors
                        .textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        expense.description
                            .isNotEmpty
                            ? expense
                            .description
                            : expenseCategoryLabel(
                          expense
                              .category,
                        ),
                        maxLines: 1,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                          FontWeight
                              .w600,
                          color: context
                              .triporaColors
                              .textPrimary,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        '${expenseCategoryLabel(expense.category)} · '
                            '${_formatDate(expense.date)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context
                              .triporaColors
                              .textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .end,
                  children: [
                    Text(
                      formattedAmount,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                        FontWeight.w700,
                        color: context
                            .triporaColors
                            .textPrimary,
                      ),
                    ),
                    Text(
                      paymentMethodLabel(
                        expense
                            .paymentMethod,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: context
                            .triporaColors
                            .textMuted,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  iconSize: 18,
                  color: context
                      .triporaColors
                      .textMuted,
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }
}

// ============================================================
// ADD / EDIT EXPENSE SHEET
// ============================================================

class _ExpenseFormSheet extends StatefulWidget {
  final ExpenseModel? existing;
  final String currency;
  final List<String> availableCurrencies;

  const _ExpenseFormSheet({
    this.existing,
    required this.currency,
    required this.availableCurrencies,
  });

  @override
  State<_ExpenseFormSheet> createState() =>
      _ExpenseFormSheetState();
}

class _ExpenseFormSheetState
    extends State<_ExpenseFormSheet> {
  final _formKey =
  GlobalKey<FormState>();

  late final TextEditingController
  _amountController;

  late final TextEditingController
  _descriptionController;

  late String _currency;
  late String _category;
  late DateTime _date;
  late String _paymentMethod;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _amountController =
        TextEditingController(
          text: existing != null
              ? existing.amount
              .toStringAsFixed(2)
              : '',
        );

    _descriptionController =
        TextEditingController(
          text:
          existing?.description ?? '',
        );

    _currency =
        existing?.currency ??
            widget.currency;

    _category =
        existing?.category ?? 'other';

    _date =
        existing?.date ??
            DateTime.now();

    _paymentMethod =
        existing?.paymentMethod ??
            'other';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked =
    await showDatePicker(
      context: context,
      initialDate:
      _date.isAfter(
        DateTime.now(),
      )
          ? DateTime.now()
          : _date,
      firstDate:
      DateTime(2000),
      lastDate:
      DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _date = picked;
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    final amount =
    double.tryParse(
      _amountController.text.trim(),
    );

    if (amount == null ||
        amount <= 0) {
      _showError(
        'Please enter a valid amount.',
      );
      return;
    }

    Navigator.pop(
      context,
      ExpenseModel(
        id: widget.existing?.id,
        tripId:
        widget.existing?.tripId,
        amount: amount,
        currency: _currency,
        category: _category,
        description:
        _descriptionController
            .text
            .trim(),
        date: _date,
        paymentMethod:
        _paymentMethod,
      ),
    );
  }

  void _showError(
      String message,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
          Text(message),
          behavior:
          SnackBarBehavior
              .floating,
        ),
      );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    final colors =
        context.triporaColors;

    final existing =
        widget.existing;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(
          context,
        ).viewInsets.bottom +
            16,
      ),
      child: Container(
        decoration:
        BoxDecoration(
          color: colors.surface,
          borderRadius:
          BorderRadius.circular(
            20,
          ),
        ),
        padding:
        const EdgeInsets.all(20),
        child:
        SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment
                  .stretch,
              children: [
                Text(
                  existing == null
                      ? 'Add Expense'
                      : 'Edit Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                    FontWeight.w800,
                    color: colors
                        .textPrimary,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                // IMPORTANT:
                // Amount and currency remain in
                // a Column because this layout
                // fixed the keyboard/input issue.
                Column(
                  children: [
                    TextFormField(
                      controller:
                      _amountController,
                      keyboardType:
                      TextInputType
                          .number,
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Amount',
                        hintText:
                        '0.00',
                      ),
                      validator:
                          (value) {
                        final parsed =
                        double.tryParse(
                          value?.trim() ??
                              '',
                        );

                        if (parsed ==
                            null ||
                            parsed <=
                                0) {
                          return 'Enter a positive amount.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    DropdownButtonFormField<
                        String>(
                      initialValue:
                      _currency,
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Currency',
                      ),
                      items: widget
                          .availableCurrencies
                          .map(
                            (currency) =>
                            DropdownMenuItem<
                                String>(
                              value:
                              currency,
                              child:
                              Text(
                                currency,
                              ),
                            ),
                      ).toList(),
                      onChanged:
                          (value) {
                        if (value !=
                            null) {
                          setState(() {
                            _currency =
                                value;
                          });
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(
                  height: 16,
                ),

                DropdownButtonFormField<
                    String>(
                  initialValue:
                  _category,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Category',
                  ),
                  items:
                  expenseCategories
                      .map(
                        (category) =>
                        DropdownMenuItem<
                            String>(
                          value:
                          category,
                          child: Text(
                            expenseCategoryLabel(
                              category,
                            ),
                          ),
                        ),
                  ).toList(),
                  onChanged:
                      (value) {
                    if (value !=
                        null) {
                      setState(() {
                        _category =
                            value;
                      });
                    }
                  },
                ),

                const SizedBox(
                  height: 16,
                ),

                TextFormField(
                  controller:
                  _descriptionController,
                  maxLength: 255,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Description (optional)',
                    hintText:
                    'e.g. Dinner at the waterfront',
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                InkWell(
                  onTap: _pickDate,
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                  child:
                  InputDecorator(
                    decoration:
                    InputDecoration(
                      labelText:
                      'Date',
                      border:
                      OutlineInputBorder(
                        borderRadius:
                        BorderRadius
                            .circular(
                          12,
                        ),
                      ),
                      suffixIcon:
                      const Icon(
                        Icons
                            .calendar_today_outlined,
                      ),
                    ),
                    child: Text(
                      '${_date.year}-'
                          '${_date.month.toString().padLeft(2, '0')}-'
                          '${_date.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                DropdownButtonFormField<
                    String>(
                  initialValue:
                  _paymentMethod,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Payment method',
                  ),
                  items:
                  paymentMethods
                      .map(
                        (method) =>
                        DropdownMenuItem<
                            String>(
                          value:
                          method,
                          child: Text(
                            paymentMethodLabel(
                              method,
                            ),
                          ),
                        ),
                  ).toList(),
                  onChanged:
                      (value) {
                    if (value !=
                        null) {
                      setState(() {
                        _paymentMethod =
                            value;
                      });
                    }
                  },
                ),

                const SizedBox(
                  height: 20,
                ),

                SizedBox(
                  height: 52,
                  child:
                  GradientButton(
                    onPressed:
                    _save,
                    height: 52,
                    child: Text(
                      existing == null
                          ? 'Add Expense'
                          : 'Save',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BUDGET EDITOR SHEET
// ============================================================

class _BudgetSheet
    extends StatefulWidget {
  final double? current;
  final String currency;

  const _BudgetSheet({
    this.current,
    required this.currency,
  });

  @override
  State<_BudgetSheet> createState() =>
      _BudgetSheetState();
}

class _BudgetSheetState
    extends State<_BudgetSheet> {
  final _formKey =
  GlobalKey<FormState>();

  late final TextEditingController
  _budgetController;

  @override
  void initState() {
    super.initState();

    _budgetController =
        TextEditingController(
          text: widget.current
              ?.toStringAsFixed(2) ??
              '',
        );
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    final value =
    double.parse(
      _budgetController.text.trim(),
    );

    Navigator.pop(
      context,
      double.parse(
        value.toStringAsFixed(2),
      ),
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    final colors =
        context.triporaColors;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(
          context,
        ).viewInsets.bottom +
            16,
      ),
      child: Container(
        decoration:
        BoxDecoration(
          color: colors.surface,
          borderRadius:
          BorderRadius.circular(
            20,
          ),
        ),
        padding:
        const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            crossAxisAlignment:
            CrossAxisAlignment
                .stretch,
            children: [
              Text(
                'Set Trip Budget',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                  FontWeight.w800,
                  color:
                  colors.textPrimary,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              TextFormField(
                controller:
                _budgetController,
                autofocus: true,
                keyboardType:
                const TextInputType
                    .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                InputDecoration(
                  labelText:
                  'Budget (${widget.currency})',
                  hintText:
                  '0.00',
                ),
                validator:
                    (value) {
                  final parsed =
                  double.tryParse(
                    value?.trim() ??
                        '',
                  );

                  if (parsed ==
                      null ||
                      parsed <= 0) {
                    return 'Enter a positive budget.';
                  }

                  return null;
                },
              ),

              const SizedBox(
                height: 20,
              ),

              SizedBox(
                height: 52,
                child:
                GradientButton(
                  onPressed:
                  _save,
                  height: 52,
                  child: const Text(
                    'Save Budget',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}