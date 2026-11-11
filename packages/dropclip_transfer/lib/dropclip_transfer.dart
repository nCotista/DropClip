library dropclip_transfer;

export 'src/resumable_checkpoint_store.dart';
export 'src/streaming_file_engine.dart';

/// Transfer item state definition
enum TransferState {
  pending,
  inProgress,
  verifying,
  complete,
  failed,
  cancelled,
}

/// Progress model for file transfer tracking
class TransferProgress {
  final String transferId;
  final String itemId;
  final int bytesTransferred;
  final int totalBytes;

  const TransferProgress({
    required this.transferId,
    required this.itemId,
    required this.bytesTransferred,
    required this.totalBytes,
  });

  double get fraction => totalBytes == 0 ? 0.0 : bytesTransferred / totalBytes;
  double get percentage => fraction * 100.0;
}
