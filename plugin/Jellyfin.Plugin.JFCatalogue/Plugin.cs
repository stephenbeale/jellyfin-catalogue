using System.Globalization;
using System.Security.Cryptography;
using Jellyfin.Plugin.JFCatalogue.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.JFCatalogue;

/// <summary>
/// JF Catalogue: an offline, installable catalogue of the library, served by Jellyfin itself.
/// </summary>
public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    /// <summary>The plugin id. Never change it: Jellyfin and plugin repositories key on it.</summary>
    public const string PluginId = "b46eac48-82aa-4990-b6d3-cb1e32170ead";

    /// <summary>
    /// Initializes a new instance of the <see cref="Plugin"/> class.
    /// </summary>
    /// <param name="applicationPaths">Application paths.</param>
    /// <param name="xmlSerializer">XML serializer.</param>
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
        if (string.IsNullOrWhiteSpace(Configuration.ShareKey))
        {
            Configuration.ShareKey = NewShareKey();
            SaveConfiguration();
        }
    }

    /// <summary>Gets the running plugin instance.</summary>
    public static Plugin? Instance { get; private set; }

    /// <inheritdoc />
    public override string Name => "JF Catalogue";

    /// <inheritdoc />
    public override Guid Id => Guid.Parse(PluginId);

    /// <inheritdoc />
    public override string Description =>
        "Offline, searchable catalogue of your library for your phone: check what you already own while out shopping.";

    /// <summary>Creates a random, URL-safe share key (128 bits).</summary>
    /// <returns>A 32-character lowercase hex string.</returns>
    public static string NewShareKey() =>
        Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLower(CultureInfo.InvariantCulture);

    /// <inheritdoc />
    public IEnumerable<PluginPageInfo> GetPages()
    {
        yield return new PluginPageInfo
        {
            Name = Name,
            EmbeddedResourcePath = GetType().Namespace + ".Configuration.configPage.html",
        };
    }
}
