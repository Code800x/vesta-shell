.pragma library

function normalizedPath(path) {
    let value = String(path || "");
    if (value.startsWith("file://"))
        value = decodeURIComponent(value.substring(7));
    return value.replace(/\/+$/, "");
}

function cachedPathFor(paths, item) {
    if (!item || !item.id)
        return "";
    return String(paths[item.id] || "");
}

function isItemActive(paths, item, activePath) {
    const cached = cachedPathFor(paths, item);
    return cached.length > 0 &&
        normalizedPath(cached) === normalizedPath(activePath);
}

function withCachedPath(paths, id, path) {
    const updated = Object.assign({}, paths);
    if (path && String(path).length > 0)
        updated[id] = String(path);
    else
        delete updated[id];
    return updated;
}
