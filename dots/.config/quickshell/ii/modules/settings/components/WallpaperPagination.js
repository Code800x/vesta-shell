// Paginação compartilhada dos navegadores de wallpapers.
// -1 representa uma lacuna visual entre páginas.
function visiblePages(page, lastPage, showLastPage) {
    var current = Math.max(1, Math.floor(Number(page) || 1));
    var maximum = Math.max(current, Math.floor(Number(lastPage) || 1));
    var selected = {};
    selected[1] = true;
    for (var number = Math.max(1, current - 1);
         number <= Math.min(maximum, current + 1); number++) {
        selected[number] = true;
    }
    if (showLastPage)
        selected[maximum] = true;
    var numbers = Object.keys(selected).map(function(value) {
        return Number(value);
    }).sort(function(a, b) { return a - b; });
    var display = [];
    for (var i = 0; i < numbers.length; i++) {
        if (i > 0 && numbers[i] - numbers[i - 1] > 1)
            display.push(-1);
        display.push(numbers[i]);
    }
    return display;
}
