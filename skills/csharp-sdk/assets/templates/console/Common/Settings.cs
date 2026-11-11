using System;
using System.IO;
using System.Reflection;
using System.Text.Json;

namespace DittoTasks
{
    public sealed class Settings
    {
        public string DatabaseId { get; set; }
        public string OfflineLicense { get; set; }
        public string Url { get; set; }
        public string Token { get; set; }
        public bool EnablePeerToPeerRadios { get; set; }

        public static Settings Load()
        {
            Settings settings;
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DittoTasks.appsettings.json"))
            using (var reader = new StreamReader(stream ?? throw new InvalidOperationException("Missing appsettings.json resource.")))
                settings = JsonSerializer.Deserialize<Settings>(reader.ReadToEnd());
            settings.DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? settings.DatabaseId;
            settings.OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE") ?? settings.OfflineLicense;
            settings.Url = Environment.GetEnvironmentVariable("DITTO_URL") ?? settings.Url;
            settings.Token = Environment.GetEnvironmentVariable("DITTO_TOKEN") ?? settings.Token;
            settings.Validate();
            return settings;
        }

        public void Validate()
        {
            Guid databaseId;
            if (!Guid.TryParse(DatabaseId, out databaseId))
                throw new InvalidOperationException("Set DatabaseId in appsettings.json or DITTO_DATABASE_ID.");
            if (string.IsNullOrWhiteSpace(Url))
            {
                if (string.IsNullOrWhiteSpace(OfflineLicense))
                    throw new InvalidOperationException("Set OfflineLicense or DITTO_OFFLINE_LICENSE for offline operation.");
            }
            else
            {
                Uri uri;
                if (!Uri.TryCreate(Url, UriKind.Absolute, out uri) || uri.Scheme != "https")
                    throw new InvalidOperationException("Url must be the HTTPS SDK URL from the Ditto Portal.");
                if (string.IsNullOrWhiteSpace(Token))
                    throw new InvalidOperationException("Set Token or DITTO_TOKEN for server authentication.");
            }
        }
    }
}
