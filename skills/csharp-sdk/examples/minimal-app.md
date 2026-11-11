# Minimal C# app

This is a copy of `MinimalApp/Program.cs` in the fixture.
The program opens an isolated offline store, subscribes, observes, writes and waits
for the actual observer result before cancelling and shutting down.

## Run

Create a .NET 10 console project and add NuGet package `Ditto` at **5.2.0**.
Replace its Program.cs with the program below. Set `DITTO_OFFLINE_LICENSE`; set
`DITTO_DATABASE_ID` too if the license is database-bound. No server is contacted.
The directory is temporary but not automatically deleted; use a persistent application
data directory for a real application.

## Program

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using DittoSDK;

internal static class Program
{
    public static async Task Main()
    {
        var license = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")
            ?? throw new InvalidOperationException("Set DITTO_OFFLINE_LICENSE.");
        var id = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID")
            ?? "e807f150-cb5d-4aa5-bcef-cc90e8521b91";
        var path = Path.Combine(Path.GetTempPath(), "ditto-minimal-" + Guid.NewGuid());
        using var ditto = await Ditto.OpenAsync(new DittoConfig(id,
            new DittoConfigConnect.SmallPeersOnly(), path));
        ditto.SetOfflineOnlyLicenseToken(license);
        using var subscription = ditto.Sync.RegisterSubscription("SELECT * FROM cars");
        var observed = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var observer = ditto.Store.RegisterObserver("SELECT * FROM cars", result => {
            using (result)
            {
                try
                {
                    if (result.Items.Count > 0)
                        observed.TrySetResult((string)result.Items[0].Value["make"]);
                }
                catch (Exception error) { observed.TrySetException(error); }
            }
        });
        try
        {
            // LAN only keeps this console example independent of Bluetooth permissions.
            ditto.UpdateTransportConfig(config => {
                config.PeerToPeer.BluetoothLE.Enabled = false;
                config.PeerToPeer.Awdl.Enabled = false;
            });
            ditto.Sync.Start();
            using (await ditto.Store.ExecuteAsync("INSERT INTO cars DOCUMENTS (:car)",
                new Dictionary<string, object> { ["car"] = new Dictionary<string, object> {
                    ["_id"] = "car1", ["make"] = "Toyota" } })) { }
            var make = await observed.Task.WaitAsync(TimeSpan.FromSeconds(15));
            if (make != "Toyota") throw new InvalidOperationException("Observer returned the wrong car.");
            Console.WriteLine("observer: " + make);
            Console.WriteLine("SDK version: " + Ditto.Version);
        }
        finally
        {
            observer.Cancel();
            subscription.Cancel();
            ditto.Sync.Stop();
        }
    }
}
```

## Expected output

```text
observer: Toyota
SDK version: 5.2.0
```

The SDK version string may include platform/build information. The runner asserts
the resolved version and the observed value, independently of the process exit code.
