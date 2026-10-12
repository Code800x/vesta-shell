.pragma library

// Comandos do backend. Não executa processos nem mantém estado.
function providers(scriptPath, purity, live) {
    var command = ["python3", scriptPath, "providers"];
    if (!live)
        command.push("--purity", purity);
    return command;
}

function searchStatic(scriptPath, provider, query, category,
                      sorting, resolution, purity, page) {
    return [
        "python3", scriptPath, "search",
        "--provider", provider,
        "--query", query,
        "--categories", category,
        "--sorting", sorting,
        "--resolutions", resolution,
        "--purity", purity,
        "--page", String(page)
    ];
}

function searchLive(scriptPath, provider, query, page) {
    return [
        "python3", scriptPath, "search",
        "--provider", provider,
        "--query", query,
        "--page", String(page)
    ];
}

function processError(output, errors, fallback) {
    var message = String(fallback || "Erro desconhecido.");
    try {
        var data = JSON.parse(String(output || "").trim());
        if (data && data.error)
            return String(data.error);
    } catch (ignored) {
        // Resposta não JSON: consultar stderr abaixo.
    }
    var stderrText = String(errors || "").trim();
    if (stderrText.length > 0) {
        var lines = stderrText.split("\\n");
        return lines[lines.length - 1] || message;
    }
    return message;
}
