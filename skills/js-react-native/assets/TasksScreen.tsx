import { useState } from 'react';
import 'react-native-get-random-values';
import { v4 as uuid } from 'uuid';
import { Button, FlatList, Text, TextInput, View } from 'react-native';
import { useDitto, useDittoQuery } from './DittoProvider';
import { decodeTask, saveTask, setTaskDone, deleteTask, TASK_QUERY } from './tasks';

export function TasksScreen() {
  const ditto = useDitto();
  const { rows, loading, error } = useDittoQuery(TASK_QUERY, decodeTask);
  const [title, setTitle] = useState('');
  const [busy, setBusy] = useState(false);
  const [writeError, setWriteError] = useState<string>();
  async function write(operation: () => Promise<unknown>) {
    setBusy(true); setWriteError(undefined);
    try { await operation(); } catch { setWriteError('Could not save. Try again.'); }
    finally { setBusy(false); }
  }
  if (loading) return <Text>Loading tasks…</Text>;
  if (error) return <Text accessibilityRole="alert">Could not load tasks.</Text>;
  return <View style={{ flex: 1, padding: 24 }}>
    <Text accessibilityRole="header">Tasks</Text>
    <Text>Saved on this device. Peer sync depends on connectivity.</Text>
    <TextInput accessibilityLabel="Task title" placeholder="Enter a task"
      style={{ borderWidth: 1, borderColor: '#777', borderRadius: 6, padding: 12, marginVertical: 12, color: '#111' }}
      placeholderTextColor="#666" value={title} onChangeText={setTitle} />
    <Button title="Add task" disabled={busy || !title.trim()} onPress={() => void write(async () => {
      await saveTask(ditto, { _id: uuid(), title: title.trim(), done: false });
      setTitle('');
    })} />
    {writeError && <Text accessibilityRole="alert">{writeError}</Text>}
    <FlatList data={rows} keyExtractor={(item) => item._id}
      ListEmptyComponent={<Text>No tasks yet.</Text>}
      renderItem={({ item }) => <View>
        <Text>{item.title}{item.done ? ' — complete' : ''}</Text>
        <Button title={item.done ? 'Reopen' : 'Complete'} disabled={busy}
          onPress={() => void write(() => setTaskDone(ditto, item._id, !item.done))} />
        <Button title="Delete" disabled={busy} onPress={() => void write(() => deleteTask(ditto, item._id))} />
      </View>} />
  </View>;
}
