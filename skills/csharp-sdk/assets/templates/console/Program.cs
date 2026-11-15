using System.Diagnostics;
using DittoTasks;

// Trace has no output by default; send the starter's full exception details to stderr.
Trace.Listeners.Add(new ConsoleTraceListener(useErrorStream: true));

await using var store = new TaskStore();
store.Changed += rows =>
{
    foreach (var row in rows) Console.WriteLine($"{row.Id} {row}");
};
store.Failed += Console.Error.WriteLine;
// Ctrl+C ends the loop so the finally block still stops sync and disposes Ditto.
var interrupted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
Console.CancelKeyPress += (_, args) => { args.Cancel = true; interrupted.TrySetResult(); };
try
{
    var settings = Settings.Load();
    await store.StartAsync(settings, settings.PersistenceDirectory ?? Settings.StorePath(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DittoTasks"), settings));
    Console.WriteLine("Commands: add TITLE | edit ID TITLE | done ID | reopen ID | delete ID | quit");
    while (true)
    {
        var read = Task.Run(Console.ReadLine);
        if (await Task.WhenAny(read, interrupted.Task) != read) return 130;
        if (await read is not { } line || line == "quit") break;
        try
        {
            switch (line.Split(' ', 3))
            {
                case ["add", ..] when line.Length > 4:
                    await store.CreateAsync(new TaskItem { Id = Guid.NewGuid().ToString(), Title = line[4..] });
                    break;
                case ["edit", var id, var title]: await store.RenameAsync(id, title); break;
                case ["done", var id, ..]: await store.SetDoneAsync(id, true); break;
                case ["reopen", var id, ..]: await store.SetDoneAsync(id, false); break;
                case ["delete", var id, ..]: await store.DeleteAsync(id); break;
                default: Console.WriteLine("Unknown command."); break;
            }
        }
        catch (Exception error) { Console.Error.WriteLine(error.Message); }
    }
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine(error.Message);
    return 1;
}
finally
{
    await store.StopAsync();
}
