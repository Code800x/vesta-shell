
.pragma library

function normalizedPath(path) {
    var value = String(path || "");

    if (value.indexOf("file://") === 0) {
        value = decodeURIComponent(value.substring(7));
    }

    return value.replace(/\/+$/, "");
}

function cachedPathFor(paths, item) {
    if (!item || !item.id || !paths) {
        return "";
    }

    return String(paths[item.id] || "");
}

function isItemActive(paths, item, activePath) {
    var cached = cachedPathFor(paths, item);

    return cached.length > 0 &&
        normalizedPath(cached) === normalizedPath(activePath);
}

function withCachedPath(paths, id, path) {
    var updated = {};
    var key;

    if (paths) {
        for (key in paths) {
            if (Object.prototype.hasOwnProperty.call(paths, key)) {
                updated[key] = paths[key];
            }
        }
    }

    if (path && String(path).length > 0) {
        updated[id] = String(path);
    } else {
        delete updated[id];
    }

    return updated;
}
