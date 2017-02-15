var styleTag = document.createElement("style")
styleTag.textContent = "mark { padding: 0; background: orange; }; mark.current { background: yellow !important };"
document.head.appendChild(styleTag)
var $results, $content, currentIndex = 0
$(function() {
	$content = $("body")
})
function jumpTo() {
	if ($results.length) {
		var position, $current = $results.eq(currentIndex)
		$results.removeClass("current")
		if ($current.length) {
			$current.addClass("current")
			position = $current.offset().top - 50
			window.scrollTo(0, position)
		}
	}
}
function cycleMatch(offset) {
	if ($results.length) {
		currentIndex += offset
		if (currentIndex < 0) {
			currentIndex = $results.length - 1
		}
		if (currentIndex > $results.length - 1) {
			currentIndex = 0
		}
		jumpTo()
	}
}
function doSearch(term, options = {accuracy: "exactly"}, ) {
	options["done"] = function(cnt) { 
		resultCount = cnt 
		$results = $content.find("mark")
		currentIndex = 0
		jumpTo()
	}
	$content.unmark( {
		done: function() {
			$content.mark(term, options)
		}
	})
	return resultCount
}
