.pragma library

// Transições puras. Os navegadores mantêm mensagens, aplicação e limpeza.
var IDLE = "idle";
var STARTING = "starting";
var DOWNLOADING = "downloading";
var CANCELLING = "cancelling";
var CANCELLED = "cancelled";
var COMPLETED = "completed";
var FAILED = "failed";

function start() { return STARTING; }
function cancel(current) {
    return current === STARTING || current === DOWNLOADING
        ? CANCELLING : current;
}
function event(current, data) {
    if (current === CANCELLING || current === CANCELLED)
        return current;
    if (!data || typeof data !== "object")
        return current;
    if (data.ok === true && data.path)
        return COMPLETED;
    if (data.ok === false)
        return data.cancelled === true ? CANCELLED : FAILED;
    if (data.event === "started" || data.event === "progress" ||
        data.event === "extracting" || data.event === "cached")
        return DOWNLOADING;
    return current;
}
function exit(current, exitCode, hasResult) {
    if (current === CANCELLING || current === CANCELLED)
        return CANCELLED;
    if (current === COMPLETED || (exitCode === 0 && hasResult === true))
        return COMPLETED;
    return FAILED;
}

// Decisão terminal compartilhada; a interface continua responsável pelos efeitos.
// preserve o comportamento legado: estático considera um evento de sucesso,
// animado exige também saída do processo com código zero.
function terminal(current, exitCode, hasResult, requireZeroExit) {
    var state = exit(current, exitCode, hasResult);
    if (state === CANCELLED)
        return { state: state, cancelled: true, succeeded: false, failed: false };
    var succeeded = requireZeroExit === true
        ? exitCode === 0 && hasResult === true
        : hasResult === true;
    return {
        state: state,
        cancelled: false,
        succeeded: succeeded,
        failed: !succeeded
    };
}

// Ações de interface derivadas da decisão terminal, sem efeitos colaterais.
// O navegador continua responsável por aplicar wallpapers e atualizar o cache.
function finishActions(outcome) {
    return {
        clearCancellation: outcome.cancelled === true,
        clearProgress: outcome.cancelled === true,
        applyResult: outcome.succeeded === true,
        reportFailure: outcome.failed === true
    };
}
