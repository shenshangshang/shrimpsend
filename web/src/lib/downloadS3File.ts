import { saveReceivedBlob } from '@/lib/receiveFiles';
import { S3TransferService } from '@/lib/services/s3Transfer';
import type { OnTransferProgress } from '@/lib/services/cloudTransfer';

const cloudTransfer = new S3TransferService();

/** Downloads an S3 object and triggers a browser save (no preview / window.open). */
export async function downloadS3FileAsBrowserSave(
  s3Key: string,
  fileName: string,
  onProgress?: OnTransferProgress,
): Promise<void> {
  const result = await cloudTransfer.download(s3Key, onProgress);
  await saveReceivedBlob(result.blob, fileName || 'download');
}
