import type { Ditto } from '@dittolive/ditto';

export interface Task { _id: string; title: string; done: boolean }
export const TASK_QUERY = 'SELECT * FROM tasks';

export function decodeTask(value: unknown): Task {
  if (typeof value !== 'object' || value === null) throw new Error('Invalid task');
  const task = value as Record<string, unknown>;
  if (typeof task._id !== 'string' || typeof task.title !== 'string' || typeof task.done !== 'boolean') {
    throw new Error('Invalid task fields');
  }
  return { _id: task._id, title: task.title, done: task.done };
}

export async function saveTask(ditto: Ditto, task: Task) {
  return ditto.store.execute(
    'INSERT INTO tasks DOCUMENTS (:task) ON ID CONFLICT DO UPDATE', { task: { ...task } },
  );
}

export async function setTaskDone(ditto: Ditto, id: string, done: boolean) {
  return ditto.store.execute('UPDATE tasks SET done = :done WHERE _id = :id', { id, done });
}

export async function deleteTask(ditto: Ditto, id: string) {
  return ditto.store.execute('DELETE FROM tasks WHERE _id = :id', { id });
}
