module deth.filterwatcher;

import std.exception : enforce;

import deth.rpcconnector;
import deth.util.types;

/// HTTP polling-based log watcher.
///
/// Usage:
/// ---
/// LogFilter!BlockNumber filter;
/// filter.address = contractAddress;
/// auto watcher = conn.watchLogs(filter);
/// scope(exit) watcher.stop();
///
/// while (watcher.active)
/// {
///     auto logs = watcher.getChanges();
///     foreach (log; logs) { /* ... */ }
///     Thread.sleep(7.dur!"seconds");
/// }
/// ---
struct LogFilterWatcher
{
    private RPCConnector conn;
    private FilterID filterID;
    private bool _active;

    this(RPCConnector conn, FilterID filterID) @trusted
    {
        this.conn = conn;
        this.filterID = filterID;
        this._active = true;
    }

    /// Returns logs accumulated since the last call.
    Log[] getChanges() @trusted
    {
        enforce(_active, "LogFilterWatcher is not active");
        return conn.getFilterChanges(filterID);
    }

    /// Uninstalls the filter and deactivates the watcher.
    void stop() @safe
    {
        if (_active)
            conn.uninstallFilter(filterID);
        _active = false;
    }

    @property bool active() const @safe nothrow { return _active; }
    @property FilterID filter() const @safe nothrow { return filterID; }
}

/// HTTP polling-based block watcher.
///
/// Usage:
/// ---
/// auto watcher = conn.watchBlocks();
/// scope(exit) watcher.stop();
///
/// while (watcher.active)
/// {
///     auto blockHashes = watcher.getChanges();
///     foreach (hash; blockHashes) { /* ... */ }
///     Thread.sleep(7.dur!"seconds");
/// }
/// ---
struct BlockFilterWatcher
{
    private RPCConnector conn;
    private FilterID filterID;
    private bool _active;

    this(RPCConnector conn, FilterID filterID) @trusted
    {
        this.conn = conn;
        this.filterID = filterID;
        this._active = true;
    }

    /// Returns new block hashes since the last call.
    Hash[] getChanges() @trusted
    {
        enforce(_active, "BlockFilterWatcher is not active");
        return conn.getFilterChangesHashes(filterID);
    }

    /// Uninstalls the filter and deactivates the watcher.
    void stop() @safe
    {
        if (_active)
            conn.uninstallFilter(filterID);
        _active = false;
    }

    @property bool active() const @safe nothrow { return _active; }
    @property FilterID filter() const @safe nothrow { return filterID; }
}

/// HTTP polling-based pending transaction watcher.
///
/// Usage:
/// ---
/// auto watcher = conn.watchPendingTransactions();
/// scope(exit) watcher.stop();
///
/// while (watcher.active)
/// {
///     auto txHashes = watcher.getChanges();
///     foreach (hash; txHashes) { /* ... */ }
///     Thread.sleep(7.dur!"seconds");
/// }
/// ---
struct PendingTxFilterWatcher
{
    private RPCConnector conn;
    private FilterID filterID;
    private bool _active;

    this(RPCConnector conn, FilterID filterID) @trusted
    {
        this.conn = conn;
        this.filterID = filterID;
        this._active = true;
    }

    /// Returns pending transaction hashes since the last call.
    Hash[] getChanges() @trusted
    {
        enforce(_active, "PendingTxFilterWatcher is not active");
        return conn.getFilterChangesHashes(filterID);
    }

    /// Uninstalls the filter and deactivates the watcher.
    void stop() @safe
    {
        if (_active)
            conn.uninstallFilter(filterID);
        _active = false;
    }

    @property bool active() const @safe nothrow { return _active; }
    @property FilterID filter() const @safe nothrow { return filterID; }
}
