using System;
using System.IO;
using System.Threading.Tasks;

namespace DittoTasks
{
    internal static class Program
    {
        public static async Task<int> Main()
        {
            var store = new TaskStore();
            store.Changed += rows => {
                foreach (var row in rows) Console.WriteLine(row.Id + " " + row);
            };
            store.Failed += Console.Error.WriteLine;
            try
            {
                await store.StartAsync(Settings.Load(), Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DittoTasks"));
                Console.WriteLine("Commands: add TITLE | edit ID TITLE | done ID | reopen ID | delete ID | quit");
                string line;
                while ((line = Console.ReadLine()) != null && line != "quit")
                {
                    var parts = line.Split(new[] { ' ' }, 3);
                    try
                    {
                        if (line.StartsWith("add ")) await store.SaveAsync(new TaskItem { Id = Guid.NewGuid().ToString(), Title = line.Substring(4) });
                        else if (parts.Length == 3 && parts[0] == "edit") await store.RenameAsync(parts[1], parts[2]);
                        else if (parts.Length >= 2 && parts[0] == "done") await store.SetDoneAsync(parts[1], true);
                        else if (parts.Length >= 2 && parts[0] == "reopen") await store.SetDoneAsync(parts[1], false);
                        else if (parts.Length >= 2 && parts[0] == "delete") await store.DeleteAsync(parts[1]);
                        else Console.WriteLine("Unknown command.");
                    }
                    catch (Exception error) { Console.Error.WriteLine(error.Message); }
                }
                return 0;
            }
            catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
            finally { await store.StopAsync(); }
        }
    }
}
