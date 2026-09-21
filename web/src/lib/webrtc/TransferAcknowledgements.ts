/** A send is complete only after the receiver confirms a successful save. */
export class TransferAcknowledgements {
  private pending = new Map<string, {
    resolve: () => void;
    reject: (reason: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();

  wait(fileId: string, timeoutMs = 120_000): Promise<void> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(fileId);
        reject(new Error('Receiver confirmation timed out. Retry to resume the transfer.'));
      }, timeoutMs);
      this.pending.set(fileId, { resolve, reject, timer });
    });
  }

  settle(fileId: string, success: boolean, error?: string): void {
    const entry = this.pending.get(fileId);
    if (!entry) return;
    clearTimeout(entry.timer);
    this.pending.delete(fileId);
    if (success) entry.resolve();
    else entry.reject(new Error(error || 'The receiver could not save the file.'));
  }

  close(): void {
    for (const fileId of this.pending.keys()) {
      this.settle(fileId, false, 'Connection closed before the receiver confirmed the file.');
    }
  }
}
