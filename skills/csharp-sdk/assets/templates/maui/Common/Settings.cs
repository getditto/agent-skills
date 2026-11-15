using System.Reflection;
using System.Text.Json;

namespace DittoTasks;

public sealed class Settings
{
    // Application-prefixed so these never collide with variables Ditto's native core reads.
    private const string Prefix = "DITTOTASKS_";

    public string? DatabaseId { get; set; }
    public string? OfflineLicense { get; set; }
    public string? Url { get; set; }
    public string? Token { get; set; }
    // Empty selects Ditto's Development (playground) provider; set a provider name for production.
    public string? AuthProvider { get; set; }
    public bool EnablePeerToPeerRadios { get; set; }
    // Optional store location override (for example, test isolation). Null uses the host's path.
    public string? PersistenceDirectory { get; set; }
    // Optional direct TCP sync. TcpListenPort 0 means off; TcpListenAddress defaults to
    // 127.0.0.1 (use 0.0.0.0 to accept other machines); TcpConnect is "host:port[,host:port]".
    public int TcpListenPort { get; set; }
    public string? TcpListenAddress { get; set; }
    public string? TcpConnect { get; set; }

    public IReadOnlyList<string> TcpServers() =>
        string.IsNullOrWhiteSpace(TcpConnect)
            ? []
            : TcpConnect.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    public static Settings Load()
    {
        // appsettings.json is embedded when present, otherwise appsettings.example.json, so a
        // fresh clone builds; environment variables can then supply the values.
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DittoTasks.appsettings.json");
        var settings = (stream is null ? null : JsonSerializer.Deserialize<Settings>(stream)) ?? new Settings();
        settings.DatabaseId = Override("DATABASE_ID", settings.DatabaseId);
        settings.OfflineLicense = Override("OFFLINE_LICENSE", settings.OfflineLicense);
        settings.Url = Override("URL", settings.Url);
        settings.Token = Override("TOKEN", settings.Token);
        settings.AuthProvider = Override("AUTH_PROVIDER", settings.AuthProvider);
        settings.PersistenceDirectory = Override("PERSISTENCE_DIRECTORY", settings.PersistenceDirectory);
        settings.TcpListenAddress = Override("TCP_LISTEN_ADDRESS", settings.TcpListenAddress);
        settings.TcpConnect = Override("TCP_CONNECT", settings.TcpConnect);
        if (Override("TCP_LISTEN_PORT", null) is { } port)
            settings.TcpListenPort = int.TryParse(port, out var parsed) ? parsed : -1;
        // The token is checked in TaskStore.StartAsync, which knows whether one is fetched at runtime.
        settings.Validate(requireToken: false);
        return settings;
    }

    // One store per database ID: Ditto treats a reused store's data as new and syncs it,
    // so switching DatabaseId (for example, development to production) must not reuse it.
    public static string StorePath(string baseDirectory, Settings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return Path.Combine(baseDirectory, settings.DatabaseId ?? throw new InvalidOperationException("DatabaseId is not set."));
    }

    private static string? Override(string name, string? value) =>
        Environment.GetEnvironmentVariable(Prefix + name) is { Length: > 0 } configured ? configured : value;

    public void Validate(bool requireToken = true)
    {
        if (!Guid.TryParse(DatabaseId, out _))
            throw new InvalidOperationException($"Set DatabaseId in appsettings.json or {Prefix}DATABASE_ID.");
        if (TcpListenPort is < 0 or > ushort.MaxValue)
            throw new InvalidOperationException($"TcpListenPort ({Prefix}TCP_LISTEN_PORT) must be 0-65535.");
        foreach (var server in TcpServers())
            if (server.LastIndexOf(':') is var colon && (colon <= 0 || !ushort.TryParse(server[(colon + 1)..], out _)))
                throw new InvalidOperationException($"TcpConnect ({Prefix}TCP_CONNECT) entries must be host:port, got '{server}'.");
        if (string.IsNullOrWhiteSpace(Url))
        {
            if (string.IsNullOrWhiteSpace(OfflineLicense))
                throw new InvalidOperationException($"Set OfflineLicense or {Prefix}OFFLINE_LICENSE for offline operation.");
            return;
        }
        if (!Uri.TryCreate(Url, UriKind.Absolute, out var uri) || uri.Scheme != "https")
            throw new InvalidOperationException("Url must be the HTTPS SDK URL from the Ditto Portal.");
        if (requireToken && string.IsNullOrWhiteSpace(Token))
            throw new InvalidOperationException($"Set Token or {Prefix}TOKEN, or pass fetchToken, for server authentication.");
    }
}
