// C# 7.3 copy of assets/common for the WinForms starter, which also builds on .NET
// Framework. Keep its public API identical to the modern copy: the same starter tests
// run against both. Everything else uses the modern, nullable-annotated sources.
using System;
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
