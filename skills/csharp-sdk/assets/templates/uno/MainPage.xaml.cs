using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DittoTasks;

public sealed partial class MainPage : Page
{
    private readonly TasksViewModel model;
    private bool started;
    public MainPage()
    {
        InitializeComponent();
        model = new TasksViewModel(action => DispatcherQueue.TryEnqueue(() => action()));
        DataContext = model;
        Loaded += async (_, _) => {
            if (started) return;
            started = true;
            await model.StartAsync(System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DittoTasks"));
        };
    }
    private async void Add(object sender, RoutedEventArgs e) => await model.SaveAsync(TitleInput.Text);
    private async void Edit(object sender, RoutedEventArgs e)
    { if (TasksList.SelectedItem is TaskItem item) await model.SaveAsync(TitleInput.Text, item); }
    private async void Toggle(object sender, RoutedEventArgs e) => await model.ToggleAsync(TasksList.SelectedItem as TaskItem);
    private async void Delete(object sender, RoutedEventArgs e) => await model.DeleteAsync(TasksList.SelectedItem as TaskItem);
    private void SelectTask(object sender, SelectionChangedEventArgs e)
    { if (TasksList.SelectedItem is TaskItem item) TitleInput.Text = item.Title; }
    public Task StopAsync() => model.StopAsync();
}
