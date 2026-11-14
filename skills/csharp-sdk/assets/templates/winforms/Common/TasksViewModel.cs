// C# 7.3 copy of assets/common for the WinForms starter, which also builds on .NET
// Framework. Keep its public API identical to the modern copy: the same starter tests
// run against both. Everything else uses the modern, nullable-annotated sources.
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Threading.Tasks;

namespace DittoTasks
{
    public sealed class TasksViewModel : INotifyPropertyChanged
    {
        private readonly TaskStore store;
        private readonly Action<Action> dispatch;
        private bool closed;
        private string status = "Opening store...";
        public event PropertyChangedEventHandler PropertyChanged;
        public ObservableCollection<TaskItem> Items { get; } = new ObservableCollection<TaskItem>();
        public string Status { get { return status; } private set { status = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Status))); } }

        // The host supplies its dispatcher, which must throw when it cannot accept work.
        // SDK callbacks never mutate UI collections directly: TaskStore raises Changed inside
        // dispatched work and waits for it before accepting the next observer result.
        public TasksViewModel(Action<Action> dispatch)
        {
            if (dispatch == null) throw new ArgumentNullException(nameof(dispatch));
            this.dispatch = dispatch;
            store = new TaskStore(dispatch);
            store.Changed += Replace;
            store.Failed += message => dispatch(() => { if (!closed) Status = message; });
        }

        private void Replace(IReadOnlyList<TaskItem> rows)
        {
            if (closed) return;
            TaskList.Apply(Items, rows);
            Status = rows.Count + " task(s)";
        }

        public Task StartAsync(string path, Func<Task<bool>> permissions = null, Func<Task<string>> fetchToken = null)
        {
            return RunAsync(() => {
                var settings = Settings.Load();
                return store.StartAsync(settings, settings.PersistenceDirectory ?? Settings.StorePath(path, settings), permissions, fetchToken);
            });
        }

        public Task SaveAsync(string title, TaskItem selected = null)
        {
            if (selected != null) return RunAsync(() => store.RenameAsync(selected.Id, title));
            return RunAsync(() => store.CreateAsync(new TaskItem {
                Id = Guid.NewGuid().ToString(), Title = title, Done = false }));
        }

        public Task ToggleAsync(TaskItem item)
        {
            return item == null ? Task.CompletedTask : RunAsync(() => store.SetDoneAsync(item.Id, !item.Done));
        }

        public Task DeleteAsync(TaskItem item)
        {
            return item == null ? Task.CompletedTask : RunAsync(() => store.DeleteAsync(item.Id));
        }

        private async Task RunAsync(Func<Task> operation)
        {
            try { await operation(); }
            catch (Exception error)
            {
                // UI handlers are async void: nothing may escape, even after the dispatcher stops.
                try { dispatch(() => { if (!closed) Status = error.GetType().Name + ": " + error.Message; }); }
                catch (Exception dispatchError) { System.Diagnostics.Trace.TraceError("DittoTasks: " + error + "; status update failed: " + dispatchError); }
            }
        }

        public async Task StopAsync()
        {
            closed = true;
            await store.StopAsync();
        }
    }

    // Applies an observed snapshot to a bound collection by document ID. Existing rows are
    // updated in place and only real inserts, moves and removals raise collection events,
    // so a UI list keeps its selection. Never Clear() and re-add: that resets selection.
    public static class TaskList
    {
        public static void Apply(ObservableCollection<TaskItem> items, IReadOnlyList<TaskItem> rows)
        {
            if (items == null) throw new ArgumentNullException(nameof(items));
            if (rows == null) throw new ArgumentNullException(nameof(rows));
            var wanted = new HashSet<string>();
            foreach (var row in rows) wanted.Add(row.Id);
            for (var i = items.Count - 1; i >= 0; i--)
                if (!wanted.Contains(items[i].Id)) items.RemoveAt(i);
            for (var i = 0; i < rows.Count; i++)
            {
                var row = rows[i];
                var existing = IndexOf(items, row.Id, i);
                if (existing < 0) { items.Insert(i, row); continue; }
                if (existing != i) items.Move(existing, i);
                items[i].Title = row.Title;
                items[i].Done = row.Done;
            }
        }

        private static int IndexOf(ObservableCollection<TaskItem> items, string id, int start)
        {
            for (var i = start; i < items.Count; i++)
                if (items[i].Id == id) return i;
            return -1;
        }
    }
}
