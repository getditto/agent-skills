using System;
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
        private readonly BindingSource rows = new BindingSource();
        private readonly TasksViewModel model;
        private bool closing;
        private bool canClose;

        public TasksForm()
        {
            Text = "Ditto Tasks";
            Size = new Size(700, 450);
            model = new TasksViewModel(action => {
                if (!closing && IsHandleCreated && !IsDisposed)
                    BeginInvoke(new Action(() => { if (!closing) action(); }));
            });
            model.Items.CollectionChanged += (sender, args) => {
                rows.DataSource = new System.Collections.Generic.List<TaskItem>(model.Items);
            };
            model.PropertyChanged += (sender, args) => status.Text = model.Status;
            list.DataSource = rows;
            list.SelectedIndexChanged += (sender, args) => {
                var selected = list.SelectedItem as TaskItem;
                if (selected != null) title.Text = selected.Title;
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
                await model.StopAsync();
                canClose = true;
                Close();
            };
        }
    }
}
