// Compact, responsive pagination shared by static and live wallpaper browsers.
// -1 is a visual separator; keep only a small number of actionable page links.
function visiblePages(page, lastPage, showLastPage) {
    var maximum = Math.max(1, Math.floor(Number(lastPage) || 1));
    var current = Math.max(1, Math.min(maximum, Math.floor(Number(page) || 1)));
    var selected = {};
    function add(n) { if (n >= 1 && n <= maximum) selected[n] = true; }
    add(1);
    if (current > 7) add(current - 5); // Jump back without stepping one by one.
    add(current - 1);
    add(current);
    add(current + 1);
    if (showLastPage) add(maximum);
    var numbers = Object.keys(selected).map(function(x) { return Number(x); })
        .sort(function(a, b) { return a - b; });
    var result = [];
    for (var i = 0; i < numbers.length; i++) {
        if (i > 0 && numbers[i] - numbers[i - 1] > 1) result.push(-1);
        result.push(numbers[i]);
    }
    return result;
}
