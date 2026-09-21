/** Retries only rejected authentication, sharing renewal across simultaneous requests. */
export class DeviceSessionRetry {
  private renewing: Promise<void> | null = null;
  renew: (() => Promise<void>) | null = null;
  private readToken: () => string | null;

  constructor(readToken: () => string | null) {
    this.readToken = readToken;
  }

  async run<T extends { status: number }>(request: (token: string | null) => Promise<T>): Promise<T> {
    const previous = this.readToken();
    const response = await request(previous);
    if (response.status !== 401 || !this.renew) return response;
    if (this.readToken() === previous) {
      this.renewing ??= Promise.resolve().then(() => this.renew!()).finally(() => {
        this.renewing = null;
      });
      await this.renewing;
    }
    return request(this.readToken());
  }
}
