.pragma library

// Estado puro: sem Process, efeitos colaterais ou dependências de QML.
function reset() {
    return { percent: -1, received: 0, total: 0, speed: 0 };
}

function positiveNumber(value) {
    var number = Number(value);
    return isFinite(number) ? Math.max(0, number) : 0;
}

function percent(value) {
    if (value === null || value === undefined || value === "")
        return -1;
    var number = Number(value);
    return isFinite(number) && number >= 0
        ? Math.min(100, number) : -1;
}

function staticStarted(event) {
    var total = positiveNumber(event.total);
    return { percent: total > 0 ? 0 : -1, received: 0, total: total, speed: 0 };
}

function staticProgress(event) {
    return {
        percent: percent(event.percentage),
        received: positiveNumber(event.downloaded),
        total: positiveNumber(event.total),
        speed: 0
    };
}

function liveProgress(event) {
    return {
        percent: percent(event.percent),
        received: positiveNumber(event.received),
        total: positiveNumber(event.total),
        speed: positiveNumber(event.speed)
    };
}
