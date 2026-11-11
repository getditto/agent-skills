using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Threading.Tasks;

namespace DittoTasks
{
    public sealed class TasksViewModel : INotifyPropertyChanged
    {
        private readonly TaskStore store = new TaskStore();
        private readonly Action<Action> dispatch;
        private bool closed;
        private string status = "Opening store...";
        public event PropertyChangedEventHandler PropertyChanged;
        public ObservableCollection<TaskItem> Items { get; } = new ObservableCollection<TaskItem>();
        public string Status { get { return status; } private set { status = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Status))); } }

        // The host supplies its dispatcher; SDK callbacks never mutate UI collections directly.
        public TasksViewModel(Action<Action> dispatch)
        {
            this.dispatch = dispatch;
            store.Changed += rows => dispatch(() => Replace(rows));
            store.Failed += message => dispatch(() => { if (!closed) Status = message; });
        }

        private void Replace(IReadOnlyList<TaskItem> rows)
        {
            if (closed) return;
            Items.Clear();
            foreach (var item in rows) Items.Add(item);
            Status = rows.Count + " task(s)";
        }

        public Task StartAsync(string path, Func<Task> permissions = null)
        {
            return RunAsync(() => store.StartAsync(Settings.Load(), path, permissions));
        }

        public Task SaveAsync(string title, TaskItem selected = null)
        {
            if (selected != null) return RunAsync(() => store.RenameAsync(selected.Id, title));
            return RunAsync(() => store.SaveAsync(new TaskItem {
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
            catch (Exception error) { dispatch(() => { if (!closed) Status = error.GetType().Name + ": " + error.Message; }); }
        }

        public async Task StopAsync()
        {
            closed = true;
            await store.StopAsync();
        }
    }
}
