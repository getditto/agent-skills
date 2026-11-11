import { Ditto, DittoConfig, init, type InitOptions } from '@dittolive/ditto';

export type Connection =
  | { mode: 'smallPeersOnly'; offlineLicense: string; privateKey?: string }
  | { mode: 'server'; url: string; provider: string; getToken: () => Promise<string> };

export interface RuntimeOptions {
  databaseID: string;
  persistenceDirectory?: string;
  connection: Connection;
  initOptions?: InitOptions;
  onAuthError: (error: unknown) => void;
}

/** One application/account owner, created outside React render. */
export function createRuntime(options: RuntimeOptions) {
  let pending: Promise<Ditto> | undefined;
  let closing: Promise<void> | undefined;
  let closed = false;

  async function open() {
    await init(options.initOptions);
    const connection = options.connection;
    const connect = connection.mode === 'server'
      ? { mode: 'server' as const, url: connection.url }
      : { mode: 'smallPeersOnly' as const, privateKey: connection.privateKey };
    const ditto = await Ditto.open(new DittoConfig(
      options.databaseID, connect, options.persistenceDirectory,
    ));
    try {
      if (connection.mode === 'smallPeersOnly') {
        ditto.setOfflineOnlyLicenseToken(connection.offlineLicense);
      } else {
        await ditto.auth.setExpirationHandler(async (instance) => {
          if (closed) return;
          try {
            const token = await connection.getToken();
            if (closed) return;
            const result = await instance.auth.login(token, connection.provider);
            if (result.error) options.onAuthError(result.error);
          } catch (error) {
            options.onAuthError(error);
          }
        });
      }
      if (closed) throw new Error('Ditto runtime was closed during startup');
      ditto.sync.start();
      return ditto;
    } catch (error) {
      await ditto.close();
      throw error;
    }
  }

  return {
    start(): Promise<Ditto> {
      if (closed) return Promise.reject(new Error('Ditto runtime is closed'));
      if (!pending) {
        pending = open().catch((error: unknown) => {
          pending = undefined; // A deliberate retry can recover from startup failure.
          throw error;
        });
      }
      return pending;
    },
    close(): Promise<void> {
      if (closing) return closing;
      closed = true;
      closing = (async () => {
        // The owner first unmounts consumers and awaits its outstanding writes.
        const ditto = await pending?.catch(() => undefined);
        if (ditto && !ditto.isClosed) {
          ditto.sync.stop();
          await ditto.close();
        }
      })();
      return closing;
    },
  };
}

export type DittoRuntime = ReturnType<typeof createRuntime>;
