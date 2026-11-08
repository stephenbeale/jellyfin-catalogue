using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.JFCatalogue.Catalogue;

/// <summary>
/// Builds catalogue.json and keeps it in the plugin's data folder.
/// </summary>
public class CatalogueStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        // Keep apostrophes, accents etc. readable instead of \u escapes.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly CatalogueBuilder _builder;
    private readonly ILogger<CatalogueStore> _logger;
    private readonly string _folder;
    private readonly SemaphoreSlim _lock = new(1, 1);

    /// <summary>
    /// Initializes a new instance of the <see cref="CatalogueStore"/> class.
    /// </summary>
    /// <param name="builder">Catalogue builder.</param>
    /// <param name="paths">Application paths.</param>
    /// <param name="logger">Logger.</param>
    public CatalogueStore(CatalogueBuilder builder, IApplicationPaths paths, ILogger<CatalogueStore> logger)
    {
        _builder = builder;
        _logger = logger;
        _folder = Path.Combine(paths.DataPath, "jfcatalogue");
    }

    /// <summary>Gets the path of the current catalogue.json.</summary>
    public string CataloguePath => Path.Combine(_folder, "catalogue.json");

    /// <summary>Builds the catalogue and saves it if the library changed.</summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The item counts.</returns>
    /// <exception cref="InvalidOperationException">The library returned nothing at all.</exception>
    public async Task<CatalogueCounts> RebuildAsync(CancellationToken cancellationToken)
    {
        var config = Plugin.Instance?.Configuration
            ?? throw new InvalidOperationException("JF Catalogue plugin is not loaded.");

        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var doc = _builder.Build(config, cancellationToken);
            var counts = new CatalogueCounts(doc.Movies.Count, doc.Tv.Count, doc.Music.Count);
            if (counts.Total == 0)
            {
                // Fail visibly (the scheduled task shows as failed) rather than publish an empty catalogue.
                throw new InvalidOperationException(
                    "The library returned no movies, TV series or albums. Check the libraries and content types selected in JF Catalogue's settings.");
            }

            // Keep the previous timestamp when nothing changed, so "Last updated" means the library changed.
            var previous = TryReadUpdated();
            doc.Updated = previous ?? Now();
            var json = JsonSerializer.Serialize(doc, JsonOptions);
            if (previous is not null && File.Exists(CataloguePath)
                && json == await File.ReadAllTextAsync(CataloguePath, cancellationToken).ConfigureAwait(false))
            {
                _logger.LogInformation("JF Catalogue: no library changes ({Counts})", counts);
                return counts;
            }

            doc.Updated = Now();
            json = JsonSerializer.Serialize(doc, JsonOptions);
            Directory.CreateDirectory(_folder);
            var tmp = CataloguePath + ".tmp";
            await File.WriteAllTextAsync(tmp, json, cancellationToken).ConfigureAwait(false);
            File.Move(tmp, CataloguePath, overwrite: true);
            _logger.LogInformation("JF Catalogue: wrote {Path} ({Counts})", CataloguePath, counts);
            return counts;
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Makes sure catalogue.json exists, building it on first use.</summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task.</returns>
    public async Task EnsureBuiltAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(CataloguePath))
        {
            await RebuildAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    private static string Now() =>
        DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);

    private string? TryReadUpdated()
    {
        try
        {
            if (!File.Exists(CataloguePath))
            {
                return null;
            }

            using var stream = File.OpenRead(CataloguePath);
            using var existing = JsonDocument.Parse(stream);
            return existing.RootElement.TryGetProperty("updated", out var u) ? u.GetString() : null;
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "JF Catalogue: existing catalogue.json is unreadable, replacing it");
            return null;
        }
    }
}

/// <summary>How many items a catalogue holds.</summary>
/// <param name="Movies">Movies.</param>
/// <param name="Tv">TV series.</param>
/// <param name="Music">Music albums.</param>
public sealed record CatalogueCounts(int Movies, int Tv, int Music)
{
    /// <summary>Gets the total number of items.</summary>
    public int Total => Movies + Tv + Music;

    /// <inheritdoc />
    public override string ToString() =>
        string.Create(CultureInfo.InvariantCulture, $"{Movies} movies, {Tv} TV series, {Music} albums");
}
