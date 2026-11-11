using DittoSDK.Sync;

namespace DittoTasks;

public sealed class MainPage : ContentPage
{
    private readonly TasksViewModel model = new TasksViewModel(action => MainThread.BeginInvokeOnMainThread(action));
    private readonly Entry title = new Entry { Placeholder = "Task title" };
    private readonly CollectionView list = new CollectionView { SelectionMode = SelectionMode.Single };
    private bool started;
    public MainPage()
    {
        Title = "Ditto Tasks";
        BindingContext = model;
        var status = new Label();
        status.SetBinding(Label.TextProperty, nameof(TasksViewModel.Status));
        list.SetBinding(ItemsView.ItemsSourceProperty, nameof(TasksViewModel.Items));
        list.ItemTemplate = new DataTemplate(() => {
            var label = new Label { Padding = new Thickness(8) };
            label.SetBinding(Label.TextProperty, ".");
            return label;
        });
        list.SelectionChanged += (_, _) => { if (list.SelectedItem is TaskItem item) title.Text = item.Title; };
        var add = new Button { Text = "Add" };
        var edit = new Button { Text = "Save edit" };
        var toggle = new Button { Text = "Toggle done" };
        var remove = new Button { Text = "Delete" };
        add.Clicked += async (_, _) => await model.SaveAsync(title.Text);
        edit.Clicked += async (_, _) => { if (list.SelectedItem is TaskItem item) await model.SaveAsync(title.Text, item); };
        toggle.Clicked += async (_, _) => await model.ToggleAsync(list.SelectedItem as TaskItem);
        remove.Clicked += async (_, _) => await model.DeleteAsync(list.SelectedItem as TaskItem);
        var bar = new Grid { ColumnSpacing = 8, RowSpacing = 8,
            ColumnDefinitions = { new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Star) },
            RowDefinitions = { new RowDefinition(GridLength.Auto), new RowDefinition(GridLength.Auto) } };
        bar.Add(add, 0, 0); bar.Add(edit, 1, 0); bar.Add(toggle, 0, 1); bar.Add(remove, 1, 1);
        var grid = new Grid { Padding = 20, RowSpacing = 12,
            RowDefinitions = { new RowDefinition(GridLength.Auto), new RowDefinition(GridLength.Auto),
                new RowDefinition(GridLength.Star), new RowDefinition(GridLength.Auto) } };
        grid.Add(title, 0, 0); grid.Add(bar, 0, 1); grid.Add(list, 0, 2); grid.Add(status, 0, 3);
        Content = grid;
    }
    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (started) return;
        started = true;
        await model.StartAsync(Path.Combine(FileSystem.AppDataDirectory, "tasks"),
            RequestPermissionsAsync);
    }
    private static Task RequestPermissionsAsync()
    {
#if ANDROID || IOS || MACCATALYST
        return MainThread.InvokeOnMainThreadAsync(async () => {
            if (!await DittoSyncPermissions.RequestPermissionsAsync())
                throw new InvalidOperationException("Ditto sync permissions were denied.");
        });
#else
        return Task.CompletedTask;
#endif
    }
    public Task StopAsync() => model.StopAsync();
}
