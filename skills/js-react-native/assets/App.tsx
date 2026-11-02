import { useState } from 'react';
import { Button, Linking, StatusBar, Text } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { createRuntime } from './runtime';
import { DittoProvider } from './DittoProvider';
import { TasksScreen } from './TasksScreen';
import { requestMeshPermissions } from './permissions';
import config from '../config.local.json';

// Configuration is application-owned. This demonstration uses an offline license.
// For production server auth use getToken + provider in RuntimeOptions.
const runtime = createRuntime({
  databaseID: config.databaseID,
  persistenceDirectory: 'ditto-tasks',
  connection: { mode: 'smallPeersOnly', offlineLicense: config.offlineLicense },
  onAuthError: () => {},
});

export default function App() {
  const [ready, setReady] = useState(false);
  const [blocked, setBlocked] = useState(false);
  const [message, setMessage] = useState<string>();
  const [attempt, setAttempt] = useState(0);
  async function enable() {
    try {
      const permission = await requestMeshPermissions();
      setBlocked(permission.blocked);
      setReady(permission.granted);
      if (!permission.granted) setMessage('Allow nearby devices to enable mesh sync.');
    } catch { setMessage('Could not request permissions. Please try again.'); }
  }
  return <SafeAreaProvider><SafeAreaView style={{ flex: 1, backgroundColor: '#fff' }}>
    <StatusBar barStyle="dark-content" />
    {!ready ? <>
      <Text>Sync tasks with nearby devices using Bluetooth and local Wi-Fi.</Text>
      {message && <Text accessibilityRole="alert">{message}</Text>}
      <Button title="Enable nearby sync" onPress={() => void enable()} />
      {blocked && <Button title="Open settings" onPress={() => void Linking.openSettings()} />}
    </> : <DittoProvider key={attempt} runtime={runtime} loading={<Text>Opening database…</Text>}
      failure={() => <><Text accessibilityRole="alert">Database could not open. Check configuration.</Text>
        <Button title="Retry" onPress={() => setAttempt(attempt + 1)} /></>}>
      <TasksScreen />
    </DittoProvider>}
  </SafeAreaView></SafeAreaProvider>;
}
