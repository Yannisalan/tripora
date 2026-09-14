import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/document_viewer.dart';
import '../../core/utils/logger.dart';
import '../../models/trip_document_model.dart';
import '../../services/document_service.dart';
import '../../widgets/shimmer_loader.dart';

/// Trip Vault: per-trip document storage (board passes, confirmations,
/// insurance PDFs, ...). Files live on the backend (S3-compatible storage);
/// this screen lists metadata, uploads new documents, streams files into the
/// device viewer and deletes them.
///
/// The vault is a convenience store, not a secure repository: the app
/// itself confirms this with an acknowledgement dialog before every upload.
/// Nobody who ever clicks straight through a one-line legal notice is
/// meaningfully informed, but the acknowledgement is still persisted per
/// trip in SharedPreferences so the user isn't nagged to death.
class VaultScreen extends StatefulWidget {
  final int tripId;
  final String tripDestination;

  const VaultScreen({
    super.key,
    required this.tripId,
    required this.tripDestination,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  static const int _maxFileSize = 10 * 1024 * 1024;

  static const List<String> _allowedExtensions = [
    'pdf',
    'png',
    'jpg',
    'jpeg',
  ];

  final DocumentService _documentService = DocumentService();

  List<TripDocumentModel> _documents = [];

  bool _isLoading = true;
  bool _isUploading = false;

  bool _warningAcked = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _checkWarningAck();
  }

  // ============================================================
  // SAFETY WARNING
  // ============================================================

  Future<void> _checkWarningAck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final acked = prefs.getBool(
        'vault_warning_acked_${widget.tripId}',
      );

      if (!mounted) return;

      setState(() {
        _warningAcked = acked ?? false;
      });

      if (acked != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showVaultWarningDialog();
        });
      }
    } catch (error) {
      appLog('TRIP VAULT - WARNING CHECK ERROR: $error');
    }
  }

  Future<void> _ackWarning() async {
    setState(() => _warningAcked = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'vault_warning_acked_${widget.tripId}',
        true,
      );
    } catch (error) {
      appLog('TRIP VAULT - ACK ERROR: $error');
    }
  }

  /// Shows the acknowledgement dialog. Returns true when the user
  /// confirmed (and the acknowledgement was persisted).
  Future<bool> _showVaultWarningDialog() async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = dialogContext.triporaColors;

        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          icon: Icon(
            Icons.security_outlined,
            color: colors.appStatus.warning,
            size: 32,
          ),
          title: Text(
            'Trip Vault — Please read',
            style: Theme.of(dialogContext).textTheme.titleMedium,
          ),
          content: const Text(
            'Important: The Tripora Vault is provided for convenience only '
            '(quick access to tickets, confirmations and insurance papers). '
            'It is NOT a guaranteed secure or irreversible storage service. '
            'Do not store anything you could not afford to lose — keep '
            'official backups of important documents.',
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('I Understand'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _ackWarning();
      return true;
    }

    return false;
  }

  /// Gates an upload on the acknowledgement. Called after a file has been
  /// picked and described but before it leaves the device.
  Future<bool> _ensureWarningAcked() async {
    if (_warningAcked) return true;
    return _showVaultWarningDialog();
  }

  // ============================================================
  // DATA
  // ============================================================

  Future<void> _loadDocuments() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final documents =
          await _documentService.getDocuments(widget.tripId);

      if (!mounted) return;

      setState(() {
        _documents = documents;
        _isLoading = false;
      });
    } catch (error) {
      appLog('TRIP VAULT - LOAD ERROR: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? context.triporaColors.appStatus.error
            : null,
      ),
    );
  }

  // ============================================================
  // UPLOAD
  // ============================================================

  Future<void> _pickAndUpload() async {
    final (String name, Uint8List bytes, String mime)? picked;

    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
      );

      if (pickedFile == null) {
        return;
      }

      final size = await pickedFile.length();

      if (size > _maxFileSize) {
        _showMessage(
          'File is too large. Maximum size is 10 MB.',
          isError: true,
        );
        return;
      }

      final bytes = await pickedFile.readAsBytes();

      if (bytes.isEmpty) {
        _showMessage('Could not read the selected file.', isError: true);
        return;
      }

      picked = (
        pickedFile.name,
        bytes,
        _mimeForExtension(_extensionOf(pickedFile.name)) ??
            'application/octet-stream',
      );
    } catch (error) {
      appLog('TRIP VAULT - PICK ERROR: $error');
      _showMessage('Could not open the file picker.', isError: true);
      return;
    }

    final metadata = await _showUploadDialog(
      defaultName: _nameWithoutExtension(picked.$1),
    );

    if (metadata == null) {
      return;
    }

    if (!mounted) return;

    // Confirm the vault is convenience-only before the file leaves the
    // device. Cancelling here discards the picked file without uploading.
    final confirmed = await _ensureWarningAcked();

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final document = await _documentService.uploadDocument(
        tripId: widget.tripId,
        name: metadata.$1,
        documentType: metadata.$2,
        fileName: picked.$1,
        bytes: picked.$2,
        mimeType: picked.$3,
      );

      if (!mounted) return;

      setState(() {
        _documents = [document, ..._documents];
        _isUploading = false;
      });

      _showMessage('Document uploaded successfully.');
    } catch (error) {
      appLog('TRIP VAULT - UPLOAD ERROR: $error');

      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      _showMessage(error.toString(), isError: true);
    }
  }

  Future<(String, String)?> _showUploadDialog({
    required String defaultName,
  }) async {
    final nameController = TextEditingController(text: defaultName);
    String selectedType = 'other';

    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final colors = dialogContext.triporaColors;

            return AlertDialog(
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              title: Text(
                'Add document',
                style: Theme.of(dialogContext).textTheme.headlineSmall,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Flight Ticket',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                    ),
                    items: _documentTypes.entries.map((entry) {
                      return DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value.$1),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedType = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      return;
                    }

                    Navigator.of(dialogContext).pop((name, selectedType));
                  },
                  child: const Text('Upload'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  // ============================================================
  // OPEN
  // ============================================================

  Future<void> _openDocument(TripDocumentModel document) async {
    if (!mounted) return;

    _showFullScreenProgress('Opening document…');

    try {
      final bytes = await _documentService.getDocumentBytes(document.id);

      await displayDocument(
        bytes: bytes,
        mimeType: document.mimeType,
        fileName: document.fileName,
      );
    } catch (error) {
      appLog('TRIP VAULT - OPEN ERROR: $error');
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> _deleteDocument(TripDocumentModel document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.triporaColors;

        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text(
            'Delete document?',
            style: Theme.of(dialogContext).textTheme.headlineSmall,
          ),
          content: Text(
            '"${document.name}" will be removed from this trip permanently.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.appStatus.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isUploading = true;
    });

    try {
      await _documentService.deleteDocument(document.id);

      if (!mounted) return;

      setState(() {
        _documents.removeWhere((item) => item.id == document.id);
        _isUploading = false;
      });

      _showMessage('Document deleted.');
    } catch (error) {
      appLog('TRIP VAULT - DELETE ERROR: $error');

      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      _showMessage(error.toString(), isError: true);
    }
  }

  // ============================================================
  // OVERLAY PROGRESS
  // ============================================================

  void _showFullScreenProgress(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: dialogContext.triporaColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 16),
                  Flexible(child: Text(message)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Vault'),
      ),
      floatingActionButton: _documents.isEmpty && !_isLoading && _errorMessage == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _isUploading ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Add document'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.triporaColors;

    if (_isLoading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          TripCardShimmer(isCompact: true),
          SizedBox(height: AppSpacing.sm),
          TripCardShimmer(isCompact: true),
          SizedBox(height: AppSpacing.sm),
          TripCardShimmer(isCompact: true),
        ],
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState(colors);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            widget.tripDestination,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (!_warningAcked)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceInfo,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: colors.appStatus.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 22,
                    color: colors.appStatus.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Important: the Vault is provided for convenience '
                      'only. Keep official backups of important documents.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            _documents.isEmpty
                ? 'No documents yet'
                : '${_documents.length} document${_documents.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textMuted,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _documents.isEmpty
              ? _buildEmptyState(colors)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    96,
                  ),
                  itemCount: _documents.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    return _DocumentCard(
                      document: _documents[index],
                      onOpen: () => _openDocument(_documents[index]),
                      onDelete: () => _deleteDocument(_documents[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(TriporaColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(
                Icons.folder_open_outlined,
                size: 34,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your trip vault is empty',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Store flight tickets, hotel confirmations and '
              'insurance documents for this trip.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _isUploading ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Add document'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(TriporaColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: colors.textMuted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not load your documents',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _loadDocuments,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STATIC HELPERS
  // ============================================================

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');

    if (dot < 0) {
      return '';
    }

    return name.substring(dot + 1).toLowerCase();
  }

  static String _nameWithoutExtension(String name) {
    final dot = name.lastIndexOf('.');

    if (dot > 0) {
      return name.substring(0, dot).trim();
    }

    return name.trim();
  }

  static String? _mimeForExtension(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  static String _formatDate(DateTime? date) {
    if (date == null) {
      return '';
    }

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

    final local = date.toLocal();

    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  /// document type key -> (label, icon).
  static const Map<String, (String, IconData)> _documentTypes = {
    'flight': ('Flight', Icons.flight_outlined),
    'hotel': ('Hotel', Icons.hotel_outlined),
    'visa': ('Visa', Icons.badge_outlined),
    'insurance': ('Insurance', Icons.health_and_safety_outlined),
    'transport': ('Transport', Icons.directions_bus_outlined),
    'activity': ('Activity', Icons.local_activity_outlined),
    'other': ('Other', Icons.description_outlined),
  };
}

/// A single document row in the vault list.
class _DocumentCard extends StatelessWidget {
  final TripDocumentModel document;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _DocumentCard({
    required this.document,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final type = _VaultScreenState._documentTypes[document.documentType] ??
        _VaultScreenState._documentTypes['other']!;

    final dateLabel = _VaultScreenState._formatDate(document.createdAt);
    final subtitle = [
      type.$1,
      document.formattedSize,
      if (dateLabel.isNotEmpty) dateLabel,
    ].join(' · ');

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surfaceInfo,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(type.$2, size: 21, color: AppColors.secondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: colors.textMuted),
                onSelected: (value) {
                  if (value == 'open') {
                    onOpen.call();
                  } else if (value == 'delete') {
                    onDelete.call();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: Icon(Icons.open_in_new),
                      title: Text('Open'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}