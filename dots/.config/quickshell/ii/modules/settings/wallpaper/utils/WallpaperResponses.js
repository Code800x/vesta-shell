.pragma library

// Valida as respostas JSON do backend sem alterar o estado da interface.
function parseResponse(output, exitCode, fallback, stderr) {
    var raw = String(output || "").trim();
    var diagnostics = String(stderr || "").trim();
    var data;
    try {
        data = JSON.parse(raw);
    } catch (error) {
        var reason = diagnostics || (raw.length > 0
            ? "Resposta inesperada do backend (não é JSON)."
            : "O backend não retornou uma resposta JSON.");
        throw new Error(reason);
    }
    if (!data || exitCode !== 0 || data.ok !== true)
        throw new Error((data && data.error) || diagnostics || fallback || "Falha no backend.");
    return data;
}

function validProviders(providers) {
    if (!Array.isArray(providers))
        throw new Error("Lista de provedores inválida.");
    return providers.filter(function(item) {
        return item &&
            typeof item.code === "string" &&
            typeof item.name === "string";
    });
}

function uniqueWallpapers(items) {
    var incoming = Array.isArray(items) ? items : [];
    var seenIds = {};
    var seenUrls = {};
    return incoming.filter(function(item) {
        if (!item || !item.id || !item.thumb)
            return false;
        var id = String(item.id);
        var url = String(item.url || "");
        if (seenIds[id] || (url && seenUrls[url]))
            return false;
        seenIds[id] = true;
        if (url)
            seenUrls[url] = true;
        return true;
    });
}
