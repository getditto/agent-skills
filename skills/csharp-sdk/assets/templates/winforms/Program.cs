using System;
using System.Windows.Forms;

namespace DittoTasks
{
    internal static class Program
    {
        [STAThread]
        public static void Main()
        {
//-:cnd:noEmit
#if NET5_0_OR_GREATER
            // Modern .NET: sharp text on high-DPI and mixed-DPI monitors.
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
#endif
//+:cnd:noEmit
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new TasksForm());
        }
    }
}
