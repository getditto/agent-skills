using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace DittoTasks;

public sealed partial class MainWindow : Window
{
    private readonly TasksViewModel model;
    private bool closing;
    private bool canClose;
    public MainWindow()
    {
        InitializeComponent();
        model = new TasksViewModel(action => Dispatcher.UIThread.Post(action));
        DataContext = model;
        Opened += async (_, _) => await model.StartAsync(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DittoTasks"));
        Closing += async (_, e) => {
            if (canClose) return;
            e.Cancel = true;
            if (closing) return;
            closing = true;
            await model.StopAsync();
            canClose = true;
            Close();
        };
    }
    private async void Add(object sender, RoutedEventArgs e) => await model.SaveAsync(TitleInput.Text ?? "");
    private async void Edit(object sender, RoutedEventArgs e)
    { if (TasksList.SelectedItem is TaskItem item) await model.SaveAsync(TitleInput.Text ?? "", item); }
    private async void Toggle(object sender, RoutedEventArgs e) => await model.ToggleAsync(TasksList.SelectedItem as TaskItem);
    private async void Delete(object sender, RoutedEventArgs e) => await model.DeleteAsync(TasksList.SelectedItem as TaskItem);
    private void SelectTask(object sender, SelectionChangedEventArgs e)
    { if (TasksList.SelectedItem is TaskItem item) TitleInput.Text = item.Title; }
}
