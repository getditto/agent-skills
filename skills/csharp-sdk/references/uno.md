# Uno Platform

Sources: [Uno templates](https://platform.uno/docs/articles/get-started-dotnet-new.html),
[desktop publishing](https://platform.uno/docs/articles/uno-publishing-desktop.html),
[Ditto compatibility](https://docs.ditto.live/sdk/latest/compatibility/c-sharp).

## Starter

The bundled template uses Uno.Sdk 7.0.5 and net10.0-desktop with the Skia desktop host.
It supports the application shape on Windows x64, macOS ARM64 and compatible Linux
hosts; execution evidence for each OS must be recorded separately.

After configuration:

```bash
dotnet build
dotnet run
```

Use the target runtime identifier when publishing, and run the published executable
on that OS. Windows ARM64/x86 and Intel macOS cannot be inferred from Uno's broader
support table. Do not add browserwasm, browser-wasm, WebAssembly or WebView-hosted
.NET WASM to this application; Ditto has no such native runtime.

## Integration

MainPage binds the shared TasksViewModel. Its dispatcher uses DispatcherQueue.TryEnqueue;
copy native result data before queueing. Retain a Window reference in App and retain
store handles in the application service. The desktop starter handles
[AppWindow.Closing](https://platform.uno/docs/articles/features/app-close-handler.html)
synchronously by cancelling the close request, then queues awaited teardown and closes
once the service has drained its writes. An async Closed event by itself cannot delay
process exit. This desktop close-interception API does not provide mobile suspension
or process-termination guarantees.

The bundled starter is desktop-only. To extend an existing Uno Android/iOS application,
select a native target using the official Uno template options, verify that NuGet chose
the mobile Ditto assembly/native assets, declare required permissions, and use the
platform's main-thread permission and lifecycle APIs. MAUI-specific view APIs are not
Uno APIs. Such mobile extensions require separate build/device evidence; they are not
claimed as executed because the desktop starter builds.
