using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.JFCatalogue.Catalogue;

// Same JSON shape as export-catalogue-api.ps1 writes, so index.html works unchanged.
// Property order here is the order written to catalogue.json.

/// <summary>The whole catalogue.</summary>
public sealed class CatalogueDocument
{
    /// <summary>Gets or sets when the library content last changed (UTC, ISO 8601).</summary>
    [JsonPropertyName("updated")]
    public string Updated { get; set; } = string.Empty;

    /// <summary>Gets or sets the catalogue title.</summary>
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    /// <summary>Gets or sets the movies.</summary>
    [JsonPropertyName("movies")]
    public IReadOnlyList<MovieEntry> Movies { get; set; } = [];

    /// <summary>Gets or sets the TV series.</summary>
    [JsonPropertyName("tv")]
    public IReadOnlyList<SeriesEntry> Tv { get; set; } = [];

    /// <summary>Gets or sets the music albums.</summary>
    [JsonPropertyName("music")]
    public IReadOnlyList<AlbumEntry> Music { get; set; } = [];
}

/// <summary>A movie.</summary>
public sealed record MovieEntry(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("year")] int? Year,
    [property: JsonPropertyName("genres")] IReadOnlyList<string> Genres,
    [property: JsonPropertyName("rating")] double? Rating,
    [property: JsonPropertyName("cert")] string? Cert,
    [property: JsonPropertyName("runtime")] int? Runtime,
    [property: JsonPropertyName("resolution")] string? Resolution,
    [property: JsonPropertyName("actors")] IReadOnlyList<string> Actors,
    [property: JsonPropertyName("director")] string? Director,
    [property: JsonPropertyName("overview")] string? Overview,
    [property: JsonPropertyName("dateAdded")] string? DateAdded);

/// <summary>A TV series.</summary>
public sealed record SeriesEntry(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("year")] int? Year,
    [property: JsonPropertyName("genres")] IReadOnlyList<string> Genres,
    [property: JsonPropertyName("rating")] double? Rating,
    [property: JsonPropertyName("cert")] string? Cert,
    [property: JsonPropertyName("episodes")] int Episodes,
    [property: JsonPropertyName("actors")] IReadOnlyList<string> Actors,
    [property: JsonPropertyName("director")] string? Director,
    [property: JsonPropertyName("overview")] string? Overview,
    [property: JsonPropertyName("dateAdded")] string? DateAdded);

/// <summary>A music album.</summary>
public sealed record AlbumEntry(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("year")] int? Year,
    [property: JsonPropertyName("artist")] string? Artist,
    [property: JsonPropertyName("genres")] IReadOnlyList<string> Genres,
    [property: JsonPropertyName("dateAdded")] string? DateAdded);
