.pragma library

// Interpretador compartilhado de linhas de eventos de download.
// Não altera estados, não executa processos e não aplica wallpapers.
function parseLine(line) {
    var raw = String(line === undefined || line === null ? "" : line).trim();
    if (!raw.length)
        return { empty: true, valid: false, raw: raw, data: null };
    try {
        var data = JSON.parse(raw);
        if (data === null || typeof data !== "object" || Array.isArray(data))
            return { empty: false, valid: false, raw: raw, data: null };
        return { empty: false, valid: true, raw: raw, data: data };
    } catch (ignored) {
        return { empty: false, valid: false, raw: raw, data: null };
    }
}
