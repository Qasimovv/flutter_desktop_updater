import 'package:flutter/material.dart';
import '../models/update_info.dart';
import '../services/update_manager.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({
    super.key,
    this.updateInfo,
    this.onUpdateAvailable,
    this.onUpdating,
    this.onReadyToRestart,
    this.onError,
  });

  /// Update info provided from outside. The app fetches this from its own
  /// backend/API and passes it here. No automatic fetching.
  final UpdateInfo? updateInfo;

  /// Called when update is available
  /// [manager] - UpdateManager instance for full control
  /// [onUpdate] - starts downloading and installing
  /// [onDismiss] - dismisses the update notification
  final Widget Function(
    BuildContext context,
    UpdateManager manager,
    VoidCallback onUpdate,
    VoidCallback onDismiss,
  )? onUpdateAvailable;

  /// Called during update download/installation
  /// [manager] - UpdateManager instance for full control
  /// [progress] - download progress (0.0 to 1.0)
  final Widget Function(
      BuildContext context, UpdateManager manager, double progress)? onUpdating;

  /// Called when update is ready to restart
  /// [manager] - UpdateManager instance for full control
  /// [onRestart] - quits and restarts the app
  final Widget Function(
          BuildContext context, UpdateManager manager, VoidCallback onRestart)?
      onReadyToRestart;

  /// Called when update fails
  /// [manager] - UpdateManager instance for full control
  /// [error] - error message
  /// [onRetry] - retries the update (download/install)
  /// [onDismiss] - dismisses the error
  final Widget Function(
    BuildContext context,
    UpdateManager manager,
    String error,
    VoidCallback onRetry,
    VoidCallback onDismiss,
  )? onError;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  UpdateInfo? _lastProcessedInfo;

  @override
  void initState() {
    super.initState();
    _processUpdateInfo(widget.updateInfo);
  }

  @override
  void didUpdateWidget(UpdateBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.updateInfo != _lastProcessedInfo) {
      _processUpdateInfo(widget.updateInfo);
    }
  }

  void _processUpdateInfo(UpdateInfo? info) {
    if (info == _lastProcessedInfo) return;

    _lastProcessedInfo = info;
    UpdateManager().setUpdateInfo(info);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateManager(),
      builder: (context, _) {
        final manager = UpdateManager();

        return switch (manager.status) {
          UpdateStatus.updateAvailable => widget.onUpdateAvailable != null
              ? widget.onUpdateAvailable!(
                  context,
                  manager,
                  manager.startUpdate,
                  manager.dismiss,
                )
              : _AvailableBanner(manager: manager),
          UpdateStatus.updating => widget.onUpdating != null
              ? widget.onUpdating!(context, manager, manager.progress)
              : _UpdatingBanner(manager: manager, progress: manager.progress),
          UpdateStatus.readyToRestart => widget.onReadyToRestart != null
              ? widget.onReadyToRestart!(context, manager, manager.restartApp)
              : _ReadyToRestartBanner(
                  manager: manager, onRestart: manager.restartApp),
          UpdateStatus.error => widget.onError != null
              ? widget.onError!(
                  context,
                  manager,
                  manager.error ?? 'Unknown error',
                  manager.startUpdate,
                  manager.dismiss,
                )
              : _ErrorBanner(
                  manager: manager,
                  error: manager.error ?? 'Unknown error',
                  onRetry: manager.startUpdate,
                  onDismiss: manager.dismiss,
                ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

class _AvailableBanner extends StatelessWidget {
  final UpdateManager manager;

  const _AvailableBanner({required this.manager});

  @override
  Widget build(BuildContext context) {
    final info = manager.updateInfo!;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update, color: Colors.blue.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Update Available',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Version ${info.version.latest} • ${(info.fileSize / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          if (info.updateRequired != null && !info.updateRequired!) ...[
            TextButton(onPressed: manager.dismiss, child: const Text('Later')),
            const SizedBox(width: 4),
          ],
          ElevatedButton(
            onPressed: manager.startUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}

class _UpdatingBanner extends StatelessWidget {
  final UpdateManager manager;
  final double progress;

  const _UpdatingBanner({required this.manager, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Updating...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.blue.shade100,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyToRestartBanner extends StatelessWidget {
  final UpdateManager manager;
  final VoidCallback onRestart;

  const _ReadyToRestartBanner({required this.manager, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Update Ready',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.green.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Restart the app to complete the update',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: onRestart,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Quit & Restart'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final UpdateManager manager;
  final String error;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _ErrorBanner({
    required this.manager,
    required this.error,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Update Failed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  error,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
