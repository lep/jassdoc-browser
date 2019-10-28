function setup(){
    var bar = document.getElementById("search")
    var display = document.getElementById("results")

    function after_timeout(){
	var value = bar.value
	if(! value)
	    return
	
	window.history.replaceState(null, "", "?query="+value)

	var pretty_args = function(args){
	    if(Array.isArray(args) && ! args.length)
		return "nothing"

	    return args.map(function(v){ return v.join(" ") }).join(", ")
	}

	var pretty = function(v){
	    var c = v[0] == "Const" ? "constant" : ""
	    var t = v[1] == "Native" ? "native" : "function"
	    var n = v[2]
	    var a = pretty_args(v[3])
	    var r = v[4]
	    return [c, t, n, "takes", a, "returns", r].join(" ")
	}

	var on_load = function(){
	    var json = JSON.parse(this.responseText)
	    results.innerHTML = ""
	    json.forEach(function(v){
		var div = document.createElement("div")
		var code = tokenize(pretty(v[1]), "code")
		div.setAttribute("class", "result")
		div.appendChild(code)
		display.appendChild(div)
	    })
	}


	var req = new XMLHttpRequest()
	req.addEventListener("load", on_load)
	req.open("GET", "/api?query="+value)
	req.send()


    }

    var timer = false
    function search_onkeydown(){
	if(timer){
	    clearTimeout(timer)
	}
	timer = setTimeout(after_timeout, 300)

    }

    bar.addEventListener('keyup', search_onkeydown)


}
