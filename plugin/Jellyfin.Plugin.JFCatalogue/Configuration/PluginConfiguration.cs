using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.JFCatalogue.Configuration;

/// <summary>
/// Settings shown on the plugin's page in the Jellyfin dashboard.
/// </summary>
public class PluginConfiguration : BasePluginConfiguration
{
    /// <summary>Gets or sets the name shown in the catalogue header and under the home-screen icon.</summary>
    public string Title { get; set; } = "JF Catalogue";

    /// <summary>Gets or sets a value indicating whether movies are included.</summary>
    public bool IncludeMovies { get; set; } = true;

    /// <summary>Gets or sets a value indicating whether TV series are included.</summary>
    public bool IncludeTv { get; set; } = true;

    /// <summary>Gets or sets a value indicating whether music albums are included.</summary>
    public bool IncludeMusic { get; set; } = true;

    /// <summary>Gets or sets the library (collection folder) ids to include. Empty means all libraries.</summary>
    public string[] LibraryIds { get; set; } = [];

    /// <summary>Gets or sets a value indicating whether plot summaries are included.</summary>
    public bool IncludeOverviews { get; set; } = true;

    /// <summary>Gets or sets a value indicating whether actors and directors are included.</summary>
    public bool IncludeCast { get; set; } = true;

    /// <summary>Gets or sets a value indicating whether the catalogue link works at all.</summary>
    public bool SharingEnabled { get; set; } = true;

    /// <summary>
    /// Gets or sets the secret part of the catalogue link (/JFCatalogue/{ShareKey}/).
    /// Anyone with the link can see the catalogue; regenerating it breaks old links.
    /// </summary>
    public string ShareKey { get; set; } = string.Empty;
}
