using System.Globalization;
using Jellyfin.Data.Enums;
using Jellyfin.Plugin.JFCatalogue.Configuration;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.JFCatalogue.Catalogue;

/// <summary>
/// Reads the library through Jellyfin's own library manager and turns it into a catalogue.
/// Same rules as export-catalogue-api.ps1: real files only (no virtual/missing items),
/// sorted by sort name, top 5 actors, first director, overviews cut at 200 characters.
/// </summary>
public class CatalogueBuilder
{
    private const int MaxActors = 5;
    private const int MaxOverview = 200;
    private const long TicksPerMinute = 600_000_000;

    private readonly ILibraryManager _libraryManager;

    /// <summary>
    /// Initializes a new instance of the <see cref="CatalogueBuilder"/> class.
    /// </summary>
    /// <param name="libraryManager">Jellyfin's library manager.</param>
    public CatalogueBuilder(ILibraryManager libraryManager)
    {
        _libraryManager = libraryManager;
    }

    /// <summary>Builds the catalogue for the given settings.</summary>
    /// <param name="config">Plugin settings.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The catalogue, with <see cref="CatalogueDocument.Updated"/> left empty.</returns>
    public CatalogueDocument Build(PluginConfiguration config, CancellationToken cancellationToken)
    {
        var libraries = ParseLibraryIds(config.LibraryIds);

        var movies = new List<MovieEntry>();
        if (config.IncludeMovies)
        {
            foreach (var m in Query(BaseItemKind.Movie, libraries))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var (actors, director) = People(m, config);
                movies.Add(new MovieEntry(
                    m.Name,
                    m.ProductionYear,
                    Genres(m),
                    Rating(m.CommunityRating),
                    Blank(m.OfficialRating),
                    m.RunTimeTicks is long t and > 0 ? (int)Math.Round((double)t / TicksPerMinute) : null,
                    Resolution(m),
                    actors,
                    director,
                    config.IncludeOverviews ? Truncate(m.Overview) : null,
                    DateOnly(m.DateCreated)));
            }
        }

        var tv = new List<SeriesEntry>();
        if (config.IncludeTv)
        {
            var episodeCounts = Query(BaseItemKind.Episode, libraries)
                .OfType<Episode>()
                .Where(e => !e.SeriesId.Equals(Guid.Empty))
                .GroupBy(e => e.SeriesId)
                .ToDictionary(g => g.Key, g => g.Count());

            foreach (var s in Query(BaseItemKind.Series, libraries))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var (actors, director) = People(s, config);
                tv.Add(new SeriesEntry(
                    s.Name,
                    s.ProductionYear,
                    Genres(s),
                    Rating(s.CommunityRating),
                    Blank(s.OfficialRating),
                    episodeCounts.GetValueOrDefault(s.Id),
                    actors,
                    director,
                    config.IncludeOverviews ? Truncate(s.Overview) : null,
                    DateOnly(s.DateCreated)));
            }
        }

        var music = new List<AlbumEntry>();
        if (config.IncludeMusic)
        {
            foreach (var a in Query(BaseItemKind.MusicAlbum, libraries))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var name = a.Name?.Trim();
                if (string.IsNullOrEmpty(name))
                {
                    continue;
                }

                var artist = (a as MusicAlbum)?.AlbumArtists.FirstOrDefault(x => !string.IsNullOrWhiteSpace(x))?.Trim();
                music.Add(new AlbumEntry(name, a.ProductionYear, artist, Genres(a), DateOnly(a.DateCreated)));
            }
        }

        return new CatalogueDocument
        {
            Title = string.IsNullOrWhiteSpace(config.Title) ? null : config.Title.Trim(),
            Movies = movies,
            Tv = tv,
            Music = music,
        };
    }

    private static Guid[] ParseLibraryIds(string[]? ids) =>
        (ids ?? [])
            .Select(id => Guid.TryParse(id, out var g) ? g : Guid.Empty)
            .Where(g => !g.Equals(Guid.Empty))
            .ToArray();

    private static IReadOnlyList<string> Genres(BaseItem item) =>
        (item.Genres ?? [])
            .Where(g => !string.IsNullOrWhiteSpace(g))
            .Select(g => g.Trim())
            .ToArray();

    private static double? Rating(float? value) =>
        value is float r && r > 0 ? Math.Round((double)r, 1) : null; // banker's rounding, as the PowerShell exporter

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static string? Truncate(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        return text.Length <= MaxOverview ? text : text[..MaxOverview].TrimEnd() + "...";
    }

    private static string DateOnly(DateTime value) =>
        (value.Kind == DateTimeKind.Local ? value.ToUniversalTime() : value)
            .ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static string? Resolution(BaseItem item)
    {
        var video = item.GetMediaStreams().FirstOrDefault(s => s.Type == MediaStreamType.Video);
        return video?.Width is int w && video.Height is int h && w > 0 && h > 0
            ? string.Create(CultureInfo.InvariantCulture, $"{w}x{h}")
            : null;
    }

    private IReadOnlyList<BaseItem> Query(BaseItemKind kind, Guid[] libraries)
    {
        var query = new InternalItemsQuery
        {
            IncludeItemTypes = [kind],
            Recursive = true,
            IsVirtualItem = false,
        };
        if (libraries.Length > 0)
        {
            query.AncestorIds = libraries;
        }

        return _libraryManager.GetItemList(query)
            .Where(i => !i.IsVirtualItem)
            .GroupBy(i => i.Id)
            .Select(g => g.First())
            .OrderBy(i => i.SortName ?? i.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private (IReadOnlyList<string> Actors, string? Director) People(BaseItem item, PluginConfiguration config)
    {
        if (!config.IncludeCast)
        {
            return ([], null);
        }

        var people = _libraryManager.GetPeople(item);
        var actors = people
            .Where(p => p.Type == PersonKind.Actor && !string.IsNullOrWhiteSpace(p.Name))
            .Select(p => p.Name)
            .Take(MaxActors)
            .ToArray();
        var director = people.FirstOrDefault(p => p.Type == PersonKind.Director && !string.IsNullOrWhiteSpace(p.Name))?.Name;
        return (actors, director);
    }
}
