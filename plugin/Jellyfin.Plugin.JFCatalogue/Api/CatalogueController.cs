using System.Globalization;
using System.Net.Mime;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Jellyfin.Plugin.JFCatalogue.Catalogue;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;

namespace Jellyfin.Plugin.JFCatalogue.Api;

/// <summary>
/// Serves the catalogue web app at /JFCatalogue/{shareKey}/ and an admin-only rebuild endpoint.
/// </summary>
/// <remarks>
/// The app pages are anonymous on purpose: a phone opening a bookmarked or installed app has no
/// Jellyfin login. The unguessable share key in the URL is the access control, and the admin can
/// turn the link off or regenerate it on the plugin's settings page.
/// </remarks>
[ApiController]
[Route("JFCatalogue")]
public class CatalogueController : ControllerBase
{
    private const string DefaultTitle = "JF Catalogue";

    private static readonly Dictionary<string, string> WebFiles = new(StringComparer.Ordinal)
    {
        ["sw.js"] = "text/javascript",
        ["manifest.webmanifest"] = "application/manifest+json",
        ["icons/icon.svg"] = "image/svg+xml",
        ["icons/icon-192.png"] = "image/png",
        ["icons/icon-512.png"] = "image/png",
        ["icons/icon-maskable-512.png"] = "image/png",
        ["icons/apple-touch-icon.png"] = "image/png",
    };

    private readonly CatalogueStore _store;

    /// <summary>
    /// Initializes a new instance of the <see cref="CatalogueController"/> class.
    /// </summary>
    /// <param name="store">Catalogue store.</param>
    public CatalogueController(CatalogueStore store)
    {
        _store = store;
    }

    /// <summary>Serves the catalogue page.</summary>
    /// <param name="key">Share key.</param>
    /// <returns>The page.</returns>
    [HttpGet("{key}")]
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
    public IActionResult GetApp([FromRoute] string key)
    {
        if (!IsValidKey(key))
        {
            return NotFound();
        }

        // Relative URLs in the page (catalogue.json, sw.js, icons) need the trailing slash.
        if (!(Request.Path.Value ?? string.Empty).EndsWith('/'))
        {
            return Redirect(Request.PathBase + Request.Path + "/" + Request.QueryString);
        }

        var html = ReadWebText("index.html").Replace(DefaultTitle, HtmlEncoder.Default.Encode(Title()), StringComparison.Ordinal);
        NoCache();
        return Content(html, "text/html; charset=utf-8");
    }

    /// <summary>Serves catalogue.json, the service worker, manifest and icons.</summary>
    /// <param name="key">Share key.</param>
    /// <param name="file">File path within the app.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The file.</returns>
    [HttpGet("{key}/{*file}")]
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
    public async Task<IActionResult> GetFile([FromRoute] string key, [FromRoute] string file, CancellationToken cancellationToken)
    {
        if (!IsValidKey(key))
        {
            return NotFound();
        }

        if (file == "catalogue.json")
        {
            await _store.EnsureBuiltAsync(cancellationToken).ConfigureAwait(false);
            NoCache();
            // ETag + Last-Modified let the service worker's daily revalidation come back as a
            // 304 instead of re-downloading the whole catalogue.
            var info = new FileInfo(_store.CataloguePath);
            var etag = new EntityTagHeaderValue(string.Create(
                CultureInfo.InvariantCulture, $"\"{info.LastWriteTimeUtc.Ticks:x}-{info.Length:x}\""));
            return PhysicalFile(info.FullName, MediaTypeNames.Application.Json, info.LastWriteTimeUtc, etag);
        }

        if (file == "index.html")
        {
            return GetApp(key);
        }

        if (!WebFiles.TryGetValue(file, out var contentType))
        {
            return NotFound();
        }

        if (file == "manifest.webmanifest")
        {
            NoCache();
            var manifest = ReadWebText(file).Replace(
                "\"" + DefaultTitle + "\"",
                JsonSerializer.Serialize(Title()),
                StringComparison.Ordinal);
            return Content(manifest, contentType);
        }

        if (file == "sw.js")
        {
            NoCache();
        }
        else
        {
            Response.Headers.CacheControl = "public, max-age=86400";
        }

        return File(ReadWebBytes(file), contentType);
    }

    /// <summary>Rebuilds the catalogue now. Admins only (used by the settings page).</summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The item counts.</returns>
    [HttpPost("Rebuild")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult<CatalogueCounts>> Rebuild(CancellationToken cancellationToken)
    {
        try
        {
            return await _store.RebuildAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            return Problem(ex.Message, statusCode: StatusCodes.Status422UnprocessableEntity);
        }
    }

    private static string Title()
    {
        var title = Plugin.Instance?.Configuration.Title;
        return string.IsNullOrWhiteSpace(title) ? DefaultTitle : title.Trim();
    }

    private static bool IsValidKey(string key)
    {
        var config = Plugin.Instance?.Configuration;
        if (config is null || !config.SharingEnabled || string.IsNullOrEmpty(config.ShareKey))
        {
            return false;
        }

        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(key),
            Encoding.UTF8.GetBytes(config.ShareKey));
    }

    private static byte[] ReadWebBytes(string file)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("web/" + file)
            ?? throw new FileNotFoundException("Embedded web file missing", file);
        using var buffer = new MemoryStream();
        stream.CopyTo(buffer);
        return buffer.ToArray();
    }

    private static string ReadWebText(string file) => Encoding.UTF8.GetString(ReadWebBytes(file));

    private void NoCache() => Response.Headers.CacheControl = "no-cache";
}
