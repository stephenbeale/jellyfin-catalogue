using Jellyfin.Plugin.JFCatalogue.Catalogue;
using MediaBrowser.Model.Tasks;

namespace Jellyfin.Plugin.JFCatalogue;

/// <summary>
/// "Rebuild JF Catalogue" in Dashboard > Scheduled Tasks. Runs daily by default;
/// users can change the schedule there. A failure shows up in that list and the log.
/// </summary>
public class RebuildCatalogueTask : IScheduledTask
{
    private readonly CatalogueStore _store;

    /// <summary>
    /// Initializes a new instance of the <see cref="RebuildCatalogueTask"/> class.
    /// </summary>
    /// <param name="store">Catalogue store.</param>
    public RebuildCatalogueTask(CatalogueStore store)
    {
        _store = store;
    }

    /// <inheritdoc />
    public string Name => "Rebuild JF Catalogue";

    /// <inheritdoc />
    public string Key => "JFCatalogueRebuild";

    /// <inheritdoc />
    public string Description => "Updates the offline catalogue that JF Catalogue serves to phones.";

    /// <inheritdoc />
    public string Category => "JF Catalogue";

    /// <inheritdoc />
    public async Task ExecuteAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        progress.Report(0);
        await _store.RebuildAsync(cancellationToken).ConfigureAwait(false);
        progress.Report(100);
    }

    /// <inheritdoc />
    public IEnumerable<TaskTriggerInfo> GetDefaultTriggers()
    {
        yield return new TaskTriggerInfo
        {
            Type = TaskTriggerInfoType.DailyTrigger,
            TimeOfDayTicks = TimeSpan.FromHours(4).Ticks,
        };
    }
}
