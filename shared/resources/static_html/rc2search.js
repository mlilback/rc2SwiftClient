$(function() {
	  var styleTag = document.createElement("style")
	  styleTag.textContent = "mark { padding: 0; background: yellow; };"
	  document.head.appendChild(styleTag)
	  styleTag = document.createElement("style")
	  styleTag.textContent = " mark.current { background: orange !important };"
	  document.head.appendChild(styleTag)
  })
var $results, $content, currentIndex = 0
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
function clearSearch() {
	$("body").unmark()
}

function doSearch(binaryStr) {
	var decodedStr = window.atob(binaryStr)
	var json = JSON.parse(decodedStr)
	var term = json["term"]
	var options = json["options"]
	$content = $("body")
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
