// C# 7.3 copy of assets/common for the WinForms starter, which also builds on .NET
// Framework. Keep its public API identical to the modern copy: the same starter tests
// run against both. Everything else uses the modern, nullable-annotated sources.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text.Json;

namespace DittoTasks
{
    public sealed class Settings
    {
        // Application-prefixed so these never collide with variables Ditto's native core reads.
        private const string Prefix = "DITTOTASKS_";

        public string DatabaseId { get; set; }
        public string OfflineLicense { get; set; }
        public string Url { get; set; }
        public string Token { get; set; }
        // Empty selects Ditto's Development (playground) provider; set a provider name for production.
        public string AuthProvider { get; set; }
        public bool EnablePeerToPeerRadios { get; set; }
        // Optional store location override (for example, test isolation). Null uses the host's path.
        public string PersistenceDirectory { get; set; }
        // Optional direct TCP sync. TcpListenPort 0 means off; TcpListenAddress defaults to
        // 127.0.0.1 (use 0.0.0.0 to accept other machines); TcpConnect is "host:port[,host:port]".
        public int TcpListenPort { get; set; }
        public string TcpListenAddress { get; set; }
        public string TcpConnect { get; set; }

        public IReadOnlyList<string> TcpServers()
        {
            if (string.IsNullOrWhiteSpace(TcpConnect)) return new string[0];
            var servers = new List<string>();
            foreach (var part in TcpConnect.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
                if (part.Trim().Length > 0) servers.Add(part.Trim());
            return servers;
        }

        public static Settings Load()
        {
            // appsettings.json is embedded when present, otherwise appsettings.example.json, so a
            // fresh clone builds; environment variables can then supply the values.
            Settings settings = null;
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DittoTasks.appsettings.json"))
                if (stream != null)
                    using (var reader = new StreamReader(stream))
                        settings = JsonSerializer.Deserialize<Settings>(reader.ReadToEnd());
            settings = settings ?? new Settings();
            settings.DatabaseId = Override("DATABASE_ID", settings.DatabaseId);
            settings.OfflineLicense = Override("OFFLINE_LICENSE", settings.OfflineLicense);
            settings.Url = Override("URL", settings.Url);
            settings.Token = Override("TOKEN", settings.Token);
            settings.AuthProvider = Override("AUTH_PROVIDER", settings.AuthProvider);
            settings.PersistenceDirectory = Override("PERSISTENCE_DIRECTORY", settings.PersistenceDirectory);
            settings.TcpListenAddress = Override("TCP_LISTEN_ADDRESS", settings.TcpListenAddress);
            settings.TcpConnect = Override("TCP_CONNECT", settings.TcpConnect);
            var port = Override("TCP_LISTEN_PORT", null);
            if (port != null)
            {
                int parsed;
                settings.TcpListenPort = int.TryParse(port, out parsed) ? parsed : -1;
            }
            // The token is checked in TaskStore.StartAsync, which knows whether one is fetched at runtime.
            settings.Validate(requireToken: false);
            return settings;
        }

        // One store per database ID: Ditto treats a reused store's data as new and syncs it,
        // so switching DatabaseId (for example, development to production) must not reuse it.
        public static string StorePath(string baseDirectory, Settings settings)
        {
            if (settings == null) throw new ArgumentNullException(nameof(settings));
            if (settings.DatabaseId == null) throw new InvalidOperationException("DatabaseId is not set.");
            return Path.Combine(baseDirectory, settings.DatabaseId);
        }

        private static string Override(string name, string value)
        {
            var configured = Environment.GetEnvironmentVariable(Prefix + name);
            return string.IsNullOrEmpty(configured) ? value : configured;
        }

        public void Validate(bool requireToken = true)
        {
            Guid databaseId;
            if (!Guid.TryParse(DatabaseId, out databaseId))
                throw new InvalidOperationException("Set DatabaseId in appsettings.json or " + Prefix + "DATABASE_ID.");
            if (TcpListenPort < 0 || TcpListenPort > ushort.MaxValue)
                throw new InvalidOperationException("TcpListenPort (" + Prefix + "TCP_LISTEN_PORT) must be 0-65535.");
            foreach (var server in TcpServers())
            {
                var colon = server.LastIndexOf(':');
                ushort serverPort;
                if (colon <= 0 || !ushort.TryParse(server.Substring(colon + 1), out serverPort))
                    throw new InvalidOperationException("TcpConnect (" + Prefix + "TCP_CONNECT) entries must be host:port, got '" + server + "'.");
            }
            if (string.IsNullOrWhiteSpace(Url))
            {
                if (string.IsNullOrWhiteSpace(OfflineLicense))
                    throw new InvalidOperationException("Set OfflineLicense or " + Prefix + "OFFLINE_LICENSE for offline operation.");
            }
            else
            {
                Uri uri;
                if (!Uri.TryCreate(Url, UriKind.Absolute, out uri) || uri.Scheme != "https")
                    throw new InvalidOperationException("Url must be the HTTPS SDK URL from the Ditto Portal.");
                if (requireToken && string.IsNullOrWhiteSpace(Token))
                    throw new InvalidOperationException("Set Token or " + Prefix + "TOKEN, or pass fetchToken, for server authentication.");
            }
        }
    }
}
