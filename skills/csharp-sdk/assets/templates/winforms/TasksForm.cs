using System;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace DittoTasks
{
    public sealed class TasksForm : Form
    {
        private readonly TextBox title = new TextBox { Width = 240 };
        private readonly ListBox list = new ListBox { Dock = DockStyle.Fill };
        private readonly Label status = new Label { Dock = DockStyle.Bottom, AutoSize = true };
        private readonly TasksViewModel model;
        private bool closing;
        private bool canClose;
        // Set while mirroring data changes, so they never overwrite what the user is typing.
        private bool syncing;

        public TasksForm()
        {
            Text = "Ditto Tasks";
            Size = new Size(700, 450);
            // The view model ignores work that arrives after it stops, so always run it.
            model = new TasksViewModel(action => {
                if (!IsHandleCreated || IsDisposed)
                    throw new InvalidOperationException("The form can no longer accept UI work.");
                BeginInvoke(action);
            });
            // Mirror each collection change instead of rebinding the whole list, which would
            // reset the selection and move it to the first row on every observer delivery.
            model.Items.CollectionChanged += (sender, args) => Sync(() => Mirror(args));
            model.PropertyChanged += (sender, args) => status.Text = model.Status;
            list.SelectedIndexChanged += (sender, args) => {
                var selected = list.SelectedItem as TaskItem;
                if (!syncing && selected != null) title.Text = selected.Title;
            };
            var bar = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true };
            bar.Controls.Add(title);
            var add = new Button { Text = "Add" };
            var edit = new Button { Text = "Save edit" };
            var toggle = new Button { Text = "Toggle done" };
            var remove = new Button { Text = "Delete" };
            add.Click += async (s, e) => await model.SaveAsync(title.Text);
            edit.Click += async (s, e) => { if (list.SelectedItem is TaskItem item) await model.SaveAsync(title.Text, item); };
            toggle.Click += async (s, e) => await model.ToggleAsync(list.SelectedItem as TaskItem);
            remove.Click += async (s, e) => await model.DeleteAsync(list.SelectedItem as TaskItem);
            bar.Controls.AddRange(new Control[] { add, edit, toggle, remove });
            Controls.Add(list); Controls.Add(bar); Controls.Add(status);
            Shown += async (s, e) => await model.StartAsync(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DittoTasks"));
            FormClosing += async (s, e) => {
                if (canClose) return;
                e.Cancel = true;
                if (closing) return;
                closing = true;
                try { await model.StopAsync(); }
                catch (Exception error) { System.Diagnostics.Trace.TraceError("Ditto shutdown failed: " + error); }
                finally { canClose = true; Close(); }
            };
        }

        private void Sync(Action change)
        {
            var selected = list.SelectedItem;
            syncing = true;
            list.BeginUpdate();
            try
            {
                change();
                // Keep the user's row selected by identity across inserts, moves and refreshes.
                if (selected != null && list.Items.Contains(selected)) list.SelectedItem = selected;
            }
            finally { list.EndUpdate(); syncing = false; }
        }

        private void Mirror(NotifyCollectionChangedEventArgs args)
        {
            switch (args.Action)
            {
                case NotifyCollectionChangedAction.Add:
                    var added = (TaskItem)args.NewItems[0];
                    added.PropertyChanged += Refresh;
                    list.Items.Insert(args.NewStartingIndex, added);
                    break;
                case NotifyCollectionChangedAction.Remove:
                    ((TaskItem)args.OldItems[0]).PropertyChanged -= Refresh;
                    list.Items.RemoveAt(args.OldStartingIndex);
                    break;
                case NotifyCollectionChangedAction.Move:
                    var moved = list.Items[args.OldStartingIndex];
                    list.Items.RemoveAt(args.OldStartingIndex);
                    list.Items.Insert(args.NewStartingIndex, moved);
                    break;
                default:
                    foreach (TaskItem item in list.Items) item.PropertyChanged -= Refresh;
                    list.Items.Clear();
                    foreach (var item in model.Items) { item.PropertyChanged += Refresh; list.Items.Add(item); }
                    break;
            }
        }

        // A row's text comes from ToString, so re-set it in place when its fields change.
        private void Refresh(object sender, PropertyChangedEventArgs args)
        {
            if (args.PropertyName != nameof(TaskItem.Display)) return;
            var index = list.Items.IndexOf(sender);
            if (index >= 0) Sync(() => list.Items[index] = sender);
        }
    }
}
