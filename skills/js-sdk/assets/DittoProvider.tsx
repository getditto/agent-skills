import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Ditto, DQLQueryArguments } from '@dittolive/ditto';
import type { DittoRuntime } from './runtime';

const Context = createContext<Ditto | null>(null);

/** Borrows the app-owned runtime. Screen unmounts must not close the database. */
export function DittoProvider({ runtime, children, loading, failure }: {
  runtime: DittoRuntime;
  children: ReactNode;
  loading: ReactNode;
  failure: (error: unknown) => ReactNode;
}) {
  const [state, setState] = useState<{
    runtime: DittoRuntime; ditto?: Ditto; error?: unknown; failed?: boolean;
  }>({ runtime });
  useEffect(() => {
    let active = true;
    setState({ runtime });
    runtime.start().then(
      (ditto) => { if (active) setState({ runtime, ditto }); },
      (error: unknown) => { if (active) setState({ runtime, error, failed: true }); },
    );
    return () => { active = false; };
  }, [runtime]);
  if (state.runtime !== runtime) return loading;
  if (state.failed) return failure(state.error);
  if (!state.ditto) return loading;
  return <Context.Provider value={state.ditto}>{children}</Context.Provider>;
}

export function useDitto() {
  const ditto = useContext(Context);
  if (!ditto) throw new Error('useDitto must be inside a ready DittoProvider');
  return ditto;
}

const EMPTY_ARGUMENTS: DQLQueryArguments = {};

/** Memoize arguments at the caller; decode validates remote data at runtime. */
export function useDittoQuery<T>(
  query: string,
  decode: (value: unknown) => T,
  args: DQLQueryArguments = EMPTY_ARGUMENTS,
  sync = true,
) {
  const ditto = useDitto();
  const [state, setState] = useState<{
    ditto: Ditto; query: string; args: DQLQueryArguments; decode: typeof decode;
    rows: T[]; loading: boolean; error?: unknown;
  }>({ ditto, query, args, decode, rows: [], loading: true });
  useEffect(() => {
    let active = true;
    let subscription: ReturnType<Ditto['sync']['registerSubscription']> | undefined;
    let observer: ReturnType<Ditto['store']['registerObserver']> | undefined;
    setState({ ditto, query, args, decode, rows: [], loading: true });
    try {
      if (sync) subscription = ditto.sync.registerSubscription(query, args);
      observer = ditto.store.registerObserver(query, (result) => {
        if (!active) return;
        try {
          const rows = result.items.map((item) => decode(item.value));
          setState({ ditto, query, args, decode, rows, loading: false });
        } catch (error) {
          setState({ ditto, query, args, decode, rows: [], loading: false, error });
        }
      }, args);
    } catch (error) {
      observer?.cancel();
      subscription?.cancel();
      setState({ ditto, query, args, decode, rows: [], loading: false, error });
    }
    return () => {
      active = false;
      observer?.cancel();
      subscription?.cancel();
    };
  }, [ditto, query, args, decode, sync]);
  // Never show rows from a previous user/query for one render before the effect runs.
  if (state.ditto !== ditto || state.query !== query || state.args !== args || state.decode !== decode) {
    return { rows: [] as T[], loading: true, error: undefined };
  }
  return { rows: state.rows, loading: state.loading, error: state.error };
}
